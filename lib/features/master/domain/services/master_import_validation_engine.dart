import '../../../../core/enums/app_enums.dart';
import '../models/import_models.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';
import '../repositories/master_admin_repository.dart';
import 'master_historical_integrity_policy.dart';
import 'master_import_duplicate_detector.dart';
import 'master_import_normalization_policy.dart';
import 'master_import_row_normalizer.dart';
import 'master_user_role_policy.dart';

/// Everything the engine needs to know about the database, read once.
///
/// ### Why a snapshot rather than a repository
///
/// Two reasons, and the second is the one that matters. The first is speed: a
/// 3,000-row item file resolving its category per row would issue 3,000 queries,
/// where six bulk reads answer all of them (§58).
///
/// The second is that [MasterImportValidationEngine] has to run in two places —
/// at preview time, and again **inside the commit transaction** (§33) — and it
/// has to behave identically in both. A pure function over a snapshot does; a
/// class holding a repository would quietly read post-write state halfway through
/// a commit and start validating rows against the rows this same import just
/// inserted.
class MasterImportReferenceSnapshot {
  const MasterImportReferenceSnapshot({
    required this.actorId,
    this.branchesByCode = const {},
    this.roomsByKey = const {},
    this.usersByEmail = const {},
    this.categoriesByName = const {},
    this.itemsBySku = const {},
    this.batchesByKey = const {},
    this.itemUsage = const {},
    this.batchUsage = const {},
    this.batchCountsByItem = const {},
    this.archivedCategoryIds = const {},
    this.archivedBatchIds = const {},
    this.activeSuperAdminIds = const {},
  });

  /// Loads exactly the indexes [entity] needs, and nothing else.
  ///
  /// A branch import does not read every batch in the clinic group, and a
  /// category import reads one index. Loading the union would make the cheapest
  /// import as slow as the most expensive one.
  static Future<MasterImportReferenceSnapshot> load({
    required MasterAdminRepository repository,
    required MasterEntityType entity,
    required String actorId,
  }) async {
    switch (entity) {
      case MasterEntityType.branches:
        return MasterImportReferenceSnapshot(
          actorId: actorId,
          branchesByCode: await repository.branchesByCodeIndex(),
        );
      case MasterEntityType.rooms:
        return MasterImportReferenceSnapshot(
          actorId: actorId,
          branchesByCode: await repository.branchesByCodeIndex(),
          roomsByKey: await repository.roomsByBranchCodeIndex(),
        );
      case MasterEntityType.users:
        final users = await repository.usersByEmailIndex();
        return MasterImportReferenceSnapshot(
          actorId: actorId,
          branchesByCode: await repository.branchesByCodeIndex(),
          usersByEmail: users,
          activeSuperAdminIds: {
            for (final list in users.values)
              for (final user in list)
                if (user.role == UserRole.superAdmin && user.isActive) user.id,
          },
        );
      case MasterEntityType.itemCategories:
        final categories = await repository.categoriesByNameIndex();
        return MasterImportReferenceSnapshot(
          actorId: actorId,
          categoriesByName: categories,
          archivedCategoryIds: await _archivedCategoryIds(
            repository,
            categories,
          ),
        );
      case MasterEntityType.items:
        final items = await repository.itemsBySkuIndex();
        final itemIds = [
          for (final list in items.values)
            for (final item in list) item.id,
        ];
        final categories = await repository.categoriesByNameIndex();
        return MasterImportReferenceSnapshot(
          actorId: actorId,
          itemsBySku: items,
          categoriesByName: categories,
          itemUsage: await repository.usageForItems(itemIds),
          batchCountsByItem: await repository.batchCountsForItems(itemIds),
          archivedCategoryIds: await _archivedCategoryIds(
            repository,
            categories,
          ),
        );
      case MasterEntityType.itemBatches:
        final batches = await repository.batchesByItemAndNumberIndex();
        final batchIds = [
          for (final list in batches.values)
            for (final batch in list) batch.id,
        ];
        return MasterImportReferenceSnapshot(
          actorId: actorId,
          itemsBySku: await repository.itemsBySkuIndex(),
          batchesByKey: batches,
          batchUsage: await repository.usageForBatches(batchIds),
          archivedBatchIds: await _archivedBatchIds(repository, batches),
        );
    }
  }

  /// Which categories are archived.
  ///
  /// A separate read because [MasterCategory] carries no `deleted_at` — the
  /// operational model deliberately never exposed one, and widening it would
  /// change a type sixteen features already read. The admin list view has the
  /// flag, so it is asked there.
  static Future<Set<String>> _archivedCategoryIds(
    MasterAdminRepository repository,
    Map<String, List<MasterCategory>> _,
  ) async {
    final views = await repository.listCategories(
      const MasterListFilter(includeInactive: true),
    );
    return {
      for (final view in views)
        if (view.isArchived) view.category.id,
    };
  }

  static Future<Set<String>> _archivedBatchIds(
    MasterAdminRepository repository,
    Map<String, List<MasterBatch>> _,
  ) async {
    final views = await repository.listBatches(
      const MasterListFilter(includeInactive: true),
    );
    return {
      for (final view in views)
        if (view.isArchived) view.batch.id,
    };
  }

  final String actorId;
  final Map<String, List<MasterBranch>> branchesByCode;
  final Map<String, List<MasterRoom>> roomsByKey;
  final Map<String, List<MasterUser>> usersByEmail;
  final Map<String, List<MasterCategory>> categoriesByName;
  final Map<String, List<MasterItem>> itemsBySku;
  final Map<String, List<MasterBatch>> batchesByKey;
  final Map<String, MasterHistoricalUsage> itemUsage;
  final Map<String, MasterHistoricalUsage> batchUsage;
  final Map<String, int> batchCountsByItem;
  final Set<String> archivedCategoryIds;
  final Set<String> archivedBatchIds;
  final Set<String> activeSuperAdminIds;
}

/// The result of validating a whole workbook.
class MasterImportValidationResult {
  const MasterImportValidationResult({
    required this.previews,
    required this.plan,
    required this.summary,
    required this.issues,
  });

  final List<ImportRowPreview> previews;

  /// The rows a commit would apply — valid ones only.
  final List<ValidatedImportRow> plan;

  final ImportValidationSummary summary;

  /// Every issue, sorted (row, column, code).
  final List<ImportRowIssue> issues;
}

/// Applies §30's per-entity rules to a parsed workbook.
///
/// ### Pure, and total
///
/// No I/O, no clock, no repository. Given the same snapshot and the same rows it
/// produces byte-identical output, which is what lets the commit re-run it inside
/// the transaction and compare (§33), and what makes `error_detail` deterministic
/// (§32).
///
/// It **never early-exits**. Every row is checked even after the first one fails,
/// and every row is checked for every rule rather than for the first that trips —
/// an operator who has to discover one error per upload will upload eleven times
/// (§29).
///
/// ### Errors block, warnings do not
///
/// The distinction is §31's: an error means *this row cannot be applied*; a
/// warning means *this row will be applied and you should know something*. A
/// warning never contributes to `failed_rows` and never appears in
/// `error_detail`, because a column whose whole purpose is explaining failures
/// must not describe rows that succeeded.
abstract final class MasterImportValidationEngine {
  static MasterImportValidationResult validate({
    required MasterEntityType entity,
    required ImportWorkbook workbook,
    required MasterImportReferenceSnapshot snapshot,
  }) {
    // 1. Normalize every row. A row that fails here yields no typed value, so it
    //    takes no part in duplicate detection or the entity rules — but it still
    //    gets a preview row, and it still counts as one failure.
    final normalized = <int, ImportNormalizedRow>{};
    final issuesByRow = <int, List<ImportRowIssue>>{};
    final displayByRow = <int, Map<String, String>>{};
    final keyDisplayByRow = <int, String>{};

    for (final raw in workbook.rows) {
      displayByRow[raw.rowNumber] = MasterImportRowNormalizer.displayValues(
        entity: entity,
        raw: raw,
      );
      final result = MasterImportRowNormalizer.normalize(
        entity: entity,
        raw: raw,
      );
      final bucket = issuesByRow[raw.rowNumber] ??= <ImportRowIssue>[];
      bucket.addAll(result.issues);
      if (result.row != null) {
        normalized[raw.rowNumber] = result.row!;
        keyDisplayByRow[raw.rowNumber] = result.row!.naturalKeyDisplay;
      } else {
        // A row that could not be normalized has no natural key to show, so the
        // preview names its position instead of inventing one.
        keyDisplayByRow[raw.rowNumber] = 'Baris ${raw.rowNumber}';
      }
    }

    // 2. Duplicates inside the file (§17). Every involved row fails, and this
    //    runs before the entity rules so a duplicated key is not also reported as
    //    two conflicting updates of the same row.
    for (final issue in MasterImportDuplicateDetector.detect(
      entity: entity,
      rows: normalized.values,
    )) {
      (issuesByRow[issue.rowNumber] ??= <ImportRowIssue>[]).add(issue);
    }

    // 3. The entity's own rules, against the snapshot.
    final actions = <int, ImportRowAction>{};
    final existingIds = <int, String?>{};
    _applyEntityRules(
      entity: entity,
      normalized: normalized,
      snapshot: snapshot,
      issuesByRow: issuesByRow,
      actions: actions,
      existingIds: existingIds,
    );

    // 4. Assemble.
    final previews = <ImportRowPreview>[];
    final plan = <ValidatedImportRow>[];
    var inserted = 0;
    var updated = 0;
    var failed = 0;

    for (final raw in workbook.rows) {
      final rowIssues =
          (issuesByRow[raw.rowNumber] ?? const <ImportRowIssue>[]).toList()
            ..sort();
      final hasError = rowIssues.any((issue) => issue.isError);
      final action = hasError
          ? ImportRowAction.none
          : (actions[raw.rowNumber] ?? ImportRowAction.none);

      previews.add(
        ImportRowPreview(
          rowNumber: raw.rowNumber,
          naturalKeyDisplay: keyDisplayByRow[raw.rowNumber] ?? '-',
          action: action,
          issues: rowIssues,
          normalizedValues:
              displayByRow[raw.rowNumber] ?? const <String, String>{},
        ),
      );

      switch (action) {
        case ImportRowAction.insert:
          inserted++;
          plan.add(
            ValidatedImportRow(
              row: normalized[raw.rowNumber]!,
              action: ImportRowAction.insert,
            ),
          );
        case ImportRowAction.update:
          updated++;
          plan.add(
            ValidatedImportRow(
              row: normalized[raw.rowNumber]!,
              action: ImportRowAction.update,
              existingId: existingIds[raw.rowNumber],
            ),
          );
        case ImportRowAction.none:
          // One failure per row, however many issues it has (§31).
          failed++;
      }
    }

    final allIssues = <ImportRowIssue>[
      for (final bucket in issuesByRow.values) ...bucket,
    ]..sort();

    return MasterImportValidationResult(
      previews: previews,
      plan: plan,
      summary: ImportValidationSummary(
        totalRows: workbook.rows.length,
        insertedRows: inserted,
        updatedRows: updated,
        failedRows: failed,
      ),
      issues: allIssues,
    );
  }

  // --- dispatch ---------------------------------------------------------------

  static void _applyEntityRules({
    required MasterEntityType entity,
    required Map<int, ImportNormalizedRow> normalized,
    required MasterImportReferenceSnapshot snapshot,
    required Map<int, List<ImportRowIssue>> issuesByRow,
    required Map<int, ImportRowAction> actions,
    required Map<int, String?> existingIds,
  }) {
    switch (entity) {
      case MasterEntityType.branches:
        for (final entry in normalized.entries) {
          _branchRules(
            row: entry.value as BranchImportRow,
            snapshot: snapshot,
            issues: issuesByRow[entry.key] ??= <ImportRowIssue>[],
            actions: actions,
            existingIds: existingIds,
          );
        }
      case MasterEntityType.rooms:
        for (final entry in normalized.entries) {
          _roomRules(
            row: entry.value as RoomImportRow,
            snapshot: snapshot,
            issues: issuesByRow[entry.key] ??= <ImportRowIssue>[],
            actions: actions,
            existingIds: existingIds,
          );
        }
      case MasterEntityType.users:
        _userRules(
          rows: normalized,
          snapshot: snapshot,
          issuesByRow: issuesByRow,
          actions: actions,
          existingIds: existingIds,
        );
      case MasterEntityType.itemCategories:
        for (final entry in normalized.entries) {
          _categoryRules(
            row: entry.value as CategoryImportRow,
            snapshot: snapshot,
            issues: issuesByRow[entry.key] ??= <ImportRowIssue>[],
            actions: actions,
            existingIds: existingIds,
          );
        }
      case MasterEntityType.items:
        for (final entry in normalized.entries) {
          _itemRules(
            row: entry.value as ItemImportRow,
            snapshot: snapshot,
            issues: issuesByRow[entry.key] ??= <ImportRowIssue>[],
            actions: actions,
            existingIds: existingIds,
          );
        }
      case MasterEntityType.itemBatches:
        for (final entry in normalized.entries) {
          _batchRules(
            row: entry.value as ItemBatchImportRow,
            snapshot: snapshot,
            issues: issuesByRow[entry.key] ??= <ImportRowIssue>[],
            actions: actions,
            existingIds: existingIds,
          );
        }
    }
  }

  // --- shared helpers -----------------------------------------------------------

  /// Resolves a natural key to at most one stored row.
  ///
  /// Returns `null` and records an issue when **two or more** stored rows match
  /// case-insensitively (§17). Not a conflict to resolve by picking one:
  /// `DEN-0001` and `den-0001` are two rows with two histories, and choosing
  /// between them would rewrite whichever was not chosen into a duplicate.
  static T? _resolveUnique<T>({
    required List<T>? matches,
    required MasterEntityType entity,
    required int rowNumber,
    required String column,
    required String display,
    required List<ImportRowIssue> issues,
  }) {
    if (matches == null || matches.isEmpty) return null;
    if (matches.length == 1) return matches.first;
    issues.add(
      ImportRowIssue(
        rowNumber: rowNumber,
        column: column,
        code: ImportIssueCode.ambiguousNaturalKey,
        message:
            '${entity.naturalKeyLabel} "$display" cocok dengan '
            '${matches.length} data yang sudah ada (perbedaan huruf besar/'
            'kecil). Rapikan data lama lewat menu Master Data terlebih dahulu.',
      ),
    );
    return null;
  }

  static ImportRowIssue _notFound({
    required int rowNumber,
    required String column,
    required String value,
    required String label,
  }) => ImportRowIssue(
    rowNumber: rowNumber,
    column: column,
    code: ImportIssueCode.foreignKeyNotFound,
    message:
        '$label "$value" tidak ditemukan. Tambahkan lewat menu Master Data '
        'atau impor entitas tersebut terlebih dahulu.',
  );

  static ImportRowIssue _inactiveReference({
    required int rowNumber,
    required String column,
    required String value,
    required String label,
  }) => ImportRowIssue(
    rowNumber: rowNumber,
    column: column,
    code: ImportIssueCode.foreignKeyInactive,
    message:
        '$label "$value" sedang nonaktif, sehingga tidak dapat dipakai untuk '
        'data baru. Aktifkan kembali terlebih dahulu.',
  );

  static ImportRowIssue _updatesInactiveWarning({
    required int rowNumber,
    required String entityLabel,
  }) => ImportRowIssue.warning(
    rowNumber: rowNumber,
    column: 'is_active',
    code: ImportIssueCode.updatesInactive,
    message:
        '$entityLabel ini sedang nonaktif dan akan diperbarui tanpa '
        'diaktifkan kembali.',
  );

  static ImportRowIssue _historicalWarning({
    required int rowNumber,
    required MasterHistoricalUsage usage,
  }) => ImportRowIssue.warning(
    rowNumber: rowNumber,
    column: '',
    code: ImportIssueCode.hasHistoricalReferences,
    message:
        'Data ini sudah dipakai transaksi (${usage.describe()}). Hanya kolom '
        'yang aman yang akan diperbarui.',
  );

  // --- branches ------------------------------------------------------------------

  static void _branchRules({
    required BranchImportRow row,
    required MasterImportReferenceSnapshot snapshot,
    required List<ImportRowIssue> issues,
    required Map<int, ImportRowAction> actions,
    required Map<int, String?> existingIds,
  }) {
    final existing = _resolveUnique(
      matches: snapshot.branchesByCode[row.naturalKey],
      entity: MasterEntityType.branches,
      rowNumber: row.rowNumber,
      column: 'code',
      display: row.code,
      issues: issues,
    );
    if (issues.any((issue) => issue.isError)) return;

    if (existing == null) {
      actions[row.rowNumber] = ImportRowAction.insert;
      return;
    }

    // `code` is the key and cannot differ — the lookup matched on it. There is
    // therefore no natural-key mutation to refuse here; the refusal exists at the
    // CRUD layer, where a form *could* offer the field.
    actions[row.rowNumber] = ImportRowAction.update;
    existingIds[row.rowNumber] = existing.id;

    if (!existing.isActive && !row.isActive) {
      issues.add(
        _updatesInactiveWarning(
          rowNumber: row.rowNumber,
          entityLabel: 'Cabang',
        ),
      );
    }
    if (existing.isArchived) {
      issues.add(
        ImportRowIssue.warning(
          rowNumber: row.rowNumber,
          column: 'code',
          code: ImportIssueCode.restoresArchived,
          message:
              'Cabang "${row.code}" sedang diarsipkan. Impor akan memperbarui '
              'datanya tanpa memulihkan arsip; gunakan menu Master Data untuk '
              'memulihkan.',
        ),
      );
    }
  }

  // --- rooms -----------------------------------------------------------------------

  static void _roomRules({
    required RoomImportRow row,
    required MasterImportReferenceSnapshot snapshot,
    required List<ImportRowIssue> issues,
    required Map<int, ImportRowAction> actions,
    required Map<int, String?> existingIds,
  }) {
    final branchKey = MasterImportNormalizationPolicy.key(row.branchCode);
    final branch = _resolveUnique(
      matches: snapshot.branchesByCode[branchKey],
      entity: MasterEntityType.branches,
      rowNumber: row.rowNumber,
      column: 'branch_code',
      display: row.branchCode,
      issues: issues,
    );
    if (branch == null && !issues.any((i) => i.isError)) {
      issues.add(
        _notFound(
          rowNumber: row.rowNumber,
          column: 'branch_code',
          value: row.branchCode,
          label: 'Cabang',
        ),
      );
    }

    final existing = _resolveUnique(
      matches: snapshot.roomsByKey[row.naturalKey],
      entity: MasterEntityType.rooms,
      rowNumber: row.rowNumber,
      column: 'code',
      display: row.naturalKeyDisplay,
      issues: issues,
    );

    if (branch != null && existing == null && !branch.isActive) {
      // A *new* room in a deactivated branch would be unreachable the moment it
      // was created. An existing room in one is history, and updating its name is
      // harmless — hence the asymmetry.
      issues.add(
        _inactiveReference(
          rowNumber: row.rowNumber,
          column: 'branch_code',
          value: row.branchCode,
          label: 'Cabang',
        ),
      );
    }

    if (issues.any((issue) => issue.isError)) return;

    if (existing == null) {
      actions[row.rowNumber] = ImportRowAction.insert;
      return;
    }

    // The key is `branch_code + code`, so a row naming another branch is a
    // *different* key and lands as an insert rather than as a move. That is what
    // makes §20.4's "a room cannot change branch" true by construction here —
    // there is no expressible way for an import to move one.
    actions[row.rowNumber] = ImportRowAction.update;
    existingIds[row.rowNumber] = existing.id;

    if (!existing.isActive && !row.isActive) {
      issues.add(
        _updatesInactiveWarning(
          rowNumber: row.rowNumber,
          entityLabel: 'Ruangan',
        ),
      );
    }
  }

  // --- users --------------------------------------------------------------------------
  //
  // The only entity whose rules are not per-row: §21's last-Super-Admin safeguard
  // is a property of the *file as a whole*, because a workbook can demote two
  // administrators on two rows and neither row is wrong on its own.

  static void _userRules({
    required Map<int, ImportNormalizedRow> rows,
    required MasterImportReferenceSnapshot snapshot,
    required Map<int, List<ImportRowIssue>> issuesByRow,
    required Map<int, ImportRowAction> actions,
    required Map<int, String?> existingIds,
  }) {
    // Pass 1: per-row rules, and record what each row would do to the Super Admin
    // population.
    final demotedSuperAdminIds = <String, int>{};
    final promotedRowNumbers = <int>[];

    for (final entry in rows.entries) {
      final row = entry.value as UserImportRow;
      final issues = issuesByRow[entry.key] ??= <ImportRowIssue>[];

      final existing = _resolveUnique(
        matches: snapshot.usersByEmail[row.naturalKey],
        entity: MasterEntityType.users,
        rowNumber: row.rowNumber,
        column: 'email',
        display: row.email,
        issues: issues,
      );

      // The role/branch invariant (§21), applied identically to CRUD (§23).
      if (!MasterUserRolePolicy.isValidPair(
        role: row.role,
        branchId: row.branchCode,
      )) {
        issues.add(
          ImportRowIssue(
            rowNumber: row.rowNumber,
            column: 'branch_code',
            code: ImportIssueCode.roleBranchMismatch,
            message: MasterUserRolePolicy.branchRequirementLabel(row.role),
          ),
        );
      }

      MasterBranch? branch;
      if (row.branchCode != null) {
        final branchKey = MasterImportNormalizationPolicy.key(row.branchCode);
        branch = _resolveUnique(
          matches: snapshot.branchesByCode[branchKey],
          entity: MasterEntityType.branches,
          rowNumber: row.rowNumber,
          column: 'branch_code',
          display: row.branchCode!,
          issues: issues,
        );
        if (branch == null && !issues.any((i) => i.isError)) {
          issues.add(
            _notFound(
              rowNumber: row.rowNumber,
              column: 'branch_code',
              value: row.branchCode!,
              label: 'Cabang',
            ),
          );
        } else if (branch != null && !branch.isActive && existing == null) {
          issues.add(
            _inactiveReference(
              rowNumber: row.rowNumber,
              column: 'branch_code',
              value: row.branchCode!,
              label: 'Cabang',
            ),
          );
        }
      }

      // The self-lockout safeguards (§21). Matched on **id**, so an operator
      // cannot dodge the rule by retyping their own address in another case —
      // the email was lower-cased before the lookup.
      if (existing != null && existing.id == snapshot.actorId) {
        if (existing.isActive && !row.isActive) {
          issues.add(
            ImportRowIssue(
              rowNumber: row.rowNumber,
              column: 'is_active',
              code: ImportIssueCode.selfDeactivation,
              message:
                  'Baris ini menonaktifkan akun Anda sendiri. Minta Super '
                  'Admin lain melakukannya.',
            ),
          );
        }
        if (existing.role == UserRole.superAdmin &&
            row.role != UserRole.superAdmin) {
          issues.add(
            ImportRowIssue(
              rowNumber: row.rowNumber,
              column: 'role',
              code: ImportIssueCode.selfDeactivation,
              message:
                  'Baris ini melepas peran Super Admin dari akun Anda sendiri. '
                  'Minta Super Admin lain melakukannya.',
            ),
          );
        }
      }

      if (issues.any((issue) => issue.isError)) continue;

      if (existing == null) {
        actions[row.rowNumber] = ImportRowAction.insert;
        if (row.role == UserRole.superAdmin && row.isActive) {
          promotedRowNumbers.add(row.rowNumber);
        }
        continue;
      }

      actions[row.rowNumber] = ImportRowAction.update;
      existingIds[row.rowNumber] = existing.id;

      final wasActiveSuperAdmin =
          existing.role == UserRole.superAdmin && existing.isActive;
      final staysActiveSuperAdmin =
          row.role == UserRole.superAdmin && row.isActive;
      if (wasActiveSuperAdmin && !staysActiveSuperAdmin) {
        demotedSuperAdminIds[existing.id] = row.rowNumber;
      } else if (!wasActiveSuperAdmin && staysActiveSuperAdmin) {
        promotedRowNumbers.add(row.rowNumber);
      }

      if (existing.role != row.role) {
        issues.add(
          ImportRowIssue.warning(
            rowNumber: row.rowNumber,
            column: 'role',
            code: ImportIssueCode.roleChanged,
            message:
                'Peran berubah dari ${existing.role.label} menjadi '
                '${row.role.label}. Hak akses pengguna ini akan menyesuaikan.',
          ),
        );
      }
      if (!existing.isActive && !row.isActive) {
        issues.add(
          _updatesInactiveWarning(
            rowNumber: row.rowNumber,
            entityLabel: 'Pengguna',
          ),
        );
      }
    }

    // Pass 2: would the file as a whole leave nobody able to administer the
    // system? The remaining population is what the database has, minus what this
    // file demotes, plus what it promotes or creates.
    if (demotedSuperAdminIds.isEmpty) return;
    final remaining = snapshot.activeSuperAdminIds
        .where((id) => !demotedSuperAdminIds.containsKey(id))
        .length;
    if (remaining + promotedRowNumbers.length > 0) return;

    // Every demoting row is marked, not just the last one: which of them the
    // operator meant to keep is their decision, and picking one for them is the
    // last-row-wins mistake §17 already refuses in another form.
    for (final entry in demotedSuperAdminIds.entries) {
      final rowNumber = entry.value;
      (issuesByRow[rowNumber] ??= <ImportRowIssue>[]).add(
        ImportRowIssue(
          rowNumber: rowNumber,
          column: 'role',
          code: ImportIssueCode.lastSuperAdmin,
          message:
              'File ini menonaktifkan atau menurunkan seluruh Super Admin yang '
              'tersisa. Sisakan minimal satu Super Admin aktif.',
        ),
      );
      actions[rowNumber] = ImportRowAction.none;
    }
  }

  // --- categories ----------------------------------------------------------------------

  static void _categoryRules({
    required CategoryImportRow row,
    required MasterImportReferenceSnapshot snapshot,
    required List<ImportRowIssue> issues,
    required Map<int, ImportRowAction> actions,
    required Map<int, String?> existingIds,
  }) {
    final existing = _resolveUnique(
      matches: snapshot.categoriesByName[row.naturalKey],
      entity: MasterEntityType.itemCategories,
      rowNumber: row.rowNumber,
      column: 'name',
      display: row.name,
      issues: issues,
    );
    if (issues.any((issue) => issue.isError)) return;

    if (existing == null) {
      actions[row.rowNumber] = ImportRowAction.insert;
      return;
    }

    actions[row.rowNumber] = ImportRowAction.update;
    existingIds[row.rowNumber] = existing.id;

    // A category has no `is_active`, so restoring it *is* the update (§3.6). An
    // archived category whose name appears in a file is one the operator is
    // asking for back — and unlike a branch, there is nothing else the row could
    // mean, because `name` is the only column.
    if (snapshot.archivedCategoryIds.contains(existing.id)) {
      issues.add(
        ImportRowIssue.warning(
          rowNumber: row.rowNumber,
          column: 'name',
          code: ImportIssueCode.restoresArchived,
          message:
              'Kategori "${row.name}" sedang diarsipkan dan akan dipulihkan.',
        ),
      );
    }
  }

  // --- items ------------------------------------------------------------------------------

  static void _itemRules({
    required ItemImportRow row,
    required MasterImportReferenceSnapshot snapshot,
    required List<ImportRowIssue> issues,
    required Map<int, ImportRowAction> actions,
    required Map<int, String?> existingIds,
  }) {
    final categoryKey = MasterImportNormalizationPolicy.key(row.categoryName);
    final category = _resolveUnique(
      matches: snapshot.categoriesByName[categoryKey],
      entity: MasterEntityType.itemCategories,
      rowNumber: row.rowNumber,
      column: 'category_name',
      display: row.categoryName,
      issues: issues,
    );
    if (category == null && !issues.any((i) => i.isError)) {
      issues.add(
        _notFound(
          rowNumber: row.rowNumber,
          column: 'category_name',
          value: row.categoryName,
          label: 'Kategori',
        ),
      );
    }

    final existing = _resolveUnique(
      matches: snapshot.itemsBySku[row.naturalKey],
      entity: MasterEntityType.items,
      rowNumber: row.rowNumber,
      column: 'sku',
      display: row.sku,
      issues: issues,
    );

    if (category != null &&
        snapshot.archivedCategoryIds.contains(category.id) &&
        (existing == null || existing.categoryId != category.id)) {
      issues.add(
        _inactiveReference(
          rowNumber: row.rowNumber,
          column: 'category_name',
          value: row.categoryName,
          label: 'Kategori',
        ),
      );
    }

    if (issues.any((issue) => issue.isError)) return;

    if (existing == null) {
      actions[row.rowNumber] = ImportRowAction.insert;
      return;
    }

    // G-M5, through the same policy the CRUD form uses (§23). Every refusal is
    // reported, not just the first, so one upload surfaces all four.
    final usage =
        snapshot.itemUsage[existing.id] ?? const MasterHistoricalUsage.none();
    final batchCount = snapshot.batchCountsByItem[existing.id] ?? 0;
    final effectiveUsage = MasterHistoricalUsage(
      movements: usage.movements,
      balances: usage.balances,
      opnameLines: usage.opnameLines,
      purchaseRequestLines: usage.purchaseRequestLines,
      deliveryOrderLines: usage.deliveryOrderLines,
      goodReceiptLines: usage.goodReceiptLines,
      distributionLines: usage.distributionLines,
      disposalLines: usage.disposalLines,
      consumptionLines: usage.consumptionLines,
      goodsReturnLines: usage.goodsReturnLines,
      batches: batchCount,
    );

    final refusals = MasterHistoricalIntegrityPolicy.decideItemUpdate(
      current: existing,
      nextSku: existing.sku,
      nextCategoryId: category!.id,
      nextUnit: row.unit,
      nextHasExpiry: row.hasExpiry,
      usage: effectiveUsage,
    );
    for (final refusal in refusals) {
      issues.add(
        ImportRowIssue(
          rowNumber: row.rowNumber,
          column: switch (refusal.field) {
            'category_id' => 'category_name',
            final field? => field,
            _ => '',
          },
          code: ImportIssueCode.historicalFieldImmutable,
          message: refusal.reason!,
        ),
      );
    }

    if (refusals.isNotEmpty) return;

    actions[row.rowNumber] = ImportRowAction.update;
    existingIds[row.rowNumber] = existing.id;

    if (effectiveUsage.isUsed) {
      issues.add(
        _historicalWarning(rowNumber: row.rowNumber, usage: effectiveUsage),
      );
    }
    if (!existing.isActive && !row.isActive) {
      issues.add(
        _updatesInactiveWarning(
          rowNumber: row.rowNumber,
          entityLabel: 'Barang',
        ),
      );
    }
  }

  // --- batches --------------------------------------------------------------------------------

  static void _batchRules({
    required ItemBatchImportRow row,
    required MasterImportReferenceSnapshot snapshot,
    required List<ImportRowIssue> issues,
    required Map<int, ImportRowAction> actions,
    required Map<int, String?> existingIds,
  }) {
    final itemKey = MasterImportNormalizationPolicy.key(row.itemSku);
    final item = _resolveUnique(
      matches: snapshot.itemsBySku[itemKey],
      entity: MasterEntityType.items,
      rowNumber: row.rowNumber,
      column: 'item_sku',
      display: row.itemSku,
      issues: issues,
    );
    if (item == null && !issues.any((i) => i.isError)) {
      issues.add(
        _notFound(
          rowNumber: row.rowNumber,
          column: 'item_sku',
          value: row.itemSku,
          label: 'Barang',
        ),
      );
    }

    // A batch on a non-expiry item is a row the rest of the application cannot
    // interpret: G-E1 makes a batch mandatory on every movement of an expiry
    // item and forbids one otherwise, so `item_batches` for a `has_expiry = false`
    // item would be rows nothing may ever reference.
    if (item != null && !item.hasExpiry) {
      issues.add(
        ImportRowIssue(
          rowNumber: row.rowNumber,
          column: 'item_sku',
          code: ImportIssueCode.batchRequiresExpiryItem,
          message:
              'Barang "${row.itemSku}" tidak dilacak per batch '
              '(has_expiry = FALSE), sehingga tidak dapat memiliki batch. '
              'Ubah barang tersebut lebih dahulu bila memang ber-kedaluwarsa.',
        ),
      );
    }

    final existing = _resolveUnique(
      matches: snapshot.batchesByKey[row.naturalKey],
      entity: MasterEntityType.itemBatches,
      rowNumber: row.rowNumber,
      column: 'batch_no',
      display: row.naturalKeyDisplay,
      issues: issues,
    );

    if (issues.any((issue) => issue.isError)) return;

    if (existing == null) {
      actions[row.rowNumber] = ImportRowAction.insert;
      return;
    }

    final usage =
        snapshot.batchUsage[existing.id] ?? const MasterHistoricalUsage.none();

    // The key is `item_sku + batch_no`, so neither can be mutated by an import —
    // a different value is a different key. `expiry_date` is the one column that
    // could change, and G-M5 locks it once the batch has moved: every quantity in
    // the ledger was posted against a lot that expires on the stored date, and
    // rewriting it silently rewrites which of them were expired at the time.
    final refusals = MasterHistoricalIntegrityPolicy.decideBatchUpdate(
      current: existing,
      nextItemId: existing.itemId,
      nextBatchNo: existing.batchNo,
      nextExpiryDate: row.expiryDate,
      usage: usage,
    );
    for (final refusal in refusals) {
      issues.add(
        ImportRowIssue(
          rowNumber: row.rowNumber,
          column: refusal.field ?? '',
          code: ImportIssueCode.historicalFieldImmutable,
          message: refusal.reason!,
        ),
      );
    }
    if (refusals.isNotEmpty) return;

    actions[row.rowNumber] = ImportRowAction.update;
    existingIds[row.rowNumber] = existing.id;

    if (snapshot.archivedBatchIds.contains(existing.id)) {
      issues.add(
        ImportRowIssue.warning(
          rowNumber: row.rowNumber,
          column: 'batch_no',
          code: ImportIssueCode.restoresArchived,
          message:
              'Batch "${row.naturalKeyDisplay}" sedang diarsipkan dan akan '
              'dipulihkan.',
        ),
      );
    }
    if (usage.isUsed) {
      issues.add(_historicalWarning(rowNumber: row.rowNumber, usage: usage));
    }
  }
}
