import '../../../../core/enums/app_enums.dart';
import '../models/import_models.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';

/// Everything the Super Admin section reads and writes, expressed in domain
/// terms (§24).
///
/// ### Why this is separate from `MasterDataRepository`
///
/// The operational repository serves every role: it lists *active* items, *active*
/// rooms, and the locations a document posts against. Widening it to also return
/// archived rows, historical usage counts and unrestricted user lists would put a
/// Super Admin-only read one method call away from every screen in the
/// application, and the sixteen existing features would each have to be trusted
/// not to call it.
///
/// This interface is the unrestricted one, and it is reached only through Super
/// Admin-guarded providers and use cases. Splitting them is the cheapest way to
/// make "who may read the whole user list" a question with one answer.
///
/// ### What is deliberately absent
///
/// * **No hard delete**, of anything (G-A4/G-A5).
/// * **No generic `update(table, columns)`** and no raw-map upsert. Every writer
///   here is typed and named, so a caller cannot construct an update the policies
///   never saw.
/// * **No stock or ledger writer.** An import may not create a balance or a
///   movement (§57); the only stock rows it touches are the `stock_locations` a
///   new branch or room must have (§22), and those go through named methods.
/// * **No import-log delete or status reversal.** [transitionImportStatus] moves
///   `validated` forward and nothing moves it back (§3.4).
abstract interface class MasterAdminRepository {
  // --- dashboard -------------------------------------------------------------

  Future<MasterAdminDashboard> dashboard();

  Future<MasterEntitySummary> summaryFor(MasterEntityType entity);

  // --- lists -----------------------------------------------------------------
  //
  // Every list takes a filter and returns admin views carrying the counts and
  // usage the screens show. `includeInactive` defaults to false on the filter,
  // so the unrestricted read is the one a caller has to ask for explicitly.

  Future<List<MasterBranchAdminView>> listBranches(MasterListFilter filter);

  Future<List<MasterRoomAdminView>> listRooms(MasterListFilter filter);

  Future<List<MasterUserAdminView>> listUsers(
    MasterListFilter filter, {
    String? actorId,
  });

  Future<List<MasterCategoryAdminView>> listCategories(MasterListFilter filter);

  Future<List<MasterItemAdminView>> listItems(MasterListFilter filter);

  Future<List<MasterBatchAdminView>> listBatches(MasterListFilter filter);

  // --- single rows, archived included ----------------------------------------
  //
  // `…ById` here means *whatever the database has*, soft-deleted rows included —
  // the opposite default from `MasterDataRepository.activeRoomById`. An
  // administration screen that could not open an archived row could not restore
  // it.

  Future<MasterBranch?> branchById(String id);

  Future<MasterRoom?> roomById(String id);

  Future<MasterUser?> adminUserById(String id);

  Future<MasterCategory?> categoryById(String id);

  Future<MasterItem?> itemById(String id);

  Future<MasterBatch?> batchById(String id);

  // --- natural-key lookup ----------------------------------------------------
  //
  // Case-insensitive, and each returns a **list** rather than a row. That is what
  // lets §17's ambiguity rule exist: two stored rows matching one key
  // case-insensitively is a state a back-office or a sync payload can produce, and
  // an import that picked one of them would rewrite the other into a duplicate.
  // A `getSingleOrNull` would throw a driver error instead of letting the caller
  // say so.

  Future<List<MasterBranch>> branchesByCode(String code);

  Future<List<MasterRoom>> roomsByBranchAndCode({
    required String branchId,
    required String code,
  });

  Future<List<MasterUser>> usersByEmail(String email);

  Future<List<MasterCategory>> categoriesByName(String name);

  Future<List<MasterItem>> itemsBySku(String sku);

  Future<List<MasterBatch>> batchesByItemAndNumber({
    required String itemId,
    required String batchNo,
  });

  /// Every branch, archived included, keyed by lower-cased code.
  ///
  /// Bulk lookups exist because an import resolves the same handful of foreign
  /// keys for thousands of rows, and a per-row query would make a 10,000-row file
  /// 10,000 round trips (§58).
  Future<Map<String, List<MasterBranch>>> branchesByCodeIndex();

  Future<Map<String, List<MasterCategory>>> categoriesByNameIndex();

  Future<Map<String, List<MasterItem>>> itemsBySkuIndex();

  Future<Map<String, List<MasterUser>>> usersByEmailIndex();

  Future<Map<String, List<MasterRoom>>> roomsByBranchCodeIndex();

  Future<Map<String, List<MasterBatch>>> batchesByItemAndNumberIndex();

  // --- historical usage ------------------------------------------------------

  Future<MasterHistoricalUsage> usageForItem(String itemId);

  Future<MasterHistoricalUsage> usageForBatch(String batchId);

  Future<MasterHistoricalUsage> usageForRoom(String roomId);

  Future<MasterHistoricalUsage> usageForBranch(String branchId);

  Future<MasterHistoricalUsage> usageForUser(String userId);

  Future<MasterHistoricalUsage> usageForCategory(String categoryId);

  /// Usage for many items at once, keyed by item id.
  ///
  /// The bulk form the import validator uses: G-M5 has to be checked for every
  /// updated row, and one query per row is what turns a 3,000-row item import into
  /// minutes.
  Future<Map<String, MasterHistoricalUsage>> usageForItems(
    Iterable<String> itemIds,
  );

  Future<Map<String, MasterHistoricalUsage>> usageForBatches(
    Iterable<String> batchIds,
  );

  /// How many batches each item has, keyed by item id — the `has_expiry` rule's
  /// input (§20.2).
  Future<Map<String, int>> batchCountsForItems(Iterable<String> itemIds);

  /// Active, non-archived Super Admins other than [excludingUserId].
  ///
  /// Read inside the write transaction, because §21's last-admin rule is a race:
  /// a count taken before the transaction is a fact about a moment that has
  /// passed.
  Future<int> countOtherActiveSuperAdmins(String excludingUserId);

  // --- typed writers ---------------------------------------------------------
  //
  // Each returns the number of rows it changed, and each caller checks it. A
  // guarded UPDATE that matched nothing means the row moved under us — which on
  // this milestone is either a concurrent edit or a status that changed, and both
  // have to be refusals rather than silent no-ops.

  Future<MasterBranch> insertBranch({
    required String code,
    required String name,
    String? address,
    required bool isActive,
  });

  Future<int> updateBranch({
    required String id,
    required String name,
    String? address,
    required bool isActive,
  });

  Future<int> setBranchActive({required String id, required bool isActive});

  Future<MasterRoom> insertRoom({
    required String branchId,
    required String code,
    required String name,
    required bool isActive,
  });

  Future<int> updateRoom({
    required String id,
    required String name,
    required bool isActive,
  });

  Future<int> setRoomActive({required String id, required bool isActive});

  Future<MasterUser> insertUser({
    required String fullName,
    required String email,
    required UserRole role,
    String? branchId,
    required bool isActive,
  });

  Future<int> updateUser({
    required String id,
    required String fullName,
    required UserRole role,
    String? branchId,
    required bool isActive,
  });

  Future<int> setUserActive({required String id, required bool isActive});

  Future<MasterCategory> insertCategory(String name);

  Future<int> updateCategory({required String id, required String name});

  /// `deleted_at = now` — categories have no `is_active` column (§3.6).
  Future<int> archiveCategory(String id);

  /// `deleted_at = NULL`.
  Future<int> restoreCategory(String id);

  Future<MasterItem> insertItem({
    required String sku,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    required int expiryAlertDays,
    required bool isActive,
  });

  Future<int> updateItem({
    required String id,
    required String name,
    required String categoryId,
    required String unit,
    required int minStockRoom,
    required int minStockBranch,
    required bool hasExpiry,
    required int expiryAlertDays,
    required bool isActive,
  });

  Future<int> setItemActive({required String id, required bool isActive});

  Future<MasterBatch> insertBatch({
    required String itemId,
    required String batchNo,
    required DateTime expiryDate,
  });

  Future<int> updateBatch({required String id, required DateTime expiryDate});

  Future<int> archiveBatch(String id);

  Future<int> restoreBatch(String id);

  // --- stock locations (§22) --------------------------------------------------

  /// Creates the one `branch_store` location a new branch must have.
  ///
  /// Named rather than reached through a generic location writer, because §22's
  /// invariant is *exactly one*: a generic insert is how a branch ends up with two
  /// stores and every posting has to guess which one the goods moved through.
  Future<void> ensureBranchStoreLocation({
    required String branchId,
    required String branchName,
  });

  /// Creates the one `room` location a new room must have.
  Future<void> ensureRoomLocation({
    required String branchId,
    required String roomId,
    required String roomName,
  });

  /// Renames the location that follows a branch's or room's name.
  ///
  /// Returns rows changed. **Never touches an id** — a rename is a label change,
  /// and every balance and movement keeps pointing at the same location row.
  Future<int> renameBranchStoreLocation({
    required String branchId,
    required String branchName,
  });

  Future<int> renameRoomLocation({
    required String roomId,
    required String roomName,
  });

  /// How many live `branch_store` locations a branch has — 1 is the only healthy
  /// answer (§22).
  Future<int> branchStoreLocationCount(String branchId);

  Future<int> roomLocationCount(String roomId);

  // --- import audit ----------------------------------------------------------

  /// Writes the `validated` row, after every row has been checked and before any
  /// master row is written (§3.3).
  Future<ImportLog> insertValidatedImportLog({
    required String id,
    required MasterEntityType entity,
    required String fileName,
    required int totalRows,
    required int insertedRows,
    required int updatedRows,
    required int failedRows,
    String? errorDetail,
    required String importedBy,
    required String storedFilePath,
    required String fileSha256,
    required int fileSizeBytes,
    required String templateVersion,
    required DateTime nowUtc,
  });

  Future<ImportLog?> importLogById(String id);

  /// The stored path, which is **not** on [ImportLog] so no screen can render it
  /// (§36). Only the commit reads it.
  Future<String?> importLogStoredPath(String id);

  /// The guarded `validated → committed` / `validated → discarded` transition
  /// (§3.4).
  ///
  /// Returns rows changed. Zero means somebody else moved it first, which the
  /// caller turns into a concurrency failure rather than a silent success.
  Future<int> transitionImportStatus({
    required String id,
    required ImportStatus from,
    required ImportStatus to,
    int? insertedRows,
    int? updatedRows,
    required DateTime nowUtc,
  });

  Stream<List<ImportLog>> watchImportHistory(ImportHistoryFilter filter);

  Future<List<ImportLog>> importHistory(ImportHistoryFilter filter);

  Future<ImportLogDetail?> importLogDetail(String id);

  // --- transaction -----------------------------------------------------------

  /// Runs [action] in one database transaction.
  ///
  /// The commit's single outer transaction (§33). Every writer above is
  /// transaction-aware and **opens none of its own**, which is what makes
  /// "10,000 rows, one transaction" possible and what stops a row writer from
  /// committing a partial import behind the caller's back.
  Future<T> transaction<T>(Future<T> Function() action);
}
