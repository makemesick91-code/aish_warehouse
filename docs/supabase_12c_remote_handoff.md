# Remote deployment handoff — Milestone 12C

Revisi server `aish-supabase-003`. Belum pernah dijalankan di project remote.
Seluruh verifikasi pada `supabase_12c_local_e2e.md` berjalan di stack lokal.

## 1. Yang ditambahkan revisi 003

Satu migrasi additive, `20260803000100_deterministic_pull_change_feed.sql`:

```text
sequence  public.sync_change_seq
table     public.sync_change_journal
table     public.sync_entity_field_versions
function  public.pull_sync_changes(bigint, integer, uuid, text[])
function  app_private.pull_entity_visible(text, uuid)
function  app_private.pull_entity_payload(text, uuid)
function  app_private.pull_entity_type_for_table(text)
function  app_private.pull_table_for_entity_type(text)
function  app_private.pull_mergeable_fields(text)
function  app_private.pull_scope_fingerprint()
function  app_private.pull_commit_horizon()
function  app_private.prune_sync_change_journal(bigint)
function  app_private.record_sync_change()
function  app_private.record_sync_change_for_parent()
function  app_private.record_field_versions()
function  app_private.reject_journal_update()
policy    sync_change_journal_read_scope
trigger   26 journal triggers + 7 field-version triggers + 1 immutability guard
```

Tidak ada objek migrasi 001–009 yang di-drop, dan tidak ada signature RPC publik
yang berubah. `push_sync_operation` tetap apa adanya.

## 2. Urutan deploy

1. Backup penuh dan verifikasi restore-nya.
2. Terapkan migrasi ke staging lebih dulu, bukan produksi.
3. Jalankan `supabase test db` di staging.
4. Naikkan `SupabaseConfig.expectedSchemaRevision` bersama rilis klien — klien
   revisi 002 akan menolak server 003 lewat health check, dan itu memang
   perilaku yang diinginkan (fail closed).
5. Rilis klien setelah server, bukan sebelumnya.

## 3. Biaya dan dampak yang harus diperhitungkan

**Satu INSERT jurnal per mutasi baris.** Setiap tabel syncable memperoleh trigger
AFTER. Beban tulis naik dan tabel jurnal tumbuh monoton. Ukur di staging dengan
volume produksi sebelum melanjutkan.

**Backfill tidak dilakukan.** Jurnal dimulai kosong, jadi data yang sudah ada
sebelum migrasi tidak muncul di feed sampai baris itu tersentuh. Konsekuensinya
perangkat baru tidak menerima master data lama lewat pull.

Ini keputusan yang harus diambil sadar sebelum rollout. Dua opsi:

- **Backfill sekali jalan** — insert satu baris jurnal `upsert` per baris hidup
  di setiap tabel syncable, dengan `server_version` baris itu. Aman karena apply
  bersifat idempoten, tetapi menghasilkan feed awal sebesar seluruh dataset.
- **Sentuh ulang** — `UPDATE ... SET updated_at = updated_at` per tabel, yang
  membiarkan trigger menulis jurnalnya sendiri. Lebih sederhana tetapi menaikkan
  `server_version` setiap baris dan karena itu menggerakkan seluruh
  `field_version`, sehingga merge berikutnya akan memenangkan server pada setiap
  kolom. **Jangan pakai opsi ini bila ada perangkat dengan edit lokal pending.**

Rekomendasi: backfill eksplisit, dijalankan pada jendela maintenance, sebelum
klien 12C dirilis.

**Realtime publication.** Migrasi menambahkan `sync_change_journal` ke publikasi
`supabase_realtime` bila ada. Policy RLS-nya melakukan satu probe keberadaan
per baris ke tabel entity yang bersangkutan, di bawah RLS tabel itu sendiri;
ini benar tetapi tidak gratis. Pantau beban Realtime, dan matikan publikasi bila
perlu — sistem tetap benar tanpanya, hanya lebih lambat.

## 4. Retensi

`app_private.prune_sync_change_journal(keep_through)` privat dan **tidak
dijadwalkan**. Fungsi ini menolak memangkas di atas commit horizon.

Sebelum menjadwalkannya, tentukan `keep_through` di bawah cursor terendah semua
device aktif dikurangi margin. Perangkat yang tertinggal di bawah horizon
pemangkasan akan menerima `sync_cursor_invalid`, mereset cursor, dan resync penuh
dari 0 — aman, tetapi mahal untuk perangkat dan server.

Query untuk menentukan batas aman tidak dapat dijalankan dari server: cursor
disimpan di perangkat. Turunkan dari umur maksimum perangkat offline yang
diterima produk, bukan dari ukuran tabel.

## 5. Rollback dan fix-forward

**Rollback penuh** tidak disarankan dan tidak diuji. Menghapus jurnal akan
membuat setiap perangkat yang sudah menyimpan cursor menunjuk posisi yang tidak
ada; mereka akan menerima `sync_cursor_invalid` dan resync penuh — pemulihan yang
benar, tetapi serentak.

**Fix-forward yang lebih murah** untuk sebagian besar masalah:

| Gejala | Tindakan |
| --- | --- |
| Beban tulis jurnal terlalu tinggi | Nonaktifkan trigger jurnal pada tabel yang paling ramai (`alter table … disable trigger trg_<tabel>_change_journal`). Feed berhenti melaporkan tabel itu; klien tidak rusak, hanya tidak menerima perubahannya. |
| Realtime membebani | Keluarkan tabel dari publikasi. Pull tetap jalan lewat login, resume, reconnect, dan manual sync. |
| Kebocoran scope terdeteksi | `revoke execute on function public.pull_sync_changes(...) from authenticated`. Push 12B tetap berfungsi; aplikasi kembali ke perilaku push-only. |
| Jurnal terlalu besar | Jalankan pruning manual dengan `keep_through` konservatif. |

Menonaktifkan pull sepenuhnya adalah rollback paling aman: klien 12C
memperlakukan kegagalan pull sebagai retryable dan tetap dapat push.

## 6. Yang belum terverifikasi

- Perilaku di bawah volume produksi — semua angka di sini dari stack lokal.
- Backfill: strateginya didokumentasikan, belum dijalankan.
- Retensi: fungsinya ada, belum pernah dieksekusi terhadap data nyata.
- Head-of-line horizon di bawah transaksi panjang produksi.
- Beban probe keberadaan policy jurnal per baris pada tabel jurnal besar.
- Multi-device melampaui lima device dan empat actor fixture.

## 7. Gate sebelum rollout

- Backup dan restore terverifikasi di staging.
- Strategi backfill dipilih dan dijalankan di staging.
- `supabase test db` lulus di staging.
- Runner 12C dijalankan terhadap staging, bukan hanya lokal.
- Beban tulis dan ukuran jurnal diukur dengan traffic realistis.
- Kebijakan retensi disepakati pemilik produk.
- Rilis klien dijadwalkan setelah migrasi server.
