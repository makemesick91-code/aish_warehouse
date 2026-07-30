import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../../purchase_request/presentation/providers/purchase_request_providers.dart';
import '../../data/repositories/drift_delivery_order_repository.dart';
import '../../domain/models/delivery_models.dart';
import '../../domain/repositories/delivery_order_repository.dart';
import '../../domain/services/delivery_warehouse_stock_reader.dart';
import '../../domain/use_cases/build_fefo_delivery_allocation_use_case.dart';
import '../../domain/use_cases/create_delivery_order_use_case.dart';
import '../../domain/use_cases/remove_delivery_order_line_use_case.dart';
import '../../domain/use_cases/ship_delivery_order_use_case.dart';
import '../../domain/use_cases/update_delivery_order_line_use_case.dart';

// --- clock ------------------------------------------------------------------

/// The UTC clock the whole feature reads "now" from.
///
/// A provider rather than a bare `DateTime.now()` because almost every expiry rule
/// is a function of the current operational day: a test that has to sit on the day
/// a batch expires must be able to say so, and overriding this one provider moves
/// the candidate list, the near-expiry badges, the shipment timestamp and the
/// Surat Jalan's print time together — which is what keeps them consistent (T-7).
final deliveryClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

// --- wiring -----------------------------------------------------------------

final deliveryOrderRepositoryProvider = Provider<DeliveryOrderRepository>(
  (ref) => DriftDeliveryOrderRepository(ref.watch(deliveryOrderDaoProvider)),
);

final deliveryWarehouseStockReaderProvider =
    Provider<DeliveryWarehouseStockReader>(
      (ref) =>
          DeliveryWarehouseStockReader(ref.watch(inventoryRepositoryProvider)),
    );

final createDeliveryOrderUseCaseProvider = Provider<CreateDeliveryOrderUseCase>(
  (ref) => CreateDeliveryOrderUseCase(
    deliveries: ref.watch(deliveryOrderRepositoryProvider),
    requests: ref.watch(purchaseRequestRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(deliveryClockProvider),
  ),
);

final buildFefoDeliveryAllocationUseCaseProvider =
    Provider<BuildFefoDeliveryAllocationUseCase>(
      (ref) => BuildFefoDeliveryAllocationUseCase(
        deliveries: ref.watch(deliveryOrderRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        stock: ref.watch(deliveryWarehouseStockReaderProvider),
        clock: ref.watch(deliveryClockProvider),
      ),
    );

final updateDeliveryOrderLineUseCaseProvider =
    Provider<UpdateDeliveryOrderLineUseCase>(
      (ref) => UpdateDeliveryOrderLineUseCase(
        deliveries: ref.watch(deliveryOrderRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        stock: ref.watch(deliveryWarehouseStockReaderProvider),
        clock: ref.watch(deliveryClockProvider),
      ),
    );

final removeDeliveryOrderLineUseCaseProvider =
    Provider<RemoveDeliveryOrderLineUseCase>(
      (ref) => RemoveDeliveryOrderLineUseCase(
        deliveries: ref.watch(deliveryOrderRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

/// The posting service the shipment uses, wired to [deliveryClockProvider].
///
/// Deliberately not `stockPostingServiceProvider`: that one reads the wall clock,
/// and the shipment's expiry decisions (G-E4) have to be made against the same
/// "now" the rest of the screen used. Overriding one provider then moves the
/// candidate list, the near-expiry badge, the ledger's expiry rejection and the
/// `shipped_at` stamp together (T-7).
final deliveryStockPostingServiceProvider = Provider<StockPostingService>(
  (ref) => StockPostingService(
    inventory: ref.watch(inventoryRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(deliveryClockProvider),
  ),
);

final shipDeliveryOrderUseCaseProvider = Provider<ShipDeliveryOrderUseCase>(
  (ref) => ShipDeliveryOrderUseCase(
    deliveries: ref.watch(deliveryOrderRepositoryProvider),
    requests: ref.watch(purchaseRequestRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    posting: ref.watch(deliveryStockPostingServiceProvider),
    stock: ref.watch(deliveryWarehouseStockReaderProvider),
    clock: ref.watch(deliveryClockProvider),
  ),
);

// --- lists ------------------------------------------------------------------

/// Selected status chip on a list; `null` means "Semua".
class DeliveryStatusFilterController extends Notifier<DeliveryOrderStatus?> {
  @override
  DeliveryOrderStatus? build() => null;

  /// Tapping the active chip clears the filter, which is what "Semua" means.
  void select(DeliveryOrderStatus? status) =>
      state = state == status ? null : status;

  void clear() => state = null;
}

final warehouseDeliveryStatusFilterProvider =
    NotifierProvider.autoDispose<
      DeliveryStatusFilterController,
      DeliveryOrderStatus?
    >(DeliveryStatusFilterController.new);

final branchDeliveryStatusFilterProvider =
    NotifierProvider.autoDispose<
      DeliveryStatusFilterController,
      DeliveryOrderStatus?
    >(DeliveryStatusFilterController.new);

/// Text typed into a delivery list's search field.
class DeliverySearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final warehouseDeliverySearchProvider =
    NotifierProvider.autoDispose<DeliverySearchController, String>(
      DeliverySearchController.new,
    );

/// Branch filter on the warehouse list; `null` means every branch.
class DeliveryBranchFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? branchId) => state = state == branchId ? null : branchId;
}

final warehouseDeliveryBranchFilterProvider =
    NotifierProvider.autoDispose<DeliveryBranchFilterController, String?>(
      DeliveryBranchFilterController.new,
    );

/// The warehouse's shipments — every branch, by design (spec §4.2).
///
/// Deliberately *not* branch-scoped: the central warehouse ships to all of them.
/// What stands in for the branch predicate is the role check: an actor who is not
/// warehouse gets an empty list here rather than a cross-branch read, so the route
/// guard is not the only thing standing between a branch session and every
/// branch's shipments.
///
/// `autoDispose` because this is a screen stream. Left alive it would keep a
/// cross-branch query subscribed after the screen closed, and — worse — keep
/// serving its cached rows to whoever the next session belongs to.
final warehouseDeliveryListProvider = StreamProvider.autoDispose
    .family<List<DeliveryOrderSummary>, void>((ref, _) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(const <DeliveryOrderSummary>[]);
      }

      final status = ref.watch(warehouseDeliveryStatusFilterProvider);
      return ref
          .watch(deliveryOrderRepositoryProvider)
          .watchListForWarehouse(
            DeliveryOrderFilter(
              branchId: ref.watch(warehouseDeliveryBranchFilterProvider),
              statuses: status == null ? warehouseDeliveryStatuses : {status},
              searchQuery: ref.watch(warehouseDeliverySearchProvider),
            ),
          );
    });

/// The acting branch head's incoming shipments (G-R2).
///
/// Three properties keep this from becoming an IDOR:
///
/// * the branch comes from [actingBranchIdProvider] on **every build**, so
///   switching user re-runs the query rather than serving the previous branch from
///   cache;
/// * the branch and the status set both travel into the SQL predicate, so a
///   `preparing` document or another branch's shipment is not fetched and then
///   withheld — it is not fetched;
/// * `autoDispose` tears the subscription down with the screen.
///
/// A role without a branch — warehouse, super admin — emits an empty list rather
/// than every branch's shipments.
final branchDeliveryListProvider = StreamProvider.autoDispose
    .family<List<DeliveryOrderSummary>, void>((ref, _) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) {
        return Stream.value(const <DeliveryOrderSummary>[]);
      }
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return Stream.value(const <DeliveryOrderSummary>[]);
      }

      final status = ref.watch(branchDeliveryStatusFilterProvider);
      return ref
          .watch(deliveryOrderRepositoryProvider)
          .watchListForBranch(
            branchId: branchId,
            statuses: status == null ? const <DeliveryOrderStatus>{} : {status},
          );
    });

/// The shipments raised against one Purchase Request — what the PR detail screen
/// shows under "Pengiriman".
final deliveriesOfPurchaseRequestProvider = StreamProvider.autoDispose
    .family<List<DeliveryOrderSummary>, String>((ref, prId) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(const <DeliveryOrderSummary>[]);
      }
      return ref
          .watch(deliveryOrderRepositoryProvider)
          .watchByPurchaseRequest(prId);
    });

// --- details ----------------------------------------------------------------

/// One shipment for a warehouse reader — unscoped by branch, but only for an actor
/// that actually holds the warehouse role.
///
/// The role check is here as well as in the route guard because this provider *is*
/// the unscoped read: a screen that reached it with a branch-scoped session would
/// otherwise see every branch's shipments.
final warehouseDeliveryDetailProvider = StreamProvider.autoDispose
    .family<DeliveryOrderDetail?, String>((ref, doId) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(null);
      }
      return ref.watch(deliveryOrderRepositoryProvider).watchForWarehouse(doId);
    });

/// One shipment, scoped to the branch of whoever is acting **and** to the statuses
/// a branch may see.
///
/// Keying the family on the id alone is deliberate: adding the branch to the key
/// would make two entries for the same document look independent while still being
/// resolvable, and the leak this prevents is precisely the one where a stale key
/// survives a session change.
final branchDeliveryDetailProvider = StreamProvider.autoDispose
    .family<DeliveryOrderDetail?, String>((ref, doId) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) return Stream.value(null);
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return Stream.value(null);
      }
      return ref
          .watch(deliveryOrderRepositoryProvider)
          .watchForBranch(doId: doId, branchId: branchId);
    });

/// Shipment progress of one Purchase Request, before any document is named.
///
/// What the *Buat Delivery Order* entry point asks: is there anything left to
/// send? A request with nothing outstanding offers no button (G-D2/G-D5).
final purchaseRequestShipmentProgressProvider = FutureProvider.autoDispose
    .family<List<ShipmentProgress>, String>((ref, prId) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Future.value(const <ShipmentProgress>[]);
      }
      return ref
          .watch(deliveryOrderRepositoryProvider)
          .shipmentProgress(prId: prId);
    });

/// The allocation drafts of a `preparing` document: outstanding quantity, current
/// allocations and the batch candidates behind each position.
///
/// `autoDispose` because these are form state *and* a stock snapshot — leaving it
/// warm would show yesterday's batch balances the next time the screen opened.
final deliveryAllocationDraftsProvider = FutureProvider.autoDispose
    .family<List<DeliveryLineDraft>, String>((ref, doId) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Future.value(const <DeliveryLineDraft>[]);
      }
      return ref
          .watch(buildFefoDeliveryAllocationUseCaseProvider)
          .drafts(deliveryOrderId: doId);
    });

/// Everything the Surat Jalan prints, scoped the way the reader is.
///
/// The family key carries the scope so a warehouse view and a branch view of the
/// same document are separate cache entries — the warehouse one includes drafts,
/// the branch one does not.
typedef WaybillRequest = ({String doId, bool branchScoped});

final deliveryWaybillProvider = FutureProvider.autoDispose
    .family<WaybillViewModel?, WaybillRequest>((ref, request) async {
      final role = ref.watch(actingRoleProvider);
      final branchId = ref.watch(actingBranchIdProvider);

      if (request.branchScoped) {
        if (role != UserRole.kepalaCabang || branchId == null) return null;
      } else if (role != UserRole.warehouse) {
        return null;
      }

      final warehouse = await ref.watch(warehouseLocationProvider.future);
      return ref
          .watch(deliveryOrderRepositoryProvider)
          .waybill(
            doId: request.doId,
            branchId: request.branchScoped ? branchId : null,
            // The Surat Jalan must print even when the location cannot be resolved:
            // withholding the whole document because a master row is ambiguous would
            // be worse than printing a placeholder next to everything else that is
            // correct. Writes still refuse — that is `requireWarehouseLocation`'s job.
            warehouseName: warehouse?.name ?? 'Warehouse Pusat',
            printedAtUtc: ref.watch(deliveryClockProvider)(),
          );
    });

// --- controllers ------------------------------------------------------------

/// Raises a shipment from a Purchase Request.
///
/// The `AsyncValue<String?>` state is the double-tap guard: while it is loading the
/// button is disabled, so two taps cannot produce two documents against the same
/// request.
class CreateDeliveryOrderController extends AsyncNotifier<String?> {
  @override
  String? build() => null;

  Future<String?> create({
    required String purchaseRequestId,
    String? note,
  }) async {
    if (state.isLoading) return null;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return null;

    state = const AsyncValue<String?>.loading();
    final result = await AsyncValue.guard(() async {
      final order = await ref
          .read(createDeliveryOrderUseCaseProvider)
          .call(
            actorUserId: session.userId,
            purchaseRequestId: purchaseRequestId,
            note: note,
          );
      return order.id;
    });
    state = result;

    if (!result.hasError) {
      // The request may have moved `submitted → processing`, and the warehouse
      // queue shows that status.
      ref.invalidate(
        purchaseRequestShipmentProgressProvider(purchaseRequestId),
      );
    }
    return result.value;
  }
}

final createDeliveryOrderControllerProvider =
    AsyncNotifierProvider<CreateDeliveryOrderController, String?>(
      CreateDeliveryOrderController.new,
    );

/// Edits and ships a `preparing` document.
///
/// The state is `AsyncValue<void>`: the screen needs to know only whether an action
/// is in flight and whether the last one failed. The document itself arrives
/// through [warehouseDeliveryDetailProvider], which is a live stream, so a
/// successful write is reflected without this controller having to carry it.
class DeliveryOrderFormController extends AsyncNotifier<void> {
  @override
  void build() {}

  /// The last posted shipment, so the screen can say whether it completed the
  /// order. Reset on every new action.
  ShipmentResult? lastShipment;

  Future<bool> allocateFefo({
    required String doId,
    Map<String, Quantity>? requestedByPrLineId,
  }) {
    return _run(
      doId,
      () => ref
          .read(buildFefoDeliveryAllocationUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            deliveryOrderId: doId,
            requestedByPrLineId: requestedByPrLineId,
          ),
    );
  }

  Future<bool> saveLine({
    required String doId,
    required String lineId,
    required Quantity shippedQty,
    String? batchId,
    String? fefoOverrideReason,
    bool nearExpiryConfirmed = false,
    String? nearExpiryNote,
  }) {
    return _run(
      doId,
      () => ref
          .read(updateDeliveryOrderLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            lineId: lineId,
            shippedQty: shippedQty,
            batchId: batchId,
            fefoOverrideReason: fefoOverrideReason,
            nearExpiryConfirmed: nearExpiryConfirmed,
            nearExpiryNote: nearExpiryNote,
          ),
    );
  }

  Future<bool> addLine({
    required String doId,
    required String prLineId,
    required Quantity shippedQty,
    String? batchId,
    String? fefoOverrideReason,
    bool nearExpiryConfirmed = false,
    String? nearExpiryNote,
  }) {
    return _run(
      doId,
      () => ref
          .read(updateDeliveryOrderLineUseCaseProvider)
          .add(
            actorUserId: _requireSession().userId,
            deliveryOrderId: doId,
            prLineId: prLineId,
            shippedQty: shippedQty,
            batchId: batchId,
            fefoOverrideReason: fefoOverrideReason,
            nearExpiryConfirmed: nearExpiryConfirmed,
            nearExpiryNote: nearExpiryNote,
          ),
    );
  }

  Future<bool> removeLine({required String doId, required String lineId}) {
    return _run(
      doId,
      () => ref
          .read(removeDeliveryOrderLineUseCaseProvider)
          .call(actorUserId: _requireSession().userId, lineId: lineId),
    );
  }

  Future<bool> saveNote({required String doId, String? note}) {
    return _run(
      doId,
      () => ref
          .read(updateDeliveryOrderLineUseCaseProvider)
          .saveNote(
            actorUserId: _requireSession().userId,
            deliveryOrderId: doId,
            note: note,
          ),
    );
  }

  /// Posts the shipment. Irreversible: the warehouse balance drops the moment this
  /// commits (G-D3), which is why the screen confirms first.
  Future<bool> ship(String doId) async {
    if (state.isLoading) return false;

    lastShipment = null;
    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(() async {
      lastShipment = await ref
          .read(shipDeliveryOrderUseCaseProvider)
          .call(actorUserId: _requireSession().userId, deliveryOrderId: doId);
    });
    state = result;

    if (!result.hasError) _invalidate(doId);
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
  Future<bool> _run(String doId, Future<void> Function() action) async {
    if (state.isLoading) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(action);
    state = result;
    if (!result.hasError) _invalidate(doId);
    return !result.hasError;
  }

  /// The stock snapshot and the progress figures are derived reads rather than
  /// streams, so they have to be told when a write moved them.
  void _invalidate(String doId) {
    ref.invalidate(deliveryAllocationDraftsProvider(doId));
    ref.invalidate(deliveryWaybillProvider((doId: doId, branchScoped: false)));
  }
}

final deliveryOrderFormControllerProvider =
    AsyncNotifierProvider<DeliveryOrderFormController, void>(
      DeliveryOrderFormController.new,
    );
