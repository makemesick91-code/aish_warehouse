import '../../../../core/enums/app_enums.dart';
import '../repositories/good_receipt_repository.dart';
import 'good_receipt_state_policy.dart';

/// When a Purchase Request is finished (§23, PR `shipped → closed`).
///
/// A pure function of the shipments' statuses, so the same answer serves the
/// posting transaction and any screen that wants to say *"one more delivery to
/// go"*. Nothing here reads a clock or a repository: the caller supplies the
/// statuses it read **inside the transaction**, which is what makes two devices
/// posting the last two receipts produce exactly one closure.
///
/// ### Which documents count
///
/// Only `shipped` and `received` ones. A `preparing` Delivery Order has no shipment
/// ledger behind it — spec §2.5 posts on `shipped` — so it is not something anybody
/// is waiting to receive, and counting it would leave a request with a forgotten
/// draft open for ever. Soft-deleted documents are excluded by the query that
/// produced the list.
///
/// ### What does *not* prevent closure
///
/// Rejected positions and shortages do not. `closed` means the send-and-receive
/// cycle is over, not that everything arrived: the discrepancies stay on the
/// warehouse's selisih/retur queue as their own follow-up, and holding the request
/// open would conflate "the delivery process finished" with "the shortfall was
/// resolved" — two different pieces of work, the second of which has no document
/// yet.
abstract final class GoodReceiptClosurePolicy {
  /// The shipments a request is waiting on.
  static List<GoodReceiptShipmentStatus> shipmentsOf(
    Iterable<GoodReceiptShipmentStatus> shipments,
  ) => shipments
      .where(
        (shipment) => GoodReceiptStatePolicy.countsAsShipment(shipment.status),
      )
      .toList(growable: false);

  /// Whether posting the receipt of [currentDoId] leaves nothing outstanding.
  ///
  /// [currentDoId] is treated as **already received**, because it is: the caller is
  /// inside the transaction that is about to mark it so, and reading its status from
  /// the list would see the `shipped` value it still holds. Every *other* shipment
  /// has to be `received` already.
  ///
  /// Answers `false` for an empty list. A request with no shipment at all has nothing
  /// to have completed, and treating that as finished would close a document on the
  /// strength of an order that was never sent.
  static bool closesRequest({
    required Iterable<GoodReceiptShipmentStatus> shipments,
    required String currentDoId,
  }) {
    final relevant = shipmentsOf(shipments);
    if (relevant.isEmpty) return false;
    if (!relevant.any((shipment) => shipment.doId == currentDoId)) {
      // The shipment being received is not among the request's own — a reference the
      // caller's integrity checks should already have refused. Never close on it.
      return false;
    }
    return relevant.every(
      (shipment) => shipment.doId == currentDoId || shipment.isReceived,
    );
  }

  /// How many shipments are still `shipped` once [currentDoId] is received — what a
  /// screen shows as *"masih menunggu N pengiriman"*.
  static int outstandingAfter({
    required Iterable<GoodReceiptShipmentStatus> shipments,
    required String currentDoId,
  }) => shipmentsOf(shipments)
      .where((shipment) => shipment.doId != currentDoId && shipment.isShipped)
      .length;

  /// Whether the request's own status permits closure at all.
  ///
  /// Only `shipped`. A `processing` request still has positions the warehouse has
  /// not sent, so "every shipment received" says nothing about the order being
  /// finished — and `PurchaseRequestStatePolicy` lists no `processing → closed`
  /// transition for exactly that reason.
  static bool isClosable(PurchaseRequestStatus status) =>
      GoodReceiptStatePolicy.canClose(status);
}
