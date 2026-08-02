# Supabase Sync Next Steps

Revision 002 menyediakan push-only transactional outbox, typed RPC, server
idempotency/numbering, atomic ledger helpers, conflict logging, dan trusted upload.
General pull sengaja belum aktif.

## Milestone 12B — trusted writes dan push

- RPC transaksional per workflow, bukan generic table write.
- Server document numbering pada submit (`TMP-*` menjadi nomor final).
- Revalidate actor dari `auth.uid()` mapping, role, branch, state, timestamps,
  batch/FEFO, quantity, dan segregation of duties di dalam transaksi.
- Atomic server stock posting; ledger UUID append-only dan balance non-negatif.
- Idempotency key per operation/device retry.
- Push pending Drift changes dengan acknowledgement dan audit.
- Trusted Storage upload untuk validated import source/report retention.
- Contract test setiap RPC terhadap RLS dan direct-client denial.

Server cursor sudah tersedia di setiap syncable table:

```text
server_updated_at timestamptz
server_version bigint
```

Trigger mengabaikan nilai client, memakai server clock, dan menaikkan version
tepat sekali. `created_at`, quantity, dan status bisnis tidak disentuh trigger.

## Milestone 12C — pull, conflict, numbering completion, signals

- Pull deterministik dengan cursor `(server_updated_at, id)` dan pagination.
- Cursor disimpan per table/account; account switch tidak berbagi cache.
- Tombstone/soft-delete handling.
- Draft conflict per-column sesuai G-Y3; final server-wins.
- Conflict audit dan UI resolusi yang tidak mengedit final document.
- Reconcile temporary/final number mapping.
- Realtime hanya sebagai invalidation signal; data tetap diambil lewat pull
  terotorisasi, bukan dipercaya dari payload signal.
- Signed/trusted cached profile policy bila read-only offline production dibuka.

## Gates sebelum remote rollout 12B

- Remote project dan Auth Dashboard tersedia.
- Role/branch matrix diterima pemilik produk.
- Local `db reset` + pgTAP tetap lulus.
- Backup/rollback dan staging environment tersedia.
- Tidak ada remote write dari credential developer yang tidak terkontrol.
