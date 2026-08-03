# Supabase Sync Next Steps

Revisi 003 melengkapi revisi 002 dengan jalur baca: change feed deterministik,
tombstone, rekonsiliasi per kolom, recovery konflik final, dan Realtime sebagai
invalidation. Push, idempotency, canonical hash, outbox dependency, trusted
upload, dan transaksi atomik 12B tidak berubah.

## Milestone 12B — trusted writes dan push (selesai)

- RPC transaksional per workflow, bukan generic table write.
- Server document numbering pada submit (`TMP-*` menjadi nomor final).
- Revalidate actor dari `auth.uid()` mapping, role, branch, state, timestamps,
  batch/FEFO, quantity, dan segregation of duties di dalam transaksi.
- Atomic server stock posting; ledger UUID append-only dan balance non-negatif.
- Idempotency key per operation/device retry.
- Push pending Drift changes dengan acknowledgement dan audit.
- Trusted Storage upload untuk validated import source/report retention.
- Contract test setiap RPC terhadap RLS dan direct-client denial.

## Milestone 12C — pull, rekonsiliasi, tombstone, signals (selesai)

- Change journal terurut (`sync_change_journal`) dengan `change_seq` monotonik
  dan commit horizon berbasis `xid8`, menggantikan rencana cursor
  `(server_updated_at, id)` yang tidak dapat menjamin no-skip saat sebuah row
  berubah dua kali. Trade-off terdokumentasi di `supabase_12c_sync_design.md`.
- `public.pull_sync_changes` terotorisasi, paginasi berbatas, filter scope di
  server, dan `scope_fingerprint` yang menginvalidasi cursor saat role/branch
  berubah. Cursor disimpan per `(actor, fingerprint)`; account switch tidak
  berbagi cache.
- Batch diterapkan bersama cursor dalam satu transaksi Drift; kegagalan di
  tengah membatalkan seluruh batch dan cursor tidak maju.
- Tombstone deterministik yang menulis `deleted_at`, bukan `DELETE`, dengan
  catatan anti-resurrection. Klasifikasi per entity di
  `supabase_12c_reconciliation.md`.
- LWW per kolom untuk master data memakai `field_version` server (G-Y3); dokumen
  final selalu dimenangkan server (G-Y2).
- `FinalConflictRecoveryService`: snapshot server diterapkan, movement lokal yang
  tidak diterima server dibalik dengan reversal ber-UUID deterministik (G-A1),
  outbox diselesaikan, conflict log menerima resolusi eksplisit.
- Realtime hanya invalidation, di-debounce dan dikoalesensi; sistem tetap benar
  tanpanya lewat login, resume, reconnect, dan manual sync.
- Nomor dokumen final server dipertahankan saat rekonsiliasi.

## Berikutnya — hybrid storage

Fondasi penyimpanan file besar di server sendiri **baru boleh dimulai setelah
seluruh acceptance gate 12C lulus di staging**, bukan hanya lokal. Abstraksi
upload 12B (`TrustedFileUploadGateway`, `SyncFileUploads`, intent/finalize)
sengaja tidak diubah pada 12C, sehingga backend penyimpanan dapat ditukar tanpa
menyentuh jalur sync.

Prasyarat sebelum memulai:

- gate rollout 12C di `supabase_12c_remote_handoff.md` terpenuhi;
- backfill jurnal dijalankan dan diverifikasi;
- kebijakan retensi jurnal disepakati;
- beban tulis jurnal dan Realtime terukur pada traffic realistis.

## Gate sebelum remote rollout

- Remote project dan Auth Dashboard tersedia.
- Role/branch matrix diterima pemilik produk.
- Local `db reset` + pgTAP tetap lulus.
- Runner 12B dan 12C dijalankan terhadap staging.
- Backup/rollback dan staging environment tersedia.
- Tidak ada remote write dari credential developer yang tidak terkontrol.
- Rilis klien dijadwalkan setelah migrasi server; klien revisi 002 sengaja
  menolak server 003 lewat health check.
