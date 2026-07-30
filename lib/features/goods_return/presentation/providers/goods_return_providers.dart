import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../inventory/presentation/models/stock_card_entry.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../inventory/presentation/stock_card_builder.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../data/repositories/drift_goods_return_repository.dart';
import '../../domain/models/goods_return_models.dart';
import '../../domain/repositories/goods_return_repository.dart';
import '../../domain/services/goods_return_access_policy.dart';
import '../../domain/use_cases/create_goods_return_use_case.dart';
import '../../domain/use_cases/receive_goods_return_use_case.dart';
import '../../domain/use_cases/ship_goods_return_use_case.dart';
import '../../domain/use_cases/update_goods_return_note_use_case.dart';

// --- clock ------------------------------------------------------------------

/// The UTC clock the whole feature reads "now" from.
///
/// A provider rather than a bare `DateTime.now()` because three separate things depend
/// on which day it is: the expiry badges on a document's lines, the *umur perjalanan*
/// column on the Warehouse queue, and the `shipped_at` / `received_at` stamps
/// themselves. Overriding this one provider moves all of them together — which is what
/// keeps them consistent (T-7).
final goodsReturnClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

// --- wiring -----------------------------------------------------------------

final goodsReturnRepositoryProvider = Provider<GoodsReturnRepository>(
  (ref) => DriftGoodsReturnRepository(
    ref.watch(goodsReturnDaoProvider),
    clock: ref.watch(goodsReturnClockProvider),
  ),
);

/// The posting service the receive uses, wired to [goodsReturnClockProvider].
///
/// Deliberately not `stockPostingServiceProvider`: that one reads the wall clock, and
/// every instant a document stamps has to come from the same "now" the screen used.
final goodsReturnStockPostingServiceProvider = Provider<StockPostingService>(
  (ref) => StockPostingService(
    inventory: ref.watch(inventoryRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(goodsReturnClockProvider),
  ),
);

final createGoodsReturnUseCaseProvider = Provider<CreateGoodsReturnUseCase>(
  (ref) => CreateGoodsReturnUseCase(
    returns: ref.watch(goodsReturnRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(goodsReturnClockProvider),
  ),
);

final updateGoodsReturnNoteUseCaseProvider =
    Provider<UpdateGoodsReturnNoteUseCase>(
      (ref) => UpdateGoodsReturnNoteUseCase(
        returns: ref.watch(goodsReturnRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final shipGoodsReturnUseCaseProvider = Provider<ShipGoodsReturnUseCase>(
  (ref) => ShipGoodsReturnUseCase(
    returns: ref.watch(goodsReturnRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(goodsReturnClockProvider),
  ),
);

final receiveGoodsReturnUseCaseProvider = Provider<ReceiveGoodsReturnUseCase>(
  (ref) => ReceiveGoodsReturnUseCase(
    returns: ref.watch(goodsReturnRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    posting: ref.watch(goodsReturnStockPostingServiceProvider),
    clock: ref.watch(goodsReturnClockProvider),
  ),
);

// --- policies ---------------------------------------------------------------
//
// `GoodsReturnStatePolicy`, `GoodsReturnAccessPolicy`, `GoodsReturnEligibilityPolicy`
// and `GoodsReturnSnapshotPolicy` are deliberately **not** wrapped in providers, and
// this note is here so the absence reads as a decision rather than an omission.
//
// All four are `abstract final class`es with nothing but static members: they hold no
// state, take no dependencies and cannot be instantiated, so a provider around one
// would have nothing to provide and nothing to override. Every earlier feature in this
// application references its policies directly for the same reason — the guards, the
// route guard, the screens and the use cases all import the one class, which is what
// makes them agree by construction. Wrapping them would add a layer whose only effect
// would be to make that agreement look optional.

// --- filters ----------------------------------------------------------------

/// The branch section's list filter. `autoDispose` so leaving the screen forgets it.
final branchGoodsReturnFilterProvider =
    NotifierProvider.autoDispose<
      GoodsReturnFilterController,
      GoodsReturnFilter
    >(GoodsReturnFilterController.new);

/// The Warehouse queue's filter — the same shape, a separate instance, because the two
/// screens filter independently and sharing one would make a branch chip set on the
/// Warehouse queue follow the user into their own section.
final warehouseGoodsReturnFilterProvider =
    NotifierProvider.autoDispose<
      GoodsReturnFilterController,
      GoodsReturnFilter
    >(GoodsReturnFilterController.new);

class GoodsReturnFilterController extends Notifier<GoodsReturnFilter> {
  @override
  GoodsReturnFilter build() => const GoodsReturnFilter();

  void setSearchQuery(String value) =>
      state = state.copyWith(searchQuery: value);

  void setStatuses(Set<GoodsReturnStatus> statuses) =>
      state = state.copyWith(statuses: statuses);

  void setBranchId(String? branchId) => branchId == null
      ? state = state.copyWith(clearBranchId: true)
      : state = state.copyWith(branchId: branchId);

  void setRange({DateTime? from, DateTime? to}) => state = state.copyWith(
    from: from,
    clearFrom: from == null,
    to: to,
    clearTo: to == null,
  );

  void clear() => state = const GoodsReturnFilter();
}

// --- branch reads -----------------------------------------------------------

/// Every posted Good Receipt of the acting branch head's branch that carries
/// rejections — the *Perlu Dibuat* section (§29).
///
/// The branch id comes from [actingBranchIdProvider] and **never** from a family
/// parameter. That is the rule §28 states and the reason is structural: a family key is
/// something a caller supplies, so a screen that could ask for a branch could ask for
/// somebody else's. Here there is no way to express the question.
final branchRejectedGoodReceiptsProvider = StreamProvider.autoDispose
    .family<List<GoodsReturnEligibility>, String>((ref, searchQuery) {
      final role = ref.watch(actingRoleProvider);
      final branchId = ref.watch(actingBranchIdProvider);
      if (!GoodsReturnAccessPolicy.canWriteBranch(role) || branchId == null) {
        return Stream.value(const <GoodsReturnEligibility>[]);
      }
      return ref
          .watch(goodsReturnRepositoryProvider)
          .watchEligibleGoodReceiptsForBranch(
            branchId: branchId,
            searchQuery: searchQuery,
          );
    });

/// One eligible receipt by id, for the create screen and its guard.
///
/// `null` for "no such receipt", for "another branch's" and for "nothing rejected"
/// alike — one answer, so the address bar cannot tell them apart (§27).
final goodsReturnEligibilityByReceiptProvider = FutureProvider.autoDispose
    .family<GoodsReturnEligibility?, String>((ref, grId) async {
      final role = ref.watch(actingRoleProvider);
      final branchId = ref.watch(actingBranchIdProvider);
      if (!GoodsReturnAccessPolicy.canWriteBranch(role) || branchId == null) {
        return null;
      }
      final rows = await ref
          .watch(goodsReturnRepositoryProvider)
          .eligibleGoodReceiptsForBranch(branchId: branchId);
      for (final row in rows) {
        if (row.grId == grId) return row;
      }
      return null;
    });

/// The acting branch's returns, in every status, filtered.
///
/// The **status and search** halves of the filter go into the SQL; the date half is
/// applied here, in Dart, on parsed UTC instants — a SQL range on `created_at` would
/// compare ISO-8601 characters (§29/§39).
final branchGoodsReturnListProvider =
    StreamProvider.autoDispose<List<GoodsReturnSummary>>((ref) {
      final role = ref.watch(actingRoleProvider);
      final branchId = ref.watch(actingBranchIdProvider);
      if (!GoodsReturnAccessPolicy.canWriteBranch(role) || branchId == null) {
        return Stream.value(const <GoodsReturnSummary>[]);
      }
      final filter = ref.watch(branchGoodsReturnFilterProvider);
      return ref
          .watch(goodsReturnRepositoryProvider)
          .watchBranchList(
            branchId: branchId,
            statuses: filter.statuses,
            searchQuery: filter.searchQuery,
          )
          .map(
            (rows) => rows.where(filter.matchesDate).toList(growable: false),
          );
    });

/// One of the acting branch's returns, live and branch-scoped.
final branchGoodsReturnDetailProvider = StreamProvider.autoDispose
    .family<GoodsReturnDetail?, String>((ref, goodsReturnId) {
      final role = ref.watch(actingRoleProvider);
      final branchId = ref.watch(actingBranchIdProvider);
      if (!GoodsReturnAccessPolicy.canWriteBranch(role) || branchId == null) {
        return Stream.value(null);
      }
      return ref
          .watch(goodsReturnRepositoryProvider)
          .watchForBranch(goodsReturnId: goodsReturnId, branchId: branchId);
    });

// --- Warehouse reads --------------------------------------------------------

/// Every branch's `shipped` and `received` returns — the Warehouse queue and history.
///
/// Deliberately **not** branch-scoped: a Petugas Warehouse works one queue across every
/// branch (§15). What keeps them out of a branch's private work is the status half of
/// the scope, which lives in the DAO predicate rather than in the parameter this
/// provider passes — so a caller cannot ask for a draft even by mistake.
final warehouseGoodsReturnListProvider =
    StreamProvider.autoDispose<List<GoodsReturnSummary>>((ref) {
      final role = ref.watch(actingRoleProvider);
      if (!GoodsReturnAccessPolicy.canReceive(role)) {
        return Stream.value(const <GoodsReturnSummary>[]);
      }
      final filter = ref.watch(warehouseGoodsReturnFilterProvider);
      return ref
          .watch(goodsReturnRepositoryProvider)
          .watchWarehouseList(
            statuses: filter.statuses,
            filterBranchId: filter.branchId,
            searchQuery: filter.searchQuery,
          )
          .map(
            (rows) => rows.where(filter.matchesDate).toList(growable: false),
          );
    });

/// The queue's two sections, split in Dart from one stream so a single subscription
/// feeds both tabs.
final warehouseGoodsReturnQueueProvider =
    Provider.autoDispose<AsyncValue<List<GoodsReturnSummary>>>(
      (ref) => ref
          .watch(warehouseGoodsReturnListProvider)
          .whenData(
            (rows) => rows
                .where((row) => row.status.isShipped)
                .toList(growable: false),
          ),
    );

final warehouseGoodsReturnHistoryProvider =
    Provider.autoDispose<AsyncValue<List<GoodsReturnSummary>>>(
      (ref) => ref
          .watch(warehouseGoodsReturnListProvider)
          .whenData(
            (rows) => rows
                .where((row) => row.status.isReceived)
                .toList(growable: false),
          ),
    );

/// One shipped or received return, live. A draft never reaches this stream.
final warehouseGoodsReturnDetailProvider = StreamProvider.autoDispose
    .family<GoodsReturnDetail?, String>((ref, goodsReturnId) {
      final role = ref.watch(actingRoleProvider);
      if (!GoodsReturnAccessPolicy.canReceive(role)) {
        return Stream.value(null);
      }
      return ref
          .watch(goodsReturnRepositoryProvider)
          .watchForWarehouse(goodsReturnId);
    });

// --- dashboards -------------------------------------------------------------

/// The four counters the Kepala Cabang's Retur section leads with (§35).
class BranchGoodsReturnDashboard {
  const BranchGoodsReturnDashboard({
    required this.pendingReceiptCount,
    required this.draftCount,
    required this.shippedCount,
    required this.receivedTodayCount,
  });

  const BranchGoodsReturnDashboard.empty()
    : pendingReceiptCount = 0,
      draftCount = 0,
      shippedCount = 0,
      receivedTodayCount = 0;

  /// Posted Good Receipts with rejections that have **no** return yet — the work the
  /// branch still owes the Warehouse.
  final int pendingReceiptCount;

  final int draftCount;
  final int shippedCount;

  /// Received **today**, in operational time (GMT+8). The day boundary comes from
  /// `AppTimeZone`, never from the device's zone (T-3/T-4).
  final int receivedTodayCount;
}

/// [BranchGoodsReturnDashboard], derived from the two streams the screen already
/// watches rather than from counting queries of its own.
///
/// [nowUtc] is a family key so the operational-day boundary is pinned by the caller —
/// a counter that read its own clock would disagree with the badges beside it (T-7).
final branchGoodsReturnDashboardProvider = Provider.autoDispose
    .family<BranchGoodsReturnDashboard, DateTime>((ref, nowUtc) {
      final eligible = ref.watch(branchRejectedGoodReceiptsProvider('')).value;
      final documents = ref.watch(branchGoodsReturnListProvider).value;
      if (eligible == null && documents == null) {
        return const BranchGoodsReturnDashboard.empty();
      }

      final rows = documents ?? const <GoodsReturnSummary>[];
      return BranchGoodsReturnDashboard(
        pendingReceiptCount: (eligible ?? const <GoodsReturnEligibility>[])
            .where((row) => row.canCreateReturn)
            .length,
        draftCount: rows.where((row) => row.status.isDraft).length,
        shippedCount: rows.where((row) => row.status.isShipped).length,
        receivedTodayCount: rows
            .where(
              (row) =>
                  row.status.isReceived &&
                  row.goodsReturn.receivedAt != null &&
                  AppTimeZone.isSameOperationalDay(
                    row.goodsReturn.receivedAt!,
                    nowUtc,
                  ),
            )
            .length,
      );
    });

/// The four counters the Warehouse queue leads with (§35).
class WarehouseGoodsReturnDashboard {
  const WarehouseGoodsReturnDashboard({
    required this.awaitingCount,
    required this.expiredBatchCount,
    required this.receivedTodayCount,
    required this.outstandingReceiptCount,
  });

  const WarehouseGoodsReturnDashboard.empty()
    : awaitingCount = 0,
      expiredBatchCount = 0,
      receivedTodayCount = 0,
      outstandingReceiptCount = 0;

  /// Documents in transit, waiting to be counted in.
  final int awaitingCount;

  /// How many of those documents carry at least one already-expired batch.
  ///
  /// A count of *documents*, not of positions: it answers *"how many boxes arriving
  /// today will need a Pemusnahan"*, which is the question a Warehouse user plans
  /// around. An expired batch is never a reason to refuse the return (§36).
  final int expiredBatchCount;

  final int receivedTodayCount;

  /// Good Receipt discrepancies that still have no return document at all — the
  /// Warehouse's view of what the branches still owe (§35).
  final int outstandingReceiptCount;
}

/// The return raised for one Good Receipt, or `null` — *Belum dibuat* (§33).
///
/// Keyed by a **single** `grId` rather than by the list a screen is showing, and that
/// is not a style choice: a Riverpod family key is compared with `==`, and a `List`
/// compares by identity — so `provider([grId])` would mint a fresh provider on every
/// rebuild and the widget would never settle. A `String` key is stable, and the DAO's
/// batched `returnsByGoodReceipt` stays available for callers that genuinely hold a set.
///
/// The lookup widens nothing: it turns a receipt the caller can already see into a
/// status label, and returns the header only — never a branch's document content.
final goodsReturnStatusByReceiptProvider = FutureProvider.autoDispose
    .family<GoodsReturn?, String>((ref, grId) async {
      final role = ref.watch(actingRoleProvider);
      // Both audiences legitimately ask: the Warehouse from the discrepancy queue, and a
      // branch head from their own Good Receipt detail (§33).
      if (!GoodsReturnAccessPolicy.canReceive(role) &&
          !GoodsReturnAccessPolicy.canWriteBranch(role)) {
        return null;
      }
      final rows = await ref
          .watch(goodsReturnRepositoryProvider)
          .returnsByGoodReceipt([grId]);
      return rows[grId];
    });

/// How many posted Good Receipts across every branch still owe a return (§35).
final outstandingRejectedGoodReceiptCountProvider =
    StreamProvider.autoDispose<int>((ref) {
      final role = ref.watch(actingRoleProvider);
      if (!GoodsReturnAccessPolicy.canReceive(role)) return Stream.value(0);
      return ref
          .watch(goodsReturnRepositoryProvider)
          .watchOutstandingRejectedGoodReceiptCount();
    });

/// [WarehouseGoodsReturnDashboard], assembled from the queue the screen already
/// watches plus two narrow reads.
///
/// The expired count is computed **in Dart** from the batch dates, against [nowUtc] —
/// asking SQL would mean comparing a stored date against a serialised "now", and would
/// also let the counter drift from the red badges on the detail beside it (T-7/§36).
final warehouseGoodsReturnDashboardProvider = FutureProvider.autoDispose
    .family<WarehouseGoodsReturnDashboard, DateTime>((ref, nowUtc) async {
      final rows = ref.watch(warehouseGoodsReturnListProvider).value;
      if (rows == null) return const WarehouseGoodsReturnDashboard.empty();

      final awaiting = rows
          .where((row) => row.status.isShipped)
          .toList(growable: false);

      final expiries = await ref
          .watch(goodsReturnRepositoryProvider)
          .batchExpiriesFor(awaiting.map((row) => row.id));
      final today = AppTimeZone.operationalDate(nowUtc);
      final withExpired = awaiting
          .where(
            (row) => (expiries[row.id] ?? const <DateTime>[]).any(
              (expiry) => DateOnly.isBeforeDate(expiry, today),
            ),
          )
          .length;

      return WarehouseGoodsReturnDashboard(
        awaitingCount: awaiting.length,
        expiredBatchCount: withExpired,
        receivedTodayCount: rows
            .where(
              (row) =>
                  row.status.isReceived &&
                  row.goodsReturn.receivedAt != null &&
                  AppTimeZone.isSameOperationalDay(
                    row.goodsReturn.receivedAt!,
                    nowUtc,
                  ),
            )
            .length,
        outstandingReceiptCount:
            ref.watch(outstandingRejectedGoodReceiptCountProvider).value ?? 0,
      );
    });

/// The active branches the Warehouse queue's chip row is built from (§31).
///
/// A display list, not a scope: whichever branch is picked only *narrows* a read that
/// is already pinned to the two Warehouse-visible statuses.
final goodsReturnBranchesProvider =
    FutureProvider.autoDispose<List<MasterBranch>>((ref) async {
      final role = ref.watch(actingRoleProvider);
      if (!GoodsReturnAccessPolicy.canReceive(role)) return const [];
      return ref.watch(masterDataRepositoryProvider).activeBranches();
    });

// --- ledger -----------------------------------------------------------------

/// The `return` movements one document wrote, ready for `StockCardList` (§34).
///
/// Scope is **inherited** rather than re-derived: the first thing it does is resolve the
/// document through the acting role's own scoped read — branch-scoped for a Kepala
/// Cabang, status-scoped for a Petugas Warehouse. A document the reader may not open
/// yields `null` there and this yields an empty card, so there is no path by which a
/// stock card reaches the movements of a document the reader was refused. Re-checking
/// the scope here would be a second copy of the rule, and the copy is what eventually
/// differs.
///
/// The rows go through `buildStockCardEntries`, the same builder every other document
/// uses, so a return row carries the item, the batch, its expiry, the Warehouse actor
/// and the RET number — and resolves them through *historical* lookups, so a withdrawn
/// item leaves the field labelled rather than the row dropped (§34/§37).
final goodsReturnMovementsProvider = FutureProvider.autoDispose
    .family<List<StockCardEntry>, String>((ref, goodsReturnId) async {
      final role = ref.watch(actingRoleProvider);

      // Whichever scoped read the acting role is entitled to. A Warehouse user reads
      // across branches but never a draft; a branch head reads their own branch only.
      final GoodsReturnDetail? detail;
      if (GoodsReturnAccessPolicy.canReceive(role)) {
        detail = ref
            .watch(warehouseGoodsReturnDetailProvider(goodsReturnId))
            .value;
      } else if (GoodsReturnAccessPolicy.canWriteBranch(role)) {
        detail = ref
            .watch(branchGoodsReturnDetailProvider(goodsReturnId))
            .value;
      } else {
        detail = null;
      }
      if (detail == null) return const <StockCardEntry>[];

      final movements = await ref
          .watch(inventoryRepositoryProvider)
          .movementsByRef(
            refDocType: RefDocType.goodsReturn,
            refDocId: detail.id,
          );

      return buildStockCardEntries(
        movements: movements,
        master: ref.watch(masterDataRepositoryProvider),
        // Supplied from the *scoped* detail, so a row always shows the number of a
        // document the reader is already looking at.
        documentNumbers: {detail.id: detail.goodsReturn.docNumber},
      );
    });

// --- actions ----------------------------------------------------------------

/// The result of one workflow action, as a screen needs to render it.
///
/// A value rather than a thrown exception crossing into the widget layer, because a
/// screen has to be able to show a message *and* stay usable. [documentId] carries the
/// existing return when a create loses the race, so the UI can offer *"Lihat Retur"*
/// instead of a dead end (§30).
class GoodsReturnActionResult {
  const GoodsReturnActionResult.success(this.documentId)
    : errorMessage = null,
      isSuccess = true;

  const GoodsReturnActionResult.failure(this.errorMessage, {this.documentId})
    : isSuccess = false;

  final bool isSuccess;
  final String? errorMessage;
  final String? documentId;
}

/// Runs the three workflow actions, exposing a `isBusy` flag the buttons disable on.
///
/// A notifier rather than a bare method so the *processing* state is part of what the
/// widget watches: §30 and §32 both require the confirmation button to be disabled
/// while the transaction is in flight, and a second tap on a receive would otherwise
/// race the first through the guarded UPDATE.
final goodsReturnActionsProvider =
    NotifierProvider.autoDispose<GoodsReturnActions, bool>(
      GoodsReturnActions.new,
    );

class GoodsReturnActions extends Notifier<bool> {
  @override
  bool build() => false;

  /// Raises a return from one posted Good Receipt.
  Future<GoodsReturnActionResult> create({
    required String goodReceiptId,
    String? note,
  }) => _run(() async {
    final actor = await ref.read(actingUserProvider.future);
    if (actor == null) return _noSession();
    final created = await ref
        .read(createGoodsReturnUseCaseProvider)
        .call(actorUserId: actor.id, goodReceiptId: goodReceiptId, note: note);
    return GoodsReturnActionResult.success(created.id);
  });

  Future<GoodsReturnActionResult> updateNote({
    required String goodsReturnId,
    required String? note,
  }) => _run(() async {
    final actor = await ref.read(actingUserProvider.future);
    if (actor == null) return _noSession();
    final updated = await ref
        .read(updateGoodsReturnNoteUseCaseProvider)
        .call(actorUserId: actor.id, goodsReturnId: goodsReturnId, note: note);
    return GoodsReturnActionResult.success(updated.id);
  });

  Future<GoodsReturnActionResult> ship(String goodsReturnId) => _run(() async {
    final actor = await ref.read(actingUserProvider.future);
    if (actor == null) return _noSession();
    final shipped = await ref
        .read(shipGoodsReturnUseCaseProvider)
        .call(actorUserId: actor.id, goodsReturnId: goodsReturnId);
    return GoodsReturnActionResult.success(shipped.id);
  });

  Future<GoodsReturnActionResult> receive({
    required String goodsReturnId,
    String? warehouseNote,
  }) => _run(() async {
    final actor = await ref.read(actingUserProvider.future);
    if (actor == null) return _noSession();
    final received = await ref
        .read(receiveGoodsReturnUseCaseProvider)
        .call(
          actorUserId: actor.id,
          goodsReturnId: goodsReturnId,
          warehouseNote: warehouseNote,
        );
    return GoodsReturnActionResult.success(received.id);
  });

  GoodsReturnActionResult _noSession() => const GoodsReturnActionResult.failure(
    'Sesi pengguna tidak tersedia. Muat ulang aplikasi lalu coba lagi.',
  );

  /// Runs [action] with the busy flag raised, and turns any failure into a sentence.
  ///
  /// Every message comes from `describeFailure`, so a raw exception string or a stack
  /// trace never reaches a clinic user (§28). The busy flag is lowered in a `finally`,
  /// because a screen stuck disabled after an error is a screen nobody can retry from.
  Future<GoodsReturnActionResult> _run(
    Future<GoodsReturnActionResult> Function() action,
  ) async {
    if (state) {
      return const GoodsReturnActionResult.failure(
        'Tindakan sebelumnya masih diproses. Tunggu sebentar lalu coba lagi.',
      );
    }
    state = true;
    try {
      return await action();
    } catch (error) {
      return GoodsReturnActionResult.failure(
        describeFailure(error),
        // The one failure that carries a document a screen can offer to open: a create
        // that lost the race to another device already knows which return won (§30).
        documentId: error is GoodsReturnAlreadyExistsFailure
            ? error.existingGoodsReturnId
            : null,
      );
    } finally {
      state = false;
    }
  }
}
