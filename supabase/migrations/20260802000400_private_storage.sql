-- Private audit/report buckets. Milestone 12A deliberately opens no client write.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'import-audit',
    'import-audit',
    false,
    20971520,
    array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
  ),
  (
    'report-artifacts',
    'report-artifacts',
    false,
    20971520,
    array[
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ]
  );

create policy import_audit_read_super_admin
on storage.objects for select to authenticated
using (
  bucket_id = 'import-audit'
  and app_private.current_user_is_active()
  and app_private.is_super_admin()
);

create policy report_artifacts_read_owner
on storage.objects for select to authenticated
using (
  bucket_id = 'report-artifacts'
  and app_private.current_user_is_active()
  and (storage.foldername(name))[1] = app_private.current_domain_user_id()::text
);

comment on policy import_audit_read_super_admin on storage.objects is
  'Read-only client access; trusted upload path is deferred to Milestone 12B.';
comment on policy report_artifacts_read_owner on storage.objects is
  'Path: <domain-user-id>/<export-id>/<sanitized-name>; no client writes in 12A.';
