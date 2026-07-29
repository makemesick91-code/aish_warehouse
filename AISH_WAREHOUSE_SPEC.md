# Aish Warehouse — by Aish Tech Solution

> **Spesifikasi Desain Aplikasi Gudang Klinik Gigi**
> Tech Stack: **Flutter + Drift (SQLite, offline-first) + Sync Backend (Supabase/REST)**
> Bahasa UI: **Bahasa Indonesia** · Cakupan: **Multi-cabang, 1 Warehouse Pusat**
> Status: Dokumen desain — **belum ada implementasi kode**.

---

## 1. Ringkasan Workflow

```
[Perawat]           [Kepala Cabang]        [Warehouse Pusat]      [Kepala Cabang]
Stok Opname   ──▶   Purchase Request  ──▶  Pengiriman        ──▶  Good Receipt   ──▶  Distribusi
mingguan/ruangan    (PR) berbasis          (Surat Jalan/DO)       ceklis sesuai,      ke 3 ruangan
                    hasil opname           sesuai PR              hapus/tolak yang     dental
                                                                  tidak sesuai
```

Siklus mingguan:

1. **Stok Opname** — Setiap minggu, Perawat menghitung fisik barang di ruangan masing-masing.
2. **Purchase Request (PR)** — Kepala Cabang membuat PR ke Warehouse Pusat, dengan acuan hasil stok opname (selisih terhadap stok minimum/par level).
3. **Pengiriman (Delivery Order)** — Warehouse memproses PR dan mengirim barang beserta Surat Jalan.
4. **Good Receipt (GR)** — Kepala Cabang menerima barang, memeriksa satu per satu: **ceklis yang sesuai**, **tolak/hapus yang tidak sesuai**. Barang yang diterima masuk ke *Gudang Cabang*.
5. **Distribusi** — Kepala Cabang mendistribusikan barang dari Gudang Cabang ke **3 ruangan dental**.

### 1.1 Model Lokasi Stok (3 tingkat)

```
WAREHOUSE PUSAT ──(GR)──▶ GUDANG CABANG ──(Distribusi)──▶ RUANGAN (Ruang Dental 1/2/3)
```

Setiap lokasi punya saldo stok sendiri per barang. Semua perpindahan dicatat di **ledger `stock_movements`** (append-only); saldo adalah hasil turunan ledger.

---

## 2. Struktur Database (Drift / SQLite)

Konvensi umum untuk **semua tabel**:

| Kolom | Tipe | Keterangan |
|---|---|---|
| `id` | TEXT (UUID v4) | Primary key — UUID agar aman untuk sync offline-first |
| `created_at` | DATETIME | Waktu dibuat (UTC) |
| `updated_at` | DATETIME | Waktu update terakhir (UTC) — dipakai untuk sync |
| `deleted_at` | DATETIME? | Soft delete; tidak pernah hard delete |
| `sync_status` | TEXT | `synced` / `pending` / `conflict` |

### 2.1 Master Data

**`branches`** — Cabang klinik

| Kolom | Tipe | Keterangan |
|---|---|---|
| `code` | TEXT UNIQUE | Kode cabang, mis. `CAB-01` |
| `name` | TEXT | Nama cabang |
| `address` | TEXT? | Alamat |
| `is_active` | BOOL | Default `true` |

**`rooms`** — Ruangan dental per cabang

| Kolom | Tipe | Keterangan |
|---|---|---|
| `branch_id` | FK → branches | |
| `code` | TEXT | mis. `R1`, `R2`, `R3` (unik per cabang) |
| `name` | TEXT | mis. "Ruang Dental 1" |
| `is_active` | BOOL | |

**`users`**

| Kolom | Tipe | Keterangan |
|---|---|---|
| `full_name` | TEXT | |
| `email` | TEXT UNIQUE | Login |
| `role` | TEXT enum | `perawat` · `kepala_cabang` · `warehouse` · `super_admin` |
| `branch_id` | FK? → branches | Wajib untuk `perawat` & `kepala_cabang`; NULL untuk `warehouse`/`super_admin` |
| `is_active` | BOOL | |

**`item_categories`** — Kategori barang (mis. Bahan Tambal, Alat Sekali Pakai, Obat, APD)

| Kolom | Tipe |
|---|---|
| `name` | TEXT UNIQUE |

**`items`** — Master barang

| Kolom | Tipe | Keterangan |
|---|---|---|
| `sku` | TEXT UNIQUE | Kode barang, mis. `DEN-0001` |
| `name` | TEXT | Nama barang |
| `category_id` | FK → item_categories | |
| `unit` | TEXT | Satuan: pcs, box, botol, tube… |
| `min_stock_room` | INT | Par level / stok minimum per ruangan (acuan saran PR) |
| `min_stock_branch` | INT | Stok minimum gudang cabang |
| `has_expiry` | BOOL | `true` = barang punya tanggal kadaluarsa (dilacak per batch) |
| `expiry_alert_days` | INT | Ambang peringatan "segera kedaluwarsa", default 30 hari |
| `is_active` | BOOL | Barang nonaktif tidak muncul di form baru |

**`item_batches`** — Batch/lot per barang (untuk pelacakan kadaluarsa)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `item_id` | FK → items | Hanya untuk barang `has_expiry = true` |
| `batch_no` | TEXT | Nomor batch/lot dari kemasan |
| `expiry_date` | DATE | Tanggal kadaluarsa |
| UNIQUE(`item_id`,`batch_no`) | | |

**`stock_locations`** — Lokasi stok (digeneralisasi)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `type` | TEXT enum | `warehouse` · `branch_store` · `room` |
| `branch_id` | FK? → branches | NULL untuk warehouse pusat |
| `room_id` | FK? → rooms | Terisi hanya jika `type = room` |
| `name` | TEXT | mis. "Warehouse Pusat", "Gudang Cabang A", "Ruang Dental 1" |

### 2.2 Stok & Ledger

**`stock_balances`** — Saldo stok per lokasi per barang (cache turunan; sumber kebenaran = ledger)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `location_id` | FK → stock_locations | |
| `item_id` | FK → items | |
| `batch_id` | FK? → item_batches | NULL untuk barang tanpa kadaluarsa |
| `qty_on_hand` | INTEGER (milli-unit) | ≥ 0 selalu. Fixed-point skala 1000 — lihat §6.2 |
| UNIQUE(`location_id`,`item_id`,`batch_id`) | | Saldo dipecah per batch untuk barang ber-ED |

**`stock_movements`** — Ledger perpindahan stok (**append-only, tidak boleh di-edit/di-delete**)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `item_id` | FK → items | |
| `batch_id` | FK? → item_batches | Wajib untuk barang `has_expiry = true` |
| `from_location_id` | FK? → stock_locations | NULL jika barang masuk dari luar sistem |
| `to_location_id` | FK? → stock_locations | NULL jika barang keluar sistem (pemakaian/buang) |
| `qty` | INTEGER (milli-unit) | > 0 selalu. Fixed-point skala 1000 — lihat §6.2 |
| `movement_type` | TEXT enum | `inbound_warehouse` · `shipment` · `good_receipt` · `distribution` · `opname_adjustment` · `consumption` · `return` · `disposal` (pemusnahan barang kedaluwarsa) |
| `ref_doc_type` | TEXT | `PR` / `DO` / `GR` / `DIST` / `SO` |
| `ref_doc_id` | TEXT | ID dokumen sumber |
| `actor_user_id` | FK → users | Siapa yang melakukan |
| `note` | TEXT? | |

### 2.3 Dokumen Workflow

**`stock_opnames`** — Header stok opname (per ruangan per periode)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `doc_number` | TEXT UNIQUE | `SO-{cabang}-{yyyyMMdd}-{seq}` |
| `branch_id` | FK → branches | |
| `room_id` | FK → rooms | |
| `period_year` | INT | |
| `period_week` | INT | Minggu ISO (1–53) — kunci unik bersama room |
| `counted_by` | FK → users | Perawat |
| `status` | TEXT enum | `draft` → `submitted` → `reviewed` |
| `submitted_at` / `reviewed_at` | DATETIME? | |
| `reviewed_by` | FK? → users | Kepala Cabang |
| UNIQUE(`room_id`,`period_year`,`period_week`) | | 1 opname per ruangan per minggu |

**`stock_opname_lines`**

| Kolom | Tipe | Keterangan |
|---|---|---|
| `opname_id` | FK → stock_opnames | |
| `item_id` | FK → items | |
| `batch_id` | FK? → item_batches | Barang ber-ED dihitung **per batch** (1 baris per batch); NULL untuk barang tanpa ED |
| `system_qty` | INTEGER (milli-unit) | Stok sistem saat opname dimulai (snapshot) |
| `counted_qty` | INTEGER (milli-unit) | Hasil hitung fisik perawat; menerima desimal, mis. `0.5` |
| `difference` | INTEGER (milli-unit, generated) | `counted_qty - system_qty`; **boleh negatif** |
| `note` | TEXT? | Alasan selisih |

**`purchase_requests`** — PR dari Kepala Cabang ke Warehouse

| Kolom | Tipe | Keterangan |
|---|---|---|
| `doc_number` | TEXT UNIQUE | `PR-{cabang}-{yyyyMMdd}-{seq}` |
| `branch_id` | FK → branches | |
| `requested_by` | FK → users | Kepala Cabang |
| `status` | TEXT enum | `draft` → `submitted` → `processing` → `shipped` → `closed` · (`rejected`, `cancelled`) |
| `needed_date` | DATE? | Target barang sampai |
| `note` | TEXT? | |

**`purchase_request_opnames`** — Tautan PR ⇆ opname acuan (many-to-many)

| Kolom | Tipe |
|---|---|
| `pr_id` | FK → purchase_requests |
| `opname_id` | FK → stock_opnames |

**`purchase_request_lines`**

| Kolom | Tipe | Keterangan |
|---|---|---|
| `pr_id` | FK → purchase_requests | |
| `item_id` | FK → items | |
| `suggested_qty` | INTEGER (milli-unit) | Saran sistem: `max(0, min_stock − counted_qty)` agregat ruangan |
| `requested_qty` | INTEGER (milli-unit) | Qty final yang diminta Kepala Cabang (> 0) |
| `note` | TEXT? | |

**`delivery_orders`** — Pengiriman/Surat Jalan dari Warehouse (1 PR bisa >1 DO untuk pengiriman parsial)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `doc_number` | TEXT UNIQUE | `DO-{yyyyMMdd}-{seq}` |
| `pr_id` | FK → purchase_requests | |
| `prepared_by` | FK → users | Petugas warehouse |
| `status` | TEXT enum | `preparing` → `shipped` → `received` |
| `shipped_at` | DATETIME? | |

**`delivery_order_lines`**

| Kolom | Tipe | Keterangan |
|---|---|---|
| `do_id` | FK → delivery_orders | |
| `pr_line_id` | FK → purchase_request_lines | Wajib merujuk baris PR |
| `item_id` | FK → items | |
| `batch_id` | FK? → item_batches | Batch yang dipilih warehouse (saran otomatis **FEFO**) |
| `shipped_qty` | INTEGER (milli-unit) | > 0; kumulatif per PR line ≤ `requested_qty` |

**`good_receipts`** — Penerimaan barang oleh Kepala Cabang (1 GR per DO)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `doc_number` | TEXT UNIQUE | `GR-{cabang}-{yyyyMMdd}-{seq}` |
| `do_id` | FK UNIQUE → delivery_orders | |
| `received_by` | FK → users | Kepala Cabang |
| `status` | TEXT enum | `checking` → `posted` |
| `posted_at` | DATETIME? | |

**`good_receipt_lines`** — Ceklis per barang

| Kolom | Tipe | Keterangan |
|---|---|---|
| `gr_id` | FK → good_receipts | |
| `do_line_id` | FK → delivery_order_lines | |
| `item_id` | FK → items | |
| `batch_id` | FK? → item_batches | Diverifikasi Kepala Cabang terhadap fisik (batch & ED di kemasan) |
| `shipped_qty` | INTEGER (milli-unit) | Salinan dari DO (read-only) |
| `received_qty` | INTEGER (milli-unit) | Qty diterima; 0 ≤ received ≤ shipped |
| `line_status` | TEXT enum | `pending` → `checked` (✔ sesuai) · `rejected` (✘ tidak sesuai/dihapus) |
| `reject_reason` | TEXT? | **Wajib** jika `rejected` |

**`distributions`** — Distribusi dari Gudang Cabang ke ruangan

| Kolom | Tipe | Keterangan |
|---|---|---|
| `doc_number` | TEXT UNIQUE | `DIST-{cabang}-{yyyyMMdd}-{seq}` |
| `branch_id` | FK → branches | |
| `distributed_by` | FK → users | Kepala Cabang |
| `status` | TEXT enum | `draft` → `posted` |
| `posted_at` | DATETIME? | |

**`distribution_lines`**

| Kolom | Tipe | Keterangan |
|---|---|---|
| `distribution_id` | FK → distributions | |
| `room_id` | FK → rooms | Ruangan tujuan (harus milik cabang yang sama) |
| `item_id` | FK → items | |
| `batch_id` | FK? → item_batches | Saran otomatis **FEFO** dari saldo gudang cabang |
| `qty` | INTEGER (milli-unit) | > 0; total per item ≤ saldo gudang cabang |

**`export_logs`** — Jejak audit setiap ekspor laporan (Excel/PDF)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `report_type` | TEXT enum | `stok_lokasi` · `kartu_stok` · `rekap_opname` · `rekap_pr` · `rekap_gr` · `rekap_distribusi` · `kadaluarsa` |
| `format` | TEXT enum | `xlsx` · `pdf` |
| `scope_type` | TEXT enum | `warehouse` · `branch_store` · `room` · `branch_all` |
| `location_id` | FK? → stock_locations | Lokasi yang dilaporkan (NULL jika `branch_all`) |
| `category_id` | FK? → item_categories | Filter kategori laporan (NULL = semua kategori) |
| `branch_id` | FK? → branches | |
| `period_start` / `period_end` | DATE | Rentang periode laporan |
| `exported_by` | FK → users | |
| `file_name` | TEXT | Nama file yang dihasilkan |

**`import_logs`** — Jejak audit impor master data via template Excel (Super Admin)

| Kolom | Tipe | Keterangan |
|---|---|---|
| `entity` | TEXT enum | `items` · `item_categories` · `branches` · `rooms` · `users` · `item_batches` |
| `file_name` | TEXT | Nama file yang diunggah |
| `total_rows` | INT | Jumlah baris pada file |
| `inserted_rows` / `updated_rows` / `failed_rows` | INT | Hasil impor |
| `error_detail` | TEXT? | Ringkasan error per baris (JSON) |
| `status` | TEXT enum | `validated` (preview) → `committed` · `discarded` |
| `imported_by` | FK → users | Super Admin |

### 2.4 Diagram Relasi (ringkas)

```
branches 1─* rooms          branches 1─* users(perawat, kepala_cabang)
items *─1 item_categories        items 1─* item_batches (batch/ED)

stock_locations 1─* stock_balances *─1 items
stock_movements (ledger; FK item, from/to location, ref dokumen)

stock_opnames 1─* stock_opname_lines
purchase_requests 1─* purchase_request_lines
purchase_requests *─* stock_opnames  (via purchase_request_opnames)
purchase_requests 1─* delivery_orders 1─* delivery_order_lines
delivery_orders 1─1 good_receipts 1─* good_receipt_lines
distributions 1─* distribution_lines *─1 rooms
```

### 2.5 Efek Stok per Dokumen

| Dokumen | Saat status | Efek ledger |
|---|---|---|
| Stok Opname `reviewed` | posting selisih | `opname_adjustment`: menyesuaikan saldo ruangan ke `counted_qty` |
| DO `shipped` | posting | `shipment`: Warehouse Pusat − `shipped_qty` |
| GR `posted` | posting | `good_receipt`: Gudang Cabang + `received_qty` (baris `checked` saja). Baris `rejected` **tidak** menambah stok cabang; barang reject dicatat kembali/retur ke warehouse |
| Distribusi `posted` | posting | `distribution`: Gudang Cabang − qty, Ruangan + qty |

---

## 3. Guardrails & Business Rules

### 3.1 Aturan Peran (RBAC)

| Aksi | Perawat | Kepala Cabang | Warehouse | Super Admin |
|---|:---:|:---:|:---:|:---:|
| Buat/isi Stok Opname (ruangan sendiri, cabang sendiri) | ✔ | — | — | — |
| Review/lock Stok Opname | — | ✔ | — | — |
| Buat & submit PR | — | ✔ | — | — |
| Proses PR & buat DO/Surat Jalan | — | — | ✔ | — |
| Good Receipt (ceklis/tolak) | — | ✔ | — | — |
| Distribusi ke ruangan | — | ✔ | — | — |
| Kelola master barang & stok warehouse | — | — | ✔ | ✔ |
| Kelola cabang, ruangan, pengguna | — | — | — | ✔ |
| Impor master data via template Excel | — | — | — | ✔ |
| Lihat laporan cabang sendiri | ✔ (ruangan) | ✔ | — | ✔ |
| Lihat laporan semua cabang | — | — | ✔ | ✔ |
| Unduh laporan Excel/PDF (sesuai cakupan) | ✔ (ruangan) | ✔ | ✔ | ✔ |

Aturan tambahan RBAC:

- **G-R1** — Perawat hanya bisa membuat opname untuk ruangan di cabangnya sendiri.
- **G-R2** — Kepala Cabang hanya melihat & mengelola dokumen cabangnya sendiri.
- **G-R3** — Warehouse tidak bisa mengubah isi PR — hanya memenuhi (fulfil) atau menolak dengan alasan.
- **G-R4** — Tidak ada satu peran pun yang bisa membuat sekaligus menyetujui dokumen yang sama (pemisahan tugas / segregation of duties).

### 3.2 Mesin Status (State Machine) — transisi selain ini DITOLAK

```
Stok Opname : draft ──▶ submitted ──▶ reviewed        (final)
PR          : draft ──▶ submitted ──▶ processing ──▶ shipped ──▶ closed
                     └▶ cancelled          └▶ rejected (oleh warehouse, wajib alasan)
DO          : preparing ──▶ shipped ──▶ received      (final)
GR          : checking ──▶ posted                     (final)
Distribusi  : draft ──▶ posted                        (final)
```

- **G-S1** — Transisi hanya maju; tidak ada "un-submit" / "un-post". Koreksi dokumen final dilakukan lewat **dokumen penyesuaian baru**, bukan edit.
- **G-S2** — Dokumen berstatus final (`reviewed`/`closed`/`received`/`posted`) bersifat **read-only permanen**, termasuk baris-barisnya.
- **G-S3** — `cancelled` hanya boleh dari `draft`/`submitted` sebelum diproses warehouse.

### 3.3 Aturan Stok Opname

- **G-O1** — Maksimal **1 opname per ruangan per minggu ISO** (ditegakkan UNIQUE constraint).
- **G-O2** — `system_qty` di-snapshot saat opname dibuat dan tidak berubah walau ada transaksi berjalan.
- **G-O3** — `counted_qty ≥ 0`; selisih ≠ 0 **wajib** diisi catatan alasan.
- **G-O4** — Opname yang belum `submitted` tidak bisa dijadikan acuan PR.
- **G-O5** — Saat Kepala Cabang me-review (`reviewed`), sistem mem-posting `opname_adjustment` agar saldo ruangan = hasil hitung fisik.

### 3.4 Aturan Purchase Request

- **G-P1** — PR **wajib** menautkan ≥ 1 stok opname berstatus `submitted`/`reviewed` dari **minggu berjalan atau minggu sebelumnya** (acuan tidak boleh kedaluwarsa > 2 minggu).
- **G-P2** — `requested_qty > 0`; tiap item hanya boleh muncul 1 baris per PR.
- **G-P3** — Sistem menampilkan `suggested_qty` (par level − stok hasil opname); Kepala Cabang boleh mengubah, tetapi kenaikan > 150% dari saran menampilkan peringatan & wajib catatan.
- **G-P4** — Hanya 1 PR `submitted`/`processing` aktif per cabang dalam satu waktu (cegah duplikat pesanan).
- **G-P5** — PR `submitted` tidak bisa diedit; harus `cancelled` lalu buat baru (selama belum `processing`).

### 3.5 Aturan Pengiriman (Warehouse)

- **G-D1** — DO hanya bisa dibuat dari PR berstatus `submitted`/`processing`.
- **G-D2** — `shipped_qty` kumulatif per baris PR **tidak boleh melebihi** `requested_qty`.
- **G-D3** — `shipped_qty` tidak boleh melebihi saldo Warehouse Pusat; posting DO mengurangi stok warehouse saat itu juga (stok tidak boleh negatif — transaksi ditolak).
- **G-D4** — Warehouse tidak bisa menambahkan item yang tidak ada di PR.
- **G-D5** — PR otomatis `shipped` bila semua baris terkirim penuh; `closed` setelah semua DO diterima (GR posted).

### 3.6 Aturan Good Receipt

- **G-G1** — GR hanya bisa dibuat oleh Kepala Cabang dari cabang tujuan, dari DO berstatus `shipped`; **1 DO = 1 GR**.
- **G-G2** — Setiap baris wajib diputuskan: `checked` (✔) atau `rejected` (✘). GR tidak bisa `posted` selama masih ada baris `pending`.
- **G-G3** — `0 ≤ received_qty ≤ shipped_qty`. Kekurangan (received < shipped) otomatis tercatat sebagai **selisih pengiriman** dan dilaporkan ke warehouse.
- **G-G4** — Baris `rejected` **wajib** memiliki alasan (rusak / salah barang / kedaluwarsa / tidak dipesan). "Hapus yang tidak sesuai" = tandai `rejected` — **bukan** menghapus record (jejak audit tetap ada).
- **G-G5** — Posting GR: hanya baris `checked` yang menambah stok Gudang Cabang. Barang `rejected` masuk daftar retur ke warehouse.
- **G-G6** — GR harus di-posting maksimal 2×24 jam setelah DO diterima (pengingat otomatis).

### 3.7 Aturan Distribusi

- **G-T1** — Distribusi hanya dari Gudang Cabang ke ruangan **dalam cabang yang sama**.
- **G-T2** — Total qty per item pada satu distribusi ≤ saldo Gudang Cabang saat posting (stok tidak boleh negatif).
- **G-T3** — Satu dokumen distribusi boleh menyasar beberapa ruangan sekaligus (baris per ruangan-item).
- **G-T4** — Posting bersifat atomik: semua baris berhasil atau semua batal.

### 3.8 Aturan Integritas & Audit

- **G-A1** — `stock_movements` append-only: tidak ada UPDATE/DELETE. Koreksi = movement balik (reversal) dengan referensi movement asal.
- **G-A2** — `stock_balances` selalu ≥ 0; setiap posting divalidasi dalam transaksi database.
- **G-A3** — Semua dokumen menyimpan `actor` + timestamp; nomor dokumen berurut dan tidak dipakai ulang.
- **G-A4** — Master data yang sudah dipakai transaksi tidak boleh dihapus — hanya dinonaktifkan (`is_active = false`).
- **G-A5** — Soft delete di semua tabel; data historis tidak pernah hilang.

### 3.9 Aturan Sync (Offline-first)

- **G-Y1** — Aplikasi berfungsi penuh offline; perubahan diberi `sync_status = pending` dan dikirim saat online.
- **G-Y2** — Dokumen `draft` milik pembuatnya (device-authoritative). Begitu `submitted`, **server menjadi sumber kebenaran** — perubahan status hanya lewat server.
- **G-Y3** — Konflik pada dokumen non-final: *last-write-wins* per kolom berdasarkan `updated_at`, dengan log konflik. Konflik pada dokumen final: versi server menang mutlak.
- **G-Y4** — Nomor dokumen final di-assign server saat submit; sebelum itu memakai nomor sementara `TMP-…`.
- **G-Y5** — Ledger tidak pernah di-merge: setiap movement adalah record baru ber-UUID, sehingga sync bebas konflik.

### 3.10 Aturan Laporan & Ekspor

- **G-L1** — Cakupan laporan mengikuti RBAC: Perawat hanya ruangannya; Kepala Cabang hanya gudang cabang + ruangan cabangnya; Warehouse hanya warehouse pusat + rekap lintas cabang; Super Admin semua.
- **G-L2** — Setiap ekspor (Excel/PDF) dicatat di `export_logs` (siapa, laporan apa, lokasi & periode apa, kapan).
- **G-L3** — Laporan dihasilkan **lokal dari Drift** (tetap bisa offline); header laporan wajib mencantumkan waktu cetak, rentang periode, lokasi, dan status sync terakhir agar jelas data per kapan.
- **G-L4** — Angka laporan diambil dari ledger `stock_movements` (bukan dari cache saldo) agar konsisten dan dapat diaudit.
- **G-L5** — File ekspor diberi nama baku: `{report_type}_{lokasi}_{periode}.xlsx|pdf` — mis. `kartu_stok_R1_2026-W31.pdf` (tambahkan `_{kategori}` bila difilter).
- **G-L6** — Semua laporan dapat difilter per **kategori barang**; tanpa filter, hasil ekspor Excel/PDF dikelompokkan per kategori dengan **subtotal per kategori** + total keseluruhan.

### 3.12 Aturan Master Data & Template Import (Super Admin)

- **G-M1** — Halaman Master Data & Template Import **hanya** dapat diakses role `super_admin` (route guard + validasi server).
- **G-M2** — Template Excel per entitas diunduh **dari aplikasi** (bukan file bebas) agar versi kolom selalu cocok: baris 1 = header kolom, baris 2 = contoh terisi, sheet kedua = petunjuk pengisian & daftar nilai valid (mis. daftar kategori, kode cabang, role).
- **G-M3** — Alur impor 2 tahap: **(1) Validasi & Preview** — semua baris dicek (kolom wajib, SKU/kode unik, FK harus ada: kategori/cabang valid, format tanggal ED, role valid) dan hasilnya ditampilkan per baris (✔ valid / ✘ error + alasan) **tanpa menyentuh database**; **(2) Commit** — hanya bisa dijalankan jika 0 error, dieksekusi atomik dalam 1 transaksi.
- **G-M4** — Perilaku *upsert* berdasarkan kunci alami: `sku` (barang), `code` (cabang/ruangan), `email` (pengguna), `nama` (kategori), `item+batch_no` (batch) — baris berkunci sama meng-update data lama, kunci baru menambah; **tidak pernah menghapus**. Penghapusan tetap hanya lewat nonaktifkan (G-A4).
- **G-M5** — Impor tidak boleh mengubah kolom yang memengaruhi jejak transaksi historis (mis. mengganti SKU yang sudah dipakai movement) — baris seperti itu ditolak validasi.
- **G-M6** — Setiap impor dicatat di `import_logs` (file, jumlah baris masuk/update/gagal, siapa, kapan); file sumber disimpan untuk audit.
- **G-M7** — Perubahan master data via impor mengikuti aturan sync yang sama (G-Y): dibuat offline → `pending` → server memvalidasi ulang saat sinkronisasi.

### 3.11 Aturan Kadaluarsa (per item, dilacak per batch)

- **G-E1** — Barang `has_expiry = true` **wajib** memiliki `batch_no` + `expiry_date` saat barang masuk warehouse (inbound). Tanpa batch, penerimaan ditolak sistem.
- **G-E2** — Semua pergerakan barang ber-ED (DO, GR, distribusi, opname) tercatat **per batch**; saldo per lokasi dipecah per batch.
- **G-E3** — **FEFO (First-Expired-First-Out)**: saat warehouse membuat DO dan saat Kepala Cabang membuat distribusi, sistem otomatis menyarankan batch dengan ED terdekat lebih dulu. Memilih batch yang lebih muda dari saran FEFO memunculkan peringatan + catatan wajib.
- **G-E4** — Barang **sudah kedaluwarsa diblokir total** dari DO dan distribusi (transaksi ditolak). Warehouse juga tidak boleh mengirim barang dengan sisa umur < `expiry_alert_days` tanpa konfirmasi eksplisit.
- **G-E5** — Di Good Receipt, ED per batch tampil di tiap baris; barang kedaluwarsa / terlalu dekat ED ditolak dengan alasan `kedaluwarsa` (masuk daftar retur).
- **G-E6** — Peringatan otomatis di dashboard tiap role: badge **"Segera kedaluwarsa"** (sisa umur ≤ `expiry_alert_days`, oranye) dan **"Kedaluwarsa"** (merah) per lokasi sesuai cakupan RBAC.
- **G-E7** — Barang kedaluwarsa dikeluarkan dari stok hanya lewat movement `disposal` (pemusnahan) dengan catatan & pelaku — bukan dengan mengedit saldo.
- **G-E8** — Laporan **Kadaluarsa** (per lokasi, diurutkan ED terdekat, kolom: barang, batch, ED, sisa hari, qty) tersedia di modul Laporan dan bisa diunduh Excel/PDF.

---

## 4. Desain Frontend (Flutter)

### 4.1 Arsitektur Aplikasi

```
lib/
├── main.dart
├── app/                      # MaterialApp, tema, GoRouter, guard per-role
├── core/
│   ├── db/                   # Drift: tables, database.dart, DAO
│   ├── sync/                 # SyncService, queue, conflict handler
│   ├── auth/                 # Sesi, role, guard
│   └── widgets/              # Komponen bersama (AppScaffold, StatusChip, QtyStepper…)
└── features/
    ├── auth/                 # Login
    ├── dashboard/            # Beranda per role
    ├── opname/               # Stok opname (Perawat)
    ├── purchase_request/     # PR (Kepala Cabang)
    ├── delivery/             # DO / Surat Jalan (Warehouse)
    ├── good_receipt/         # GR ceklis (Kepala Cabang)
    ├── distribution/         # Distribusi ruangan (Kepala Cabang)
    ├── inventory/            # Stok per lokasi, kartu stok (ledger)
    ├── reports/              # Laporan + ekspor Excel (.xlsx) & PDF
    └── master/               # Master data + template import Excel (Super Admin)
```

- **State management:** Riverpod (stream Drift → UI reaktif).
- **Navigasi:** GoRouter dengan *route guard* per role.
- **Pola:** Repository di atas DAO Drift; use-case memvalidasi guardrails **sebelum** menulis DB.
- **Tema:** Material 3 — palet dasar **biru (primary), putih (background/surface), gold (aksen)**; mode terang default.

### 4.2 Peta Navigasi per Role

Setelah login, beranda & menu mengikuti role:

**Perawat** (bottom nav: Beranda · Opname · Stok · Profil)

| Layar | Isi |
|---|---|
| Beranda | Status opname minggu ini per ruangan (sudah/belum), pengingat, ringkasan stok menipis di ruangannya |
| Stok Opname — daftar | Riwayat opname ruangan; tombol **+ Opname Minggu Ini** (nonaktif jika sudah ada — G-O1) |
| Stok Opname — form | **CategoryFilterChips** (Semua / Bahan Tambal / Alat Sekali Pakai / Obat / APD…) + **SearchableDropdown** di atas daftar (cari barang per nama/SKU dalam kategori terpilih); perawat bisa menghitung per kelompok kategori; daftar barang: `stok sistem` vs input `hasil hitung` (QtyStepper), selisih otomatis ter-highlight, catatan wajib jika selisih ≠ 0, tombol **Simpan Draft** / **Kirim** |
| Stok Ruangan | Saldo stok ruangan real-time + kartu stok, filter per kategori |

**Kepala Cabang** (bottom nav: Beranda · PR · Penerimaan · Distribusi · Stok)

| Layar | Isi |
|---|---|
| Beranda | Kartu ringkas: opname masuk minggu ini (3 ruangan), PR aktif & statusnya, DO dalam perjalanan, GR menunggu ceklis, stok cabang menipis, **barang segera kedaluwarsa/kedaluwarsa** (G-E6) |
| Review Opname | Daftar opname `submitted` per ruangan → detail selisih → tombol **Review & Kunci** |
| Buat PR | Wizard 3 langkah: (1) pilih opname acuan → (2) tabel item dengan `suggested_qty` (bisa diedit, peringatan >150%) + **CategoryFilterChips** & **SearchableDropdown** untuk menyaring/mencari/menambah barang (dropdown menyaring seiring ketikan, mengikuti kategori terpilih) → (3) ringkasan & **Kirim ke Warehouse** (dikelompokkan per kategori) |
| Daftar PR | Filter status; timeline status per PR (submitted → processing → shipped → closed) |
| Good Receipt | Daftar DO `shipped` → layar ceklis: tiap baris menampilkan **batch & ED** (badge kadaluarsa), tombol **✔ Sesuai** / **✘ Tolak** (sheet alasan, termasuk `kedaluwarsa`), input `received_qty`, progress "8/12 diperiksa", tombol **Posting GR** aktif setelah semua diputuskan (G-G2) |
| Distribusi | Pilih ruangan tujuan (chip R1/R2/R3) → **CategoryFilterChips** + **SearchableDropdown** barang dari saldo Gudang Cabang (hanya barang bersaldo > 0 yang muncul, mengikuti kategori terpilih) → batch tersaran otomatis **FEFO** (ED terdekat dulu, G-E3) → qty → **Posting Distribusi** |
| Stok Cabang | Tab: Gudang Cabang · per Ruangan; filter per kategori; kartu stok & indikator di bawah minimum |
| Laporan | **SearchableDropdown** (cari jenis laporan / nama barang untuk kartu stok, menyaring seiring ketikan) + pilih lokasi (Gudang Cabang / R1 / R2 / R3 / semua) + rentang periode + **filter kategori barang** (opsional; tanpa filter, ekspor menampilkan subtotal per kategori — G-L6) → jenis laporan: Stok Saat Ini, Kartu Stok (mutasi), **Kadaluarsa (per batch, urut ED terdekat)**, Rekap Opname, Rekap Penerimaan (GR), Rekap Distribusi → tombol **Unduh Excel** / **Unduh PDF**, lalu bagikan (share sheet) |

**Warehouse** (bottom nav: Beranda · PR Masuk · Pengiriman · Stok WH)

| Layar | Isi |
|---|---|
| Beranda | PR baru masuk, DO disiapkan, laporan selisih GR dari cabang, stok warehouse menipis |
| PR Masuk | **SearchableDropdown** (cari nomor PR / nama cabang / barang, menyaring seiring ketikan) + daftar PR `submitted` semua cabang → detail → **Proses** / **Tolak** (wajib alasan) |
| Buat DO | Dari PR: isi `shipped_qty` per baris (maks = sisa `requested`, cek saldo WH — G-D2/G-D3), pilih batch dengan saran **FEFO** & blokir batch kedaluwarsa (G-E3/G-E4) → cetak/lihat Surat Jalan → **Kirim** |
| Stok Warehouse | Saldo per batch, filter per kategori, penerimaan barang masuk (inbound dari supplier — wajib isi batch & ED untuk barang ber-ED, G-E1), kartu stok, daftar kedaluwarsa & pemusnahan (`disposal`) |
| Retur | Daftar barang `rejected` dari GR cabang untuk ditindaklanjuti |
| Laporan | Stok warehouse pusat, rekap PR/DO per cabang & per periode, laporan selisih GR — semuanya bisa difilter per kategori (subtotal per kategori di ekspor) → **Unduh Excel** / **Unduh PDF** |

**Super Admin** (bottom nav: Beranda · Master · Import · Laporan)

| Layar | Isi |
|---|---|
| Beranda | Ringkasan lintas cabang: jumlah entitas master, aktivitas impor terakhir, alert stok & kadaluarsa semua lokasi |
| Master Data | Kartu per entitas dengan jumlah record: **Barang · Kategori · Cabang · Ruangan · Pengguna · Batch** → tiap kartu membuka daftar CRUD (tambah/edit/nonaktifkan — G-A4) dengan SearchableDropdown & filter kategori |
| Template Import | Per entitas: **⬇ Unduh Template Excel** (header + baris contoh + sheet petunjuk — G-M2) → **⬆ Upload File** → tabel preview validasi per baris (✔ valid / ✘ error + alasan — G-M3) → tombol **Commit Impor** (aktif hanya jika 0 error) → hasil tercatat di `import_logs` |
| Pengguna & Peran | Kelola akun, atur role & cabang, reset akses, nonaktifkan akun |
| Laporan | Semua laporan lintas cabang (superset laporan Warehouse & Kepala Cabang) + riwayat `export_logs`/`import_logs` |

### 4.3 Komponen UI Kunci

- **StatusChip** — warna konsisten: Draft (abu), Submitted (biru), Processing (ungu), Shipped (oranye), Checking (kuning), Posted/Closed/Reviewed (hijau), Rejected/Cancelled (merah).
- **QtyStepper** — input angka besar ramah jempol (− / angka / +) untuk opname & GR.
- **DocTimeline** — garis waktu status dokumen (siapa & kapan) di setiap detail dokumen.
- **ChecklistTile GR** — baris barang dengan swipe/tombol ✔/✘, badge selisih qty.
- **LowStockBadge** — indikator merah bila saldo < stok minimum.
- **ExpiryBadge** — badge tanggal kadaluarsa per batch dengan kode warna: merah = kedaluwarsa, oranye = sisa umur ≤ `expiry_alert_days`, abu = masih aman. Tampil di daftar stok, GR, distribusi, dan opname.
- **OfflineBanner** — banner kuning "Offline — perubahan akan disinkronkan" + ikon status sync per dokumen.
- **ExportButtons** — pasangan tombol **⬇ Excel** (hijau) / **⬇ PDF** (merah) yang konsisten di semua layar laporan; setelah file jadi, tampilkan share sheet (simpan/kirim WhatsApp/email) dan catat ke `export_logs`.
- **CategoryFilterChips** — deretan chip kategori barang (Semua · Bahan Tambal · Alat Sekali Pakai · Obat · APD · …) yang dapat digulir horizontal; dipakai di Stok Opname, Buat PR, Distribusi, semua layar stok, dan Laporan. Memilih chip menyaring daftar barang **dan** hasil SearchableDropdown; daftar kategori diambil dari `item_categories` (dinamis, dikelola Super Admin).
- **SearchableDropdown** — kolom pencarian dengan dropdown hasil yang **menyaring langsung mengikuti ketikan** (typeahead/autocomplete). Dipakai di: Stok Opname, Buat PR, Distribusi, PR Masuk (warehouse), dan Laporan. Perilaku: berbasis `Autocomplete`/`TypeAheadField` Flutter; debounce ±200 ms; query lokal Drift `LIKE %kata%` pada nama + SKU (case-insensitive, tetap jalan offline); bagian teks yang cocok di-highlight; maksimal ±8 hasil dengan scroll; pilihan langsung melompat/menambah baris terkait; tampilkan "Tidak ditemukan" bila kosong; di Distribusi hanya menampilkan barang bersaldo > 0, di PR Masuk mencari nomor PR/cabang/barang.

### 4.4 Alur Layar Utama (happy path)

```
Perawat:  Beranda → +Opname → isi hitung fisik → Kirim
Kacab:    Beranda → Review Opname → Buat PR (acuan opname) → Kirim ke Warehouse
Warehouse:PR Masuk → Proses → Buat DO → Kirim (stok WH berkurang)
Kacab:    Penerimaan → pilih DO → ceklis ✔/✘ per barang → Posting GR (stok cabang bertambah)
Kacab:    Distribusi → pilih R1/R2/R3 → pilih barang & qty → Posting (stok ruangan bertambah)
```

---

## 5. Tech Stack & Keputusan Teknis

| Aspek | Pilihan | Alasan |
|---|---|---|
| Framework | Flutter (Android, iOS, tablet) | Satu codebase untuk semua perangkat klinik |
| DB lokal | **Drift** (SQLite) | Reaktif (Stream), type-safe, transaksi ACID untuk posting stok |
| Sync backend | Supabase (Postgres + Auth + RLS) atau REST API | Multi-perangkat multi-role; RLS menegakkan RBAC di server |
| State | Riverpod | Integrasi natural dengan stream Drift |
| Router | GoRouter | Route guard per role |
| ID | UUID v4 di client | Aman untuk pembuatan dokumen offline |
| Ekspor Excel | package `excel` (atau `syncfusion_flutter_xlsio`) | Generate `.xlsx` lokal, tanpa server |
| Ekspor PDF | package `pdf` + `printing` | Generate `.pdf` lokal + preview/print/share sheet |
| Berbagi file | `share_plus` + `path_provider` | Simpan & bagikan hasil ekspor |
| Zona waktu | Simpan UTC, zona operasional **UTC+08:00 / GMT+8** (§6.1) | Konsistensi lintas cabang, bebas dari zona waktu perangkat |
| Kuantitas | Fixed-point INTEGER milli-unit, skala 1000 (§6.2) | Desimal (0.5, 1.25, 2.375) tanpa galat floating point |

### 5.1 Urutan Implementasi yang Disarankan (belum dikerjakan)

1. Skema Drift + seed master data (cabang, ruangan, barang, user).
2. Modul Stok & ledger (`stock_movements`, `stock_balances`) + validasi non-negatif + batch/kadaluarsa (`item_batches`, FEFO).
3. Fitur Stok Opname (Perawat) → 4. PR (Kepala Cabang) → 5. DO (Warehouse) → 6. GR ceklis → 7. Distribusi.
8. Dashboard per role. 9. Modul Laporan + ekspor Excel/PDF (`export_logs`). 10. Master Data & Template Import Super Admin (`import_logs`). 11. Sync service + auth backend. 12. Uji guardrails (unit test per aturan G-*).

---

## 6. Keputusan Operasional (Milestone 1.1)

Dua keputusan bisnis di bawah ini berlaku sebagai **aturan project untuk sekarang dan
seterusnya**, dan mengikat seluruh fitur berikutnya (Stok Opname, PR, DO, GR, Distribusi,
Laporan).

### 6.1 Zona Waktu Operasional

```
Operational timezone: UTC+08:00 / GMT+8
```

Keputusan ini **menggantikan asumsi zona waktu perangkat** dan mempertegas (bukan
mengganti) prinsip penyimpanan UTC untuk sinkronisasi.

**Aturan:**

- **T-1** — Seluruh timestamp persisten tetap disimpan dalam **UTC**: `created_at`,
  `updated_at`, `deleted_at`, timestamp movement, dan timestamp dokumen
  (`submitted_at`, `reviewed_at`, `shipped_at`, `posted_at`).
- **T-2** — Seluruh waktu yang **ditampilkan** kepada pengguna dikonversi ke UTC+08:00.
- **T-3** — Perhitungan tanggal operasional, "hari ini", minggu ISO, dan batas pergantian
  hari menggunakan UTC+08:00.
- **T-4** — Implementasi **tidak boleh bergantung pada zona waktu perangkat**. Pemanggilan
  `DateTime.toLocal()` dilarang pada jalur tampilan maupun perhitungan.
- **T-5** — Seluruh konversi berada di utility terpusat `lib/core/time/app_time_zone.dart`
  (`AppTimeZone`). Menyebar `.add(const Duration(hours: 8))` ke banyak file dilarang.
- **T-6** — Istilah kode yang dipakai adalah **operational time**, bukan *local time*, agar
  tidak tertukar dengan zona waktu perangkat.
- **T-7** — Clock tetap dapat di-inject pada service (`StockPostingService({clock})`) agar
  test deterministik. Test tidak boleh memakai waktu nyata.

**Mengapa UTC tetap dipakai untuk penyimpanan:**

- Sinkronisasi tetap konsisten lintas cabang dan perangkat.
- Data tidak tergantung zona waktu perangkat yang bisa salah setel.
- Backend tidak pernah menerima timestamp ambigu.
- Audit trail memiliki satu referensi waktu tunggal.

**GMT+8 hanya dipakai sebagai zona operasional untuk:** tampilan UI, input tanggal & waktu
pengguna, penentuan "hari ini", penentuan batch kedaluwarsa, periode laporan, minggu ISO
Stok Opname, filter berdasarkan tanggal, serta batas awal dan akhir hari.

**Civil date (`expiry_date`):**

- **T-8** — `expiry_date` bukan timestamp kejadian melainkan **tanggal kalender tanpa jam**
  (civil date / date-only), disimpan sebagai UTC midnight dan **tidak boleh bergeser** oleh
  konversi zona waktu. Tanggal `2026-07-29` harus tetap `2026-07-29` di penyimpanan,
  perbandingan, maupun tampilan.
- **T-9** — Konversi GMT+8 **tidak** boleh dipanggil pada `expiry_date`. Utility date-only
  ada di `lib/core/time/date_only.dart`.
- **T-10** — Batch berlaku **sampai akhir tanggal kedaluwarsa** menurut tanggal operasional
  GMT+8, dan ditolak mulai hari berikutnya:

  | `expiry_date` | Tanggal operasional | Hasil |
  |---|---|---|
  | 2026-07-29 | 2026-07-29 | masih valid |
  | 2026-07-29 | 2026-07-30 | kedaluwarsa |

**Format tampilan** (`lib/core/time/app_date_time_formatter.dart`, Bahasa Indonesia):
`dd MMM yyyy` · `dd MMM yyyy, HH:mm` · `HH:mm`. Setiap timestamp dipastikan UTC → dikonversi
lewat `AppTimeZone` → baru diformat. Label zona ditambahkan bila kejelasan dibutuhkan,
mis. `29 Jul 2026, 22:30 GMT+8`.

### 6.2 Kuantitas Desimal (Fixed-Point)

**Aturan:**

- **Q-1** — Semua kuantitas barang mendukung **maksimal 3 angka desimal**.
  Valid: `1`, `0.5`, `1.25`, `2.375`. Tidak valid: `-1`, `0.0001`, `NaN`, `Infinity`.
- **Q-2** — Kuantitas stok disimpan sebagai **fixed-point integer**, bukan floating point.
  Skala penyimpanan adalah **1000**:

  ```
  1 unit     = 1000 milli-units
  0.5 unit   = 500 milli-units
  1.25 unit  = 1250 milli-units
  2.375 unit = 2375 milli-units
  ```

- **Q-3** — Kolom kuantitas ledger memakai tipe SQLite **INTEGER** berisi milli-unit.
  **REAL dilarang** pada kolom kuantitas, dan `double` dilarang sebagai sumber kebenaran
  perhitungan saldo. Constraint tetap berlaku pada nilai terskala
  (`qty_on_hand >= 0`, `qty > 0`).
- **Q-4** — Value object terpusat `Quantity` (`lib/core/quantity/quantity.dart`) adalah
  satu-satunya representasi kuantitas di domain, repository, service, dan UI. DAO boleh
  memakai `int` milli-unit **hanya** pada boundary database; widget dan service tidak boleh
  mengetahui bahwa database memakai milli-unit.
- **Q-5** — Parser `Quantity.parse` menerima titik maupun koma sebagai pemisah desimal
  (`"0.5"` dan `"0,5"` sama-sama 500 milli-unit) dan **menolak** input kosong, negatif,
  bukan angka, `NaN`, `Infinity`, serta lebih dari 3 desimal. **Tidak ada pembulatan diam-diam**:
  input berdesimal lebih dari 3 menghasilkan validation error.
- **Q-6** — Formatter menghapus nol yang tidak diperlukan: `1000 → "1"`, `500 → "0.5"`,
  `1250 → "1.25"`, `2375 → "2.375"`. Bentuk `0.500` / `1.000` tidak ditampilkan kecuali
  diminta oleh laporan formal tertentu. Nilai milli-unit **tidak pernah** ditampilkan kepada
  pengguna.
- **Q-7** — Kuantitas umum tidak boleh negatif. Operasi pengurangan `Quantity` boleh
  menghasilkan nilai negatif secara internal (dipakai untuk selisih opname), tetapi input
  fisik dan movement tetap mengikuti business rule masing-masing (`qty > 0`,
  `qty_on_hand >= 0`).
- **Q-8** — Input UI memakai `TextInputType.numberWithOptions(decimal: true)` dengan
  formatter terpusat yang membatasi 3 desimal namun **tidak menghalangi** ketikan antara
  seperti `0.` atau `0,`. Validasi final dijalankan saat submit atau saat field kehilangan
  fokus, dengan pesan Bahasa Indonesia: *"Masukkan jumlah yang valid."*,
  *"Jumlah harus lebih dari 0."*, *"Maksimal 3 angka di belakang koma."*

**Field yang wajib memakai mekanisme ini** — sekarang dan pada seluruh fitur berikutnya:

```
qty              qty_on_hand      system_qty       counted_qty      difference
requested_qty    approved_qty     shipped_qty      received_qty     distributed_qty
```

**Catatan untuk Stok Opname (schema v3):** `system_qty`, `counted_qty`, dan `difference`
memakai `Quantity` dan disimpan sebagai INTEGER milli-unit. `difference` **dapat bernilai
negatif**. Input `counted_qty` oleh perawat harus menerima nilai desimal seperti `0.5`.

### 6.3 Versi Schema Database

| Versi | Cakupan |
|---|---|
| v1 | Skema awal Milestone 1 (kuantitas sebagai unit bulat) |
| **v2** | **Milestone 1.1** — kuantitas ledger menjadi fixed-point milli-unit |
| v3 | Stok Opname (`stock_opnames`, `stock_opname_lines`) — **belum dikerjakan** |

Migrasi v1 → v2 hanya menskalakan data (`× 1000`) pada `stock_balances.qty_on_hand` dan
`stock_movements.qty`; tipe kolom tetap INTEGER sehingga tidak ada rebuild tabel. Migrasi
dijalankan tepat satu kali, pada blok `if (from < 2)`. Stok Opname **wajib** memakai schema
v3, bukan menumpang v2.

---

*Aish Warehouse © Aish Tech Solution — dokumen spesifikasi v1.1, 29 Juli 2026.*
