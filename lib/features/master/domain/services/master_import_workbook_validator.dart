import '../../../../core/errors/failures.dart';
import '../models/import_models.dart';
import '../models/master_admin_models.dart';
import 'master_import_normalization_policy.dart';

/// Everything a workbook must satisfy *before* any row is looked at (§15).
///
/// ### Pure, and that is the point
///
/// Not one method here opens a file or touches a package. The parser under
/// `data/` reads cells; this decides whether what it read is acceptable. The split
/// means every refusal in §15 is testable against a list of strings, and the one
/// class that knows about OOXML has no business rules in it.
///
/// ### The order the checks run in is load-bearing
///
/// Extension, then size, then emptiness, then bytes, then sheets, then version,
/// then headers. Each one makes the next meaningful: there is no point reporting
/// a missing header on a `.csv`, and *"template version not supported"* on a file
/// with no *Petunjuk* sheet at all would be a worse message than *"sheet
/// missing"*. A caller that ran them in another order would produce messages that
/// are true and unhelpful.
abstract final class MasterImportWorkbookValidator {
  /// Sheet 1 — the data (§13).
  static const String dataSheetName = 'Data';

  /// Sheet 2 — instructions and valid-value lists (G-M2).
  static const String instructionsSheetName = 'Petunjuk';

  /// The *Petunjuk* cell that carries the template version, as a label the parser
  /// looks for in column A.
  static const String versionLabel = 'Versi template';

  /// Row 1 is the header, row 2 the sample; data starts at row 3.
  static const int headerRowNumber = 1;
  static const int sampleRowNumber = 2;
  static const int firstDataRowNumber = 3;

  // --- the file ---------------------------------------------------------------

  /// Refuses anything that is not an `.xlsx` by name (§15).
  ///
  /// By extension, before a byte is read. `.xlsm` is called out by name in the
  /// message because it is the one a user is most likely to have produced by
  /// accident — and the one this module least wants to open, since a
  /// macro-enabled workbook is a file that runs code when an auditor opens it.
  static void ensureSupportedExtension(PickedImportFile file) {
    final extension = file.extension;
    if (extension == MasterImportLimits.allowedExtension) return;
    throw ImportUnsupportedFileFailure(
      extension.isEmpty
          ? 'File tanpa ekstensi tidak didukung. Gunakan file .xlsx hasil '
                'unduhan template.'
          : 'Format $extension tidak didukung. Gunakan file .xlsx hasil '
                'unduhan template — .xls, .xlsm, dan .csv tidak dapat diimpor.',
      fileName: file.originalFileName,
      extension: extension.isEmpty ? null : extension,
    );
  }

  static void ensureWithinSizeLimit(PickedImportFile file) {
    if (file.sizeBytes == 0) {
      throw ImportFileEmptyFailure(
        'File yang dipilih kosong. Pastikan file template sudah terisi lalu '
        'coba lagi.',
        fileName: file.originalFileName,
      );
    }
    if (file.sizeBytes <= MasterImportLimits.maxFileBytes) return;
    throw ImportFileTooLargeFailure(
      'Ukuran file melebihi batas ${MasterImportLimits.maxFileSizeLabel}. '
      'Pecah data menjadi beberapa file lalu impor bergantian.',
      fileName: file.originalFileName,
      sizeBytes: file.sizeBytes,
      maxBytes: MasterImportLimits.maxFileBytes,
    );
  }

  /// Whether the bytes even begin like a ZIP, which every `.xlsx` is.
  ///
  /// Cheap, and it turns the most common real failure — a `.csv` or an `.xls`
  /// renamed to `.xlsx` — into a clear message instead of whatever the parser
  /// happens to throw three layers down.
  static bool looksLikeXlsx(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);

  static void ensureLooksLikeXlsx({
    required List<int> bytes,
    required String fileName,
  }) {
    if (looksLikeXlsx(bytes)) return;
    throw ImportWorkbookCorruptFailure(
      'File tidak dapat dibaca sebagai workbook Excel. Unduh template lagi, '
      'isi ulang, lalu simpan sebagai .xlsx.',
      fileName: fileName,
    );
  }

  // --- the sheets --------------------------------------------------------------

  static void ensureSheetsPresent(Iterable<String> sheetNames) {
    final names = sheetNames.toSet();
    for (final required in const [dataSheetName, instructionsSheetName]) {
      if (names.contains(required)) continue;
      throw ImportSheetMissingFailure(
        'Sheet "$required" tidak ditemukan. Gunakan file .xlsx hasil unduhan '
        'template tanpa mengubah nama sheet.',
        sheetName: required,
      );
    }
  }

  static void ensureSupportedTemplateVersion(String? found) {
    if (MasterTemplateVersion.isSupported(found)) return;
    throw ImportTemplateVersionFailure(
      found == null || found.trim().isEmpty
          ? 'Versi template tidak ditemukan pada sheet "$instructionsSheetName". '
                'Unduh template terbaru (${MasterTemplateVersion.current}) lalu '
                'isi ulang.'
          : 'Versi template "$found" tidak didukung. Unduh template terbaru '
                '(${MasterTemplateVersion.current}) lalu isi ulang.',
      expected: MasterTemplateVersion.current,
      found: found == null || found.trim().isEmpty ? null : found.trim(),
    );
  }

  // --- the header row -----------------------------------------------------------

  /// Refuses a header row that is not exactly this entity's, in order (§15).
  ///
  /// Four distinct mistakes, four distinct sentences, because the fix differs:
  /// a missing column means the template was edited, an unknown one means a column
  /// was added, a duplicate means a column was copied, and a reorder means the
  /// columns were dragged. Reporting all four as *"header tidak sesuai"* would
  /// leave the operator comparing two lists by eye.
  ///
  /// Order matters and is enforced. A workbook whose columns are the right *set*
  /// in the wrong order would import every value into the wrong field while
  /// passing every per-cell type check — the failure that is silent, and therefore
  /// the one worth being strict about.
  static void ensureHeadersMatch({
    required MasterEntityType entity,
    required List<String> found,
  }) {
    final expected = entity.headers;
    final trimmed = found
        .map((header) => header.trim())
        .where((header) => header.isNotEmpty)
        .toList(growable: false);

    final duplicates = <String>[];
    final seen = <String>{};
    for (final header in trimmed) {
      if (!seen.add(header)) duplicates.add(header);
    }
    if (duplicates.isNotEmpty) {
      throw ImportHeaderMismatchFailure(
        'Kolom ganda pada baris header: ${duplicates.toSet().join(', ')}. '
        'Setiap kolom hanya boleh muncul satu kali.',
        entity: entity,
        expected: expected,
        found: trimmed,
      );
    }

    final missing = expected.where((h) => !trimmed.contains(h)).toList();
    if (missing.isNotEmpty) {
      throw ImportHeaderMismatchFailure(
        'Kolom wajib tidak ditemukan: ${missing.join(', ')}. Unduh template '
        '${entity.label} lalu isi ulang tanpa mengubah baris header.',
        entity: entity,
        expected: expected,
        found: trimmed,
      );
    }

    final unknown = trimmed.where((h) => !expected.contains(h)).toList();
    if (unknown.isNotEmpty) {
      throw ImportHeaderMismatchFailure(
        'Kolom tidak dikenal: ${unknown.join(', ')}. Hapus kolom tambahan, '
        'atau unduh template ${entity.label} lalu isi ulang.',
        entity: entity,
        expected: expected,
        found: trimmed,
      );
    }

    for (var index = 0; index < expected.length; index++) {
      if (trimmed[index] == expected[index]) continue;
      throw ImportHeaderMismatchFailure(
        'Urutan kolom tidak sesuai template. Urutan yang benar: '
        '${expected.join(', ')}.',
        entity: entity,
        expected: expected,
        found: trimmed,
      );
    }
  }

  // --- the rows ------------------------------------------------------------------

  static void ensureWithinRowLimit(int rowCount) {
    if (rowCount <= MasterImportLimits.maxDataRows) return;
    throw ImportRowLimitFailure(
      'Jumlah baris data ($rowCount) melebihi batas '
      '${MasterImportLimits.maxDataRows}. Pecah data menjadi beberapa file '
      'lalu impor bergantian.',
      rowCount: rowCount,
      maxRows: MasterImportLimits.maxDataRows,
    );
  }

  static void ensureCellWithinLength({
    required int rowNumber,
    required String column,
    required String value,
  }) {
    if (value.length <= MasterImportLimits.maxCellCharacters) return;
    throw ImportRowLimitFailure(
      'Isi sel pada baris $rowNumber kolom "$column" terlalu panjang '
      '(${value.length} karakter, batas '
      '${MasterImportLimits.maxCellCharacters}).',
      rowCount: rowNumber,
      maxRows: MasterImportLimits.maxCellCharacters,
    );
  }

  /// Always throws. Declared `Never` so a caller can use it as the value of an
  /// expression — which is what lets the parser's `switch` handle the formula arm
  /// without an early return that would break its exhaustiveness.
  static Never rejectFormulaCell({
    required int rowNumber,
    required String column,
  }) {
    throw ImportFormulaCellFailure(
      'Baris $rowNumber kolom "$column" berisi rumus. Ganti rumus dengan '
      'nilai tetap (salin lalu tempel sebagai nilai) sebelum mengimpor.',
      rowNumber: rowNumber,
      column: column,
    );
  }

  /// Whether [row] is the template's untouched sample row (§3.7).
  ///
  /// Every natural-key column must still hold its sentinel. A row where one was
  /// replaced and the other was not is **not** the sample — it is a half-edited
  /// row, and skipping it would silently drop data the operator believes they
  /// imported. It goes through validation and fails there, loudly, which is the
  /// right outcome.
  static bool isSampleRow({
    required MasterEntityType entity,
    required ImportRawRow row,
  }) {
    final sentinels = entity.sampleSentinels;
    for (final entry in sentinels.entries) {
      if (row[entry.key].trim() != entry.value) return false;
    }
    return true;
  }
}
