# Supabase Local Setup

Milestone 12A memakai Supabase CLI project-scoped (`npm`), PostgreSQL migrations,
Auth email/password, RLS, dan Storage privat. Stack lokal hanya untuk development:
tidak memiliki TLS/rate limiting production dan tidak boleh diekspos ke jaringan
publik.

## Prasyarat

- Node.js dan npm.
- Docker-compatible runtime aktif dengan ruang disk/RAM yang memadai.
- Flutter/Dart sesuai `pubspec.yaml`.
- `psql` opsional untuk inspeksi manual.

Referensi resmi: [local development](https://supabase.com/docs/guides/local-development/overview),
[CLI workflow](https://supabase.com/docs/guides/local-development/cli-workflows), dan
[Flutter initialization](https://supabase.com/docs/reference/dart/initializing).

## Menjalankan stack

```bash
npm install
npm run supabase:start
npm run supabase:status
npm run supabase:reset
npm run supabase:test
```

`supabase db reset` hanya menarget database lokal secara default. Perintah ini
menghapus database lokal, menerapkan seluruh file di `supabase/migrations/`, lalu
menjalankan `supabase/seed.sql`.

Service lokal default:

- API: `http://127.0.0.1:54321`
- PostgreSQL: `127.0.0.1:54322`
- Studio: `http://127.0.0.1:54323`
- Mailpit: `http://127.0.0.1:54324`

Ambil publishable key lokal dengan `npx supabase status`. Jangan menyalin secret
key, database URL, access token, atau refresh token ke source, screenshot, log,
atau file konfigurasi Flutter.

## Menjalankan Flutter

Mode offline-development eksplisit (debug acting-user tetap tersedia):

```bash
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=SUPABASE_ENABLED=false
```

Mode Supabase lokal:

```bash
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=SUPABASE_ENABLED=true \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<LOCAL_PUBLISHABLE_KEY>
```

Untuk Android emulator, loopback host biasanya perlu diganti dengan alamat host
yang dapat dicapai emulator. Jangan membuka port stack ke jaringan publik.

Fixture login lokal memakai data sintetis dan password development yang tercantum
di `supabase/seed.sql`. Credential tersebut bukan credential production.

## Environment contract

Variabel client hanya:

- `APP_ENV`: `development`, `staging`, `production`, atau `test`.
- `SUPABASE_ENABLED`: boolean eksplisit.
- `SUPABASE_URL`: Project URL, bukan database URL.
- `SUPABASE_PUBLISHABLE_KEY`: key berawalan `sb_publishable_`.

`.env.example` dan `config/supabase.example.json` hanya contract. `.env`, config
per-environment, local CLI state, serta function secrets di-ignore. Production
fail closed bila Auth dimatikan atau config tidak valid.

## Perilaku startup offline

12A memilih kebijakan konservatif:

- Belum pernah login: offline tidak dapat masuk.
- Session SDK ada: aplikasi tetap harus mengambil domain profile dan health dari
  server sebelum route terlindungi dibuka.
- Network gagal: tidak ada fallback ke user Drift, debug user, role lama, atau
  Super Admin.
- Offline read-only production dengan cached signed profile belum dibuka; desain
  cache terverifikasi menjadi bagian 12B/12C.

Drift tetap schema v13 dan workflow offline tidak diubah. Mode offline-development
hanya tersedia saat debug dan `SUPABASE_ENABLED=false`.

Workflow existing masih revalidasi actor pada `users` Drift. Karena initial
master/profile pull baru masuk 12B, pengujian production 12A harus memakai local
dataset yang berasal dari domain dataset yang sama dan mempertahankan UUID user.
Jangan membuat identity domain baru hanya untuk menyesuaikan Auth user.

## Berhenti dan troubleshooting

```bash
npm run supabase:stop
```

- Migration/seed gagal: baca error, perbaiki file, lalu `npm run supabase:reset`.
- Docker health check gagal: pastikan daemon aktif dan port 54320–54324 kosong.
- Login berkata provider disabled: `[auth.email]` harus aktif, sedangkan public
  signup tetap ditutup oleh `[auth].enable_signup = false`.
- Jangan memakai `supabase stop --no-backup` kecuali memang hendak membuang data
  lokal dan sudah memahami dampaknya.
