-- Deterministic LOCAL-ONLY fixtures. Password: LocalOnly!12345
-- These addresses and credentials are synthetic and must never be used remotely.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'nurse.local@example.test', extensions.crypt('LocalOnly!12345', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'branchhead.local@example.test', extensions.crypt('LocalOnly!12345', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'warehouse.local@example.test', extensions.crypt('LocalOnly!12345', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'admin.local@example.test', extensions.crypt('LocalOnly!12345', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'inactive.local@example.test', extensions.crypt('LocalOnly!12345', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'unlinked.local@example.test', extensions.crypt('LocalOnly!12345', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(),
  auth_user.id,
  auth_user.id::text,
  jsonb_build_object('sub', auth_user.id::text, 'email', auth_user.email),
  'email',
  now(),
  now(),
  now()
from auth.users as auth_user
where auth_user.email like '%.local@example.test';

insert into public.branches (
  id, created_at, updated_at, sync_status, code, name, address, is_active
)
values
  ('20000000-0000-0000-0000-000000000001', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'LOCAL-A', 'Cabang Lokal A', 'Alamat sintetis A', true),
  ('20000000-0000-0000-0000-000000000002', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'LOCAL-B', 'Cabang Lokal B', 'Alamat sintetis B', true);

insert into public.rooms (
  id, created_at, updated_at, sync_status, branch_id, code, name, is_active
)
values
  ('21000000-0000-0000-0000-000000000001', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', '20000000-0000-0000-0000-000000000001', 'R1', 'Ruang Lokal A1', true),
  ('21000000-0000-0000-0000-000000000002', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', '20000000-0000-0000-0000-000000000001', 'R2', 'Ruang Lokal A2', true),
  ('21000000-0000-0000-0000-000000000003', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', '20000000-0000-0000-0000-000000000002', 'R1', 'Ruang Lokal B1', true);

insert into public.users (
  id, created_at, updated_at, sync_status, full_name, email, role, branch_id, is_active
)
values
  ('30000000-0000-0000-0000-000000000001', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'Perawat Lokal', 'nurse.local@example.test', 'perawat', '20000000-0000-0000-0000-000000000001', true),
  ('30000000-0000-0000-0000-000000000002', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'Kepala Cabang Lokal', 'branchhead.local@example.test', 'kepala_cabang', '20000000-0000-0000-0000-000000000001', true),
  ('30000000-0000-0000-0000-000000000003', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'Warehouse Lokal', 'warehouse.local@example.test', 'warehouse', null, true),
  ('30000000-0000-0000-0000-000000000004', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'Super Admin Lokal', 'admin.local@example.test', 'super_admin', null, true),
  ('30000000-0000-0000-0000-000000000005', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'Pengguna Nonaktif Lokal', 'inactive.local@example.test', 'perawat', '20000000-0000-0000-0000-000000000001', false);

insert into public.user_auth_links (auth_user_id, user_id)
values
  ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002'),
  ('10000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003'),
  ('10000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000004'),
  ('10000000-0000-0000-0000-000000000005', '30000000-0000-0000-0000-000000000005');

insert into public.item_categories (
  id, created_at, updated_at, sync_status, name
)
values ('40000000-0000-0000-0000-000000000001', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'Kategori Lokal');

insert into public.items (
  id, created_at, updated_at, sync_status, sku, name, category_id, unit,
  min_stock_room, min_stock_branch, has_expiry, expiry_alert_days, is_active
)
values
  ('41000000-0000-0000-0000-000000000001', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'LOCAL-001', 'Barang Lokal Tanpa ED', '40000000-0000-0000-0000-000000000001', 'pcs', 1000, 3000, false, 30, true),
  ('41000000-0000-0000-0000-000000000002', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'LOCAL-002', 'Barang Lokal Ber-ED', '40000000-0000-0000-0000-000000000001', 'box', 1000, 3000, true, 30, true);

insert into public.item_batches (
  id, created_at, updated_at, sync_status, item_id, batch_no, expiry_date
)
values ('42000000-0000-0000-0000-000000000001', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', '41000000-0000-0000-0000-000000000002', 'LOCAL-BATCH-01', '2027-12-31');

insert into public.stock_locations (
  id, created_at, updated_at, sync_status, type, branch_id, room_id, name
)
values
  ('50000000-0000-0000-0000-000000000001', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'warehouse', null, null, 'Warehouse Pusat Lokal'),
  ('50000000-0000-0000-0000-000000000002', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'branch_store', '20000000-0000-0000-0000-000000000001', null, 'Gudang Cabang Lokal A'),
  ('50000000-0000-0000-0000-000000000003', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'branch_store', '20000000-0000-0000-0000-000000000002', null, 'Gudang Cabang Lokal B'),
  ('50000000-0000-0000-0000-000000000004', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'room', '20000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001', 'Ruang Lokal A1'),
  ('50000000-0000-0000-0000-000000000005', '2026-08-01 00:00:00+00', '2026-08-01 00:00:00+00', 'synced', 'room', '20000000-0000-0000-0000-000000000002', '21000000-0000-0000-0000-000000000003', 'Ruang Lokal B1');
