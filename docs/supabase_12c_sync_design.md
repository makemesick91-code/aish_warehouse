# Milestone 12C — Deterministic Pull, Reconciliation, Tombstone, Recovery

Revisi server `aish-supabase-003`. Dokumen ini adalah sumber desain untuk pull
deterministik; kontrak operasionalnya ada di `supabase_rpc_contracts.md`, aturan
per entity di `supabase_12c_reconciliation.md`, dan langkah lokal di
`supabase_12c_local_e2e.md`.

12B tetap utuh: push, idempotency, canonical hash, outbox dependency, trusted
upload, dan transaksi atomik tidak diubah. 12C hanya menambah jalur baca.

## 1. Klasifikasi entity

| Kelas | Entity | Pull | Tombstone | Rekonsiliasi |
| --- | --- | --- | --- | --- |
| Master | `branch`, `room`, `user`, `category`, `item`, `batch`, `stock_location` | ya | `category`, `batch`, `stock_location` saja | field-level LWW |
| Dokumen non-final | header `submitted`/`processing`/`preparing` | ya | tidak | server-authoritative state, field mergeable terbatas |
| Dokumen final | `reviewed`, `posted`, `received`, `shipped`, `rejected`, `cancelled` | ya | tidak | server menang mutlak |
| Ledger append-only | `stock_movement` | ya | tidak pernah | tidak pernah di-merge |
| Balance/cache | `stock_balance` | ya | tidak | server menang, direkonstruksi dari ledger saat recovery |
| Audit log | `export_audit`, `import_audit` | tidak | tidak pernah | append-only lokal |
| Upload metadata | `remote_file_objects` | tidak | tidak | tetap milik jalur upload 12B |

`users` tidak pernah dihapus (trigger server) dan tidak pernah menerima tombstone:
penonaktifan adalah `is_active = false`, sebuah perubahan field biasa. `branches`,
`rooms`, dan `items` mengikuti G-A4 — master yang sudah dipakai transaksi hanya
dinonaktifkan. `stock_movements` dan `export_logs` sudah append-only di server
(trigger `reject_immutable_mutation`), sehingga secara struktural tidak dapat
menghasilkan tombstone.

## 2. Change feed deterministik

### Yang ditolak

`updated_at > last_sync_time` ditolak sebagai cursor. Dua perubahan pada
`statement_timestamp()` yang sama tidak punya urutan total, sehingga pagination
dapat melewatkan record; dan sebuah row yang diubah dua kali "bergerak" di dalam
urutan, sehingga halaman berikutnya dapat melompatinya.

`(server_updated_at, id)` memperbaiki tie-break tetapi tidak memperbaiki masalah
kedua: row yang berubah lagi setelah cursor melewatinya tidak akan pernah terlihat
lagi pada posisi lamanya, dan `id` bukan urutan kejadian.

### Yang dipakai

`public.sync_change_journal` — change journal terurut, append-only, ditulis oleh
trigger `AFTER INSERT OR UPDATE` pada setiap tabel syncable.

```text
change_seq   bigint  primary key, dari sequence khusus
xact_id      xid8    default pg_current_xact_id()
entity_type  varchar(64)
entity_id    uuid
operation    'upsert' | 'tombstone'
server_version bigint
changed_at   timestamptz
```

Journal memisahkan *urutan perubahan* dari *isi entity*. Sebuah row yang berubah
dua kali menghasilkan dua entry journal, jadi cursor tidak pernah melompatinya:
entry lama sudah diterapkan, entry baru datang di posisi baru. Payload selalu
dibaca dari state entity *sekarang*, sehingga menerapkan ulang halaman lama
bersifat idempoten — hasil akhirnya sama dengan menerapkan entry terbaru saja.

### Horizon commit

`nextval` tidak transaksional: transaksi yang mendapat `change_seq = 10` bisa
commit setelah transaksi yang mendapat `change_seq = 11`. Pembaca naif akan
memajukan cursor melewati 11 dan kehilangan 10 selamanya.

Pull karena itu membatasi batch pada horizon:

```sql
horizon := coalesce(
  (select min(change_seq) - 1 from public.sync_change_journal
     where xact_id >= pg_snapshot_xmin(pg_current_snapshot())),
  (select coalesce(max(change_seq), 0) from public.sync_change_journal));
```

Setiap row yang dikembalikan punya `change_seq <= horizon`, dan menurut definisi
horizon tidak ada row dengan seq lebih kecil yang transaksinya masih berjalan.
Entry yang belum settle selalu punya seq di atas horizon dan diambil pull
berikutnya. Gap permanen akibat transaksi yang rollback tidak masalah: kontrak
hanya menuntut monotonik, bukan kontigu.

Konsekuensi yang diterima: satu transaksi panjang menahan kepala antrean
(head-of-line). Itu dipilih dengan sadar — menahan lebih aman daripada melewatkan.

### Cursor

Cursor adalah satu `bigint` (`change_seq` terakhir yang berhasil diterapkan).
Monotonik, dapat dipaginasi, dan dapat dilanjutkan setelah crash.

Visibilitas bergantung pada role dan branch, sehingga cursor hanya sah untuk satu
scope. Server mengembalikan `scope_fingerprint` — SHA-256 dari
`domain_user_id|role|branch_id`. Klien menyimpan cursor per fingerprint; ketika
fingerprint berubah (ganti akun, promosi role, pindah cabang) cursor untuk scope
baru dimulai dari 0 dan resync penuh berjalan. Tidak ada cache lintas akun.

## 3. Otorisasi pull

`public.pull_sync_changes(cursor, limit, device_id, entity_types)` adalah
`SECURITY DEFINER` dengan `search_path = ''`, `execute` dicabut dari `public` dan
`anon`.

Fungsi memvalidasi, dalam urutan ini: identitas domain aktif, device milik actor,
lalu bentuk argumen. Filter data dilakukan di server melalui
`app_private.pull_entity_visible(entity_type, entity_id)`.

`pull_entity_visible` mengulang predikat SELECT RLS untuk setiap entity type dan
memakai helper yang sama (`is_nurse()`, `can_read_location()`,
`current_user_branch_id()`). Pengulangan itu perlu karena SECURITY DEFINER berjalan
sebagai owner dan melewati RLS; ia juga berisiko menyimpang dari policy. Karena itu
`supabase/tests/database/pull_sync.test.sql` membandingkan, untuk setiap entity
type dan setiap actor fixture, himpunan id yang lolos RLS dengan himpunan id yang
lolos `pull_entity_visible`. Divergensi menggagalkan suite, bukan membocorkan data.

Row journal yang tidak terlihat **dibuang tanpa jejak** — tidak ada tombstone
palsu, tidak ada penanda "ada sesuatu di sini". Actor cabang B tidak dapat
menyimpulkan keberadaan record cabang A dari gap `change_seq`, karena gap juga
dihasilkan rollback dan entity di luar filter.

`limit` dibatasi 1..500 dan default 200. `entity_types` opsional dan hanya
mempersempit.

## 4. Batch dan transaksi lokal

Satu batch pull diterapkan dalam **satu transaksi Drift**. Cursor disimpan dalam
transaksi yang sama. Kegagalan pada perubahan ke-N membatalkan seluruh batch dan
cursor tidak maju, sehingga retry mengulang batch yang sama dan menghasilkan state
akhir yang identik.

Idempotensi per-change dijamin oleh:

- upsert entity memakai primary key yang sama;
- movement di-`INSERT OR IGNORE` berdasarkan UUID — ledger tidak pernah di-update;
- tombstone dicatat di `sync_tombstones` dengan `server_version`, sehingga
  penerapan kedua tidak mengubah apa pun.

## 5. Tombstone

Journal menandai `tombstone` ketika `deleted_at` berpindah dari NULL ke non-NULL.
Penerapan lokal **tidak pernah** `DELETE`: ia menulis `deleted_at`, menyalakan
`sync_status = 'synced'`, dan menyisipkan baris `sync_tombstones`. Data historis,
foreign key, dan audit trail tetap utuh.

`sync_tombstones` menyimpan `entity_type`, `entity_id`, `server_version`,
`tombstoned_at_utc`, dan `applied_at_utc`. Baris itu mencegah tiga hal:

1. **Resurrection.** Upsert dengan `server_version <= server_version` tombstone
   ditolak. Perangkat lama yang online kembali membawa snapshot usang tidak dapat
   menghidupkan record.
2. **Kebingungan "belum pernah punya".** Tombstone untuk entity yang tidak ada
   secara lokal tetap dicatat tanpa membuat row bisnis. Perangkat tahu record itu
   dihapus di server, bukan sekadar belum pernah sampai.
3. **Retry ganda.** Penerapan bersifat idempoten pada `(entity_type, entity_id)`.

Tombstone dengan `server_version` lebih tinggi dari yang tercatat menimpa catatan
lama; entity yang di-restore server (deleted_at kembali NULL) datang sebagai
upsert dengan `server_version` lebih tinggi dan karena itu diterima.

## 6. Rekonsiliasi field-level (G-Y3)

Berlaku hanya untuk entity **non-final yang mutable**, yaitu master data. Dokumen
`submitted` ke atas tidak pernah di-merge per field: G-Y2 membuat server menjadi
sumber kebenaran begitu dokumen meninggalkan draft.

### Klasifikasi kolom

| Kelas | Contoh | Perilaku |
| --- | --- | --- |
| Mergeable mutable | `items.name`, `items.unit`, `items.min_stock_room`, `rooms.name` | 3-way merge |
| Server-controlled | `server_version`, `server_updated_at`, `doc_number`, `sync_status` | selalu dari server |
| Immutable | `id`, `created_at`, `items.sku`, `branches.code`, `item_batches.batch_no` | tidak pernah di-merge; beda nilai = konflik |
| Final-state | `status`, `posted_at`, `reviewed_by` | server menang |
| Ledger/audit | seluruh `stock_movements`, `export_logs` | tidak pernah di-merge |

Allowlist per entity dan per state ada di `EntityReconciler`; tidak ada generic
map merge atas seluruh JSON.

### Algoritma

Server menyimpan `public.sync_entity_field_versions(entity_type, entity_id,
field_name, field_version)`. `field_version` **adalah `server_version` entity saat
field itu terakhir berubah** — bukan penghitung terpisah. Karena `server_version`
sudah monotonik per entity dan ditulis trigger server, ordering field otomatis
deterministik dan tidak dapat dipengaruhi client. Klien tidak pernah mengirim
field version; server menghitungnya dengan membandingkan nilai lama dan baru.

Klien menyimpan baseline server terakhir per entity di `sync_entity_snapshots`.
Merge tiga arah untuk tiap field mergeable:

| Lokal berubah | Server berubah (`field_version > base_server_version`) | Hasil |
| --- | --- | --- |
| tidak | tidak | tetap |
| tidak | ya | ambil server |
| ya | tidak | pertahankan lokal, re-enqueue push |
| ya | ya | **server menang**, catat konflik `local_change_superseded` |

Keputusan memakai versi server, bukan urutan kedatangan jaringan, sehingga hasil
merge dua perangkat identik apa pun urutan paketnya. Server tetap memvalidasi
state machine dan invariant bisnis pada push berikutnya; merge lokal tidak pernah
menjadi otoritas.

Konflik dicatat di `sync_conflict_logs` dengan `safe_detail_json` berisi nama
field dan kode resolusi saja — tanpa nilai sensitif, JWT, SQL, stack trace, atau
path internal.

## 7. Recovery konflik final

`FinalConflictRecoveryService` berjalan ketika pull membawa dokumen final yang
berbeda dari state lokal, atau ketika outbox memegang konflik final.

1. Header dan lines lokal ditimpa snapshot server; nomor dokumen final server
   dipertahankan apa adanya.
2. Movement server yang belum ada lokal disisipkan dengan UUID server. Movement
   yang sudah ada tidak pernah di-update atau dihapus.
3. Movement lokal yang mereferensi dokumen itu tetapi **tidak ada di server** tidak
   dihapus — itu akan melanggar G-A1. Sebagai gantinya dibuat movement balik
   (reversal) yang mereferensi movement asal, persis koreksi yang diresepkan G-A1.
   UUID reversal bersifat deterministik (UUID v5 dari id movement asal), sehingga
   retry tidak pernah membuat transaksi bisnis baru.
4. `stock_balances` untuk posisi terdampak dihitung ulang dari ledger. Jika hasil
   akan negatif, batch dibatalkan dan konflik ditandai `manual_review_required`.
5. Outbox untuk aggregate itu diselesaikan: operasi yang sudah tercermin di server
   dihapus, sisanya menjadi `conflict` dengan resolusi eksplisit dan berhenti
   retry.
6. `sync_conflict_logs` menerima `resolved_at` dan `resolution`.

Kode resolusi: `server_final_applied`, `local_nonfinal_merged`,
`local_change_superseded`, `tombstone_applied`, `manual_review_required`.

Sync Center menampilkan sisa `manual_review_required` sebagai satu-satunya keadaan
yang menuntut orang; semua yang lain punya jalur pemulihan otomatis.

## 8. Realtime sebagai invalidation

Realtime hanya menandai bahwa state remote mungkin berubah.

```text
event → tandai dirty → debounce/coalesce → pull dari cursor terakhir
      → apply transaksional → ulangi selama has_more
```

Subscription mengikuti lifecycle sesi, berhenti saat logout, tidak membawa service
key, dan hanya menerima row journal yang lolos RLS. Payload event **tidak pernah**
dipercaya sebagai event bisnis, tidak pernah menulis ledger, dan tidak pernah
mengganti entity.

Policy SELECT jurnal tidak memanggil `pull_entity_visible`. Ekspresi policy
dievaluasi dengan privilege role pemanggil, sehingga memanggil helper privat di
sana akan memaksa grant EXECUTE ke `authenticated`. Predikatnya karena itu
dinyatakan sebagai probe keberadaan ke tabel entity yang bersangkutan — di bawah
RLS tabel itu, sebagai actor — sehingga jawabannya *adalah* jawaban RLS dan tidak
bisa menyimpang. `pull_sync.test.sql` membuktikan policy itu meloloskan persis
baris jurnal yang diloloskan filter pull untuk setiap actor fixture, dan bahwa
himpunan yang diloloskan tidak kosong.

Sistem tetap benar tanpa Realtime sama sekali. Pull juga dipicu saat login,
reconnect, app resume, dan manual sync. Event yang terlambat, hilang, duplikat,
atau tidak berurutan tidak mengubah hasil, karena hasilnya ditentukan cursor —
bukan event.

Debounce 750 ms mengubah burst menjadi satu pull. Worker bersifat single-flight;
event yang tiba saat pull berjalan menandai dirty sekali lagi dan memicu tepat satu
pull lanjutan, bukan satu pull per event.

## 9. Orkestrasi

```text
sesi valid
→ pulihkan lease kedaluwarsa
→ push operasi eligible
→ pull sampai has_more = false
→ rekonsiliasi
→ push sekali lagi bila rekonsiliasi menghasilkan operasi baru
```

Putaran push tambahan dibatasi satu kali per siklus, sehingga tidak ada loop
push/pull tak berujung. Single-flight, bounded drain, cancellation saat logout,
actor-session matching, dan exponential backoff 12B dipertahankan.

## 10. Trade-off yang diterima

- **Change journal menambah satu insert per mutasi.** Ditukar dengan ordering total
  yang tidak dimiliki timestamp. Retensi dibatasi (§11).
- **Horizon commit menahan kepala antrean.** Ditukar dengan jaminan tidak ada
  record terlewat.
- **`pull_entity_visible` menduplikasi predikat RLS.** Ditukar dengan filter di
  server; drift dijaga test ekuivalensi, bukan disiplin.
- **Reset cursor saat scope berubah.** Ditukar dengan kebenaran: entry lama untuk
  entity yang baru terlihat tidak dapat direkonstruksi dari cursor lama.
- **Reversal alih-alih hapus movement.** Ledger tumbuh; append-only dan audit
  trail terjaga.

## 11. Retensi journal

`sync_change_journal` dipangkas hanya oleh `app_private.prune_sync_change_journal`
dan hanya di bawah `min(last_acked_seq)` seluruh device aktif dikurangi margin.
Fungsi ini privat, tidak dijadwalkan otomatis pada 12C, dan didokumentasikan di
`supabase_12c_remote_handoff.md`. Perangkat yang tertinggal di bawah horizon
pemangkasan menerima `sync_cursor_expired` dan melakukan resync penuh dari 0 —
aman, karena apply bersifat idempoten.

Angka yang membuat sebuah batas aman — cursor terendah di seluruh perangkat
aktif — tersimpan di perangkat, bukan di server, sehingga tidak ada query yang
dapat menghasilkannya. `tool/plan_supabase_12c_journal_retention.ts` melaporkan
batas usulan berdasarkan safety window yang diputuskan produk dan secara
eksplisit melaporkan `current_min_active_cursor` sebagai tidak diketahui, alih-
alih menebaknya. Script itu tidak menghapus dan tidak menjadwalkan apa pun.

## 12. Baseline journal untuk data pra-migrasi

Journal dimulai kosong. Baris yang sudah ada sebelum migrasi 12C tidak punya
entry, sehingga cursor 0 tidak membawanya — instalasi baru akan hidup tanpa
katalog. Baseline karena itu harus ditulis sekali sebelum klien 12C dirilis.

Baseline **bukan** sebuah perubahan bisnis. Ia menyisipkan satu entry `upsert`
(atau `tombstone` bila `deleted_at` sudah terisi) per baris hidup, membawa
`server_version` dan `server_updated_at` baris itu **apa adanya**, ditambah baris
`sync_entity_field_versions` untuk tiap field mergeable dengan `field_version`
sama dengan `server_version` entity. Tidak ada kolom bisnis yang ditulis.

Alternatif yang ditolak — `UPDATE ... SET updated_at = updated_at` agar trigger
menulis jurnalnya sendiri — menaikkan `server_version` setiap baris, yang
menggerakkan seluruh `field_version`, yang membuat server memenangkan setiap
kolom pada merge tiga arah berikutnya (§6). Perangkat dengan edit lokal pending
kehilangan edit itu tanpa jejak. Baseline karena itu ditulis langsung ke journal,
bukan lewat trigger.

Granularitasnya sama dengan feed normal: master dan header dokumen dijurnal per
aggregate (child line ikut lewat parent-nya), sedangkan `stock_movement` dan
`stock_balance` dijurnal per baris.

Idempotensinya struktural. Primary key `(backfill_revision, entity_type,
entity_id)` membuat dua operator yang berjalan bersamaan, atau satu operator yang
menjalankan ulang, tidak mungkin menghasilkan dua baseline untuk satu entity —
insert kedua kalah balapan dan dihitung sebagai skipped. Entity yang sudah punya
entry runtime juga dilewati: feed sudah memuatnya, dan mengirim ulang berarti
mengulang perubahan yang sudah diterapkan perangkat.

Mekanisme, batasan, dan prosedurnya ada di `supabase_12c_staging_rollout.md` §6.
