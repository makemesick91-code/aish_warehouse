# Push sync Milestone 12B

Jalur produksi adalah `business transaction → sync_outbox → authenticated RPC →
PostgreSQL transaction → local acknowledgement`. Draft tetap device-authoritative dan
tidak dikirim. Status bisnis tetap hanya `pending`, `synced`, dan `conflict`; keadaan
`processing` berada di outbox.

Envelope memakai UUID request/device/aggregate, operasi dan aggregate bertipe,
`payload_version = 1`, base server version, waktu kejadian UTC, serta snapshot aggregate.
JSON di-hash SHA-256 setelah semua object key diurutkan leksikal, rekursif, tanpa
whitespace. PostgreSQL memakai serializer canonical yang sama—bukan urutan internal
`jsonb::text`. Hash klien tetap advisory dan dihitung ulang server; hash snapshot lokal
juga diverifikasi sebelum acknowledgement.

Worker bersifat single-flight, batch 20, dan lease dua menit. Retry hanya untuk network,
timeout, 429, 5xx, `sync_dependency_pending`, dan `sync_retry_later`; backoff
eksponensial berjitter dibatasi lima
menit. Access/security, payload invalid, stale version, dan final mismatch menjadi conflict.
Operasi hanya dikirim ketika akun aktif sama dengan actor lokal. Akun lain melihat operasi
tetap antre sebagai “menunggu akun pembuat”; tidak ada reassignment otomatis.

Rebuild data schema 1–13 tidak menerima identitas sesi. Provenance diambil langsung
dari kolom audit workflow: opname `counted_by` lalu `reviewed_by`; PR
`requested_by`, `processed_by`, `rejected_by`, atau `cancelled_by` per transisi;
DO `shipped_by`; GR `received_by`; distribusi `distributed_by`; disposal dan
consumption `posted_by`; retur `shipped_by` lalu `received_by`; audit
`imported_by`/`exported_by`. State bertahap menghasilkan satu operation per transisi,
masing-masing dengan actor dan waktu historisnya sendiri. Rebuild ulang dan account
switch tidak mengubah actor operation yang sudah ada.

Master schema 1–13 tidak memiliki kolom actor. Pending master legacy direkonstruksi
dengan `actor_user_id = NULL`, `status = blocked`, dan error stabil
`sync_original_actor_unknown`; current session maupun Super Admin tidak pernah
mengambil alih. Worker hanya membaca status `queued` milik actor aktif, sehingga
blocked ini tidak dipoll, tidak menambah retry counter, dan menunggu rekonsiliasi
administratif 12C. Bila row master semantik yang dibutuhkan sudah ada di server,
foreign-key/semantic checks workflow dapat tetap terpenuhi tanpa mengirim mutasi
master yang actor-nya tidak diketahui.

Upload file memakai queue/lease terpisah, tetap difilter actor, dan dijalankan sebelum
outbox bisnis. Audit impor diblokir lokal sampai file private finalized. Upload report
bersifat opsional dan kegagalannya tidak membatalkan audit ekspor lokal/server.

Movement UUID lokal dipakai persis di server. `occurred_at_utc` mempertahankan waktu fisik
offline dan tanggal operasional dihitung di Asia/Makassar. Jam perangkat offline tidak
anti-tamper; server menolak waktu lebih dari lima menit di masa depan.

12B mendeteksi stale/non-final serta final mismatch dan mencatatnya. Perbaikannya
ada di 12C: pull deterministik, tombstone, LWW per kolom, dan recovery konflik
final — lihat `supabase_12c_sync_design.md` dan `supabase_12c_reconciliation.md`.

Push tidak berubah pada 12C. Yang bertambah hanya urutannya: satu siklus kini
push dulu, baru pull, lalu — hanya bila rekonsiliasi menyisakan kolom yang masih
terutang ke server — satu ronde push tambahan yang dibatasi tepat sekali. Blocked
master legacy `sync_original_actor_unknown` tetap menunggu rekonsiliasi
administratif dan tidak pernah diambil alih akun mana pun.
