import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../delivery/presentation/providers/delivery_providers.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../../purchase_request/presentation/providers/purchase_request_providers.dart';
import '../../data/repositories/drift_good_receipt_repository.dart';
import '../../domain/models/good_receipt_models.dart';
import '../../domain/repositories/good_receipt_repository.dart';
import '../../domain/services/good_receipt_reminder_builder.dart';
import '../../domain/use_cases/create_good_receipt_use_case.dart';
import '../../domain/use_cases/decide_good_receipt_line_use_cases.dart';
import '../../domain/use_cases/post_good_receipt_use_case.dart';

// --- clock ------------------------------------------------------------------

/// The UTC clock the whole feature reads "now" from.
///
/// A provider rather than a bare `DateTime.now()` because two of this milestone's
/// rules are functions of the current instant: G-E5 asks which operational day it is,
/// and G-G6 asks how far past a 48-hour deadline a shipment has drifted. Overriding
/// this one provider moves the expiry badges, the overdue badges, the dashboard count,
/// the sort order and the `posted_at` stamp together — which is what keeps them
/// consistent (T-7).
final goodReceiptClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

// --- wiring -----------------------------------------------------------------

final goodReceiptRepositoryProvider = Provider<GoodReceiptRepository>(
  (ref) => DriftGoodReceiptRepository(ref.watch(goodReceiptDaoProvider)),
);

/// The posting service the receipt uses, wired to [goodReceiptClockProvider].
///
/// Deliberately not `stockPostingServiceProvider`: that one reads the wall clock, and
/// the receipt's expiry decisions have to be made against the same "now" the rest of
/// the screen used.
final goodReceiptStockPostingServiceProvider = Provider<StockPostingService>(
  (ref) => StockPostingService(
    inventory: ref.watch(inventoryRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(goodReceiptClockProvider),
  ),
);

final createGoodReceiptUseCaseProvider = Provider<CreateGoodReceiptUseCase>(
  (ref) => CreateGoodReceiptUseCase(
    receipts: ref.watch(goodReceiptRepositoryProvider),
    deliveries: ref.watch(deliveryOrderRepositoryProvider),
    requests: ref.watch(purchaseRequestRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(goodReceiptClockProvider),
  ),
);

final checkGoodReceiptLineUseCaseProvider =
    Provider<CheckGoodReceiptLineUseCase>(
      (ref) => CheckGoodReceiptLineUseCase(
        receipts: ref.watch(goodReceiptRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        clock: ref.watch(goodReceiptClockProvider),
      ),
    );

final rejectGoodReceiptLineUseCaseProvider =
    Provider<RejectGoodReceiptLineUseCase>(
      (ref) => RejectGoodReceiptLineUseCase(
        receipts: ref.watch(goodReceiptRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        clock: ref.watch(goodReceiptClockProvider),
      ),
    );

final resetGoodReceiptLineUseCaseProvider =
    Provider<ResetGoodReceiptLineUseCase>(
      (ref) => ResetGoodReceiptLineUseCase(
        receipts: ref.watch(goodReceiptRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        clock: ref.watch(goodReceiptClockProvider),
      ),
    );

final postGoodReceiptUseCaseProvider = Provider<PostGoodReceiptUseCase>(
  (ref) => PostGoodReceiptUseCase(
    receipts: ref.watch(goodReceiptRepositoryProvider),
    deliveries: ref.watch(deliveryOrderRepositoryProvider),
    requests: ref.watch(purchaseRequestRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    posting: ref.watch(goodReceiptStockPostingServiceProvider),
    outbox: ref.watch(syncOutboxWriterProvider),
    clock: ref.watch(goodReceiptClockProvider),
  ),
);

// --- filters ----------------------------------------------------------------

/// Text typed into a Good Receipt list's search field.
class GoodReceiptSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final warehouseGoodReceiptSearchProvider =
    NotifierProvider.autoDispose<GoodReceiptSearchController, String>(
      GoodReceiptSearchController.new,
    );

final warehouseDiscrepancySearchProvider =
    NotifierProvider.autoDispose<GoodReceiptSearchController, String>(
      GoodReceiptSearchController.new,
    );

/// Branch filter on a warehouse list; `null` means every branch.
class GoodReceiptBranchFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? branchId) => state = state == branchId ? null : branchId;
}

final warehouseDiscrepancyBranchFilterProvider =
    NotifierProvider.autoDispose<GoodReceiptBranchFilterController, String?>(
      GoodReceiptBranchFilterController.new,
    );

/// Discrepancy type chip on the warehouse queue; `null` means both.
class GoodReceiptDiscrepancyKindController
    extends Notifier<GoodReceiptDiscrepancyKind?> {
  @override
  GoodReceiptDiscrepancyKind? build() => null;

  void select(GoodReceiptDiscrepancyKind? kind) =>
      state = state == kind ? null : kind;

  void clear() => state = null;
}

final warehouseDiscrepancyKindFilterProvider =
    NotifierProvider.autoDispose<
      GoodReceiptDiscrepancyKindController,
      GoodReceiptDiscrepancyKind?
    >(GoodReceiptDiscrepancyKindController.new);

/// Posted-date window on the warehouse queue; `null` on either side means open.
class GoodReceiptDateRangeController
    extends Notifier<({DateTime? from, DateTime? to})> {
  @override
  ({DateTime? from, DateTime? to}) build() => (from: null, to: null);

  void select({DateTime? from, DateTime? to}) =>
      state = (from: from?.toUtc(), to: to?.toUtc());

  void clear() => state = (from: null, to: null);
}

final warehouseDiscrepancyDateFilterProvider =
    NotifierProvider.autoDispose<
      GoodReceiptDateRangeController,
      ({DateTime? from, DateTime? to})
    >(GoodReceiptDateRangeController.new);

/// Status chip on the branch list; `null` means "Semua".
class GoodReceiptStatusFilterController extends Notifier<GoodReceiptStatus?> {
  @override
  GoodReceiptStatus? build() => null;

  void select(GoodReceiptStatus? status) =>
      state = state == status ? null : status;

  void clear() => state = null;
}

final branchGoodReceiptStatusFilterProvider =
    NotifierProvider.autoDispose<
      GoodReceiptStatusFilterController,
      GoodReceiptStatus?
    >(GoodReceiptStatusFilterController.new);

// --- lists ------------------------------------------------------------------

/// Shipments the acting branch still has to check in (G-G1/G-G6).
///
/// Three properties keep this from becoming an IDOR:
///
/// * the branch comes from [actingBranchIdProvider] on **every build**, so switching
///   user re-runs the query rather than serving the previous branch from cache;
/// * the branch travels into the SQL predicate, so another branch's shipment is not
///   fetched and then withheld — it is not fetched;
/// * `autoDispose` tears the subscription down with the screen.
///
/// A role without a branch — warehouse, super admin — emits an empty list rather than
/// every branch's shipments.
final branchAwaitingDeliveriesProvider = StreamProvider.autoDispose
    .family<List<GoodReceiptAwaitingDelivery>, void>((ref, _) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) {
        return Stream.value(const <GoodReceiptAwaitingDelivery>[]);
      }
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return Stream.value(const <GoodReceiptAwaitingDelivery>[]);
      }
      return ref
          .watch(goodReceiptRepositoryProvider)
          .watchAwaitingDeliveryOrders(branchId: branchId);
    });

/// The acting branch head's own receipts, checking and posted (G-R2).
final branchGoodReceiptListProvider = StreamProvider.autoDispose
    .family<List<GoodReceiptSummary>, void>((ref, _) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) {
        return Stream.value(const <GoodReceiptSummary>[]);
      }
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return Stream.value(const <GoodReceiptSummary>[]);
      }

      final status = ref.watch(branchGoodReceiptStatusFilterProvider);
      return ref
          .watch(goodReceiptRepositoryProvider)
          .watchListForBranch(
            branchId: branchId,
            statuses: status == null ? const <GoodReceiptStatus>{} : {status},
          );
    });

/// Posted receipts across every branch — the warehouse's read-only view.
///
/// Deliberately *not* branch-scoped: the central warehouse ships to all of them. What
/// stands in for the branch predicate is the role check: an actor who is not warehouse
/// gets an empty list here rather than a cross-branch read, so the route guard is not
/// the only thing standing between a branch session and every branch's receipts.
final warehouseGoodReceiptListProvider = StreamProvider.autoDispose
    .family<List<GoodReceiptSummary>, void>((ref, _) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(const <GoodReceiptSummary>[]);
      }
      return ref
          .watch(goodReceiptRepositoryProvider)
          .watchListForWarehouse(
            GoodReceiptFilter(
              searchQuery: ref.watch(warehouseGoodReceiptSearchProvider),
            ),
          );
    });

/// The warehouse's selisih/retur queue, across every branch (G-G3/G-G5, §33).
///
/// Read-only by construction: the repository behind it offers no writer at all for
/// these rows, so there is nothing a screen could call even by mistake.
final warehouseDiscrepancyQueueProvider = StreamProvider.autoDispose
    .family<List<GoodReceiptDiscrepancy>, void>((ref, _) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(const <GoodReceiptDiscrepancy>[]);
      }
      final range = ref.watch(warehouseDiscrepancyDateFilterProvider);
      return ref
          .watch(goodReceiptRepositoryProvider)
          .watchWarehouseDiscrepancies(
            GoodReceiptFilter(
              branchId: ref.watch(warehouseDiscrepancyBranchFilterProvider),
              searchQuery: ref.watch(warehouseDiscrepancySearchProvider),
              discrepancyKind: ref.watch(
                warehouseDiscrepancyKindFilterProvider,
              ),
              postedFromUtc: range.from,
              postedToUtc: range.to,
            ),
          );
    });

/// Refused positions only — the return list, derived from the same rows.
final warehouseReturnCandidatesProvider = Provider.autoDispose
    .family<List<GoodReceiptReturnCandidate>, void>(
      (ref, key) => GoodReceiptReturnCandidate.fromDiscrepancies(
        ref.watch(warehouseDiscrepancyQueueProvider(key)).value ??
            const <GoodReceiptDiscrepancy>[],
      ),
    );

// --- details ----------------------------------------------------------------

/// One receipt, scoped to the branch of whoever is acting.
///
/// Keying the family on the id alone is deliberate: adding the branch to the key would
/// make two entries for the same receipt look independent while still being resolvable,
/// and the leak this prevents is precisely the one where a stale key survives a session
/// change.
final branchGoodReceiptDetailProvider = StreamProvider.autoDispose
    .family<GoodReceiptDetail?, String>((ref, grId) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) return Stream.value(null);
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return Stream.value(null);
      }
      return ref
          .watch(goodReceiptRepositoryProvider)
          .watchForBranch(grId: grId, branchId: branchId);
    });

/// One posted receipt for a warehouse reader — unscoped by branch, but only for an
/// actor that actually holds the warehouse role, and only for a posted document.
final warehouseGoodReceiptDetailProvider = StreamProvider.autoDispose
    .family<GoodReceiptDetail?, String>((ref, grId) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(null);
      }
      return ref.watch(goodReceiptRepositoryProvider).watchForWarehouse(grId);
    });

/// The checklist's decision progress, derived from the branch-scoped detail (G-G2).
final branchGoodReceiptProgressProvider = Provider.autoDispose
    .family<GoodReceiptProgress?, String>(
      (ref, grId) =>
          ref.watch(branchGoodReceiptDetailProvider(grId)).value?.progress,
    );

/// The receipt that already exists for one shipment, if any — what the *Terima
/// Barang* / *Lanjutkan Pemeriksaan* decision asks.
///
/// Branch-scoped through [branchAwaitingDeliveriesProvider] rather than by a lookup of
/// its own, so it cannot answer about a shipment the acting branch may not see.
final branchReceiptForDeliveryProvider = Provider.autoDispose
    .family<GoodReceiptAwaitingDelivery?, String>((ref, doId) {
      final awaiting =
          ref.watch(branchAwaitingDeliveriesProvider(null)).value ??
          const <GoodReceiptAwaitingDelivery>[];
      for (final row in awaiting) {
        if (row.doId == doId) return row;
      }
      return null;
    });

// --- reminders (G-G6) -------------------------------------------------------

/// The acting branch head's 2×24 hour reminders, overdue first.
final branchGoodReceiptRemindersProvider = Provider.autoDispose
    .family<List<GoodReceiptReminder>, void>((ref, key) {
      final awaiting =
          ref.watch(branchAwaitingDeliveriesProvider(key)).value ??
          const <GoodReceiptAwaitingDelivery>[];
      return GoodReceiptReminderBuilder.build(
        awaiting: awaiting,
        nowUtc: ref.watch(goodReceiptClockProvider)(),
      );
    });

/// Only the rows a badge should shout about — what the dashboard card counts.
final branchGoodReceiptUrgentRemindersProvider = Provider.autoDispose
    .family<List<GoodReceiptReminder>, void>(
      (ref, key) => GoodReceiptReminderBuilder.urgentOnly(
        ref.watch(branchGoodReceiptRemindersProvider(key)),
      ),
    );

/// Outstanding receipts across every branch — the warehouse's view of who is late.
///
/// The warehouse gets the cross-branch queue by design (spec §4.2 gives them the
/// selisih report), and the role check here is what keeps a branch session from
/// reaching it.
final warehouseGoodReceiptRemindersProvider = StreamProvider.autoDispose
    .family<List<GoodReceiptAwaitingDelivery>, void>((ref, _) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(const <GoodReceiptAwaitingDelivery>[]);
      }
      return ref
          .watch(goodReceiptRepositoryProvider)
          .watchAwaitingDeliveryOrders();
    });

final warehouseOverdueRemindersProvider = Provider.autoDispose
    .family<List<GoodReceiptReminder>, void>((ref, key) {
      final awaiting =
          ref.watch(warehouseGoodReceiptRemindersProvider(key)).value ??
          const <GoodReceiptAwaitingDelivery>[];
      return GoodReceiptReminderBuilder.urgentOnly(
        GoodReceiptReminderBuilder.build(
          awaiting: awaiting,
          nowUtc: ref.watch(goodReceiptClockProvider)(),
        ),
      );
    });

// --- controllers ------------------------------------------------------------

/// Starts the checklist for one shipment.
///
/// The `AsyncValue<String?>` state is the double-tap guard: while it is loading the
/// button is disabled, so two taps cannot produce two receipts for the same
/// shipment — and if they somehow did, the unique index on `do_id` would let exactly
/// one through.
class CreateGoodReceiptController extends AsyncNotifier<String?> {
  @override
  String? build() => null;

  Future<String?> create({required String deliveryOrderId}) async {
    if (state.isLoading) return null;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return null;

    state = const AsyncValue<String?>.loading();
    final result = await AsyncValue.guard(() async {
      final receipt = await ref
          .read(createGoodReceiptUseCaseProvider)
          .call(actorUserId: session.userId, deliveryOrderId: deliveryOrderId);
      return receipt.id;
    });
    state = result;
    return result.value;
  }
}

final createGoodReceiptControllerProvider =
    AsyncNotifierProvider<CreateGoodReceiptController, String?>(
      CreateGoodReceiptController.new,
    );

/// Decides lines and posts one receipt.
///
/// The state is `AsyncValue<void>`: the screen needs to know only whether an action is
/// in flight and whether the last one failed. The document itself arrives through
/// [branchGoodReceiptDetailProvider], which is a live stream, so a successful write is
/// reflected without this controller having to carry it.
class GoodReceiptCheckingController extends AsyncNotifier<void> {
  @override
  void build() {}

  /// The last posted receipt, so the screen can say what it did. Reset on every new
  /// action.
  GoodReceiptPostingResult? lastPosting;

  Future<bool> check({
    required String grId,
    required String lineId,
    required Quantity receivedQty,
  }) {
    return _run(
      () => ref
          .read(checkGoodReceiptLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            goodReceiptId: grId,
            goodReceiptLineId: lineId,
            receivedQty: receivedQty,
          ),
    );
  }

  Future<bool> reject({
    required String grId,
    required String lineId,
    required String? reason,
  }) {
    return _run(
      () => ref
          .read(rejectGoodReceiptLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            goodReceiptId: grId,
            goodReceiptLineId: lineId,
            reason: reason,
          ),
    );
  }

  Future<bool> reset({required String grId, required String lineId}) {
    return _run(
      () => ref
          .read(resetGoodReceiptLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            goodReceiptId: grId,
            goodReceiptLineId: lineId,
          ),
    );
  }

  /// Posts the receipt. Irreversible: the branch store balance rises the moment this
  /// commits (G-G5), which is why the screen confirms first.
  Future<bool> post(String grId) async {
    if (state.isLoading) return false;

    lastPosting = null;
    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(() async {
      lastPosting = await ref
          .read(postGoodReceiptUseCaseProvider)
          .call(actorUserId: _requireSession().userId, goodReceiptId: grId);
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
  /// whether it succeeded, so the screen can navigate only on success.
  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(action);
    state = result;
    return !result.hasError;
  }
}

final goodReceiptCheckingControllerProvider =
    AsyncNotifierProvider<GoodReceiptCheckingController, void>(
      GoodReceiptCheckingController.new,
    );
