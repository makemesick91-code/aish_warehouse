# Aish Warehouse

Aplikasi gudang klinik gigi (Flutter + Drift/SQLite, offline-first).
Spesifikasi lengkap ada di [`AISH_WAREHOUSE_SPEC.md`](AISH_WAREHOUSE_SPEC.md) —
dokumen itu adalah sumber kebenaran untuk seluruh aturan bisnis.

## Status

| Milestone | Cakupan | Status |
|---|---|---|
| 1 | Fondasi aplikasi, master data, ledger stok (`stock_movements`, `stock_balances`), FEFO | Selesai |
| 1.1 | Zona waktu operasional GMT+8, kuantitas fixed-point milli-unit (schema v2) | Selesai |
| 2 | **Stok Opname** (`stock_opnames`, `stock_opname_lines`, schema v3) | Selesai |
| 3 | Purchase Request | Belum |

## Menjalankan

```bash
flutter pub get
dart run build_runner build     # kode Drift generated
flutter run
```

Pada halaman pengembangan, tekan **Jalankan Seed Pengembangan** untuk mengisi
cabang, ruangan, pengguna, barang, batch, saldo Warehouse Pusat, dan saldo awal
Ruang Dental 1. Seed bersifat idempoten dan hanya berjalan pada build debug.

## Schema database

| Versi | Cakupan |
|---|---|
| v1 | Skema awal Milestone 1 (kuantitas unit bulat) |
| v2 | Kuantitas ledger menjadi fixed-point milli-unit (skala 1000) |
| **v3** | Stok Opname: `stock_opnames` + `stock_opname_lines` |

Migrasi v2 → v3 bersifat aditif: dua tabel baru beserta index-nya, tanpa
menyentuh satu pun kolom lama. Database v1 dapat dibuka langsung pada v3 —
penskalaan v1 → v2 berjalan tepat sekali, lalu tabel opname ditambahkan.

Catatan schema v3:

- `stock_opname_lines.difference` adalah **generated column** (`STORED`) yang
  dihitung SQLite sebagai `counted_qty - system_qty`, sehingga tidak pernah
  bisa berbeda dari operandnya. Nilainya boleh negatif.
- Keunikan memakai **partial unique index**, bukan `UNIQUE` biasa:
  - `stock_opnames (room_id, period_year, period_week) WHERE deleted_at IS NULL`
    — satu opname per ruangan per minggu ISO (G-O1), dan draft yang dihapus
    tidak memblokir minggu itu.
  - `stock_opname_lines (opname_id, item_id, batch_id) WHERE batch_id IS NOT NULL
    AND deleted_at IS NULL` dan pasangannya untuk `batch_id IS NULL` — SQLite
    menganggap setiap NULL berbeda, sehingga `UNIQUE` biasa akan meloloskan
    baris ganda untuk barang tanpa batch.
- `system_qty`, `counted_qty`, dan `difference` adalah INTEGER milli-unit
  (1 unit = 1000). REAL dan `double` dilarang pada jalur kuantitas.

## Workflow Stok Opname (development)

Autentikasi belum ada. Peran dipilih lewat kartu **Sesi pengembangan** di
halaman utama, yang menggantikan login sementara. Use case tetap memvalidasi
peran dan cabang dari database, sehingga mengganti sesi tidak memberi wewenang
apa pun yang tidak dimiliki pengguna tersebut.

**Perawat → kirim**

1. Pilih pengguna berperan *Perawat* pada kartu sesi, lalu buka **Stok Opname**.
2. Tekan **+ Opname Minggu Ini** untuk ruangan yang dituju. Tombol nonaktif bila
   ruangan itu sudah dihitung minggu ini (G-O1) dan menjelaskan alasannya.
3. Dokumen dibuat sudah terisi: setiap posisi stok ruangan menjadi satu baris
   dengan `system_qty` hasil snapshot saat itu (G-O2), dan tidak pernah berubah
   lagi walau ada transaksi berjalan.
4. Isi **Hasil hitung** (menerima `0`, `0.5`, `0,5`, `2.375`). Selisih dihitung
   otomatis; bila tidak nol, **catatan wajib** (G-O3).
5. Barang yang ditemukan fisik tetapi tidak ada di snapshot dapat ditambahkan
   lewat pencarian (nama atau SKU, mengikuti chip kategori, bekerja offline).
6. **Kirim** memvalidasi seluruh dokumen sekaligus dan menandai baris yang masih
   kurang catatan. Setelah terkirim, dokumen read-only bagi Perawat.

**Kepala Cabang → review**

1. Ganti sesi ke pengguna berperan *Kepala Cabang*, buka **Review**.
2. Daftar hanya memuat dokumen `submitted` dari cabang sendiri (G-R2).
3. Detail menampilkan selisih per baris dan ringkasan kelebihan/kekurangan
   **per satuan** — kuantitas beda satuan tidak pernah dijumlahkan.
4. **Review & Kunci** meminta konfirmasi, lalu dalam **satu transaksi**:
   membaca saldo terkini tiap baris, memposting `opname_adjustment`
   (`ref_doc_type = SO`, `ref_doc_id = opname.id`, aktor = reviewer), dan
   mengunci dokumen. Semua baris berhasil atau tidak ada satu pun yang tersimpan.
5. Setelah direview, saldo ruangan sama persis dengan hasil hitung fisik (G-O5)
   dan dokumen bersifat final permanen (G-S2).

Pembuat dokumen tidak boleh mereview dokumennya sendiri (G-R4) — ditegakkan di
use case *dan* oleh CHECK constraint di database.

## Pengujian

```bash
flutter test                                # seluruh suite
flutter test test/opname                    # Milestone 2: aturan, RBAC, UI
flutter test test/db                        # schema, migrasi, seed
```

Berkas uji Milestone 2:

| Berkas | Cakupan |
|---|---|
| `test/db/migration_v2_to_v3_test.dart` | Migrasi v2→v3 dan v1→v3, `foreign_key_check` |
| `test/db/opname_schema_test.dart` | Constraint, partial unique index, generated column |
| `test/opname/opname_rules_test.dart` | G-O1 … G-O4 |
| `test/opname/opname_review_test.dart` | G-O5, atomisitas dan rollback |
| `test/opname/opname_rbac_test.dart` | RBAC dan mesin status |
| `test/opname/opname_repository_test.dart` | Stream, konkurensi, filter, pencarian |
| `test/opname/opname_perawat_widget_test.dart` | UI Perawat |
| `test/opname/opname_review_widget_test.dart` | UI Kepala Cabang |
| `test/opname/opname_architecture_test.dart` | Batas lapisan dan atomisitas (guard sumber) |

Seluruh uji memakai database in-memory dan clock yang di-inject, sehingga tidak
bergantung pada perangkat maupun waktu nyata.
