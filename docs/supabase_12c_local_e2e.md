# Local E2E Milestone 12C

Prasyarat sama seperti 12B: Docker, Flutter, Deno, Node/npm, dan Supabase CLI.
Seluruh perintah menargetkan stack lokal; tidak ada project atau credential
remote.

```bash
npx supabase start
npx supabase db reset
npx supabase test db
npx supabase db lint
deno test supabase/functions
flutter test
bash tool/run_supabase_12b_e2e.sh
npx supabase db reset
bash tool/run_supabase_12c_e2e.sh
```

`db reset` dijalankan lagi sebelum runner 12C karena runner 12B meninggalkan
dokumen dan posisi jurnal; 12C mengasserikan aritmetika cursor, sehingga butuh
titik awal deterministik. Runner 12C tidak memerlukan Edge Function server —
kontrak pull adalah RPC database, jadi seluruh assertion lewat PostgREST dengan
token sesi sungguhan.

## Yang dibuktikan pgTAP

`supabase/tests/database/pull_sync.test.sql` menambah 74 assertion di atas
suite 12B:

- struktur jurnal, grant, dan RLS paksa; klien tidak dapat insert, update, atau
  delete baris jurnal, dan tidak dapat membaca `sync_entity_field_versions`
  mentah;
- setiap fungsi `SECURITY DEFINER` baru tetap mengunci `search_path`;
- ledger tetap append-only dengan trigger jurnal terpasang — update dan delete
  keduanya ditolak;
- dua perubahan pada `statement_timestamp()` yang sama tetap memiliki
  `change_seq` berbeda;
- tombstone dicatat saat `deleted_at` pertama kali terisi, dan tidak dicatat
  lagi saat baris yang sudah terhapus diedit;
- `is_active = false` adalah upsert, bukan tombstone (G-A4);
- `field_version` mengambil `server_version` entity, kolom yang tak tersentuh
  mempertahankan versi lama, dan tulisan yang tidak mengubah nilai tidak
  menggerakkan versi apa pun;
- daftar kolom mergeable dipin literal per entity — pasangan klien-server;
- **ekuivalensi RLS**: untuk setiap entity type dan setiap actor fixture,
  himpunan id yang lolos RLS identik dengan himpunan id yang diloloskan
  `app_private.pull_entity_visible`. Ini yang menjaga predikat SECURITY DEFINER
  tidak menyimpang dari policy;
- isolasi cabang dan role lewat RPC nyata pada data seed yang sudah commit;
- pagination limit kecil mengunjungi setiap change tepat sekali dan berakhir di
  posisi yang sama dengan satu halaman besar;
- cursor negatif, cursor di luar feed, limit 0, limit 501, device kosong, dan
  device milik actor lain semuanya ditolak dengan kode aman;
- payload dokumen selalu membawa `lines`; PR membawa `opname_links` dan tidak
  membawa `movements`; dokumen posting membawa `movements`;
- baris line dijurnal terhadap header induknya, sehingga tidak ada entity type
  `*_line` sama sekali;
- **horizon commit** menahan perubahan transaksi yang belum settle — pgTAP
  berjalan dalam satu transaksi, jadi assertion ini menguji tepat kasus yang
  membuat cursor tidak pernah melompati change yang belum terlihat.

## Yang dibuktikan runner HTTP 12C

`tool/supabase_12c_e2e.ts` menjalankan empat sesi terautentikasi dan lima device
terdaftar, lalu membuktikan:

- perangkat yang mulai dari cursor 0 mencapai state saat ini, urutannya menaik
  ketat, dan feed yang sudah terkuras melaporkan `has_more = false` tanpa
  menggerakkan cursor;
- device A submit Purchase Request; Warehouse — actor dan device berbeda —
  menerimanya lewat pull lengkap dengan nomor dokumen final server dan barisnya;
- perawat tidak pernah mengetahui keberadaan Purchase Request, cabang lain,
  atau baris pengguna selain miliknya; kepala cabang A tidak melihat ruangan
  cabang B; dua scope tidak pernah berbagi fingerprint; device milik actor lain
  ditolak `sync_access_denied`;
- jalan berhalaman tiga-per-halaman mengunjungi change yang persis sama dengan
  satu halaman 500, tanpa lompatan dan tanpa pengulangan, dan berakhir di posisi
  yang sama;
- cursor yang sama menghasilkan batch identik; memutar ulang halaman yang sudah
  dikonsumsi bersifat deterministik — inilah yang membuat event Realtime
  duplikat, terlambat, atau tidak berurutan tidak berbahaya;
- cursor dan limit tidak valid ditolak dengan kode stabil tanpa membocorkan
  nama fungsi internal; anon tidak dapat memanggil pull sama sekali;
- device kedua yang sepenuhnya offline mengejar dan mendarat pada state
  identik;
- `field_version` kolom yang diubah naik ke versi entity baru sementara kolom
  lain mempertahankan versi lama; `sku` dan `server_version` tidak pernah
  ditawarkan untuk merge; push dari base version basi ditolak; setelah rebase,
  kolom kedua device bertahan bersama kolom device pertama;
- kategori baru datang sebagai upsert, soft delete-nya datang sebagai tombstone
  tanpa payload, dan barisnya **masih ada di server** — tombstone bukan hard
  delete; `is_active = false` tetap upsert;
- consumption yang diposting datang utuh dengan baris dan UUID movement klien
  yang persis; posisi balance sampai sebagai entity tersendiri sehingga kartu
  stok benar meski dokumen yang menggerakkannya di luar scope; tidak ada saldo
  negatif;
- push retry bersamaan dengan pull tidak menghasilkan movement ganda dan saldo
  hanya terdebit sekali;
- klien tidak dapat insert atau delete baris jurnal, tidak dapat update ledger,
  tidak dapat membaca field version mentah, dan kanal Realtime tidak membocorkan
  baris di luar scope.

## Yang dibuktikan test Flutter

`flutter test test/sync test/db/migration_v14_to_v15_test.dart` menjalankan
137 test tanpa jaringan: merge tiga arah sebagai logika murni, applier terhadap
database sungguhan, worker cursor/transaksi/rollback/retry, recovery final,
koalesensi Realtime, orkestrasi, klasifikasi entity, dan rantai migrasi.

## Batasan

Harness ini bukan bukti deployment remote. Skenario beban lintas workflow, jumlah
device besar, dan perilaku Realtime di bawah jaringan nyata tetap harus diulang
di staging sebelum rollout. Lihat `supabase_12c_remote_handoff.md`.
