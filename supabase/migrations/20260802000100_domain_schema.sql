-- Aish Warehouse Milestone 12A
-- Semantic PostgreSQL mirror of the Drift v13 business schema.

create schema if not exists app_private;
create schema if not exists app_meta;

revoke all on schema app_private from public, anon, authenticated;
revoke all on schema app_meta from public, anon, authenticated;

create table public.branches (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  code varchar(32) not null unique check (length(code) >= 1),
  name varchar(128) not null check (length(name) >= 1),
  address text,
  is_active boolean not null default true
);

create table public.rooms (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  branch_id uuid not null references public.branches(id),
  code varchar(32) not null check (length(code) >= 1),
  name varchar(128) not null check (length(name) >= 1),
  is_active boolean not null default true,
  unique (branch_id, code)
);

create table public.users (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  full_name varchar(128) not null check (length(full_name) >= 1),
  email varchar(190) not null unique check (length(email) >= 3),
  role text not null check (role in ('perawat', 'kepala_cabang', 'warehouse', 'super_admin')),
  branch_id uuid references public.branches(id),
  is_active boolean not null default true,
  check (
    (role in ('perawat', 'kepala_cabang') and branch_id is not null)
    or (role in ('warehouse', 'super_admin') and branch_id is null)
  )
);

create table public.user_auth_links (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  user_id uuid not null unique references public.users(id),
  created_at timestamptz not null default now()
);

comment on table public.user_auth_links is
  'One-to-one mapping from Supabase Auth identity to the persistent Aish domain user.';

create table public.item_categories (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  name varchar(128) not null unique check (length(name) >= 1)
);

create table public.items (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  sku varchar(64) not null unique check (length(sku) >= 1),
  name varchar(190) not null check (length(name) >= 1),
  category_id uuid not null references public.item_categories(id),
  unit varchar(32) not null check (length(unit) >= 1),
  min_stock_room bigint not null default 0 check (min_stock_room >= 0),
  min_stock_branch bigint not null default 0 check (min_stock_branch >= 0),
  has_expiry boolean not null default false,
  expiry_alert_days integer not null default 30 check (expiry_alert_days >= 0),
  is_active boolean not null default true
);

create table public.item_batches (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  item_id uuid not null references public.items(id),
  batch_no varchar(64) not null check (length(batch_no) >= 1),
  expiry_date date not null,
  unique (item_id, batch_no)
);

create table public.stock_locations (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  type text not null check (type in ('warehouse', 'branch_store', 'room')),
  branch_id uuid references public.branches(id),
  room_id uuid references public.rooms(id),
  name varchar(190) not null check (length(name) >= 1),
  check (
    (type = 'warehouse' and branch_id is null and room_id is null)
    or (type = 'branch_store' and branch_id is not null and room_id is null)
    or (type = 'room' and branch_id is not null and room_id is not null)
  )
);

create table public.stock_balances (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  location_id uuid not null references public.stock_locations(id),
  item_id uuid not null references public.items(id),
  batch_id uuid references public.item_batches(id),
  qty_on_hand bigint not null check (qty_on_hand >= 0)
);

create unique index idx_stock_balances_batched
  on public.stock_balances (location_id, item_id, batch_id)
  where batch_id is not null;
create unique index idx_stock_balances_unbatched
  on public.stock_balances (location_id, item_id)
  where batch_id is null;

create table public.stock_movements (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  item_id uuid not null references public.items(id),
  batch_id uuid references public.item_batches(id),
  from_location_id uuid references public.stock_locations(id),
  to_location_id uuid references public.stock_locations(id),
  qty bigint not null check (qty > 0),
  movement_type text not null check (movement_type in (
    'inbound_warehouse', 'shipment', 'good_receipt', 'distribution',
    'opname_adjustment', 'consumption', 'return', 'disposal', 'reversal'
  )),
  ref_doc_type varchar(16),
  ref_doc_id uuid,
  actor_user_id uuid not null references public.users(id),
  note text,
  reversal_of_movement_id uuid references public.stock_movements(id),
  check (from_location_id is not null or to_location_id is not null),
  check (from_location_id is null or to_location_id is null or from_location_id <> to_location_id)
);

create index idx_stock_movements_item on public.stock_movements (item_id, created_at);
create index idx_stock_movements_ref on public.stock_movements (ref_doc_type, ref_doc_id);

create table public.stock_opnames (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  doc_number varchar(64) not null check (length(doc_number) >= 1),
  branch_id uuid not null references public.branches(id),
  room_id uuid not null references public.rooms(id),
  period_year integer not null check (period_year between 2000 and 2999),
  period_week integer not null check (period_week between 1 and 53),
  counted_by uuid not null references public.users(id),
  status text not null default 'draft' check (status in ('draft', 'submitted', 'reviewed')),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.users(id),
  check (
    (status = 'draft' and submitted_at is null and reviewed_at is null and reviewed_by is null)
    or (status = 'submitted' and submitted_at is not null and reviewed_at is null and reviewed_by is null)
    or (status = 'reviewed' and submitted_at is not null and reviewed_at is not null and reviewed_by is not null)
  ),
  check (reviewed_by is null or reviewed_by <> counted_by)
);

create index idx_stock_opnames_branch_status on public.stock_opnames (branch_id, status);
create index idx_stock_opnames_counted_by_status on public.stock_opnames (counted_by, status);
create unique index idx_stock_opnames_room_period on public.stock_opnames (room_id, period_year, period_week) where deleted_at is null;
create unique index idx_stock_opnames_doc_number on public.stock_opnames (doc_number) where deleted_at is null;

create table public.stock_opname_lines (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  opname_id uuid not null references public.stock_opnames(id),
  item_id uuid not null references public.items(id),
  batch_id uuid references public.item_batches(id),
  system_qty bigint not null check (system_qty >= 0),
  counted_qty bigint not null check (counted_qty >= 0),
  difference bigint generated always as (counted_qty - system_qty) stored,
  note text
);

create index idx_stock_opname_lines_opname on public.stock_opname_lines (opname_id);
create index idx_stock_opname_lines_item on public.stock_opname_lines (item_id);
create unique index idx_stock_opname_lines_batched on public.stock_opname_lines (opname_id, item_id, batch_id) where batch_id is not null and deleted_at is null;
create unique index idx_stock_opname_lines_unbatched on public.stock_opname_lines (opname_id, item_id) where batch_id is null and deleted_at is null;

create table public.purchase_requests (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  doc_number varchar(64) not null check (length(doc_number) >= 1),
  branch_id uuid not null references public.branches(id),
  requested_by uuid not null references public.users(id),
  status text not null default 'draft' check (status in ('draft', 'submitted', 'processing', 'shipped', 'closed', 'rejected', 'cancelled')),
  needed_date date,
  note text,
  submitted_at timestamptz,
  processing_at timestamptz,
  processed_by uuid references public.users(id),
  cancelled_at timestamptz,
  cancelled_by uuid references public.users(id),
  cancel_reason text,
  rejected_at timestamptz,
  rejected_by uuid references public.users(id),
  reject_reason text,
  check (status <> 'draft' or submitted_at is null),
  check (submitted_at is not null or status in ('draft', 'cancelled')),
  check ((processing_at is null and processed_by is null) or (processing_at is not null and processed_by is not null)),
  check ((status in ('processing', 'shipped', 'closed', 'rejected') and processing_at is not null) or (status in ('draft', 'submitted', 'cancelled') and processing_at is null)),
  check ((status = 'rejected' and rejected_at is not null and rejected_by is not null and reject_reason is not null and btrim(reject_reason) <> '') or (status <> 'rejected' and rejected_at is null and rejected_by is null and reject_reason is null)),
  check ((status = 'cancelled' and cancelled_at is not null and cancelled_by is not null and cancel_reason is not null and btrim(cancel_reason) <> '') or (status <> 'cancelled' and cancelled_at is null and cancelled_by is null and cancel_reason is null)),
  check (processed_by is null or processed_by <> requested_by),
  check (rejected_by is null or rejected_by <> requested_by)
);

create index idx_purchase_requests_branch_status on public.purchase_requests (branch_id, status);
create index idx_purchase_requests_requested_by_status on public.purchase_requests (requested_by, status);
create index idx_purchase_requests_created_at on public.purchase_requests (created_at);
create index idx_purchase_requests_needed_date on public.purchase_requests (needed_date);
create unique index idx_purchase_requests_active_branch on public.purchase_requests (branch_id) where status in ('submitted', 'processing') and deleted_at is null;
create unique index idx_purchase_requests_doc_number on public.purchase_requests (doc_number) where deleted_at is null;

create table public.purchase_request_opnames (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  pr_id uuid not null references public.purchase_requests(id),
  opname_id uuid not null references public.stock_opnames(id)
);

create index idx_purchase_request_opnames_pr on public.purchase_request_opnames (pr_id);
create index idx_purchase_request_opnames_opname on public.purchase_request_opnames (opname_id);
create unique index idx_purchase_request_opnames_unique on public.purchase_request_opnames (pr_id, opname_id) where deleted_at is null;

create table public.purchase_request_lines (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  pr_id uuid not null references public.purchase_requests(id),
  item_id uuid not null references public.items(id),
  suggested_qty bigint not null check (suggested_qty >= 0),
  requested_qty bigint not null check (requested_qty > 0),
  note text
);

create index idx_purchase_request_lines_pr on public.purchase_request_lines (pr_id);
create index idx_purchase_request_lines_item on public.purchase_request_lines (item_id);
create unique index idx_purchase_request_lines_item_unique on public.purchase_request_lines (pr_id, item_id) where deleted_at is null;

create table public.delivery_orders (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  doc_number varchar(64) not null check (length(doc_number) >= 1),
  pr_id uuid not null references public.purchase_requests(id),
  prepared_by uuid not null references public.users(id),
  status text not null default 'preparing' check (status in ('preparing', 'shipped', 'received')),
  shipped_at timestamptz,
  shipped_by uuid references public.users(id),
  note text,
  check ((status = 'preparing' and shipped_at is null and shipped_by is null) or (status in ('shipped', 'received') and shipped_at is not null and shipped_by is not null))
);

create index idx_delivery_orders_pr_status on public.delivery_orders (pr_id, status);
create index idx_delivery_orders_status_created on public.delivery_orders (status, created_at);
create index idx_delivery_orders_prepared_by_status on public.delivery_orders (prepared_by, status);
create index idx_delivery_orders_shipped_at on public.delivery_orders (shipped_at);
create unique index idx_delivery_orders_doc_number on public.delivery_orders (doc_number) where deleted_at is null;

create table public.delivery_order_lines (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  do_id uuid not null references public.delivery_orders(id),
  pr_line_id uuid not null references public.purchase_request_lines(id),
  item_id uuid not null references public.items(id),
  batch_id uuid references public.item_batches(id),
  shipped_qty bigint not null check (shipped_qty > 0),
  fefo_override_reason text check (fefo_override_reason is null or btrim(fefo_override_reason) <> ''),
  near_expiry_confirmed boolean not null default false,
  near_expiry_note text check (near_expiry_note is null or btrim(near_expiry_note) <> ''),
  check (near_expiry_note is null or near_expiry_confirmed),
  check (batch_id is not null or (fefo_override_reason is null and not near_expiry_confirmed and near_expiry_note is null))
);

create index idx_delivery_order_lines_do on public.delivery_order_lines (do_id);
create index idx_delivery_order_lines_pr_line on public.delivery_order_lines (pr_line_id);
create index idx_delivery_order_lines_item on public.delivery_order_lines (item_id);
create index idx_delivery_order_lines_batch on public.delivery_order_lines (batch_id);
create unique index idx_delivery_order_lines_batched on public.delivery_order_lines (do_id, pr_line_id, batch_id) where batch_id is not null and deleted_at is null;
create unique index idx_delivery_order_lines_unbatched on public.delivery_order_lines (do_id, pr_line_id) where batch_id is null and deleted_at is null;

create table public.good_receipts (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  doc_number varchar(64) not null check (length(doc_number) >= 1),
  do_id uuid not null references public.delivery_orders(id),
  received_by uuid not null references public.users(id),
  status text not null default 'checking' check (status in ('checking', 'posted')),
  posted_at timestamptz,
  check ((status = 'checking' and posted_at is null) or (status = 'posted' and posted_at is not null))
);

create index idx_good_receipts_received_by_status on public.good_receipts (received_by, status);
create index idx_good_receipts_status_created on public.good_receipts (status, created_at);
create index idx_good_receipts_posted_at on public.good_receipts (posted_at);
create unique index idx_good_receipts_do on public.good_receipts (do_id);
create unique index idx_good_receipts_doc_number on public.good_receipts (doc_number) where deleted_at is null;

create table public.good_receipt_lines (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  gr_id uuid not null references public.good_receipts(id),
  do_line_id uuid not null references public.delivery_order_lines(id),
  item_id uuid not null references public.items(id),
  batch_id uuid references public.item_batches(id),
  shipped_qty bigint not null check (shipped_qty > 0),
  received_qty bigint not null check (received_qty >= 0 and received_qty <= shipped_qty),
  line_status text not null default 'pending' check (line_status in ('pending', 'checked', 'rejected')),
  reject_reason text,
  check (
    (line_status = 'pending' and reject_reason is null)
    or (line_status = 'checked' and reject_reason is null)
    or (line_status = 'rejected' and received_qty = 0 and reject_reason is not null and btrim(reject_reason) <> '')
  )
);

create index idx_good_receipt_lines_gr on public.good_receipt_lines (gr_id);
create index idx_good_receipt_lines_do_line on public.good_receipt_lines (do_line_id);
create index idx_good_receipt_lines_item on public.good_receipt_lines (item_id);
create index idx_good_receipt_lines_batch on public.good_receipt_lines (batch_id);
create index idx_good_receipt_lines_status on public.good_receipt_lines (line_status);
create unique index idx_good_receipt_lines_unique on public.good_receipt_lines (gr_id, do_line_id);

create table public.distributions (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  doc_number varchar(64) not null check (length(doc_number) >= 1),
  branch_id uuid not null references public.branches(id),
  distributed_by uuid not null references public.users(id),
  status text not null default 'draft' check (status in ('draft', 'posted')),
  posted_at timestamptz,
  note text,
  check ((status = 'draft' and posted_at is null) or (status = 'posted' and posted_at is not null))
);

create index idx_distributions_branch_status on public.distributions (branch_id, status);
create index idx_distributions_distributed_by_status on public.distributions (distributed_by, status);
create index idx_distributions_created_at on public.distributions (created_at);
create index idx_distributions_posted_at on public.distributions (posted_at);
create unique index idx_distributions_doc_number on public.distributions (doc_number) where deleted_at is null;

create table public.distribution_lines (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  distribution_id uuid not null references public.distributions(id),
  room_id uuid not null references public.rooms(id),
  item_id uuid not null references public.items(id),
  batch_id uuid references public.item_batches(id),
  qty bigint not null check (qty > 0),
  fefo_override_reason text check (fefo_override_reason is null or btrim(fefo_override_reason) <> '')
);

create index idx_distribution_lines_distribution on public.distribution_lines (distribution_id);
create index idx_distribution_lines_room on public.distribution_lines (room_id);
create index idx_distribution_lines_item on public.distribution_lines (item_id);
create index idx_distribution_lines_batch on public.distribution_lines (batch_id);
create unique index idx_distribution_lines_batched on public.distribution_lines (distribution_id, room_id, item_id, batch_id) where batch_id is not null and deleted_at is null;
create unique index idx_distribution_lines_unbatched on public.distribution_lines (distribution_id, room_id, item_id) where batch_id is null and deleted_at is null;

create table public.disposals (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  doc_number varchar(64) not null check (length(doc_number) >= 1),
  source_location_id uuid not null references public.stock_locations(id),
  created_by uuid not null references public.users(id),
  status text not null default 'draft' check (status in ('draft', 'posted')),
  reason text check (reason is null or btrim(reason) <> ''),
  posted_at timestamptz,
  posted_by uuid references public.users(id),
  check ((status = 'draft' and posted_at is null and posted_by is null) or (status = 'posted' and posted_at is not null and posted_by is not null and reason is not null and btrim(reason) <> ''))
);

create index idx_disposals_source_location_status on public.disposals (source_location_id, status);
create index idx_disposals_created_by_status on public.disposals (created_by, status);
create index idx_disposals_posted_by_status on public.disposals (posted_by, status);
create index idx_disposals_created_at on public.disposals (created_at);
create index idx_disposals_posted_at on public.disposals (posted_at);
create unique index idx_disposals_doc_number on public.disposals (doc_number);

create table public.disposal_lines (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  disposal_id uuid not null references public.disposals(id),
  item_id uuid not null references public.items(id),
  batch_id uuid not null references public.item_batches(id),
  qty bigint not null check (qty > 0),
  note text check (note is null or btrim(note) <> '')
);

create index idx_disposal_lines_disposal on public.disposal_lines (disposal_id);
create index idx_disposal_lines_item on public.disposal_lines (item_id);
create index idx_disposal_lines_batch on public.disposal_lines (batch_id);
create unique index idx_disposal_lines_position on public.disposal_lines (disposal_id, item_id, batch_id) where deleted_at is null;

create table public.consumptions (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  doc_number varchar(64) not null check (length(doc_number) >= 1),
  branch_id uuid not null references public.branches(id),
  room_id uuid not null references public.rooms(id),
  created_by uuid not null references public.users(id),
  status text not null default 'draft' check (status in ('draft', 'posted')),
  note text check (note is null or btrim(note) <> ''),
  posted_at timestamptz,
  posted_by uuid references public.users(id),
  check ((status = 'draft' and posted_at is null and posted_by is null) or (status = 'posted' and posted_at is not null and posted_by is not null))
);

create index idx_consumptions_branch_status on public.consumptions (branch_id, status);
create index idx_consumptions_room_status on public.consumptions (room_id, status);
create index idx_consumptions_created_by_status on public.consumptions (created_by, status);
create index idx_consumptions_posted_by_status on public.consumptions (posted_by, status);
create index idx_consumptions_created_at on public.consumptions (created_at);
create index idx_consumptions_posted_at on public.consumptions (posted_at);
create unique index idx_consumptions_doc_number on public.consumptions (doc_number);

create table public.consumption_lines (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  consumption_id uuid not null references public.consumptions(id),
  item_id uuid not null references public.items(id),
  batch_id uuid references public.item_batches(id),
  qty bigint not null check (qty > 0),
  note text check (note is null or btrim(note) <> '')
);

create index idx_consumption_lines_consumption on public.consumption_lines (consumption_id);
create index idx_consumption_lines_item on public.consumption_lines (item_id);
create index idx_consumption_lines_batch on public.consumption_lines (batch_id);
create unique index idx_consumption_lines_batched on public.consumption_lines (consumption_id, item_id, batch_id) where batch_id is not null and deleted_at is null;
create unique index idx_consumption_lines_unbatched on public.consumption_lines (consumption_id, item_id) where batch_id is null and deleted_at is null;

create table public.goods_returns (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  doc_number varchar(64) not null check (length(doc_number) >= 1),
  gr_id uuid not null references public.good_receipts(id),
  branch_id uuid not null references public.branches(id),
  created_by uuid not null references public.users(id),
  status text not null default 'draft' check (status in ('draft', 'shipped', 'received')),
  note text check (note is null or btrim(note) <> ''),
  shipped_at timestamptz,
  shipped_by uuid references public.users(id),
  received_at timestamptz,
  received_by uuid references public.users(id),
  warehouse_note text check (warehouse_note is null or btrim(warehouse_note) <> ''),
  check (
    (status = 'draft' and shipped_at is null and shipped_by is null and received_at is null and received_by is null)
    or (status = 'shipped' and shipped_at is not null and shipped_by is not null and received_at is null and received_by is null)
    or (status = 'received' and shipped_at is not null and shipped_by is not null and received_at is not null and received_by is not null)
  ),
  check (received_by is null or received_by <> created_by),
  check (received_by is null or shipped_by is null or received_by <> shipped_by)
);

create index idx_goods_returns_branch_status on public.goods_returns (branch_id, status);
create index idx_goods_returns_created_by_status on public.goods_returns (created_by, status);
create index idx_goods_returns_shipped_by_status on public.goods_returns (shipped_by, status);
create index idx_goods_returns_received_by_status on public.goods_returns (received_by, status);
create index idx_goods_returns_created_at on public.goods_returns (created_at);
create index idx_goods_returns_shipped_at on public.goods_returns (shipped_at);
create index idx_goods_returns_received_at on public.goods_returns (received_at);
create unique index idx_goods_returns_gr on public.goods_returns (gr_id);
create unique index idx_goods_returns_doc_number on public.goods_returns (doc_number);

create table public.goods_return_lines (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  goods_return_id uuid not null references public.goods_returns(id),
  gr_line_id uuid not null references public.good_receipt_lines(id),
  item_id uuid not null references public.items(id),
  batch_id uuid references public.item_batches(id),
  qty bigint not null check (qty > 0),
  reject_reason_snapshot text not null check (btrim(reject_reason_snapshot) <> '')
);

create index idx_goods_return_lines_return on public.goods_return_lines (goods_return_id);
create index idx_goods_return_lines_gr_line on public.goods_return_lines (gr_line_id);
create index idx_goods_return_lines_item on public.goods_return_lines (item_id);
create index idx_goods_return_lines_batch on public.goods_return_lines (batch_id);
create unique index idx_goods_return_lines_gr_line_unique on public.goods_return_lines (gr_line_id);
create unique index idx_goods_return_lines_unique on public.goods_return_lines (goods_return_id, gr_line_id);

create table public.export_logs (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  report_type text not null check (report_type in ('stok_lokasi', 'kartu_stok', 'rekap_opname', 'rekap_pr', 'rekap_do', 'rekap_gr', 'rekap_distribusi', 'rekap_pemakaian', 'rekap_pemusnahan', 'rekap_retur', 'kadaluarsa')),
  format text not null check (format in ('xlsx', 'pdf')),
  scope_type text not null check (scope_type in ('warehouse', 'branch_store', 'room', 'branch_all', 'cross_branch', 'all_locations')),
  location_id uuid references public.stock_locations(id),
  category_id uuid references public.item_categories(id),
  branch_id uuid references public.branches(id),
  item_id uuid references public.items(id),
  period_start date not null,
  period_end date not null,
  exported_by uuid not null references public.users(id),
  file_name varchar(255) not null check (btrim(file_name) <> ''),
  data_cutoff_at timestamptz not null,
  sync_summary text not null check (btrim(sync_summary) <> ''),
  row_count integer not null check (row_count >= 0),
  check (
    (scope_type = 'warehouse' and location_id is not null and branch_id is null)
    or (scope_type in ('branch_store', 'room') and location_id is not null and branch_id is not null)
    or (scope_type = 'branch_all' and location_id is null and branch_id is not null)
    or (scope_type in ('cross_branch', 'all_locations') and location_id is null and branch_id is null)
  )
);

create index idx_export_logs_actor on public.export_logs (exported_by, created_at);
create index idx_export_logs_type on public.export_logs (report_type, created_at);
create index idx_export_logs_format on public.export_logs (format, created_at);
create index idx_export_logs_scope on public.export_logs (scope_type, created_at);
create index idx_export_logs_branch on public.export_logs (branch_id, created_at);
create index idx_export_logs_location on public.export_logs (location_id, created_at);
create index idx_export_logs_category on public.export_logs (category_id, created_at);
create index idx_export_logs_item on public.export_logs (item_id, created_at);
create index idx_export_logs_created_at on public.export_logs (created_at);

create table public.import_logs (
  id uuid primary key,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  sync_status text not null check (sync_status in ('synced', 'pending', 'conflict')),
  server_updated_at timestamptz not null default now(),
  server_version bigint not null default 1 check (server_version > 0),
  entity text not null check (entity in ('items', 'item_categories', 'branches', 'rooms', 'users', 'item_batches')),
  file_name varchar(255) not null check (btrim(file_name) <> ''),
  total_rows integer not null check (total_rows >= 0),
  inserted_rows integer not null check (inserted_rows >= 0),
  updated_rows integer not null check (updated_rows >= 0),
  failed_rows integer not null check (failed_rows >= 0),
  error_detail text,
  status text not null check (status in ('validated', 'committed', 'discarded')),
  imported_by uuid not null references public.users(id),
  stored_file_path varchar(1024) not null check (btrim(stored_file_path) <> ''),
  file_sha256 varchar(64) not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  file_size_bytes bigint not null check (file_size_bytes > 0),
  template_version varchar(64) not null check (btrim(template_version) <> ''),
  check (total_rows = inserted_rows + updated_rows + failed_rows),
  check (status <> 'committed' or failed_rows = 0),
  check (failed_rows = 0 or (error_detail is not null and btrim(error_detail) <> ''))
);

create index idx_import_logs_entity_status on public.import_logs (entity, status, created_at);
create index idx_import_logs_status on public.import_logs (status, created_at);
create index idx_import_logs_actor on public.import_logs (imported_by, created_at);
create index idx_import_logs_created_at on public.import_logs (created_at);
create index idx_import_logs_sha256 on public.import_logs (file_sha256);
create index idx_import_logs_sync on public.import_logs (sync_status, created_at);

create table app_meta.schema_revisions (
  revision text primary key,
  applied_at timestamptz not null default now()
);

insert into app_meta.schema_revisions (revision) values ('aish-supabase-001');

comment on column public.stock_balances.qty_on_hand is 'Fixed-point quantity in milli-units (scale 1000).';
comment on column public.stock_movements.qty is 'Fixed-point quantity in milli-units (scale 1000).';
comment on column public.stock_opname_lines.difference is 'Generated fixed-point difference; never client-written.';
