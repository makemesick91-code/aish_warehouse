-- Milestone 12C rollout: administrative support for seeding the change journal
-- with a baseline for rows that already existed when revision 003 was deployed.
--
-- `20260803000100` starts the journal empty, so a device pulling from cursor 0
-- receives only what has been *touched* since the migration. Master data and
-- open documents that predate it are invisible to a fresh install until someone
-- happens to edit them. This migration adds the machinery to close that gap.
--
-- What it deliberately does NOT do:
--
--   * It does not run a backfill. Creating triggers is cheap; scanning every
--     syncable table under an exclusive-ish workload is not, and a migration
--     that does it at deploy time would hold locks for as long as the largest
--     table takes. The work is driven batch by batch by an operator instead.
--   * It never writes to a business table. No `UPDATE ... SET updated_at =
--     updated_at`, no state transition, no synthetic movement. `server_version`
--     and `updated_at` are read, never assigned, so no client's pending local
--     edit is silently superseded by a rollout step (see the "touch" option
--     rejected in `docs/supabase_12c_remote_handoff.md` §3).
--   * It does not change `20260803000100`. Every object here is additive.
--
-- Idempotency is structural, not procedural. A `(backfill_revision,
-- entity_type, entity_id)` primary key on the marks table means two operators
-- running concurrently, or the same operator running twice, cannot produce two
-- baseline entries for one entity — the second insert loses the race and is
-- counted as skipped. `NOT EXISTS` alone would not survive that.

-- ---------------------------------------------------------------------------
-- 1. Run bookkeeping and the idempotency key
-- ---------------------------------------------------------------------------
create table public.sync_change_journal_backfill_runs (
  run_id uuid primary key,
  backfill_revision varchar(64) not null,
  entity_types text[],
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Resume checkpoint. The pair is the last entity the run *handled*, whether
  -- it was journalled or skipped; a failed entity never advances it.
  last_entity_type varchar(64),
  last_entity_id uuid,
  scanned bigint not null default 0,
  inserted bigint not null default 0,
  skipped bigint not null default 0,
  failed bigint not null default 0,
  completed boolean not null default false
);

alter table public.sync_change_journal_backfill_runs enable row level security;
alter table public.sync_change_journal_backfill_runs force row level security;
revoke all on table public.sync_change_journal_backfill_runs
  from public, anon, authenticated;
grant all on table public.sync_change_journal_backfill_runs to service_role;

-- One row per entity that has ever been given a baseline under a revision.
-- `backfill_revision` rather than `run_id` is what carries uniqueness: a second
-- run started to finish an interrupted first one must see the first one's work.
create table public.sync_change_journal_backfill_marks (
  backfill_revision varchar(64) not null,
  entity_type varchar(64) not null,
  entity_id uuid not null,
  run_id uuid not null references public.sync_change_journal_backfill_runs(run_id),
  operation text not null check (operation in ('upsert', 'tombstone')),
  change_seq bigint,
  created_at timestamptz not null default now(),
  primary key (backfill_revision, entity_type, entity_id)
);

create index idx_backfill_marks_run
  on public.sync_change_journal_backfill_marks (run_id, entity_type, entity_id);

alter table public.sync_change_journal_backfill_marks enable row level security;
alter table public.sync_change_journal_backfill_marks force row level security;
revoke all on table public.sync_change_journal_backfill_marks
  from public, anon, authenticated;
grant all on table public.sync_change_journal_backfill_marks to service_role;

-- ---------------------------------------------------------------------------
-- 2. Scan order
-- ---------------------------------------------------------------------------
-- Fixed and total, so a checkpoint of `(entity_type, entity_id)` is a position
-- in one global sequence and a resumed run cannot revisit a finished type or
-- skip an unstarted one. Masters come first: a device that applies the feed in
-- order then has categories and items before the documents referencing them.
create or replace function app_private.backfill_entity_type_order()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'branch', 'room', 'user', 'category', 'item', 'batch', 'stock_location',
    'stock_balance', 'stock_movement', 'stock_opname', 'purchase_request',
    'delivery_order', 'good_receipt', 'distribution', 'disposal', 'consumption',
    'goods_return'
  ];
$$;

revoke all on function app_private.backfill_entity_type_order()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. The backfill worker
-- ---------------------------------------------------------------------------
-- One call is one transaction, so `max_batches > 1` trades resumability for
-- fewer round trips: a failure rolls the whole call back. The operator script
-- drives it at one batch per call by default and persists the checkpoint from
-- the returned report.
create or replace function app_private.backfill_sync_change_journal(
  p_run_id uuid,
  p_backfill_revision text default 'aish-supabase-003-baseline',
  p_entity_types text[] default null,
  p_batch_size integer default 500,
  p_max_batches integer default 1,
  p_after_entity_type text default null,
  p_after_entity_id uuid default null,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
-- Runs as the owner for the same reason the journal triggers do: the baseline
-- has to be complete regardless of which maintenance role drives it, and the
-- reachable entry point is the guarded wrapper in §4, not this.
security definer
set search_path = ''
as $$
declare
  ordered_types text[];
  type_index integer;
  current_type text;
  source_table text;
  cursor_id uuid;
  batch_started timestamptz;
  -- Scalar targets rather than a `record`. `FOR ... IN EXECUTE` cannot tell a
  -- static analyser what shape a dynamic query returns, so a record variable
  -- reads as "never assigned"; naming the four columns keeps the loop checkable.
  candidate_id uuid;
  candidate_version bigint;
  candidate_deleted timestamptz;
  candidate_updated timestamptz;
  fetched integer;
  batch_scanned integer;
  batch_inserted integer;
  batch_skipped integer;
  batch_failed integer;
  batch_min_seq bigint;
  batch_max_seq bigint;
  new_seq bigint;
  resolved_operation text;
  mark_rows integer;
  stop_batch boolean;
  last_handled uuid;
  batches jsonb := '[]'::jsonb;
  run_completed boolean := false;
  merge_field text;
begin
  if p_run_id is null then
    raise exception using errcode = '22023', message = 'sync_backfill_run_id_required';
  end if;
  if p_backfill_revision is null or length(trim(p_backfill_revision)) = 0 then
    raise exception using errcode = '22023', message = 'sync_backfill_revision_required';
  end if;
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 5000 then
    raise exception using errcode = '22023', message = 'sync_backfill_batch_size_invalid';
  end if;
  if p_max_batches is null or p_max_batches < 1 or p_max_batches > 100 then
    raise exception using errcode = '22023', message = 'sync_backfill_max_batches_invalid';
  end if;

  -- One backfill at a time per database. The marks primary key already makes
  -- duplicates impossible; this makes two operators racing *visible* instead of
  -- letting them interleave checkpoints and each believe they finished.
  if not pg_try_advisory_xact_lock(
    ('x' || substr(md5('aish_sync_change_journal_backfill'), 1, 16))::bit(64)::bigint
  ) then
    raise exception using errcode = '55006', message = 'sync_backfill_run_in_progress';
  end if;

  ordered_types := app_private.backfill_entity_type_order();
  if p_entity_types is not null then
    if array_length(p_entity_types, 1) is null then
      raise exception using errcode = '22023', message = 'sync_backfill_entity_types_empty';
    end if;
    foreach current_type in array p_entity_types loop
      if not (current_type = any(ordered_types)) then
        raise exception using errcode = '22023',
          message = 'sync_backfill_entity_type_unknown';
      end if;
    end loop;
    -- Intersect rather than adopt the caller's ordering, so the checkpoint stays
    -- a position in the canonical sequence.
    select array_agg(entry order by type_position)
      into ordered_types
      from unnest(ordered_types) with ordinality as t(entry, type_position)
      where entry = any(p_entity_types);
  end if;

  if p_after_entity_type is null then
    type_index := 1;
    cursor_id := null;
  else
    select type_position into type_index
      from unnest(ordered_types) with ordinality as t(entry, type_position)
      where entry = p_after_entity_type;
    if type_index is null then
      raise exception using errcode = '22023',
        message = 'sync_backfill_checkpoint_out_of_scope';
    end if;
    cursor_id := p_after_entity_id;
  end if;

  if not p_dry_run then
    insert into public.sync_change_journal_backfill_runs
      (run_id, backfill_revision, entity_types)
    values (p_run_id, p_backfill_revision, p_entity_types)
    on conflict (run_id) do nothing;
    -- A run id is bound to one revision for its whole life; reusing it under a
    -- different revision would make the recorded totals meaningless.
    if exists (
      select 1 from public.sync_change_journal_backfill_runs as run
      where run.run_id = p_run_id and run.backfill_revision <> p_backfill_revision
    ) then
      raise exception using errcode = '22023',
        message = 'sync_backfill_run_revision_mismatch';
    end if;
  end if;

  for batch_index in 1..p_max_batches loop
    if type_index > coalesce(array_length(ordered_types, 1), 0) then
      run_completed := true;
      exit;
    end if;

    current_type := ordered_types[type_index];
    source_table := app_private.pull_table_for_entity_type(current_type);
    if source_table is null then
      raise exception using errcode = '22023',
        message = 'sync_backfill_entity_type_unmapped';
    end if;

    batch_started := clock_timestamp();
    fetched := 0;
    batch_scanned := 0;
    batch_inserted := 0;
    batch_skipped := 0;
    batch_failed := 0;
    batch_min_seq := null;
    batch_max_seq := null;
    stop_batch := false;
    last_handled := cursor_id;

    for candidate_id, candidate_version, candidate_deleted, candidate_updated
      in execute format(
        'select entity.id, entity.server_version, entity.deleted_at, '
        '       entity.server_updated_at '
        '  from public.%I as entity '
        ' where ($1 is null or entity.id > $1) '
        ' order by entity.id '
        ' limit $2', source_table)
      using cursor_id, p_batch_size
    loop
      fetched := fetched + 1;
      if stop_batch then
        -- Drained by the cursor, not handled: leave it for the resumed run.
        continue;
      end if;
      batch_scanned := batch_scanned + 1;
      begin
        -- Already represented in the feed by a runtime write. Nothing to add,
        -- and adding anyway would replay a change the device has seen.
        if exists (
          select 1 from public.sync_change_journal as journal
          where journal.entity_type = current_type
            and journal.entity_id = candidate_id
        ) then
          batch_skipped := batch_skipped + 1;
          last_handled := candidate_id;
          continue;
        end if;

        if exists (
          select 1 from public.sync_change_journal_backfill_marks as mark
          where mark.backfill_revision = p_backfill_revision
            and mark.entity_type = current_type
            and mark.entity_id = candidate_id
        ) then
          batch_skipped := batch_skipped + 1;
          last_handled := candidate_id;
          continue;
        end if;

        resolved_operation := case
          when candidate_deleted is not null then 'tombstone' else 'upsert' end;

        if p_dry_run then
          -- Counted as it *would* be applied. Nothing is written, including the
          -- mark, so a dry run leaves no trace for a later real run to skip.
          batch_inserted := batch_inserted + 1;
          last_handled := candidate_id;
          continue;
        end if;

        insert into public.sync_change_journal_backfill_marks
          (backfill_revision, entity_type, entity_id, run_id, operation)
        values (p_backfill_revision, current_type, candidate_id, p_run_id,
          resolved_operation)
        on conflict (backfill_revision, entity_type, entity_id) do nothing;
        get diagnostics mark_rows = row_count;

        if mark_rows = 0 then
          -- Another run claimed this entity between the check above and here.
          batch_skipped := batch_skipped + 1;
          last_handled := candidate_id;
          continue;
        end if;

        insert into public.sync_change_journal
          (entity_type, entity_id, operation, server_version, changed_at)
        values (current_type, candidate_id, resolved_operation,
          candidate_version,
          coalesce(candidate_updated, now()))
        returning change_seq into new_seq;

        update public.sync_change_journal_backfill_marks as mark
          set change_seq = new_seq
          where mark.backfill_revision = p_backfill_revision
            and mark.entity_type = current_type
            and mark.entity_id = candidate_id;

        -- Baseline field versions. The entity's current `server_version` is the
        -- only honest answer for "when did this column last change" when the
        -- history predates the journal, and it is exactly what a runtime write
        -- would have recorded. `do nothing` on conflict so a version already
        -- observed by a real write — which is strictly better information — is
        -- never overwritten by the baseline.
        foreach merge_field in array app_private.pull_mergeable_fields(current_type) loop
          insert into public.sync_entity_field_versions
            (entity_type, entity_id, field_name, field_version, changed_at)
          values (current_type, candidate_id, merge_field, candidate_version,
            coalesce(candidate_updated, now()))
          on conflict (entity_type, entity_id, field_name) do nothing;
        end loop;

        batch_inserted := batch_inserted + 1;
        batch_min_seq := least(coalesce(batch_min_seq, new_seq), new_seq);
        batch_max_seq := greatest(coalesce(batch_max_seq, new_seq), new_seq);
        last_handled := candidate_id;
      exception when others then
        -- The failing entity is left unhandled and the checkpoint stays on the
        -- last one that succeeded, so a resumed run retries it rather than
        -- stepping over it. The sub-block rollback also removes the mark, so a
        -- failure never leaves a claim behind that would make the entity look
        -- done.
        batch_failed := batch_failed + 1;
        stop_batch := true;
      end;
    end loop;

    cursor_id := last_handled;
    if fetched < p_batch_size and not stop_batch then
      -- This type is exhausted; the next batch starts at the top of the next.
      type_index := type_index + 1;
      cursor_id := null;
      if type_index > coalesce(array_length(ordered_types, 1), 0) then
        run_completed := true;
      end if;
    end if;

    batches := batches || jsonb_build_array(jsonb_build_object(
      'run_id', p_run_id,
      'backfill_revision', p_backfill_revision,
      'entity_type', current_type,
      'dry_run', p_dry_run,
      'scanned', batch_scanned,
      'inserted', batch_inserted,
      'skipped', batch_skipped,
      'failed', batch_failed,
      'next_checkpoint', jsonb_build_object(
        'entity_type', case when run_completed then null
          else ordered_types[least(type_index,
            coalesce(array_length(ordered_types, 1), 1))] end,
        'entity_id', cursor_id),
      'completed', run_completed,
      'duration_ms', round(extract(epoch from (clock_timestamp() - batch_started)) * 1000)::bigint,
      'journal_min_seq', batch_min_seq,
      'journal_max_seq', batch_max_seq));

    if not p_dry_run then
      update public.sync_change_journal_backfill_runs as run
        set updated_at = now(),
            last_entity_type = case when run_completed then run.last_entity_type
              else ordered_types[least(type_index,
                coalesce(array_length(ordered_types, 1), 1))] end,
            last_entity_id = case when run_completed then run.last_entity_id
              else cursor_id end,
            scanned = run.scanned + batch_scanned,
            inserted = run.inserted + batch_inserted,
            skipped = run.skipped + batch_skipped,
            failed = run.failed + batch_failed,
            completed = run_completed
        where run.run_id = p_run_id;
    end if;

    if stop_batch or run_completed then
      exit;
    end if;
  end loop;

  return jsonb_build_object(
    'run_id', p_run_id,
    'backfill_revision', p_backfill_revision,
    'dry_run', p_dry_run,
    'completed', run_completed,
    'batches', batches);
end;
$$;

revoke all on function app_private.backfill_sync_change_journal(
  uuid, text, text[], integer, integer, text, uuid, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Operator entry point
-- ---------------------------------------------------------------------------
-- PostgREST only exposes `public`, so the wrapper is what an operator tool can
-- actually reach. EXECUTE is the real control; the claim check below is the
-- second lock on the same door, so a future migration that grants too widely
-- still fails closed instead of silently opening the backfill to a session
-- token. A request with no JWT claims at all is a direct `psql` connection,
-- which the EXECUTE grant has already restricted to `service_role` and
-- superusers.
create or replace function public.admin_backfill_sync_change_journal(
  run_id uuid,
  backfill_revision text default 'aish-supabase-003-baseline',
  entity_types text[] default null,
  batch_size integer default 500,
  max_batches integer default 1,
  after_entity_type text default null,
  after_entity_id uuid default null,
  dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare claim_role text;
begin
  claim_role := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  if claim_role is not null and claim_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'sync_backfill_forbidden';
  end if;
  return app_private.backfill_sync_change_journal(
    run_id, backfill_revision, entity_types, batch_size, max_batches,
    after_entity_type, after_entity_id, dry_run);
end;
$$;

revoke all on function public.admin_backfill_sync_change_journal(
  uuid, text, text[], integer, integer, text, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.admin_backfill_sync_change_journal(
  uuid, text, text[], integer, integer, text, uuid, boolean) to service_role;

-- ---------------------------------------------------------------------------
-- 5. Coverage report
-- ---------------------------------------------------------------------------
-- Answers the only question that decides whether the rollout may proceed: is
-- there a live entity of a syncable type with no journal entry at all? Counted
-- from the tables themselves rather than from the run totals, so an aborted run
-- or a hand-edited checkpoint cannot make an incomplete backfill look finished.
create or replace function app_private.sync_backfill_coverage(
  p_backfill_revision text default 'aish-supabase-003-baseline'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_entity_type text;
  source_table text;
  total bigint;
  journalled bigint;
  marked bigint;
  missing bigint;
  rows jsonb := '[]'::jsonb;
  missing_total bigint := 0;
begin
  foreach current_entity_type in array app_private.backfill_entity_type_order() loop
    source_table := app_private.pull_table_for_entity_type(current_entity_type);
    execute format('select count(*) from public.%I', source_table) into total;
    execute format(
      'select count(*) from public.%I as entity where exists ('
      '  select 1 from public.sync_change_journal as journal '
      '   where journal.entity_type = $1 and journal.entity_id = entity.id)',
      source_table) using current_entity_type into journalled;
    select count(*) into marked
      from public.sync_change_journal_backfill_marks as mark
      where mark.backfill_revision = p_backfill_revision
        and mark.entity_type = current_entity_type;
    missing := total - journalled;
    missing_total := missing_total + missing;
    rows := rows || jsonb_build_array(jsonb_build_object(
      'entity_type', current_entity_type,
      'rows', total,
      'journalled', journalled,
      'backfill_marks', marked,
      'missing_baseline', missing));
  end loop;

  return jsonb_build_object(
    'backfill_revision', p_backfill_revision,
    'entities', rows,
    'missing_baseline_total', missing_total,
    'complete', missing_total = 0,
    'journal_rows', (select count(*) from public.sync_change_journal),
    'max_change_seq', (select coalesce(max(change_seq), 0)
      from public.sync_change_journal),
    'duplicate_marks', (select count(*) from (
      select 1 from public.sync_change_journal_backfill_marks as mark
      group by mark.entity_type, mark.entity_id
      having count(*) filter (where mark.change_seq is not null) > 1) as duplicates));
end;
$$;

revoke all on function app_private.sync_backfill_coverage(text)
  from public, anon, authenticated;

create or replace function public.admin_sync_backfill_coverage(
  backfill_revision text default 'aish-supabase-003-baseline'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare claim_role text;
begin
  claim_role := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  if claim_role is not null and claim_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'sync_backfill_forbidden';
  end if;
  return app_private.sync_backfill_coverage(backfill_revision);
end;
$$;

revoke all on function public.admin_sync_backfill_coverage(text)
  from public, anon, authenticated;
grant execute on function public.admin_sync_backfill_coverage(text) to service_role;

-- ---------------------------------------------------------------------------
-- 6. Retention planning input
-- ---------------------------------------------------------------------------
-- Read-only. `app_private.prune_sync_change_journal` stays untouched, unbound to
-- any schedule, and is not called from here: the planner's job is to produce a
-- boundary for a human to approve, not to act on one. The lowest active device
-- cursor lives on the devices, not on the server, so the safety window is the
-- product decision this function reports against rather than computes.
create or replace function app_private.sync_journal_retention_plan(
  p_safety_window_days integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  max_seq bigint;
  horizon bigint;
  boundary bigint;
  oldest timestamptz;
  cutoff timestamptz;
  eligible bigint;
begin
  if p_safety_window_days is null or p_safety_window_days < 1 then
    raise exception using errcode = '22023', message = 'sync_invalid_payload';
  end if;
  select coalesce(max(change_seq), 0), min(changed_at)
    into max_seq, oldest from public.sync_change_journal;
  horizon := app_private.pull_commit_horizon();
  cutoff := now() - make_interval(days => p_safety_window_days);
  select coalesce(max(change_seq), 0) into boundary
    from public.sync_change_journal where changed_at < cutoff;
  boundary := least(boundary, horizon);
  select count(*) into eligible
    from public.sync_change_journal where change_seq <= boundary;
  return jsonb_build_object(
    'current_max_cursor', max_seq,
    'commit_horizon', horizon,
    'proposed_keep_through', boundary,
    'rows_eligible', eligible,
    'rows_total', (select count(*) from public.sync_change_journal),
    'oldest_change', oldest,
    'safety_window_days', p_safety_window_days,
    'safety_cutoff_utc', cutoff,
    'active_device_count', (select count(*) from public.sync_devices),
    'executed', false);
end;
$$;

revoke all on function app_private.sync_journal_retention_plan(integer)
  from public, anon, authenticated;

create or replace function public.admin_sync_journal_retention_plan(
  safety_window_days integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare claim_role text;
begin
  claim_role := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  if claim_role is not null and claim_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'sync_backfill_forbidden';
  end if;
  return app_private.sync_journal_retention_plan(safety_window_days);
end;
$$;

revoke all on function public.admin_sync_journal_retention_plan(integer)
  from public, anon, authenticated;
grant execute on function public.admin_sync_journal_retention_plan(integer)
  to service_role;

-- ---------------------------------------------------------------------------
-- 7. Rollout verification snapshot
-- ---------------------------------------------------------------------------
-- PostgREST cannot run ad-hoc SQL, so a staging verifier would otherwise have
-- to be handed a database connection — which is exactly the thing the security
-- model refuses. This returns the facts a verifier needs to *assert* rather
-- than the ability to ask anything: grants, RLS flags, policy shape, trigger
-- presence, publication membership, the journal's column list, and counts.
-- Read-only, `service_role` only, no business payload anywhere in the result.
create or replace function app_private.sync_rollout_verification()
returns jsonb
language plpgsql
-- Not STABLE: `pg_total_relation_size` and friends are volatile, and claiming
-- otherwise would let the planner cache a size that is the whole point of
-- reading.
security definer
set search_path = ''
as $$
declare
  private_helpers text[] := array[
    'app_private.pull_entity_visible(text,uuid)',
    'app_private.pull_entity_payload(text,uuid)',
    'app_private.pull_entity_type_for_table(text)',
    'app_private.pull_table_for_entity_type(text)',
    'app_private.pull_mergeable_fields(text)',
    'app_private.pull_scope_fingerprint()',
    'app_private.pull_commit_horizon()',
    'app_private.prune_sync_change_journal(bigint)',
    'app_private.record_sync_change()',
    'app_private.record_sync_change_for_parent()',
    'app_private.record_field_versions()',
    'app_private.reject_journal_update()',
    'app_private.backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
    'app_private.sync_backfill_coverage(text)',
    'app_private.sync_journal_retention_plan(integer)',
    'app_private.sync_rollout_verification()'
  ];
  exposed text[];
  signature text;
begin
  exposed := array[]::text[];
  foreach signature in array private_helpers loop
    if to_regprocedure(signature) is not null and (
      pg_catalog.has_function_privilege('authenticated', signature, 'EXECUTE')
      or pg_catalog.has_function_privilege('anon', signature, 'EXECUTE')
      or pg_catalog.has_function_privilege('public', signature, 'EXECUTE')
    ) then
      exposed := exposed || signature;
    end if;
  end loop;

  return jsonb_build_object(
    'server_revision', (select revision from app_meta.schema_revisions
      order by applied_at desc limit 1),
    'migrations', (select coalesce(jsonb_agg(version order by version), '[]'::jsonb)
      from supabase_migrations.schema_migrations),
    'pull_rpc_present',
      to_regprocedure('public.pull_sync_changes(bigint,integer,uuid,text[])') is not null,
    'pull_rpc_signature', (select pg_catalog.pg_get_function_identity_arguments(
      to_regprocedure('public.pull_sync_changes(bigint,integer,uuid,text[])'))),
    'pull_rpc_is_definer', (select p.prosecdef from pg_proc as p
      where p.oid = to_regprocedure('public.pull_sync_changes(bigint,integer,uuid,text[])')),
    'privileges', jsonb_build_object(
      'authenticated_pull_rpc', pg_catalog.has_function_privilege('authenticated',
        'public.pull_sync_changes(bigint,integer,uuid,text[])', 'EXECUTE'),
      'anon_pull_rpc', pg_catalog.has_function_privilege('anon',
        'public.pull_sync_changes(bigint,integer,uuid,text[])', 'EXECUTE'),
      'authenticated_pull_entity_visible', pg_catalog.has_function_privilege(
        'authenticated', 'app_private.pull_entity_visible(text,uuid)', 'EXECUTE'),
      'authenticated_backfill', pg_catalog.has_function_privilege('authenticated',
        'public.admin_backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
        'EXECUTE'),
      'anon_backfill', pg_catalog.has_function_privilege('anon',
        'public.admin_backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
        'EXECUTE'),
      'exposed_private_helpers', to_jsonb(exposed),
      'exposed_private_helper_count', coalesce(array_length(exposed, 1), 0)),
    'journal', jsonb_build_object(
      'rls_enabled', (select c.relrowsecurity from pg_class as c
        where c.oid = 'public.sync_change_journal'::regclass),
      'rls_forced', (select c.relforcerowsecurity from pg_class as c
        where c.oid = 'public.sync_change_journal'::regclass),
      'policies', (select coalesce(jsonb_agg(jsonb_build_object(
          'name', p.policyname, 'command', p.cmd, 'roles', p.roles)
        order by p.policyname), '[]'::jsonb)
        from pg_policies as p
        where p.schemaname = 'public' and p.tablename = 'sync_change_journal'),
      'authenticated_select', pg_catalog.has_table_privilege('authenticated',
        'public.sync_change_journal', 'SELECT'),
      'authenticated_insert', pg_catalog.has_table_privilege('authenticated',
        'public.sync_change_journal', 'INSERT'),
      'authenticated_update', pg_catalog.has_table_privilege('authenticated',
        'public.sync_change_journal', 'UPDATE'),
      'authenticated_delete', pg_catalog.has_table_privilege('authenticated',
        'public.sync_change_journal', 'DELETE'),
      'anon_select', pg_catalog.has_table_privilege('anon',
        'public.sync_change_journal', 'SELECT'),
      'immutable_trigger', exists (select 1 from pg_trigger as t
        where t.tgrelid = 'public.sync_change_journal'::regclass
          and t.tgname = 'trg_sync_change_journal_immutable' and not t.tgisinternal),
      -- The whole point of the Realtime channel: bookkeeping columns only, so a
      -- broadcast frame cannot carry business data even if a client trusted it.
      'columns', (select coalesce(jsonb_agg(a.attname order by a.attnum), '[]'::jsonb)
        from pg_attribute as a
        where a.attrelid = 'public.sync_change_journal'::regclass
          and a.attnum > 0 and not a.attisdropped),
      'in_realtime_publication', exists (select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public'
          and tablename = 'sync_change_journal'),
      'realtime_publication_present', exists (select 1 from pg_publication
        where pubname = 'supabase_realtime'),
      'rows', (select count(*) from public.sync_change_journal),
      'min_change_seq', (select coalesce(min(change_seq), 0) from public.sync_change_journal),
      'max_change_seq', (select coalesce(max(change_seq), 0) from public.sync_change_journal),
      'commit_horizon', app_private.pull_commit_horizon(),
      'total_bytes', pg_catalog.pg_total_relation_size('public.sync_change_journal'),
      'table_bytes', pg_catalog.pg_table_size('public.sync_change_journal'),
      'index_bytes', pg_catalog.pg_indexes_size('public.sync_change_journal'),
      'journal_trigger_count', (select count(*) from pg_trigger as t
        where not t.tgisinternal
          and t.tgfoid in (
            to_regprocedure('app_private.record_sync_change()'),
            to_regprocedure('app_private.record_sync_change_for_parent()'))),
      'field_version_trigger_count', (select count(*) from pg_trigger as t
        where not t.tgisinternal
          and t.tgfoid = to_regprocedure('app_private.record_field_versions()')),
      'field_version_rows', (select count(*) from public.sync_entity_field_versions)),
    'rollout_tables', jsonb_build_object(
      'marks_present', to_regclass('public.sync_change_journal_backfill_marks') is not null,
      'runs_present', to_regclass('public.sync_change_journal_backfill_runs') is not null,
      'authenticated_marks_select', pg_catalog.has_table_privilege('authenticated',
        'public.sync_change_journal_backfill_marks', 'SELECT'),
      'authenticated_runs_select', pg_catalog.has_table_privilege('authenticated',
        'public.sync_change_journal_backfill_runs', 'SELECT'),
      'runs', (select coalesce(jsonb_agg(jsonb_build_object(
          'run_id', r.run_id, 'backfill_revision', r.backfill_revision,
          'completed', r.completed, 'scanned', r.scanned, 'inserted', r.inserted,
          'skipped', r.skipped, 'failed', r.failed, 'updated_at', r.updated_at)
        order by r.started_at), '[]'::jsonb)
        from public.sync_change_journal_backfill_runs as r)),
    'devices', jsonb_build_object(
      'total', (select count(*) from public.sync_devices)),
    'checked_at_utc', statement_timestamp());
end;
$$;

revoke all on function app_private.sync_rollout_verification()
  from public, anon, authenticated;

create or replace function public.admin_sync_rollout_verification()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare claim_role text;
begin
  claim_role := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  if claim_role is not null and claim_role <> 'service_role' then
    raise exception using errcode = '42501', message = 'sync_backfill_forbidden';
  end if;
  return app_private.sync_rollout_verification();
end;
$$;

revoke all on function public.admin_sync_rollout_verification()
  from public, anon, authenticated;
grant execute on function public.admin_sync_rollout_verification() to service_role;

-- No new row in `app_meta.schema_revisions`. The client contract is unchanged:
-- `SupabaseConfig.expectedSchemaRevision` is still `aish-supabase-003`, and a
-- revision bump here would make every 12C client fail its health check for a
-- migration that adds no client-visible surface. Whether this migration is
-- applied is answered by `supabase_migrations.schema_migrations`, which is what
-- `tool/verify_supabase_12c_staging.ts` checks.
