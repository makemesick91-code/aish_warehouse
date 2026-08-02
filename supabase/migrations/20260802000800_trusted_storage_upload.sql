create or replace function public.create_file_upload_intent(
  request_id uuid,
  entity_type text,
  entity_id uuid,
  original_file_name text,
  expected_sha256 text,
  expected_size_bytes bigint,
  mime_type text
)
returns table (intent_id uuid, bucket_id text, object_key text, expires_at timestamptz,
  intent_status text, remote_object_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare actor_id uuid; actor_role text; safe_name text; chosen_bucket text;
  new_id uuid; existing public.file_upload_intents%rowtype;
begin
  actor_id:=app_private.current_domain_user_id(); actor_role:=app_private.current_user_role();
  if actor_id is null then raise exception using errcode='42501',message='sync_identity_unlinked'; end if;
  if not app_private.current_user_is_active() then raise exception using errcode='42501',message='sync_user_inactive'; end if;
  if expected_sha256 !~ '^[0-9a-f]{64}$' or expected_size_bytes not between 1 and 20971520 then
    raise exception using errcode='22023',message='sync_invalid_payload';
  end if;
  safe_name:=regexp_replace(regexp_replace(original_file_name,'[^A-Za-z0-9._-]+','_','g'),'^[.]+','','g');
  if safe_name='' or length(safe_name)>180 then raise exception using errcode='22023',message='sync_invalid_payload'; end if;
  if entity_type='import_audit' then
    if expected_size_bytes > 10485760 then
      raise exception using errcode='22023',message='sync_upload_too_large';
    end if;
    if actor_role<>'super_admin' or lower(safe_name) not like '%.xlsx'
      or mime_type<>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then
      raise exception using errcode='42501',message='sync_upload_not_authorized';
    end if;
    chosen_bucket:='import-audit';
  elsif entity_type='report_artifact' then
    if expected_size_bytes > 20971520 then
      raise exception using errcode='22023',message='sync_upload_too_large';
    end if;
    if lower(safe_name) not like '%.pdf' and lower(safe_name) not like '%.xlsx' then
      raise exception using errcode='22023',message='sync_invalid_payload';
    end if;
    chosen_bucket:='report-artifacts';
  else raise exception using errcode='42501',message='sync_upload_not_authorized';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(request_id::text,0));
  select * into existing from public.file_upload_intents as intent
    where intent.request_id=create_file_upload_intent.request_id;
  if found then
    if existing.actor_user_id<>actor_id or existing.entity_type<>entity_type
      or existing.entity_id<>entity_id or existing.expected_sha256<>expected_sha256
      or existing.expected_size_bytes<>expected_size_bytes or existing.mime_type<>mime_type
      or existing.bucket_id<>chosen_bucket then
      raise exception using errcode='23505',message='sync_request_id_reused';
    end if;
    if existing.status in ('issued','expired') then
      update public.file_upload_intents set status='issued',expires_at=now()+interval '5 minutes'
        where id=existing.id returning * into existing;
    end if;
    return query select existing.id,existing.bucket_id,existing.object_key,
      existing.expires_at,existing.status,
      (select object.id from public.remote_file_objects as object
        where object.intent_id=existing.id);
    return;
  end if;

  new_id:=gen_random_uuid();
  insert into public.file_upload_intents
    (id,request_id,actor_user_id,bucket_id,object_key,entity_type,entity_id,expected_sha256,
     expected_size_bytes,mime_type,expires_at)
  values (new_id,request_id,actor_id,chosen_bucket,
    case when chosen_bucket='import-audit' then entity_id::text||'/'||safe_name
      else actor_id::text||'/'||entity_id::text||'/'||safe_name end,
    entity_type,entity_id,expected_sha256,expected_size_bytes,mime_type,now()+interval '5 minutes');
  return query select intent.id,intent.bucket_id,intent.object_key,intent.expires_at,
    intent.status,null::uuid
    from public.file_upload_intents as intent where intent.id=new_id;
end;
$$;

create or replace function public.finalize_file_upload(
  intent_id uuid, actual_sha256 text, actual_size_bytes bigint, actual_mime_type text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare actor_id uuid; intent public.file_upload_intents%rowtype; object_id uuid;
begin
  actor_id:=app_private.current_domain_user_id();
  select * into intent from public.file_upload_intents as upload
    where upload.id=intent_id and upload.actor_user_id=actor_id for update;
  if not found then raise exception using errcode='42501',message='sync_upload_not_authorized'; end if;
  if intent.status<>'issued' or intent.expires_at<=now() then
    update public.file_upload_intents set status='expired' where id=intent_id and status='issued';
    raise exception using errcode='22023',message='sync_upload_expired';
  end if;
  if actual_size_bytes<>intent.expected_size_bytes then raise exception using errcode='22023',message='sync_upload_size_mismatch'; end if;
  if actual_sha256<>intent.expected_sha256 then raise exception using errcode='22023',message='sync_upload_hash_mismatch'; end if;
  if actual_mime_type<>intent.mime_type then raise exception using errcode='22023',message='sync_invalid_payload'; end if;
  if not exists(select 1 from storage.objects as object where object.bucket_id=intent.bucket_id and object.name=intent.object_key) then
    raise exception using errcode='P0002',message='sync_upload_object_missing';
  end if;
  insert into public.remote_file_objects
    (intent_id,actor_user_id,bucket_id,object_key,entity_type,entity_id,sha256,size_bytes,mime_type)
  values (intent.id,actor_id,intent.bucket_id,intent.object_key,intent.entity_type,intent.entity_id,
    actual_sha256,actual_size_bytes,actual_mime_type) returning id into object_id;
  update public.file_upload_intents set status='finalized',finalized_at=now() where id=intent.id;
  return object_id;
end;
$$;

revoke all on function public.create_file_upload_intent(uuid,text,uuid,text,text,bigint,text) from public,anon;
grant execute on function public.create_file_upload_intent(uuid,text,uuid,text,text,bigint,text) to authenticated;
revoke all on function public.finalize_file_upload(uuid,text,bigint,text) from public,anon;
grant execute on function public.finalize_file_upload(uuid,text,bigint,text) to authenticated;
