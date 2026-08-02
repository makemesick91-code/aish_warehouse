# Trusted private Storage upload

Bucket `import-audit` dan `report-artifacts` tetap private dan tidak memiliki generic
client INSERT policy. Alur: authenticated RPC membuat intent lima menit dan path
server-side; Edge Function membuat signed upload token menggunakan service credential;
client mengunggah sekali; finalize Function mengunduh object lewat service boundary,
menghitung SHA-256 dari bytes, membaca MIME Storage, memeriksa ukuran/MIME/actor/expiry,
lalu RPC mencatat
metadata immutable.

Import hanya `.xlsx`, maksimal **10 MiB**, Super Admin, path
`import-audit/<import-id>/<sanitized-name>`. Report hanya PDF/XLSX, maksimal 20 MiB,
harus dimiliki actor export, path
`report-artifacts/<domain-user-id>/<export-id>/<sanitized-name>`. Tidak ada public URL,
overwrite, arbitrary bucket, atau arbitrary path. Service key tidak pernah dikirim atau
dicatat. Object invalid ditolak; orphan dapat dihapus oleh operator setelah intent expired.

Batas report-artifacts adalah policy terpisah sebesar **20 MiB**; nilainya tidak
diturunkan dari batas import. Edge Function memiliki hard ceiling **20 MiB** untuk
semua bucket. Finalize memeriksa ukuran metadata Storage dan `Blob.size` sebelum
membuat `ArrayBuffer`, sehingga object di atas ceiling ditolak sebelum pemrosesan
full-memory.

`request_id` membuat intent idempotent. Retry setelah finalize mengembalikan object yang
sama tanpa upload kedua. Source impor wajib finalized sebelum audit impor diterima; path
lokal perangkat tidak dikirim atau disimpan server. Retensi report remote opsional—audit
ekspor tetap sah bila artifact hanya disimpan/dibagikan lokal.
