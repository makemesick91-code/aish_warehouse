# Supabase Security Model — Milestone 12B

## Trust boundaries

- Flutter memakai Project URL dan publishable key saja.
- Supabase Auth membuktikan identity; `auth.uid()` tidak langsung menjadi domain
  actor.
- `public.user_auth_links` memetakan Auth user satu-ke-satu ke `public.users`.
- Role, branch, dan active status selalu dibaca dari `public.users`, bukan JWT
  metadata atau local preferences.
- `app_private` helper memakai `SECURITY DEFINER`, schema qualification, fixed
  empty `search_path`, zero actor parameter, dan grant minimum.
- UI/route guard adalah fail-fast; PostgreSQL RLS adalah enforcement server.

Referensi resmi: [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[Auth user data](https://supabase.com/docs/guides/auth/managing-user-data), dan
[Storage access control](https://supabase.com/docs/guides/storage/security/access-control).

## Schema inventory

Migration mirror mencakup seluruh 28 tabel Drift v13:

```text
branches rooms users item_categories items item_batches stock_locations
stock_balances stock_movements stock_opnames stock_opname_lines
purchase_requests purchase_request_opnames purchase_request_lines
delivery_orders delivery_order_lines good_receipts good_receipt_lines
distributions distribution_lines disposals disposal_lines consumptions
consumption_lines goods_returns goods_return_lines export_logs import_logs
```

Tambahan server: `user_auth_links`, `app_meta.schema_revisions`, dan kolom
`server_updated_at` + `server_version` di 28 tabel syncable. UUID, UTC
`timestamptz`, civil `date`, bigint milli-unit, generated opname difference,
foreign key, partial unique index, workflow CHECK, serta historical soft delete
dipertahankan secara semantik. Drift v14 menambah enam tabel sync lokal tanpa mengubah
business schema v13.

## Read matrix ringkas

| Data | Perawat | Kepala Cabang | Warehouse | Super Admin |
|---|---|---|---|---|
| Profil user | sendiri | sendiri | sendiri | semua domain user |
| Branch/room | branch sendiri | branch sendiri | daftar branch, tanpa room | semua |
| Master barang | read | read | read | read/admin via trusted path nanti |
| Stock | room branch sendiri | store + room branch sendiri | Warehouse Pusat | semua |
| Opname | dokumen sendiri | branch sendiri | finalized recap | finalized recap/global |
| PR/DO/GR | tidak | branch sendiri | cross-branch workflow | report/read global |
| Distribusi | tidak | branch sendiri | posted recap | posted recap/global |
| Disposal | tidak | lokasi branch sendiri | Warehouse Pusat | global report |
| Consumption | dokumen sendiri | posted branch sendiri | posted recap | posted global |
| Goods Return | tidak | branch sendiri | shipped/received queue | global report |
| Import audit | tidak | tidak | tidak | read |

Master historical rows tetap dapat dibaca bila diperlukan dokumen. `users` lebih
ketat karena memuat email; actor detail lintas user tidak dibuka sebagai daftar.

## Write model 12B

Authenticated hanya mendapat table `SELECT`. Tidak ada policy business
INSERT/UPDATE/DELETE, DELETE policy, atau direct document finalization. Write memakai
`register_sync_device`, typed `push_sync_operation`, serta intent/finalize upload yang
sempit. RPC membaca actor/role/branch aktif dari Auth mapping pada setiap request.

`stock_movements`:

- direct client INSERT/UPDATE/DELETE tidak memiliki privilege/policy;
- trigger menolak UPDATE/DELETE bahkan dari jalur privileged;
- koreksi kelak tetap movement reversal baru.

`stock_balances` tidak source of truth dan tidak dapat dimutasi client. Semua
quantity server memakai bigint milli-unit, tidak ada floating point.

## Storage

- `import-audit`: private; hanya active Super Admin membaca. Path
  `import-audit/<import-id>/<sanitized-name>`.
- `report-artifacts`: private; owner path membaca. Path
  `report-artifacts/<domain-user-id>/<export-id>/<sanitized-name>`.
- Tidak ada generic client upload/update/delete/overwrite. Upload hanya memakai signed
  token satu-object dari Edge Function.
- Metadata database tetap authority untuk hash, size, actor, scope, dan status.
- Filename bukan identity dan object key internal tidak ditampilkan UI.

## Revocation and stale sessions

Setiap policy/helper membaca mapping/domain row pada request saat itu. Perubahan
role/branch, penghapusan link, atau `is_active=false` berlaku tanpa menunggu JWT
baru. Flutter juga mengambil profile ulang saat startup/login. Identity yang
unlinked/inactive dikeluarkan dan route terlindungi tidak dibuka.

## Residual risks / scope sengaja ditunda

- General pull, tombstone, dan LWW per kolom belum ada; 12B hanya mendeteksi dan mencatat
  conflict.
- Existing workflow use case masih memvalidasi actor terhadap row `users` di
  Drift. Sampai initial pull 12B tersedia, instalasi production harus
  mem-bootstrap data lokal dari dataset domain yang sama agar UUID user server
  dan Drift identik; profil Auth tidak boleh dibuat sebagai UUID domain baru.
- File report remote bersifat opsional; orphan cleanup tetap operasi administrator.
- Belum ada Realtime, MFA, atau reset password production.
- Local stack bukan bukti remote Dashboard/Auth config; remote verification wajib.
# Revision 002 write boundary

Authenticated client writes hanya melalui RPC eksplisit dan signed upload intent.
`sync_operations`, counter, balance, movement, dan storage control-plane tidak memiliki
generic authenticated write policy. Semua definer function memakai empty search path dan
fully-qualified names; actor selalu berasal dari Auth mapping.

# Revision 003 read boundary

Jalur baca terotorisasi ditambahkan tanpa membuka satu pun tabel bisnis untuk
generic read lintas scope.

- `public.pull_sync_changes` adalah satu-satunya cara klien membaca change feed,
  dan satu-satunya fungsi revisi 003 yang di-grant ke `authenticated`. Seluruh
  helper `app_private` revisi 003 — `pull_entity_visible`,
  `pull_entity_payload`, `pull_commit_horizon`, `pull_scope_fingerprint`,
  `pull_mergeable_fields`, registry entity type, ketiga trigger function, dan
  `prune_sync_change_journal` — dicabut dari `public`, `anon`, dan
  `authenticated`. RPC publiknya SECURITY DEFINER sehingga menjangkau helper
  sebagai owner; klien tidak perlu dan tidak mendapat privilege langsung.
  `pull_sync.test.sql` menguji daftar itu sebagai satu himpunan agar helper baru
  tidak lolos dengan EXECUTE default milik PUBLIC.
- `app_private.pull_entity_visible` mengulang predikat SELECT RLS karena
  SECURITY DEFINER melewati RLS. Pengulangan itu berisiko menyimpang, sehingga
  `pull_sync.test.sql` membandingkan himpunan id RLS dengan himpunan id yang
  diloloskan fungsi ini untuk setiap entity type dan setiap actor fixture.
  Fungsi ini tidak dipanggil dari policy mana pun: ekspresi policy dievaluasi
  dengan privilege role pemanggil, sehingga memanggilnya di sana akan memaksa
  grant EXECUTE ke `authenticated` dan menyerahkan oracle keberadaan entity ke
  koneksi langsung.
- `sync_change_journal` memaksa RLS, hanya punya policy SELECT, dan tidak
  memiliki grant INSERT/UPDATE/DELETE untuk role klien mana pun. Trigger
  tambahan menolak UPDATE. Kanal Realtime karena itu hanya membawa bookkeeping
  baris yang memang boleh dibaca actor.
- Policy SELECT jurnal menyatakan predikatnya sebagai probe keberadaan ke tabel
  entity itu sendiri, bukan pemanggilan helper privat. Policy dievaluasi sebagai
  actor dengan RLS aktif pada setiap tabel yang disentuhnya, sehingga probe itu
  *adalah* jawaban RLS dan tidak bisa menyimpang darinya. `pull_sync.test.sql`
  membuktikan policy tersebut meloloskan persis baris jurnal yang diloloskan
  filter pull, untuk setiap actor fixture.
- `sync_entity_field_versions` tidak dapat dibaca klien sama sekali; nilainya
  hanya keluar melalui response pull. Klien tidak pernah mengirim field version,
  sehingga ordering merge tidak dapat dipengaruhi payload.
- Trigger jurnal dan field version berjalan `SECURITY DEFINER` agar feed mencatat
  setiap penulis, termasuk `service_role` yang tidak diberi usage pada
  `app_private`. Ketiganya tidak dapat dipanggil langsung.
- Realtime tidak pernah menjadi sumber kebenaran: payload event tidak dibaca,
  tidak menulis ledger, dan tidak mengganti entity. Ia hanya menjadwalkan pull.

## Residual risks revisi 003

- Backfill jurnal belum dijalankan; data pra-migrasi tidak muncul di feed sampai
  barisnya tersentuh. Strategi ada di `supabase_12c_remote_handoff.md`.
- Retensi jurnal tersedia tetapi tidak dijadwalkan; jurnal tumbuh monoton.
- Policy RLS jurnal melakukan satu probe keberadaan per baris — benar, tetapi
  biayanya belum diukur pada volume produksi.
- `grant usage on schema app_private to authenticated` masih berlaku dari
  revisi 001. Helper revisi 003 sudah dicabut satu per satu, tetapi helper
  identitas revisi 001 masih memakai EXECUTE default milik PUBLIC. Mencabut
  usage schema itu adalah hardening satu baris yang menutup seluruh sisa
  permukaan sekaligus; belum dilakukan karena berada di luar scope revisi 003
  dan menyentuh migrasi yang sudah ter-deploy.
