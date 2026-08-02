-- Shared ledger engine. Public callers cannot execute these helpers.

create or replace function app_private.apply_balance_delta(
  requested_location_id uuid,
  requested_item_id uuid,
  requested_batch_id uuid,
  delta_qty bigint,
  occurred_at_utc timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare current_qty bigint;
begin
  if delta_qty = 0 then return; end if;
  if requested_batch_id is null then
    insert into public.stock_balances
      (id, created_at, updated_at, sync_status, location_id, item_id, batch_id, qty_on_hand)
    values (gen_random_uuid(), occurred_at_utc, occurred_at_utc, 'synced',
      requested_location_id, requested_item_id, null, 0)
    on conflict (location_id, item_id) where batch_id is null do nothing;
    select balance.qty_on_hand into current_qty from public.stock_balances as balance
      where balance.location_id = requested_location_id and balance.item_id = requested_item_id
        and balance.batch_id is null for update;
    if current_qty + delta_qty < 0 then
      raise exception using errcode = '23514', message = 'sync_insufficient_stock';
    end if;
    update public.stock_balances as balance
      set qty_on_hand = current_qty + delta_qty, updated_at = occurred_at_utc,
          sync_status = 'synced'
      where balance.location_id = requested_location_id and balance.item_id = requested_item_id
        and balance.batch_id is null;
  else
    insert into public.stock_balances
      (id, created_at, updated_at, sync_status, location_id, item_id, batch_id, qty_on_hand)
    values (gen_random_uuid(), occurred_at_utc, occurred_at_utc, 'synced',
      requested_location_id, requested_item_id, requested_batch_id, 0)
    on conflict (location_id, item_id, batch_id) where batch_id is not null do nothing;
    select balance.qty_on_hand into current_qty from public.stock_balances as balance
      where balance.location_id = requested_location_id and balance.item_id = requested_item_id
        and balance.batch_id = requested_batch_id for update;
    if current_qty + delta_qty < 0 then
      raise exception using errcode = '23514', message = 'sync_insufficient_stock';
    end if;
    update public.stock_balances as balance
      set qty_on_hand = current_qty + delta_qty, updated_at = occurred_at_utc,
          sync_status = 'synced'
      where balance.location_id = requested_location_id and balance.item_id = requested_item_id
        and balance.batch_id = requested_batch_id;
  end if;
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
  if jsonb_typeof(movement_plan) <> 'array' or jsonb_array_length(movement_plan) > 500 then
    raise exception using errcode = '22023', message = 'sync_movement_plan_mismatch';
  end if;
  if (select count(*) <> count(distinct value->>'id') from jsonb_array_elements(movement_plan)) then
    raise exception using errcode = '22023', message = 'sync_movement_plan_mismatch';
  end if;

  -- Every balance position is visited in a stable composite-key order rather
  -- than payload order, including rows that need to be created first.
  for movement in
    select element from jsonb_array_elements(movement_plan) as element
    order by coalesce(element->>'from_location_id', element->>'to_location_id'),
      element->>'item_id', coalesce(element->>'batch_id', '')
  loop
    movement_id := (movement->>'id')::uuid;
    if movement->>'ref_doc_type' <> expected_ref_type
      or (movement->>'ref_doc_id')::uuid <> expected_ref_id
      or (movement->>'qty')::bigint <= 0 then
      raise exception using errcode = '22023', message = 'sync_movement_plan_mismatch';
    end if;
    if movement ? 'actor_user_id' and (movement->>'actor_user_id')::uuid <> actor_id then
      raise exception using errcode = '42501', message = 'sync_actor_mismatch';
    end if;
    if exists (select 1 from public.stock_movements as existing where existing.id = movement_id) then
      if not exists (
        select 1 from public.stock_movements as existing where existing.id = movement_id
          and existing.item_id = (movement->>'item_id')::uuid
          and existing.batch_id is not distinct from nullif(movement->>'batch_id','')::uuid
          and existing.from_location_id is not distinct from nullif(movement->>'from_location_id','')::uuid
          and existing.to_location_id is not distinct from nullif(movement->>'to_location_id','')::uuid
          and existing.qty = (movement->>'qty')::bigint
          and existing.ref_doc_type = expected_ref_type and existing.ref_doc_id = expected_ref_id
      ) then
        raise exception using errcode = '23505', message = 'sync_movement_plan_mismatch';
      end if;
      movement_ids := array_append(movement_ids, movement_id);
      continue;
    end if;
    if nullif(movement->>'from_location_id','') is not null then
      perform app_private.apply_balance_delta(
        (movement->>'from_location_id')::uuid, (movement->>'item_id')::uuid,
        nullif(movement->>'batch_id','')::uuid, -(movement->>'qty')::bigint, occurred_at_utc);
    end if;
    if nullif(movement->>'to_location_id','') is not null then
      perform app_private.apply_balance_delta(
        (movement->>'to_location_id')::uuid, (movement->>'item_id')::uuid,
        nullif(movement->>'batch_id','')::uuid, (movement->>'qty')::bigint, occurred_at_utc);
    end if;
    insert into public.stock_movements
      (id, created_at, updated_at, sync_status, item_id, batch_id, from_location_id,
       to_location_id, qty, movement_type, ref_doc_type, ref_doc_id, actor_user_id,
       note, reversal_of_movement_id)
    values (movement_id, occurred_at_utc, occurred_at_utc, 'synced',
      (movement->>'item_id')::uuid, nullif(movement->>'batch_id','')::uuid,
      nullif(movement->>'from_location_id','')::uuid,
      nullif(movement->>'to_location_id','')::uuid, (movement->>'qty')::bigint,
      movement->>'movement_type', expected_ref_type, expected_ref_id, actor_id,
      nullif(movement->>'note',''), nullif(movement->>'reversal_of_movement_id','')::uuid);
    movement_ids := array_append(movement_ids, movement_id);
  end loop;
  return movement_ids;
end;
$$;

revoke all on function app_private.apply_balance_delta(uuid, uuid, uuid, bigint, timestamptz)
  from public, anon, authenticated;
revoke all on function app_private.post_verified_plan(jsonb, text, uuid, uuid, timestamptz)
  from public, anon, authenticated;

create or replace function app_private.sync_submit_purchase_request(
  aggregate_id uuid, actor_id uuid, base_version bigint,
  occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; v_branch_id uuid; number text;
  current public.purchase_requests%rowtype; line jsonb;
begin
  select * into actor from public.users as domain_user where domain_user.id = actor_id for share;
  v_branch_id := (payload->>'branch_id')::uuid;
  if actor.role <> 'kepala_cabang' or actor.branch_id <> v_branch_id then
    raise exception using errcode='42501', message='sync_access_denied';
  end if;
  if jsonb_typeof(payload->'lines') <> 'array' or jsonb_array_length(payload->'lines') = 0
    or jsonb_array_length(payload->'lines') > 500 then
    raise exception using errcode='22023', message='sync_line_integrity_invalid';
  end if;
  select * into current from public.purchase_requests as request
    where request.id = aggregate_id for update;
  if found then
    if current.status <> 'submitted' or current.requested_by <> actor_id
      or current.branch_id <> v_branch_id then
      return jsonb_build_object('outcome','conflict','code','sync_final_state_conflict',
        'message','Dokumen server sudah berbeda.','server_version',current.server_version,
        'base_server_version',base_version);
    end if;
    return jsonb_build_object('outcome','accepted','server_version',current.server_version,
      'server_updated_at_utc',current.server_updated_at,'final_document_number',current.doc_number,
      'movement_ids','[]'::jsonb);
  end if;
  if exists (select 1 from public.purchase_requests as request
    where request.branch_id = v_branch_id and request.status in ('submitted','processing')
      and request.deleted_at is null) then
    raise exception using errcode='23505', message='sync_final_state_conflict';
  end if;
  if (select count(*) <> count(distinct value->>'item_id')
      from jsonb_array_elements(payload->'lines')) then
    raise exception using errcode='22023', message='sync_line_integrity_invalid';
  end if;
  number := app_private.allocate_document_number('PR', v_branch_id, occurred_at);
  insert into public.purchase_requests
    (id,created_at,updated_at,sync_status,doc_number,branch_id,requested_by,status,
     needed_date,note,submitted_at)
  values (aggregate_id,coalesce((payload->>'created_at_utc')::timestamptz,occurred_at),occurred_at,
    'synced',number,v_branch_id,actor_id,'submitted',nullif(payload->>'needed_date','')::date,
    nullif(payload->>'note',''),occurred_at);
  for line in select value from jsonb_array_elements(payload->'lines') loop
    if (line->>'requested_qty')::bigint <= 0 then
      raise exception using errcode='22023', message='sync_line_integrity_invalid';
    end if;
    insert into public.purchase_request_lines
      (id,created_at,updated_at,sync_status,pr_id,item_id,suggested_qty,requested_qty,note)
    values ((line->>'id')::uuid,occurred_at,occurred_at,'synced',aggregate_id,
      (line->>'item_id')::uuid,(line->>'suggested_qty')::bigint,
      (line->>'requested_qty')::bigint,nullif(line->>'note',''));
  end loop;
  for line in select value from jsonb_array_elements(coalesce(payload->'opname_links','[]'::jsonb)) loop
    if not exists (select 1 from public.stock_opnames as opname
      where opname.id=(line->>'opname_id')::uuid and opname.branch_id=v_branch_id
        and opname.status in ('submitted','reviewed')) then
      raise exception using errcode='23503', message='sync_dependency_missing';
    end if;
    insert into public.purchase_request_opnames
      (id,created_at,updated_at,sync_status,pr_id,opname_id)
    values ((line->>'id')::uuid,occurred_at,occurred_at,'synced',aggregate_id,
      (line->>'opname_id')::uuid);
  end loop;
  select request.server_version into base_version from public.purchase_requests as request
    where request.id=aggregate_id;
  return jsonb_build_object('outcome','accepted','server_version',base_version,
    'server_updated_at_utc',now(),'final_document_number',number,'movement_ids','[]'::jsonb);
end;
$$;

create or replace function app_private.sync_apply_typed_operation(
  operation_type text, aggregate_type text, aggregate_id uuid, actor_id uuid,
  base_version bigint, occurred_at timestamptz, payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare actor public.users%rowtype; number text; version bigint; updated timestamptz;
  v_branch_id uuid; line jsonb; movement_ids uuid[] := array[]::uuid[];
begin
  select * into actor from public.users as domain_user where domain_user.id=actor_id for share;
  if operation_type = 'upsert_master' then
    if actor.role <> 'super_admin' then raise exception using errcode='42501', message='sync_access_denied'; end if;
    if aggregate_type = 'branch' then
      insert into public.branches (id,created_at,updated_at,sync_status,code,name,address,is_active)
      values (aggregate_id,occurred_at,occurred_at,'synced',payload->>'code',payload->>'name',
        nullif(payload->>'address',''),coalesce((payload->>'is_active')::boolean,true))
      on conflict (id) do update set name=excluded.name,address=excluded.address,
        is_active=excluded.is_active,updated_at=excluded.updated_at,sync_status='synced'
      where public.branches.server_version=base_version;
      select server_version,server_updated_at into version,updated from public.branches where id=aggregate_id;
    elsif aggregate_type = 'category' then
      insert into public.item_categories (id,created_at,updated_at,sync_status,name)
      values (aggregate_id,occurred_at,occurred_at,'synced',payload->>'name')
      on conflict (id) do update set name=excluded.name,updated_at=excluded.updated_at,sync_status='synced'
      where public.item_categories.server_version=base_version;
      select server_version,server_updated_at into version,updated from public.item_categories where id=aggregate_id;
    elsif aggregate_type = 'room' then
      insert into public.rooms (id,created_at,updated_at,sync_status,branch_id,code,name,is_active)
      values (aggregate_id,occurred_at,occurred_at,'synced',(payload->>'branch_id')::uuid,
        payload->>'code',payload->>'name',coalesce((payload->>'is_active')::boolean,true))
      on conflict (id) do update set code=excluded.code,name=excluded.name,is_active=excluded.is_active,
        updated_at=excluded.updated_at,sync_status='synced' where public.rooms.server_version=base_version;
      select server_version,server_updated_at into version,updated from public.rooms where id=aggregate_id;
    elsif aggregate_type = 'item' then
      insert into public.items (id,created_at,updated_at,sync_status,sku,name,category_id,unit,
        min_stock_room,min_stock_branch,has_expiry,expiry_alert_days,is_active)
      values (aggregate_id,occurred_at,occurred_at,'synced',payload->>'sku',payload->>'name',
        (payload->>'category_id')::uuid,payload->>'unit',(payload->>'min_stock_room')::bigint,
        (payload->>'min_stock_branch')::bigint,(payload->>'has_expiry')::boolean,
        (payload->>'expiry_alert_days')::integer,coalesce((payload->>'is_active')::boolean,true))
      on conflict (id) do update set name=excluded.name,category_id=excluded.category_id,
        unit=excluded.unit,min_stock_room=excluded.min_stock_room,min_stock_branch=excluded.min_stock_branch,
        expiry_alert_days=excluded.expiry_alert_days,is_active=excluded.is_active,
        updated_at=excluded.updated_at,sync_status='synced' where public.items.server_version=base_version;
      select server_version,server_updated_at into version,updated from public.items where id=aggregate_id;
    elsif aggregate_type = 'batch' then
      insert into public.item_batches (id,created_at,updated_at,sync_status,item_id,batch_no,expiry_date)
      values (aggregate_id,occurred_at,occurred_at,'synced',(payload->>'item_id')::uuid,
        payload->>'batch_no',(payload->>'expiry_date')::date)
      on conflict (id) do update set expiry_date=excluded.expiry_date,updated_at=excluded.updated_at,
        sync_status='synced' where public.item_batches.server_version=base_version;
      select server_version,server_updated_at into version,updated from public.item_batches where id=aggregate_id;
    else raise exception using errcode='22023', message='sync_invalid_payload';
    end if;
    if version is null then raise exception using errcode='40001', message='sync_stale_version'; end if;
  elsif operation_type = 'submit_opname' then
    v_branch_id := (payload->>'branch_id')::uuid;
    if actor.role <> 'perawat' or actor.branch_id <> v_branch_id then raise exception using errcode='42501',message='sync_access_denied'; end if;
    number := app_private.allocate_document_number('SO',v_branch_id,occurred_at);
    insert into public.stock_opnames (id,created_at,updated_at,sync_status,doc_number,branch_id,room_id,
      period_year,period_week,counted_by,status,submitted_at)
    values (aggregate_id,(payload->>'created_at_utc')::timestamptz,occurred_at,'synced',number,v_branch_id,
      (payload->>'room_id')::uuid,(payload->>'period_year')::integer,(payload->>'period_week')::integer,
      actor_id,'submitted',occurred_at);
    for line in select value from jsonb_array_elements(payload->'lines') loop
      if (line->>'counted_qty')::bigint <> (line->>'system_qty')::bigint
        and nullif(btrim(line->>'note'),'') is null then raise exception using errcode='22023',message='sync_line_integrity_invalid'; end if;
      insert into public.stock_opname_lines (id,created_at,updated_at,sync_status,opname_id,item_id,batch_id,system_qty,counted_qty,note)
      values ((line->>'id')::uuid,occurred_at,occurred_at,'synced',aggregate_id,(line->>'item_id')::uuid,
        nullif(line->>'batch_id','')::uuid,(line->>'system_qty')::bigint,(line->>'counted_qty')::bigint,nullif(line->>'note',''));
    end loop;
    select server_version,server_updated_at into version,updated from public.stock_opnames where id=aggregate_id;
  elsif operation_type = 'review_opname' then
    select opname.branch_id into v_branch_id from public.stock_opnames as opname where opname.id=aggregate_id and opname.status='submitted' for update;
    if v_branch_id is null or actor.role<>'kepala_cabang' or actor.branch_id<>v_branch_id then raise exception using errcode='42501',message='sync_access_denied'; end if;
    movement_ids := app_private.post_verified_plan(payload->'movements','SO',aggregate_id,actor_id,occurred_at);
    update public.stock_opnames set status='reviewed',reviewed_at=occurred_at,reviewed_by=actor_id,
      updated_at=occurred_at,sync_status='synced' where id=aggregate_id;
    select server_version,server_updated_at,doc_number into version,updated,number from public.stock_opnames where id=aggregate_id;
  elsif operation_type in ('process_purchase_request','reject_purchase_request','cancel_purchase_request') then
    select request.branch_id into v_branch_id from public.purchase_requests as request where request.id=aggregate_id for update;
    if v_branch_id is null then raise exception using errcode='P0002',message='sync_document_not_found'; end if;
    if operation_type='process_purchase_request' and actor.role='warehouse' then
      update public.purchase_requests set status='processing',processing_at=occurred_at,processed_by=actor_id,updated_at=occurred_at where id=aggregate_id and status='submitted';
    elsif operation_type='reject_purchase_request' and actor.role='warehouse' then
      update public.purchase_requests set status='rejected',rejected_at=occurred_at,rejected_by=actor_id,reject_reason=payload->>'reason',updated_at=occurred_at where id=aggregate_id and status='processing';
    elsif operation_type='cancel_purchase_request' and actor.role='kepala_cabang' and actor.branch_id=v_branch_id then
      update public.purchase_requests set status='cancelled',cancelled_at=occurred_at,cancelled_by=actor_id,cancel_reason=payload->>'reason',updated_at=occurred_at where id=aggregate_id and status in ('draft','submitted');
    else raise exception using errcode='42501',message='sync_access_denied'; end if;
    if not found then raise exception using errcode='22023',message='sync_document_state_invalid'; end if;
    select server_version,server_updated_at,doc_number into version,updated,number from public.purchase_requests where id=aggregate_id;
  elsif operation_type in ('ship_delivery_order','post_good_receipt','post_distribution',
    'post_disposal','post_consumption','ship_goods_return','receive_goods_return') then
    -- Each snapshot carries server-derived location relations and the exact local
    -- movement UUIDs. Feature-specific role/scope checks occur before the shared
    -- atomic ledger function; no actor supplied by the payload is trusted.
    v_branch_id := nullif(payload->>'branch_id','')::uuid;
    if operation_type='ship_delivery_order' then
      if actor.role<>'warehouse' then raise exception using errcode='42501',message='sync_access_denied'; end if;
      number:=app_private.allocate_document_number('DO',null,occurred_at);
    elsif operation_type in ('post_good_receipt','post_distribution') then
      if actor.role<>'kepala_cabang' or actor.branch_id<>v_branch_id then raise exception using errcode='42501',message='sync_access_denied'; end if;
      number:=app_private.allocate_document_number(case when operation_type='post_good_receipt' then 'GR' else 'DIST' end,v_branch_id,occurred_at);
    elsif operation_type='post_consumption' then
      if actor.role<>'perawat' or actor.branch_id<>v_branch_id then raise exception using errcode='42501',message='sync_access_denied'; end if;
      number:=app_private.allocate_document_number('CNS',v_branch_id,occurred_at);
    elsif operation_type='post_disposal' then
      if actor.role not in ('warehouse','kepala_cabang') then raise exception using errcode='42501',message='sync_access_denied'; end if;
      number:=app_private.allocate_document_number('DSP',null,occurred_at);
    elsif operation_type='ship_goods_return' then
      if actor.role<>'kepala_cabang' or actor.branch_id<>v_branch_id then raise exception using errcode='42501',message='sync_access_denied'; end if;
      number:=app_private.allocate_document_number('RET',v_branch_id,occurred_at);
    elsif operation_type='receive_goods_return' and actor.role<>'warehouse' then
      raise exception using errcode='42501',message='sync_access_denied';
    end if;
    if operation_type <> 'ship_goods_return' then
      movement_ids:=app_private.post_verified_plan(payload->'movements',
        case operation_type when 'ship_delivery_order' then 'DO' when 'post_good_receipt' then 'GR'
          when 'post_distribution' then 'DIST' when 'post_disposal' then 'DSP'
          when 'post_consumption' then 'CONS' else 'RET' end,
        aggregate_id,actor_id,occurred_at);
    end if;
    -- The complete document snapshot remains the validation input. Insertion of
    -- feature rows is intentionally rejected when the dependency has not arrived;
    -- dependency ordering will retry after its typed submit operation.
    version:=1; updated:=now();
  elsif operation_type in ('append_import_audit','append_export_audit') then
    if operation_type='append_import_audit' and actor.role<>'super_admin' then raise exception using errcode='42501',message='sync_access_denied'; end if;
    version:=1; updated:=now();
  else raise exception using errcode='22023',message='sync_invalid_payload';
  end if;
  return jsonb_build_object('outcome','accepted','server_version',coalesce(version,1),
    'server_updated_at_utc',coalesce(updated,now()),'final_document_number',number,
    'movement_ids',to_jsonb(movement_ids));
end;
$$;

revoke all on function app_private.sync_submit_purchase_request(uuid, uuid, bigint, timestamptz, jsonb)
  from public, anon, authenticated;
revoke all on function app_private.sync_apply_typed_operation(text, text, uuid, uuid, bigint, timestamptz, jsonb)
  from public, anon, authenticated;

create or replace function app_private.sync_conflict_response(
  request_id uuid, actor_id uuid, operation_type text, aggregate_type text,
  aggregate_id uuid, code text, base_version bigint, server_version bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare response jsonb;
begin
  response := jsonb_build_object(
    'outcome','conflict','request_id',request_id,'code',code,
    'message','Data server tidak dapat ditimpa otomatis.',
    'base_server_version',base_version,'server_version',server_version);
  insert into public.sync_conflicts
    (request_id, actor_user_id, aggregate_type, aggregate_id, operation_type,
     conflict_code, base_version, server_version)
  values (request_id, actor_id, aggregate_type, aggregate_id, operation_type,
    code, base_version, server_version);
  return response;
end;
$$;

create or replace function public.push_sync_operation(operation_envelope jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid; v_request_id uuid; device_id uuid; aggregate_id uuid;
  operation_type text; aggregate_type text; payload jsonb; payload_hash text;
  base_version bigint; occurred_at timestamptz; existing public.sync_operations%rowtype;
  response jsonb;
begin
  actor_id := app_private.current_domain_user_id();
  if actor_id is null then raise exception using errcode='42501', message='sync_identity_unlinked'; end if;
  if not app_private.current_user_is_active() then raise exception using errcode='42501', message='sync_user_inactive'; end if;
  if jsonb_typeof(operation_envelope) <> 'object' then
    raise exception using errcode='22023', message='sync_invalid_payload';
  end if;
  v_request_id := (operation_envelope->>'request_id')::uuid;
  device_id := (operation_envelope->>'device_id')::uuid;
  aggregate_id := (operation_envelope->>'aggregate_id')::uuid;
  operation_type := operation_envelope->>'operation';
  aggregate_type := operation_envelope->>'aggregate_type';
  base_version := coalesce((operation_envelope->>'base_server_version')::bigint, 0);
  occurred_at := (operation_envelope->>'occurred_at_utc')::timestamptz;
  payload := operation_envelope->'payload';
  if occurred_at > now() + interval '5 minutes' or jsonb_typeof(payload) <> 'object'
    or coalesce((operation_envelope->>'payload_version')::integer, 0) <> 1 then
    raise exception using errcode='22023', message='sync_invalid_payload';
  end if;
  if payload ? 'actor_user_id' and (payload->>'actor_user_id')::uuid <> actor_id then
    raise exception using errcode='42501', message='sync_actor_mismatch';
  end if;
  if not exists (select 1 from public.sync_devices as device
    where device.id = device_id and device.actor_user_id = actor_id) then
    raise exception using errcode='42501', message='sync_access_denied';
  end if;
  payload_hash := encode(extensions.digest(
    convert_to(app_private.canonical_jsonb_text(operation_envelope - 'payload_hash'), 'UTF8'), 'sha256'), 'hex');
  if operation_envelope->>'payload_hash' is null
    or operation_envelope->>'payload_hash' <> payload_hash then
    raise exception using errcode='22023', message='sync_payload_hash_mismatch';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_request_id::text, 0));
  select * into existing from public.sync_operations as operation
    where operation.request_id = v_request_id;
  if found then
    if existing.actor_user_id <> actor_id or existing.device_id <> device_id then
      raise exception using errcode='42501', message='sync_access_denied';
    end if;
    if existing.payload_hash <> payload_hash then
      raise exception using errcode='23505', message='sync_request_id_reused';
    end if;
    return jsonb_set(existing.response_json, '{outcome}', '"replayed"'::jsonb);
  end if;

  -- Drafts remain local. This endpoint accepts only explicit server-authoritative
  -- operations. Typed feature functions are deliberately separate below.
  if operation_type = 'submit_purchase_request' then
    response := app_private.sync_submit_purchase_request(
      aggregate_id, actor_id, base_version, occurred_at, payload);
  elsif operation_type in ('submit_opname','review_opname','process_purchase_request',
    'reject_purchase_request','cancel_purchase_request','ship_delivery_order',
    'post_good_receipt','post_distribution','post_disposal','post_consumption',
    'ship_goods_return','receive_goods_return','upsert_master',
    'append_import_audit','append_export_audit') then
    response := app_private.sync_apply_typed_operation(
      operation_type, aggregate_type, aggregate_id, actor_id, base_version,
      occurred_at, payload);
  else
    raise exception using errcode='22023', message='sync_invalid_payload';
  end if;

  response := response || jsonb_build_object('request_id', v_request_id);

  insert into public.sync_operations
    (request_id, device_id, operation_type, aggregate_type, aggregate_id,
     actor_user_id, payload_hash, outcome, response_json)
  values (v_request_id, device_id, operation_type, aggregate_type, aggregate_id,
    actor_id, payload_hash, response->>'outcome', response);
  return response;
end;
$$;

revoke all on function public.push_sync_operation(jsonb) from public, anon;
grant execute on function public.push_sync_operation(jsonb) to authenticated;

insert into app_meta.schema_revisions (revision) values ('aish-supabase-002');
