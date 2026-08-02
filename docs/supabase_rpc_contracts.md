# RPC contracts revision 002

Client write surface:

- `register_sync_device(device_id, requested_app_install_id, requested_display_label)`
- `push_sync_operation(operation_envelope)`
- `create_file_upload_intent(request_id, entity_type, entity_id, …)`
- `finalize_file_upload(...)`

Semua fungsi hanya diberi EXECUTE kepada `authenticated`, memperoleh actor dari
`auth.uid() → user_auth_links → users`, memuat ulang status aktif/role/branch, dan memakai
`SECURITY DEFINER SET search_path = ''`. Tidak ada actor parameter bisnis yang dipercaya.

Operasi push: master upsert per aggregate; submit/review SO; submit/process/reject/cancel
PR; ship DO; post GR/DIST/DSP/CNS; ship/receive RET; append audit impor/ekspor. Snapshot
workflow dibatasi 500 baris. Server mengembalikan `accepted`, `replayed`, atau `conflict`
beserta request ID, server version/time, nomor final, dan movement UUID.

| Operasi | Actor server | Transition/tabel atomik |
|---|---|---|
| submit/review SO | Perawat / Kepala Cabang | SO + lines; review juga movement/balance |
| submit/process/reject/cancel PR | Kepala Cabang / Warehouse | PR + lines/opname links + audit transition |
| ship DO | Warehouse | DO + lines + shipment ledger + PR state |
| post GR | Kepala Cabang tujuan | GR + decisions + receipt ledger + DO/PR state |
| post DIST | Kepala Cabang | DIST + multi-room transfer ledger |
| post DSP | Warehouse atau Kepala Cabang sesuai lokasi | DSP + source-only ledger |
| post CNS | Perawat room sendiri | CNS + source-only ledger |
| ship/receive RET | Kepala Cabang / Warehouse | RET + lines; receive menambah warehouse ledger |
| upsert master | Super Admin | Satu master; branch/room menyertakan lokasi stok exact |
| append import/export audit | Actor asli | Audit append; import mensyaratkan source finalized |

Draft tetap lokal. Server menghitung movement plan dari state/snapshot, membandingkan set
field bisnis, memakai UUID movement client, mengunci posisi balance dalam stable composite
order, lalu menjalankan movement, balance, status, dan numbering pada satu transaksi.

Kode stabil meliputi `sync_auth_required`, `sync_identity_unlinked`,
`sync_user_inactive`, `sync_actor_mismatch`, `sync_access_denied`,
`sync_invalid_payload`, `sync_request_id_reused`, `sync_stale_version`,
`sync_final_state_conflict`, `sync_dependency_missing`,
`sync_dependency_pending`, `sync_movement_plan_mismatch`,
`sync_insufficient_stock`, dan kode upload yang
didokumentasikan di `supabase_storage_upload.md`. Pesan UI tidak memakai substring SQL.
