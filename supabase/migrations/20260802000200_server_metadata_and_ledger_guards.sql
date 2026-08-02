-- Server-authoritative pull cursor metadata for Milestone 12B.

create or replace function app_private.set_server_sync_metadata()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.server_updated_at := statement_timestamp();
    new.server_version := 1;
  else
    new.server_updated_at := statement_timestamp();
    new.server_version := old.server_version + 1;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

revoke all on function app_private.set_server_sync_metadata() from public, anon, authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'branches', 'rooms', 'users', 'item_categories', 'items', 'item_batches',
    'stock_locations', 'stock_balances', 'stock_movements', 'stock_opnames',
    'stock_opname_lines', 'purchase_requests', 'purchase_request_opnames',
    'purchase_request_lines', 'delivery_orders', 'delivery_order_lines',
    'good_receipts', 'good_receipt_lines', 'distributions', 'distribution_lines',
    'disposals', 'disposal_lines', 'consumptions', 'consumption_lines',
    'goods_returns', 'goods_return_lines', 'export_logs', 'import_logs'
  ]
  loop
    execute format(
      'create trigger %I before insert or update on public.%I '
      'for each row execute function app_private.set_server_sync_metadata()',
      'trg_' || table_name || '_server_metadata',
      table_name
    );
  end loop;
end;
$$;

create or replace function app_private.reject_immutable_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = format('%I is append-only', tg_table_name);
end;
$$;

revoke all on function app_private.reject_immutable_mutation() from public, anon, authenticated;

create trigger trg_stock_movements_append_only
before update or delete on public.stock_movements
for each row execute function app_private.reject_immutable_mutation();

create trigger trg_export_logs_append_only
before update or delete on public.export_logs
for each row execute function app_private.reject_immutable_mutation();

-- Domain users are historical business actors. Deleting an Auth identity removes
-- only its link (the FK is owned by user_auth_links), never the domain user.
create or replace function app_private.reject_domain_user_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = '55000', message = 'domain users cannot be deleted';
end;
$$;

revoke all on function app_private.reject_domain_user_delete() from public, anon, authenticated;

create trigger trg_users_no_delete
before delete on public.users
for each row execute function app_private.reject_domain_user_delete();
