import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/delivery_models.dart';
import '../repositories/delivery_order_repository.dart';
import '../services/delivery_expiry_policy.dart';
import '../services/delivery_fefo_policy.dart';
import '../services/delivery_quantity_policy.dart';
import '../services/delivery_warehouse_stock_reader.dart';
import 'delivery_order_guards.dart';

/// What one requested position ended up with, and why it is not more (§20.2).
///
/// The shortfall is reported rather than silently accepted: an officer who asked
/// to ship the whole outstanding quantity and got two thirds of it needs to know
/// whether the limit was the order or the shelf.
class FefoAllocationOutcome {
  const FefoAllocationOutcome({
    required this.prLineId,
    required this.sku,
    required this.itemName,
    required this.unit,
    required this.requestedQty,
    required this.allocatedQty,
    required this.availableQty,
    this.expiredQty,
  });

  final String prLineId;
  final String sku;
  final String itemName;
  final String unit;

  /// What was asked of the allocator — the outstanding quantity, or the smaller
  /// amount the caller named.
  final Quantity requestedQty;

  final Quantity allocatedQty;

  /// Usable (non-expired, positive) warehouse stock at the moment of allocation.
  final Quantity availableQty;

  /// Stock that exists but may not ship because it has expired (G-E4). Reported so
  /// the form can say "there is stock, but not stock you may send" rather than
  /// "there is none".
  final Quantity? expiredQty;

  bool get isShort => allocatedQty < requestedQty;

  bool get isEmpty => allocatedQty.isZero;
}

/// Fills a `preparing` Delivery Order with the FEFO suggestion (§20.2, G-E3).
///
/// One pass over the parent request's positions:
///
/// 1. work out what is still outstanding (G-D2), excluding this document;
/// 2. read what the warehouse holds *now*;
/// 3. take from the nearest expiry first, splitting across batches as needed;
/// 4. clamp to whichever of the two is smaller, and report the shortfall.
///
/// The allocations replace whatever the document held, in **one** transaction: a
/// document holding half of yesterday's answer and half of today's is not a state
/// anybody should be able to observe, let alone ship.
///
/// Three things it deliberately does **not** do:
///
/// * **No ledger write.** Allocating is planning; stock leaves when the document
///   ships (spec §2.5).
/// * **No near-expiry confirmation.** `near_expiry_confirmed` is left `false` on
///   every allocation, even when FEFO's own answer is a batch inside its alert
///   window. Auto-ticking it would make G-E4's "konfirmasi eksplisit" a
///   formality — the whole point is that a person says so.
/// * **No expired batch, ever.** They are filtered out before the allocator sees
///   them and reported separately, so an officer is told the stock is there and
///   unusable rather than left wondering where it went (G-E7 is how it leaves).
///
/// Because FEFO's own answer is by definition the nearest-expiry-first one, the
/// allocations it produces never violate FEFO and never carry an override reason.
/// A reason only appears when somebody changes a batch by hand afterwards, which
/// is `UpdateDeliveryOrderLineUseCase`'s business.
class BuildFefoDeliveryAllocationUseCase {
  BuildFefoDeliveryAllocationUseCase({
    required this._deliveries,
    required MasterDataRepository master,
    required this._stock,
    DateTime Function()? clock,
  }) : _guards = DeliveryOrderGuards(master),
       _master = master,
       _clock = clock ?? _defaultClock;

  final DeliveryOrderRepository _deliveries;
  final MasterDataRepository _master;
  final DeliveryWarehouseStockReader _stock;
  final DeliveryOrderGuards _guards;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  /// [requestedByPrLineId] names how much to ship of each position. A position
  /// absent from the map gets its whole outstanding quantity, which is what the
  /// *Alokasikan FEFO* button asks for; an explicit zero skips it.
  Future<List<FefoAllocationOutcome>> call({
    required String actorUserId,
    required String deliveryOrderId,
    Map<String, Quantity>? requestedByPrLineId,
  }) async {
    final actor = await _guards.requireWarehouseActor(actorUserId);
    final warehouse = await _guards.requireWarehouseLocation();
    final nowUtc = _clock().toUtc();

    return _deliveries.runInTransaction(() async {
      final order = await _deliveries.getById(deliveryOrderId);
      if (order == null) {
        throw DeliveryOrderNotFoundFailure(
          'Surat Jalan tidak ditemukan.',
          doId: deliveryOrderId,
        );
      }
      _guards.requireStatus(
        order: order,
        expected: DeliveryOrderStatus.preparing,
      );
      _guards.requireTransition(
        actor: actor,
        order: order,
        to: DeliveryOrderStatus.shipped,
      );

      final positions = await _deliveries.purchaseRequestPositions(order.prId);
      // Excluding this document: what it currently holds is about to be replaced,
      // so counting it would shrink the room the new allocation has.
      final previouslyShipped = await _deliveries.cumulativeShippedByPrLine(
        prId: order.prId,
        excludeDoId: deliveryOrderId,
      );

      final allocations = <DeliveryAllocation>[];
      final outcomes = <FefoAllocationOutcome>[];

      for (final position in positions) {
        final alreadyShipped =
            previouslyShipped[position.prLineId] ?? Quantity.zero();
        final outstanding = DeliveryQuantityPolicy.remaining(
          requestedQty: position.requestedQty,
          cumulativeShippedQty: alreadyShipped,
        );

        final asked = requestedByPrLineId?[position.prLineId] ?? outstanding;
        if (!asked.isPositive) continue;
        if (asked > outstanding) {
          // G-D2, refused rather than clamped: a caller asking for more than the
          // order has left is a caller working from a stale screen, and quietly
          // sending less than it asked for would hide that.
          throw DeliveryQuantityExceedsRequestedFailure(
            'Jumlah kirim ${position.itemName} melebihi sisa permintaan '
            '(${outstanding.formatWithUnit(position.unit)}).',
            prLineId: position.prLineId,
            requested: position.requestedQty,
            alreadyShipped: alreadyShipped,
            attempted: asked,
          );
        }

        final item = await _guards.requireHistoricalItem(
          doId: deliveryOrderId,
          itemId: position.itemId,
        );

        final outcome = item.hasExpiry
            ? await _allocateBatched(
                position: position,
                item: item,
                warehouseLocationId: warehouse.id,
                asked: asked,
                nowUtc: nowUtc,
                into: allocations,
              )
            : await _allocateUnbatched(
                position: position,
                warehouseLocationId: warehouse.id,
                asked: asked,
                into: allocations,
              );
        outcomes.add(outcome);
      }

      final replaced = await _deliveries.replacePreparingLines(
        doId: deliveryOrderId,
        allocations: allocations,
      );
      if (!replaced) _guards.concurrentUpdate(order);

      return List<FefoAllocationOutcome>.unmodifiable(outcomes);
    });
  }

  /// An expiry-tracked position: FEFO across the batches the warehouse holds.
  Future<FefoAllocationOutcome> _allocateBatched({
    required ShipmentProgressInput position,
    required MasterItem item,
    required String warehouseLocationId,
    required Quantity asked,
    required DateTime nowUtc,
    required List<DeliveryAllocation> into,
  }) async {
    final candidates = await _stock.batchCandidates(
      warehouseLocationId: warehouseLocationId,
      itemId: position.itemId,
    );
    final usable = DeliveryExpiryPolicy.usableCandidates(
      candidates: candidates,
      nowUtc: nowUtc,
    );
    final available = Quantity.sum(
      usable.map((candidate) => candidate.availableQty),
    );
    final expired = Quantity.sum(
      DeliveryExpiryPolicy.expiredCandidates(
        candidates: candidates,
        nowUtc: nowUtc,
      ).map((candidate) => candidate.availableQty),
    );

    // Clamp rather than fail. `DeliveryFefoPolicy.allocate` refuses to return a
    // partial answer — which is right for "allocate exactly this much" — so the
    // clamp happens here, where the shortfall can be reported next to the item it
    // concerns instead of aborting the other eight positions.
    final target = Quantity.min(asked, available);
    if (target.isPositive) {
      final allocated = DeliveryFefoPolicy.allocate(
        prLineId: position.prLineId,
        itemId: position.itemId,
        candidates: usable,
        qty: target,
        nowUtc: nowUtc,
      );
      if (allocated == null) {
        // Only reachable if the balance moved between the two reads above; the
        // honest answer is then that there is not enough.
        throw InsufficientWarehouseStockFailure(
          'Stok warehouse untuk ${item.name} berubah saat alokasi. '
          'Muat ulang halaman lalu coba lagi.',
          itemId: position.itemId,
          available: available,
          requested: target,
        );
      }
      into.addAll(allocated);
    }

    return FefoAllocationOutcome(
      prLineId: position.prLineId,
      sku: position.sku,
      itemName: position.itemName,
      unit: position.unit,
      requestedQty: asked,
      allocatedQty: target,
      availableQty: available,
      expiredQty: expired.isPositive ? expired : null,
    );
  }

  /// A position without expiry: one allocation, no batch, no FEFO (G-E2).
  Future<FefoAllocationOutcome> _allocateUnbatched({
    required ShipmentProgressInput position,
    required String warehouseLocationId,
    required Quantity asked,
    required List<DeliveryAllocation> into,
  }) async {
    final available = await _stock.unbatchedBalance(
      warehouseLocationId: warehouseLocationId,
      itemId: position.itemId,
    );
    final target = Quantity.min(asked, available);
    if (target.isPositive) {
      into.add(
        DeliveryAllocation(
          prLineId: position.prLineId,
          itemId: position.itemId,
          qty: target,
        ),
      );
    }

    return FefoAllocationOutcome(
      prLineId: position.prLineId,
      sku: position.sku,
      itemName: position.itemName,
      unit: position.unit,
      requestedQty: asked,
      allocatedQty: target,
      availableQty: available,
    );
  }

  /// The batch candidates and the outstanding quantity of every position of a
  /// document, as the allocation form needs them.
  ///
  /// A read-only companion to [call], and it lives on the same use case because the
  /// two must agree about what "available" and "outstanding" mean: a form that
  /// computed them its own way would offer maxima the allocator then refused.
  Future<List<DeliveryLineDraft>> drafts({
    required String deliveryOrderId,
    DateTime? asOfUtc,
  }) async {
    final warehouse = await _guards.requireWarehouseLocation();
    final nowUtc = (asOfUtc ?? _clock()).toUtc();

    final order = await _deliveries.getById(deliveryOrderId);
    if (order == null) {
      throw DeliveryOrderNotFoundFailure(
        'Surat Jalan tidak ditemukan.',
        doId: deliveryOrderId,
      );
    }

    final progress = await _deliveries.shipmentProgress(
      prId: order.prId,
      doId: deliveryOrderId,
    );
    final lines = await _deliveries.lineReferences(deliveryOrderId);

    final drafts = <DeliveryLineDraft>[];
    for (final entry in progress) {
      final item = await _master.itemById(entry.itemId);
      final hasExpiry = item?.hasExpiry ?? false;

      // An expiry-tracked item ships from its batches; one without expiry ships
      // from a single non-batch balance and has no picker to draw (G-E2).
      final candidates = hasExpiry
          ? await _stock.batchCandidates(
              warehouseLocationId: warehouse.id,
              itemId: entry.itemId,
            )
          : const <DeliveryBatchCandidate>[];
      final available = hasExpiry
          ? DeliveryExpiryPolicy.usableTotal(
              candidates: candidates,
              nowUtc: nowUtc,
            )
          : await _stock.unbatchedBalance(
              warehouseLocationId: warehouse.id,
              itemId: entry.itemId,
            );

      drafts.add(
        DeliveryLineDraft(
          prLineId: entry.prLineId,
          itemId: entry.itemId,
          sku: entry.sku,
          itemName: entry.itemName,
          unit: entry.unit,
          hasExpiry: hasExpiry,
          expiryAlertDays: item?.expiryAlertDays ?? 0,
          progress: entry,
          allocations: lines
              .where((line) => line.prLineId == entry.prLineId)
              .map(
                (line) => DeliveryAllocation(
                  lineId: line.id,
                  prLineId: line.prLineId,
                  itemId: line.itemId,
                  batchId: line.batchId,
                  batchNo: candidates
                      .where((candidate) => candidate.batchId == line.batchId)
                      .map((candidate) => candidate.batchNo)
                      .firstOrNull,
                  expiryDate: candidates
                      .where((candidate) => candidate.batchId == line.batchId)
                      .map((candidate) => candidate.expiryDate)
                      .firstOrNull,
                  qty: line.shippedQty,
                  fefoOverrideReason: line.fefoOverrideReason,
                  nearExpiryConfirmed: line.nearExpiryConfirmed,
                  nearExpiryNote: line.nearExpiryNote,
                ),
              )
              .toList(growable: false),
          availableQty: available,
          candidates: candidates,
        ),
      );
    }
    return List<DeliveryLineDraft>.unmodifiable(drafts);
  }
}
