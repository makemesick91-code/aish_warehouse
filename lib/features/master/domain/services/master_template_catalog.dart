import '../../../../core/time/app_date_time_formatter.dart';
import '../models/import_models.dart';
import '../models/master_admin_models.dart';
import 'master_import_normalization_policy.dart';

/// The dynamic value lists a template's *Petunjuk* sheet carries (G-M2).
///
/// Read from Drift at generation time, never cached across downloads: a template
/// whose category list is a week old teaches an operator to type a category that
/// no longer exists, and they will find out one upload later.
class MasterTemplateReferenceData {
  const MasterTemplateReferenceData({
    this.branchCodes = const [],
    this.categoryNames = const [],
    this.expiryItemSkus = const [],
  });

  final List<String> branchCodes;
  final List<String> categoryNames;

  /// SKUs of items with `has_expiry = true` — the only items a batch may name
  /// (§14.6). Listing every SKU here would invite exactly the row the validator
  /// then has to refuse.
  final List<String> expiryItemSkus;
}

/// Builds one [MasterTemplateDefinition] per entity (§13, §14).
///
/// ### Why the definition is data rather than code in the generator
///
/// The generator turns a definition into cells and knows nothing about branches
/// or roles; this catalogue knows the business meaning and nothing about `.xlsx`.
/// That split is what lets the template tests assert on *what the template says*
/// without opening a workbook, and lets the generator test assert on *how it says
/// it* without knowing what a room is.
///
/// ### The sample row is complete, and unimportable
///
/// G-M2 requires row 2 to be a filled example. §3.7 requires that example not to
/// be imported by accident. Both hold: every column carries a plausible value, and
/// the natural-key columns carry the sentinels [ImportEntity.sampleSentinels]
/// defines. The importer skips exactly one row, and only when its key still
/// matches — the moment somebody types over `__CONTOH_SKU__`, it is data.
abstract final class MasterTemplateCatalog {
  /// Builds the definition for [entity].
  ///
  /// [generatedAtUtc] is stamped into the *Petunjuk* sheet as an operational
  /// GMT+8 date (T-1), so an operator holding two downloads can tell which is
  /// which.
  static MasterTemplateDefinition definitionFor({
    required MasterEntityType entity,
    required DateTime generatedAtUtc,
    MasterTemplateReferenceData reference = const MasterTemplateReferenceData(),
  }) => MasterTemplateDefinition(
    entity: entity,
    version: MasterTemplateVersion.current,
    generatedAtUtc: generatedAtUtc,
    columns: _columnsFor(entity, reference),
    sampleRow: _sampleRowFor(entity),
    notes: _notesFor(entity),
  );

  static List<MasterTemplateColumnGuide> _columnsFor(
    MasterEntityType entity,
    MasterTemplateReferenceData reference,
  ) {
    bool required(String column) => entity.requiredHeaders.contains(column);

    MasterTemplateColumnGuide guide(
      String column,
      String meaning, {
      String? format,
      List<String> allowedValues = const [],
    }) => MasterTemplateColumnGuide(
      column: column,
      meaning: meaning,
      isRequired: required(column),
      format: format,
      allowedValues: allowedValues,
    );

    return switch (entity) {
      MasterEntityType.branches => [
        guide(
          'code',
          'Kode cabang. Kunci identitas — baris dengan kode yang sudah ada '
              'akan memperbarui data lama.',
          format: 'teks, contoh CAB-01',
        ),
        guide('name', 'Nama cabang.', format: 'teks'),
        guide('address', 'Alamat cabang. Boleh dikosongkan.', format: 'teks'),
        guide(
          'is_active',
          'Cabang aktif dapat dipilih pada dokumen baru.',
          format: MasterImportNormalizationPolicy.booleanFormatLabel,
          allowedValues: MasterImportNormalizationPolicy.canonicalBooleans,
        ),
      ],
      MasterEntityType.rooms => [
        guide(
          'branch_code',
          'Kode cabang tempat ruangan berada. Harus sudah ada di master '
              'cabang.',
          format: 'teks',
          allowedValues: reference.branchCodes,
        ),
        guide(
          'code',
          'Kode ruangan, unik di dalam satu cabang. Kunci identitas bersama '
              'branch_code.',
          format: 'teks, contoh R1',
        ),
        guide('name', 'Nama ruangan.', format: 'teks'),
        guide(
          'is_active',
          'Ruangan aktif dapat dipilih pada dokumen baru.',
          format: MasterImportNormalizationPolicy.booleanFormatLabel,
          allowedValues: MasterImportNormalizationPolicy.canonicalBooleans,
        ),
      ],
      MasterEntityType.users => [
        guide('full_name', 'Nama lengkap pengguna.', format: 'teks'),
        guide(
          'email',
          'Email pengguna. Kunci identitas, disimpan huruf kecil.',
          format: 'teks, contoh nama@klinik.id',
        ),
        guide(
          'role',
          'Peran pengguna.',
          format: 'salah satu nilai berikut',
          allowedValues: MasterImportNormalizationPolicy.allowedRoles,
        ),
        guide(
          'branch_code',
          'Wajib untuk perawat dan kepala_cabang; harus dikosongkan untuk '
              'warehouse dan super_admin.',
          format: 'teks',
          allowedValues: reference.branchCodes,
        ),
        guide(
          'is_active',
          'Pengguna nonaktif tidak dapat masuk ke aplikasi.',
          format: MasterImportNormalizationPolicy.booleanFormatLabel,
          allowedValues: MasterImportNormalizationPolicy.canonicalBooleans,
        ),
      ],
      MasterEntityType.itemCategories => [
        guide(
          'name',
          'Nama kategori. Kunci identitas — nama yang sudah ada akan '
              'memperbarui atau memulihkan kategori lama.',
          format: 'teks',
        ),
      ],
      MasterEntityType.items => [
        guide(
          'sku',
          'Kode barang. Kunci identitas dan tidak dapat diubah setelah '
              'dipakai transaksi.',
          format: 'teks, contoh DEN-0001',
        ),
        guide('name', 'Nama barang.', format: 'teks'),
        guide(
          'category_name',
          'Nama kategori barang. Harus sudah ada di master kategori.',
          format: 'teks',
          allowedValues: reference.categoryNames,
        ),
        guide(
          'unit',
          'Satuan barang, contoh pcs, box, botol. Tidak dapat diubah setelah '
              'dipakai transaksi.',
          format: 'teks',
        ),
        guide(
          'min_stock_room',
          'Stok minimum per ruangan.',
          format: MasterImportNormalizationPolicy.integerFormatLabel,
        ),
        guide(
          'min_stock_branch',
          'Stok minimum gudang cabang.',
          format: MasterImportNormalizationPolicy.integerFormatLabel,
        ),
        guide(
          'has_expiry',
          'TRUE bila barang dilacak per batch dan punya tanggal kedaluwarsa. '
              'Tidak dapat diubah setelah dipakai transaksi.',
          format: MasterImportNormalizationPolicy.booleanFormatLabel,
          allowedValues: MasterImportNormalizationPolicy.canonicalBooleans,
        ),
        guide(
          'expiry_alert_days',
          'Berapa hari sebelum kedaluwarsa barang mulai diperingatkan.',
          format: MasterImportNormalizationPolicy.integerFormatLabel,
        ),
        guide(
          'is_active',
          'Barang nonaktif tidak muncul di form baru.',
          format: MasterImportNormalizationPolicy.booleanFormatLabel,
          allowedValues: MasterImportNormalizationPolicy.canonicalBooleans,
        ),
      ],
      MasterEntityType.itemBatches => [
        guide(
          'item_sku',
          'SKU barang. Harus sudah ada dan harus barang dengan '
              'has_expiry = TRUE.',
          format: 'teks',
          allowedValues: reference.expiryItemSkus,
        ),
        guide(
          'batch_no',
          'Nomor batch/lot dari kemasan. Kunci identitas bersama item_sku.',
          format: 'teks',
        ),
        guide(
          'expiry_date',
          'Tanggal kedaluwarsa batch.',
          format: MasterImportNormalizationPolicy.dateFormatLabel,
        ),
      ],
    };
  }

  static Map<String, String> _sampleRowFor(MasterEntityType entity) {
    final sentinels = entity.sampleSentinels;
    final row = switch (entity) {
      MasterEntityType.branches => <String, String>{
        'code': sentinels['code']!,
        'name': 'Cabang Contoh',
        'address': 'Jl. Contoh No. 1',
        'is_active': 'TRUE',
      },
      MasterEntityType.rooms => <String, String>{
        'branch_code': sentinels['branch_code']!,
        'code': sentinels['code']!,
        'name': 'Ruang Dental Contoh',
        'is_active': 'TRUE',
      },
      MasterEntityType.users => <String, String>{
        'full_name': 'Nama Contoh',
        'email': sentinels['email']!,
        'role': 'perawat',
        'branch_code': 'CAB-01',
        'is_active': 'TRUE',
      },
      MasterEntityType.itemCategories => <String, String>{
        'name': sentinels['name']!,
      },
      MasterEntityType.items => <String, String>{
        'sku': sentinels['sku']!,
        'name': 'Barang Contoh',
        'category_name': 'Kategori Contoh',
        'unit': 'pcs',
        'min_stock_room': '5',
        'min_stock_branch': '20',
        'has_expiry': 'TRUE',
        'expiry_alert_days': '30',
        'is_active': 'TRUE',
      },
      MasterEntityType.itemBatches => <String, String>{
        'item_sku': sentinels['item_sku']!,
        'batch_no': sentinels['batch_no']!,
        'expiry_date': '2026-12-31',
      },
    };
    // Every header filled, asserted here rather than trusted: G-M2 asks for a
    // *filled* example row, and a column added to `headers` without a sample
    // value would otherwise ship a template with a hole in row 2.
    assert(
      entity.headers.every(row.containsKey),
      'Baris contoh ${entity.dbValue} tidak mengisi seluruh kolom.',
    );
    return row;
  }

  static List<String> _notesFor(MasterEntityType entity) => <String>[
    'Baris 1 adalah header dan tidak boleh diubah, dihapus, atau ditukar '
        'urutannya.',
    'Baris 2 adalah contoh. Ganti isinya dengan data Anda, atau hapus '
        'barisnya. Baris contoh yang belum diganti akan dilewati.',
    'Isi mulai baris 3. Baris kosong akan dilewati.',
    'Kunci identitas entitas ini: ${entity.naturalKeyLabel}. Baris dengan '
        'kunci yang sudah ada akan memperbarui data lama; kunci baru akan '
        'menambah data.',
    'Impor tidak pernah menghapus data. Untuk menonaktifkan, gunakan kolom '
        'is_active atau menu Master Data.',
    'Kunci identitas tidak dapat diubah lewat impor. Untuk mengganti kunci, '
        'buat data baru lalu nonaktifkan data lama.',
    'Kolom yang memengaruhi jejak transaksi historis (misalnya satuan atau '
        'kategori barang yang sudah dipakai) akan ditolak validasi.',
    'Jangan menggunakan rumus, makro, atau tautan ke file lain. Sel berisi '
        'rumus akan ditolak.',
    'Simpan file dalam format .xlsx. Format .xls, .xlsm, dan .csv tidak '
        'didukung.',
    'Impor hanya dapat dijalankan bila hasil validasi menunjukkan 0 baris '
        'gagal.',
    'Ukuran file maksimal ${MasterImportLimits.maxFileSizeLabel} dan maksimal '
        '${MasterImportLimits.maxDataRows} baris data.',
  ];

  /// The *Petunjuk* header block, as label/value pairs in a fixed order.
  static List<({String label, String value})> metadataRows(
    MasterTemplateDefinition definition,
  ) => <({String label, String value})>[
    (label: 'Entitas', value: definition.entity.label),
    (label: 'Tabel', value: definition.entity.dbValue),
    (label: 'Versi template', value: definition.version),
    (
      label: 'Dibuat',
      value: AppDateTimeFormatter.dateTimeWithZone(definition.generatedAtUtc),
    ),
    (label: 'Kunci identitas', value: definition.entity.naturalKeyLabel),
    (label: 'Kolom wajib', value: definition.entity.requiredHeaders.join(', ')),
    (
      label: 'Kolom opsional',
      value: definition.entity.optionalHeaders.isEmpty
          ? '(tidak ada)'
          : definition.entity.optionalHeaders.join(', '),
    ),
    (
      label: 'Format boolean',
      value: MasterImportNormalizationPolicy.booleanFormatLabel,
    ),
    (
      label: 'Format tanggal',
      value: MasterImportNormalizationPolicy.dateFormatLabel,
    ),
  ];
}
