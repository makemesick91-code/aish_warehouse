-- Milestone 12C: deterministic server change feed, tombstones, server-computed
-- field versions, and the authenticated pull contract.
--
-- Additive only. No migration 001-009 object is dropped and no existing public
-- RPC signature changes. `push_sync_operation` and every 12B validator keep
-- working untouched; this migration only adds the read path.

-- ---------------------------------------------------------------------------
-- 1. Entity type registry
-- ---------------------------------------------------------------------------
-- The journal records changes at *aggregate* granularity for master rows and
-- documents: a line-table mutation is journalled against its parent header, so a
-- puller can only ever apply a complete document. `stock_movement` and
-- `stock_balance` are journalled per row instead — a movement is append-only and
-- self-contained, and a balance is a cache position a nurse may read even when
-- the document that moved it is outside their scope.

create or replace function app_private.pull_entity_type_for_table(source_table text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case source_table
    when 'branches' then 'branch'
    when 'rooms' then 'room'
    when 'users' then 'user'
    when 'item_categories' then 'category'
    when 'items' then 'item'
    when 'item_batches' then 'batch'
    when 'stock_locations' then 'stock_location'
    when 'stock_balances' then 'stock_balance'
    when 'stock_movements' then 'stock_movement'
    when 'stock_opnames' then 'stock_opname'
    when 'purchase_requests' then 'purchase_request'
    when 'delivery_orders' then 'delivery_order'
    when 'good_receipts' then 'good_receipt'
    when 'distributions' then 'distribution'
    when 'disposals' then 'disposal'
    when 'consumptions' then 'consumption'
    when 'goods_returns' then 'goods_return'
    else null
  end;
$$;

revoke all on function app_private.pull_entity_type_for_table(text) from public, anon, authenticated;

create or replace function app_private.pull_table_for_entity_type(requested_entity_type text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case requested_entity_type
    when 'branch' then 'branches'
    when 'room' then 'rooms'
    when 'user' then 'users'
    when 'category' then 'item_categories'
    when 'item' then 'items'
    when 'batch' then 'item_batches'
    when 'stock_location' then 'stock_locations'
    when 'stock_balance' then 'stock_balances'
    when 'stock_movement' then 'stock_movements'
    when 'stock_opname' then 'stock_opnames'
    when 'purchase_request' then 'purchase_requests'
    when 'delivery_order' then 'delivery_orders'
    when 'good_receipt' then 'good_receipts'
    when 'distribution' then 'distributions'
    when 'disposal' then 'disposals'
    when 'consumption' then 'consumptions'
    when 'goods_return' then 'goods_returns'
    else null
  end;
$$;

revoke all on function app_private.pull_table_for_entity_type(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Change journal
-- ---------------------------------------------------------------------------
create sequence public.sync_change_seq as bigint start with 1 increment by 1;

create table public.sync_change_journal (
  change_seq bigint primary key default nextval('public.sync_change_seq'),
  -- `nextval` is not transactional, so a transaction holding a low sequence
  -- number can commit after one holding a higher number. The reader needs to
  -- know which rows may still be in flight; `xid8` is monotonic and comparable
  -- against `pg_snapshot_xmin(pg_current_snapshot())`.
  xact_id xid8 not null default pg_current_xact_id(),
  entity_type varchar(64) not null,
  entity_id uuid not null,
  operation text not null check (operation in ('upsert', 'tombstone')),
  server_version bigint not null check (server_version > 0),
  changed_at timestamptz not null default now()
);

create index idx_sync_change_journal_entity
  on public.sync_change_journal (entity_type, entity_id, change_seq desc);
create index idx_sync_change_journal_xact
  on public.sync_change_journal (xact_id, change_seq);

alter table public.sync_change_journal enable row level security;
alter table public.sync_change_journal force row level security;
revoke all on table public.sync_change_journal from public, anon, authenticated;
grant all on table public.sync_change_journal to service_role;
grant usage on sequence public.sync_change_seq to service_role;

-- A journal row is a record of something that already happened, so it is never
-- edited. Deletion is left to retention (§11) rather than blocked outright,
-- because forced RLS plus the absence of any DELETE policy already means no
-- client role can remove one.
create or replace function app_private.reject_journal_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'sync_change_journal is immutable';
end;
$$;

revoke all on function app_private.reject_journal_update() from public, anon, authenticated;

create trigger trg_sync_change_journal_immutable
before update on public.sync_change_journal
for each row execute function app_private.reject_journal_update();

-- ---------------------------------------------------------------------------
-- 3. Server-computed field versions
-- ---------------------------------------------------------------------------
-- `field_version` is the entity's `server_version` at the moment that column
-- last changed. Reusing the entity version rather than keeping a separate
-- counter is what makes per-field ordering deterministic for free:
-- `server_version` is already assigned by `app_private.set_server_sync_metadata`
-- from the server clock and is monotonic per row, so no client can influence a
-- field version even indirectly. Clients never send field versions; they read.
create table public.sync_entity_field_versions (
  entity_type varchar(64) not null,
  entity_id uuid not null,
  field_name varchar(64) not null,
  field_version bigint not null check (field_version > 0),
  changed_at timestamptz not null default now(),
  primary key (entity_type, entity_id, field_name)
);

alter table public.sync_entity_field_versions enable row level security;
alter table public.sync_entity_field_versions force row level security;
revoke all on table public.sync_entity_field_versions from public, anon, authenticated;
grant all on table public.sync_entity_field_versions to service_role;

-- Only these columns take part in field-level last-write-wins. Server-controlled
-- columns, immutable identity columns and final-state columns are deliberately
-- absent: they are never merged, so carrying a version for them would invite a
-- caller to believe otherwise.
create or replace function app_private.pull_mergeable_fields(requested_entity_type text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case requested_entity_type
    when 'branch' then array['name', 'address', 'is_active']
    when 'room' then array['code', 'name', 'is_active']
    when 'user' then array['full_name', 'role', 'branch_id', 'is_active']
    when 'category' then array['name']
    when 'item' then array['name', 'category_id', 'unit', 'min_stock_room',
      'min_stock_branch', 'expiry_alert_days', 'is_active']
    when 'batch' then array['expiry_date']
    when 'stock_location' then array['name']
    else array[]::text[]
  end;
$$;

revoke all on function app_private.pull_mergeable_fields(text) from public, anon, authenticated;

create or replace function app_private.record_field_versions()
returns trigger
language plpgsql
-- A change journal has to record every writer, including `service_role` and any
-- future maintenance job, and none of them are granted usage on `app_private`.
-- Running as the owner is what makes the feed complete rather than dependent on
-- who happened to make the change. It is still unreachable directly: the grant
-- below revokes execute, and a trigger function has no other caller.
security definer
set search_path = ''
as $$
declare
  resolved_type text;
  field text;
  old_row jsonb;
  new_row jsonb;
begin
  resolved_type := app_private.pull_entity_type_for_table(tg_table_name);
  if resolved_type is null then return null; end if;
  new_row := to_jsonb(new);
  if tg_op = 'UPDATE' then old_row := to_jsonb(old); else old_row := null; end if;
  foreach field in array app_private.pull_mergeable_fields(resolved_type) loop
    if old_row is null or (old_row -> field) is distinct from (new_row -> field) then
      insert into public.sync_entity_field_versions
        (entity_type, entity_id, field_name, field_version, changed_at)
      values (resolved_type, (new_row ->> 'id')::uuid, field,
        (new_row ->> 'server_version')::bigint, statement_timestamp())
      on conflict (entity_type, entity_id, field_name) do update
        set field_version = excluded.field_version,
            changed_at = excluded.changed_at;
    end if;
  end loop;
  return null;
end;
$$;

revoke all on function app_private.record_field_versions() from public, anon, authenticated;

do $$
declare source_table text;
begin
  foreach source_table in array array[
    'branches', 'rooms', 'users', 'item_categories', 'items', 'item_batches',
    'stock_locations'
  ] loop
    execute format(
      'create trigger %I after insert or update on public.%I '
      'for each row execute function app_private.record_field_versions()',
      'trg_' || source_table || '_field_versions', source_table);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Journal triggers
-- ---------------------------------------------------------------------------
-- A row whose `deleted_at` moves from NULL to non-NULL is a tombstone. Every
-- other insert or update is an upsert, including reactivation (`deleted_at` back
-- to NULL) and `is_active = false`, which is a field change and not a deletion
-- (G-A4). `stock_movements` and `export_logs` cannot be updated at all, so they
-- structurally cannot produce a tombstone.
create or replace function app_private.record_sync_change()
returns trigger
language plpgsql
-- A change journal has to record every writer, including `service_role` and any
-- future maintenance job, and none of them are granted usage on `app_private`.
-- Running as the owner is what makes the feed complete rather than dependent on
-- who happened to make the change. It is still unreachable directly: the grant
-- below revokes execute, and a trigger function has no other caller.
security definer
set search_path = ''
as $$
declare
  resolved_type text;
  resolved_operation text;
  new_row jsonb;
begin
  resolved_type := app_private.pull_entity_type_for_table(tg_table_name);
  if resolved_type is null then return null; end if;
  new_row := to_jsonb(new);
  resolved_operation := 'upsert';
  if (new_row ->> 'deleted_at') is not null then
    if tg_op = 'INSERT' or (to_jsonb(old) ->> 'deleted_at') is null then
      resolved_operation := 'tombstone';
    end if;
  end if;
  insert into public.sync_change_journal
    (entity_type, entity_id, operation, server_version, changed_at)
  values (resolved_type, (new_row ->> 'id')::uuid, resolved_operation,
    (new_row ->> 'server_version')::bigint, statement_timestamp());
  return null;
end;
$$;

revoke all on function app_private.record_sync_change() from public, anon, authenticated;

-- A line mutation is journalled against its parent header, so the puller only
-- ever sees whole aggregates. The header's own `server_version` is reported
-- because that is the version the client reconciles against.
create or replace function app_private.record_sync_change_for_parent()
returns trigger
language plpgsql
-- A change journal has to record every writer, including `service_role` and any
-- future maintenance job, and none of them are granted usage on `app_private`.
-- Running as the owner is what makes the feed complete rather than dependent on
-- who happened to make the change. It is still unreachable directly: the grant
-- below revokes execute, and a trigger function has no other caller.
security definer
set search_path = ''
as $$
declare
  parent_id uuid;
  parent_version bigint;
begin
  parent_id := (to_jsonb(new) ->> tg_argv[1])::uuid;
  if parent_id is null then return null; end if;
  execute format('select entity.server_version from public.%I as entity where entity.id = $1',
    tg_argv[2]) into parent_version using parent_id;
  if parent_version is null then return null; end if;
  insert into public.sync_change_journal
    (entity_type, entity_id, operation, server_version, changed_at)
  values (tg_argv[0], parent_id, 'upsert', parent_version, statement_timestamp());
  return null;
end;
$$;

revoke all on function app_private.record_sync_change_for_parent() from public, anon, authenticated;

do $$
declare source_table text;
begin
  foreach source_table in array array[
    'branches', 'rooms', 'users', 'item_categories', 'items', 'item_batches',
    'stock_locations', 'stock_balances', 'stock_movements', 'stock_opnames',
    'purchase_requests', 'delivery_orders', 'good_receipts', 'distributions',
    'disposals', 'consumptions', 'goods_returns'
  ] loop
    execute format(
      'create trigger %I after insert or update on public.%I '
      'for each row execute function app_private.record_sync_change()',
      'trg_' || source_table || '_change_journal', source_table);
  end loop;
end;
$$;

do $$
declare child record;
begin
  for child in
    select * from (values
      ('stock_opname_lines', 'stock_opname', 'opname_id', 'stock_opnames'),
      ('purchase_request_lines', 'purchase_request', 'pr_id', 'purchase_requests'),
      ('purchase_request_opnames', 'purchase_request', 'pr_id', 'purchase_requests'),
      ('delivery_order_lines', 'delivery_order', 'do_id', 'delivery_orders'),
      ('good_receipt_lines', 'good_receipt', 'gr_id', 'good_receipts'),
      ('distribution_lines', 'distribution', 'distribution_id', 'distributions'),
      ('disposal_lines', 'disposal', 'disposal_id', 'disposals'),
      ('consumption_lines', 'consumption', 'consumption_id', 'consumptions'),
      ('goods_return_lines', 'goods_return', 'goods_return_id', 'goods_returns')
    ) as t(child_table, parent_type, parent_column, parent_table)
  loop
    execute format(
      'create trigger %I after insert or update on public.%I for each row '
      'execute function app_private.record_sync_change_for_parent(%L, %L, %L)',
      'trg_' || child.child_table || '_change_journal', child.child_table,
      child.parent_type, child.parent_column, child.parent_table);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Visibility
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER runs as the function owner and therefore bypasses RLS, so the
-- SELECT predicates have to be restated here. They call exactly the same helpers
-- as the policies, and those helpers resolve the *calling* identity because they
-- read `auth.uid()` from the request claims rather than from the database role.
--
-- Restating a predicate risks drifting from the policy it mirrors.
-- `supabase/tests/database/pull_sync.test.sql` therefore compares, per entity
-- type and per fixture actor, the id set RLS returns against the id set this
-- function admits. Divergence fails the suite instead of leaking data.
create or replace function app_private.pull_entity_visible(
  requested_entity_type text,
  requested_entity_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare visible boolean;
begin
  if not app_private.current_user_is_active() then return false; end if;

  case requested_entity_type
    when 'branch' then
      select (app_private.current_user_role() in ('warehouse', 'super_admin')
        or entity.id = app_private.current_user_branch_id())
        into visible from public.branches as entity
        where entity.id = requested_entity_id;
    when 'room' then
      select (app_private.is_super_admin()
        or entity.branch_id = app_private.current_user_branch_id())
        into visible from public.rooms as entity
        where entity.id = requested_entity_id;
    when 'user' then
      select (entity.id = app_private.current_domain_user_id()
        or app_private.is_super_admin())
        into visible from public.users as entity
        where entity.id = requested_entity_id;
    when 'category' then
      select true into visible from public.item_categories as entity
        where entity.id = requested_entity_id;
    when 'item' then
      select true into visible from public.items as entity
        where entity.id = requested_entity_id;
    when 'batch' then
      select true into visible from public.item_batches as entity
        where entity.id = requested_entity_id;
    when 'stock_location' then
      select app_private.can_read_location(entity.id) into visible
        from public.stock_locations as entity
        where entity.id = requested_entity_id;
    when 'stock_balance' then
      select app_private.can_read_location(entity.location_id) into visible
        from public.stock_balances as entity
        where entity.id = requested_entity_id;
    when 'stock_movement' then
      select (app_private.is_super_admin()
        or (entity.from_location_id is not null
          and app_private.can_read_location(entity.from_location_id))
        or (entity.to_location_id is not null
          and app_private.can_read_location(entity.to_location_id)))
        into visible from public.stock_movements as entity
        where entity.id = requested_entity_id;
    when 'stock_opname' then
      select ((app_private.is_nurse()
          and entity.counted_by = app_private.current_domain_user_id()
          and entity.branch_id = app_private.current_user_branch_id())
        or (app_private.is_branch_head()
          and entity.branch_id = app_private.current_user_branch_id())
        or (app_private.current_user_role() in ('warehouse', 'super_admin')
          and entity.status = 'reviewed'))
        into visible from public.stock_opnames as entity
        where entity.id = requested_entity_id;
    when 'purchase_request' then
      select ((app_private.is_branch_head()
          and entity.branch_id = app_private.current_user_branch_id())
        or app_private.current_user_role() in ('warehouse', 'super_admin'))
        into visible from public.purchase_requests as entity
        where entity.id = requested_entity_id;
    when 'delivery_order' then
      select (app_private.current_user_role() in ('warehouse', 'super_admin')
        or (app_private.is_branch_head()
          and request.branch_id = app_private.current_user_branch_id()
          and entity.status in ('shipped', 'received')))
        into visible from public.delivery_orders as entity
        join public.purchase_requests as request on request.id = entity.pr_id
        where entity.id = requested_entity_id;
    when 'good_receipt' then
      select (app_private.current_user_role() in ('warehouse', 'super_admin')
        or (app_private.is_branch_head()
          and request.branch_id = app_private.current_user_branch_id()))
        into visible from public.good_receipts as entity
        join public.delivery_orders as delivery on delivery.id = entity.do_id
        join public.purchase_requests as request on request.id = delivery.pr_id
        where entity.id = requested_entity_id;
    when 'distribution' then
      select ((app_private.is_branch_head()
          and entity.branch_id = app_private.current_user_branch_id())
        or (app_private.current_user_role() in ('warehouse', 'super_admin')
          and entity.status = 'posted'))
        into visible from public.distributions as entity
        where entity.id = requested_entity_id;
    when 'disposal' then
      select (app_private.is_super_admin()
        or app_private.can_read_location(entity.source_location_id))
        into visible from public.disposals as entity
        where entity.id = requested_entity_id;
    when 'consumption' then
      select ((app_private.is_nurse()
          and entity.created_by = app_private.current_domain_user_id()
          and entity.branch_id = app_private.current_user_branch_id())
        or (app_private.is_branch_head()
          and entity.branch_id = app_private.current_user_branch_id()
          and entity.status = 'posted')
        or (app_private.current_user_role() in ('warehouse', 'super_admin')
          and entity.status = 'posted'))
        into visible from public.consumptions as entity
        where entity.id = requested_entity_id;
    when 'goods_return' then
      select ((app_private.is_branch_head()
          and entity.branch_id = app_private.current_user_branch_id())
        or (app_private.is_warehouse() and entity.status in ('shipped', 'received'))
        or app_private.is_super_admin())
        into visible from public.goods_returns as entity
        where entity.id = requested_entity_id;
    else
      return false;
  end case;

  return coalesce(visible, false);
end;
$$;

-- No client role may call this directly. `public.pull_sync_changes` is SECURITY
-- DEFINER and therefore reaches it as the function owner, so a grant to
-- `authenticated` would buy the pull path nothing and would hand a direct
-- connection an existence oracle over every entity type. The journal policy in
-- §10 used to need the grant, because a policy expression is evaluated with the
-- privileges of the querying role; it no longer calls this function at all.
revoke all on function app_private.pull_entity_visible(text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Payload
-- ---------------------------------------------------------------------------
-- The shape mirrors what `DriftSyncSnapshotReader` pushes, so one applier can
-- consume both: header columns at the top level, `lines` for child rows,
-- `opname_links` for a purchase request, and `movements` for a posting document.
-- Building the whole aggregate in one call is what makes a partial document
-- impossible on the client.
create or replace function app_private.pull_entity_payload(
  requested_entity_type text,
  requested_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  source_table text;
  v_child_table text;
  v_child_column text;
  ref_type text;
  payload jsonb;
  children jsonb;
begin
  source_table := app_private.pull_table_for_entity_type(requested_entity_type);
  if source_table is null then return null; end if;

  execute format(
    'select to_jsonb(entity) from public.%I as entity where entity.id = $1',
    source_table) into payload using requested_entity_id;
  if payload is null then return null; end if;

  select mapping.child_table, mapping.child_column
    into v_child_table, v_child_column
  from (values
    ('stock_opname', 'stock_opname_lines', 'opname_id'),
    ('purchase_request', 'purchase_request_lines', 'pr_id'),
    ('delivery_order', 'delivery_order_lines', 'do_id'),
    ('good_receipt', 'good_receipt_lines', 'gr_id'),
    ('distribution', 'distribution_lines', 'distribution_id'),
    ('disposal', 'disposal_lines', 'disposal_id'),
    ('consumption', 'consumption_lines', 'consumption_id'),
    ('goods_return', 'goods_return_lines', 'goods_return_id')
  ) as mapping(parent_type, child_table, child_column)
  where mapping.parent_type = requested_entity_type;

  if v_child_table is not null then
    execute format(
      'select coalesce(jsonb_agg(to_jsonb(line) order by line.id), ''[]''::jsonb) '
      'from public.%I as line where line.%I = $1 and line.deleted_at is null',
      v_child_table, v_child_column) into children using requested_entity_id;
    payload := payload || jsonb_build_object('lines', children);
  end if;

  if requested_entity_type = 'purchase_request' then
    select coalesce(jsonb_agg(to_jsonb(link) order by link.id), '[]'::jsonb)
      into children from public.purchase_request_opnames as link
      where link.pr_id = requested_entity_id and link.deleted_at is null;
    payload := payload || jsonb_build_object('opname_links', children);
  end if;

  ref_type := case requested_entity_type
    when 'stock_opname' then 'SO' when 'delivery_order' then 'DO'
    when 'good_receipt' then 'GR' when 'distribution' then 'DIST'
    when 'disposal' then 'DSP' when 'consumption' then 'CONS'
    when 'goods_return' then 'RET' else null end;
  if ref_type is not null then
    select coalesce(jsonb_agg(to_jsonb(movement) order by movement.id), '[]'::jsonb)
      into children from public.stock_movements as movement
      where movement.ref_doc_type = ref_type
        and movement.ref_doc_id = requested_entity_id;
    payload := payload || jsonb_build_object('movements', children);
  end if;

  return payload;
end;
$$;

revoke all on function app_private.pull_entity_payload(text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Scope fingerprint
-- ---------------------------------------------------------------------------
-- A cursor is only meaningful inside one authorization scope. When role or
-- branch changes, journal entries the actor could not previously see are
-- permanently behind the cursor and cannot be reconstructed from it, so the
-- client must resync from zero. The fingerprint is what lets it notice, and it
-- reveals nothing: it is a digest, and the actor already knows its own identity.
create or replace function app_private.pull_scope_fingerprint()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select encode(extensions.digest(convert_to(
    coalesce(app_private.current_domain_user_id()::text, '') || '|' ||
    coalesce(app_private.current_user_role(), '') || '|' ||
    coalesce(app_private.current_user_branch_id()::text, ''), 'UTF8'), 'sha256'), 'hex');
$$;

revoke all on function app_private.pull_scope_fingerprint() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. Commit horizon
-- ---------------------------------------------------------------------------
-- Everything at or below the horizon belongs to a settled transaction, so a
-- cursor advanced to it can never step over a change that has not been seen.
-- An in-flight transaction holds the queue head rather than being skipped.
create or replace function app_private.pull_commit_horizon()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select min(journal.change_seq) - 1 from public.sync_change_journal as journal
      where journal.xact_id >= pg_snapshot_xmin(pg_current_snapshot())),
    (select coalesce(max(journal.change_seq), 0)
      from public.sync_change_journal as journal));
$$;

revoke all on function app_private.pull_commit_horizon() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 9. Authenticated pull contract
-- ---------------------------------------------------------------------------
create or replace function public.pull_sync_changes(
  after_cursor bigint,
  batch_limit integer default 200,
  device_id uuid default null,
  entity_types text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  effective_limit integer;
  horizon bigint;
  changes jsonb := '[]'::jsonb;
  next_cursor bigint;
  more boolean := false;
  entry record;
  payload jsonb;
  field_versions jsonb;
  emitted integer := 0;
begin
  actor_id := app_private.current_domain_user_id();
  if actor_id is null then
    raise exception using errcode = '42501', message = 'sync_identity_unlinked';
  end if;
  if not app_private.current_user_is_active() then
    raise exception using errcode = '42501', message = 'sync_user_inactive';
  end if;
  if device_id is null or not exists (
    select 1 from public.sync_devices as device
    where device.id = device_id and device.actor_user_id = actor_id
  ) then
    raise exception using errcode = '42501', message = 'sync_access_denied';
  end if;
  if after_cursor is null or after_cursor < 0 then
    raise exception using errcode = '22023', message = 'sync_cursor_invalid';
  end if;
  effective_limit := coalesce(batch_limit, 200);
  if effective_limit < 1 or effective_limit > 500 then
    raise exception using errcode = '22023', message = 'sync_invalid_payload';
  end if;
  -- A cursor beyond anything the server ever issued cannot be this client's own
  -- progress; treat it as a corrupt or forged scope rather than silently
  -- returning an empty page forever.
  if after_cursor > (select coalesce(max(journal.change_seq), 0)
    from public.sync_change_journal as journal) then
    raise exception using errcode = '22023', message = 'sync_cursor_invalid';
  end if;

  horizon := app_private.pull_commit_horizon();
  next_cursor := after_cursor;

  for entry in
    select journal.change_seq, journal.entity_type, journal.entity_id,
           journal.operation, journal.server_version, journal.changed_at
    from public.sync_change_journal as journal
    where journal.change_seq > after_cursor
      and journal.change_seq <= horizon
      and (entity_types is null or journal.entity_type = any(entity_types))
    order by journal.change_seq
    limit effective_limit + 1
  loop
    if emitted = effective_limit then
      more := true;
      exit;
    end if;
    next_cursor := entry.change_seq;
    emitted := emitted + 1;
    -- An entry the caller may not read is dropped without a trace. Emitting a
    -- placeholder would tell a branch A actor that a branch B record exists; a
    -- gap in `change_seq` tells them nothing, because rolled-back transactions
    -- and filtered entity types leave identical gaps.
    if not app_private.pull_entity_visible(entry.entity_type, entry.entity_id) then
      continue;
    end if;
    if entry.operation = 'tombstone' then
      payload := null;
    else
      payload := app_private.pull_entity_payload(entry.entity_type, entry.entity_id);
      if payload is null then continue; end if;
    end if;
    select coalesce(jsonb_object_agg(version.field_name, version.field_version),
      '{}'::jsonb)
      into field_versions from public.sync_entity_field_versions as version
      where version.entity_type = entry.entity_type
        and version.entity_id = entry.entity_id;
    changes := changes || jsonb_build_array(jsonb_build_object(
      'change_seq', entry.change_seq,
      'entity_type', entry.entity_type,
      'entity_id', entry.entity_id,
      'operation', entry.operation,
      'server_version', entry.server_version,
      'server_changed_at_utc', entry.changed_at,
      'payload', payload,
      'field_versions', field_versions));
  end loop;

  return jsonb_build_object(
    'changes', changes,
    'next_cursor', next_cursor,
    'has_more', more,
    'server_time_utc', statement_timestamp(),
    'server_horizon', horizon,
    'scope_fingerprint', app_private.pull_scope_fingerprint());
end;
$$;

revoke all on function public.pull_sync_changes(bigint, integer, uuid, text[]) from public, anon;
grant execute on function public.pull_sync_changes(bigint, integer, uuid, text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Realtime invalidation channel
-- ---------------------------------------------------------------------------
-- Realtime is a hint that a pull is due, never a source of truth. A client sees
-- only the journal bookkeeping columns of rows it is already allowed to read;
-- the business payload is never broadcast and always comes from the
-- authenticated pull above. There is no INSERT, UPDATE or DELETE policy, so with
-- forced RLS no client role can write or remove a journal row.
grant select on table public.sync_change_journal to authenticated;

-- The predicate is expressed as an existence probe against the entity's own
-- table rather than as a call to `app_private.pull_entity_visible`. Two reasons,
-- and the first is the load bearing one:
--
--  1. A policy expression runs with the privileges of the querying role, so
--     calling the helper here would force an EXECUTE grant to `authenticated`
--     and expose the whole visibility oracle to any direct connection. §5 keeps
--     that helper private instead.
--  2. Unlike the SECURITY DEFINER pull path, a policy is evaluated as the actor
--     with RLS live on every table it touches. The probe therefore *is* the RLS
--     answer rather than a restatement of it, so this predicate cannot drift.
--
-- Equivalence with the pull filter is asserted per fixture actor over every
-- journal row in `supabase/tests/database/pull_sync.test.sql`; an unmapped
-- entity type falls through to `false` exactly as the helper does.
create policy sync_change_journal_read_scope on public.sync_change_journal
for select to authenticated
using (
  app_private.current_user_is_active()
  and case entity_type
    when 'branch' then exists (select 1 from public.branches as e where e.id = entity_id)
    when 'room' then exists (select 1 from public.rooms as e where e.id = entity_id)
    when 'user' then exists (select 1 from public.users as e where e.id = entity_id)
    when 'category' then exists (select 1 from public.item_categories as e where e.id = entity_id)
    when 'item' then exists (select 1 from public.items as e where e.id = entity_id)
    when 'batch' then exists (select 1 from public.item_batches as e where e.id = entity_id)
    when 'stock_location' then exists (select 1 from public.stock_locations as e where e.id = entity_id)
    when 'stock_balance' then exists (select 1 from public.stock_balances as e where e.id = entity_id)
    when 'stock_movement' then exists (select 1 from public.stock_movements as e where e.id = entity_id)
    when 'stock_opname' then exists (select 1 from public.stock_opnames as e where e.id = entity_id)
    when 'purchase_request' then exists (select 1 from public.purchase_requests as e where e.id = entity_id)
    when 'delivery_order' then exists (select 1 from public.delivery_orders as e where e.id = entity_id)
    when 'good_receipt' then exists (select 1 from public.good_receipts as e where e.id = entity_id)
    when 'distribution' then exists (select 1 from public.distributions as e where e.id = entity_id)
    when 'disposal' then exists (select 1 from public.disposals as e where e.id = entity_id)
    when 'consumption' then exists (select 1 from public.consumptions as e where e.id = entity_id)
    when 'goods_return' then exists (select 1 from public.goods_returns as e where e.id = entity_id)
    else false
  end
);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public' and tablename = 'sync_change_journal'
    ) then
    execute 'alter publication supabase_realtime add table public.sync_change_journal';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Retention
-- ---------------------------------------------------------------------------
-- Not scheduled by this migration. Pruning below a device's cursor makes that
-- device resync from zero, which is safe but expensive, so the decision belongs
-- to an operator following `docs/supabase_12c_remote_handoff.md`.
create or replace function app_private.prune_sync_change_journal(keep_through bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare removed bigint;
begin
  if keep_through is null or keep_through < 0 then
    raise exception using errcode = '22023', message = 'sync_invalid_payload';
  end if;
  -- Never prune at or above the commit horizon: those entries may still be
  -- unread by every device.
  keep_through := least(keep_through, app_private.pull_commit_horizon());
  delete from public.sync_change_journal as journal
    where journal.change_seq <= keep_through;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function app_private.prune_sync_change_journal(bigint)
  from public, anon, authenticated;

insert into app_meta.schema_revisions (revision) values ('aish-supabase-003');
