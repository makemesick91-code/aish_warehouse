import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../delivery/domain/repositories/delivery_order_repository.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../../../purchase_request/domain/repositories/purchase_request_repository.dart';
import '../models/good_receipt_models.dart';
import '../repositories/good_receipt_repository.dart';
import 'good_receipt_guards.dart';

/// `Mulai Pemeriksaan` — snapshots one shipped Delivery Order into a `checking`
/// Good Receipt (§24.1, G-G1).
///
/// Everything happens in **one** database transaction, and the order is chosen so
/// that nothing is written until everything has been checked:
///
/// ```
///  1. load the actor, refuse an inactive or non-branch-head account
///  2. load the shipment, guard `shipped`                          (G-G1)
///  3. load the request, verify the branch is the actor's          (G-G1)
///  4. refuse a shipment that already has a receipt                (G-G1)
///  5. read every allocation without a join — refuse an empty one
///  6. verify item and batch references resolve                   (G-E1/G-E2)
///  7. insert the header and the whole snapshot together
///  8. re-read the receipt's lines and verify the set matches      (§11)
/// ```
///
/// **Nothing about stock happens here.** No movement, no balance, no status change on
/// the shipment or the request. Spec §2.5 credits the branch when the receipt is
/// *posted*, and creating the checklist is the branch head opening a document — the
/// goods are on the counter either way.
///
/// ### Concurrency
///
/// Two branch heads (or one, twice) can both read "no receipt yet" and both insert.
/// The unique index on `good_receipts.do_id` lets exactly one through and the
/// repository turns the other into [GoodReceiptAlreadyExistsFailure]; because the
/// whole thing is one transaction, the loser leaves no orphan lines behind. The read
/// in step 4 exists to produce the *helpful* message in the ordinary case, not to be
/// the guard — a check-then-act pair never is.
class CreateGoodReceiptUseCase {
  CreateGoodReceiptUseCase({
    required this._receipts,
    required this._deliveries,
    required this._requests,
    required MasterDataRepository master,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _guards = GoodReceiptGuards(master),
       _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final GoodReceiptRepository _receipts;
  final DeliveryOrderRepository _deliveries;
  final PurchaseRequestRepository _requests;
  final GoodReceiptGuards _guards;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  Future<GoodReceipt> call({
    required String actorUserId,
    required String deliveryOrderId,
  }) async {
    // 1. Outside the transaction: an inactive account is not a concurrency question,
    // and refusing early keeps the message precise.
    final actor = await _guards.requireBranchHeadActor(actorUserId);

    return _receipts.runInTransaction(() async {
      // 2. The shipment.
      final order = await _deliveries.getById(deliveryOrderId);
      if (order == null) {
        throw DeliveryOrderNotFoundFailure(
          'Surat Jalan tidak ditemukan.',
          doId: deliveryOrderId,
        );
      }
      _guards.requireDeliveryOrderEligible(order);

      // 3. The request, for the branch it was raised by. A shipment's destination is
      // its Purchase Request's branch — `delivery_orders` carries no `branch_id`, on
      // purpose, so there is only one place that fact lives.
      final request = await _requests.getById(order.prId);
      if (request == null) {
        throw HistoricalDeliveryReferenceMissingFailure(
          'Surat Jalan tidak dapat diperiksa karena Purchase Request-nya tidak '
          'ditemukan. Hubungi administrator.',
          entity: 'purchase_requests',
          id: order.prId,
          doId: order.id,
        );
      }
      _guards.requireBranchMatches(
        actor: actor,
        documentBranchId: request.branchId,
      );
      _guards.requirePurchaseRequestReceivable(request);

      // 4. One DO, one GR. The friendly path; the unique index is the guard.
      final existing = await _receipts.findByDeliveryOrder(order.id);
      if (existing != null) {
        throw GoodReceiptAlreadyExistsFailure(
          'Surat Jalan ${order.docNumber} sudah memiliki Good Receipt '
          '${existing.docNumber}. Lanjutkan pemeriksaan yang ada.',
          doId: order.id,
          grId: existing.id,
        );
      }

      // 5. Every allocation, read without a join so a broken reference is reported
      // rather than silently dropped — a receipt that snapshots one line fewer than
      // the shipment would credit the branch short with nobody told.
      final allocations = await _deliveries.lineReferences(order.id);
      _guards.requireShipmentNotEmpty(
        doId: order.id,
        docNumber: order.docNumber,
        lines: allocations,
      );

      // 6. Item and batch references. Checked before anything is written, so a
      // shipment resting on a physically missing row produces a failure instead of a
      // receipt that cannot be posted.
      for (final allocation in allocations) {
        final item = await _guards.requireHistoricalItem(
          // The receipt does not exist yet, so a reference failure is reported
          // against the shipment it would have snapshotted.
          grId: order.id,
          itemId: allocation.itemId,
        );
        await _guards.requireBatchConsistency(
          grId: order.id,
          item: item,
          batchId: allocation.batchId,
        );
      }

      // 7. Header and snapshot together. `received_qty` starts at the shipped
      // quantity — the branch head is confirming a delivery, not entering it from
      // scratch — and every line starts `pending`, which is what G-G2 then requires
      // to be resolved.
      final receipt = await _receipts.createChecking(
        // `TMP-GR-{uuid}`: minting a server-shaped `GR-{cabang}-{date}-{seq}`
        // offline would collide across devices, and every branch receives on its own
        // (G-Y4).
        docNumber: 'TMP-GR-${_newId()}',
        deliveryOrderId: order.id,
        receivedBy: actor.id,
        createdAtUtc: _clock().toUtc(),
        lines: allocations
            .map(
              (allocation) => GoodReceiptLineSnapshot(
                doLineId: allocation.id,
                itemId: allocation.itemId,
                batchId: allocation.batchId,
                shippedQty: allocation.shippedQty,
              ),
            )
            .toList(growable: false),
      );

      // 8. The snapshot must mirror the shipment exactly — same count, same ids. A
      // set comparison rather than a count, because two lines swapped for two others
      // would pass a count and fail here.
      _guards.requireLineSetMatchesShipment(
        grId: receipt.id,
        expectedDoLineIds: allocations.map((allocation) => allocation.id),
        loadedDoLineIds: (await _receipts.lineReferences(
          receipt.id,
        )).map((line) => line.doLineId),
      );

      return receipt;
    });
  }
}
