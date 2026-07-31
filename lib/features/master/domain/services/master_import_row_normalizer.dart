import '../models/import_models.dart';
import '../models/master_admin_models.dart';
import 'master_import_normalization_policy.dart';

/// One raw row, turned into a typed row or into the reasons it could not be
/// (§16, §18).
///
/// ### Never throws, always collects
///
/// Every method here returns a result carrying *every* problem it found, and none
/// of them raises. That is §29's *"do not early-exit on row error"* expressed at
/// the level it matters most: an operator whose file has a bad date in column C
/// and a bad boolean in column I needs to see both, or they will fix one, upload
/// again, and discover the other.
///
/// A row that produced any issue yields no typed value. Half-built domain objects
/// are how a validator ends up reasoning about a `null` it decided to tolerate.
class ImportRowNormalizationResult<T extends ImportNormalizedRow> {
  const ImportRowNormalizationResult.success(this.row) : issues = const [];

  const ImportRowNormalizationResult.failed(this.issues) : row = null;

  /// The typed row, or `null` when [issues] is non-empty.
  final T? row;

  final List<ImportRowIssue> issues;

  bool get isValid => row != null;
}

/// Turns [ImportRawRow]s into the six typed row classes.
///
/// The **only** place a `Map<String, String>` becomes a domain object. Everything
/// downstream reads named fields, so a rule that forgets a column does not
/// compile (§18).
abstract final class MasterImportRowNormalizer {
  /// Dispatches to the per-entity normalizer.
  static ImportRowNormalizationResult<ImportNormalizedRow> normalize({
    required MasterEntityType entity,
    required ImportRawRow raw,
  }) => switch (entity) {
    MasterEntityType.branches => branch(raw),
    MasterEntityType.rooms => room(raw),
    MasterEntityType.users => user(raw),
    MasterEntityType.itemCategories => category(raw),
    MasterEntityType.items => item(raw),
    MasterEntityType.itemBatches => batch(raw),
  };

  // --- shared cell readers ----------------------------------------------------
  //
  // Each appends to `issues` and returns a fallback, so a caller reads every cell
  // unconditionally and inspects `issues` once at the end. Returning early would
  // reintroduce exactly the one-error-per-upload behaviour §29 forbids.

  static String _required(
    ImportRawRow raw,
    String column,
    List<ImportRowIssue> issues,
  ) {
    final value = MasterImportNormalizationPolicy.text(raw[column]);
    if (value.isEmpty) {
      issues.add(
        ImportRowIssue(
          rowNumber: raw.rowNumber,
          column: column,
          code: ImportIssueCode.requiredMissing,
          message: 'Kolom "$column" wajib diisi.',
        ),
      );
    }
    return value;
  }

  static String? _optional(ImportRawRow raw, String column) =>
      MasterImportNormalizationPolicy.optionalText(raw[column]);

  static bool _boolean(
    ImportRawRow raw,
    String column,
    List<ImportRowIssue> issues,
  ) {
    final text = MasterImportNormalizationPolicy.text(raw[column]);
    final value = MasterImportNormalizationPolicy.boolean(text);
    if (value != null) return value;
    issues.add(
      ImportRowIssue(
        rowNumber: raw.rowNumber,
        column: column,
        code: text.isEmpty
            ? ImportIssueCode.requiredMissing
            : ImportIssueCode.invalidBoolean,
        message: text.isEmpty
            ? 'Kolom "$column" wajib diisi dengan '
                  '${MasterImportNormalizationPolicy.booleanFormatLabel}.'
            : 'Nilai "$text" pada kolom "$column" tidak valid. Gunakan '
                  '${MasterImportNormalizationPolicy.booleanFormatLabel}.',
      ),
    );
    // The fallback is never used: `issues` is non-empty, so no typed row is
    // built. It exists so the reader can keep its non-nullable return type and
    // the caller can keep reading the remaining cells.
    return false;
  }

  static int _integer(
    ImportRawRow raw,
    String column,
    List<ImportRowIssue> issues,
  ) {
    final text = MasterImportNormalizationPolicy.text(raw[column]);
    final value = MasterImportNormalizationPolicy.nonNegativeInteger(text);
    if (value != null) return value;
    issues.add(
      ImportRowIssue(
        rowNumber: raw.rowNumber,
        column: column,
        code: text.isEmpty
            ? ImportIssueCode.requiredMissing
            : ImportIssueCode.invalidInteger,
        message: text.isEmpty
            ? 'Kolom "$column" wajib diisi dengan '
                  '${MasterImportNormalizationPolicy.integerFormatLabel}.'
            : 'Nilai "$text" pada kolom "$column" bukan '
                  '${MasterImportNormalizationPolicy.integerFormatLabel}.',
      ),
    );
    return 0;
  }

  /// Refuses a value a spreadsheet turned into a number.
  ///
  /// Identifier columns are written as text by the generator, so `007` and
  /// `1000000000000` survive a round trip. A file rebuilt by hand can still hand
  /// back `1E+12`, and importing that as a SKU would create an item whose code
  /// nobody typed and no label carries.
  static void _rejectMangledIdentifier(
    ImportRawRow raw,
    String column,
    String value,
    List<ImportRowIssue> issues,
  ) {
    if (value.isEmpty) return;
    if (!MasterImportNormalizationPolicy.looksLikeMangledNumber(value)) return;
    issues.add(
      ImportRowIssue(
        rowNumber: raw.rowNumber,
        column: column,
        code: ImportIssueCode.valueTooLong,
        message:
            'Nilai "$value" pada kolom "$column" terbaca sebagai angka '
            'ilmiah. Format kolom ini sebagai teks di Excel lalu isi ulang '
            'agar kode tidak berubah.',
      ),
    );
  }

  // --- branches ----------------------------------------------------------------

  static ImportRowNormalizationResult<BranchImportRow> branch(
    ImportRawRow raw,
  ) {
    final issues = <ImportRowIssue>[];
    final code = _required(raw, 'code', issues);
    _rejectMangledIdentifier(raw, 'code', code, issues);
    final name = _required(raw, 'name', issues);
    final address = _optional(raw, 'address');
    final isActive = _boolean(raw, 'is_active', issues);

    if (issues.isNotEmpty) {
      return ImportRowNormalizationResult<BranchImportRow>.failed(issues);
    }
    return ImportRowNormalizationResult<BranchImportRow>.success(
      BranchImportRow(
        rowNumber: raw.rowNumber,
        naturalKey: MasterImportNormalizationPolicy.key(code),
        naturalKeyDisplay: code,
        code: code,
        name: name,
        address: address,
        isActive: isActive,
      ),
    );
  }

  // --- rooms -------------------------------------------------------------------

  static ImportRowNormalizationResult<RoomImportRow> room(ImportRawRow raw) {
    final issues = <ImportRowIssue>[];
    final branchCode = _required(raw, 'branch_code', issues);
    _rejectMangledIdentifier(raw, 'branch_code', branchCode, issues);
    final code = _required(raw, 'code', issues);
    _rejectMangledIdentifier(raw, 'code', code, issues);
    final name = _required(raw, 'name', issues);
    final isActive = _boolean(raw, 'is_active', issues);

    if (issues.isNotEmpty) {
      return ImportRowNormalizationResult<RoomImportRow>.failed(issues);
    }
    return ImportRowNormalizationResult<RoomImportRow>.success(
      RoomImportRow(
        rowNumber: raw.rowNumber,
        // `branch_code + code`, not `code` alone — §3.1. The schema allows `R1`
        // in every branch, so a global key would make one branch's import
        // silently rewrite another's rooms.
        naturalKey: MasterImportNormalizationPolicy.compositeKey([
          branchCode,
          code,
        ]),
        naturalKeyDisplay: '$branchCode / $code',
        branchCode: branchCode,
        code: code,
        name: name,
        isActive: isActive,
      ),
    );
  }

  // --- users -------------------------------------------------------------------

  static ImportRowNormalizationResult<UserImportRow> user(ImportRawRow raw) {
    final issues = <ImportRowIssue>[];
    final fullName = _required(raw, 'full_name', issues);

    final rawEmail = MasterImportNormalizationPolicy.text(raw['email']);
    final email = MasterImportNormalizationPolicy.email(rawEmail);
    if (email.isEmpty) {
      issues.add(
        ImportRowIssue(
          rowNumber: raw.rowNumber,
          column: 'email',
          code: ImportIssueCode.requiredMissing,
          message: 'Kolom "email" wajib diisi.',
        ),
      );
    } else if (!MasterImportNormalizationPolicy.isValidEmail(email)) {
      issues.add(
        ImportRowIssue(
          rowNumber: raw.rowNumber,
          column: 'email',
          code: ImportIssueCode.invalidEmail,
          message:
              'Email "$rawEmail" tidak valid. Gunakan format '
              'nama@domain.',
        ),
      );
    }

    final rawRole = MasterImportNormalizationPolicy.text(raw['role']);
    final role = MasterImportNormalizationPolicy.role(rawRole);
    if (role == null) {
      issues.add(
        ImportRowIssue(
          rowNumber: raw.rowNumber,
          column: 'role',
          code: rawRole.isEmpty
              ? ImportIssueCode.requiredMissing
              : ImportIssueCode.invalidRole,
          message: rawRole.isEmpty
              ? 'Kolom "role" wajib diisi dengan salah satu: '
                    '${MasterImportNormalizationPolicy.allowedRoles.join(', ')}.'
              : 'Peran "$rawRole" tidak dikenal. Gunakan salah satu: '
                    '${MasterImportNormalizationPolicy.allowedRoles.join(', ')}.',
        ),
      );
    }

    final branchCode = _optional(raw, 'branch_code');
    if (branchCode != null) {
      _rejectMangledIdentifier(raw, 'branch_code', branchCode, issues);
    }
    final isActive = _boolean(raw, 'is_active', issues);

    if (issues.isNotEmpty) {
      return ImportRowNormalizationResult<UserImportRow>.failed(issues);
    }
    return ImportRowNormalizationResult<UserImportRow>.success(
      UserImportRow(
        rowNumber: raw.rowNumber,
        // Already lower-cased, so the key and the stored value are one string —
        // an account cannot be created twice under two spellings (§16).
        naturalKey: email,
        naturalKeyDisplay: email,
        fullName: fullName,
        email: email,
        role: role!,
        branchCode: branchCode,
        isActive: isActive,
      ),
    );
  }

  // --- categories --------------------------------------------------------------

  static ImportRowNormalizationResult<CategoryImportRow> category(
    ImportRawRow raw,
  ) {
    final issues = <ImportRowIssue>[];
    final name = _required(raw, 'name', issues);

    if (issues.isNotEmpty) {
      return ImportRowNormalizationResult<CategoryImportRow>.failed(issues);
    }
    return ImportRowNormalizationResult<CategoryImportRow>.success(
      CategoryImportRow(
        rowNumber: raw.rowNumber,
        naturalKey: MasterImportNormalizationPolicy.key(name),
        naturalKeyDisplay: name,
        // Display spelling preserved verbatim — only the key is case-folded, so
        // *Bahan Tambal* stays capitalised on screen while matching an existing
        // *bahan tambal* (§16).
        name: name,
      ),
    );
  }

  // --- items -------------------------------------------------------------------

  static ImportRowNormalizationResult<ItemImportRow> item(ImportRawRow raw) {
    final issues = <ImportRowIssue>[];
    final sku = _required(raw, 'sku', issues);
    _rejectMangledIdentifier(raw, 'sku', sku, issues);
    final name = _required(raw, 'name', issues);
    final categoryName = _required(raw, 'category_name', issues);
    final unit = _required(raw, 'unit', issues);
    final minStockRoom = _integer(raw, 'min_stock_room', issues);
    final minStockBranch = _integer(raw, 'min_stock_branch', issues);
    final hasExpiry = _boolean(raw, 'has_expiry', issues);
    final expiryAlertDays = _integer(raw, 'expiry_alert_days', issues);
    final isActive = _boolean(raw, 'is_active', issues);

    if (issues.isNotEmpty) {
      return ImportRowNormalizationResult<ItemImportRow>.failed(issues);
    }
    return ImportRowNormalizationResult<ItemImportRow>.success(
      ItemImportRow(
        rowNumber: raw.rowNumber,
        naturalKey: MasterImportNormalizationPolicy.key(sku),
        naturalKeyDisplay: sku,
        sku: sku,
        name: name,
        categoryName: categoryName,
        unit: unit,
        minStockRoom: minStockRoom,
        minStockBranch: minStockBranch,
        hasExpiry: hasExpiry,
        expiryAlertDays: expiryAlertDays,
        isActive: isActive,
      ),
    );
  }

  // --- batches -----------------------------------------------------------------

  static ImportRowNormalizationResult<ItemBatchImportRow> batch(
    ImportRawRow raw,
  ) {
    final issues = <ImportRowIssue>[];
    final itemSku = _required(raw, 'item_sku', issues);
    _rejectMangledIdentifier(raw, 'item_sku', itemSku, issues);
    final batchNo = _required(raw, 'batch_no', issues);
    _rejectMangledIdentifier(raw, 'batch_no', batchNo, issues);

    final rawExpiry = MasterImportNormalizationPolicy.text(raw['expiry_date']);
    final expiryDate = MasterImportNormalizationPolicy.isoDate(rawExpiry);
    if (expiryDate == null) {
      issues.add(
        ImportRowIssue(
          rowNumber: raw.rowNumber,
          column: 'expiry_date',
          code: rawExpiry.isEmpty
              ? ImportIssueCode.requiredMissing
              : ImportIssueCode.invalidDate,
          message: rawExpiry.isEmpty
              ? 'Kolom "expiry_date" wajib diisi dengan format '
                    '${MasterImportNormalizationPolicy.dateFormatLabel}.'
              : 'Tanggal "$rawExpiry" tidak valid. Gunakan format '
                    '${MasterImportNormalizationPolicy.dateFormatLabel}.',
        ),
      );
    }

    if (issues.isNotEmpty) {
      return ImportRowNormalizationResult<ItemBatchImportRow>.failed(issues);
    }
    return ImportRowNormalizationResult<ItemBatchImportRow>.success(
      ItemBatchImportRow(
        rowNumber: raw.rowNumber,
        naturalKey: MasterImportNormalizationPolicy.compositeKey([
          itemSku,
          batchNo,
        ]),
        naturalKeyDisplay: '$itemSku / $batchNo',
        itemSku: itemSku,
        batchNo: batchNo,
        // A past date is **not** an error here. A batch is master history: an
        // expired lot that is still on a shelf has to be recordable so a
        // Pemusnahan can destroy it (G-E7). What refuses an expired batch is the
        // *outbound* movement, which is a different rule in a different module.
        expiryDate: expiryDate!,
      ),
    );
  }

  /// The normalized values a preview row shows, keyed by header.
  ///
  /// Presentation only — nothing decides anything from this map (§18).
  static Map<String, String> displayValues({
    required MasterEntityType entity,
    required ImportRawRow raw,
  }) => <String, String>{
    for (final header in entity.headers)
      header: MasterImportNormalizationPolicy.text(raw[header]),
  };
}
