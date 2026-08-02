# Bootstrap Initial Super Admin

Tidak ada akun, UUID, atau password production yang di-hard-code. Jalankan hanya
dalam trusted SQL/admin context setelah migration remote berhasil.

## Alur

1. Pastikan satu domain user existing di `public.users` memiliki role
   `super_admin`, `branch_id is null`, `is_active=true`, dan `deleted_at is null`.
2. Buat Auth user email/password melalui Supabase Dashboard/trusted admin API.
3. Salin UUID Auth dan UUID domain user secara terpisah.
4. Ganti placeholder lalu jalankan template berikut dalam satu transaksi.

```sql
begin;

do $$
declare
  selected_auth_user_id uuid := '<AUTH_USER_UUID>'::uuid;
  selected_domain_user_id uuid := '<DOMAIN_USER_UUID>'::uuid;
begin
  if not exists (
    select 1 from auth.users where id = selected_auth_user_id
  ) then
    raise exception 'Auth user tidak ditemukan';
  end if;

  if not exists (
    select 1
    from public.users
    where id = selected_domain_user_id
      and role = 'super_admin'
      and branch_id is null
      and is_active
      and deleted_at is null
  ) then
    raise exception 'Domain Super Admin aktif tidak ditemukan';
  end if;

  if exists (
    select 1 from public.user_auth_links
    where auth_user_id = selected_auth_user_id
       or user_id = selected_domain_user_id
  ) then
    raise exception 'Auth user atau domain user sudah tertaut';
  end if;

  insert into public.user_auth_links (auth_user_id, user_id)
  values (selected_auth_user_id, selected_domain_user_id);
end;
$$;

commit;
```

## Verifikasi

1. Login dari Flutter memakai Project URL + publishable key.
2. Panggil `get_my_domain_profile()` sebagai user tersebut.
3. Pastikan hanya field berikut tampil: `id`, `full_name`, `email`, `role`,
   `branch_id`, `is_active`.
4. Pastikan role `super_admin`, branch null, active true.
5. Panggil `get_server_health()` dan verifikasi revision
   `aish-supabase-002`.

Menghapus Auth user hanya menghapus `user_auth_links`; domain user historical
tidak ikut terhapus. Nonaktifkan akses dengan `public.users.is_active=false` dan
verifikasi RLS menolak session yang masih memiliki JWT.
