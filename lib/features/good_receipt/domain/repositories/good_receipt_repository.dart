import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../models/good_receipt_models.dart';

/// Good Receipt persistence, expressed in domain terms.
///
/// The shape of this contract encodes the guardrails:
///
/// * There is no `update(GoodReceipt)` and no `delete`. The only writes are the
///   specific, guarded operations below, so an arbitrary mutation of a posted
///   receipt is not expressible (G-S2).
/// * There is no writer that removes a line. *"Hapus yang tidak sesuai"* means
///   [decideRejected] (G-G4), and the audit trail is the point.
/// * There is no writer that reaches `item_id`, `batch_id` or `shipped_qty`. Those
///   are the snapshot the shipment left, and editing them would make the ledger a
///   lie.
/// * The one status change, [postAtomically], performs the receipt transition, the
///   Delivery Order transition and the Purchase Request closure **together**.
///   There is deliberately no way to do one without the others: three separate
///   methods would be three chances to mark a shipment received with no stock to
///   show for it, or to close an order whose goods were never checked.
/// * Reads come in scoped pairs — `…ForWarehouse` and `…ForBranch`. The warehouse
///   variants carry a `posted`-only predicate inside the query and the branch ones
///   carry the branch predicate, so a receipt that is not this branch's, or has not
///   been posted, is never fetched rather than being fetched and then withheld.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers stay
/// behind the implementation (Q-4).
abstract interface class GoodReceiptRepository {
  /// Runs [action] in a single database transaction.
  ///
  /// The posting owns exactly one of these. Every write it performs — movements,
  /// balances, the receipt status and timestamp, the shipment transition and the
  /// request closure — happens inside it, so a failure on the last movement rolls
  /// the first one back.
  Future<T> runInTransaction<T>(Future<T> Function() action);

  /// Creates a `checking` header together with its whole line snapshot, in one
  /// transaction.
  ///
  /// One method rather than "insert header, then add lines", because every
  /// intermediate state is wrong: a receipt with no lines could be posted as an
  /// empty document, and a receipt missing one line would check in less than was
  /// sent. Throws [GoodReceiptAlreadyExistsFailure] when the unique index on
  /// `do_id` refuses — which is what makes two devices starting the same shipment
  /// produce exactly one receipt.
  Future<GoodReceipt> createChecking({
    required String docNumber,
    required String deliveryOrderId,
    required String receivedBy,
    required List<GoodReceiptLineSnapshot> lines,
    DateTime? createdAtUtc,
  });

  Future<GoodReceipt?> getById(String grId);

  /// G-G1's read half: the receipt of one shipment, or `null`.
  Future<GoodReceipt?> findByDeliveryOrder(String deliveryOrderId);

  /// Unscoped detail read, for **use cases only**.
  ///
  /// A use case loads the document and then applies its guards, producing a precise
  /// failure that names it — the right answer for somebody attempting a write.
  /// Presentation code must not use this: by the time a widget could apply that
  /// check, the foreign document has already been handed to the UI layer. Screens
  /// use [getForBranch] / [watchForBranch] instead, and the architecture test
  /// enforces the split.
  Future<GoodReceiptDetail?> getDetail(String grId);

  /// The receipt, but only if it belongs to [branchId]. The predicate is part of
  /// the query.
  Future<GoodReceiptDetail?> getForBranch({
    required String grId,
    required String branchId,
  });

  /// Live version of [getForBranch]. A stream opened for one branch can never emit
  /// another branch's receipt, whatever happens underneath it.
  Stream<GoodReceiptDetail?> watchForBranch({
    required String grId,
    required String branchId,
  });

  /// One posted receipt for a warehouse reader, which is not branch-scoped by
  /// design — but is restricted to `posted`.
  ///
  /// Separate from [getDetail] so the unscoped read a *screen* performs is a named,
  /// searchable decision rather than the same method the use cases use.
  Future<GoodReceiptDetail?> getForWarehouse(String grId);

  Stream<GoodReceiptDetail?> watchForWarehouse(String grId);

  /// Read authorization, answered without reading the document.
  ///
  /// Returns `null` when [grId] does not name a live receipt within the scope asked
  /// for — one answer for "no such receipt", for "another branch's" and for "not
  /// posted yet", so a caller cannot probe which ids exist elsewhere. [branchId] is
  /// `null` for the warehouse, whose scope is every branch.
  Future<GoodReceiptAccessScope?> findAccessScope({
    required String grId,
    String? branchId,
    Set<GoodReceiptStatus> statuses = const {},
  });

  /// The branch's own receipts, newest first. Always restricted to [branchId].
  Stream<List<GoodReceiptSummary>> watchListForBranch({
    required String branchId,
    Set<GoodReceiptStatus> statuses = const {},
  });

  Future<List<GoodReceiptSummary>> listForBranch({
    required String branchId,
    Set<GoodReceiptStatus> statuses = const {},
  });

  /// Posted receipts across every branch — the warehouse's read-only view.
  Stream<List<GoodReceiptSummary>> watchListForWarehouse(
    GoodReceiptFilter filter,
  );

  Future<List<GoodReceiptSummary>> listForWarehouse(GoodReceiptFilter filter);

  /// Shipments still waiting to be checked in: `shipped` Delivery Orders, with
  /// their `checking` receipt attached when one exists.
  ///
  /// [branchId] is `null` for the warehouse, which watches the same queue across
  /// every branch so it can see who is late (G-G6).
  Stream<List<GoodReceiptAwaitingDelivery>> watchAwaitingDeliveryOrders({
    String? branchId,
  });

  Future<List<GoodReceiptAwaitingDelivery>> awaitingDeliveryOrders({
    String? branchId,
  });

  /// The warehouse's selisih/retur queue — every position of every posted receipt
  /// that did not arrive complete (G-G3/G-G5).
  ///
  /// A derived read, not a table. Nothing here marks a return done, adds stock back
  /// to the warehouse or removes a row: the physical return is a later milestone's
  /// document, and offering a writer now would create exactly the phantom stock
  /// §17 forbids.
  Stream<List<GoodReceiptDiscrepancy>> watchWarehouseDiscrepancies(
    GoodReceiptFilter filter,
  );

  Future<List<GoodReceiptDiscrepancy>> warehouseDiscrepancies(
    GoodReceiptFilter filter,
  );

  /// Live receipt lines of one document, read **without joining** items or batches.
  ///
  /// The joined read can hide a row whose item or batch is physically gone; this
  /// cannot. It is the honest inventory the posting path checks the joined read
  /// against, so a corrupt reference is reported rather than silently reducing the
  /// receipt by one line.
  Future<List<GoodReceiptLineReference>> lineReferences(String grId);

  /// One receipt line by id, again without any join.
  ///
  /// Returns the identifiers and quantities only — including the `gr_id` the caller
  /// then uses to load and authorise the receipt. A read that returned the joined
  /// line would hand a screen the item name of a receipt it has not been cleared
  /// for.
  Future<GoodReceiptLineReference?> lineReferenceById(String lineId);

  /// The id of every live allocation of one shipment, read **without joining**
  /// anything.
  ///
  /// The honest set the receipt's own lines are checked against. A join can hide a
  /// row; a plain select cannot. The difference matters because a receipt that has
  /// quietly lost a line is a receipt that would check in less than was sent, with
  /// nobody told.
  Future<List<String>> deliveryOrderLineIds(String deliveryOrderId);

  /// `→ checked` with an accepted quantity (G-G2/G-G3). `false` when the guarded
  /// write matched no rows — the receipt is no longer `checking`, or the line is
  /// not on it.
  Future<bool> decideChecked({
    required String grId,
    required String lineId,
    required Quantity receivedQty,
  });

  /// `→ rejected` with a mandatory reason (G-G4). The row is never removed.
  Future<bool> decideRejected({
    required String grId,
    required String lineId,
    required String reason,
  });

  /// Back to `pending`, so a branch head can undo a decision while the receipt is
  /// still `checking`.
  Future<bool> resetDecision({required String grId, required String lineId});

  /// `checking → posted`, together with the shipment transition and the request
  /// closure that follow from it.
  ///
  /// Returns `false` when the guarded update matched no rows — the receipt was
  /// posted by somebody else between the read and the write, or a line is still
  /// `pending` — which the caller turns into a concurrency failure and a full
  /// rollback.
  ///
  /// [closeRequest] is decided by the caller from statuses it re-read inside the
  /// transaction, not by this method: which shipments count and whether they are all
  /// in is a domain rule (§23) and belongs above the repository.
  Future<bool> postAtomically({
    required String grId,
    required DateTime postedAtUtc,
    required String deliveryOrderId,
    required String prId,
    required bool closeRequest,
  });

  /// Every live Delivery Order of one Purchase Request, with its status — the input
  /// to the closure decision (§23).
  Future<List<GoodReceiptShipmentStatus>> shipmentDeliveryOrdersOf(String prId);
}

/// One line to snapshot when a receipt is created.
///
/// Deliberately not [GoodReceiptLine]: that model carries an item name, a unit and
/// an expiry date, all of which come from joins, and none of which is stored. What
/// a snapshot is, is exactly these five facts copied off the shipped allocation.
///
/// `receivedQty` defaults to the shipped quantity because that is what the branch
/// head is confirming: the common case is *"yes, all of it arrived"*, and starting
/// from zero would make every complete delivery a data-entry exercise.
class GoodReceiptLineSnapshot {
  const GoodReceiptLineSnapshot({
    required this.doLineId,
    required this.itemId,
    this.batchId,
    required this.shippedQty,
    Quantity? receivedQty,
  }) : receivedQty = receivedQty ?? shippedQty;

  final String doLineId;
  final String itemId;
  final String? batchId;
  final Quantity shippedQty;
  final Quantity receivedQty;
}

/// One receipt line as the integrity checks see it: identifiers, quantities and a
/// decision, no joined master data at all.
///
/// Deliberately not [GoodReceiptLine], for the reason [GoodReceiptLineSnapshot]
/// gives: that model's item name and expiry date come from joins, and a join is
/// exactly what can make a broken reference *disappear* instead of reporting it. The
/// set integrity check compares these ids against the joined read, so a line whose
/// item row is gone shows up as a difference rather than as one fewer line.
class GoodReceiptLineReference {
  const GoodReceiptLineReference({
    required this.id,
    required this.grId,
    required this.doLineId,
    required this.itemId,
    this.batchId,
    required this.shippedQty,
    required this.receivedQty,
    required this.lineStatus,
    this.rejectReason,
  });

  final String id;
  final String grId;
  final String doLineId;
  final String itemId;
  final String? batchId;
  final Quantity shippedQty;
  final Quantity receivedQty;
  final GoodReceiptLineStatus lineStatus;
  final String? rejectReason;

  bool get isPending => lineStatus.isPending;

  bool get isChecked => lineStatus.isChecked;

  bool get isRejected => lineStatus.isRejected;

  bool get isDecided => lineStatus.isDecided;

  Quantity get discrepancyQty => shippedQty - receivedQty;

  /// Whether this line will write a movement when the receipt posts (G-G5).
  bool get addsStock => lineStatus.addsStock && receivedQty.isPositive;
}

/// The status of one Delivery Order raised against a Purchase Request.
class GoodReceiptShipmentStatus {
  const GoodReceiptShipmentStatus({required this.doId, required this.status});

  final String doId;
  final DeliveryOrderStatus status;

  bool get isShipped => status.isShipped;

  bool get isReceived => status.isReceived;

  bool get isPreparing => status.isPreparing;
}

/// Convenience filter for the branch list — every status it shows.
const Set<GoodReceiptStatus> branchGoodReceiptStatuses = {
  GoodReceiptStatus.checking,
  GoodReceiptStatus.posted,
};
