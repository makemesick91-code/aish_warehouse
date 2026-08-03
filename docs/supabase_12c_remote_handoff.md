# Remote deployment handoff — Milestone 12C

Revisi server `aish-supabase-003`.

> **Status deploy — sudah diterapkan ke produksi.** Kalimat "belum pernah
> dijalankan di project remote" pada revisi dokumen sebelumnya sudah tidak
> berlaku. Seluruh 11 migrasi sampai
> `20260803000200_sync_change_journal_backfill_support.sql` sudah diterapkan ke
> project produksi, tanpa error, **sebelum approved preflight benar-benar
> berjalan**. Insiden, penyebab, containment, bukti backup/restore, dan
> verifikasi live tercatat di `supabase_12c_production_rollout_incident.md`.
>
> Tidak ada rollback, tidak ada `migration repair`, tidak ada `db reset` remote.
> Backfill **SKIP** (seluruh tabel live bernilai 0). Canary, Realtime canary,
> dan benchmark **BLOCKED** — menunggu credential, change ticket, maintenance
> window, dan operator acknowledgement. GO/NO-GO = **HOLD**.

Seluruh verifikasi pada `supabase_12c_local_e2e.md` berjalan di stack lokal.

> **Rollout staging.** Runbook operasional — backup, urutan deploy, backfill,
> verifikasi, E2E staging, benchmark, retensi, fix-forward, dan tabel GO/NO-GO —
> ada di `supabase_12c_staging_rollout.md`. Dokumen ini tetap menjadi inventaris
> revisi 003 dan catatan risiko; dokumen itu yang dijalankan.
>
> **Production canary.** Bila project remote yang tersedia adalah produksi dan
> bukan staging, jalurnya terpisah: `supabase_production_canary_rollout.md`.
> Jalur itu punya guard sendiri (`tool/production_guard.ts`), konfirmasi ganda,
> blocker backup + restore rehearsal, jendela maintenance, dan seluruh tool-nya
> read-only atau dry-run secara default. Staging tooling tidak diubah dan tidak
> dilemahkan untuk itu.

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

**Backfill.** Jurnal dimulai kosong, jadi data yang sudah ada sebelum migrasi
tidak muncul di feed sampai baris itu tersentuh. Konsekuensinya perangkat baru
tidak menerima master data lama lewat pull.

Dua opsi pernah dipertimbangkan:

- **Backfill eksplisit** — insert satu baris jurnal `upsert` per baris hidup di
  setiap tabel syncable, dengan `server_version` baris itu apa adanya. Aman
  karena apply bersifat idempoten, tetapi menghasilkan feed awal sebesar seluruh
  dataset.
- **Sentuh ulang** — `UPDATE ... SET updated_at = updated_at` per tabel, yang
  membiarkan trigger menulis jurnalnya sendiri. Lebih sederhana tetapi menaikkan
  `server_version` setiap baris dan karena itu menggerakkan seluruh
  `field_version`, sehingga merge berikutnya akan memenangkan server pada setiap
  kolom. Perangkat dengan edit lokal pending kehilangan edit itu diam-diam.

Opsi kedua **ditolak**. Yang diimplementasikan adalah opsi pertama, lewat
migrasi `20260803000200_sync_change_journal_backfill_support.sql`: fungsi
administratif privat yang dijalankan batch demi batch oleh
`tool/run_supabase_12c_backfill_staging.sh`, idempoten lewat primary key
`(backfill_revision, entity_type, entity_id)`, resumable dari checkpoint yang
disimpan server, punya dry-run, dan tidak pernah menulis satu kolom bisnis pun.
Migrasi itu sendiri tidak menjalankan backfill apa pun saat deploy.

Prosedurnya ada di `supabase_12c_staging_rollout.md` §6; regresinya dijaga
`supabase/tests/database/journal_backfill.test.sql`.

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
- Backfill: mekanismenya sudah diimplementasikan dan diuji lokal (pgTAP), tetapi
  belum dijalankan terhadap project remote mana pun.
- Retensi: fungsinya ada, planner-nya ada, belum pernah dieksekusi terhadap data
  nyata — dan memang tidak boleh sebelum keputusan produk di
  `supabase_12c_staging_rollout.md` §8.
- Head-of-line horizon di bawah transaksi panjang produksi.
- Beban probe keberadaan policy jurnal per baris pada tabel jurnal besar.
- Multi-device melampaui lima device dan empat actor fixture.

## 7. Gate sebelum rollout

Tabel GO/NO-GO lengkap ada di `supabase_12c_staging_rollout.md` §10. Ringkasnya:

- Backup dan restore terverifikasi di staging.
- Backfill dijalankan di staging dan `missing_baseline_total = 0`.
- `supabase test db` lulus di staging.
- Runner 12B dan 12C staging lulus, bukan hanya lokal.
- Realtime diuji lewat frame nyata, termasuk isolasi lintas cabang.
- Beban tulis dan ukuran jurnal diukur dengan traffic realistis.
- Fix-forward (cabut execute pull) sudah dilatih di staging.
- Kebijakan retensi disepakati pemilik produk — belum ada prune yang dijadwalkan.
- Rilis klien dijadwalkan setelah migrasi server.
