/// The import domain, expressed as immutable values.
///
/// One rule runs through the whole file, and §18 states it: `Map<String, dynamic>`
/// is **not** a domain contract here. A map appears exactly once — inside
/// [ImportRawRow], at the parser boundary, where a workbook genuinely is a bag of
/// strings keyed by header — and is mapped into a typed row before any rule looks
/// at it. Everything downstream of normalization is a named type with named
/// fields, so a validator that forgets `expiry_alert_days` fails to compile rather
/// than reading `null` out of a map at runtime.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/enums/app_enums.dart';
import 'master_admin_models.dart';

// --- templates ---------------------------------------------------------------

/// The generation of template this build writes and reads (§13).
///
/// A stored string rather than a number, and it goes into the workbook, into
/// `import_logs.template_version` and into the filename. The importer refuses a
/// version it does not know instead of guessing that the columns still line up —
/// a v2 template with a reordered header would otherwise import every value into
/// the wrong field and pass every per-cell check while doing it.
abstract final class MasterTemplateVersion {
  static const String current = 'aish-master-v1';

  /// Versions this build can parse. Exactly one today; the list exists so adding
  /// a v2 does not mean dropping support for the files already on people's
  /// devices.
  static const Set<String> supported = {current};

  static bool isSupported(String? value) =>
      value != null && supported.contains(value.trim());
}

/// One row of the *Petunjuk* sheet: a column and what it means.
class MasterTemplateColumnGuide {
  const MasterTemplateColumnGuide({
    required this.column,
    required this.meaning,
    required this.isRequired,
    this.format,
    this.allowedValues = const [],
  });

  final String column;
  final String meaning;
  final bool isRequired;

  /// e.g. *"YYYY-MM-DD"*, *"TRUE atau FALSE"*, *"bilangan bulat >= 0"*.
  final String? format;

  /// The valid values, when the set is small and fixed (roles) or read from the
  /// database at generation time (branch codes, category names, item SKUs).
  final List<String> allowedValues;
}

/// Everything the generator needs to write one entity's workbook (§13, §14).
///
/// Built fresh on every download, because three of its lists come from Drift: a
/// template whose *Petunjuk* sheet lists last month's categories is a template
/// that teaches an operator to type a category that no longer exists.
class MasterTemplateDefinition {
  const MasterTemplateDefinition({
    required this.entity,
    required this.version,
    required this.generatedAtUtc,
    required this.columns,
    required this.sampleRow,
    required this.notes,
  });

  final MasterEntityType entity;
  final String version;
  final DateTime generatedAtUtc;
  final List<MasterTemplateColumnGuide> columns;

  /// Row 2 of the Data sheet, keyed by header. Every column filled (G-M2), with
  /// the natural-key columns carrying their sentinels (§3.7).
  final Map<String, String> sampleRow;

  /// The free-text warnings the *Petunjuk* sheet ends with.
  final List<String> notes;

  List<String> get headers => entity.headers;

  String get fileName => '${entity.templateFileStem}_$version.xlsx';
}

/// A generated template that has been written to disk and can be shared.
class MasterTemplateArtifact {
  const MasterTemplateArtifact({
    required this.entity,
    required this.version,
    required this.fileName,
    required this.path,
    required this.byteLength,
  });

  final MasterEntityType entity;
  final String version;

  /// The canonical §26 name — what the user sees in the share sheet.
  final String fileName;

  /// Absolute path on this device. **Never shown to a user** (§26).
  final String path;

  final int byteLength;
}

/// How a share sheet ended. A dismissal is not an error: the file exists.
enum MasterTemplateShareOutcome { shared, cancelled, unavailable }

// --- the picked file ---------------------------------------------------------

/// A file the operator chose, before anything has been validated about it (§27).
class PickedImportFile {
  const PickedImportFile({required this.originalFileName, required this.bytes});

  /// The name as the platform reported it. Not a path, and not sanitized yet —
  /// sanitizing happens when a copy is stored, and the raw name is what the audit
  /// row records so the operator recognises their own file.
  final String originalFileName;

  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  /// Lowercase, dot included, or `''` when the name has no extension.
  String get extension {
    final dot = originalFileName.lastIndexOf('.');
    if (dot < 0 || dot == originalFileName.length - 1) return '';
    return originalFileName.substring(dot).toLowerCase();
  }
}

/// The retained audit copy of a source file (G-M6, §28).
class ImportSourceFile {
  const ImportSourceFile({
    required this.importId,
    required this.fileName,
    required this.path,
    required this.sha256,
    required this.sizeBytes,
  });

  final String importId;

  /// The sanitized name the copy was written under.
  final String fileName;

  /// Absolute path under app documents. **Never rendered** (§36).
  final String path;

  /// Lowercase hex, 64 characters.
  final String sha256;

  final int sizeBytes;

  /// The first eight characters, which is what a detail screen shows. Enough for
  /// a human to compare two rows; not enough to be mistaken for the file itself.
  String get shortHash => sha256.substring(0, 8);
}

// --- the workbook ------------------------------------------------------------

/// One data row exactly as the parser read it: trimmed strings, keyed by header.
///
/// The **only** map in this file, and the boundary §18 permits it at. Nothing
/// downstream of [ImportNormalizedRow] ever sees one.
class ImportRawRow {
  const ImportRawRow({required this.rowNumber, required this.values});

  /// The spreadsheet row number the operator sees, 1-based, header included. The
  /// first data row is 3 — row 1 is the header and row 2 the sample.
  final int rowNumber;

  final Map<String, String> values;

  String operator [](String column) => values[column] ?? '';

  bool get isBlank => values.values.every((value) => value.isEmpty);
}

/// A parsed workbook: the sheets checked, the version read, the rows collected.
class ImportWorkbook {
  const ImportWorkbook({
    required this.entity,
    required this.templateVersion,
    required this.headers,
    required this.rows,
    required this.blankRowCount,
    required this.sampleRowSkipped,
  });

  final MasterEntityType entity;
  final String templateVersion;

  /// Row 1, in file order. Already checked against `entity.headers`.
  final List<String> headers;

  /// Every non-blank data row except the untouched sample row.
  final List<ImportRawRow> rows;

  final int blankRowCount;

  /// Whether a row carrying the template's sentinels was found and skipped
  /// (§3.7). At most one ever is.
  final bool sampleRowSkipped;

  int get rowCount => rows.length;
}

// --- normalized rows ---------------------------------------------------------

/// What a normalized row of any entity has in common.
///
/// [naturalKey] is the *comparison* key — normalized, case-folded where the rule
/// says so — and [naturalKeyDisplay] is what a person reads. They differ for
/// exactly the reason the ambiguity rule exists: `DEN-0001` and `den-0001` share
/// a comparison key and are two different display strings.
sealed class ImportNormalizedRow {
  const ImportNormalizedRow({
    required this.rowNumber,
    required this.naturalKey,
    required this.naturalKeyDisplay,
  });

  final int rowNumber;
  final String naturalKey;
  final String naturalKeyDisplay;
}

class BranchImportRow extends ImportNormalizedRow {
  const BranchImportRow({
    required super.rowNumber,
    required super.naturalKey,
    required super.naturalKeyDisplay,
    required this.code,
    required this.name,
    this.address,
    required this.isActive,
  });

  final String code;
  final String name;
  final String? address;
  final bool isActive;
}

class RoomImportRow extends ImportNormalizedRow {
  const RoomImportRow({
    required super.rowNumber,
    required super.naturalKey,
    required super.naturalKeyDisplay,
    required this.branchCode,
    required this.code,
    required this.name,
    required this.isActive,
  });

  final String branchCode;
  final String code;
  final String name;
  final bool isActive;
}

class UserImportRow extends ImportNormalizedRow {
  const UserImportRow({
    required super.rowNumber,
    required super.naturalKey,
    required super.naturalKeyDisplay,
    required this.fullName,
    required this.email,
    required this.role,
    this.branchCode,
    required this.isActive,
  });

  final String fullName;

  /// Already lower-cased (§16) — the natural key and the stored value are the
  /// same string, so an account cannot be created twice under two spellings.
  final String email;

  final UserRole role;

  /// `null` for `warehouse` and `super_admin`, required for the other two (§21).
  final String? branchCode;

  final bool isActive;
}

class CategoryImportRow extends ImportNormalizedRow {
  const CategoryImportRow({
    required super.rowNumber,
    required super.naturalKey,
    required super.naturalKeyDisplay,
    required this.name,
  });

  /// The display spelling, preserved verbatim (§16). Only the comparison key is
  /// case-folded.
  final String name;
}

class ItemImportRow extends ImportNormalizedRow {
  const ItemImportRow({
    required super.rowNumber,
    required super.naturalKey,
    required super.naturalKeyDisplay,
    required this.sku,
    required this.name,
    required this.categoryName,
    required this.unit,
    required this.minStockRoom,
    required this.minStockBranch,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.isActive,
  });

  final String sku;
  final String name;
  final String categoryName;
  final String unit;
  final int minStockRoom;
  final int minStockBranch;
  final bool hasExpiry;
  final int expiryAlertDays;
  final bool isActive;
}

class ItemBatchImportRow extends ImportNormalizedRow {
  const ItemBatchImportRow({
    required super.rowNumber,
    required super.naturalKey,
    required super.naturalKeyDisplay,
    required this.itemSku,
    required this.batchNo,
    required this.expiryDate,
  });

  final String itemSku;
  final String batchNo;

  /// A civil date at UTC midnight (T-8). Never converted.
  final DateTime expiryDate;
}

// --- issues ------------------------------------------------------------------

/// Machine-readable issue codes (§32).
///
/// Stored in `import_logs.error_detail`, so they are part of the audit record and
/// may not be renamed casually: a code written last month has to still mean what
/// the row said it meant.
abstract final class ImportIssueCode {
  static const String requiredMissing = 'required_missing';
  static const String invalidBoolean = 'invalid_boolean';
  static const String invalidInteger = 'invalid_integer';
  static const String invalidDate = 'invalid_date';
  static const String invalidRole = 'invalid_role';
  static const String invalidEmail = 'invalid_email';
  static const String valueTooLong = 'value_too_long';
  static const String duplicateNaturalKey = 'duplicate_natural_key';
  static const String ambiguousNaturalKey = 'ambiguous_natural_key';
  static const String foreignKeyNotFound = 'foreign_key_not_found';
  static const String foreignKeyInactive = 'foreign_key_inactive';
  static const String roleBranchMismatch = 'role_branch_mismatch';
  static const String historicalFieldImmutable = 'historical_field_immutable';
  static const String naturalKeyImmutable = 'natural_key_immutable';
  static const String batchRequiresExpiryItem = 'batch_requires_expiry_item';
  static const String expiryFlagHasBatches = 'expiry_flag_has_batches';
  static const String lastSuperAdmin = 'last_super_admin';
  static const String selfDeactivation = 'self_deactivation';
  static const String stockLocationIntegrity = 'stock_location_integrity';

  // Warnings — never block a commit (§31).
  static const String updatesInactive = 'updates_inactive';
  static const String restoresArchived = 'restores_archived';
  static const String hasHistoricalReferences = 'has_historical_references';
  static const String roleChanged = 'role_changed';
}

/// Whether an issue refuses a row or only annotates it (§31).
enum ImportIssueSeverity { error, warning }

/// One problem with one cell of one row (§32).
class ImportRowIssue implements Comparable<ImportRowIssue> {
  const ImportRowIssue({
    required this.rowNumber,
    required this.column,
    required this.code,
    required this.message,
    this.severity = ImportIssueSeverity.error,
  });

  const ImportRowIssue.warning({
    required this.rowNumber,
    required this.column,
    required this.code,
    required this.message,
  }) : severity = ImportIssueSeverity.warning;

  final int rowNumber;

  /// The header this is about, or `''` for a row-level issue that belongs to no
  /// single column.
  final String column;

  final String code;

  /// Indonesian, written for the operator, and **never** carrying a path, a table
  /// name or an exception string (§32, §45).
  final String message;

  final ImportIssueSeverity severity;

  bool get isError => severity == ImportIssueSeverity.error;

  bool get isWarning => severity == ImportIssueSeverity.warning;

  /// Row, then column, then code — the deterministic order §32 requires, so two
  /// validations of the same file produce byte-identical `error_detail`.
  @override
  int compareTo(ImportRowIssue other) {
    final byRow = rowNumber.compareTo(other.rowNumber);
    if (byRow != 0) return byRow;
    final byColumn = column.compareTo(other.column);
    if (byColumn != 0) return byColumn;
    return code.compareTo(other.code);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'row': rowNumber,
    'column': column,
    'code': code,
    'message': message,
  };
}

/// Serializes issues into `import_logs.error_detail` (§32).
abstract final class ImportErrorDetail {
  /// A JSON array, sorted by (row, column, code).
  ///
  /// **Errors only.** Warnings are shown on the preview and are not a reason the
  /// import failed, so recording them in a column whose whole purpose is
  /// explaining `failed_rows` would make the audit say a row failed when it did
  /// not.
  ///
  /// Returns `null` when there is nothing to record, which is what lets the
  /// column stay NULL on a clean import.
  static String? encode(Iterable<ImportRowIssue> issues) {
    final errors = issues.where((issue) => issue.isError).toList()..sort();
    if (errors.isEmpty) return null;
    return jsonEncode(
      errors.map((issue) => issue.toJson()).toList(growable: false),
    );
  }

  /// Reads the column back for the detail screen. Returns an empty list on
  /// anything unparseable rather than throwing — a malformed audit row is still
  /// an audit row, and refusing to render it would hide the import entirely.
  static List<ImportRowIssue> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(
            (entry) => ImportRowIssue(
              rowNumber: entry['row'] is int ? entry['row']! as int : 0,
              column: entry['column'] as String? ?? '',
              code: entry['code'] as String? ?? '',
              message: entry['message'] as String? ?? '',
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

// --- preview -----------------------------------------------------------------

/// What committing this row would do (§31).
enum ImportRowAction {
  insert,
  update,

  /// The row is invalid, so it would do nothing at all. Distinct from
  /// `insert`/`update` because a preview must not claim a failed row was "going
  /// to be an insert" — it was going to be nothing.
  none;

  String get label => switch (this) {
    insert => 'Tambah',
    update => 'Perbarui',
    none => 'Gagal',
  };
}

/// One row as the preview table renders it (§18).
class ImportRowPreview {
  const ImportRowPreview({
    required this.rowNumber,
    required this.naturalKeyDisplay,
    required this.action,
    required this.issues,
    required this.normalizedValues,
  });

  final int rowNumber;
  final String naturalKeyDisplay;
  final ImportRowAction action;
  final List<ImportRowIssue> issues;

  /// The normalized cell values, keyed by header, for the expanded row view.
  ///
  /// A map here is deliberate and is not the §18 violation it looks like: this is
  /// *presentation* — a table renders columns it was told about at runtime — and
  /// nothing decides anything from it. Every rule reads the typed row.
  final Map<String, String> normalizedValues;

  List<ImportRowIssue> get errors =>
      issues.where((issue) => issue.isError).toList(growable: false);

  List<ImportRowIssue> get warnings =>
      issues.where((issue) => issue.isWarning).toList(growable: false);

  bool get isValid => action != ImportRowAction.none && errors.isEmpty;
}

/// The four numbers above the preview table, and the invariant between them.
class ImportValidationSummary {
  const ImportValidationSummary({
    required this.totalRows,
    required this.insertedRows,
    required this.updatedRows,
    required this.failedRows,
  });

  /// Data rows the workbook held. Blank rows and the sample row are not rows
  /// (§15), so they are counted in neither this nor the three below.
  final int totalRows;

  final int insertedRows;
  final int updatedRows;

  /// Rows with at least one error. **Per row**, however many issues it has
  /// (§31) — a row with four problems is one failure, not four.
  final int failedRows;

  bool get hasErrors => failedRows > 0;

  bool get isEmpty => totalRows == 0;

  /// G-M3: a commit needs zero errors *and* something to do.
  bool get canCommit => totalRows > 0 && failedRows == 0;

  /// §31's invariant, asserted where anything can read it.
  bool get isConsistent => totalRows == insertedRows + updatedRows + failedRows;
}

/// The result of a preview: an audit row exists, no master row moved (§29).
class ImportPreviewSession {
  const ImportPreviewSession({
    required this.importId,
    required this.entity,
    required this.fileName,
    required this.templateVersion,
    required this.summary,
    required this.rows,
    required this.issues,
    required this.sourceFile,
    required this.validatedAtUtc,
  });

  final String importId;
  final MasterEntityType entity;
  final String fileName;
  final String templateVersion;
  final ImportValidationSummary summary;
  final List<ImportRowPreview> rows;

  /// Every issue across every row, already sorted.
  final List<ImportRowIssue> issues;

  final ImportSourceFile sourceFile;
  final DateTime validatedAtUtc;

  bool get canCommit => summary.canCommit;
}

/// A revalidated plan, built inside the commit transaction and never from the UI
/// (§33).
class ValidatedImportPlan {
  const ValidatedImportPlan({
    required this.entity,
    required this.rows,
    required this.summary,
  });

  final MasterEntityType entity;

  /// Typed rows, each already decided as an insert or an update against the
  /// database as it is **right now**.
  final List<ValidatedImportRow> rows;

  final ImportValidationSummary summary;
}

/// One row of a [ValidatedImportPlan].
class ValidatedImportRow {
  const ValidatedImportRow({
    required this.row,
    required this.action,
    this.existingId,
  });

  final ImportNormalizedRow row;
  final ImportRowAction action;

  /// The id of the row being updated, or `null` on an insert. Resolved inside the
  /// transaction — a preview's id is a fact about a moment that has passed.
  final String? existingId;
}

/// What a commit actually did (§33).
class ImportCommitResult {
  const ImportCommitResult({
    required this.importId,
    required this.entity,
    required this.insertedRows,
    required this.updatedRows,
    required this.committedAtUtc,
  });

  final String importId;
  final MasterEntityType entity;

  /// The **actual** counts from the transaction, not the preview's prediction.
  /// They normally match; when they do not, the audit records what happened.
  final int insertedRows;
  final int updatedRows;

  final DateTime committedAtUtc;

  int get totalRows => insertedRows + updatedRows;
}

// --- audit -------------------------------------------------------------------

/// One `import_logs` row, in domain terms.
class ImportLog {
  const ImportLog({
    required this.id,
    required this.entity,
    required this.fileName,
    required this.totalRows,
    required this.insertedRows,
    required this.updatedRows,
    required this.failedRows,
    this.errorDetail,
    required this.status,
    required this.importedBy,
    required this.templateVersion,
    required this.fileSha256,
    required this.fileSizeBytes,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.syncStatus,
  });

  final String id;
  final MasterEntityType entity;
  final String fileName;
  final int totalRows;
  final int insertedRows;
  final int updatedRows;
  final int failedRows;
  final String? errorDetail;
  final ImportStatus status;
  final String importedBy;
  final String templateVersion;
  final String fileSha256;
  final int fileSizeBytes;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final SyncStatus syncStatus;

  /// **`stored_file_path` is deliberately absent.** The audit row in the database
  /// has it, because the commit needs somewhere to read the bytes back from; the
  /// domain model a screen receives does not, so no view can render it even by
  /// accident (§36).
  String get shortHash => fileSha256.substring(0, 8);

  List<ImportRowIssue> get issues => ImportErrorDetail.decode(errorDetail);
}

/// One import as the detail screen shows it (§36).
class ImportLogDetail {
  const ImportLogDetail({
    required this.log,
    required this.importedByName,
    required this.importedByEmail,
  });

  final ImportLog log;
  final String importedByName;
  final String importedByEmail;

  /// The one sentence §36 requires the screen to say about the source file —
  /// which is a statement that it is retained, never a path to it.
  static const String sourceFileNotice = 'File sumber tersimpan untuk audit.';
}

/// What the history list is filtered by (§36).
class ImportHistoryFilter {
  const ImportHistoryFilter({
    this.entity,
    this.status,
    this.importedBy,
    this.fromDateUtc,
    this.toDateUtc,
    this.fileNameQuery = '',
    this.syncStatus,
  });

  final MasterEntityType? entity;
  final ImportStatus? status;
  final String? importedBy;

  /// Civil-date bounds compared against `created_at` as **instants**, never as
  /// text: §36 refuses lexical timestamp comparison for the reason schema v4
  /// removed one from `stock_opnames`.
  final DateTime? fromDateUtc;
  final DateTime? toDateUtc;

  final String fileNameQuery;
  final SyncStatus? syncStatus;

  bool get isEmpty =>
      entity == null &&
      status == null &&
      importedBy == null &&
      fromDateUtc == null &&
      toDateUtc == null &&
      fileNameQuery.trim().isEmpty &&
      syncStatus == null;

  ImportHistoryFilter copyWith({
    MasterEntityType? entity,
    bool clearEntity = false,
    ImportStatus? status,
    bool clearStatus = false,
    String? importedBy,
    bool clearImportedBy = false,
    DateTime? fromDateUtc,
    bool clearFrom = false,
    DateTime? toDateUtc,
    bool clearTo = false,
    String? fileNameQuery,
    SyncStatus? syncStatus,
    bool clearSyncStatus = false,
  }) => ImportHistoryFilter(
    entity: clearEntity ? null : (entity ?? this.entity),
    status: clearStatus ? null : (status ?? this.status),
    importedBy: clearImportedBy ? null : (importedBy ?? this.importedBy),
    fromDateUtc: clearFrom ? null : (fromDateUtc ?? this.fromDateUtc),
    toDateUtc: clearTo ? null : (toDateUtc ?? this.toDateUtc),
    fileNameQuery: fileNameQuery ?? this.fileNameQuery,
    syncStatus: clearSyncStatus ? null : (syncStatus ?? this.syncStatus),
  );
}
