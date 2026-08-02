create or replace function app_private.allocate_document_number(
  requested_type text,
  requested_branch_id uuid,
  occurred_at_utc timestamptz
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  branch_code text;
  v_scope_code text;
  v_operational_date date;
  allocated bigint;
  prefix text;
begin
  if requested_type not in ('SO','PR','DO','GR','DIST','DSP','CNS','RET') then
    raise exception using errcode = '22023', message = 'sync_invalid_payload';
  end if;
  if occurred_at_utc > now() + interval '5 minutes' then
    raise exception using errcode = '22023', message = 'sync_invalid_payload';
  end if;
  v_operational_date := (occurred_at_utc at time zone 'Asia/Makassar')::date;

  if requested_type in ('SO','PR','GR','DIST','CNS','RET') then
    select branch.code into branch_code from public.branches as branch
      where branch.id = requested_branch_id and branch.deleted_at is null;
    if branch_code is null then
      raise exception using errcode = '23503', message = 'sync_dependency_missing';
    end if;
    v_scope_code := branch_code;
  else
    v_scope_code := 'WH';
  end if;
  prefix := case requested_type when 'CNS' then 'CNS' else requested_type end;

  insert into public.document_number_counters as counter
    (document_type, scope_code, operational_date, next_value)
  values (requested_type, v_scope_code, v_operational_date, 2)
  on conflict (document_type, scope_code, operational_date) do update
    set next_value = counter.next_value + 1
  returning next_value - 1 into allocated;

  return prefix || '-' || v_scope_code || '-' || to_char(v_operational_date, 'YYYYMMDD') ||
    '-' || lpad(allocated::text, 4, '0');
end;
$$;

revoke all on function app_private.allocate_document_number(text, uuid, timestamptz)
  from public, anon, authenticated;
