/// Riverpod wiring for the Super Admin master and import screens (§38).
///
/// ### Two rules run through every provider here
///
/// **The actor is never a parameter.** No provider takes an actor id from the
/// UI; every one that needs one reads [actingUserProvider], which loads the user
/// from the database by id. A screen that could pass an id would be a screen that
/// could pass somebody else's (§53).
///
/// **Every data provider re-applies the policy.** The route guard is the first
/// line, not the line: a provider can be read from anywhere, including a widget
/// test with no router at all. Each one below therefore returns empty for an
/// unauthorized actor rather than trusting that a guard ran — so an unauthorized
/// widget tree contains no email, no SKU, no filename and no count, whatever
/// path led to it.
///
/// Everything page-scoped is `autoDispose`, and everything depends on the acting
/// user, so switching session tears the whole subtree down: a stale cache entry
/// is the one way a correctly-scoped read still leaks.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../data/files/file_selector_master_import_file_picker.dart';
import '../../data/files/local_import_source_file_store.dart';
import '../../data/files/local_master_template_file_store.dart';
import '../../data/files/share_plus_master_template_share_gateway.dart';
import '../../data/import/excel_master_import_workbook_parser.dart';
import '../../data/repositories/drift_master_admin_repository.dart';
import '../../data/templates/excel_master_template_generator.dart';
import '../../domain/gateways/master_import_gateways.dart';
import '../../domain/models/import_models.dart';
import '../../domain/models/master_admin_models.dart';
import '../../domain/repositories/master_admin_repository.dart';
import '../../domain/services/master_admin_access_policy.dart';
import '../../domain/use_cases/batch_crud_use_cases.dart';
import '../../domain/use_cases/branch_crud_use_cases.dart';
import '../../domain/use_cases/category_crud_use_cases.dart';
import '../../domain/use_cases/commit_master_import_use_case.dart';
import '../../domain/use_cases/download_master_template_use_case.dart';
import '../../domain/use_cases/item_crud_use_cases.dart';
import '../../domain/use_cases/room_crud_use_cases.dart';
import '../../domain/use_cases/user_crud_use_cases.dart';
import '../../domain/use_cases/validate_master_import_use_case.dart';

// --- repository ---------------------------------------------------------------

final masterAdminRepositoryProvider = Provider<MasterAdminRepository>(
  (ref) => DriftMasterAdminRepository(ref.watch(masterAdminDaoProvider)),
);

// --- gateways ------------------------------------------------------------------
//
// The four platform boundaries. Overridden with fakes in every test, which is
// what keeps the picker and the share sheet out of the test suite entirely.

final masterTemplateGeneratorProvider = Provider<MasterTemplateGenerator>(
  (ref) => const ExcelMasterTemplateGenerator(),
);

final masterTemplateFileStoreProvider = Provider<MasterTemplateFileStore>(
  (ref) => const LocalMasterTemplateFileStore(),
);

final masterTemplateShareGatewayProvider = Provider<MasterTemplateShareGateway>(
  (ref) => const SharePlusMasterTemplateShareGateway(),
);

final masterImportFilePickerProvider = Provider<MasterImportFilePicker>(
  (ref) => const FileSelectorMasterImportFilePicker(),
);

final importSourceFileStoreProvider = Provider<ImportSourceFileStore>(
  (ref) => const LocalImportSourceFileStore(),
);

final masterImportWorkbookReaderProvider = Provider<MasterImportWorkbookReader>(
  (ref) => const ExcelMasterImportWorkbookReader(),
);

// --- authorization --------------------------------------------------------------

/// Whether the acting user may see the master and import sections at all.
///
/// `false` while the actor is loading, and `false` on error. A screen that
/// rendered optimistically during the load would flash a list of every user in
/// the clinic group before the refusal arrived.
final canAdministerMasterProvider = Provider<bool>((ref) {
  final actor = ref.watch(actingUserProvider);
  return actor.maybeWhen(
    data: (user) => MasterAdminAccessPolicy.forSection(
      user: user,
      kind: MasterAdminRouteKind.master,
    ).isGranted,
    orElse: () => false,
  );
});

/// The acting user's id, or `null`.
///
/// The **only** way a use case in this feature learns who is acting. Nothing in
/// the presentation layer accepts an actor id as an argument (§38).
final masterAdminActorIdProvider = Provider<String?>((ref) {
  final actor = ref.watch(actingUserProvider);
  return actor.maybeWhen(data: (user) => user?.id, orElse: () => null);
});

// --- use cases -------------------------------------------------------------------

final createBranchUseCaseProvider = Provider<CreateBranchUseCase>(
  (ref) => CreateBranchUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final updateBranchUseCaseProvider = Provider<UpdateBranchUseCase>(
  (ref) => UpdateBranchUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final setBranchActiveUseCaseProvider = Provider<SetBranchActiveUseCase>(
  (ref) => SetBranchActiveUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final createRoomUseCaseProvider = Provider<CreateRoomUseCase>(
  (ref) => CreateRoomUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final updateRoomUseCaseProvider = Provider<UpdateRoomUseCase>(
  (ref) => UpdateRoomUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final setRoomActiveUseCaseProvider = Provider<SetRoomActiveUseCase>(
  (ref) => SetRoomActiveUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final createUserUseCaseProvider = Provider<CreateUserUseCase>(
  (ref) => CreateUserUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final updateUserUseCaseProvider = Provider<UpdateUserUseCase>(
  (ref) => UpdateUserUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final setUserActiveUseCaseProvider = Provider<SetUserActiveUseCase>(
  (ref) => SetUserActiveUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final createCategoryUseCaseProvider = Provider<CreateItemCategoryUseCase>(
  (ref) => CreateItemCategoryUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final archiveCategoryUseCaseProvider = Provider<ArchiveItemCategoryUseCase>(
  (ref) => ArchiveItemCategoryUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final restoreCategoryUseCaseProvider = Provider<RestoreItemCategoryUseCase>(
  (ref) => RestoreItemCategoryUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final createItemUseCaseProvider = Provider<CreateItemUseCase>(
  (ref) => CreateItemUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final updateItemUseCaseProvider = Provider<UpdateItemUseCase>(
  (ref) => UpdateItemUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final setItemActiveUseCaseProvider = Provider<SetItemActiveUseCase>(
  (ref) => SetItemActiveUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final createBatchUseCaseProvider = Provider<CreateItemBatchUseCase>(
  (ref) => CreateItemBatchUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final updateBatchUseCaseProvider = Provider<UpdateItemBatchUseCase>(
  (ref) => UpdateItemBatchUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final archiveBatchUseCaseProvider = Provider<ArchiveItemBatchUseCase>(
  (ref) => ArchiveItemBatchUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final restoreBatchUseCaseProvider = Provider<RestoreItemBatchUseCase>(
  (ref) => RestoreItemBatchUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final downloadTemplateUseCaseProvider = Provider<DownloadMasterTemplateUseCase>(
  (ref) => DownloadMasterTemplateUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    generator: ref.watch(masterTemplateGeneratorProvider),
    fileStore: ref.watch(masterTemplateFileStoreProvider),
    shareGateway: ref.watch(masterTemplateShareGatewayProvider),
  ),
);

final validateImportUseCaseProvider = Provider<ValidateMasterImportUseCase>(
  (ref) => ValidateMasterImportUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    workbookReader: ref.watch(masterImportWorkbookReaderProvider),
    sourceFileStore: ref.watch(importSourceFileStoreProvider),
    fileUploadQueue: ref.watch(syncFileUploadQueueProvider),
  ),
);

final commitImportUseCaseProvider = Provider<CommitMasterImportUseCase>(
  (ref) => CommitMasterImportUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    workbookReader: ref.watch(masterImportWorkbookReaderProvider),
    sourceFileStore: ref.watch(importSourceFileStoreProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final discardImportUseCaseProvider = Provider<DiscardMasterImportUseCase>(
  (ref) => DiscardMasterImportUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
    outboxWriter: ref.watch(syncOutboxWriterProvider),
  ),
);

final watchImportHistoryUseCaseProvider = Provider<WatchImportHistoryUseCase>(
  (ref) => WatchImportHistoryUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
  ),
);

final importLogDetailUseCaseProvider = Provider<GetImportLogDetailUseCase>(
  (ref) => GetImportLogDetailUseCase(
    repository: ref.watch(masterAdminRepositoryProvider),
  ),
);

// --- dashboard -------------------------------------------------------------------

final masterDashboardProvider =
    FutureProvider.autoDispose<MasterAdminDashboard>((ref) async {
      if (!ref.watch(canAdministerMasterProvider)) {
        // An empty dashboard rather than a throw: an unauthorized tree must
        // contain no counts at all, and an error object carrying one would be
        // exactly the leak §53 tests for.
        return const MasterAdminDashboard(summaries: []);
      }
      return ref.watch(masterAdminRepositoryProvider).dashboard();
    });

// --- list filters -----------------------------------------------------------------

/// The filter each list is showing, keyed by entity.
///
/// One notifier holding a map rather than a family of notifiers, and the map is
/// what keeps the six lists independent: a category typed into *Barang* must not
/// still be applied when *Batch* opens. `autoDispose` so leaving the master
/// section forgets every search box at once — a filter that survived a session
/// switch would be a filter applied to somebody else's data.
final masterListFiltersProvider =
    NotifierProvider.autoDispose<
      MasterListFilterController,
      Map<MasterEntityType, MasterListFilter>
    >(MasterListFilterController.new);

class MasterListFilterController
    extends Notifier<Map<MasterEntityType, MasterListFilter>> {
  @override
  Map<MasterEntityType, MasterListFilter> build() =>
      const <MasterEntityType, MasterListFilter>{};

  MasterListFilter filterFor(MasterEntityType entity) =>
      state[entity] ?? const MasterListFilter();

  void _update(
    MasterEntityType entity,
    MasterListFilter Function(MasterListFilter) change,
  ) => state = {...state, entity: change(filterFor(entity))};

  void setQuery(MasterEntityType entity, String query) =>
      _update(entity, (filter) => filter.copyWith(query: query));

  void setIncludeInactive(MasterEntityType entity, bool value) =>
      _update(entity, (filter) => filter.copyWith(includeInactive: value));

  void setCategory(MasterEntityType entity, String? categoryId) => _update(
    entity,
    (filter) => categoryId == null
        ? filter.copyWith(clearCategory: true)
        : filter.copyWith(categoryId: categoryId),
  );

  void setBranch(MasterEntityType entity, String? branchId) => _update(
    entity,
    (filter) => branchId == null
        ? filter.copyWith(clearBranch: true)
        : filter.copyWith(branchId: branchId),
  );

  void setRole(MasterEntityType entity, UserRole? role) => _update(
    entity,
    (filter) => role == null
        ? filter.copyWith(clearRole: true)
        : filter.copyWith(role: role),
  );

  void setHasExpiry(MasterEntityType entity, bool? value) => _update(
    entity,
    (filter) => value == null
        ? filter.copyWith(clearHasExpiry: true)
        : filter.copyWith(hasExpiry: value),
  );

  void reset(MasterEntityType entity) =>
      state = {...state, entity: const MasterListFilter()};
}

/// The filter one list is showing — what a list page watches.
final masterListFilterProvider = Provider.autoDispose
    .family<MasterListFilter, MasterEntityType>(
      (ref, entity) =>
          ref.watch(masterListFiltersProvider)[entity] ??
          const MasterListFilter(),
    );

// --- lists --------------------------------------------------------------------------
//
// Every one guards, and every one returns an **empty list** when refused rather
// than throwing: an error object rendered by a list widget is still a widget with
// data in it, and §53 asserts an unauthorized tree contains none.

final masterBranchListProvider = FutureProvider.autoDispose
    .family<List<MasterBranchAdminView>, MasterListFilter>((ref, filter) async {
      if (!ref.watch(canAdministerMasterProvider)) return const [];
      return ref.watch(masterAdminRepositoryProvider).listBranches(filter);
    });

final masterRoomListProvider = FutureProvider.autoDispose
    .family<List<MasterRoomAdminView>, MasterListFilter>((ref, filter) async {
      if (!ref.watch(canAdministerMasterProvider)) return const [];
      return ref.watch(masterAdminRepositoryProvider).listRooms(filter);
    });

final masterUserListProvider = FutureProvider.autoDispose
    .family<List<MasterUserAdminView>, MasterListFilter>((ref, filter) async {
      if (!ref.watch(canAdministerMasterProvider)) return const [];
      return ref
          .watch(masterAdminRepositoryProvider)
          .listUsers(filter, actorId: ref.watch(masterAdminActorIdProvider));
    });

final masterCategoryListProvider = FutureProvider.autoDispose
    .family<List<MasterCategoryAdminView>, MasterListFilter>((
      ref,
      filter,
    ) async {
      if (!ref.watch(canAdministerMasterProvider)) return const [];
      return ref.watch(masterAdminRepositoryProvider).listCategories(filter);
    });

final masterItemListProvider = FutureProvider.autoDispose
    .family<List<MasterItemAdminView>, MasterListFilter>((ref, filter) async {
      if (!ref.watch(canAdministerMasterProvider)) return const [];
      return ref.watch(masterAdminRepositoryProvider).listItems(filter);
    });

final masterBatchListProvider = FutureProvider.autoDispose
    .family<List<MasterBatchAdminView>, MasterListFilter>((ref, filter) async {
      if (!ref.watch(canAdministerMasterProvider)) return const [];
      return ref.watch(masterAdminRepositoryProvider).listBatches(filter);
    });

/// Historical usage for one row, for the badge and the disabled-field reasons.
final masterItemUsageProvider = FutureProvider.autoDispose
    .family<MasterHistoricalUsage, String>((ref, itemId) async {
      if (!ref.watch(canAdministerMasterProvider)) {
        return const MasterHistoricalUsage.none();
      }
      return ref.watch(masterAdminRepositoryProvider).usageForItem(itemId);
    });

final masterBatchUsageProvider = FutureProvider.autoDispose
    .family<MasterHistoricalUsage, String>((ref, batchId) async {
      if (!ref.watch(canAdministerMasterProvider)) {
        return const MasterHistoricalUsage.none();
      }
      return ref.watch(masterAdminRepositoryProvider).usageForBatch(batchId);
    });

// --- import history ------------------------------------------------------------------

final importHistoryFilterProvider =
    NotifierProvider.autoDispose<
      ImportHistoryFilterNotifier,
      ImportHistoryFilter
    >(ImportHistoryFilterNotifier.new);

class ImportHistoryFilterNotifier extends Notifier<ImportHistoryFilter> {
  @override
  ImportHistoryFilter build() => const ImportHistoryFilter();

  void setEntity(MasterEntityType? entity) => state = entity == null
      ? state.copyWith(clearEntity: true)
      : state.copyWith(entity: entity);

  void setStatus(ImportStatus? status) => state = status == null
      ? state.copyWith(clearStatus: true)
      : state.copyWith(status: status);

  void setSyncStatus(SyncStatus? syncStatus) => state = syncStatus == null
      ? state.copyWith(clearSyncStatus: true)
      : state.copyWith(syncStatus: syncStatus);

  void setFileNameQuery(String query) =>
      state = state.copyWith(fileNameQuery: query);

  void setRange({DateTime? fromUtc, DateTime? toUtc}) => state = state.copyWith(
    fromDateUtc: fromUtc,
    clearFrom: fromUtc == null,
    toDateUtc: toUtc,
    clearTo: toUtc == null,
  );

  void reset() => state = const ImportHistoryFilter();
}

final importHistoryProvider = StreamProvider.autoDispose
    .family<List<ImportLog>, ImportHistoryFilter>((ref, filter) {
      final actorId = ref.watch(masterAdminActorIdProvider);
      if (actorId == null || !ref.watch(canAdministerMasterProvider)) {
        return Stream.value(const <ImportLog>[]);
      }
      return ref
          .watch(watchImportHistoryUseCaseProvider)
          .call(actorUserId: actorId, filter: filter);
    });

final importLogDetailProvider = FutureProvider.autoDispose
    .family<ImportLogDetail?, String>((ref, importId) async {
      final actorId = ref.watch(masterAdminActorIdProvider);
      if (actorId == null) return null;
      return ref
          .watch(importLogDetailUseCaseProvider)
          .call(actorUserId: actorId, importId: importId);
    });

/// Counts for the Super Admin home page (§39).
final importDashboardSummaryProvider =
    FutureProvider.autoDispose<ImportDashboardSummary>((ref) async {
      if (!ref.watch(canAdministerMasterProvider)) {
        return const ImportDashboardSummary.empty();
      }
      final logs = await ref
          .watch(masterAdminRepositoryProvider)
          .importHistory(const ImportHistoryFilter());
      return ImportDashboardSummary.from(logs);
    });

/// The four numbers §39 asks the Super Admin dashboard for.
class ImportDashboardSummary {
  const ImportDashboardSummary({
    required this.pendingValidation,
    required this.committedToday,
    required this.pendingSync,
    this.lastImport,
  });

  const ImportDashboardSummary.empty()
    : pendingValidation = 0,
      committedToday = 0,
      pendingSync = 0,
      lastImport = null;

  /// Validated imports nobody has committed or discarded yet — the queue an
  /// administrator has to come back to.
  final int pendingValidation;

  final int committedToday;

  /// Import logs whose own row has not reached the server (G-M7).
  final int pendingSync;

  final ImportLog? lastImport;

  static ImportDashboardSummary from(List<ImportLog> logs) {
    if (logs.isEmpty) return const ImportDashboardSummary.empty();
    // The history is already `created_at DESC`, so the newest is first.
    final newest = logs.first;
    final todayUtc = DateTime.now().toUtc();
    return ImportDashboardSummary(
      pendingValidation: logs.where((log) => log.status.isValidated).length,
      committedToday: logs
          .where(
            (log) =>
                log.status.isCommitted &&
                log.updatedAtUtc.year == todayUtc.year &&
                log.updatedAtUtc.month == todayUtc.month &&
                log.updatedAtUtc.day == todayUtc.day,
          )
          .length,
      pendingSync: logs
          .where((log) => log.syncStatus != SyncStatus.synced)
          .length,
      lastImport: newest,
    );
  }
}
