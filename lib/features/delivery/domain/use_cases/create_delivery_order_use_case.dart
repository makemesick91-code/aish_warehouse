import 'package:uuid/uuid.dart';

import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../../../purchase_request/domain/repositories/purchase_request_repository.dart';
import '../models/delivery_models.dart';
import '../repositories/delivery_order_repository.dart';
import 'delivery_order_guards.dart';

/// Raises a `preparing` Delivery Order against a Purchase Request (§20.1, G-D1).
///
/// ```
/// PR submitted  ──create DO──▶  PR processing + DO preparing   (one transaction)
/// PR processing ──create DO──▶  PR processing + DO preparing
/// ```
///
/// The document is created **empty**, and that is a deliberate flow choice rather
/// than an omission. Auto-allocating during creation would mean a failure to find
/// stock for one item aborted the whole document, and the officer would be left
/// with nothing — while the honest answer is usually "eight of the nine items can
/// ship today". So creation is the cheap, always-possible step, and
/// `BuildFefoDeliveryAllocationUseCase` fills it in behind the *Alokasikan FEFO*
/// button (§27.2), where a per-item shortfall can be shown next to the item it
/// concerns.
///
/// **Nothing here touches the ledger.** A `preparing` document is an intention:
/// stock leaves the warehouse when it is shipped (spec §2.5), not when it is
/// prepared. No movement is written, no balance changes, and G-D2's cumulative
/// total deliberately does not count this document until it posts.
///
/// The `submitted → processing` transition is the one write outside the Delivery
/// Order's own tables, and it has to share the transaction: a document that exists
/// against a request nobody has started processing would be invisible to G-D1 on
/// the next attempt, and a request moved to `processing` with no document to show
/// for it would block the branch's active-order slot for nothing (G-P4).
class CreateDeliveryOrderUseCase {
  CreateDeliveryOrderUseCase({
    required this._deliveries,
    required this._requests,
    required MasterDataRepository master,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _guards = DeliveryOrderGuards(master),
       _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final DeliveryOrderRepository _deliveries;
  final PurchaseRequestRepository _requests;
  final DeliveryOrderGuards _guards;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  Future<DeliveryOrder> call({
    required String actorUserId,
    required String purchaseRequestId,
    String? note,
  }) async {
    // Outside the transaction on purpose: an inactive or wrong-role actor is not a
    // concurrency question, and refusing before opening one keeps the failure
    // cheap and the message precise.
    final actor = await _guards.requireWarehouseActor(actorUserId);

    // The warehouse must exist before a shipment is prepared against it. Checked
    // here as well as at ship time so an officer is told at the start rather than
    // after filling a whole document in (G-D3).
    await _guards.requireWarehouseLocation();

    return _deliveries.runInTransaction(() async {
      final request = await _requests.getById(purchaseRequestId);
      if (request == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan.',
          prId: purchaseRequestId,
        );
      }
      _guards.requirePurchaseRequestEligible(request);

      // Set integrity before acting. The requested positions are read through a
      // join on `items`, so a position whose item row is gone would be absent
      // rather than reported — and a shipment prepared against an order that is
      // quietly one line short would look complete when it is not (G-D5).
      final positions = await _deliveries.purchaseRequestPositions(
        purchaseRequestId,
      );
      final storedItemIds = await _requests.lineItemIds(purchaseRequestId);
      if (storedItemIds.isEmpty) {
        throw PurchaseRequestLineNotFoundFailure(
          'Purchase Request ${request.docNumber} tidak memiliki baris barang, '
          'sehingga tidak ada yang dapat dikirim.',
          lineId: '',
        );
      }
      if (positions.length != storedItemIds.length) {
        throw HistoricalDeliveryReferenceMissingFailure(
          'Purchase Request tidak dapat dikirim karena sebagian baris historis '
          'tidak dapat dimuat. Hubungi administrator.',
          entity: 'purchase_request_lines',
          id: purchaseRequestId,
          doId: '',
        );
      }

      // Every requested item must still resolve. Deactivated is fine — a
      // withdrawn item is still exactly what was ordered — but a row that is
      // physically gone cannot be shipped and must not be guessed at.
      for (final position in positions) {
        await _guards.requireHistoricalItem(doId: '', itemId: position.itemId);
      }

      final now = _clock().toUtc();
      final needsProcessing = request.status == PurchaseRequestStatus.submitted;
      if (needsProcessing) {
        // Ordered against the submission, on UTC instants, never as text (§8.2).
        DocumentTimestampPolicy.requireProcessingNotBeforeSubmit(
          documentId: purchaseRequestId,
          submittedAtUtc: request.submittedAt,
          processingAtUtc: now,
        );
      }

      return _deliveries.createPreparing(
        // `TMP-DO-{uuid}` until a sync backend assigns the final
        // `DO-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number offline
        // would collide across the devices a warehouse ships from.
        docNumber: 'TMP-DO-${_newId()}',
        prId: purchaseRequestId,
        preparedBy: actor.id,
        note: DeliveryOrderGuards.normalizeReason(note),
        allocations: const <DeliveryAllocation>[],
        markRequestProcessing: needsProcessing,
        // Both instants come from the injected clock, so the shipment's later
        // `shipped_at >= created_at` check compares two values from one source
        // (T-7).
        createdAtUtc: now,
        processingAtUtc: now,
      );
    });
  }
}
