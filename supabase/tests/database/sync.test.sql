begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select has_table('public','sync_devices','device registry exists');
select has_table('public','sync_operations','idempotency registry exists');
select has_table('public','sync_conflicts','server conflict audit exists');
select has_table('public','document_number_counters','number counter exists');
select has_table('public','file_upload_intents','upload intent exists');
select has_table('public','remote_file_objects','remote object audit exists');

select is((select revision from app_meta.schema_revisions order by applied_at desc limit 1),
  'aish-supabase-002','revision 002 is latest');
select is((select count(*)::bigint from storage.buckets where id in ('import-audit','report-artifacts') and not public),2::bigint,'buckets remain private');
select ok(not has_table_privilege('authenticated','public.stock_movements','INSERT'),'client still cannot insert movement');
select ok(not has_table_privilege('authenticated','public.stock_balances','UPDATE'),'client still cannot update balance');
select ok(not has_table_privilege('authenticated','public.document_number_counters','SELECT'),'counter is private');
select ok(not has_function_privilege('anon','public.push_sync_operation(jsonb)','EXECUTE'),'anon cannot push');
select ok(has_function_privilege('authenticated','public.push_sync_operation(jsonb)','EXECUTE'),'authenticated can push RPC');
select ok(not has_function_privilege('authenticated','app_private.post_verified_plan(jsonb,text,uuid,uuid,timestamp with time zone)','EXECUTE'),'ledger helper is private');
select ok(not has_function_privilege('authenticated','app_private.allocate_document_number(text,uuid,timestamp with time zone)','EXECUTE'),'number helper is private');
select is((select count(*)::bigint from pg_policies where schemaname='storage' and tablename='objects' and cmd='INSERT'),0::bigint,'no generic storage insert policy');
select is((select count(*)::bigint from pg_policies where schemaname='public' and tablename in ('sync_devices','sync_operations','sync_conflicts','file_upload_intents','remote_file_objects') and cmd<>'SELECT'),0::bigint,'sync tables have no client write policy');
select is((select count(*)::bigint from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','app_private') and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%'),0::bigint,'all security definer functions fix search path');

create function pg_temp.sync_envelope(
  request_id uuid, device_id uuid, operation text, aggregate_type text,
  aggregate_id uuid, occurred_at timestamptz, payload jsonb
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with raw as (
    select jsonb_build_object(
      'request_id',request_id,'device_id',device_id,'operation',operation,
      'aggregate_type',aggregate_type,'aggregate_id',aggregate_id,
      'payload_version',1,'base_server_version',0,
      'occurred_at_utc',occurred_at,'payload',payload
    ) as value
  )
  select value || jsonb_build_object('payload_hash',
    encode(extensions.digest(convert_to(app_private.canonical_jsonb_text(value),'UTF8'),'sha256'),'hex'))
  from raw;
$$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is((select count(*)::bigint from public.register_sync_device(
  '81000000-0000-0000-0000-000000000004','admin-install','Local Admin')),
  1::bigint,'active actor registers a local device');
select is((public.push_sync_operation(pg_temp.sync_envelope(
  '82000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000004','upsert_master','category',
  '83000000-0000-0000-0000-000000000001',now(),jsonb_build_object(
    'id','83000000-0000-0000-0000-000000000001','created_at',now(),
    'updated_at',now(),'sync_status','pending','name','Kategori Push')))->>'outcome'),
  'accepted','master category push is accepted');
select lives_ok($$select * from public.create_file_upload_intent(
  '82000000-0000-0000-0000-000000000010','import_audit',
  '83000000-0000-0000-0000-000000000010','boundary.xlsx',repeat('a',64),
  10485760,'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')$$,
  'import source exactly 10 MiB is accepted');
select throws_ok($$select * from public.create_file_upload_intent(
  '82000000-0000-0000-0000-000000000011','import_audit',
  '83000000-0000-0000-0000-000000000011','too-large.xlsx',repeat('b',64),
  10485761,'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')$$,
  '22023','sync_upload_too_large','import source above 10 MiB is rejected');
select lives_ok($$select * from public.create_file_upload_intent(
  '82000000-0000-0000-0000-000000000012','report_artifact',
  '83000000-0000-0000-0000-000000000012','boundary.pdf',repeat('c',64),
  20971520,'application/pdf')$$,
  'report artifact follows its separate 20 MiB cap');
select throws_ok($$select * from public.create_file_upload_intent(
  '82000000-0000-0000-0000-000000000013','report_artifact',
  '83000000-0000-0000-0000-000000000013','too-large.pdf',repeat('d',64),
  20971521,'application/pdf')$$,
  '22023','sync_invalid_payload','all declared files above 20 MiB are rejected');
select is((public.push_sync_operation(pg_temp.sync_envelope(
  '82000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000004','upsert_master','category',
  '83000000-0000-0000-0000-000000000001',now(),jsonb_build_object(
    'id','83000000-0000-0000-0000-000000000001','created_at',now(),
    'updated_at',now(),'sync_status','pending','name','Kategori Push')))->>'outcome'),
  'replayed','same request and hash is replayed');
select throws_ok(
  $$select public.push_sync_operation(pg_temp.sync_envelope(
    '82000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000004','upsert_master','category',
    '83000000-0000-0000-0000-000000000001',now(),jsonb_build_object(
      'id','83000000-0000-0000-0000-000000000001','created_at',now(),
      'updated_at',now(),'sync_status','pending','name','Hash Berbeda')))$$,
  '23505','sync_request_id_reused','same request with another hash is rejected');
reset role;

insert into public.stock_opnames
  (id,created_at,updated_at,sync_status,doc_number,branch_id,room_id,
   period_year,period_week,counted_by,status,submitted_at)
values ('84000000-0000-0000-0000-000000000001',now(),now(),'synced','SO-SEED',
  '20000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000001',
  2026,30,'30000000-0000-0000-0000-000000000001','submitted',now());

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select lives_ok($$select * from public.register_sync_device(
  '81000000-0000-0000-0000-000000000002','head-install',null)$$,
  'branch head registers device');
select throws_ok($$select public.push_sync_operation(pg_temp.sync_envelope(
  '82000000-0000-0000-0000-000000000020',
  '81000000-0000-0000-0000-000000000002','submit_purchase_request',
  'purchase_request','85000000-0000-0000-0000-000000000020',now(),
  jsonb_build_object('actor_user_id','30000000-0000-0000-0000-000000000004')))$$,
  '42501','sync_actor_mismatch','server rejects payload actor mismatch');
select is((public.push_sync_operation(pg_temp.sync_envelope(
  '82000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000002','submit_purchase_request',
  'purchase_request','85000000-0000-0000-0000-000000000001',now(),
  jsonb_build_object('id','85000000-0000-0000-0000-000000000001',
    'created_at',now(),'branch_id','20000000-0000-0000-0000-000000000001',
    'requested_by','30000000-0000-0000-0000-000000000002','status','submitted',
    'lines',jsonb_build_array(jsonb_build_object(
      'id','85000000-0000-0000-0000-000000000002',
      'item_id','41000000-0000-0000-0000-000000000001',
      'suggested_qty',1000,'requested_qty',2000)),
    'opname_links',jsonb_build_array(jsonb_build_object(
      'id','85000000-0000-0000-0000-000000000003',
      'opname_id','84000000-0000-0000-0000-000000000001')))))->>'outcome'),
  'accepted','submitted PR aggregate is accepted');
select matches((select doc_number from public.purchase_requests
  where id='85000000-0000-0000-0000-000000000001'),
  '^PR-LOCAL-A-[0-9]{8}-[0-9]{4}$','server assigns final PR number');
reset role;

insert into public.stock_balances
  (id,created_at,updated_at,sync_status,location_id,item_id,batch_id,qty_on_hand)
values ('86000000-0000-0000-0000-000000000001',now(),now(),'synced',
  '50000000-0000-0000-0000-000000000004',
  '41000000-0000-0000-0000-000000000001',null,5000);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select lives_ok($$select * from public.register_sync_device(
  '81000000-0000-0000-0000-000000000001','nurse-install',null)$$,
  'nurse registers device');
select is((public.push_sync_operation(pg_temp.sync_envelope(
  '82000000-0000-0000-0000-000000000003',
  '81000000-0000-0000-0000-000000000001','post_consumption','consumption',
  '87000000-0000-0000-0000-000000000001',now(),jsonb_build_object(
    'id','87000000-0000-0000-0000-000000000001','created_at',now(),
    'branch_id','20000000-0000-0000-0000-000000000001',
    'room_id','21000000-0000-0000-0000-000000000001',
    'created_by','30000000-0000-0000-0000-000000000001','status','posted',
    'lines',jsonb_build_array(jsonb_build_object(
      'id','87000000-0000-0000-0000-000000000002',
      'item_id','41000000-0000-0000-0000-000000000001','qty',1000)),
    'movements',jsonb_build_array(jsonb_build_object(
      'id','87000000-0000-0000-0000-000000000003','created_at',now(),
      'item_id','41000000-0000-0000-0000-000000000001','qty',1000,
      'movement_type','consumption','ref_doc_type','CONS',
      'ref_doc_id','87000000-0000-0000-0000-000000000001',
      'actor_user_id','30000000-0000-0000-0000-000000000001',
      'from_location_id','50000000-0000-0000-0000-000000000004')))))->>'outcome'),
  'accepted','consumption and ledger post atomically');
reset role;
select is((select qty_on_hand from public.stock_balances
  where id='86000000-0000-0000-0000-000000000001'),4000::bigint,
  'accepted consumption debits exact balance');
select is((select count(*)::bigint from public.stock_movements
  where ref_doc_type='CONS' and ref_doc_id='87000000-0000-0000-0000-000000000001'),
  1::bigint,'accepted consumption reuses one client movement UUID');

-- Exercise every remaining server-authoritative workflow against real tables.
-- These calls deliberately use the private validators as database fixtures;
-- public authentication, device ownership and hashing are covered above and
-- by the HTTP E2E harness.
insert into public.stock_locations
  (id,created_at,updated_at,sync_status,type,branch_id,room_id,name)
values ('50000000-0000-0000-0000-000000000006',now(),now(),'synced','room',
  '20000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002','Ruang Lokal A2');

select is((app_private.sync_submit_opname_complete(
  '88000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',now(),
  jsonb_build_object('created_at',now(),'branch_id','20000000-0000-0000-0000-000000000001',
    'room_id','21000000-0000-0000-0000-000000000002','counted_by','30000000-0000-0000-0000-000000000001',
    'period_year',2026,'period_week',32,'lines',jsonb_build_array(jsonb_build_object(
      'id','88000000-0000-0000-0000-000000000002','item_id','41000000-0000-0000-0000-000000000001',
      'system_qty',0,'counted_qty',1000,'note','Hitung fisik'))))->>'outcome'),
  'accepted','opname snapshot is submitted by its nurse');
select is((app_private.sync_review_opname_complete(
  '88000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002',0,now(),
  jsonb_build_object('doc_number','TMP-SO-fixture','movements',jsonb_build_array(jsonb_build_object(
    'id','88000000-0000-0000-0000-000000000003','created_at',now(),
    'item_id','41000000-0000-0000-0000-000000000001','from_location_id',null,
    'to_location_id','50000000-0000-0000-0000-000000000006','qty',1000,
    'movement_type','opname_adjustment','ref_doc_type','SO',
    'ref_doc_id','88000000-0000-0000-0000-000000000001',
    'note','Penyesuaian stok opname TMP-SO-fixture — Hitung fisik'))))->>'outcome'),
  'accepted','opname review posts exact adjustment plan');
select is((select qty_on_hand from public.stock_balances where
  location_id='50000000-0000-0000-0000-000000000006'
  and item_id='41000000-0000-0000-0000-000000000001' and batch_id is null),
  1000::bigint,'opname review updates the room balance atomically');

insert into public.stock_balances
  (id,created_at,updated_at,sync_status,location_id,item_id,batch_id,qty_on_hand)
values ('89000000-0000-0000-0000-000000000001',now(),now(),'synced',
  '50000000-0000-0000-0000-000000000002','41000000-0000-0000-0000-000000000001',null,5000);
select is((app_private.sync_post_distribution_complete(
  '89000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002',now(),
  jsonb_build_object('created_at',now(),'branch_id','20000000-0000-0000-0000-000000000001',
    'lines',jsonb_build_array(jsonb_build_object('id','89000000-0000-0000-0000-000000000003',
      'room_id','21000000-0000-0000-0000-000000000001',
      'item_id','41000000-0000-0000-0000-000000000001','qty',1000)),
    'movements',jsonb_build_array(jsonb_build_object('id','89000000-0000-0000-0000-000000000004',
      'created_at',now(),'item_id','41000000-0000-0000-0000-000000000001',
      'from_location_id','50000000-0000-0000-0000-000000000002',
      'to_location_id','50000000-0000-0000-0000-000000000004','qty',1000,
      'movement_type','distribution','ref_doc_type','DIST',
      'ref_doc_id','89000000-0000-0000-0000-000000000002'))))->>'outcome'),
  'accepted','distribution posts exact transfer plan');
select is((select qty_on_hand from public.stock_balances where id='89000000-0000-0000-0000-000000000001'),
  4000::bigint,'distribution debits branch store');

insert into public.item_batches
  (id,created_at,updated_at,sync_status,item_id,batch_no,expiry_date)
values ('8a000000-0000-0000-0000-000000000001',now(),now(),'synced',
  '41000000-0000-0000-0000-000000000002','EXPIRED-12B','2020-01-01');
insert into public.stock_balances
  (id,created_at,updated_at,sync_status,location_id,item_id,batch_id,qty_on_hand)
values ('8a000000-0000-0000-0000-000000000002',now(),now(),'synced',
  '50000000-0000-0000-0000-000000000002','41000000-0000-0000-0000-000000000002',
  '8a000000-0000-0000-0000-000000000001',3000);
select is((app_private.sync_post_disposal_complete(
  '8a000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000002',now(),
  jsonb_build_object('created_at',now(),'source_location_id','50000000-0000-0000-0000-000000000002',
    'reason','Kedaluwarsa','lines',jsonb_build_array(jsonb_build_object(
      'id','8a000000-0000-0000-0000-000000000004','item_id','41000000-0000-0000-0000-000000000002',
      'batch_id','8a000000-0000-0000-0000-000000000001','qty',1000,'note','Kemasan rusak')),
    'movements',jsonb_build_array(jsonb_build_object('id','8a000000-0000-0000-0000-000000000005',
      'created_at',now(),'item_id','41000000-0000-0000-0000-000000000002',
      'batch_id','8a000000-0000-0000-0000-000000000001',
      'from_location_id','50000000-0000-0000-0000-000000000002','to_location_id',null,
      'qty',1000,'movement_type','disposal','ref_doc_type','DSP',
      'ref_doc_id','8a000000-0000-0000-0000-000000000003',
      'note','Kedaluwarsa · Kemasan rusak'))))->>'outcome'),
  'accepted','expired disposal posts exact source-only plan');

select is(app_private.sync_transition_purchase_request_complete(
  'process_purchase_request','85000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000003',0,now(),'{}'::jsonb)->>'outcome',
  'accepted','warehouse processes submitted PR');
insert into public.stock_balances
  (id,created_at,updated_at,sync_status,location_id,item_id,batch_id,qty_on_hand)
values ('8b000000-0000-0000-0000-000000000001',now(),now(),'synced',
  '50000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001',null,5000);
select is((app_private.sync_ship_delivery_order_complete(
  '8b000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000003',now(),
  jsonb_build_object('created_at',now(),'pr_id','85000000-0000-0000-0000-000000000001',
    'lines',jsonb_build_array(jsonb_build_object('id','8b000000-0000-0000-0000-000000000003',
      'pr_line_id','85000000-0000-0000-0000-000000000002',
      'item_id','41000000-0000-0000-0000-000000000001','shipped_qty',2000)),
    'movements',jsonb_build_array(jsonb_build_object('id','8b000000-0000-0000-0000-000000000004',
      'created_at',now(),'item_id','41000000-0000-0000-0000-000000000001',
      'from_location_id','50000000-0000-0000-0000-000000000001','to_location_id',null,
      'qty',2000,'movement_type','shipment','ref_doc_type','DO',
      'ref_doc_id','8b000000-0000-0000-0000-000000000002'))))->>'outcome'),
  'accepted','delivery order shipment posts exact warehouse debit');
select is((app_private.sync_post_good_receipt_complete(
  '8c000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002',now(),
  jsonb_build_object('created_at',now(),'do_id','8b000000-0000-0000-0000-000000000002',
    'lines',jsonb_build_array(jsonb_build_object('id','8c000000-0000-0000-0000-000000000002',
      'do_line_id','8b000000-0000-0000-0000-000000000003',
      'item_id','41000000-0000-0000-0000-000000000001','shipped_qty',2000,
      'received_qty',0,'line_status','rejected','reject_reason','Rusak')),
    'movements','[]'::jsonb))->>'outcome'),
  'accepted','good receipt records complete rejected decision set');
select is((app_private.sync_ship_goods_return_complete(
  '8d000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002',now(),
  jsonb_build_object('created_at',now(),'gr_id','8c000000-0000-0000-0000-000000000001',
    'branch_id','20000000-0000-0000-0000-000000000001',
    'created_by','30000000-0000-0000-0000-000000000002',
    'lines',jsonb_build_array(jsonb_build_object('id','8d000000-0000-0000-0000-000000000002',
      'gr_line_id','8c000000-0000-0000-0000-000000000002',
      'item_id','41000000-0000-0000-0000-000000000001','qty',2000,
      'reject_reason_snapshot','Rusak')),'movements','[]'::jsonb))->>'outcome'),
  'accepted','branch ships the actual goods-return transition');
select is((app_private.sync_receive_goods_return_complete(
  '8d000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003',0,now(),
  jsonb_build_object('movements',jsonb_build_array(jsonb_build_object(
    'id','8d000000-0000-0000-0000-000000000003','created_at',now(),
    'item_id','41000000-0000-0000-0000-000000000001','from_location_id',null,
    'to_location_id','50000000-0000-0000-0000-000000000001','qty',2000,
    'movement_type','return','ref_doc_type','RET',
    'ref_doc_id','8d000000-0000-0000-0000-000000000001','note','Rusak'))))->>'outcome'),
  'accepted','warehouse receives return and restores exact warehouse balance');
select is((select count(*)::bigint from public.stock_movements where id in (
  '88000000-0000-0000-0000-000000000003','89000000-0000-0000-0000-000000000004',
  '8a000000-0000-0000-0000-000000000005','8b000000-0000-0000-0000-000000000004',
  '8d000000-0000-0000-0000-000000000003')),5::bigint,
  'all tested workflows preserve the five client movement UUIDs');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}',true);
select throws_ok($$select * from public.register_sync_device(
  '81000000-0000-0000-0000-000000000005','inactive-install',null)$$,
  '42501','sync_user_inactive','inactive user cannot register a sync device');
reset role;

select * from finish();
rollback;
