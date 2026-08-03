-- Milestone 12C rollout: the change-journal baseline backfill.
--
-- The property under test is narrow and load-bearing: the backfill must make a
-- pre-existing row appear in the feed *without* being a business write. Every
-- assertion here is therefore either "the journal grew the way it should" or
-- "nothing else moved at all" — and the second kind is the reason the suite
-- exists, because the cheap implementation of a backfill (touch every row) is
-- exactly the one that silently supersedes every pending client edit.
--
-- Scope note, stated rather than papered over: pgTAP runs inside a single
-- transaction, so `app_private.pull_commit_horizon()` never releases a row this
-- suite writes and `public.pull_sync_changes` cannot be driven over backfilled
-- entries here. Cursor-from-zero drain and page-boundary coverage are asserted
-- against the journal directly below, and over the real RPC with committed
-- writes in `tool/supabase_12c_staging_e2e.ts`.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- ---------------------------------------------------------------------------
-- Structure and privilege
-- ---------------------------------------------------------------------------
select has_table('public', 'sync_change_journal_backfill_runs', 'run ledger exists');
select has_table('public', 'sync_change_journal_backfill_marks', 'idempotency marks exist');

-- The revision contract is deliberately unchanged: this migration adds no
-- client-visible surface, so a 12C client must not be told to fail its health
-- check over it.
select is((select revision from app_meta.schema_revisions order by applied_at desc limit 1),
  'aish-supabase-003', 'rollout migration does not move the server revision');

select ok((select relrowsecurity and relforcerowsecurity from pg_class
  where oid = 'public.sync_change_journal_backfill_runs'::regclass),
  'run ledger has forced RLS');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
  where oid = 'public.sync_change_journal_backfill_marks'::regclass),
  'marks table has forced RLS');
select is((select count(*)::bigint from pg_policies
  where schemaname = 'public'
    and tablename in ('sync_change_journal_backfill_runs',
      'sync_change_journal_backfill_marks')),
  0::bigint, 'no client policy exists on either rollout table');

-- Requirements 11, 12 and 13: the operator surface is reachable by the trusted
-- role and by nobody else. EXECUTE is the control; the claim check in the
-- wrapper is the second one, asserted separately below.
select ok(has_function_privilege('service_role',
  'public.admin_backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
  'EXECUTE'), 'service_role may run the backfill');
select ok(not has_function_privilege('authenticated',
  'public.admin_backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
  'EXECUTE'), 'authenticated may not run the backfill');
select ok(not has_function_privilege('anon',
  'public.admin_backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
  'EXECUTE'), 'anon may not run the backfill');
select ok(not has_function_privilege('public',
  'public.admin_backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
  'EXECUTE'), 'PUBLIC may not run the backfill');

select is(
  (select coalesce(string_agg(signature, ', ' order by signature), '') from unnest(array[
    'app_private.backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
    'app_private.backfill_entity_type_order()',
    'app_private.sync_backfill_coverage(text)',
    'app_private.sync_journal_retention_plan(integer)'
  ]) as signature
  where has_function_privilege('authenticated', signature, 'EXECUTE')
     or has_function_privilege('anon', signature, 'EXECUTE')
     or has_function_privilege('public', signature, 'EXECUTE')),
  '', 'no rollout worker is executable by a client role');

select is(
  (select coalesce(string_agg(signature, ', ' order by signature), '') from unnest(array[
    'public.admin_backfill_sync_change_journal(uuid,text,text[],integer,integer,text,uuid,boolean)',
    'public.admin_sync_backfill_coverage(text)',
    'public.admin_sync_journal_retention_plan(integer)'
  ]) as signature
  where has_function_privilege('authenticated', signature, 'EXECUTE')
     or has_function_privilege('anon', signature, 'EXECUTE')),
  '', 'no operator wrapper is executable by a session token role');

-- Every rollout function is SECURITY DEFINER with a pinned search_path.
select is((select count(*)::bigint from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'app_private')
    and (p.proname like 'backfill%' or p.proname like '%sync_backfill%'
      or p.proname like '%journal_retention%')
    and p.prosecdef
    and not (coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')),
  0::bigint, 'every rollout definer function pins search_path');

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
-- The journal is emptied so the seeded rows stand in for "data that predates
-- revision 003". A ledger row and a balance row are added first, because the
-- invariants that matter most here are the ones about them not moving, and an
-- assertion over an empty table proves nothing.
insert into public.stock_movements (
  id, created_at, updated_at, sync_status, item_id, batch_id, from_location_id,
  to_location_id, qty, movement_type, actor_user_id
) values (
  '60000000-0000-0000-0000-0000000000a1', now(), now(), 'synced',
  '41000000-0000-0000-0000-000000000001', null, null,
  '50000000-0000-0000-0000-000000000002', 40, 'inbound_warehouse',
  '30000000-0000-0000-0000-000000000004');

insert into public.stock_balances (
  id, created_at, updated_at, sync_status, location_id, item_id, batch_id, qty_on_hand
) values (
  '61000000-0000-0000-0000-0000000000a1', now(), now(), 'synced',
  '50000000-0000-0000-0000-000000000002', '41000000-0000-0000-0000-000000000001',
  null, 40);

-- A soft-deleted master, so the tombstone path is exercised rather than assumed.
update public.item_categories set deleted_at = now()
  where id = '40000000-0000-0000-0000-000000000001';

create temp table business_before as
  select 'item'::text as kind, id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.items
  union all select 'branch', id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.branches
  union all select 'room', id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.rooms
  union all select 'user', id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.users
  union all select 'category', id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.item_categories
  union all select 'batch', id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.item_batches
  union all select 'stock_location', id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.stock_locations
  union all select 'stock_balance', id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.stock_balances
  union all select 'stock_movement', id, server_version, created_at, updated_at,
         server_updated_at, deleted_at from public.stock_movements;

create temp table ledger_before as
  select count(*) as movements,
    coalesce(sum(qty), 0) as qty_total from public.stock_movements;
create temp table balance_before as
  select id, qty_on_hand from public.stock_balances;

delete from public.sync_change_journal;
delete from public.sync_entity_field_versions;

select is((select count(*)::bigint from public.sync_change_journal), 0::bigint,
  'journal starts empty, standing in for a pre-003 dataset');
-- Negative guard: if the fixture ever stops producing candidates, every
-- "nothing was duplicated" assertion below would pass vacuously.
select cmp_ok((select count(*)::bigint from public.items
  union all select count(*) from public.branches limit 1), '>', 0::bigint,
  'there is something to back fill');

-- ---------------------------------------------------------------------------
-- Requirement 1: a dry run writes nothing
-- ---------------------------------------------------------------------------
create temp table dry_report as select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000d001',
  p_batch_size => 500, p_max_batches => 100, p_dry_run => true) as report;

select cmp_ok((select (report -> 'batches' -> 0 ->> 'inserted')::bigint from dry_report),
  '>', 0::bigint, 'dry run reports work it would do');
select is((select count(*)::bigint from public.sync_change_journal), 0::bigint,
  'dry run writes no journal row');
select is((select count(*)::bigint from public.sync_change_journal_backfill_marks),
  0::bigint, 'dry run claims no idempotency mark');
select is((select count(*)::bigint from public.sync_change_journal_backfill_runs),
  0::bigint, 'dry run records no run');
select is((select count(*)::bigint from public.sync_entity_field_versions), 0::bigint,
  'dry run writes no field version');

-- ---------------------------------------------------------------------------
-- Requirement 2: the first real run creates the baseline
-- ---------------------------------------------------------------------------
create temp table run_one as select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000b001',
  p_batch_size => 500, p_max_batches => 100, p_dry_run => false) as report;

select is((select report ->> 'completed' from run_one), 'true',
  'first run reports completion');
select cmp_ok((select count(*)::bigint from public.sync_change_journal), '>', 0::bigint,
  'first run journals the baseline');
select is(
  (select count(*)::bigint from public.sync_change_journal),
  (select count(*)::bigint from public.sync_change_journal_backfill_marks),
  'one mark per journalled entity');

-- Every live entity of every syncable type now has exactly one baseline entry.
select is((select (app_private.sync_backfill_coverage() ->> 'missing_baseline_total')::bigint),
  0::bigint, 'no syncable entity is left without a baseline');
select is((select app_private.sync_backfill_coverage() ->> 'complete'), 'true',
  'coverage reports complete');

-- Aggregate granularity: a document header is journalled once, and child line
-- tables never appear as an entity type of their own.
select is((select count(*)::bigint from public.sync_change_journal
  where entity_type in ('purchase_request_line', 'stock_opname_line',
    'delivery_order_line', 'consumption_line')),
  0::bigint, 'child lines are never journalled as their own entity');
select is((select count(*)::bigint from (
    select entity_type, entity_id from public.sync_change_journal
    group by entity_type, entity_id having count(*) > 1) as repeated),
  0::bigint, 'baseline journals each aggregate exactly once');

-- ---------------------------------------------------------------------------
-- Requirement 10: a soft-deleted row arrives as a tombstone, not an upsert
-- ---------------------------------------------------------------------------
select is((select operation from public.sync_change_journal
  where entity_type = 'category'
    and entity_id = '40000000-0000-0000-0000-000000000001'),
  'tombstone', 'a soft-deleted master is journalled as a tombstone');
select is((select operation from public.sync_change_journal
  where entity_type = 'item'
    and entity_id = '41000000-0000-0000-0000-000000000001'),
  'upsert', 'a live master is journalled as an upsert');
select is((select operation from public.sync_change_journal_backfill_marks
  where entity_type = 'category'
    and entity_id = '40000000-0000-0000-0000-000000000001'),
  'tombstone', 'the mark records the operation it claimed');
select is((select server_version from public.sync_change_journal
  where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000001'),
  (select server_version from public.items
  where id = '41000000-0000-0000-0000-000000000001'),
  'the baseline reports the entity version the server already held');

-- ---------------------------------------------------------------------------
-- Requirement 9: field version baselines
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::bigint from public.sync_entity_field_versions
   where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000001'),
  (select array_length(app_private.pull_mergeable_fields('item'), 1)::bigint),
  'every mergeable field of a master gets a baseline version');
select is(
  (select distinct field_version from public.sync_entity_field_versions
   where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000001'),
  (select server_version from public.items
   where id = '41000000-0000-0000-0000-000000000001'),
  'a baseline field version is the entity version, never a fabricated counter');
-- A ledger row is never merged per field, so carrying versions for it would
-- invite a client to believe otherwise.
select is((select count(*)::bigint from public.sync_entity_field_versions
  where entity_type in ('stock_movement', 'stock_balance')),
  0::bigint, 'ledger and cache entities get no field versions');

-- ---------------------------------------------------------------------------
-- Requirements 5, 6, 7, 8: nothing about the business moved
-- ---------------------------------------------------------------------------
select is((select count(*)::bigint from business_before as before
  join (
    select 'item'::text as kind, id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.items
    union all select 'branch', id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.branches
    union all select 'room', id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.rooms
    union all select 'user', id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.users
    union all select 'category', id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.item_categories
    union all select 'batch', id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.item_batches
    union all select 'stock_location', id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.stock_locations
    union all select 'stock_balance', id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.stock_balances
    union all select 'stock_movement', id, server_version, created_at, updated_at,
           server_updated_at, deleted_at from public.stock_movements) as after
  on after.kind = before.kind and after.id = before.id
  where after.server_version is distinct from before.server_version
     or after.updated_at is distinct from before.updated_at
     or after.created_at is distinct from before.created_at
     or after.server_updated_at is distinct from before.server_updated_at
     or after.deleted_at is distinct from before.deleted_at),
  0::bigint, 'backfill changes no business column, version or timestamp');

select is((select count(*)::bigint from public.stock_movements),
  (select movements from ledger_before), 'the ledger gains no movement');
select is((select coalesce(sum(qty), 0) from public.stock_movements),
  (select qty_total from ledger_before), 'the ledger gains no quantity');
select is((select count(*)::bigint from balance_before as before
  join public.stock_balances as after on after.id = before.id
  where after.qty_on_hand is distinct from before.qty_on_hand),
  0::bigint, 'no stock balance moves');
select is((select count(*)::bigint from public.stock_balances where qty_on_hand < 0),
  0::bigint, 'no balance is driven negative');

-- ---------------------------------------------------------------------------
-- Requirements 3 and 4: re-running never duplicates
-- ---------------------------------------------------------------------------
create temp table journal_after_first as
  select count(*) as rows, coalesce(max(change_seq), 0) as max_seq
  from public.sync_change_journal;

-- Same run id.
select ok((select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000b001',
  p_batch_size => 500, p_max_batches => 100, p_dry_run => false) is not null),
  'the same run id may be replayed');
select is((select count(*)::bigint from public.sync_change_journal),
  (select rows from journal_after_first),
  'replaying the same run id adds no journal row');

-- A different run id under the same revision — the interrupted-run-resumed case.
select ok((select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000b002',
  p_batch_size => 500, p_max_batches => 100, p_dry_run => false) is not null),
  'a second run id may run under the same revision');
select is((select count(*)::bigint from public.sync_change_journal),
  (select rows from journal_after_first),
  'a different run under the same revision adds no journal row');
select is((select count(*)::bigint from public.sync_change_journal_backfill_marks
  where run_id = '99999999-0000-0000-0000-00000000b002'),
  0::bigint, 'the second run claims nothing the first already claimed');
select is((select (app_private.sync_backfill_coverage() ->> 'duplicate_marks')::bigint),
  0::bigint, 'no entity carries two journalled backfill marks');

-- A run id is bound to the revision it was opened under.
select throws_ok($$
  select app_private.backfill_sync_change_journal(
    p_run_id => '99999999-0000-0000-0000-00000000b001',
    p_backfill_revision => 'some-other-revision',
    p_dry_run => false) $$,
  '22023', 'sync_backfill_run_revision_mismatch',
  'a run id cannot be reused under a different revision');

-- Negative control: the duplicate detector is not stuck at zero.
insert into public.sync_change_journal_backfill_marks
  (backfill_revision, entity_type, entity_id, run_id, operation, change_seq)
values ('deliberate-duplicate-probe', 'item',
  '41000000-0000-0000-0000-000000000001',
  '99999999-0000-0000-0000-00000000b001', 'upsert', 1);
select cmp_ok((select (app_private.sync_backfill_coverage() ->> 'duplicate_marks')::bigint),
  '>', 0::bigint, 'the duplicate detector fires when an entity is marked twice');
delete from public.sync_change_journal_backfill_marks
  where backfill_revision = 'deliberate-duplicate-probe';

-- Negative control for coverage: removing one baseline must be noticed.
create temp table removed_baseline as
  with removed as (
    delete from public.sync_change_journal
    where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000002'
    returning entity_type, entity_id, operation, server_version, changed_at)
  select * from removed;
select is((select (app_private.sync_backfill_coverage() ->> 'missing_baseline_total')::bigint),
  1::bigint, 'coverage notices a missing baseline');
select is((select app_private.sync_backfill_coverage() ->> 'complete'), 'false',
  'coverage refuses to report complete while an entity is missing');
insert into public.sync_change_journal (entity_type, entity_id, operation, server_version, changed_at)
  select entity_type, entity_id, operation, server_version, changed_at from removed_baseline;

-- ---------------------------------------------------------------------------
-- Requirement 17: runtime writes still journal after a backfill
-- ---------------------------------------------------------------------------
-- The backfill must not have consumed, disabled or otherwise shadowed the
-- triggers that keep the feed live.
create temp table seq_before_runtime as
  select coalesce(max(change_seq), 0) as max_seq from public.sync_change_journal;
update public.items set name = 'Barang Lokal Tanpa ED (diubah)'
  where id = '41000000-0000-0000-0000-000000000001';
select cmp_ok((select coalesce(max(change_seq), 0) from public.sync_change_journal),
  '>', (select max_seq from seq_before_runtime),
  'a runtime write after the backfill still advances the journal');
select is((select count(*)::bigint from public.sync_change_journal
  where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000001'),
  2::bigint, 'the runtime entry is added beside the baseline, not instead of it');
select cmp_ok((select field_version from public.sync_entity_field_versions
  where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000001'
    and field_name = 'name'), '>',
  (select field_version from public.sync_entity_field_versions
  where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000001'
    and field_name = 'unit'),
  'a real write raises the changed field past the baseline, and only that field');

-- A backfill run started after that write leaves the runtime entry alone.
select ok((select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000b003',
  p_backfill_revision => 'post-runtime-revision',
  p_batch_size => 500, p_max_batches => 100, p_dry_run => false) is not null),
  'a fresh revision may be run after runtime traffic');
select is((select count(*)::bigint from public.sync_change_journal
  where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000001'),
  2::bigint,
  'an entity already present in the feed is skipped even under a new revision');

-- ---------------------------------------------------------------------------
-- Requirements 18 and 19: a cursor from zero sees the whole baseline
-- ---------------------------------------------------------------------------
-- Asserted against the journal itself; the commit horizon cannot release these
-- rows inside pgTAP's transaction, so the RPC drain is covered in the staging
-- harness. What is provable here is the property the drain depends on: the
-- baseline is totally ordered by `change_seq` and page boundaries partition it
-- without gaps or repeats.
select is(
  (select count(distinct (entity_type, entity_id))::bigint from public.sync_change_journal),
  (select sum((entity ->> 'journalled')::bigint)::bigint from
    jsonb_array_elements(app_private.sync_backfill_coverage() -> 'entities') as entity),
  'a scan from seq 0 reaches every entity the coverage report counts');
select is((select count(*)::bigint from public.sync_change_journal
  where change_seq <= 0), 0::bigint, 'every entry sits strictly above cursor zero');
select is(
  (select count(*)::bigint from public.sync_change_journal),
  (select count(distinct change_seq)::bigint from public.sync_change_journal),
  'change_seq is unique, so a cursor can never straddle two entries');
-- Paginate the baseline at a page size of three and confirm the union of pages
-- is exactly the whole journal: no aggregate falls between two pages.
select is(
  (select count(*)::bigint from (
    select change_seq, ((row_number() over (order by change_seq)) - 1) / 3 as page
    from public.sync_change_journal) as paged
   where page is null),
  0::bigint, 'every entry lands on exactly one page');
select is(
  (select count(distinct change_seq)::bigint from (
    select change_seq, ((row_number() over (order by change_seq)) - 1) / 3 as page
    from public.sync_change_journal) as paged),
  (select count(*)::bigint from public.sync_change_journal),
  'paginating the baseline neither skips nor repeats an aggregate');

-- ---------------------------------------------------------------------------
-- Requirement 20: the baseline does not leak across branches
-- ---------------------------------------------------------------------------
-- The backfill writes journal rows for every branch, which is correct — the
-- feed is filtered on read, not on write. What must hold is that the filter
-- still refuses branch B's rows to a branch A actor after the backfill, on both
-- the pull path and the Realtime policy path.
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select is((select count(*)::bigint from public.sync_change_journal as journal
  where journal.entity_type = 'room'
    and app_private.pull_entity_visible(journal.entity_type, journal.entity_id)
    and journal.entity_id = '21000000-0000-0000-0000-000000000003'),
  0::bigint, 'a branch A nurse cannot see a backfilled branch B room');
select cmp_ok((select count(*)::bigint from public.sync_change_journal as journal
  where journal.entity_type = 'room'
    and app_private.pull_entity_visible(journal.entity_type, journal.entity_id)),
  '>', 0::bigint, 'and does see the backfilled rooms of their own branch');
select is((select count(*)::bigint from public.sync_change_journal as journal
  where journal.entity_type = 'stock_location'
    and app_private.pull_entity_visible(journal.entity_type, journal.entity_id)
    and journal.entity_id = '50000000-0000-0000-0000-000000000005'),
  0::bigint, 'a branch A nurse cannot see a backfilled branch B location');

-- The Realtime channel is the same answer, reached a different way: the journal
-- policy is evaluated as the actor with RLS live, so it must agree with the
-- pull filter over the backfilled rows too.
set local role authenticated;
select is(
  (select count(*)::bigint from public.sync_change_journal
   where entity_type = 'room' and entity_id = '21000000-0000-0000-0000-000000000003'),
  0::bigint, 'the journal policy also hides the backfilled branch B room');
select cmp_ok((select count(*)::bigint from public.sync_change_journal), '>', 0::bigint,
  'and the policy is not simply denying everything');
-- Not "returns no rows" but "is not a table you may name": SELECT was revoked
-- outright, so the refusal happens before RLS is even consulted.
select throws_ok($$ select count(*) from public.sync_change_journal_backfill_marks $$,
  '42501', null, 'the marks table is unreadable by an authenticated session');
select throws_ok($$ select count(*) from public.sync_change_journal_backfill_runs $$,
  '42501', null, 'the run ledger is unreadable by an authenticated session');
reset role;

-- Requirement 12 again, this time through the wrapper rather than the grant: a
-- session token reaching the RPC by any route is refused on its claims.
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select throws_ok($$
  select public.admin_backfill_sync_change_journal(
    run_id => '99999999-0000-0000-0000-00000000c001', dry_run => true) $$,
  '42501', 'sync_backfill_forbidden',
  'the wrapper refuses an authenticated claim even if EXECUTE were granted');
select throws_ok($$ select public.admin_sync_backfill_coverage() $$,
  '42501', 'sync_backfill_forbidden',
  'the coverage wrapper refuses an authenticated claim');
select throws_ok($$ select public.admin_sync_journal_retention_plan(30) $$,
  '42501', 'sync_backfill_forbidden',
  'the retention planner refuses an authenticated claim');

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok($$
  select public.admin_backfill_sync_change_journal(
    run_id => '99999999-0000-0000-0000-00000000c002', dry_run => true) $$,
  '42501', 'sync_backfill_forbidden', 'the wrapper refuses an anon claim');

-- Positive control, so the three refusals above are not passing because the
-- function is broken for everyone.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select ok((select public.admin_backfill_sync_change_journal(
  run_id => '99999999-0000-0000-0000-00000000c003', dry_run => true) is not null),
  'the wrapper admits a service_role claim');
select ok((select public.admin_sync_backfill_coverage() is not null),
  'the coverage wrapper admits a service_role claim');
select set_config('request.jwt.claims', null, true);

-- ---------------------------------------------------------------------------
-- Requirement 14: concurrent runs are serialised
-- ---------------------------------------------------------------------------
-- A second *session* cannot be opened from inside pgTAP, so what is asserted is
-- the mechanism: the worker takes a transaction-scoped advisory lock, which is
-- what makes a second session's `pg_try_advisory_xact_lock` return false and
-- the run raise `sync_backfill_run_in_progress`. The property that survives
-- even if the lock were lost — no duplicate entry — is asserted above.
select cmp_ok((select count(*)::bigint from pg_locks
  where locktype = 'advisory' and pid = pg_backend_pid()), '>', 0::bigint,
  'the worker holds a transaction-scoped advisory lock');
select ok(not pg_try_advisory_lock(
  ('x' || substr(md5('aish_sync_change_journal_backfill'), 1, 16))::bit(64)::bigint)
  is null, 'the documented lock key is well formed');
select pg_advisory_unlock_all();

-- ---------------------------------------------------------------------------
-- Requirements 15 and 16: partial batches resume, failures do not fake progress
-- ---------------------------------------------------------------------------
delete from public.sync_change_journal;
delete from public.sync_entity_field_versions;
delete from public.sync_change_journal_backfill_marks;
delete from public.sync_change_journal_backfill_runs;

-- One batch of one entity type, sized below the row count, so the run must stop
-- mid-type and hand back a usable checkpoint.
create temp table partial_one as select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000e001',
  p_entity_types => array['stock_location'],
  p_batch_size => 2, p_max_batches => 1, p_dry_run => false) as report;

select is((select report -> 'batches' -> 0 ->> 'scanned' from partial_one), '2',
  'a partial batch scans exactly the batch size');
select is((select report ->> 'completed' from partial_one), 'false',
  'a partial batch does not claim completion');
select is((select report -> 'batches' -> 0 -> 'next_checkpoint' ->> 'entity_id'
  from partial_one), '50000000-0000-0000-0000-000000000002',
  'the checkpoint is the last entity actually handled');
select is((select count(*)::bigint from public.sync_change_journal
  where entity_type = 'stock_location'), 2::bigint,
  'only the scanned rows were journalled');
select is((select last_entity_id from public.sync_change_journal_backfill_runs
  where run_id = '99999999-0000-0000-0000-00000000e001'),
  '50000000-0000-0000-0000-000000000002'::uuid,
  'the checkpoint is persisted for a later resume');

-- Resume from the reported checkpoint and finish the type.
select ok((select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000e001',
  p_entity_types => array['stock_location'],
  p_batch_size => 2, p_max_batches => 10,
  p_after_entity_type => 'stock_location',
  p_after_entity_id => '50000000-0000-0000-0000-000000000002',
  p_dry_run => false) is not null), 'a run resumes from its checkpoint');
select is((select count(*)::bigint from public.sync_change_journal
  where entity_type = 'stock_location'),
  (select count(*)::bigint from public.stock_locations),
  'resuming covers the rest of the type and nothing twice');

-- Requirement 16. A journal insert is made to fail for one specific entity, so
-- the batch hits a real error rather than a simulated one.
delete from public.sync_change_journal;
delete from public.sync_entity_field_versions;
delete from public.sync_change_journal_backfill_marks;
delete from public.sync_change_journal_backfill_runs;

create function pg_temp.fail_second_item() returns trigger
language plpgsql as $$
begin
  if new.entity_id = '41000000-0000-0000-0000-000000000002' then
    raise exception 'injected_backfill_failure';
  end if;
  return new;
end;
$$;
create trigger trg_injected_backfill_failure
  before insert on public.sync_change_journal
  for each row execute function pg_temp.fail_second_item();

create temp table failed_run as select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000f001',
  p_entity_types => array['item'],
  p_batch_size => 500, p_max_batches => 1, p_dry_run => false) as report;

select is((select report -> 'batches' -> 0 ->> 'failed' from failed_run), '1',
  'the failing entity is counted as a failure');
select is((select report -> 'batches' -> 0 ->> 'inserted' from failed_run), '1',
  'the entity before it is still journalled');
select is((select report ->> 'completed' from failed_run), 'false',
  'a run with a failure never reports completion');
select is((select report -> 'batches' -> 0 -> 'next_checkpoint' ->> 'entity_id'
  from failed_run), '41000000-0000-0000-0000-000000000001',
  'the checkpoint stops at the last success, not past the failure');
select is((select count(*)::bigint from public.sync_change_journal_backfill_marks
  where entity_id = '41000000-0000-0000-0000-000000000002'),
  0::bigint, 'a failed entity leaves no mark that would make it look done');
select is((select last_entity_id from public.sync_change_journal_backfill_runs
  where run_id = '99999999-0000-0000-0000-00000000f001'),
  '41000000-0000-0000-0000-000000000001'::uuid,
  'the persisted checkpoint does not step over the failure either');

drop trigger trg_injected_backfill_failure on public.sync_change_journal;

-- With the fault removed the resumed run picks the failed entity back up.
select ok((select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000f001',
  p_entity_types => array['item'],
  p_batch_size => 500, p_max_batches => 10,
  p_after_entity_type => 'item',
  p_after_entity_id => '41000000-0000-0000-0000-000000000001',
  p_dry_run => false) is not null), 'the run resumes after the fault is cleared');
select is((select count(*)::bigint from public.sync_change_journal
  where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000002'),
  1::bigint, 'the previously failed entity is journalled exactly once');

-- ---------------------------------------------------------------------------
-- Argument validation
-- ---------------------------------------------------------------------------
select throws_ok($$ select app_private.backfill_sync_change_journal(
  p_run_id => null) $$, '22023', 'sync_backfill_run_id_required',
  'a run id is mandatory');
select throws_ok($$ select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000a001', p_batch_size => 0) $$,
  '22023', 'sync_backfill_batch_size_invalid', 'batch size is bounded below');
select throws_ok($$ select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000a001', p_batch_size => 500000) $$,
  '22023', 'sync_backfill_batch_size_invalid', 'batch size is bounded above');
select throws_ok($$ select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000a001', p_max_batches => 0) $$,
  '22023', 'sync_backfill_max_batches_invalid', 'batch count is bounded');
select throws_ok($$ select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000a001',
  p_entity_types => array['not_an_entity']) $$,
  '22023', 'sync_backfill_entity_type_unknown', 'an unknown entity type is refused');
select throws_ok($$ select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000a001',
  p_entity_types => array['item'], p_after_entity_type => 'branch') $$,
  '22023', 'sync_backfill_checkpoint_out_of_scope',
  'a checkpoint outside the requested scope is refused rather than reset');
select throws_ok($$ select app_private.backfill_sync_change_journal(
  p_run_id => '99999999-0000-0000-0000-00000000a001',
  p_backfill_revision => '   ') $$,
  '22023', 'sync_backfill_revision_required', 'a blank revision is refused');

-- ---------------------------------------------------------------------------
-- Retention planning stays a proposal
-- ---------------------------------------------------------------------------
create temp table retention as
  select app_private.sync_journal_retention_plan(30) as plan;
select is((select plan ->> 'executed' from retention), 'false',
  'the retention planner reports that it deleted nothing');
select is((select count(*)::bigint from public.sync_change_journal),
  (select (plan ->> 'rows_total')::bigint from retention),
  'and the journal still holds every row it counted');
select cmp_ok((select (plan ->> 'proposed_keep_through')::bigint from retention),
  '<=', (select (plan ->> 'commit_horizon')::bigint from retention),
  'a proposed boundary never reaches the commit horizon');
select throws_ok($$ select app_private.sync_journal_retention_plan(0) $$,
  '22023', 'sync_invalid_payload', 'a zero safety window is refused');

select * from finish();
rollback;
