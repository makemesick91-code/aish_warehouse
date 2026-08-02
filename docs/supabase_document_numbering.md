# Server document numbering

Nomor lokal selalu `TMP-SO/PR/DO/GR/DIST/DSP/CNS/RET-{uuid}`. Nomor final dialokasikan
di transaksi acceptance yang sama melalui counter `(type, scope, operational_date)` dengan
upsert atomik.

Format:

| Dokumen | Format | Scope |
|---|---|---|
| SO, PR, GR, DIST, CNS, RET | `{TYPE}-{branch.code}-{yyyyMMdd}-{seq4}` | cabang |
| DO, DSP | `{TYPE}-WH-{yyyyMMdd}-{seq4}` | warehouse |

Tanggal adalah tanggal Asia/Makassar dari `occurred_at_utc`. Branch code selalu dibaca
dari relasi server. Retry request yang sama mengembalikan nomor tersimpan; concurrency
menaikkan counter berbeda. Karena counter adalah row transaksional, kegagalan business
commit juga me-rollback alokasi; tidak ada dokumen bernomor tanpa commit. Nomor yang
sudah terpasang tidak pernah diubah.
