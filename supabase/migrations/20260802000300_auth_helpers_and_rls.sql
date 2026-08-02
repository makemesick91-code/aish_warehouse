-- Auth identity mapping, server-side authorization helpers, RPCs, and default-deny RLS.

create or replace function app_private.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_auth_links as link
    join public.users as domain_user on domain_user.id = link.user_id
    where link.auth_user_id = (select auth.uid())
      and domain_user.is_active
      and domain_user.deleted_at is null
  );
$$;

create or replace function app_private.current_domain_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select link.user_id
  from public.user_auth_links as link
  join public.users as domain_user on domain_user.id = link.user_id
  where link.auth_user_id = (select auth.uid())
    and domain_user.is_active
    and domain_user.deleted_at is null
  limit 1;
$$;

create or replace function app_private.current_user_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select domain_user.role
  from public.users as domain_user
  where domain_user.id = app_private.current_domain_user_id();
$$;

create or replace function app_private.current_user_branch_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select domain_user.branch_id
  from public.users as domain_user
  where domain_user.id = app_private.current_domain_user_id();
$$;

create or replace function app_private.is_super_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(app_private.current_user_role() = 'super_admin', false); $$;

create or replace function app_private.is_warehouse()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(app_private.current_user_role() = 'warehouse', false); $$;

create or replace function app_private.is_branch_head()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(app_private.current_user_role() = 'kepala_cabang', false); $$;

create or replace function app_private.is_nurse()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(app_private.current_user_role() = 'perawat', false); $$;

create or replace function app_private.can_read_location(requested_location_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case app_private.current_user_role()
      when 'super_admin' then true
      when 'warehouse' then location.type = 'warehouse'
      when 'kepala_cabang' then location.branch_id = app_private.current_user_branch_id()
        and location.type in ('branch_store', 'room')
      when 'perawat' then location.branch_id = app_private.current_user_branch_id()
        and location.type = 'room'
      else false
    end
    from public.stock_locations as location
    where location.id = requested_location_id
  ), false);
$$;

do $$
declare
  signature text;
begin
  foreach signature in array array[
    'app_private.current_user_is_active()',
    'app_private.current_domain_user_id()',
    'app_private.current_user_role()',
    'app_private.current_user_branch_id()',
    'app_private.is_super_admin()',
    'app_private.is_warehouse()',
    'app_private.is_branch_head()',
    'app_private.is_nurse()',
    'app_private.can_read_location(uuid)'
  ]
  loop
    execute 'revoke all on function ' || signature || ' from public, anon';
    execute 'grant execute on function ' || signature || ' to authenticated';
  end loop;
end;
$$;

grant usage on schema app_private to authenticated;

create or replace function public.get_my_domain_profile()
returns table (
  id uuid,
  full_name text,
  email text,
  role text,
  branch_id uuid,
  is_active boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select domain_user.id,
         domain_user.full_name::text,
         domain_user.email::text,
         domain_user.role,
         domain_user.branch_id,
         domain_user.is_active
  from public.user_auth_links as link
  join public.users as domain_user on domain_user.id = link.user_id
  where link.auth_user_id = (select auth.uid())
    and domain_user.deleted_at is null
  limit 1;
$$;

create or replace function public.get_server_health()
returns table (status text, server_time_utc timestamptz, schema_revision text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.current_user_is_active() then
    raise exception using errcode = '42501', message = 'access denied';
  end if;
  return query
    select 'ok'::text, statement_timestamp(), revision.revision
    from app_meta.schema_revisions as revision
    order by revision.applied_at desc
    limit 1;
end;
$$;

revoke all on function public.get_my_domain_profile() from public, anon;
revoke all on function public.get_server_health() from public, anon;
grant execute on function public.get_my_domain_profile() to authenticated;
grant execute on function public.get_server_health() to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'branches', 'rooms', 'users', 'user_auth_links', 'item_categories', 'items',
    'item_batches', 'stock_locations', 'stock_balances', 'stock_movements',
    'stock_opnames', 'stock_opname_lines', 'purchase_requests',
    'purchase_request_opnames', 'purchase_request_lines', 'delivery_orders',
    'delivery_order_lines', 'good_receipts', 'good_receipt_lines',
    'distributions', 'distribution_lines', 'disposals', 'disposal_lines',
    'consumptions', 'consumption_lines', 'goods_returns', 'goods_return_lines',
    'export_logs', 'import_logs'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

grant select on table
  public.branches, public.rooms, public.users, public.item_categories,
  public.items, public.item_batches, public.stock_locations,
  public.stock_balances, public.stock_movements, public.stock_opnames,
  public.stock_opname_lines, public.purchase_requests,
  public.purchase_request_opnames, public.purchase_request_lines,
  public.delivery_orders, public.delivery_order_lines, public.good_receipts,
  public.good_receipt_lines, public.distributions, public.distribution_lines,
  public.disposals, public.disposal_lines, public.consumptions,
  public.consumption_lines, public.goods_returns, public.goods_return_lines,
  public.export_logs, public.import_logs
to authenticated;

-- Master and identity data.
create policy branches_read_scope on public.branches for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    app_private.current_user_role() in ('warehouse', 'super_admin')
    or id = app_private.current_user_branch_id()
  )
);

create policy rooms_read_scope on public.rooms for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    app_private.is_super_admin()
    or branch_id = app_private.current_user_branch_id()
  )
);

create policy users_read_self_or_admin on public.users for select to authenticated
using (
  app_private.current_user_is_active()
  and (id = app_private.current_domain_user_id() or app_private.is_super_admin())
);

create policy item_categories_read_authenticated on public.item_categories for select to authenticated
using (app_private.current_user_is_active());
create policy items_read_authenticated on public.items for select to authenticated
using (app_private.current_user_is_active());
create policy item_batches_read_authenticated on public.item_batches for select to authenticated
using (app_private.current_user_is_active());

-- No user_auth_links policy is intentional: only fixed SECURITY DEFINER helpers read it.

-- Inventory reads are location scoped. No INSERT/UPDATE/DELETE policy exists.
create policy stock_locations_read_scope on public.stock_locations for select to authenticated
using (app_private.current_user_is_active() and app_private.can_read_location(id));

create policy stock_balances_read_scope on public.stock_balances for select to authenticated
using (app_private.current_user_is_active() and app_private.can_read_location(location_id));

create policy stock_movements_read_scope on public.stock_movements for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    app_private.is_super_admin()
    or (from_location_id is not null and app_private.can_read_location(from_location_id))
    or (to_location_id is not null and app_private.can_read_location(to_location_id))
  )
);

-- Stock Opname: nurse owns their documents; branch head owns branch scope;
-- Warehouse/Super Admin receive finalized recap visibility required by Reporting.
create policy stock_opnames_read_scope on public.stock_opnames for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    (app_private.is_nurse() and counted_by = app_private.current_domain_user_id() and branch_id = app_private.current_user_branch_id())
    or (app_private.is_branch_head() and branch_id = app_private.current_user_branch_id())
    or (app_private.current_user_role() in ('warehouse', 'super_admin') and status = 'reviewed')
  )
);
create policy stock_opname_lines_read_scope on public.stock_opname_lines for select to authenticated
using (exists (select 1 from public.stock_opnames as parent where parent.id = opname_id));

-- Purchase Requests and descendant rows.
create policy purchase_requests_read_scope on public.purchase_requests for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    (app_private.is_branch_head() and branch_id = app_private.current_user_branch_id())
    or app_private.current_user_role() in ('warehouse', 'super_admin')
  )
);
create policy purchase_request_opnames_read_scope on public.purchase_request_opnames for select to authenticated
using (exists (select 1 from public.purchase_requests as parent where parent.id = pr_id));
create policy purchase_request_lines_read_scope on public.purchase_request_lines for select to authenticated
using (exists (select 1 from public.purchase_requests as parent where parent.id = pr_id));

create policy delivery_orders_read_scope on public.delivery_orders for select to authenticated
using (
  app_private.current_user_is_active()
  and exists (
    select 1 from public.purchase_requests as request
    where request.id = pr_id
      and (
        app_private.current_user_role() in ('warehouse', 'super_admin')
        or (app_private.is_branch_head() and request.branch_id = app_private.current_user_branch_id() and delivery_orders.status in ('shipped', 'received'))
      )
  )
);
create policy delivery_order_lines_read_scope on public.delivery_order_lines for select to authenticated
using (exists (select 1 from public.delivery_orders as parent where parent.id = do_id));

create policy good_receipts_read_scope on public.good_receipts for select to authenticated
using (
  app_private.current_user_is_active()
  and exists (
    select 1
    from public.delivery_orders as delivery
    join public.purchase_requests as request on request.id = delivery.pr_id
    where delivery.id = do_id
      and (
        app_private.current_user_role() in ('warehouse', 'super_admin')
        or (app_private.is_branch_head() and request.branch_id = app_private.current_user_branch_id())
      )
  )
);
create policy good_receipt_lines_read_scope on public.good_receipt_lines for select to authenticated
using (exists (select 1 from public.good_receipts as parent where parent.id = gr_id));

create policy distributions_read_scope on public.distributions for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    (app_private.is_branch_head() and branch_id = app_private.current_user_branch_id())
    or (app_private.current_user_role() in ('warehouse', 'super_admin') and status = 'posted')
  )
);
create policy distribution_lines_read_scope on public.distribution_lines for select to authenticated
using (exists (select 1 from public.distributions as parent where parent.id = distribution_id));

create policy disposals_read_scope on public.disposals for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    app_private.is_super_admin()
    or app_private.can_read_location(source_location_id)
  )
);
create policy disposal_lines_read_scope on public.disposal_lines for select to authenticated
using (exists (select 1 from public.disposals as parent where parent.id = disposal_id));

create policy consumptions_read_scope on public.consumptions for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    (app_private.is_nurse() and created_by = app_private.current_domain_user_id() and branch_id = app_private.current_user_branch_id())
    or (app_private.is_branch_head() and branch_id = app_private.current_user_branch_id() and status = 'posted')
    or (app_private.current_user_role() in ('warehouse', 'super_admin') and status = 'posted')
  )
);
create policy consumption_lines_read_scope on public.consumption_lines for select to authenticated
using (exists (select 1 from public.consumptions as parent where parent.id = consumption_id));

create policy goods_returns_read_scope on public.goods_returns for select to authenticated
using (
  app_private.current_user_is_active()
  and (
    (app_private.is_branch_head() and branch_id = app_private.current_user_branch_id())
    or (app_private.is_warehouse() and status in ('shipped', 'received'))
    or app_private.is_super_admin()
  )
);
create policy goods_return_lines_read_scope on public.goods_return_lines for select to authenticated
using (exists (select 1 from public.goods_returns as parent where parent.id = goods_return_id));

create policy export_logs_read_scope on public.export_logs for select to authenticated
using (
  app_private.current_user_is_active()
  and (exported_by = app_private.current_domain_user_id() or app_private.is_super_admin())
);
create policy import_logs_read_admin on public.import_logs for select to authenticated
using (app_private.current_user_is_active() and app_private.is_super_admin());
