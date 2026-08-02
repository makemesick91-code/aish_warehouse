-- Milestone 12B: authenticated push identity, idempotency and safe conflict audit.

create or replace function app_private.canonical_jsonb_text(value jsonb)
returns text
language plpgsql
stable
strict
set search_path = ''
as $$
declare result text;
begin
  case jsonb_typeof(value)
    when 'object' then
      select '{'||coalesce(string_agg(to_jsonb(entry.key)::text||':'||
        app_private.canonical_jsonb_text(entry.value),',' order by entry.key collate "C"),'')||'}'
        into result from jsonb_each(value) as entry;
      return result;
    when 'array' then
      select '['||coalesce(string_agg(app_private.canonical_jsonb_text(entry.value),','
        order by entry.ordinality),'')||']' into result
        from jsonb_array_elements(value) with ordinality as entry(value,ordinality);
      return result;
    else return value::text;
  end case;
end;
$$;
revoke all on function app_private.canonical_jsonb_text(jsonb) from public,anon,authenticated;

create or replace function app_private.strip_sync_metadata(value jsonb)
returns jsonb
language plpgsql
stable
strict
set search_path = ''
as $$
declare result jsonb;
begin
  case jsonb_typeof(value)
    when 'object' then
      select coalesce(jsonb_object_agg(entry.key,
        app_private.strip_sync_metadata(entry.value)),'{}'::jsonb)
        into result from jsonb_each(value) as entry
        where entry.key not in ('created_at','updated_at','deleted_at','sync_status',
          'server_updated_at','server_received_at','server_version','doc_number');
      return result;
    when 'array' then
      select coalesce(jsonb_agg(app_private.strip_sync_metadata(entry.value)
        order by entry.ordinality),'[]'::jsonb) into result
        from jsonb_array_elements(value) with ordinality as entry(value,ordinality);
      return result;
    else return value;
  end case;
end;
$$;
revoke all on function app_private.strip_sync_metadata(jsonb) from public,anon,authenticated;

create table public.sync_devices (
  id uuid primary key,
  actor_user_id uuid not null references public.users(id),
  app_install_id text not null,
  display_label varchar(128),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (actor_user_id, app_install_id),
  unique (id, actor_user_id)
);

create table public.sync_operations (
  request_id uuid primary key,
  device_id uuid not null references public.sync_devices(id),
  operation_type varchar(64) not null,
  aggregate_type varchar(64) not null,
  aggregate_id uuid not null,
  actor_user_id uuid not null references public.users(id),
  payload_hash varchar(64) not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  outcome text not null check (outcome in ('accepted', 'replayed', 'conflict')),
  response_json jsonb not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz not null default now()
);

create index idx_sync_operations_aggregate
  on public.sync_operations (aggregate_type, aggregate_id, completed_at);
create index idx_sync_operations_actor on public.sync_operations (actor_user_id, completed_at);

create table public.sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  actor_user_id uuid not null references public.users(id),
  aggregate_type varchar(64) not null,
  aggregate_id uuid not null,
  operation_type varchar(64) not null,
  conflict_code varchar(96) not null,
  base_version bigint not null check (base_version >= 0),
  server_version bigint check (server_version is null or server_version >= 0),
  safe_detail jsonb not null default '{}'::jsonb,
  detected_at timestamptz not null default now()
);

create index idx_sync_conflicts_request on public.sync_conflicts (request_id);
create index idx_sync_conflicts_aggregate on public.sync_conflicts (aggregate_type, aggregate_id);

create table public.document_number_counters (
  document_type varchar(16) not null,
  scope_code varchar(32) not null,
  operational_date date not null,
  next_value bigint not null default 1 check (next_value > 0),
  primary key (document_type, scope_code, operational_date)
);

create table public.file_upload_intents (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  actor_user_id uuid not null references public.users(id),
  bucket_id text not null check (bucket_id in ('import-audit', 'report-artifacts')),
  object_key text not null unique,
  entity_type varchar(64) not null,
  entity_id uuid not null,
  expected_sha256 varchar(64) not null check (expected_sha256 ~ '^[0-9a-f]{64}$'),
  expected_size_bytes bigint not null check (expected_size_bytes between 1 and 52428800),
  mime_type varchar(128) not null,
  status text not null default 'issued'
    check (status in ('issued', 'uploaded', 'finalized', 'expired', 'rejected')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  finalized_at timestamptz,
  check (expires_at <= created_at + interval '5 minutes 30 seconds'),
  check ((status = 'finalized' and finalized_at is not null) or status <> 'finalized')
);

create table public.remote_file_objects (
  id uuid primary key default gen_random_uuid(),
  intent_id uuid not null unique references public.file_upload_intents(id),
  actor_user_id uuid not null references public.users(id),
  bucket_id text not null,
  object_key text not null unique,
  entity_type varchar(64) not null,
  entity_id uuid not null,
  sha256 varchar(64) not null,
  size_bytes bigint not null check (size_bytes > 0),
  mime_type varchar(128) not null,
  created_at timestamptz not null default now()
);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'sync_devices', 'sync_operations', 'sync_conflicts',
    'document_number_counters', 'file_upload_intents', 'remote_file_objects'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
  end loop;
end;
$$;

grant select on public.sync_devices, public.sync_operations, public.sync_conflicts,
  public.file_upload_intents, public.remote_file_objects to authenticated;
revoke all on public.document_number_counters from public, anon, authenticated;

create policy sync_devices_read_own on public.sync_devices for select to authenticated
  using (actor_user_id = app_private.current_domain_user_id());
create policy sync_operations_read_own on public.sync_operations for select to authenticated
  using (actor_user_id = app_private.current_domain_user_id());
create policy sync_conflicts_read_own on public.sync_conflicts for select to authenticated
  using (actor_user_id = app_private.current_domain_user_id());
create policy upload_intents_read_own on public.file_upload_intents for select to authenticated
  using (actor_user_id = app_private.current_domain_user_id());
create policy remote_files_read_own on public.remote_file_objects for select to authenticated
  using (actor_user_id = app_private.current_domain_user_id());

create or replace function public.register_sync_device(
  device_id uuid,
  requested_app_install_id text,
  requested_display_label text default null
)
returns table (id uuid, last_seen_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare actor_id uuid;
begin
  actor_id := app_private.current_domain_user_id();
  if actor_id is null then
    raise exception using errcode = '42501', message = 'sync_identity_unlinked';
  end if;
  if not app_private.current_user_is_active() then
    raise exception using errcode = '42501', message = 'sync_user_inactive';
  end if;
  if device_id is null or nullif(btrim(requested_app_install_id), '') is null then
    raise exception using errcode = '22023', message = 'sync_invalid_payload';
  end if;

  insert into public.sync_devices as device
    (id, actor_user_id, app_install_id, display_label)
  values (device_id, actor_id, requested_app_install_id, nullif(btrim(requested_display_label), ''))
  on conflict (actor_user_id, app_install_id) do update
    set last_seen_at = now(), display_label = excluded.display_label
  where device.actor_user_id = actor_id;

  return query
    select device.id, device.last_seen_at
    from public.sync_devices as device
    where device.actor_user_id = actor_id and device.app_install_id = requested_app_install_id;
end;
$$;

revoke all on function public.register_sync_device(uuid, text, text) from public, anon;
grant execute on function public.register_sync_device(uuid, text, text) to authenticated;
