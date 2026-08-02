# Local E2E Milestone 12B

Prasyarat: Docker, Flutter, Deno, Node/npm, dan Supabase CLI. Semua perintah di
halaman ini menargetkan stack lokal; tidak perlu project atau credential remote.

```bash
npx supabase start
npx supabase db reset
npx supabase test db
npx supabase db lint
deno test supabase/functions
flutter test test/sync test/db/migration_v13_to_v14_test.dart
bash tool/run_supabase_12b_e2e.sh
```

Runner mengambil URL serta key lokal langsung dari `supabase status -o env`,
menjalankan Edge Functions dengan verifikasi JWT, lalu membersihkan proses function
server saat selesai. Key tidak disalin ke source. Jalankan `db reset` sebelum runner
agar fixture server kembali deterministik.

HTTP E2E membuktikan:

- login Auth lokal dan register device;
- hash canonical lintas JavaScript/PostgreSQL;
- master push, exact request replay, dan reused-key rejection;
- dua request PR ekuivalen benar-benar dikirim bersamaan dengan `Promise.all`,
  menghasilkan tepat satu acceptance, satu replay, dan satu nomor final;
- authenticated PR process, DO shipment/replay, mixed GR post, return ship/receive,
  multi-room distribution, consumption, dan disposal;
- wrong-role, cross-branch, inactive-user, stale-version, dan final-state conflict;
- dua konsumsi memperebutkan 1.500 milli-unit secara bersamaan: tepat satu
  menang, saldo akhir 500, dan hanya satu movement tersimpan;
- dua DO memperebutkan saldo Warehouse dan dua distribution memperebutkan batch
  gudang cabang: masing-masing tepat satu winner, satu rollback utuh, tanpa saldo
  negatif atau dokumen loser parsial;
- disposal dan consumption dikirim bersamaan terhadap source serta batch
  kedaluwarsa yang sama: disposal diterima, consumption ditolak oleh aturan expiry,
  saldo tepat, dan tidak ada dokumen consumption parsial;
- GR penambah stok dan distribution pembaca/pengurang posisi yang sama dikirim
  bersamaan; hasilnya serializable (distribution diterima atau stable insufficient
  stock), saldo tepat, dan tidak ada dokumen parsial;
- dua payload multi-item dengan urutan item/movement terbalik selesai tanpa
  deadlock karena posisi ledger dikunci dalam urutan deterministik;
- duplicate request concurrent, different request dengan final document ekuivalen,
  movement UUID yang dipakai ulang dengan payload berbeda, serta request ID sama
  dengan hash berbeda;
- signed private upload, hash/size/MIME verification, cross-user finalize denial,
  hash mismatch rejection, serta best-effort invalid-object deletion.

pgTAP melengkapi HTTP harness dengan grant/RLS, anonymous/inactive denial,
numbering, direct-table write denial, dan eksekusi nyata seluruh jalur workflow:
opname submit/review, PR process, DO ship, GR post, distribution, disposal,
consumption, serta goods-return ship/receive. Assertions juga memeriksa saldo dan
exact reuse UUID movement. Flutter fakes menguji lease recovery, actor filtering,
bounded draining, retry/no-retry, successor request, safe acknowledgement, upload
worker, dan UI.

Harness ini tidak dianggap bukti deployment remote. Skenario beban lintas workflow
yang lebih luas tetap harus diulang di staging dengan traffic dan observability
production sebelum remote rollout.
