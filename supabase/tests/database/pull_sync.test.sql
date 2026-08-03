-- Milestone 12C: deterministic pull contract, scope isolation, tombstones and
-- the RLS/visibility equivalence that keeps `pull_entity_visible` honest.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- ---------------------------------------------------------------------------
-- Structure, grants and privacy
-- ---------------------------------------------------------------------------
select has_table('public', 'sync_change_journal', 'change journal exists');
select has_table('public', 'sync_entity_field_versions', 'field version registry exists');
select is((select revision from app_meta.schema_revisions order by applied_at desc limit 1),
  'aish-supabase-003', 'revision 003 is latest');

select ok(has_function_privilege('authenticated', 'public.pull_sync_changes(bigint,integer,uuid,text[])', 'EXECUTE'),
  'authenticated can call the pull contract');
select ok(not has_function_privilege('anon', 'public.pull_sync_changes(bigint,integer,uuid,text[])', 'EXECUTE'),
  'anon cannot call the pull contract');
select ok(not has_function_privilege('authenticated', 'app_private.pull_entity_payload(text,uuid)', 'EXECUTE'),
  'payload builder is private');
select ok(not has_function_privilege('authenticated', 'app_private.pull_commit_horizon()', 'EXECUTE'),
  'commit horizon helper is private');
select ok(not has_function_privilege('authenticated', 'app_private.prune_sync_change_journal(bigint)', 'EXECUTE'),
  'retention helper is private');
select ok(not has_function_privilege('authenticated', 'app_private.record_sync_change()', 'EXECUTE'),
  'journal trigger function is private');

-- The visibility oracle in particular. `pull_sync_changes` is SECURITY DEFINER
-- and reaches it as the owner, so no client role needs — or gets — EXECUTE.
-- Granting it would let a direct connection ask "does entity X exist and may I
-- see it" for any guessed id, which is the one question the pull contract is
-- built to answer only through a cursor.
select ok(not has_function_privilege('authenticated', 'app_private.pull_entity_visible(text,uuid)', 'EXECUTE'),
  'authenticated cannot execute the private visibility helper');
select ok(not has_function_privilege('anon', 'app_private.pull_entity_visible(text,uuid)', 'EXECUTE'),
  'anon cannot execute the private visibility helper');
select ok(not has_function_privilege('public', 'app_private.pull_entity_visible(text,uuid)', 'EXECUTE'),
  'PUBLIC cannot execute the private visibility helper');
select ok(not has_function_privilege('authenticated', 'app_private.pull_scope_fingerprint()', 'EXECUTE'),
  'scope fingerprint helper is private');

-- Every helper this migration adds to `app_private`, checked as a set so a new
-- one cannot be introduced with the PUBLIC default EXECUTE still in place.
select is(
  (select coalesce(string_agg(signature, ', ' order by signature), '') from unnest(array[
    'app_private.pull_entity_type_for_table(text)',
    'app_private.pull_table_for_entity_type(text)',
    'app_private.pull_mergeable_fields(text)',
    'app_private.pull_entity_visible(text,uuid)',
    'app_private.pull_entity_payload(text,uuid)',
    'app_private.pull_scope_fingerprint()',
    'app_private.pull_commit_horizon()',
    'app_private.prune_sync_change_journal(bigint)',
    'app_private.reject_journal_update()',
    'app_private.record_field_versions()',
    'app_private.record_sync_change()',
    'app_private.record_sync_change_for_parent()'
  ]) as signature
  where has_function_privilege('authenticated', signature, 'EXECUTE')
     or has_function_privilege('anon', signature, 'EXECUTE')
     or has_function_privilege('public', signature, 'EXECUTE')),
  '', 'no revision 003 private helper is executable by a client role');

-- The client-facing surface of this migration is the RPC and nothing else.
select ok(has_function_privilege('authenticated', 'public.pull_sync_changes(bigint,integer,uuid,text[])', 'EXECUTE'),
  'authenticated can execute the public pull RPC');
select is((select count(*)::bigint from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app_private' and p.proname like 'pull\_%'
    and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  0::bigint, 'no app_private pull helper is reachable by authenticated');

-- Acceptance 9: the journal cannot be manipulated by a client.
select ok(not has_table_privilege('authenticated', 'public.sync_change_journal', 'INSERT'),
  'client cannot insert a journal row');
select ok(not has_table_privilege('authenticated', 'public.sync_change_journal', 'UPDATE'),
  'client cannot update a journal row');
select ok(not has_table_privilege('authenticated', 'public.sync_change_journal', 'DELETE'),
  'client cannot delete a journal row');
select ok(not has_table_privilege('authenticated', 'public.sync_entity_field_versions', 'SELECT'),
  'client cannot read raw field versions outside the pull contract');
select is((select count(*)::bigint from pg_policies
  where schemaname = 'public' and tablename = 'sync_change_journal' and cmd <> 'SELECT'),
  0::bigint, 'journal has no client write policy');
select ok((select relforcerowsecurity from pg_class where oid = 'public.sync_change_journal'::regclass),
  'journal forces row level security');

-- Acceptance: every SECURITY DEFINER function added here keeps a hardened path.
select is((select count(*)::bigint from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'app_private') and p.prosecdef
    and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%'),
  0::bigint, 'all security definer functions still fix search_path');

-- Acceptance 10: the ledger stays append-only with the journal trigger attached.
-- The guard is a row trigger, so it needs a row to fire on.
insert into public.stock_movements
  (id, created_at, updated_at, sync_status, item_id, from_location_id, to_location_id,
   qty, movement_type, ref_doc_type, ref_doc_id, actor_user_id)
values ('cf000000-0000-0000-0000-000000000001', now(), now(), 'synced',
  '41000000-0000-0000-0000-000000000001', null, '50000000-0000-0000-0000-000000000001',
  1000, 'opname_adjustment', 'SO', 'cf000000-0000-0000-0000-0000000000ff',
  '30000000-0000-0000-0000-000000000003');
select throws_ok(
  $$update public.stock_movements set qty = qty + 1
    where id = 'cf000000-0000-0000-0000-000000000001'$$,
  '55000', null, 'ledger update is still refused');
select throws_ok(
  $$delete from public.stock_movements
    where id = 'cf000000-0000-0000-0000-000000000001'$$,
  '55000', null, 'ledger delete is still refused');

-- A journal row is a record of something that happened and is never edited.
insert into public.item_categories (id, created_at, updated_at, sync_status, name)
values ('c0000000-0000-0000-0000-000000000001', now(), now(), 'synced', 'Jurnal Uji');
select throws_ok(
  $$update public.sync_change_journal set entity_id = gen_random_uuid()
    where entity_id = 'c0000000-0000-0000-0000-000000000001'$$,
  '55000', 'sync_change_journal is immutable', 'journal rows are immutable');

-- ---------------------------------------------------------------------------
-- Acceptance 1: equal timestamps still order deterministically
-- ---------------------------------------------------------------------------
-- Both rows are written by one statement, so `statement_timestamp()` — the value
-- the server-metadata trigger uses — is identical for them. Only `change_seq`
-- separates the two.
insert into public.item_categories (id, created_at, updated_at, sync_status, name)
values ('c0000000-0000-0000-0000-000000000002', now(), now(), 'synced', 'Serentak A'),
       ('c0000000-0000-0000-0000-000000000003', now(), now(), 'synced', 'Serentak B');

select is((select count(distinct changed_at)::bigint from public.sync_change_journal
  where entity_id in ('c0000000-0000-0000-0000-000000000002',
                      'c0000000-0000-0000-0000-000000000003')),
  1::bigint, 'the two simultaneous changes share one timestamp');
select is((select count(distinct change_seq)::bigint from public.sync_change_journal
  where entity_id in ('c0000000-0000-0000-0000-000000000002',
                      'c0000000-0000-0000-0000-000000000003')),
  2::bigint, 'the two simultaneous changes still have distinct sequence numbers');

-- ---------------------------------------------------------------------------
-- Tombstone journalling
-- ---------------------------------------------------------------------------
update public.item_categories set deleted_at = now()
  where id = 'c0000000-0000-0000-0000-000000000003';
select is((select operation from public.sync_change_journal
  where entity_id = 'c0000000-0000-0000-0000-000000000003'
  order by change_seq desc limit 1),
  'tombstone', 'a first soft delete journals a tombstone');

update public.item_categories set name = 'Serentak B2'
  where id = 'c0000000-0000-0000-0000-000000000003';
select is((select operation from public.sync_change_journal
  where entity_id = 'c0000000-0000-0000-0000-000000000003'
  order by change_seq desc limit 1),
  'upsert', 'editing an already deleted row is not a second tombstone');

-- Deactivation is a field change, never a tombstone (G-A4).
update public.items set is_active = false
  where id = '41000000-0000-0000-0000-000000000002';
select is((select operation from public.sync_change_journal
  where entity_id = '41000000-0000-0000-0000-000000000002'
  order by change_seq desc limit 1),
  'upsert', 'is_active = false is an upsert, not a tombstone');

-- ---------------------------------------------------------------------------
-- Field versions are server-computed and only move on real change
-- ---------------------------------------------------------------------------
select is((select field_version from public.sync_entity_field_versions
  where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000002'
    and field_name = 'is_active'),
  (select server_version from public.items where id = '41000000-0000-0000-0000-000000000002'),
  'a changed field takes the entity server version');
select ok((select field_version from public.sync_entity_field_versions
    where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000002'
      and field_name = 'name')
  < (select field_version from public.sync_entity_field_versions
    where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000002'
      and field_name = 'is_active'),
  'an untouched field keeps its older version');

-- A no-op update must not move any field version.
select public.items.server_version as before_version
  into temporary table pull_noop_probe from public.items
  where public.items.id = '41000000-0000-0000-0000-000000000001';
update public.items set name = name where id = '41000000-0000-0000-0000-000000000001';
select is((select count(*)::bigint from public.sync_entity_field_versions
  where entity_type = 'item' and entity_id = '41000000-0000-0000-0000-000000000001'
    and field_version > (select before_version from pull_noop_probe)),
  0::bigint, 'a write that changes no value moves no field version');

-- Server-controlled and immutable columns are never offered for merging.
select ok(not ('sku' = any(app_private.pull_mergeable_fields('item'))),
  'the natural key is not mergeable');
select ok(not ('server_version' = any(app_private.pull_mergeable_fields('item'))),
  'server-controlled columns are not mergeable');
select ok(not ('code' = any(app_private.pull_mergeable_fields('branch'))),
  'branch code is immutable, not mergeable');
select is(array_length(app_private.pull_mergeable_fields('consumption'), 1), null,
  'a posting document exposes no mergeable field at all');
select is(array_length(app_private.pull_mergeable_fields('stock_movement'), 1), null,
  'the ledger exposes no mergeable field at all');

-- The client half of this list lives in `SyncEntityPolicies` and is pinned by
-- `test/sync/sync_entity_policy_test.dart`. Both sides are stated literally on
-- purpose: a client that merges a column the server does not version has no
-- ordering to merge by, and a server that versions a column the client never
-- merges is dead weight nobody notices. Changing one alone fails one suite.
select is(app_private.pull_mergeable_fields('branch'),
  array['name', 'address', 'is_active'], 'branch mergeable list is pinned');
select is(app_private.pull_mergeable_fields('room'),
  array['code', 'name', 'is_active'], 'room mergeable list is pinned');
select is(app_private.pull_mergeable_fields('user'),
  array['full_name', 'role', 'branch_id', 'is_active'],
  'user mergeable list is pinned');
select is(app_private.pull_mergeable_fields('category'),
  array['name'], 'category mergeable list is pinned');
select is(app_private.pull_mergeable_fields('item'),
  array['name', 'category_id', 'unit', 'min_stock_room', 'min_stock_branch',
    'expiry_alert_days', 'is_active'], 'item mergeable list is pinned');
select is(app_private.pull_mergeable_fields('batch'),
  array['expiry_date'], 'batch mergeable list is pinned');
select is(app_private.pull_mergeable_fields('stock_location'),
  array['name'], 'stock location mergeable list is pinned');

-- ---------------------------------------------------------------------------
-- Fixtures used by the authenticated pull assertions
-- ---------------------------------------------------------------------------
insert into public.sync_devices (id, actor_user_id, app_install_id)
values
  ('81000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-000000000001', 'pull-nurse'),
  ('81000000-0000-0000-0000-0000000000a2', '30000000-0000-0000-0000-000000000002', 'pull-head-a'),
  ('81000000-0000-0000-0000-0000000000a3', '30000000-0000-0000-0000-000000000003', 'pull-warehouse'),
  ('81000000-0000-0000-0000-0000000000a4', '30000000-0000-0000-0000-000000000004', 'pull-admin');

-- A branch head for branch B, so cross-branch isolation has two real sides.
insert into public.users (id, created_at, updated_at, sync_status, full_name, email, role, branch_id, is_active)
values ('30000000-0000-0000-0000-0000000000b1', now(), now(), 'synced',
  'Kepala Cabang Lokal B', 'branchhead.b.local@example.test', 'kepala_cabang',
  '20000000-0000-0000-0000-000000000002', true);
insert into public.user_auth_links (auth_user_id, user_id)
values ('10000000-0000-0000-0000-000000000006', '30000000-0000-0000-0000-0000000000b1');
insert into public.sync_devices (id, actor_user_id, app_install_id)
values ('81000000-0000-0000-0000-0000000000a5', '30000000-0000-0000-0000-0000000000b1', 'pull-head-b');

-- One document per branch, so "cabang A tidak melihat cabang B" has something
-- concrete to be true about.
insert into public.purchase_requests
  (id, created_at, updated_at, sync_status, doc_number, branch_id, requested_by, status, submitted_at)
values
  ('e0000000-0000-0000-0000-00000000000a', now(), now(), 'synced', 'PR-PULL-A',
   '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', 'submitted', now()),
  ('e0000000-0000-0000-0000-00000000000b', now(), now(), 'synced', 'PR-PULL-B',
   '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-0000000000b1', 'submitted', now());

-- ---------------------------------------------------------------------------
-- The commit horizon holds back this transaction's own uncommitted changes
-- ---------------------------------------------------------------------------
-- pgTAP runs inside one transaction, so every row inserted above is still in
-- flight from the server's point of view. That is exactly the case the horizon
-- exists for: a reader must not step over a sequence number whose transaction
-- has not settled, because that number would otherwise be lost forever.
select ok(app_private.pull_commit_horizon() <
  (select min(change_seq) from public.sync_change_journal
   where entity_id = 'c0000000-0000-0000-0000-000000000001'),
  'the horizon stops below this transaction''s own uncommitted entries');

-- A posted document with a real ledger movement, for the payload assertions.
insert into public.consumptions
  (id, created_at, updated_at, sync_status, doc_number, branch_id, room_id,
   created_by, status, posted_by, posted_at)
values ('e2000000-0000-0000-0000-00000000000a', now(), now(), 'synced', 'CNS-PULL-A',
  '20000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001', 'posted',
  '30000000-0000-0000-0000-000000000001', now());
insert into public.consumption_lines
  (id, created_at, updated_at, sync_status, consumption_id, item_id, qty)
values ('e2000000-0000-0000-0000-00000000000b', now(), now(), 'synced',
  'e2000000-0000-0000-0000-00000000000a', '41000000-0000-0000-0000-000000000001', 1000);
insert into public.stock_movements
  (id, created_at, updated_at, sync_status, item_id, from_location_id, to_location_id,
   qty, movement_type, ref_doc_type, ref_doc_id, actor_user_id)
values ('e2000000-0000-0000-0000-00000000000c', now(), now(), 'synced',
  '41000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000004', null,
  1000, 'consumption', 'CONS', 'e2000000-0000-0000-0000-00000000000a',
  '30000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------
-- Acceptance 5 and 6: branch and role isolation over the real RPC
-- ---------------------------------------------------------------------------
-- These use committed seed rows, so the horizon admits them and the assertions
-- exercise the whole pull path rather than the visibility helper alone.
create function pg_temp.pull_ids(claims text, device uuid, wanted_type text)
returns uuid[]
language plpgsql
as $$
declare result uuid[];
begin
  perform set_config('request.jwt.claims', claims, true);
  select coalesce(array_agg(distinct (change ->> 'entity_id')::uuid), array[]::uuid[])
    into result
    from jsonb_array_elements(
      public.pull_sync_changes(0, 500, device, array[wanted_type]) -> 'changes') as change;
  return result;
end;
$$;

set local role authenticated;

select ok('21000000-0000-0000-0000-000000000001' = any(pg_temp.pull_ids(
    '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
    '81000000-0000-0000-0000-0000000000a2', 'room')),
  'branch A head pulls a branch A room');
select ok(not ('21000000-0000-0000-0000-000000000003' = any(pg_temp.pull_ids(
    '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
    '81000000-0000-0000-0000-0000000000a2', 'room'))),
  'branch A head never sees a branch B room');
select ok(not ('20000000-0000-0000-0000-000000000002' = any(pg_temp.pull_ids(
    '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
    '81000000-0000-0000-0000-0000000000a2', 'branch'))),
  'branch A head never sees the branch B row itself');
select ok('20000000-0000-0000-0000-000000000002' = any(pg_temp.pull_ids(
    '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
    '81000000-0000-0000-0000-0000000000a3', 'branch')),
  'warehouse pulls every branch by design');

-- A location outside the caller's scope is not merely hidden from the payload:
-- the change never appears, so its existence cannot be inferred.
select ok(not ('50000000-0000-0000-0000-000000000003' = any(pg_temp.pull_ids(
    '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
    '81000000-0000-0000-0000-0000000000a2', 'stock_location'))),
  'branch A head never sees the branch B store location');
select ok(not ('50000000-0000-0000-0000-000000000002' = any(pg_temp.pull_ids(
    '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
    '81000000-0000-0000-0000-0000000000a1', 'stock_location'))),
  'a nurse never sees the branch store location');

-- Acceptance 6 restated on identity: a nurse sees only their own user row.
select is(pg_temp.pull_ids(
    '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
    '81000000-0000-0000-0000-0000000000a1', 'user'),
  array['30000000-0000-0000-0000-000000000001']::uuid[],
  'a nurse pulls only their own identity row');

reset role;

-- ---------------------------------------------------------------------------
-- Document scope, proven on the filter the pull path actually uses
-- ---------------------------------------------------------------------------
-- The documents above belong to this uncommitted transaction, so the RPC cannot
-- return them yet. `pull_entity_visible` is the predicate the RPC applies, and
-- the equivalence block below pins it to RLS, so asserting on it here is the
-- same statement about scope without waiting for a commit. The end-to-end
-- document pull is covered by `tool/supabase_12c_e2e.ts` over real sessions.
--
-- These run as the owner rather than as `authenticated`: the helper is revoked
-- from every client role. That does not weaken the assertion, because the
-- helper is SECURITY DEFINER and resolves the actor from `request.jwt.claims`
-- rather than from the database role, so only the claims below decide the
-- answer. The claims are transaction local and survive the role reset above.
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select ok(app_private.pull_entity_visible('purchase_request', 'e0000000-0000-0000-0000-00000000000a'),
  'branch A head may read the branch A request');
select ok(not app_private.pull_entity_visible('purchase_request', 'e0000000-0000-0000-0000-00000000000b'),
  'branch A head may not read the branch B request');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}', true);
select ok(not app_private.pull_entity_visible('purchase_request', 'e0000000-0000-0000-0000-00000000000a'),
  'branch B head may not read the branch A request');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select ok(not app_private.pull_entity_visible('purchase_request', 'e0000000-0000-0000-0000-00000000000a'),
  'a nurse cannot learn that a purchase request exists at all');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select ok(app_private.pull_entity_visible('purchase_request', 'e0000000-0000-0000-0000-00000000000a'),
  'warehouse may read requests across branches by design');
select ok(not app_private.pull_entity_visible('purchase_request', gen_random_uuid()),
  'an unknown id is invisible rather than an error');
select ok(not app_private.pull_entity_visible('not_an_entity', 'e0000000-0000-0000-0000-00000000000a'),
  'an unknown entity type is refused outright');

-- And the privilege that keeps it that way, proven by execution rather than by
-- catalogue lookup: the same call as the caller's own role is refused.
set local role authenticated;
select throws_ok(
  $$select app_private.pull_entity_visible('purchase_request', 'e0000000-0000-0000-0000-00000000000a')$$,
  '42501', 'permission denied for function pull_entity_visible',
  'the visibility helper is unreachable from the authenticated role');
reset role;

-- ---------------------------------------------------------------------------
-- The equivalence that keeps `pull_entity_visible` from drifting off RLS
-- ---------------------------------------------------------------------------
-- For every entity type and every fixture actor, the id set RLS returns must
-- equal the id set the pull filter admits. This is what makes restating the
-- policies inside a SECURITY DEFINER function safe over time.
-- The table mapping is restated here rather than read from
-- `app_private.pull_table_for_entity_type`, which is revoked from every client
-- role. The RLS side must run *as* the authenticated actor so that RLS applies;
-- the filter side runs as the owner because `pull_entity_visible` is revoked
-- too, and it reads the actor from the claims rather than from the role.
create function pg_temp.entity_table(wanted_type text)
returns text
language sql
immutable
as $$
  select case wanted_type
    when 'branch' then 'branches' when 'room' then 'rooms'
    when 'user' then 'users' when 'category' then 'item_categories'
    when 'item' then 'items' when 'batch' then 'item_batches'
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
  end;
$$;

create function pg_temp.rls_ids(wanted_type text)
returns uuid[]
language plpgsql
as $$
declare result uuid[];
begin
  execute format(
    'select coalesce(array_agg(entity.id order by entity.id), array[]::uuid[]) '
    'from public.%I as entity', pg_temp.entity_table(wanted_type)) into result;
  return result;
end;
$$;

create function pg_temp.visible_ids(wanted_type text)
returns uuid[]
language plpgsql
as $$
declare result uuid[];
begin
  execute format(
    'select coalesce(array_agg(entity.id order by entity.id), array[]::uuid[]) '
    'from public.%I as entity where app_private.pull_entity_visible($1, entity.id)',
    pg_temp.entity_table(wanted_type)) into result using wanted_type;
  return result;
end;
$$;

do $$
declare
  actor record;
  wanted_type text;
  rls_result uuid[];
  filter_result uuid[];
begin
  for actor in
    select * from (values
      ('nurse', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}'),
      ('branch head A', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}'),
      ('warehouse', '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}'),
      ('super admin', '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}'),
      ('branch head B', '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}')
    ) as t(label, claims)
  loop
    foreach wanted_type in array array[
      'branch', 'room', 'user', 'category', 'item', 'batch', 'stock_location',
      'stock_balance', 'stock_movement', 'stock_opname', 'purchase_request',
      'delivery_order', 'good_receipt', 'distribution', 'disposal',
      'consumption', 'goods_return'
    ] loop
      set local role authenticated;
      perform set_config('request.jwt.claims', actor.claims, true);
      rls_result := pg_temp.rls_ids(wanted_type);
      reset role;
      filter_result := pg_temp.visible_ids(wanted_type);
      if rls_result is distinct from filter_result then
        raise exception
          'pull_entity_visible diverged from RLS for % / %: rls=% filter=%',
          actor.label, wanted_type, rls_result, filter_result;
      end if;
    end loop;
  end loop;
end;
$$;

select pass('pull_entity_visible matches RLS for every entity type and fixture actor');

-- ---------------------------------------------------------------------------
-- The Realtime channel keeps its scope without a grant on the private helper
-- ---------------------------------------------------------------------------
-- `sync_change_journal_read_scope` states the visibility predicate as an
-- existence probe rather than as a call to `pull_entity_visible`, because a
-- policy expression runs with the privileges of the querying role and that
-- helper is revoked from every client role. The two must still admit exactly
-- the same journal rows: the policy is what decides which INSERTs Realtime
-- delivers, and a row admitted here that the pull filter would drop is a
-- cross-scope metadata leak.
create function pg_temp.journal_policy_seqs()
returns bigint[]
language sql
as $$
  select coalesce(array_agg(journal.change_seq order by journal.change_seq),
    array[]::bigint[])
  from public.sync_change_journal as journal;
$$;

create function pg_temp.journal_filter_seqs()
returns bigint[]
language sql
as $$
  select coalesce(array_agg(journal.change_seq order by journal.change_seq),
    array[]::bigint[])
  from public.sync_change_journal as journal
  where app_private.current_user_is_active()
    and app_private.pull_entity_visible(journal.entity_type, journal.entity_id);
$$;

do $$
declare
  actor record;
  policy_result bigint[];
  filter_result bigint[];
  delivered integer := 0;
begin
  for actor in
    select * from (values
      ('nurse', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}'),
      ('branch head A', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}'),
      ('warehouse', '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}'),
      ('super admin', '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}'),
      ('branch head B', '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}'),
      ('inactive', '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}')
    ) as t(label, claims)
  loop
    set local role authenticated;
    perform set_config('request.jwt.claims', actor.claims, true);
    policy_result := pg_temp.journal_policy_seqs();
    reset role;
    filter_result := pg_temp.journal_filter_seqs();
    if policy_result is distinct from filter_result then
      raise exception
        'journal policy diverged from the pull filter for %: policy=% filter=%',
        actor.label, policy_result, filter_result;
    end if;
    delivered := delivered + coalesce(array_length(policy_result, 1), 0);
  end loop;
  -- Equivalence alone would also hold if the policy admitted nothing at all,
  -- which is exactly how a missing privilege would look. It does not.
  if delivered = 0 then
    raise exception 'the journal policy delivered no row to any fixture actor';
  end if;
end;
$$;

select pass('the journal read policy admits exactly the rows the pull filter admits');

-- An inactive actor is woken by nothing, and a scope boundary holds on the
-- Realtime channel itself rather than only inside the RPC.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}', true);
select is((select count(*)::bigint from public.sync_change_journal), 0::bigint,
  'a deactivated actor reads no journal row at all');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select isnt((select count(*)::bigint from public.sync_change_journal), 0::bigint,
  'an active actor still receives the realtime invalidation feed');
select is((select count(*)::bigint from public.sync_change_journal
  where entity_type = 'room' and entity_id = '21000000-0000-0000-0000-000000000003'),
  0::bigint, 'the branch A head is never woken by a branch B room change');
reset role;

-- ---------------------------------------------------------------------------
-- Acceptance 2, 3 and 4: pagination, repeatability and cursor validation
-- ---------------------------------------------------------------------------
create function pg_temp.pull_seqs(device uuid, from_cursor bigint, size integer)
returns bigint[]
language sql
as $$
  select coalesce(array_agg((change ->> 'change_seq')::bigint order by
    (change ->> 'change_seq')::bigint), array[]::bigint[])
  from jsonb_array_elements(
    public.pull_sync_changes(from_cursor, size, device) -> 'changes') as change;
$$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}', true);

-- Acceptance 3: the same cursor against the same server state answers the same.
select is(pg_temp.pull_seqs('81000000-0000-0000-0000-0000000000a4', 0, 7),
  pg_temp.pull_seqs('81000000-0000-0000-0000-0000000000a4', 0, 7),
  'the same cursor yields an identical batch');

-- Acceptance 2: walking in pages of 3 visits every sequence exactly once and
-- reaches the same place a single large page does.
do $$
declare
  cursor_value bigint := 0;
  response jsonb;
  walked bigint[] := array[]::bigint[];
  whole bigint[];
  guard integer := 0;
begin
  loop
    guard := guard + 1;
    if guard > 200 then raise exception 'pagination did not terminate'; end if;
    response := public.pull_sync_changes(cursor_value, 3, '81000000-0000-0000-0000-0000000000a4');
    select walked || coalesce(array_agg((change ->> 'change_seq')::bigint), array[]::bigint[])
      into walked from jsonb_array_elements(response -> 'changes') as change;
    cursor_value := (response ->> 'next_cursor')::bigint;
    exit when not (response ->> 'has_more')::boolean;
  end loop;
  select coalesce(array_agg((change ->> 'change_seq')::bigint order by
    (change ->> 'change_seq')::bigint), array[]::bigint[]) into whole
    from jsonb_array_elements(
      public.pull_sync_changes(0, 500, '81000000-0000-0000-0000-0000000000a4') -> 'changes') as change;
  if walked is distinct from whole then
    raise exception 'paged walk % differs from single page %', walked, whole;
  end if;
  if array_length(walked, 1) is distinct from
    array_length((select array_agg(distinct value) from unnest(walked) as value), 1) then
    raise exception 'paged walk repeated a change';
  end if;
end;
$$;

select pass('paging with a small limit loses no change and duplicates none');

-- has_more is honest at the boundary rather than optimistic.
select is((public.pull_sync_changes(0, 500, '81000000-0000-0000-0000-0000000000a4') ->> 'has_more')::boolean,
  false, 'a page that drains the feed reports no more');

-- Acceptance 4: invalid cursor and scope mismatch fail with a safe code.
select throws_ok(
  $$select public.pull_sync_changes(-1, 10, '81000000-0000-0000-0000-0000000000a4')$$,
  '22023', 'sync_cursor_invalid', 'a negative cursor is refused');
select throws_ok(
  $$select public.pull_sync_changes(9223372036854775806, 10, '81000000-0000-0000-0000-0000000000a4')$$,
  '22023', 'sync_cursor_invalid', 'a cursor beyond the feed is refused');
select throws_ok(
  $$select public.pull_sync_changes(0, 0, '81000000-0000-0000-0000-0000000000a4')$$,
  '22023', 'sync_invalid_payload', 'a zero batch limit is refused');
select throws_ok(
  $$select public.pull_sync_changes(0, 501, '81000000-0000-0000-0000-0000000000a4')$$,
  '22023', 'sync_invalid_payload', 'an oversized batch limit is refused');
select throws_ok(
  $$select public.pull_sync_changes(0, 10, null)$$,
  '42501', 'sync_access_denied', 'a missing device is refused');
select throws_ok(
  $$select public.pull_sync_changes(0, 10, '81000000-0000-0000-0000-0000000000a1')$$,
  '42501', 'sync_access_denied', 'another actor''s device is refused');

-- The scope fingerprint separates one authorization scope from another.
select isnt(
  (public.pull_sync_changes(0, 1, '81000000-0000-0000-0000-0000000000a4') ->> 'scope_fingerprint'),
  null, 'the response carries a scope fingerprint');
reset role;

do $$
declare admin_print text; head_print text;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
  admin_print := public.pull_sync_changes(0, 1, '81000000-0000-0000-0000-0000000000a4') ->> 'scope_fingerprint';
  perform set_config('request.jwt.claims',
    '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
  head_print := public.pull_sync_changes(0, 1, '81000000-0000-0000-0000-0000000000a2') ->> 'scope_fingerprint';
  reset role;
  if admin_print = head_print then
    raise exception 'two different scopes share a fingerprint';
  end if;
end;
$$;

select pass('two different scopes never share a fingerprint');

-- ---------------------------------------------------------------------------
-- Acceptance 7: tombstones are journalled and scoped
-- ---------------------------------------------------------------------------
update public.item_batches set deleted_at = now()
  where id = '42000000-0000-0000-0000-000000000001';
select is((select operation from public.sync_change_journal
  where entity_type = 'batch' and entity_id = '42000000-0000-0000-0000-000000000001'
  order by change_seq desc limit 1),
  'tombstone', 'a soft deleted batch is journalled as a tombstone');

-- A branch-scoped tombstone stays inside its branch: the tombstone is nothing
-- more than a journal entry, and the same visibility filter applies to it.
update public.rooms set deleted_at = now()
  where id = '21000000-0000-0000-0000-000000000003';
-- As above: owner role, actor from the claims, because the helper is private.
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select ok(not app_private.pull_entity_visible('room', '21000000-0000-0000-0000-000000000003'),
  'a branch B room tombstone is invisible to the branch A head');
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}', true);
select ok(app_private.pull_entity_visible('room', '21000000-0000-0000-0000-000000000003'),
  'the branch B head does receive their own room tombstone');

-- ---------------------------------------------------------------------------
-- Payload completeness: a document always arrives whole
-- ---------------------------------------------------------------------------
-- Asserted on the payload builder directly. It is the single place the RPC gets
-- a payload from, and unlike the RPC it is not bounded by the commit horizon,
-- so the fixtures above are readable here.
select ok(app_private.pull_entity_payload('purchase_request',
    'e0000000-0000-0000-0000-00000000000a') ? 'lines',
  'a document payload always carries its lines');
select ok(app_private.pull_entity_payload('purchase_request',
    'e0000000-0000-0000-0000-00000000000a') ? 'opname_links',
  'a purchase request payload always carries its opname links');
-- A purchase request never posts to the ledger (spec §2.5), so it carries no
-- movement collection at all. A posting document does.
select ok(not (app_private.pull_entity_payload('purchase_request',
    'e0000000-0000-0000-0000-00000000000a') ? 'movements'),
  'a purchase request payload carries no movements');
select ok(app_private.pull_entity_payload('consumption',
    'e2000000-0000-0000-0000-00000000000a') ? 'movements',
  'a posting document payload always carries its movements');
select is(jsonb_array_length(app_private.pull_entity_payload('consumption',
    'e2000000-0000-0000-0000-00000000000a') -> 'movements'), 1,
  'the posting document carries exactly the movement it posted');
select is(app_private.pull_entity_payload('purchase_request',
    'e0000000-0000-0000-0000-00000000000a') ->> 'doc_number',
  'PR-PULL-A', 'the server document number travels with the document');
select is(app_private.pull_entity_payload('purchase_request', gen_random_uuid()),
  null, 'a payload for a missing entity is null rather than a half document');
select ok(not (app_private.pull_entity_payload('item',
    '41000000-0000-0000-0000-000000000001') ? 'lines'),
  'a master payload carries no line collection');

-- ---------------------------------------------------------------------------
-- A line edit republishes its parent, so no partial document can be applied
-- ---------------------------------------------------------------------------
insert into public.purchase_request_lines
  (id, created_at, updated_at, sync_status, pr_id, item_id, suggested_qty, requested_qty)
values ('e1000000-0000-0000-0000-00000000000a', now(), now(), 'synced',
  'e0000000-0000-0000-0000-00000000000a', '41000000-0000-0000-0000-000000000001', 1000, 2000);
select is((select entity_type from public.sync_change_journal
  order by change_seq desc limit 1),
  'purchase_request', 'a line insert is journalled against its parent document');
select is((select count(*)::bigint from public.sync_change_journal
  where entity_type = 'purchase_request_line'),
  0::bigint, 'lines never appear as their own entity type');

-- ---------------------------------------------------------------------------
-- Commit horizon
-- ---------------------------------------------------------------------------
select ok(app_private.pull_commit_horizon() <=
  (select coalesce(max(change_seq), 0) from public.sync_change_journal),
  'the commit horizon never runs ahead of the journal');
select ok(app_private.pull_commit_horizon() >= 0, 'the commit horizon is non-negative');

select * from finish();
rollback;
