begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

select is(
  (
    select count(*)::bigint
    from pg_class as relation
    join pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = any (array[
        'branches', 'rooms', 'users', 'user_auth_links', 'item_categories', 'items',
        'item_batches', 'stock_locations', 'stock_balances', 'stock_movements',
        'stock_opnames', 'stock_opname_lines', 'purchase_requests',
        'purchase_request_opnames', 'purchase_request_lines', 'delivery_orders',
        'delivery_order_lines', 'good_receipts', 'good_receipt_lines',
        'distributions', 'distribution_lines', 'disposals', 'disposal_lines',
        'consumptions', 'consumption_lines', 'goods_returns', 'goods_return_lines',
        'export_logs', 'import_logs'
      ])
      and relation.relrowsecurity
      and relation.relforcerowsecurity
  ),
  29::bigint,
  'all public business tables have forced RLS'
);

select is(
  (
    select count(*)::bigint
    from pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'branches', 'rooms', 'users', 'user_auth_links', 'item_categories', 'items',
        'item_batches', 'stock_locations', 'stock_balances', 'stock_movements',
        'stock_opnames', 'stock_opname_lines', 'purchase_requests',
        'purchase_request_opnames', 'purchase_request_lines', 'delivery_orders',
        'delivery_order_lines', 'good_receipts', 'good_receipt_lines',
        'distributions', 'distribution_lines', 'disposals', 'disposal_lines',
        'consumptions', 'consumption_lines', 'goods_returns', 'goods_return_lines',
        'export_logs', 'import_logs'
      ])
      and cmd <> 'SELECT'
  ),
  0::bigint,
  'Milestone 12A creates no client business write policy'
);

select is(
  (
    select count(*)::bigint
    from pg_policies
    where roles @> array['authenticated']::name[]
      and coalesce(qual, '') ~ '^\s*true\s*$'
  ),
  0::bigint,
  'no authenticated USING true policy exists'
);

select is(
  (select revision from app_meta.schema_revisions order by applied_at desc limit 1),
  'aish-supabase-003',
  'schema revision is exact'
);

select is(
  (select data_type from information_schema.columns where table_schema = 'public' and table_name = 'stock_balances' and column_name = 'qty_on_hand'),
  'bigint',
  'stock balance uses bigint fixed point'
);
select is(
  (select data_type from information_schema.columns where table_schema = 'public' and table_name = 'stock_movements' and column_name = 'qty'),
  'bigint',
  'ledger quantity uses bigint fixed point'
);
select is(
  (select data_type from information_schema.columns where table_schema = 'public' and table_name = 'item_batches' and column_name = 'expiry_date'),
  'date',
  'civil expiry is PostgreSQL date'
);

select is(
  (select count(*)::bigint from storage.buckets where id in ('import-audit', 'report-artifacts') and not public),
  2::bigint,
  'both storage buckets are private'
);
select is(
  (select count(*)::bigint from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname in ('import_audit_read_super_admin', 'report_artifacts_read_owner') and cmd = 'SELECT'),
  2::bigint,
  'storage has read-only scoped policies'
);
select is(
  (
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and (policyname like '%audit%' or policyname like 'report_artifacts%')
      and cmd <> 'SELECT'
  ),
  0::bigint,
  'storage client writes stay closed'
);

select ok(
  not has_table_privilege('anon', 'public.branches', 'SELECT'),
  'anonymous has no business table privilege'
);
select ok(
  not has_function_privilege('anon', 'public.get_my_domain_profile()', 'EXECUTE'),
  'anonymous cannot call profile RPC'
);
select ok(
  not has_table_privilege('authenticated', 'public.stock_movements', 'INSERT')
  and not has_table_privilege('authenticated', 'public.stock_movements', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.stock_movements', 'DELETE'),
  'authenticated cannot mutate the ledger'
);
select ok(
  not has_table_privilege('authenticated', 'public.stock_balances', 'INSERT')
  and not has_table_privilege('authenticated', 'public.stock_balances', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.stock_balances', 'DELETE'),
  'authenticated cannot mutate balance cache'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}', true);
select is((select count(*)::bigint from public.get_my_domain_profile()), 0::bigint, 'unlinked identity has no profile');
select is((select count(*)::bigint from public.branches), 0::bigint, 'unlinked identity sees no business rows');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}', true);
select is((select count(*)::bigint from public.get_my_domain_profile() where not is_active), 1::bigint, 'inactive identity resolves only for client rejection');
select is((select count(*)::bigint from public.branches), 0::bigint, 'inactive identity has no business access');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((select count(*)::bigint from public.branches), 1::bigint, 'nurse sees own branch only');
select is((select count(*)::bigint from public.branches where code = 'LOCAL-B'), 0::bigint, 'nurse cannot see another branch');
select is((select count(*)::bigint from public.rooms), 2::bigint, 'nurse sees rooms in own branch');
select is((select count(*)::bigint from public.rooms where branch_id = '20000000-0000-0000-0000-000000000002'), 0::bigint, 'nurse sees no foreign room');
select is((select count(*)::bigint from public.users), 1::bigint, 'nurse sees only own user row');
select is((select count(*)::bigint from public.import_logs), 0::bigint, 'nurse sees no import audit');
select is((select count(*)::bigint from public.stock_locations where type = 'warehouse'), 0::bigint, 'nurse sees no warehouse stock location');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is((select count(*)::bigint from public.branches), 1::bigint, 'branch head sees own branch only');
select is((select count(*)::bigint from public.rooms), 2::bigint, 'branch head sees own rooms');
select is((select count(*)::bigint from public.stock_locations where type = 'warehouse'), 0::bigint, 'branch head sees no central warehouse location');
select is((select count(*)::bigint from public.import_logs), 0::bigint, 'branch head sees no import audit');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select is((select count(*)::bigint from public.branches), 2::bigint, 'warehouse can resolve cross-branch workflow branches');
select is((select count(*)::bigint from public.rooms), 0::bigint, 'warehouse cannot enumerate treatment rooms');
select is((select count(*)::bigint from public.users), 1::bigint, 'warehouse sees only own user row');
select is((select count(*)::bigint from public.stock_locations where type = 'warehouse'), 1::bigint, 'warehouse sees central warehouse location');
select is((select count(*)::bigint from public.stock_locations where type <> 'warehouse'), 0::bigint, 'warehouse sees no branch or room stock location');
select is((select count(*)::bigint from public.import_logs), 0::bigint, 'warehouse sees no master import audit');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
select is((select count(*)::bigint from public.branches), 2::bigint, 'super admin reads all branches');
select is((select count(*)::bigint from public.rooms), 3::bigint, 'super admin reads all rooms');
select is((select count(*)::bigint from public.users), 5::bigint, 'super admin reads domain users');
select is((select schema_revision from public.get_server_health()), 'aish-supabase-003', 'active session health RPC returns revision');

reset role;

insert into storage.objects (id, bucket_id, name, owner_id)
values
  ('60000000-0000-0000-0000-000000000001', 'report-artifacts', '30000000-0000-0000-0000-000000000001/61000000-0000-0000-0000-000000000001/report.pdf', '10000000-0000-0000-0000-000000000001'),
  ('60000000-0000-0000-0000-000000000002', 'import-audit', '62000000-0000-0000-0000-000000000001/source.xlsx', '10000000-0000-0000-0000-000000000004');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is((select count(*)::bigint from storage.objects), 1::bigint, 'report owner reads only own artifact path');
select is((select count(*)::bigint from storage.objects where bucket_id = 'import-audit'), 0::bigint, 'nurse cannot read import source');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is((select count(*)::bigint from storage.objects where bucket_id = 'report-artifacts'), 0::bigint, 'cross-user report artifact path is denied');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}', true);
select is((select count(*)::bigint from storage.objects where bucket_id = 'import-audit'), 1::bigint, 'super admin reads import source');
reset role;

insert into public.stock_movements (
  id, created_at, updated_at, sync_status, item_id, from_location_id, qty,
  movement_type, actor_user_id
)
values (
  '70000000-0000-0000-0000-000000000001', now(), now(), 'synced',
  '41000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001', 1000, 'consumption',
  '30000000-0000-0000-0000-000000000003'
);
select throws_ok(
  $$update public.stock_movements set note = 'tamper' where id = '70000000-0000-0000-0000-000000000001'$$,
  '55000',
  'stock_movements is append-only',
  'ledger UPDATE is rejected even outside client RLS'
);
select throws_ok(
  $$delete from public.stock_movements where id = '70000000-0000-0000-0000-000000000001'$$,
  '55000',
  'stock_movements is append-only',
  'ledger DELETE is rejected even outside client RLS'
);

insert into public.branches (
  id, created_at, updated_at, sync_status, server_updated_at, server_version,
  code, name, is_active
)
values (
  '71000000-0000-0000-0000-000000000001', '2026-01-01 00:00:00+00', now(),
  'synced', '2000-01-01 00:00:00+00', 999, 'META', 'Metadata Test', true
);
select is((select server_version from public.branches where code = 'META'), 1::bigint, 'client insert cannot choose server version');
update public.branches set server_version = 999 where code = 'META';
select is((select server_version from public.branches where code = 'META'), 2::bigint, 'server version increments exactly once');
select is((select created_at from public.branches where code = 'META'), '2026-01-01 00:00:00+00'::timestamptz, 'metadata trigger preserves created_at');

select is(
  (
    select count(*)::bigint
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'app_private'
      and procedure.proname in ('current_domain_user_id', 'current_user_role', 'current_user_branch_id', 'current_user_is_active')
      and procedure.pronargs = 0
      and procedure.prosecdef
      and procedure.proconfig @> array['search_path=""']
  ),
  4::bigint,
  'authorization identity helpers take no actor input and fix search_path'
);

select * from finish();
rollback;
