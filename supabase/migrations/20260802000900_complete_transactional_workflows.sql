-- Complete Milestone 12B workflow validators. These functions replace the
-- deliberately small infrastructure implementations from migration 007 while
-- keeping its public RPC signature stable.

-- Identity resolution and activation are deliberately separate. This lets RPCs
-- return the stable `sync_user_inactive` code instead of misclassifying a linked
-- but disabled account as unlinked; every RLS policy still checks activation.
create or replace function app_private.current_domain_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select link.user_id from public.user_auth_links link
  where link.auth_user_id=(select auth.uid()) limit 1;
$$;

create or replace function app_private.normalized_movement_business_plan(plan jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'movement_type', value->>'movement_type',
        'item_id', value->>'item_id',
        'batch_id', nullif(value->>'batch_id', ''),
        'from_location_id', nullif(value->>'from_location_id', ''),
        'to_location_id', nullif(value->>'to_location_id', ''),
        'qty', (value->>'qty')::bigint,
        'note', nullif(btrim(value->>'note'), ''),
        'reversal_of_movement_id', nullif(value->>'reversal_of_movement_id', '')
      ) order by
        value->>'movement_type', value->>'item_id', coalesce(value->>'batch_id',''),
        coalesce(value->>'from_location_id',''), coalesce(value->>'to_location_id',''),
        (value->>'qty')::bigint, coalesce(value->>'reversal_of_movement_id','')
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(plan, '[]'::jsonb));
$$;

create or replace function app_private.assert_exact_movement_plan(
  expected_plan jsonb,
  supplied_plan jsonb,
  expected_ref_type text,
  expected_ref_id uuid,
  expected_actor_id uuid,
  expected_occurred_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare movement jsonb;
begin
  if jsonb_typeof(expected_plan) <> 'array'
    or jsonb_typeof(supplied_plan) <> 'array'
    or jsonb_array_length(expected_plan) <> jsonb_array_length(supplied_plan)
    or jsonb_array_length(supplied_plan) > 500
    or app_private.normalized_movement_business_plan(expected_plan)
       <> app_private.normalized_movement_business_plan(supplied_plan) then
    raise exception using errcode='22023', message='sync_movement_plan_mismatch';
  end if;
  if (select count(*) <> count(distinct value->>'id')
      from jsonb_array_elements(supplied_plan)) then
    raise exception using errcode='22023', message='sync_movement_plan_mismatch';
  end if;
  for movement in select value from jsonb_array_elements(supplied_plan) loop
    perform (movement->>'id')::uuid;
    if movement->>'ref_doc_type' <> expected_ref_type
      or (movement->>'ref_doc_id')::uuid <> expected_ref_id
      or (movement ? 'actor_user_id'
        and (movement->>'actor_user_id')::uuid <> expected_actor_id)
      or coalesce((movement->>'created_at')::timestamptz, expected_occurred_at)
        <> expected_occurred_at then
      raise exception using errcode='22023', message='sync_movement_plan_mismatch';
    end if;
  end loop;
end;
$$;

create or replace function app_private.lock_balance_positions(movement_plan jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare candidate_position record;
begin
  -- Create every missing cache row before taking locks. Partial unique indexes
  -- make concurrent creators converge on the same balance position.
  for candidate_position in
    with positions as (
      select nullif(value->>'from_location_id','')::uuid as location_id,
             (value->>'item_id')::uuid as item_id,
             nullif(value->>'batch_id','')::uuid as batch_id
      from jsonb_array_elements(movement_plan)
      union
      select nullif(value->>'to_location_id','')::uuid,
             (value->>'item_id')::uuid,
             nullif(value->>'batch_id','')::uuid
      from jsonb_array_elements(movement_plan)
    )
    select * from positions where location_id is not null
    order by location_id, item_id, coalesce(batch_id, '00000000-0000-0000-0000-000000000000'::uuid)
  loop
    if candidate_position.batch_id is null then
      insert into public.stock_balances
        (id,created_at,updated_at,sync_status,location_id,item_id,batch_id,qty_on_hand)
      values (gen_random_uuid(),now(),now(),'synced',candidate_position.location_id,candidate_position.item_id,null,0)
      on conflict (location_id,item_id) where batch_id is null do nothing;
    else
      insert into public.stock_balances
        (id,created_at,updated_at,sync_status,location_id,item_id,batch_id,qty_on_hand)
      values (gen_random_uuid(),now(),now(),'synced',candidate_position.location_id,candidate_position.item_id,candidate_position.batch_id,0)
      on conflict (location_id,item_id,batch_id) where batch_id is not null do nothing;
    end if;
  end loop;

  -- PostgreSQL acquires these row locks in this explicit composite order for
  -- every workflow, never in user payload order.
  perform balance.id
  from public.stock_balances as balance
  join (
    select distinct location_id,item_id,batch_id from (
      select nullif(value->>'from_location_id','')::uuid as location_id,
             (value->>'item_id')::uuid as item_id,
             nullif(value->>'batch_id','')::uuid as batch_id
      from jsonb_array_elements(movement_plan)
      union all
      select nullif(value->>'to_location_id','')::uuid,
             (value->>'item_id')::uuid,
             nullif(value->>'batch_id','')::uuid
      from jsonb_array_elements(movement_plan)
    ) as raw_positions where location_id is not null
  ) as locked_position
    on balance.location_id=locked_position.location_id
   and balance.item_id=locked_position.item_id
   and balance.batch_id is not distinct from locked_position.batch_id
  order by locked_position.location_id,locked_position.item_id,
    coalesce(locked_position.batch_id,'00000000-0000-0000-0000-000000000000'::uuid)
  for update of balance;
end;
$$;

create or replace function app_private.post_verified_plan(
  movement_plan jsonb,
  expected_ref_type text,
  expected_ref_id uuid,
  actor_id uuid,
  occurred_at_utc timestamptz
)
returns uuid[]
language plpgsql
security definer
set search_path = ''
as $$
declare movement jsonb; movement_ids uuid[] := array[]::uuid[]; movement_id uuid;
begin
  if jsonb_typeof(movement_plan) <> 'array' or jsonb_array_length(movement_plan)>500 then
    raise exception using errcode='22023',message='sync_movement_plan_mismatch';
  end if;
  perform app_private.lock_balance_positions(movement_plan);
  for movement in select value from jsonb_array_elements(movement_plan) order by value->>'id' loop
    movement_id := (movement->>'id')::uuid;
    if movement->>'ref_doc_type'<>expected_ref_type
      or (movement->>'ref_doc_id')::uuid<>expected_ref_id
      or (movement->>'qty')::bigint<=0 then
      raise exception using errcode='22023',message='sync_movement_plan_mismatch';
    end if;
    if exists(select 1 from public.stock_movements where id=movement_id) then
      if not exists(
        select 1 from public.stock_movements as existing where existing.id=movement_id
          and existing.item_id=(movement->>'item_id')::uuid
          and existing.batch_id is not distinct from nullif(movement->>'batch_id','')::uuid
          and existing.from_location_id is not distinct from nullif(movement->>'from_location_id','')::uuid
          and existing.to_location_id is not distinct from nullif(movement->>'to_location_id','')::uuid
          and existing.qty=(movement->>'qty')::bigint
          and existing.movement_type=movement->>'movement_type'
          and existing.ref_doc_type=expected_ref_type and existing.ref_doc_id=expected_ref_id
          and existing.actor_user_id=actor_id
          and existing.note is not distinct from nullif(btrim(movement->>'note'),'')
          and existing.reversal_of_movement_id is not distinct from
            nullif(movement->>'reversal_of_movement_id','')::uuid
      ) then
        raise exception using errcode='23505',message='sync_movement_plan_mismatch';
      end if;
      movement_ids:=array_append(movement_ids,movement_id);
      continue;
    end if;
    if nullif(movement->>'from_location_id','') is not null then
      perform app_private.apply_balance_delta(
        (movement->>'from_location_id')::uuid,(movement->>'item_id')::uuid,
        nullif(movement->>'batch_id','')::uuid,-(movement->>'qty')::bigint,occurred_at_utc);
    end if;
    if nullif(movement->>'to_location_id','') is not null then
      perform app_private.apply_balance_delta(
        (movement->>'to_location_id')::uuid,(movement->>'item_id')::uuid,
        nullif(movement->>'batch_id','')::uuid,(movement->>'qty')::bigint,occurred_at_utc);
    end if;
    insert into public.stock_movements
      (id,created_at,updated_at,sync_status,item_id,batch_id,from_location_id,
       to_location_id,qty,movement_type,ref_doc_type,ref_doc_id,actor_user_id,note,
       reversal_of_movement_id)
    values (movement_id,occurred_at_utc,occurred_at_utc,'synced',
      (movement->>'item_id')::uuid,nullif(movement->>'batch_id','')::uuid,
      nullif(movement->>'from_location_id','')::uuid,
      nullif(movement->>'to_location_id','')::uuid,(movement->>'qty')::bigint,
      movement->>'movement_type',expected_ref_type,expected_ref_id,actor_id,
      nullif(movement->>'note',''),nullif(movement->>'reversal_of_movement_id','')::uuid);
    movement_ids:=array_append(movement_ids,movement_id);
  end loop;
  return movement_ids;
end;
$$;

create or replace function app_private.require_snapshot_time(
  created_at_utc timestamptz, occurred_at_utc timestamptz
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if created_at_utc is null or occurred_at_utc < created_at_utc
    or occurred_at_utc > now() + interval '5 minutes' then
    raise exception using errcode='22023',message='sync_invalid_payload';
  end if;
end;
$$;

revoke all on function app_private.normalized_movement_business_plan(jsonb) from public,anon,authenticated;
revoke all on function app_private.assert_exact_movement_plan(jsonb,jsonb,text,uuid,uuid,timestamptz) from public,anon,authenticated;
revoke all on function app_private.lock_balance_positions(jsonb) from public,anon,authenticated;
revoke all on function app_private.require_snapshot_time(timestamptz,timestamptz) from public,anon,authenticated;

create or replace function app_private.sync_upsert_master_complete(
  aggregate_type text, aggregate_id uuid, actor_id uuid, base_version bigint,
  occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current_version bigint; updated timestamptz;
  changed bigint; requested_role text; requested_active boolean; location jsonb;
begin
  select * into actor from public.users where id=actor_id for share;
  if actor.role<>'super_admin' then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  perform app_private.require_snapshot_time(
    coalesce((payload->>'created_at')::timestamptz,occurred_at),occurred_at);

  if aggregate_type='branch' then
    insert into public.branches
      (id,created_at,updated_at,deleted_at,sync_status,code,name,address,is_active)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',btrim(payload->>'code'),
      btrim(payload->>'name'),nullif(btrim(payload->>'address'),''),
      coalesce((payload->>'is_active')::boolean,true))
    on conflict (id) do update set code=excluded.code,name=excluded.name,
      address=excluded.address,is_active=excluded.is_active,deleted_at=excluded.deleted_at,
      updated_at=excluded.updated_at,sync_status='synced'
    where public.branches.server_version=base_version
      and public.branches.code=excluded.code;
    get diagnostics changed=row_count;
    if jsonb_typeof(payload->'stock_locations')<>'array'
      or jsonb_array_length(payload->'stock_locations')<>1 then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    location:=payload->'stock_locations'->0;
    if location->>'type'<>'branch_store'
      or (location->>'branch_id')::uuid<>aggregate_id
      or nullif(location->>'room_id','') is not null then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    insert into public.stock_locations
      (id,created_at,updated_at,deleted_at,sync_status,type,branch_id,room_id,name)
    values ((location->>'id')::uuid,(location->>'created_at')::timestamptz,occurred_at,
      nullif(location->>'deleted_at','')::timestamptz,'synced','branch_store',
      aggregate_id,null,btrim(location->>'name'))
    on conflict (id) do update set name=excluded.name,updated_at=excluded.updated_at,
      sync_status='synced'
    where public.stock_locations.type='branch_store'
      and public.stock_locations.branch_id=aggregate_id
      and public.stock_locations.room_id is null;
  elsif aggregate_type='category' then
    insert into public.item_categories
      (id,created_at,updated_at,deleted_at,sync_status,name)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',btrim(payload->>'name'))
    on conflict (id) do update set name=excluded.name,deleted_at=excluded.deleted_at,
      updated_at=excluded.updated_at,sync_status='synced'
    where public.item_categories.server_version=base_version
      and public.item_categories.name=excluded.name;
    get diagnostics changed=row_count;
  elsif aggregate_type='room' then
    if not exists(select 1 from public.branches where id=(payload->>'branch_id')::uuid
      and deleted_at is null) then
      raise exception using errcode='23503',message='sync_dependency_missing';
    end if;
    insert into public.rooms
      (id,created_at,updated_at,deleted_at,sync_status,branch_id,code,name,is_active)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',
      (payload->>'branch_id')::uuid,btrim(payload->>'code'),btrim(payload->>'name'),
      coalesce((payload->>'is_active')::boolean,true))
    on conflict (id) do update set branch_id=excluded.branch_id,code=excluded.code,
      name=excluded.name,is_active=excluded.is_active,deleted_at=excluded.deleted_at,
      updated_at=excluded.updated_at,sync_status='synced'
    where public.rooms.server_version=base_version
      and public.rooms.branch_id=excluded.branch_id
      and public.rooms.code=excluded.code;
    get diagnostics changed=row_count;
    if jsonb_typeof(payload->'stock_locations')<>'array'
      or jsonb_array_length(payload->'stock_locations')<>1 then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    location:=payload->'stock_locations'->0;
    if location->>'type'<>'room' or (location->>'room_id')::uuid<>aggregate_id
      or (location->>'branch_id')::uuid<>(payload->>'branch_id')::uuid then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    insert into public.stock_locations
      (id,created_at,updated_at,deleted_at,sync_status,type,branch_id,room_id,name)
    values ((location->>'id')::uuid,(location->>'created_at')::timestamptz,occurred_at,
      nullif(location->>'deleted_at','')::timestamptz,'synced','room',
      (payload->>'branch_id')::uuid,aggregate_id,btrim(location->>'name'))
    on conflict (id) do update set name=excluded.name,updated_at=excluded.updated_at,
      sync_status='synced'
    where public.stock_locations.type='room'
      and public.stock_locations.branch_id=(payload->>'branch_id')::uuid
      and public.stock_locations.room_id=aggregate_id;
  elsif aggregate_type='item' then
    if not exists(select 1 from public.item_categories
      where id=(payload->>'category_id')::uuid and deleted_at is null) then
      raise exception using errcode='23503',message='sync_dependency_missing';
    end if;
    insert into public.items
      (id,created_at,updated_at,deleted_at,sync_status,sku,name,category_id,unit,
       min_stock_room,min_stock_branch,has_expiry,expiry_alert_days,is_active)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',btrim(payload->>'sku'),
      btrim(payload->>'name'),(payload->>'category_id')::uuid,btrim(payload->>'unit'),
      (payload->>'min_stock_room')::bigint,(payload->>'min_stock_branch')::bigint,
      (payload->>'has_expiry')::boolean,(payload->>'expiry_alert_days')::integer,
      coalesce((payload->>'is_active')::boolean,true))
    on conflict (id) do update set name=excluded.name,category_id=excluded.category_id,
      unit=excluded.unit,min_stock_room=excluded.min_stock_room,
      min_stock_branch=excluded.min_stock_branch,expiry_alert_days=excluded.expiry_alert_days,
      is_active=excluded.is_active,deleted_at=excluded.deleted_at,
      updated_at=excluded.updated_at,sync_status='synced'
    where public.items.server_version=base_version
      and public.items.sku=excluded.sku
      and public.items.has_expiry=excluded.has_expiry;
    get diagnostics changed=row_count;
  elsif aggregate_type='batch' then
    if not exists(select 1 from public.items where id=(payload->>'item_id')::uuid) then
      raise exception using errcode='23503',message='sync_dependency_missing';
    end if;
    insert into public.item_batches
      (id,created_at,updated_at,deleted_at,sync_status,item_id,batch_no,expiry_date)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',
      (payload->>'item_id')::uuid,btrim(payload->>'batch_no'),
      (payload->>'expiry_date')::date)
    on conflict (id) do update set expiry_date=excluded.expiry_date,
      deleted_at=excluded.deleted_at,updated_at=excluded.updated_at,sync_status='synced'
    where public.item_batches.server_version=base_version
      and public.item_batches.item_id=excluded.item_id
      and public.item_batches.batch_no=excluded.batch_no;
    get diagnostics changed=row_count;
  elsif aggregate_type='stock_location' then
    if payload->>'type' not in ('warehouse','branch_store','room') then
      raise exception using errcode='22023',message='sync_invalid_payload';
    end if;
    insert into public.stock_locations
      (id,created_at,updated_at,deleted_at,sync_status,type,branch_id,room_id,name)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',payload->>'type',
      nullif(payload->>'branch_id','')::uuid,nullif(payload->>'room_id','')::uuid,
      btrim(payload->>'name'))
    on conflict (id) do update set name=excluded.name,deleted_at=excluded.deleted_at,
      updated_at=excluded.updated_at,sync_status='synced'
    where public.stock_locations.server_version=base_version
      and public.stock_locations.type=excluded.type
      and public.stock_locations.branch_id is not distinct from excluded.branch_id
      and public.stock_locations.room_id is not distinct from excluded.room_id;
    get diagnostics changed=row_count;
  elsif aggregate_type='user' then
    requested_role:=payload->>'role';
    requested_active:=coalesce((payload->>'is_active')::boolean,true);
    if requested_role not in ('perawat','kepala_cabang','warehouse','super_admin') then
      raise exception using errcode='22023',message='sync_invalid_payload';
    end if;
    if aggregate_id=actor_id and (requested_role<>'super_admin' or not requested_active
      or nullif(payload->>'deleted_at','') is not null) then
      raise exception using errcode='42501',message='sync_access_denied';
    end if;
    if exists(select 1 from public.users where id=aggregate_id and role='super_admin'
      and is_active and deleted_at is null)
      and (requested_role<>'super_admin' or not requested_active
        or nullif(payload->>'deleted_at','') is not null)
      and (select count(*) from public.users where role='super_admin' and is_active
        and deleted_at is null)<=1 then
      raise exception using errcode='23514',message='sync_access_denied';
    end if;
    insert into public.users
      (id,created_at,updated_at,deleted_at,sync_status,full_name,email,role,branch_id,is_active)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',btrim(payload->>'full_name'),
      lower(btrim(payload->>'email')),requested_role,nullif(payload->>'branch_id','')::uuid,
      requested_active)
    on conflict (id) do update set full_name=excluded.full_name,email=excluded.email,
      role=excluded.role,branch_id=excluded.branch_id,is_active=excluded.is_active,
      deleted_at=excluded.deleted_at,updated_at=excluded.updated_at,sync_status='synced'
    where public.users.server_version=base_version
      and public.users.email=excluded.email;
    get diagnostics changed=row_count;
  else
    raise exception using errcode='22023',message='sync_invalid_payload';
  end if;

  if changed=0 then
    raise exception using errcode='40001',message='sync_stale_version';
  end if;
  execute format('select server_version,server_updated_at from public.%I where id=$1',
    case aggregate_type when 'branch' then 'branches' when 'room' then 'rooms'
      when 'user' then 'users' when 'category' then 'item_categories'
      when 'item' then 'items' when 'batch' then 'item_batches'
      else 'stock_locations' end)
    into current_version,updated using aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',current_version,
    'server_updated_at_utc',updated,'movement_ids','[]'::jsonb);
exception
  when unique_violation then
    raise exception using errcode='23505',message='sync_final_state_conflict';
end;
$$;

create or replace function app_private.sync_append_audit_complete(
  operation_type text, aggregate_id uuid, actor_id uuid,
  occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; version bigint; updated timestamptz;
  remote_key text;
begin
  select * into actor from public.users where id=actor_id for share;
  if operation_type='append_import_audit' then
    if actor.role<>'super_admin' or (payload->>'imported_by')::uuid<>actor_id then
      raise exception using errcode='42501',message='sync_access_denied';
    end if;
    select object.object_key into remote_key from public.remote_file_objects as object
      where object.entity_type='import_audit' and object.entity_id=aggregate_id
        and object.actor_user_id=actor_id;
    if remote_key is null then
      raise exception using errcode='23503',message='sync_dependency_pending';
    end if;
    insert into public.import_logs
      (id,created_at,updated_at,deleted_at,sync_status,entity,file_name,total_rows,
       inserted_rows,updated_rows,failed_rows,error_detail,status,imported_by,
       stored_file_path,file_sha256,file_size_bytes,template_version)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',payload->>'entity',
      payload->>'file_name',(payload->>'total_rows')::integer,
      (payload->>'inserted_rows')::integer,(payload->>'updated_rows')::integer,
      (payload->>'failed_rows')::integer,nullif(payload->>'error_detail',''),
      payload->>'status',actor_id,remote_key,payload->>'file_sha256',
      (payload->>'file_size_bytes')::bigint,payload->>'template_version');
    select server_version,server_updated_at into version,updated from public.import_logs where id=aggregate_id;
  elsif operation_type='append_export_audit' then
    if (payload->>'exported_by')::uuid<>actor_id then
      raise exception using errcode='42501',message='sync_actor_mismatch';
    end if;
    insert into public.export_logs
      (id,created_at,updated_at,deleted_at,sync_status,report_type,format,scope_type,
       location_id,category_id,branch_id,item_id,period_start,period_end,exported_by,
       file_name,data_cutoff_at,sync_summary,row_count)
    values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,
      nullif(payload->>'deleted_at','')::timestamptz,'synced',payload->>'report_type',
      payload->>'format',payload->>'scope_type',nullif(payload->>'location_id','')::uuid,
      nullif(payload->>'category_id','')::uuid,nullif(payload->>'branch_id','')::uuid,
      nullif(payload->>'item_id','')::uuid,(payload->>'period_start')::date,
      (payload->>'period_end')::date,actor_id,payload->>'file_name',
      (payload->>'data_cutoff_at')::timestamptz,payload->>'sync_summary',
      (payload->>'row_count')::integer);
    select server_version,server_updated_at into version,updated from public.export_logs where id=aggregate_id;
  else
    raise exception using errcode='22023',message='sync_invalid_payload';
  end if;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'movement_ids','[]'::jsonb);
exception when unique_violation then
  if operation_type='append_import_audit' and exists(select 1 from public.import_logs where id=aggregate_id)
    or operation_type='append_export_audit' and exists(select 1 from public.export_logs where id=aggregate_id) then
    return jsonb_build_object('outcome','accepted','server_version',1,
      'server_updated_at_utc',now(),'movement_ids','[]'::jsonb);
  end if;
  raise;
end;
$$;

revoke all on function app_private.sync_upsert_master_complete(text,uuid,uuid,bigint,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function app_private.sync_append_audit_complete(text,uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;

create or replace function app_private.sync_submit_purchase_request(
  aggregate_id uuid, actor_id uuid, base_version bigint,
  occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.purchase_requests%rowtype;
  v_branch_id uuid; number text; line jsonb; version bigint; updated timestamptz;
begin
  select * into actor from public.users where id=actor_id for share;
  v_branch_id:=(payload->>'branch_id')::uuid;
  if actor.role<>'kepala_cabang' or actor.branch_id<>v_branch_id
    or (payload ? 'requested_by' and (payload->>'requested_by')::uuid<>actor_id) then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  perform app_private.require_snapshot_time((payload->>'created_at')::timestamptz,occurred_at);
  if jsonb_typeof(payload->'lines')<>'array' or jsonb_array_length(payload->'lines')=0
    or jsonb_array_length(payload->'lines')>500
    or (select count(*)<>count(distinct value->>'item_id')
        from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  select * into current from public.purchase_requests where id=aggregate_id for update;
  if found then
    if current.status='submitted' and current.branch_id=v_branch_id
      and current.requested_by=actor_id
      and (select count(*) from public.purchase_request_lines where pr_id=aggregate_id
        and deleted_at is null)=jsonb_array_length(payload->'lines')
      and not exists(
        select 1 from jsonb_array_elements(payload->'lines') as supplied
        left join public.purchase_request_lines as stored
          on stored.id=(supplied.value->>'id')::uuid and stored.pr_id=aggregate_id
         and stored.deleted_at is null
        where stored.id is null or stored.item_id<>(supplied.value->>'item_id')::uuid
          or stored.requested_qty<>(supplied.value->>'requested_qty')::bigint
          or stored.suggested_qty<>(supplied.value->>'suggested_qty')::bigint
      ) then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,'movement_ids','[]'::jsonb);
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Data final server berbeda.','base_server_version',base_version,
      'server_version',current.server_version);
  end if;
  if exists(select 1 from public.purchase_requests where branch_id=v_branch_id
    and status in ('submitted','processing') and deleted_at is null) then
    raise exception using errcode='23505',message='sync_final_state_conflict';
  end if;
  if jsonb_typeof(coalesce(payload->'opname_links','[]'::jsonb))<>'array'
    or jsonb_array_length(coalesce(payload->'opname_links','[]'::jsonb))=0 then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  number:=app_private.allocate_document_number('PR',v_branch_id,occurred_at);
  insert into public.purchase_requests
    (id,created_at,updated_at,sync_status,doc_number,branch_id,requested_by,status,
     needed_date,note,submitted_at)
  values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,'synced',number,
    v_branch_id,actor_id,'submitted',nullif(payload->>'needed_date','')::date,
    nullif(btrim(payload->>'note'),''),occurred_at);
  for line in select value from jsonb_array_elements(payload->'lines') loop
    if (line->>'requested_qty')::bigint<=0 or (line->>'suggested_qty')::bigint<0
      or not exists(select 1 from public.items where id=(line->>'item_id')::uuid) then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    insert into public.purchase_request_lines
      (id,created_at,updated_at,sync_status,pr_id,item_id,suggested_qty,requested_qty,note)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'item_id')::uuid,
      (line->>'suggested_qty')::bigint,(line->>'requested_qty')::bigint,
      nullif(btrim(line->>'note'),''));
  end loop;
  for line in select value from jsonb_array_elements(payload->'opname_links') loop
    if not exists(select 1 from public.stock_opnames where id=(line->>'opname_id')::uuid
      and branch_id=v_branch_id and status in ('submitted','reviewed')) then
      raise exception using errcode='23503',message='sync_dependency_missing';
    end if;
    insert into public.purchase_request_opnames
      (id,created_at,updated_at,sync_status,pr_id,opname_id)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'opname_id')::uuid);
  end loop;
  select server_version,server_updated_at into version,updated
    from public.purchase_requests where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'final_document_number',number,
    'movement_ids','[]'::jsonb);
end;
$$;

create or replace function app_private.sync_transition_purchase_request_complete(
  operation_type text, aggregate_id uuid, actor_id uuid, base_version bigint,
  occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.purchase_requests%rowtype;
begin
  select * into actor from public.users where id=actor_id for share;
  select * into current from public.purchase_requests where id=aggregate_id for update;
  if not found then raise exception using errcode='P0002',message='sync_document_not_found'; end if;
  if base_version>0 and current.server_version<>base_version then
    return jsonb_build_object('outcome','conflict','code','sync_stale_version',
      'message','Versi server lebih baru.','base_server_version',base_version,
      'server_version',current.server_version);
  end if;
  if operation_type='process_purchase_request' then
    if actor.role<>'warehouse' then raise exception using errcode='42501',message='sync_access_denied'; end if;
    if current.status='processing' and current.processed_by=actor_id then
      null;
    elsif current.status='submitted' then
      update public.purchase_requests set status='processing',processing_at=occurred_at,
        processed_by=actor_id,updated_at=occurred_at,sync_status='synced' where id=aggregate_id;
    else
      return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
        'message','Status server sudah berbeda.','base_server_version',base_version,
        'server_version',current.server_version);
    end if;
  elsif operation_type='reject_purchase_request' then
    if actor.role<>'warehouse' or nullif(btrim(payload->>'reject_reason'),'') is null then
      raise exception using errcode='42501',message='sync_access_denied';
    end if;
    if current.status='rejected' and current.rejected_by=actor_id
      and current.reject_reason=payload->>'reject_reason' then null;
    elsif current.status='processing' then
      update public.purchase_requests set status='rejected',rejected_at=occurred_at,
        rejected_by=actor_id,reject_reason=btrim(payload->>'reject_reason'),
        updated_at=occurred_at,sync_status='synced' where id=aggregate_id;
    else
      return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
        'message','Status server sudah berbeda.','base_server_version',base_version,
        'server_version',current.server_version);
    end if;
  elsif operation_type='cancel_purchase_request' then
    if actor.role<>'kepala_cabang' or actor.branch_id<>current.branch_id
      or nullif(btrim(payload->>'cancel_reason'),'') is null then
      raise exception using errcode='42501',message='sync_access_denied';
    end if;
    if current.status='cancelled' and current.cancelled_by=actor_id
      and current.cancel_reason=payload->>'cancel_reason' then null;
    elsif current.status in ('draft','submitted') then
      update public.purchase_requests set status='cancelled',cancelled_at=occurred_at,
        cancelled_by=actor_id,cancel_reason=btrim(payload->>'cancel_reason'),
        updated_at=occurred_at,sync_status='synced' where id=aggregate_id;
    else
      return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
        'message','Status server sudah berbeda.','base_server_version',base_version,
        'server_version',current.server_version);
    end if;
  else raise exception using errcode='22023',message='sync_invalid_payload';
  end if;
  select * into current from public.purchase_requests where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',current.server_version,
    'server_updated_at_utc',current.server_updated_at,
    'final_document_number',current.doc_number,'movement_ids','[]'::jsonb);
end;
$$;

revoke all on function app_private.sync_transition_purchase_request_complete(text,uuid,uuid,bigint,timestamptz,jsonb) from public,anon,authenticated;

create or replace function app_private.sync_submit_opname_complete(
  aggregate_id uuid, actor_id uuid, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.stock_opnames%rowtype;
  number text; line jsonb; version bigint; updated timestamptz;
begin
  select * into actor from public.users where id=actor_id for share;
  if actor.role<>'perawat' or actor.branch_id<>(payload->>'branch_id')::uuid
    or (payload ? 'counted_by' and (payload->>'counted_by')::uuid<>actor_id)
    or not exists(select 1 from public.rooms where id=(payload->>'room_id')::uuid
      and branch_id=actor.branch_id and is_active and deleted_at is null) then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  perform app_private.require_snapshot_time((payload->>'created_at')::timestamptz,occurred_at);
  if jsonb_typeof(payload->'lines')<>'array' or jsonb_array_length(payload->'lines')=0
    or jsonb_array_length(payload->'lines')>500
    or (select count(*)<>count(distinct (value->>'item_id')||'|'||coalesce(value->>'batch_id',''))
        from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  select * into current from public.stock_opnames where id=aggregate_id for update;
  if found then
    if current.status='submitted' and current.counted_by=actor_id
      and current.branch_id=actor.branch_id
      and (select count(*) from public.stock_opname_lines where opname_id=aggregate_id
        and deleted_at is null)=jsonb_array_length(payload->'lines') then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,'movement_ids','[]'::jsonb);
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Data final server berbeda.','base_server_version',0,
      'server_version',current.server_version);
  end if;
  number:=app_private.allocate_document_number('SO',actor.branch_id,occurred_at);
  insert into public.stock_opnames
    (id,created_at,updated_at,sync_status,doc_number,branch_id,room_id,period_year,
     period_week,counted_by,status,submitted_at)
  values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,'synced',number,
    actor.branch_id,(payload->>'room_id')::uuid,(payload->>'period_year')::integer,
    (payload->>'period_week')::integer,actor_id,'submitted',occurred_at);
  for line in select value from jsonb_array_elements(payload->'lines') loop
    if (line->>'system_qty')::bigint<0 or (line->>'counted_qty')::bigint<0
      or ((line->>'system_qty')::bigint<>(line->>'counted_qty')::bigint
        and nullif(btrim(line->>'note'),'') is null)
      or not exists(select 1 from public.items where id=(line->>'item_id')::uuid)
      or (nullif(line->>'batch_id','') is not null and not exists(
        select 1 from public.item_batches where id=(line->>'batch_id')::uuid
          and item_id=(line->>'item_id')::uuid)) then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    insert into public.stock_opname_lines
      (id,created_at,updated_at,sync_status,opname_id,item_id,batch_id,system_qty,
       counted_qty,note)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'item_id')::uuid,
      nullif(line->>'batch_id','')::uuid,(line->>'system_qty')::bigint,
      (line->>'counted_qty')::bigint,nullif(btrim(line->>'note'),''));
  end loop;
  select server_version,server_updated_at into version,updated from public.stock_opnames where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'final_document_number',number,
    'movement_ids','[]'::jsonb);
exception when unique_violation then
  raise exception using errcode='23505',message='sync_final_state_conflict';
end;
$$;

create or replace function app_private.sync_review_opname_complete(
  aggregate_id uuid, actor_id uuid, base_version bigint,
  occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.stock_opnames%rowtype;
  room_location uuid; expected jsonb; movement_ids uuid[];
begin
  select * into actor from public.users where id=actor_id for share;
  select * into current from public.stock_opnames where id=aggregate_id for update;
  if not found then raise exception using errcode='P0002',message='sync_document_not_found'; end if;
  if actor.role<>'kepala_cabang' or actor.branch_id<>current.branch_id
    or actor_id=current.counted_by then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  if current.status='reviewed' then
    if current.reviewed_by=actor_id and not exists(
      select 1 from jsonb_array_elements(coalesce(payload->'movements','[]'::jsonb)) supplied
      where not exists(select 1 from public.stock_movements stored
        where stored.id=(supplied.value->>'id')::uuid and stored.ref_doc_type='SO'
          and stored.ref_doc_id=aggregate_id)) then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,
        'movement_ids',(select coalesce(jsonb_agg(value->>'id'),'[]'::jsonb)
          from jsonb_array_elements(coalesce(payload->'movements','[]'::jsonb))));
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Opname server sudah final.','base_server_version',base_version,
      'server_version',current.server_version);
  end if;
  if current.status<>'submitted' then
    raise exception using errcode='22023',message='sync_document_state_invalid';
  end if;
  if payload->>'doc_number'<>current.doc_number
    and payload->>'doc_number' not like 'TMP-SO-%' then
    raise exception using errcode='22023',message='sync_invalid_payload';
  end if;
  if base_version>0 and current.server_version<>base_version then
    return jsonb_build_object('outcome','conflict','code','sync_stale_version',
      'message','Versi server lebih baru.','base_server_version',base_version,
      'server_version',current.server_version);
  end if;
  select id into room_location from public.stock_locations where type='room'
    and room_id=current.room_id and branch_id=current.branch_id and deleted_at is null;
  if room_location is null then raise exception using errcode='23503',message='sync_dependency_missing'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'movement_type','opname_adjustment','item_id',line.item_id::text,
      'batch_id',line.batch_id::text,
      'from_location_id',case when line.counted_qty<coalesce(balance.qty_on_hand,0)
        then room_location::text end,
      'to_location_id',case when line.counted_qty>coalesce(balance.qty_on_hand,0)
        then room_location::text end,
      'qty',abs(line.counted_qty-coalesce(balance.qty_on_hand,0)),
      'note','Penyesuaian stok opname '||(payload->>'doc_number')||
        case when nullif(btrim(line.note),'') is null then ''
          else ' — '||btrim(line.note) end)),'[]'::jsonb)
    into expected
  from public.stock_opname_lines line
  left join public.stock_balances balance on balance.location_id=room_location
    and balance.item_id=line.item_id and balance.batch_id is not distinct from line.batch_id
  where line.opname_id=aggregate_id and line.deleted_at is null
    and line.counted_qty<>coalesce(balance.qty_on_hand,0);
  perform app_private.assert_exact_movement_plan(expected,payload->'movements','SO',
    aggregate_id,actor_id,occurred_at);
  movement_ids:=app_private.post_verified_plan(payload->'movements','SO',aggregate_id,actor_id,occurred_at);
  update public.stock_opnames set status='reviewed',reviewed_at=occurred_at,
    reviewed_by=actor_id,updated_at=occurred_at,sync_status='synced' where id=aggregate_id;
  select * into current from public.stock_opnames where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',current.server_version,
    'server_updated_at_utc',current.server_updated_at,
    'final_document_number',current.doc_number,'movement_ids',to_jsonb(movement_ids));
end;
$$;

revoke all on function app_private.sync_submit_opname_complete(uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function app_private.sync_review_opname_complete(uuid,uuid,bigint,timestamptz,jsonb) from public,anon,authenticated;

create or replace function app_private.sync_ship_delivery_order_complete(
  aggregate_id uuid, actor_id uuid, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.delivery_orders%rowtype;
  request public.purchase_requests%rowtype; warehouse_id uuid; number text;
  line jsonb; expected jsonb; movement_ids uuid[]; version bigint; updated timestamptz;
  requested bigint; shipped_before bigint; chosen_expiry date;
begin
  select * into actor from public.users where id=actor_id for share;
  if actor.role<>'warehouse' then raise exception using errcode='42501',message='sync_access_denied'; end if;
  perform app_private.require_snapshot_time((payload->>'created_at')::timestamptz,occurred_at);
  select * into current from public.delivery_orders where id=aggregate_id for update;
  if found then
    if current.status in ('shipped','received') and current.shipped_by=actor_id
      and not exists(select 1 from jsonb_array_elements(payload->'movements') supplied
        where not exists(select 1 from public.stock_movements stored
          where stored.id=(supplied.value->>'id')::uuid and stored.ref_doc_type='DO'
            and stored.ref_doc_id=aggregate_id)) then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,
        'movement_ids',(select coalesce(jsonb_agg(value->>'id'),'[]'::jsonb)
          from jsonb_array_elements(payload->'movements')));
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Surat Jalan server sudah final.','base_server_version',0,
      'server_version',current.server_version);
  end if;
  select * into request from public.purchase_requests where id=(payload->>'pr_id')::uuid for update;
  if not found then raise exception using errcode='23503',message='sync_dependency_missing'; end if;
  if request.status<>'processing' then raise exception using errcode='22023',message='sync_document_state_invalid'; end if;
  select id into warehouse_id from public.stock_locations where type='warehouse'
    and deleted_at is null order by id limit 2;
  if warehouse_id is null or (select count(*) from public.stock_locations
      where type='warehouse' and deleted_at is null)<>1 then
    raise exception using errcode='23503',message='sync_dependency_missing';
  end if;
  if jsonb_typeof(payload->'lines')<>'array' or jsonb_array_length(payload->'lines')=0
    or jsonb_array_length(payload->'lines')>500
    or (select count(*)<>count(distinct value->>'id') from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  for line in select value from jsonb_array_elements(payload->'lines') loop
    select pr_line.requested_qty into requested from public.purchase_request_lines pr_line
      where pr_line.id=(line->>'pr_line_id')::uuid and pr_line.pr_id=request.id
        and pr_line.item_id=(line->>'item_id')::uuid and pr_line.deleted_at is null;
    if requested is null or (line->>'shipped_qty')::bigint<=0 then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    select coalesce(sum(existing.shipped_qty),0) into shipped_before
      from public.delivery_order_lines existing
      join public.delivery_orders header on header.id=existing.do_id
      where existing.pr_line_id=(line->>'pr_line_id')::uuid
        and header.status in ('shipped','received') and existing.deleted_at is null;
    if shipped_before+(line->>'shipped_qty')::bigint>requested then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    if exists(select 1 from public.items where id=(line->>'item_id')::uuid and has_expiry) then
      select expiry_date into chosen_expiry from public.item_batches
        where id=(line->>'batch_id')::uuid and item_id=(line->>'item_id')::uuid;
      if chosen_expiry is null then raise exception using errcode='22023',message='sync_batch_invalid'; end if;
      if chosen_expiry < (occurred_at at time zone 'Asia/Makassar')::date then
        raise exception using errcode='22023',message='sync_batch_expired';
      end if;
      if exists(
        select 1 from public.item_batches older
        join public.stock_balances balance on balance.batch_id=older.id
          and balance.location_id=warehouse_id and balance.qty_on_hand>0
        where older.item_id=(line->>'item_id')::uuid
          and older.expiry_date >= (occurred_at at time zone 'Asia/Makassar')::date
          and older.expiry_date<chosen_expiry and older.deleted_at is null
      ) and nullif(btrim(line->>'fefo_override_reason'),'') is null then
        raise exception using errcode='22023',message='sync_fefo_override_required';
      end if;
    elsif nullif(line->>'batch_id','') is not null then
      raise exception using errcode='22023',message='sync_batch_invalid';
    end if;
  end loop;
  select jsonb_agg(jsonb_build_object('movement_type','shipment',
      'item_id',value->>'item_id','batch_id',nullif(value->>'batch_id',''),
      'from_location_id',warehouse_id::text,'to_location_id',null,
      'qty',(value->>'shipped_qty')::bigint,
      'note',nullif(btrim(value->>'fefo_override_reason'),''))) into expected
    from jsonb_array_elements(payload->'lines');
  perform app_private.assert_exact_movement_plan(expected,payload->'movements','DO',aggregate_id,actor_id,occurred_at);
  number:=app_private.allocate_document_number('DO',null,occurred_at);
  insert into public.delivery_orders
    (id,created_at,updated_at,sync_status,doc_number,pr_id,prepared_by,status,
     shipped_at,shipped_by,note)
  values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,'synced',number,
    request.id,actor_id,'shipped',occurred_at,actor_id,nullif(btrim(payload->>'note'),''));
  for line in select value from jsonb_array_elements(payload->'lines') loop
    insert into public.delivery_order_lines
      (id,created_at,updated_at,sync_status,do_id,pr_line_id,item_id,batch_id,
       shipped_qty,fefo_override_reason,near_expiry_confirmed,near_expiry_note)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'pr_line_id')::uuid,
      (line->>'item_id')::uuid,nullif(line->>'batch_id','')::uuid,
      (line->>'shipped_qty')::bigint,nullif(btrim(line->>'fefo_override_reason'),''),
      coalesce((line->>'near_expiry_confirmed')::boolean,false),
      nullif(btrim(line->>'near_expiry_note'),''));
  end loop;
  movement_ids:=app_private.post_verified_plan(payload->'movements','DO',aggregate_id,actor_id,occurred_at);
  if not exists(
    select 1 from public.purchase_request_lines pr_line
    where pr_line.pr_id=request.id and pr_line.deleted_at is null
      and coalesce((select sum(do_line.shipped_qty) from public.delivery_order_lines do_line
        join public.delivery_orders header on header.id=do_line.do_id
        where do_line.pr_line_id=pr_line.id and header.status in ('shipped','received')
          and do_line.deleted_at is null),0)<pr_line.requested_qty
  ) then
    update public.purchase_requests set status='shipped',updated_at=occurred_at,
      sync_status='synced' where id=request.id and status='processing';
  end if;
  select server_version,server_updated_at into version,updated from public.delivery_orders where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'final_document_number',number,
    'movement_ids',to_jsonb(movement_ids));
end;
$$;

revoke all on function app_private.sync_ship_delivery_order_complete(uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;

create or replace function app_private.sync_post_good_receipt_complete(
  aggregate_id uuid, actor_id uuid, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.good_receipts%rowtype;
  shipment public.delivery_orders%rowtype; request public.purchase_requests%rowtype;
  branch_store uuid; number text; line jsonb; expected jsonb; movement_ids uuid[];
  version bigint; updated timestamptz; do_line public.delivery_order_lines%rowtype;
begin
  select * into actor from public.users where id=actor_id for share;
  select * into current from public.good_receipts where id=aggregate_id for update;
  if found then
    if current.status='posted' and current.received_by=actor_id
      and not exists(select 1 from jsonb_array_elements(payload->'movements') supplied
        where not exists(select 1 from public.stock_movements stored
          where stored.id=(supplied.value->>'id')::uuid and stored.ref_doc_type='GR'
            and stored.ref_doc_id=aggregate_id)) then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,
        'movement_ids',(select coalesce(jsonb_agg(value->>'id'),'[]'::jsonb)
          from jsonb_array_elements(payload->'movements')));
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Good Receipt server sudah final.','base_server_version',0,
      'server_version',current.server_version);
  end if;
  select * into shipment from public.delivery_orders where id=(payload->>'do_id')::uuid for update;
  if not found then raise exception using errcode='23503',message='sync_dependency_missing'; end if;
  if shipment.status<>'shipped' then raise exception using errcode='22023',message='sync_document_state_invalid'; end if;
  select * into request from public.purchase_requests where id=shipment.pr_id for update;
  if actor.role<>'kepala_cabang' or actor.branch_id<>request.branch_id then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  if exists(select 1 from public.good_receipts where do_id=shipment.id) then
    raise exception using errcode='23505',message='sync_final_state_conflict';
  end if;
  select id into branch_store from public.stock_locations where type='branch_store'
    and branch_id=request.branch_id and deleted_at is null;
  if branch_store is null or (select count(*) from public.stock_locations
      where type='branch_store' and branch_id=request.branch_id and deleted_at is null)<>1 then
    raise exception using errcode='23503',message='sync_dependency_missing';
  end if;
  if jsonb_typeof(payload->'lines')<>'array'
    or jsonb_array_length(payload->'lines')<>(select count(*) from public.delivery_order_lines
      where do_id=shipment.id and deleted_at is null)
    or (select count(*)<>count(distinct value->>'do_line_id')
      from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  for line in select value from jsonb_array_elements(payload->'lines') loop
    select * into do_line from public.delivery_order_lines
      where id=(line->>'do_line_id')::uuid and do_id=shipment.id and deleted_at is null;
    if not found or do_line.item_id<>(line->>'item_id')::uuid
      or do_line.batch_id is distinct from nullif(line->>'batch_id','')::uuid
      or do_line.shipped_qty<>(line->>'shipped_qty')::bigint
      or (line->>'received_qty')::bigint not between 0 and do_line.shipped_qty
      or line->>'line_status' not in ('checked','rejected')
      or (line->>'line_status'='rejected' and ((line->>'received_qty')::bigint<>0
        or nullif(btrim(line->>'reject_reason'),'') is null))
      or (line->>'line_status'='checked' and nullif(line->>'reject_reason','') is not null) then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    if line->>'line_status'='checked' and do_line.batch_id is not null
      and exists(select 1 from public.item_batches where id=do_line.batch_id
        and expiry_date<(occurred_at at time zone 'Asia/Makassar')::date) then
      raise exception using errcode='22023',message='sync_batch_expired';
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('movement_type','good_receipt',
      'item_id',value->>'item_id','batch_id',nullif(value->>'batch_id',''),
      'from_location_id',null,'to_location_id',branch_store::text,
      'qty',(value->>'received_qty')::bigint,'note',null)),'[]'::jsonb) into expected
    from jsonb_array_elements(payload->'lines')
    where value->>'line_status'='checked' and (value->>'received_qty')::bigint>0;
  perform app_private.assert_exact_movement_plan(expected,payload->'movements','GR',aggregate_id,actor_id,occurred_at);
  number:=app_private.allocate_document_number('GR',request.branch_id,occurred_at);
  insert into public.good_receipts
    (id,created_at,updated_at,sync_status,doc_number,do_id,received_by,status,posted_at)
  values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,'synced',number,
    shipment.id,actor_id,'posted',occurred_at);
  for line in select value from jsonb_array_elements(payload->'lines') loop
    insert into public.good_receipt_lines
      (id,created_at,updated_at,sync_status,gr_id,do_line_id,item_id,batch_id,
       shipped_qty,received_qty,line_status,reject_reason)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'do_line_id')::uuid,
      (line->>'item_id')::uuid,nullif(line->>'batch_id','')::uuid,
      (line->>'shipped_qty')::bigint,(line->>'received_qty')::bigint,
      line->>'line_status',nullif(btrim(line->>'reject_reason'),''));
  end loop;
  movement_ids:=app_private.post_verified_plan(payload->'movements','GR',aggregate_id,actor_id,occurred_at);
  update public.delivery_orders set status='received',updated_at=occurred_at,
    sync_status='synced' where id=shipment.id and status='shipped';
  if request.status='shipped' and not exists(
    select 1 from public.delivery_orders pending
    where pending.pr_id=request.id and pending.status<>'received' and pending.deleted_at is null
  ) then
    update public.purchase_requests set status='closed',updated_at=occurred_at,
      sync_status='synced' where id=request.id;
  end if;
  select server_version,server_updated_at into version,updated from public.good_receipts where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'final_document_number',number,
    'movement_ids',to_jsonb(movement_ids));
end;
$$;

revoke all on function app_private.sync_post_good_receipt_complete(uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;

create or replace function app_private.sync_post_distribution_complete(
  aggregate_id uuid, actor_id uuid, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.distributions%rowtype;
  source_id uuid; number text; line jsonb; expected jsonb; movement_ids uuid[];
  version bigint; updated timestamptz; destination_id uuid; item_has_expiry boolean;
  chosen_expiry date;
begin
  select * into actor from public.users where id=actor_id for share;
  if actor.role<>'kepala_cabang' or actor.branch_id<>(payload->>'branch_id')::uuid then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  select * into current from public.distributions where id=aggregate_id for update;
  if found then
    if current.status='posted' and current.distributed_by=actor_id then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,
        'movement_ids',(select coalesce(jsonb_agg(value->>'id'),'[]'::jsonb)
          from jsonb_array_elements(payload->'movements')));
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Distribusi server sudah final.','base_server_version',0,
      'server_version',current.server_version);
  end if;
  select id into source_id from public.stock_locations where type='branch_store'
    and branch_id=actor.branch_id and deleted_at is null;
  if source_id is null or (select count(*) from public.stock_locations
      where type='branch_store' and branch_id=actor.branch_id and deleted_at is null)<>1 then
    raise exception using errcode='23503',message='sync_dependency_missing';
  end if;
  if jsonb_typeof(payload->'lines')<>'array' or jsonb_array_length(payload->'lines')=0
    or jsonb_array_length(payload->'lines')>500
    or (select count(*)<>count(distinct (value->>'room_id')||'|'||
      (value->>'item_id')||'|'||coalesce(value->>'batch_id',''))
      from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  for line in select value from jsonb_array_elements(payload->'lines') loop
    select location.id into destination_id from public.stock_locations location
      join public.rooms room on room.id=location.room_id
      where room.id=(line->>'room_id')::uuid and room.branch_id=actor.branch_id
        and room.is_active and room.deleted_at is null and location.type='room'
        and location.deleted_at is null;
    select has_expiry into item_has_expiry from public.items
      where id=(line->>'item_id')::uuid;
    if destination_id is null or item_has_expiry is null or (line->>'qty')::bigint<=0 then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
    if item_has_expiry then
      select expiry_date into chosen_expiry from public.item_batches
        where id=(line->>'batch_id')::uuid and item_id=(line->>'item_id')::uuid;
      if chosen_expiry is null then raise exception using errcode='22023',message='sync_batch_invalid'; end if;
      if chosen_expiry<(occurred_at at time zone 'Asia/Makassar')::date then
        raise exception using errcode='22023',message='sync_batch_expired';
      end if;
      if exists(select 1 from public.item_batches older
        join public.stock_balances balance on balance.batch_id=older.id
          and balance.location_id=source_id and balance.qty_on_hand>0
        where older.item_id=(line->>'item_id')::uuid
          and older.expiry_date >= (occurred_at at time zone 'Asia/Makassar')::date
          and older.expiry_date<chosen_expiry and older.deleted_at is null)
        and nullif(btrim(line->>'fefo_override_reason'),'') is null then
        raise exception using errcode='22023',message='sync_fefo_override_required';
      end if;
    elsif nullif(line->>'batch_id','') is not null then
      raise exception using errcode='22023',message='sync_batch_invalid';
    end if;
  end loop;
  select jsonb_agg(jsonb_build_object('movement_type','distribution',
      'item_id',value->>'item_id','batch_id',nullif(value->>'batch_id',''),
      'from_location_id',source_id::text,
      'to_location_id',(select location.id::text from public.stock_locations location
        where location.type='room' and location.room_id=(value->>'room_id')::uuid
          and location.branch_id=actor.branch_id and location.deleted_at is null),
      'qty',(value->>'qty')::bigint,'note',null)) into expected
    from jsonb_array_elements(payload->'lines');
  perform app_private.assert_exact_movement_plan(expected,payload->'movements','DIST',aggregate_id,actor_id,occurred_at);
  number:=app_private.allocate_document_number('DIST',actor.branch_id,occurred_at);
  insert into public.distributions
    (id,created_at,updated_at,sync_status,doc_number,branch_id,distributed_by,status,posted_at,note)
  values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,'synced',number,
    actor.branch_id,actor_id,'posted',occurred_at,nullif(btrim(payload->>'note'),''));
  for line in select value from jsonb_array_elements(payload->'lines') loop
    insert into public.distribution_lines
      (id,created_at,updated_at,sync_status,distribution_id,room_id,item_id,batch_id,qty,
       fefo_override_reason)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'room_id')::uuid,
      (line->>'item_id')::uuid,nullif(line->>'batch_id','')::uuid,
      (line->>'qty')::bigint,nullif(btrim(line->>'fefo_override_reason'),''));
  end loop;
  movement_ids:=app_private.post_verified_plan(payload->'movements','DIST',aggregate_id,actor_id,occurred_at);
  select server_version,server_updated_at into version,updated from public.distributions where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'final_document_number',number,
    'movement_ids',to_jsonb(movement_ids));
end;
$$;

revoke all on function app_private.sync_post_distribution_complete(uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;

create or replace function app_private.sync_post_disposal_complete(
  aggregate_id uuid, actor_id uuid, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; source public.stock_locations%rowtype;
  current public.disposals%rowtype; number text; line jsonb; expected jsonb;
  movement_ids uuid[]; version bigint; updated timestamptz;
begin
  select * into actor from public.users where id=actor_id for share;
  select * into source from public.stock_locations where id=(payload->>'source_location_id')::uuid
    and deleted_at is null for share;
  if not found or nullif(btrim(payload->>'reason'),'') is null
    or (source.type='warehouse' and actor.role<>'warehouse')
    or (source.type<>'warehouse' and (actor.role<>'kepala_cabang' or actor.branch_id<>source.branch_id)) then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  select * into current from public.disposals where id=aggregate_id for update;
  if found then
    if current.status='posted' and current.posted_by=actor_id then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,
        'movement_ids',(select coalesce(jsonb_agg(value->>'id'),'[]'::jsonb)
          from jsonb_array_elements(payload->'movements')));
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Pemusnahan server sudah final.','base_server_version',0,
      'server_version',current.server_version);
  end if;
  if jsonb_typeof(payload->'lines')<>'array' or jsonb_array_length(payload->'lines')=0
    or (select count(*)<>count(distinct (value->>'item_id')||'|'||(value->>'batch_id'))
      from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  for line in select value from jsonb_array_elements(payload->'lines') loop
    if (line->>'qty')::bigint<=0 or not exists(select 1 from public.item_batches batch
      where batch.id=(line->>'batch_id')::uuid and batch.item_id=(line->>'item_id')::uuid
        and batch.expiry_date<(occurred_at at time zone 'Asia/Makassar')::date) then
      raise exception using errcode='22023',message='sync_batch_invalid';
    end if;
  end loop;
  select jsonb_agg(jsonb_build_object('movement_type','disposal',
      'item_id',value->>'item_id','batch_id',value->>'batch_id',
      'from_location_id',source.id::text,'to_location_id',null,
      'qty',(value->>'qty')::bigint,
      'note',btrim(payload->>'reason')||case
        when nullif(btrim(value->>'note'),'') is null then ''
        else ' · '||btrim(value->>'note') end)) into expected
    from jsonb_array_elements(payload->'lines');
  perform app_private.assert_exact_movement_plan(expected,payload->'movements','DSP',aggregate_id,actor_id,occurred_at);
  number:=app_private.allocate_document_number('DSP',null,occurred_at);
  insert into public.disposals
    (id,created_at,updated_at,sync_status,doc_number,source_location_id,created_by,
     status,reason,posted_at,posted_by)
  values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,'synced',number,
    source.id,actor_id,'posted',btrim(payload->>'reason'),occurred_at,actor_id);
  for line in select value from jsonb_array_elements(payload->'lines') loop
    insert into public.disposal_lines
      (id,created_at,updated_at,sync_status,disposal_id,item_id,batch_id,qty,note)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'item_id')::uuid,
      (line->>'batch_id')::uuid,(line->>'qty')::bigint,nullif(btrim(line->>'note'),''));
  end loop;
  movement_ids:=app_private.post_verified_plan(payload->'movements','DSP',aggregate_id,actor_id,occurred_at);
  select server_version,server_updated_at into version,updated from public.disposals where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'final_document_number',number,
    'movement_ids',to_jsonb(movement_ids));
end;
$$;

create or replace function app_private.sync_post_consumption_complete(
  aggregate_id uuid, actor_id uuid, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.consumptions%rowtype;
  source_id uuid; number text; line jsonb; expected jsonb; movement_ids uuid[];
  version bigint; updated timestamptz; item_has_expiry boolean;
begin
  select * into actor from public.users where id=actor_id for share;
  if actor.role<>'perawat' or actor.branch_id<>(payload->>'branch_id')::uuid
    or (payload->>'created_by')::uuid<>actor_id
    or not exists(select 1 from public.rooms where id=(payload->>'room_id')::uuid
      and branch_id=actor.branch_id and is_active and deleted_at is null) then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  select * into current from public.consumptions where id=aggregate_id for update;
  if found then
    if current.status='posted' and current.posted_by=actor_id then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,
        'movement_ids',(select coalesce(jsonb_agg(value->>'id'),'[]'::jsonb)
          from jsonb_array_elements(payload->'movements')));
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Pemakaian server sudah final.','base_server_version',0,
      'server_version',current.server_version);
  end if;
  select id into source_id from public.stock_locations where type='room'
    and room_id=(payload->>'room_id')::uuid and branch_id=actor.branch_id
    and deleted_at is null;
  if source_id is null then raise exception using errcode='23503',message='sync_dependency_missing'; end if;
  if jsonb_typeof(payload->'lines')<>'array' or jsonb_array_length(payload->'lines')=0
    or (select count(*)<>count(distinct (value->>'item_id')||'|'||coalesce(value->>'batch_id',''))
      from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  for line in select value from jsonb_array_elements(payload->'lines') loop
    select has_expiry into item_has_expiry from public.items where id=(line->>'item_id')::uuid;
    if item_has_expiry is null or (line->>'qty')::bigint<=0
      or (item_has_expiry and not exists(select 1 from public.item_batches
        where id=(line->>'batch_id')::uuid and item_id=(line->>'item_id')::uuid
          and expiry_date >= (occurred_at at time zone 'Asia/Makassar')::date))
      or (not item_has_expiry and nullif(line->>'batch_id','') is not null) then
      raise exception using errcode='22023',message='sync_batch_invalid';
    end if;
  end loop;
  select jsonb_agg(jsonb_build_object('movement_type','consumption',
      'item_id',value->>'item_id','batch_id',nullif(value->>'batch_id',''),
      'from_location_id',source_id::text,'to_location_id',null,
      'qty',(value->>'qty')::bigint,
      'note',case
        when nullif(btrim(payload->>'note'),'') is null then nullif(btrim(value->>'note'),'')
        when nullif(btrim(value->>'note'),'') is null then btrim(payload->>'note')
        else btrim(payload->>'note')||' · '||btrim(value->>'note') end)) into expected
    from jsonb_array_elements(payload->'lines');
  perform app_private.assert_exact_movement_plan(expected,payload->'movements','CONS',aggregate_id,actor_id,occurred_at);
  number:=app_private.allocate_document_number('CNS',actor.branch_id,occurred_at);
  insert into public.consumptions
    (id,created_at,updated_at,sync_status,doc_number,branch_id,room_id,created_by,
     status,note,posted_at,posted_by)
  values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,'synced',number,
    actor.branch_id,(payload->>'room_id')::uuid,actor_id,'posted',
    nullif(btrim(payload->>'note'),''),occurred_at,actor_id);
  for line in select value from jsonb_array_elements(payload->'lines') loop
    insert into public.consumption_lines
      (id,created_at,updated_at,sync_status,consumption_id,item_id,batch_id,qty,note)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'item_id')::uuid,
      nullif(line->>'batch_id','')::uuid,(line->>'qty')::bigint,
      nullif(btrim(line->>'note'),''));
  end loop;
  movement_ids:=app_private.post_verified_plan(payload->'movements','CONS',aggregate_id,actor_id,occurred_at);
  select server_version,server_updated_at into version,updated from public.consumptions where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'final_document_number',number,
    'movement_ids',to_jsonb(movement_ids));
end;
$$;

revoke all on function app_private.sync_post_disposal_complete(uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function app_private.sync_post_consumption_complete(uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;

create or replace function app_private.sync_ship_goods_return_complete(
  aggregate_id uuid, actor_id uuid, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.goods_returns%rowtype;
  receipt public.good_receipts%rowtype; request_branch uuid; number text; line jsonb;
  gr_line public.good_receipt_lines%rowtype; version bigint; updated timestamptz;
begin
  select * into actor from public.users where id=actor_id for share;
  select * into current from public.goods_returns where id=aggregate_id for update;
  if found then
    if current.status in ('shipped','received') and current.shipped_by=actor_id then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,'movement_ids','[]'::jsonb);
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Retur server sudah final.','base_server_version',0,
      'server_version',current.server_version);
  end if;
  select * into receipt from public.good_receipts where id=(payload->>'gr_id')::uuid
    and status='posted' for share;
  if not found then raise exception using errcode='23503',message='sync_dependency_missing'; end if;
  select request.branch_id into request_branch from public.delivery_orders shipment
    join public.purchase_requests request on request.id=shipment.pr_id
    where shipment.id=receipt.do_id;
  if actor.role<>'kepala_cabang' or actor.branch_id<>request_branch
    or (payload->>'branch_id')::uuid<>request_branch
    or (payload->>'created_by')::uuid<>actor_id then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  if jsonb_typeof(payload->'lines')<>'array'
    or jsonb_array_length(payload->'lines')<>(select count(*) from public.good_receipt_lines
      where gr_id=receipt.id and line_status='rejected' and deleted_at is null)
    or (select count(*)<>count(distinct value->>'gr_line_id')
      from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023',message='sync_line_integrity_invalid';
  end if;
  for line in select value from jsonb_array_elements(payload->'lines') loop
    select * into gr_line from public.good_receipt_lines
      where id=(line->>'gr_line_id')::uuid and gr_id=receipt.id
        and line_status='rejected' and deleted_at is null;
    if not found or gr_line.item_id<>(line->>'item_id')::uuid
      or gr_line.batch_id is distinct from nullif(line->>'batch_id','')::uuid
      or (line->>'qty')::bigint<=0 or (line->>'qty')::bigint>gr_line.shipped_qty
      or btrim(line->>'reject_reason_snapshot')<>btrim(gr_line.reject_reason) then
      raise exception using errcode='22023',message='sync_line_integrity_invalid';
    end if;
  end loop;
  if jsonb_array_length(coalesce(payload->'movements','[]'::jsonb))<>0 then
    raise exception using errcode='22023',message='sync_movement_plan_mismatch';
  end if;
  number:=app_private.allocate_document_number('RET',request_branch,occurred_at);
  insert into public.goods_returns
    (id,created_at,updated_at,sync_status,doc_number,gr_id,branch_id,created_by,
     status,note,shipped_at,shipped_by)
  values (aggregate_id,(payload->>'created_at')::timestamptz,occurred_at,'synced',number,
    receipt.id,request_branch,actor_id,'shipped',
    nullif(btrim(payload->>'note'),''),occurred_at,actor_id);
  for line in select value from jsonb_array_elements(payload->'lines') loop
    insert into public.goods_return_lines
      (id,created_at,updated_at,sync_status,goods_return_id,gr_line_id,item_id,batch_id,
       qty,reject_reason_snapshot)
    values ((line->>'id')::uuid,coalesce((line->>'created_at')::timestamptz,occurred_at),
      occurred_at,'synced',aggregate_id,(line->>'gr_line_id')::uuid,
      (line->>'item_id')::uuid,nullif(line->>'batch_id','')::uuid,
      (line->>'qty')::bigint,btrim(line->>'reject_reason_snapshot'));
  end loop;
  select server_version,server_updated_at into version,updated from public.goods_returns where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',version,
    'server_updated_at_utc',updated,'final_document_number',number,
    'movement_ids','[]'::jsonb);
end;
$$;

create or replace function app_private.sync_receive_goods_return_complete(
  aggregate_id uuid, actor_id uuid, base_version bigint,
  occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; current public.goods_returns%rowtype;
  warehouse_id uuid; expected jsonb; movement_ids uuid[];
begin
  select * into actor from public.users where id=actor_id for share;
  if actor.role<>'warehouse' then raise exception using errcode='42501',message='sync_access_denied'; end if;
  select * into current from public.goods_returns where id=aggregate_id for update;
  if not found then raise exception using errcode='23503',message='sync_dependency_missing'; end if;
  if current.status='received' then
    if current.received_by=actor_id then
      return jsonb_build_object('outcome','accepted','server_version',current.server_version,
        'server_updated_at_utc',current.server_updated_at,
        'final_document_number',current.doc_number,
        'movement_ids',(select coalesce(jsonb_agg(value->>'id'),'[]'::jsonb)
          from jsonb_array_elements(payload->'movements')));
    end if;
    return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
      'message','Retur server sudah diterima.','base_server_version',base_version,
      'server_version',current.server_version);
  end if;
  if current.status<>'shipped' or actor_id in (current.created_by,current.shipped_by) then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  if base_version>0 and current.server_version<>base_version then
    return jsonb_build_object('outcome','conflict','code','sync_stale_version',
      'message','Versi server lebih baru.','base_server_version',base_version,
      'server_version',current.server_version);
  end if;
  select id into warehouse_id from public.stock_locations where type='warehouse'
    and deleted_at is null;
  if warehouse_id is null or (select count(*) from public.stock_locations
      where type='warehouse' and deleted_at is null)<>1 then
    raise exception using errcode='23503',message='sync_dependency_missing';
  end if;
  select jsonb_agg(jsonb_build_object('movement_type','return',
      'item_id',line.item_id::text,'batch_id',line.batch_id::text,
      'from_location_id',null,'to_location_id',warehouse_id::text,'qty',line.qty,
      'note',btrim(line.reject_reason_snapshot)||
        case when nullif(btrim(current.note),'') is null then ''
          else ' — Catatan cabang: '||btrim(current.note) end||
        case when nullif(btrim(payload->>'warehouse_note'),'') is null then ''
          else ' — Catatan Warehouse: '||btrim(payload->>'warehouse_note') end))
    into expected from public.goods_return_lines line
    where line.goods_return_id=aggregate_id and line.deleted_at is null;
  perform app_private.assert_exact_movement_plan(expected,payload->'movements','RET',aggregate_id,actor_id,occurred_at);
  movement_ids:=app_private.post_verified_plan(payload->'movements','RET',aggregate_id,actor_id,occurred_at);
  update public.goods_returns set status='received',received_at=occurred_at,
    received_by=actor_id,warehouse_note=nullif(btrim(payload->>'warehouse_note'),''),
    updated_at=occurred_at,sync_status='synced' where id=aggregate_id;
  select * into current from public.goods_returns where id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',current.server_version,
    'server_updated_at_utc',current.server_updated_at,
    'final_document_number',current.doc_number,'movement_ids',to_jsonb(movement_ids));
end;
$$;

revoke all on function app_private.sync_ship_goods_return_complete(uuid,uuid,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function app_private.sync_receive_goods_return_complete(uuid,uuid,bigint,timestamptz,jsonb) from public,anon,authenticated;

alter table public.sync_operations
  add column semantic_hash varchar(64)
  check (semantic_hash is null or semantic_hash ~ '^[0-9a-f]{64}$');
create index idx_sync_operations_terminal_semantic
  on public.sync_operations(operation_type,aggregate_type,aggregate_id,semantic_hash);

create or replace function app_private.sync_apply_typed_operation(
  operation_type text, aggregate_type text, aggregate_id uuid, actor_id uuid,
  base_version bigint, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if operation_type='upsert_master' then
    return app_private.sync_upsert_master_complete(aggregate_type,aggregate_id,
      actor_id,base_version,occurred_at,payload);
  elsif operation_type='submit_opname' and aggregate_type='stock_opname' then
    return app_private.sync_submit_opname_complete(aggregate_id,actor_id,occurred_at,payload);
  elsif operation_type='review_opname' and aggregate_type='stock_opname' then
    return app_private.sync_review_opname_complete(aggregate_id,actor_id,base_version,occurred_at,payload);
  elsif operation_type in ('process_purchase_request','reject_purchase_request','cancel_purchase_request')
    and aggregate_type='purchase_request' then
    return app_private.sync_transition_purchase_request_complete(operation_type,
      aggregate_id,actor_id,base_version,occurred_at,payload);
  elsif operation_type='ship_delivery_order' and aggregate_type='delivery_order' then
    return app_private.sync_ship_delivery_order_complete(aggregate_id,actor_id,occurred_at,payload);
  elsif operation_type='post_good_receipt' and aggregate_type='good_receipt' then
    return app_private.sync_post_good_receipt_complete(aggregate_id,actor_id,occurred_at,payload);
  elsif operation_type='post_distribution' and aggregate_type='distribution' then
    return app_private.sync_post_distribution_complete(aggregate_id,actor_id,occurred_at,payload);
  elsif operation_type='post_disposal' and aggregate_type='disposal' then
    return app_private.sync_post_disposal_complete(aggregate_id,actor_id,occurred_at,payload);
  elsif operation_type='post_consumption' and aggregate_type='consumption' then
    return app_private.sync_post_consumption_complete(aggregate_id,actor_id,occurred_at,payload);
  elsif operation_type='ship_goods_return' and aggregate_type='goods_return' then
    return app_private.sync_ship_goods_return_complete(aggregate_id,actor_id,occurred_at,payload);
  elsif operation_type='receive_goods_return' and aggregate_type='goods_return' then
    return app_private.sync_receive_goods_return_complete(aggregate_id,actor_id,
      base_version,occurred_at,payload);
  elsif operation_type in ('append_import_audit','append_export_audit') then
    return app_private.sync_append_audit_complete(operation_type,aggregate_id,
      actor_id,occurred_at,payload);
  end if;
  raise exception using errcode='22023',message='sync_invalid_payload';
end;
$$;

create or replace function public.push_sync_operation(operation_envelope jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare actor_id uuid; v_request_id uuid; v_device_id uuid; aggregate_id uuid;
  operation_type text; aggregate_type text; payload jsonb; payload_hash text;
  semantic_hash text; base_version bigint; occurred_at timestamptz;
  existing public.sync_operations%rowtype; prior public.sync_operations%rowtype;
  response jsonb; final_operations constant text[]:=array[
    'submit_opname','review_opname','submit_purchase_request','ship_delivery_order',
    'post_good_receipt','post_distribution','post_disposal','post_consumption',
    'ship_goods_return','receive_goods_return'];
begin
  actor_id:=app_private.current_domain_user_id();
  if actor_id is null then raise exception using errcode='42501',message='sync_identity_unlinked'; end if;
  if not app_private.current_user_is_active() then
    raise exception using errcode='42501',message='sync_user_inactive';
  end if;
  if jsonb_typeof(operation_envelope)<>'object' or jsonb_typeof(operation_envelope->'payload')<>'object'
    or coalesce((operation_envelope->>'payload_version')::integer,0)<>1 then
    raise exception using errcode='22023',message='sync_invalid_payload';
  end if;
  v_request_id:=(operation_envelope->>'request_id')::uuid;
  v_device_id:=(operation_envelope->>'device_id')::uuid;
  aggregate_id:=(operation_envelope->>'aggregate_id')::uuid;
  operation_type:=operation_envelope->>'operation';
  aggregate_type:=operation_envelope->>'aggregate_type';
  base_version:=coalesce((operation_envelope->>'base_server_version')::bigint,0);
  occurred_at:=(operation_envelope->>'occurred_at_utc')::timestamptz;
  payload:=operation_envelope->'payload';
  if occurred_at>now()+interval '5 minutes' then
    raise exception using errcode='22023',message='sync_invalid_payload';
  end if;
  if payload ? 'actor_user_id' and (payload->>'actor_user_id')::uuid<>actor_id then
    raise exception using errcode='42501',message='sync_actor_mismatch';
  end if;
  if not exists(select 1 from public.sync_devices where id=v_device_id
    and actor_user_id=actor_id) then
    raise exception using errcode='42501',message='sync_access_denied';
  end if;
  payload_hash:=encode(extensions.digest(
    convert_to(app_private.canonical_jsonb_text(operation_envelope-'payload_hash'),'UTF8'),'sha256'),'hex');
  if operation_envelope->>'payload_hash' is null
    or operation_envelope->>'payload_hash'<>payload_hash then
    raise exception using errcode='22023',message='sync_payload_hash_mismatch';
  end if;
  semantic_hash:=encode(extensions.digest(convert_to(app_private.canonical_jsonb_text(jsonb_build_object(
    'operation',operation_type,'aggregate_type',aggregate_type,
    'aggregate_id',aggregate_id,'payload_version',1,
    'payload',app_private.strip_sync_metadata(payload))),'UTF8'),
    'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended(v_request_id::text,0));
  select * into existing from public.sync_operations where request_id=v_request_id;
  if found then
    if existing.actor_user_id<>actor_id or existing.device_id<>v_device_id then
      raise exception using errcode='42501',message='sync_access_denied';
    end if;
    if existing.payload_hash<>payload_hash then
      raise exception using errcode='23505',message='sync_request_id_reused';
    end if;
    return jsonb_set(existing.response_json,'{outcome}','"replayed"'::jsonb);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    operation_type||'|'||aggregate_type||'|'||aggregate_id::text,0));
  if operation_type=any(final_operations) then
    select * into prior from public.sync_operations candidate
      where candidate.operation_type=operation_type
        and candidate.aggregate_type=aggregate_type and candidate.aggregate_id=aggregate_id
        and candidate.outcome in ('accepted','replayed') order by candidate.completed_at limit 1;
    if found then
      if prior.actor_user_id<>actor_id then
        raise exception using errcode='42501',message='sync_actor_mismatch';
      end if;
      if prior.semantic_hash=semantic_hash then
        response:=jsonb_set(prior.response_json,'{outcome}','"replayed"'::jsonb)
          ||jsonb_build_object('request_id',v_request_id);
      else
        response:=jsonb_build_object('outcome','conflict','request_id',v_request_id,
          'code','sync_final_state_conflict','message','Data final server berbeda.',
          'base_server_version',base_version);
      end if;
    end if;
  end if;
  if response is null then
    if operation_type='submit_purchase_request' and aggregate_type='purchase_request' then
      response:=app_private.sync_submit_purchase_request(aggregate_id,actor_id,
        base_version,occurred_at,payload);
    else
      response:=app_private.sync_apply_typed_operation(operation_type,aggregate_type,
        aggregate_id,actor_id,base_version,occurred_at,payload);
    end if;
    response:=response||jsonb_build_object('request_id',v_request_id);
  end if;
  if response->>'outcome'='conflict' then
    insert into public.sync_conflicts
      (request_id,actor_user_id,aggregate_type,aggregate_id,operation_type,
       conflict_code,base_version,server_version,safe_detail)
    values (v_request_id,actor_id,aggregate_type,aggregate_id,operation_type,
      response->>'code',base_version,nullif(response->>'server_version','')::bigint,
      jsonb_build_object('message',response->>'message'));
  end if;
  insert into public.sync_operations
    (request_id,device_id,operation_type,aggregate_type,aggregate_id,actor_user_id,
     payload_hash,semantic_hash,outcome,response_json)
  values (v_request_id,v_device_id,operation_type,aggregate_type,aggregate_id,actor_id,
    payload_hash,semantic_hash,response->>'outcome',response);
  return response;
exception
  when invalid_text_representation or not_null_violation then
    raise exception using errcode='22023',message='sync_invalid_payload';
end;
$$;

revoke all on function app_private.sync_apply_typed_operation(text,text,uuid,uuid,bigint,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function public.push_sync_operation(jsonb) from public,anon;
grant execute on function public.push_sync_operation(jsonb) to authenticated;
