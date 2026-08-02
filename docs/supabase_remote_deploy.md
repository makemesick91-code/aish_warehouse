# Supabase Remote Deployment Handoff

Milestone 12A tidak melakukan remote write. Langkah berikut dijalankan manual
setelah project dibuat dan izin deployment diberikan.

## 1. Buat project

1. Buat project Supabase dan pilih region yang memenuhi kebutuhan operasi/data.
2. Catat Project Ref dan Project URL dari Dashboard.
3. Di Settings > API Keys, buat/ambil **publishable key** (`sb_publishable_...`).
4. Jangan memakai secret key atau legacy service-role key di Flutter.

Referensi resmi: [API keys](https://supabase.com/docs/guides/getting-started/api-keys)
dan [local-to-remote workflow](https://supabase.com/docs/guides/local-development/cli-workflows).

## 2. Guard sebelum remote write

Deployment hanya boleh dilanjutkan bila semua tersedia:

```text
SUPABASE_ACCESS_TOKEN
SUPABASE_PROJECT_REF
ALLOW_REMOTE_SUPABASE_WRITE=true
izin eksplisit pemilik project
```

Perintah handoff yang **belum dijalankan**:

```bash
npx supabase login
npx supabase link --project-ref <PROJECT_REF>
npx supabase db push --dry-run
npx supabase db push
```

Jangan memakai `--include-seed` pada production. `supabase/seed.sql` berisi fixture
lokal, bukan data production.

## 3. Auth Dashboard

1. Authentication > Providers: aktifkan email/password.
2. Matikan public signup/allow new users.
3. Jangan aktifkan anonymous, magic link, social login, atau public registration.
4. Buat user melalui Dashboard/trusted admin operation saja.
5. Konfigurasikan Site URL/redirect allow-list sebelum membuka reset password.
6. Reset password production tetap ditunda sampai SMTP dan redirect teruji.

`db push` tidak menggantikan pemeriksaan Auth Dashboard ini.

## 4. Bootstrap domain admin

Ikuti `docs/supabase_bootstrap_admin.md`. Auth user dan `public.users` adalah dua
identity berbeda yang wajib ditautkan lewat `public.user_auth_links`.

## 5. Flutter environment

Gunakan secret manager CI/CD untuk memasok define berikut:

```bash
flutter build apk \
  --dart-define=APP_ENV=production \
  --dart-define=SUPABASE_ENABLED=true \
  --dart-define=SUPABASE_URL=<PROJECT_URL> \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<PUBLISHABLE_KEY>
```

Tidak ada database password, access token, secret key, atau refresh token di
perintah Flutter.

## 6. Verification checklist

- Email/password login berhasil; public signup ditolak.
- `get_my_domain_profile()` hanya mengembalikan profil tertaut sendiri.
- Missing link dan inactive domain user ditolak aplikasi dan RLS.
- `get_server_health()` mengembalikan `aish-supabase-001`.
- Anonymous tidak membaca business table/RPC.
- Uji silang nurse/head/warehouse/admin dan dua branch.
- Direct INSERT/UPDATE/DELETE ledger serta balance ditolak.
- Seluruh business table forced RLS dan tidak ada blanket policy.
- Bucket `import-audit` serta `report-artifacts` tetap private.
- Client upload masih ditolak pada 12A.

## 7. Secrets dan Edge Functions

12A tidak membuat Edge Function dan tidak membutuhkan function secret. Bila 12B
menambahnya, gunakan Dashboard secret manager atau file env yang di-ignore:

```bash
npx supabase secrets set --env-file <IGNORED_ENV_FILE> \
  --project-ref <PROJECT_REF>
npx supabase functions deploy <FUNCTION_NAME> \
  --project-ref <PROJECT_REF>
```

Jangan menaruh value secret langsung di command history. Referensi resmi:
[Edge Function secrets](https://supabase.com/docs/guides/functions/secrets).

## 8. Backup, rollback, dan recovery

- Ambil backup logical/Platform backup sebelum migration production.
- Jalankan dry-run dan staging verification lebih dulu.
- Migration production bersifat forward-only; perbaikan dilakukan dengan
  migration baru yang ditinjau, bukan mengedit history yang sudah applied.
- Jangan menjalankan `supabase db reset --linked` pada production.
- Untuk insiden akses, cabut key terdampak, nonaktifkan user, dan audit policies
  sebelum memulihkan traffic.
