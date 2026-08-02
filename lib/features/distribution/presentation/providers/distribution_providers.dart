import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../data/repositories/drift_distribution_repository.dart';
import '../../domain/models/distribution_models.dart';
import '../../domain/repositories/distribution_repository.dart';
import '../../domain/services/distribution_access_policy.dart';
import '../../domain/services/distribution_branch_stock_reader.dart';
import '../../domain/use_cases/add_distribution_item_use_case.dart';
import '../../domain/use_cases/add_manual_distribution_allocation_use_case.dart';
import '../../domain/use_cases/create_distribution_use_case.dart';
import '../../domain/use_cases/post_distribution_use_case.dart';
import '../../domain/use_cases/remove_distribution_line_use_case.dart';
import '../../domain/use_cases/update_distribution_line_use_case.dart';

// --- clock ------------------------------------------------------------------

/// The UTC clock the whole feature reads "now" from.
///
/// A provider rather than a bare `DateTime.now()` because this milestone's expiry
/// rules are functions of the current instant: G-E4 asks which operational day it is,
/// and G-E6 how many days a batch has left. Overriding this one provider moves the
/// expiry badges, the candidate list, the FEFO evaluation and the `posted_at` stamp
/// together — which is what keeps them consistent (T-7).
final distributionClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

// --- wiring -----------------------------------------------------------------

final distributionRepositoryProvider = Provider<DistributionRepository>(
  (ref) => DriftDistributionRepository(ref.watch(distributionDaoProvider)),
);

final distributionBranchStockReaderProvider =
    Provider<DistributionBranchStockReader>(
      (ref) =>
          DistributionBranchStockReader(ref.watch(inventoryRepositoryProvider)),
    );

/// The posting service the distribution uses, wired to [distributionClockProvider].
///
/// Deliberately not `stockPostingServiceProvider`: that one reads the wall clock, and
/// the expiry decisions behind a posting have to be made against the same "now" the
/// rest of the screen used.
final distributionStockPostingServiceProvider = Provider<StockPostingService>(
  (ref) => StockPostingService(
    inventory: ref.watch(inventoryRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(distributionClockProvider),
  ),
);

final createDistributionUseCaseProvider = Provider<CreateDistributionUseCase>(
  (ref) => CreateDistributionUseCase(
    distributions: ref.watch(distributionRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(distributionClockProvider),
  ),
);

final addDistributionItemUseCaseProvider = Provider<AddDistributionItemUseCase>(
  (ref) => AddDistributionItemUseCase(
    distributions: ref.watch(distributionRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(distributionClockProvider),
  ),
);

final addManualDistributionAllocationUseCaseProvider =
    Provider<AddManualDistributionAllocationUseCase>(
      (ref) => AddManualDistributionAllocationUseCase(
        distributions: ref.watch(distributionRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        clock: ref.watch(distributionClockProvider),
      ),
    );

final updateDistributionLineUseCaseProvider =
    Provider<UpdateDistributionLineUseCase>(
      (ref) => UpdateDistributionLineUseCase(
        distributions: ref.watch(distributionRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        clock: ref.watch(distributionClockProvider),
      ),
    );

final removeDistributionLineUseCaseProvider =
    Provider<RemoveDistributionLineUseCase>(
      (ref) => RemoveDistributionLineUseCase(
        distributions: ref.watch(distributionRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final postDistributionUseCaseProvider = Provider<PostDistributionUseCase>(
  (ref) => PostDistributionUseCase(
    distributions: ref.watch(distributionRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    posting: ref.watch(distributionStockPostingServiceProvider),
    stock: ref.watch(distributionBranchStockReaderProvider),
    outbox: ref.watch(syncOutboxWriterProvider),
    clock: ref.watch(distributionClockProvider),
  ),
);

// --- filters ----------------------------------------------------------------

/// Text typed into the distribution list's search field.
class DistributionSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final distributionSearchProvider =
    NotifierProvider.autoDispose<DistributionSearchController, String>(
      DistributionSearchController.new,
    );

/// Status chip on the list; `null` means "Semua".
class DistributionStatusFilterController extends Notifier<DistributionStatus?> {
  @override
  DistributionStatus? build() => null;

  void select(DistributionStatus? status) =>
      state = state == status ? null : status;

  void clear() => state = null;
}

final distributionStatusFilterProvider =
    NotifierProvider.autoDispose<
      DistributionStatusFilterController,
      DistributionStatus?
    >(DistributionStatusFilterController.new);

/// The room the form is currently adding items to.
///
/// A document targets several rooms (G-T3), so the form needs a "which room am I
/// filling in" selection — and it is a provider rather than widget state so the room
/// chips, the item picker and the grouped line list all read the same answer.
class DistributionSelectedRoomController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? roomId) => state = roomId;

  void clear() => state = null;
}

final distributionSelectedRoomProvider =
    NotifierProvider.autoDispose<DistributionSelectedRoomController, String?>(
      DistributionSelectedRoomController.new,
    );

/// Category chip on the item picker; `null` means "Semua" (§15).
class DistributionCategoryFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? categoryId) =>
      state = state == categoryId ? null : categoryId;

  void clear() => state = null;
}

final distributionCategoryFilterProvider =
    NotifierProvider.autoDispose<DistributionCategoryFilterController, String?>(
      DistributionCategoryFilterController.new,
    );

/// The categories the chips are built from — dynamic master data, never hard-coded
/// (spec §4.3).
final distributionCategoriesProvider =
    FutureProvider.autoDispose<List<MasterCategory>>(
      (ref) => ref.watch(masterDataRepositoryProvider).categories(),
    );

// --- branch context ---------------------------------------------------------

/// The acting branch head's rooms, live (§29).
///
/// Dynamic rather than a hard-coded `R1 / R2 / R3`: rooms are master data managed by
/// the Super Admin, and a branch with four rooms must show four chips. A role that is
/// not `kepala_cabang`, or an account with no branch, gets an empty list rather than
/// every branch's rooms.
final branchDistributionRoomsProvider = StreamProvider.autoDispose
    .family<List<MasterRoom>, void>((ref, _) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) return Stream.value(const <MasterRoom>[]);
      if (!DistributionAccessPolicy.canWrite(ref.watch(actingRoleProvider))) {
        return Stream.value(const <MasterRoom>[]);
      }
      return ref
          .watch(distributionRepositoryProvider)
          .watchBranchRooms(branchId);
    });

/// The acting branch head's own branch, or `null`.
///
/// Read from master data rather than inferred from whatever documents happen to be on
/// screen: §28 asks the list to name the branch, and deriving it from the first row would
/// make the header vanish the moment a status filter matched nothing.
final actingBranchProvider = FutureProvider.autoDispose<MasterBranch?>((
  ref,
) async {
  final branchId = ref.watch(actingBranchIdProvider);
  if (branchId == null) return null;
  if (!DistributionAccessPolicy.canWrite(ref.watch(actingRoleProvider))) {
    return null;
  }
  final branches = await ref
      .watch(masterDataRepositoryProvider)
      .activeBranches();
  for (final branch in branches) {
    if (branch.id == branchId) return branch;
  }
  return null;
});

/// The acting branch's single *Gudang Cabang*, or `null`.
///
/// `null` covers three cases on purpose: no branch, no store, and *more than one*
/// store. A screen has nothing useful to say about the third — which of two stores did
/// it mean? — and reading the list rather than asking for "the" store is what keeps it
/// from throwing a driver error on a form. The precise failure is produced where it
/// matters, in the use cases (§14).
final branchStoreLocationProvider = FutureProvider.autoDispose<MasterLocation?>(
  (ref) async {
    final branchId = ref.watch(actingBranchIdProvider);
    if (branchId == null) return null;
    if (!DistributionAccessPolicy.canWrite(ref.watch(actingRoleProvider))) {
      return null;
    }
    final locations = await ref
        .watch(masterDataRepositoryProvider)
        .activeBranchStoreLocations(branchId);
    return locations.length == 1 ? locations.single : null;
  },
);

// --- lists ------------------------------------------------------------------

/// The acting branch head's own distributions, drafts and posted (G-R2).
///
/// Three properties keep this from becoming an IDOR:
///
/// * the branch comes from [actingBranchIdProvider] on **every build**, so switching
///   user re-runs the query rather than serving the previous branch from cache;
/// * the branch travels into the SQL predicate, so another branch's document is not
///   fetched and then withheld — it is not fetched;
/// * `autoDispose` tears the subscription down with the screen.
///
/// A role that may not write distributions emits an empty list rather than a
/// cross-branch read, so the route guard is never the only thing standing between a
/// warehouse session and a branch's documents.
final branchDistributionListProvider = StreamProvider.autoDispose
    .family<List<DistributionSummary>, void>((ref, _) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) {
        return Stream.value(const <DistributionSummary>[]);
      }
      if (!DistributionAccessPolicy.canWrite(ref.watch(actingRoleProvider))) {
        return Stream.value(const <DistributionSummary>[]);
      }

      final status = ref.watch(distributionStatusFilterProvider);
      return ref
          .watch(distributionRepositoryProvider)
          .watchListForBranch(
            branchId: branchId,
            statuses: status == null ? const <DistributionStatus>{} : {status},
            searchQuery: ref.watch(distributionSearchProvider),
          );
    });

// --- details ----------------------------------------------------------------

/// One document, scoped to the branch of whoever is acting.
///
/// Keying the family on the id alone is deliberate: adding the branch to the key would
/// make two entries for the same document look independent while still being
/// resolvable, and the leak this prevents is precisely the one where a stale key
/// survives a session change.
final branchDistributionDetailProvider = StreamProvider.autoDispose
    .family<DistributionDetail?, String>((ref, distributionId) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) return Stream.value(null);
      if (!DistributionAccessPolicy.canWrite(ref.watch(actingRoleProvider))) {
        return Stream.value(null);
      }
      return ref
          .watch(distributionRepositoryProvider)
          .watchForBranch(distributionId: distributionId, branchId: branchId);
    });

/// The document's counters, judged against the feature clock so a badge and the number
/// beside it agree (T-7).
final branchDistributionProgressProvider = Provider.autoDispose
    .family<DistributionProgress?, String>((ref, distributionId) {
      final detail = ref
          .watch(branchDistributionDetailProvider(distributionId))
          .value;
      if (detail == null) return null;
      return detail.progressOn(ref.watch(distributionClockProvider)());
    });

// --- branch-store stock (§15) -----------------------------------------------

/// The key an item search is cached under: what was typed, and which category chip is
/// active. A record rather than a class — Dart gives structural equality and
/// `hashCode` for free, which is the whole of what a Riverpod family key needs.
typedef DistributionStockQuery = ({String query, String? categoryId});

/// Items the branch store can actually distribute, matching [query] (§15).
///
/// Only positive **usable** balances appear: an item whose only stock has expired is
/// absent rather than offered and then refused (G-E4). Everything runs against the
/// local database, so the picker keeps working with no network (G-Y1).
final distributionStockSearchProvider = FutureProvider.autoDispose
    .family<List<DistributionStockItem>, DistributionStockQuery>((
      ref,
      key,
    ) async {
      final store = await ref.watch(branchStoreLocationProvider.future);
      if (store == null) return const <DistributionStockItem>[];

      return ref
          .watch(distributionRepositoryProvider)
          .searchBranchStock(
            branchStoreLocationId: store.id,
            nowUtc: ref.watch(distributionClockProvider)(),
            searchQuery: key.query,
            categoryId: key.categoryId,
          );
    });

/// One item's branch-store position, for the allocation card.
final distributionStockItemProvider = FutureProvider.autoDispose
    .family<DistributionStockItem?, String>((ref, itemId) async {
      final store = await ref.watch(branchStoreLocationProvider.future);
      if (store == null) return null;

      return ref
          .watch(distributionRepositoryProvider)
          .branchStockFor(
            branchStoreLocationId: store.id,
            itemId: itemId,
            nowUtc: ref.watch(distributionClockProvider)(),
          );
    });

// --- dashboard (§31) --------------------------------------------------------

/// Drafts the branch head has not posted yet — the card that says "you have unfinished
/// work".
final branchDraftDistributionCountProvider = Provider.autoDispose<int>((ref) {
  final rows =
      ref.watch(branchDistributionListProvider(null)).value ??
      const <DistributionSummary>[];
  return rows.where((summary) => summary.distribution.isDraft).length;
});

/// Distributions posted today, in **operational** time (GMT+8).
///
/// The window is applied in Dart on UTC instants rather than in SQL, because
/// timestamps are ISO-8601 TEXT and a SQL comparison would compare characters — the
/// trap schema v4 removed from `stock_opnames`. Moving a *display* filter into Dart is
/// safe in a way moving the branch predicate would not be: a row outside today is this
/// branch's own data either way.
final branchDistributionsPostedTodayProvider = Provider.autoDispose<int>((ref) {
  final rows =
      ref.watch(branchDistributionListProvider(null)).value ??
      const <DistributionSummary>[];
  final nowUtc = ref.watch(distributionClockProvider)();
  return rows.where((summary) {
    final postedAt = summary.distribution.postedAt;
    if (postedAt == null) return false;
    return AppTimeZone.isSameOperationalDay(postedAt, nowUtc);
  }).length;
});

/// Positions in the branch store that are below the item's branch minimum, or already
/// past their expiry date (G-E6).
///
/// Read from the store's own balances rather than from any document, so the card is
/// about the shelf rather than about paperwork.
final branchStoreAlertsProvider = FutureProvider.autoDispose<DistributionStoreAlerts>((
  ref,
) async {
  final store = await ref.watch(branchStoreLocationProvider.future);
  if (store == null) return const DistributionStoreAlerts.empty();

  final nowUtc = ref.watch(distributionClockProvider)();
  final balances = await ref
      .watch(inventoryRepositoryProvider)
      .balancesAtLocation(store.id);

  var nearExpiry = 0;
  var expired = 0;
  final totalsByItem = <String, Quantity>{};

  for (final balance in balances) {
    totalsByItem[balance.itemId] =
        (totalsByItem[balance.itemId] ?? Quantity.zero()) + balance.qtyOnHand;
    // Expiry is counted per **batch position**, because that is what a reader acts
    // on: one batch to dispose of (G-E7), rather than "this product has a problem".
    if (balance.isExpiredOn(nowUtc)) {
      expired += 1;
      continue;
    }
    final days = balance.daysUntilExpiry(nowUtc);
    if (days != null && days < balance.expiryAlertDays) nearExpiry += 1;
  }

  // Iterated over the **catalogue** rather than over the balances, and that is the
  // whole point: `balancesAtLocation` returns positive rows only, so an item the
  // store has run out of entirely has no row at all — and a product at zero against
  // a minimum of twenty is the most low-stock thing there is. Counting from the
  // balances alone would have reported it as fine.
  var low = 0;
  final items = await ref.watch(masterDataRepositoryProvider).activeItems();
  for (final item in items) {
    if (item.minStockBranch <= 0) continue;
    final onHand = totalsByItem[item.id] ?? Quantity.zero();
    if (onHand < Quantity.fromWhole(item.minStockBranch)) low += 1;
  }

  return DistributionStoreAlerts(
    lowStockItems: low,
    nearExpiryPositions: nearExpiry,
    expiredPositions: expired,
  );
});

/// The three numbers the branch-store card shows.
class DistributionStoreAlerts {
  const DistributionStoreAlerts({
    required this.lowStockItems,
    required this.nearExpiryPositions,
    required this.expiredPositions,
  });

  const DistributionStoreAlerts.empty()
    : lowStockItems = 0,
      nearExpiryPositions = 0,
      expiredPositions = 0;

  /// Items whose total branch-store balance is below `items.min_stock_branch`.
  final int lowStockItems;

  /// Batch positions inside their alert window (G-E6).
  final int nearExpiryPositions;

  /// Batch positions already past their expiry date. Not distributable at all (G-E4);
  /// they leave through disposal (G-E7).
  final int expiredPositions;

  bool get isEmpty =>
      lowStockItems == 0 && nearExpiryPositions == 0 && expiredPositions == 0;
}

// --- controllers ------------------------------------------------------------

/// Creates a draft and hands its id back so the caller can navigate to the form.
///
/// The `AsyncValue<String?>` state is the double-tap guard: while it is loading the
/// button is disabled, so two taps cannot produce two documents.
class CreateDistributionController extends AsyncNotifier<String?> {
  @override
  String? build() => null;

  Future<String?> create({String? note}) async {
    if (state.isLoading) return null;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return null;

    state = const AsyncValue<String?>.loading();
    final result = await AsyncValue.guard(() async {
      final distribution = await ref
          .read(createDistributionUseCaseProvider)
          .call(actorUserId: session.userId, note: note);
      return distribution.id;
    });
    state = result;
    return result.value;
  }
}

final createDistributionControllerProvider =
    AsyncNotifierProvider<CreateDistributionController, String?>(
      CreateDistributionController.new,
    );

/// Edits the lines of one draft and posts it.
///
/// The state is `AsyncValue<void>`: the screen needs to know only whether an action is
/// in flight and whether the last one failed. The document itself arrives through
/// [branchDistributionDetailProvider], which is a live stream, so a successful write is
/// reflected without this controller having to carry it.
class DistributionEditorController extends AsyncNotifier<void> {
  @override
  void build() {}

  /// The last posted result, so the screen can say what it did. Reset on every new
  /// action.
  DistributionPostingResult? lastPosting;

  Future<bool> addItem({
    required String distributionId,
    required String roomId,
    required String itemId,
    required Quantity qty,
  }) {
    return _run(
      () => ref
          .read(addDistributionItemUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            distributionId: distributionId,
            roomId: roomId,
            itemId: itemId,
            requestedQty: qty,
          ),
    );
  }

  Future<bool> addAllocation({
    required String distributionId,
    required String roomId,
    required String itemId,
    String? batchId,
    required Quantity qty,
    String? fefoOverrideReason,
  }) {
    return _run(
      () => ref
          .read(addManualDistributionAllocationUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            distributionId: distributionId,
            roomId: roomId,
            itemId: itemId,
            batchId: batchId,
            qty: qty,
            fefoOverrideReason: fefoOverrideReason,
          ),
    );
  }

  Future<bool> updateLine({
    required String distributionId,
    required String lineId,
    required Quantity qty,
    String? fefoOverrideReason,
  }) {
    return _run(
      () => ref
          .read(updateDistributionLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            distributionId: distributionId,
            lineId: lineId,
            qty: qty,
            fefoOverrideReason: fefoOverrideReason,
          ),
    );
  }

  Future<bool> removeLine({
    required String distributionId,
    required String lineId,
  }) {
    return _run(
      () => ref
          .read(removeDistributionLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            distributionId: distributionId,
            lineId: lineId,
          ),
    );
  }

  /// Posts the document. Irreversible: the store balance falls and every targeted
  /// room's rises the moment this commits (spec §2.5), which is why the screen confirms
  /// first.
  Future<bool> post(String distributionId) async {
    if (state.isLoading) return false;

    lastPosting = null;
    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(() async {
      lastPosting = await ref
          .read(postDistributionUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            distributionId: distributionId,
          );
    });
    state = result;
    return !result.hasError;
  }

  CurrentUserSession _requireSession() {
    final session = ref.read(currentSessionValueProvider);
    if (session == null) {
      throw StateError('Tidak ada sesi pengguna aktif.');
    }
    return session;
  }

  /// Runs one action behind the in-flight guard and records the outcome. Returns
  /// whether it succeeded, so the screen can close a sheet only on success.
  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(action);
    state = result;
    return !result.hasError;
  }
}

final distributionEditorControllerProvider =
    AsyncNotifierProvider<DistributionEditorController, void>(
      DistributionEditorController.new,
    );
