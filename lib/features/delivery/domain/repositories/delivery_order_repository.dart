import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../models/delivery_models.dart';
import '../services/delivery_quantity_policy.dart';

/// Delivery Order persistence, expressed in domain terms.
///
/// The shape of this contract encodes the guardrails:
///
/// * There is no `update(DeliveryOrder)` and no `delete`. The only writes are the
///   specific, guarded operations below, so an arbitrary mutation of a shipped
///   document is not expressible (G-S2).
/// * There is no writer for `received` at all. That transition belongs to Good
///   Receipt, and offering it here would be a button waiting to be wired up
///   before the document that justifies it exists.
/// * The one status change, [markShippedAtomically], performs the ledger posting,
///   the document transition and the Purchase Request transition **together**.
///   There is deliberately no way to do one without the others: three separate
///   methods would be three chances to commit a shipment whose stock never left,
///   or stock that left with no document to show for it.
/// * Reads come in scoped pairs — `…ForWarehouse` and `…ForBranch`. The branch
///   variants carry both the branch predicate and the status predicate inside the
///   query, so a document that is not this branch's, or has not shipped yet, is
///   never fetched rather than being fetched and then withheld.
///
/// Quantities cross this boundary as [Quantity]; the milli-unit integers stay
/// behind the implementation (Q-4).
abstract interface class DeliveryOrderRepository {
  /// Runs [action] in a single database transaction.
  ///
  /// The shipment owns exactly one of these. Every write it performs — movements,
  /// balances, the document status and timestamps, and the Purchase Request
  /// transition that may follow — happens inside it, so a failure on the last
  /// allocation rolls the first one back.
  Future<T> runInTransaction<T>(Future<T> Function() action);

  /// Creates a `preparing` header, optionally with its first allocations, in one
  /// transaction.
  ///
  /// [markRequestProcessing] is what makes G-D1 atomic: when the parent request is
  /// still `submitted`, the same transaction that inserts the document moves it to
  /// `processing`. Returns the header, or throws when the guarded Purchase Request
  /// transition matched no rows because another officer got there first.
  Future<DeliveryOrder> createPreparing({
    required String docNumber,
    required String prId,
    required String preparedBy,
    String? note,
    required List<DeliveryAllocation> allocations,
    bool markRequestProcessing = false,
    DateTime? createdAtUtc,
    DateTime? processingAtUtc,
  });

  Future<DeliveryOrder?> getById(String doId);

  /// Unscoped detail read, for **use cases only**.
  ///
  /// A use case loads the document and then applies its guards, producing a
  /// precise failure that names it — the right answer for somebody attempting a
  /// write. Presentation code must not use this: by the time a widget could apply
  /// that check, the foreign document has already been handed to the UI layer.
  /// Screens use [getForBranch] / [watchForBranch] instead, and the architecture
  /// test enforces the split.
  Future<DeliveryOrderDetail?> getDetail(String doId);

  /// The document for a warehouse reader, which is not branch-scoped by design.
  ///
  /// Separate from [getDetail] so the unscoped read a *screen* performs is a
  /// named, searchable decision rather than the same method the use cases use.
  Future<DeliveryOrderDetail?> getForWarehouse(String doId);

  Stream<DeliveryOrderDetail?> watchForWarehouse(String doId);

  /// The document, but only if it belongs to [branchId] **and** has actually been
  /// shipped. Both predicates are part of the query.
  Future<DeliveryOrderDetail?> getForBranch({
    required String doId,
    required String branchId,
  });

  /// Live version of [getForBranch]. A stream opened for one branch can never
  /// emit another branch's document, or a draft, whatever happens underneath it.
  Stream<DeliveryOrderDetail?> watchForBranch({
    required String doId,
    required String branchId,
  });

  /// Read authorization, answered without reading the document.
  ///
  /// Returns `null` when [doId] does not name a live document within the scope
  /// asked for — one answer for "no such document", for "another branch's" and for
  /// "not shipped yet", so a caller cannot probe which ids exist elsewhere.
  /// [branchId] is `null` for the warehouse, whose scope is every branch.
  Future<DeliveryOrderAccessScope?> findAccessScope({
    required String doId,
    String? branchId,
    Set<DeliveryOrderStatus> statuses = const {},
  });

  Stream<List<DeliveryOrderSummary>> watchListForWarehouse(
    DeliveryOrderFilter filter,
  );

  /// The branch's incoming shipments, newest first. Always restricted to
  /// `shipped`/`received`, whatever [statuses] asks for.
  Stream<List<DeliveryOrderSummary>> watchListForBranch({
    required String branchId,
    Set<DeliveryOrderStatus> statuses = const {},
  });

  Future<List<DeliveryOrderSummary>> listForWarehouse(
    DeliveryOrderFilter filter,
  );

  /// Every Delivery Order raised against one Purchase Request, newest first.
  ///
  /// A list, because one request may ship in parts (spec §2.3) and the progress a
  /// form shows is the sum over all of them.
  Future<List<DeliveryOrderSummary>> listByPurchaseRequest(String prId);

  Stream<List<DeliveryOrderSummary>> watchByPurchaseRequest(String prId);

  /// G-D2's authority: how much of each requested position has already **left the
  /// warehouse**, counting only `shipped`/`received` documents.
  ///
  /// [excludeDoId] leaves the document being posted out, so the ship path can add
  /// its own quantities rather than double-counting them.
  Future<Map<String, Quantity>> cumulativeShippedByPrLine({
    required String prId,
    String? excludeDoId,
  });

  /// What one document itself allocates, per requested position. Status-agnostic:
  /// the ship path reads it for a `preparing` document, which
  /// [cumulativeShippedByPrLine] excludes by design.
  Future<Map<String, Quantity>> allocatedByPrLine(String doId);

  /// The per-position shipment picture of a request, with [doId]'s own
  /// allocations counted separately (G-D2/G-D5).
  ///
  /// [doId] may be `null`, which is how the "create a new shipment" screen asks
  /// what is still outstanding before anything has been allocated.
  Future<List<ShipmentProgress>> shipmentProgress({
    required String prId,
    String? doId,
  });

  /// The requested positions of a request, as the progress calculation and the
  /// allocation form need them.
  ///
  /// Read through a join on `items`, so a position whose item row is physically
  /// gone is **absent** from the result rather than reported. That is what
  /// [purchaseRequestLineIds] exists to detect.
  Future<List<ShipmentProgressInput>> purchaseRequestPositions(String prId);

  /// The id of every live requested position, read **without joining** `items`.
  ///
  /// The honest count [purchaseRequestPositions] is checked against. A join can
  /// hide a row; a plain select cannot. The difference matters because a request
  /// that has quietly lost a position is a request a shipment could complete —
  /// and G-D5 would then mark it `shipped` on the strength of an order that is
  /// short a line nobody was told about.
  Future<List<String>> purchaseRequestLineIds(String prId);

  /// Live allocation rows of one document, read **without joining** items or
  /// batches.
  ///
  /// The joined read can hide a row whose item or batch is physically gone; this
  /// cannot. It is the honest inventory the ship path checks the joined read
  /// against, so a corrupt reference is reported rather than silently reducing the
  /// shipment by one line.
  Future<List<DeliveryLineReference>> lineReferences(String doId);

  /// One allocation by id, again without any join.
  ///
  /// Returns the identifiers only — including the `do_id` the caller then uses to
  /// load and authorise the document. A read that returned the joined line would
  /// hand a screen the item name and quantity of a shipment it has not been
  /// cleared for; this returns nothing anybody would want to display.
  Future<DeliveryLineReference?> lineReferenceById(String lineId);

  /// Replaces every allocation of a `preparing` document. `false` when the
  /// document is no longer editable.
  Future<bool> replacePreparingLines({
    required String doId,
    required List<DeliveryAllocation> allocations,
  });

  /// Quantity, batch and expiry audit of one allocation on a `preparing`
  /// document. Cannot reach `pr_line_id` or `item_id` (G-D4).
  Future<bool> updatePreparingLine({
    required String lineId,
    required Quantity shippedQty,
    String? batchId,
    String? fefoOverrideReason,
    bool nearExpiryConfirmed = false,
    String? nearExpiryNote,
  });

  /// Appends one allocation to a `preparing` document. `null` when it is no
  /// longer editable.
  Future<DeliveryLineReference?> addPreparingLine({
    required String doId,
    required DeliveryAllocation allocation,
  });

  /// Soft-deletes one allocation of a `preparing` document. `false` when the
  /// guard rejected it.
  Future<bool> removePreparingLine(String lineId);

  /// The header note of a `preparing` document.
  Future<bool> updatePreparingNote({required String doId, String? note});

  /// `preparing → shipped`, together with the Purchase Request transition that may
  /// follow from it.
  ///
  /// Returns `false` when the guarded update matched no rows — the document was
  /// shipped by somebody else between the read and the write — which the caller
  /// turns into a concurrency failure and a full rollback.
  ///
  /// [completesRequest] is decided by the caller from quantities it re-read inside
  /// the transaction, not by this method: the arithmetic is a domain rule
  /// (G-D2/G-D5) and belongs above the repository.
  Future<bool> markShipped({
    required String doId,
    required String shippedBy,
    required DateTime shippedAtUtc,
    required String prId,
    required bool completesRequest,
  });

  /// Soft-deletes a `preparing` document; shipped and received ones are refused
  /// (G-A5/G-S2).
  Future<bool> removePreparing(String doId);

  /// Everything the Surat Jalan prints.
  ///
  /// Scoped the same way the detail reads are: [branchId] pins it to one branch
  /// and restricts it to shipped documents, `null` widens it to the warehouse's
  /// view, which includes drafts and marks them as such.
  ///
  /// [warehouseName] is supplied rather than resolved here, because "which
  /// warehouse" is a master-data question and this repository deliberately knows
  /// only about Delivery Orders. The caller already had to resolve the location to
  /// read balances, so passing the name costs nothing and keeps the dependency
  /// out.
  Future<WaybillViewModel?> waybill({
    required String doId,
    String? branchId,
    required String warehouseName,
    required DateTime printedAtUtc,
  });
}

/// One allocation as the integrity checks see it: identifiers and a quantity, no
/// joined master data at all.
///
/// Deliberately not [DeliveryOrderLine]. That model carries an item name, a unit
/// and an expiry date, all of which come from joins — and a join is exactly what
/// can make a broken reference *disappear* instead of reporting it. The set
/// integrity check compares these ids against the joined read, so a line whose
/// item row is gone shows up as a difference rather than as one fewer line.
class DeliveryLineReference {
  const DeliveryLineReference({
    required this.id,
    required this.doId,
    required this.prLineId,
    required this.itemId,
    this.batchId,
    required this.shippedQty,
    this.fefoOverrideReason,
    this.nearExpiryConfirmed = false,
    this.nearExpiryNote,
  });

  final String id;
  final String doId;
  final String prLineId;
  final String itemId;
  final String? batchId;
  final Quantity shippedQty;
  final String? fefoOverrideReason;
  final bool nearExpiryConfirmed;
  final String? nearExpiryNote;

  /// The uniqueness key of an allocation within one document, as the two partial
  /// unique indexes define it.
  String get allocationKey => '$prLineId|${batchId ?? ''}';
}

/// Convenience filter for the warehouse list — every status it shows.
const Set<DeliveryOrderStatus> warehouseDeliveryStatuses = {
  DeliveryOrderStatus.preparing,
  DeliveryOrderStatus.shipped,
  DeliveryOrderStatus.received,
};
