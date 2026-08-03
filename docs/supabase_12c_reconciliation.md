# Reconciliation dan tombstone per entity — Milestone 12C

Halaman ini adalah aturan operasional. Alasan desainnya ada di
`supabase_12c_sync_design.md`; kontrak transport ada di
`supabase_rpc_contracts.md`.

Sumber tunggal klasifikasi ini adalah `lib/core/sync/sync_entity_policy.dart`
(klien) dan `app_private.pull_mergeable_fields` (server). Keduanya dipin secara
literal oleh `test/sync/sync_entity_policy_test.dart` dan
`supabase/tests/database/pull_sync.test.sql`; mengubah salah satu saja
menggagalkan salah satu suite.

## 1. Kelas entity

| Entity | Kelas | Tombstone | Merge per kolom |
| --- | --- | --- | --- |
| `branch` | master | tidak | ya |
| `room` | master | tidak | ya |
| `user` | master | **tidak pernah** | ya |
| `category` | master | ya | ya |
| `item` | master | tidak | ya |
| `batch` | master | ya | ya |
| `stock_location` | master | ya | ya |
| `stock_balance` | balance/cache | tidak | tidak — server menang |
| `stock_movement` | ledger append-only | **tidak pernah** | tidak pernah |
| `stock_opname` | dokumen | ya | tidak |
| `purchase_request` | dokumen | ya | tidak |
| `delivery_order` | dokumen | ya | tidak |
| `good_receipt` | dokumen | ya | tidak |
| `distribution` | dokumen | ya | tidak |
| `disposal` | dokumen | ya | tidak |
| `consumption` | dokumen | ya | tidak |
| `goods_return` | dokumen | ya | tidak |
| `import_audit`, `export_audit` | audit log | tidak pernah | tidak — tidak di-pull |

`branch`, `room`, `item`, dan `user` tidak menerima tombstone karena G-A4: master
yang sudah dipakai transaksi hanya dinonaktifkan. Penonaktifannya datang sebagai
upsert biasa dengan `is_active = false`. `user` lebih keras lagi — server menolak
DELETE pada tabelnya, dan setiap dokumen historis menyebut actor-nya.

## 2. Klasifikasi kolom

| Kelas | Contoh | Perilaku |
| --- | --- | --- |
| Mergeable mutable | `items.name`, `items.unit`, `rooms.name` | merge tiga arah |
| Server-controlled | `server_version`, `server_updated_at`, `sync_status`, `doc_number` | selalu server |
| Immutable | `id`, `created_at`, `items.sku`, `items.has_expiry`, `branches.code`, `users.email`, `item_batches.batch_no` | tidak pernah di-merge; beda = konflik |
| Final-state | `status`, `posted_at`, `reviewed_by`, seluruh kolom dokumen | server menang (G-Y2) |
| Ledger/audit | seluruh `stock_movements` | tidak pernah di-merge (G-A1, G-Y5) |
| Device bookkeeping | `updated_at`, `deleted_at` | tidak pernah jadi hasil merge |

`updated_at` sengaja tidak dipakai sebagai arbiter meski G-Y3 menyebutnya: itu
jam perangkat. Perannya diambil `field_version` server yang monotonik.

`deleted_at` juga tidak pernah di-merge. Penghapusan berjalan lewat tombstone,
dan pemulihan (server menghidupkan kembali record) menghapus baris tombstone lalu
membersihkan `deleted_at` secara eksplisit.

## 3. Daftar kolom mergeable

```text
branch          name, address, is_active
room            code, name, is_active
user            full_name, role, branch_id, is_active
category        name
item            name, category_id, unit, min_stock_room, min_stock_branch,
                expiry_alert_days, is_active
batch           expiry_date
stock_location  name
```

Entity lain tidak memiliki kolom mergeable sama sekali.

## 4. Matriks keputusan merge

Untuk setiap kolom mergeable, dengan `base` = snapshot server terakhir yang
diterapkan perangkat dan `base_version` = `sync_entity_states.server_version`:

| Lokal berubah dari base | `field_version > base_version` | Hasil | Resolusi |
| --- | --- | --- | --- |
| tidak | tidak | tetap | — |
| tidak | ya | ambil server | — |
| ya | tidak | **pertahankan lokal**, row tetap `pending`, push ulang | `local_nonfinal_merged` |
| ya | ya | **ambil server** | `local_change_superseded` |

Tanpa baseline sama sekali (entity belum pernah direkonsiliasi perangkat ini),
server diambil utuh: perbedaan tidak dapat diatribusikan ke pengguna.

Kolom immutable yang berbeda menghasilkan `manual_review_required` dan nilai
server tetap diterapkan.

### Mengembalikan kolom yang bertahan ke server

Merge yang mempertahankan kolom lokal belum menyelesaikan apa pun sampai kolom
itu sampai ke server. Row ditandai `pending`, dan applier mendaftarkan ulang
aggregate-nya ke outbox dengan `base_server_version` yang sudah di-rebase ke
versi yang baru saja dilaporkan server. Tanpa langkah ini, entry outbox lama
masih membawa payload hash pra-merge dan akan ditolak sebagai
`sync_payload_hash_mismatch`, bukan terkirim.

Actor diambil dari entry outbox yang sudah ada, **bukan** dari sesi yang
menjalankan pull. Perangkat bisa dipakai bersama, dan mengatribusikan edit satu
pengguna ke pengguna lain adalah reassignment yang justru ditolak 12B. Bila tidak
ada entry outbox sama sekali, tidak ada penulis yang dapat dibuktikan: row tetap
`pending` dan menunggu workflow-nya sendiri mendaftarkannya.

## 5. Dokumen

Dokumen tidak pernah di-merge per kolom. Setelah meninggalkan `draft`, server
adalah sumber kebenaran (G-Y2), jadi snapshot server ditulis utuh — header,
lines, dan movements dalam satu transaksi. Baris lines yang tidak lagi ada di
server di-*soft delete*, bukan dihapus.

Status final per dokumen:

```text
stock_opname      reviewed
purchase_request  rejected, cancelled, completed
delivery_order    shipped, received
good_receipt      posted
distribution      posted
disposal          posted
consumption       posted
goods_return      shipped, received
```

Draft lokal yang belum pernah dikirim tidak memiliki padanan di server, sehingga
tidak ada change yang dapat menamainya. Applier hanya menyentuh entity yang
disebut batch.

## 6. Tombstone

Jurnal menandai `tombstone` saat `deleted_at` berpindah dari NULL ke non-NULL.

Penerapan lokal:

1. `UPDATE ... SET deleted_at = ?` pada header dan lines — **tidak pernah**
   `DELETE`. Foreign key tetap resolve dan audit trail utuh (G-A5).
2. Menulis `sync_tombstones(entity_type, entity_id, server_version,
   tombstoned_at_utc, applied_at_utc, had_local_row)`.
3. Menghapus baseline entity itu.
4. Menutup conflict log terbuka dengan `tombstone_applied`.

Baris `sync_tombstones` mencegah:

- **Resurrection** — upsert dengan `server_version <= server_version` tombstone
  ditolak;
- **Kebingungan "belum pernah punya"** — `had_local_row` membedakan penghapusan
  data yang perangkat pernah pegang dari yang tidak pernah sampai;
- **Retry ganda** — idempoten pada `(entity_type, entity_id)`.

Upsert dengan `server_version` lebih tinggi adalah restore server yang sah:
tombstone dihapus dan `deleted_at` lokal dibersihkan.

Entity `tombstonable = false` mengabaikan tombstone sepenuhnya.

## 7. Recovery konflik final

Dijalankan `FinalConflictRecoveryService` setelah applier menulis snapshot
server.

1. Movement server yang belum ada lokal disisipkan dengan UUID server.
2. Movement lokal yang mereferensi dokumen itu tetapi tidak ada di daftar
   movement server **tidak dihapus** — dibuat movement balik yang mereferensi
   movement asal (G-A1). UUID reversal deterministik: UUID v5 dari id movement
   asal, sehingga retry tidak membuat transaksi baru.
3. Balance posisi terdampak dikembalikan. Bila hasilnya akan negatif, seluruh
   recovery dibatalkan dan konflik ditandai `manual_review_required` (G-A2).
4. Outbox untuk aggregate itu dihapus setelah dicatat sebagai conflict log
   dengan resolusi `local_change_superseded`; membiarkannya antre akan mem-post
   ulang dokumen begitu jaringan pulih.
5. Conflict log terbuka ditutup dengan `server_final_applied`.

Daftar movement server disimpan di baseline dengan kunci
`__server_movement_ids` — id saja, bukan baris, agar baseline tetap kecil dan
tidak membawa qty/lokasi yang bisa disalahartikan merge.

## 8. Kode resolusi

```text
server_final_applied      dokumen final server menggantikan state lokal
local_nonfinal_merged     merge per kolom, kedua sisi bertahan
local_change_superseded   edit lokal kalah oleh nilai server yang lebih baru
tombstone_applied         server menghapus entity; lokal ikut soft delete
manual_review_required    pemulihan otomatis akan melanggar invariant
```

Hanya `manual_review_required` yang ditampilkan Sync Center sebagai keadaan yang
menuntut orang. Sisanya sudah selesai.

## 9. Isi conflict log

`safe_detail_json` hanya berisi nama kolom yang terlibat dan kode resolusi.
Tidak ada nilai, pesan server, JWT, SQL, stack trace, atau path internal. Log
yang bisa dibuka pengguna adalah log yang bisa dibaca orang lain di belakangnya.
