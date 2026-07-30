/// The typed layer between the repository and the report builders.
///
/// It exists so a builder never touches a drift row and never a raw milli-unit: by
/// the time a row reaches [StockLocationReportRow] or [GoodReceiptRecapRow] every
/// quantity is a [Quantity] and every master reference has already been resolved —
/// or explicitly resolved to `null`, which is a fact the builder must render rather
/// than a lookup it should retry.
library;

import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import 'reporting_models.dart';

/// One ledger row in domain terms.
///
/// The reporting counterpart of `StockMovement`, and deliberately not that class:
/// it carries [Quantity] rather than milli-units, and it is what
/// [LedgerBalanceEngine] signs. Nothing above the repository sees a scale.
class ReportLedgerMovement {
  const ReportLedgerMovement({
    required this.id,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.syncStatus,
    required this.itemId,
    required this.batchId,
    required this.fromLocationId,
    required this.toLocationId,
    required this.qty,
    required this.movementType,
    required this.refDocType,
    required this.refDocId,
    required this.actorUserId,
    required this.note,
    required this.reversalOfMovementId,
  });

  final String id;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final SyncStatus syncStatus;
  final String itemId;
  final String? batchId;
  final String? fromLocationId;
  final String? toLocationId;

  /// Always strictly positive — the ledger's own CHECK. Direction is carried by
  /// the two location columns, never by the sign (§2.2).
  final Quantity qty;

  final StockMovementType movementType;
  final String? refDocType;
  final String? refDocId;
  final String actorUserId;
  final String? note;
  final String? reversalOfMovementId;

  /// What this row does to [locationId]'s balance: `+qty` into it, `−qty` out of
  /// it, zero when it does not touch that location at all.
  ///
  /// A transfer touches two locations and is therefore signed **twice**, once per
  /// side — which is exactly why a per-location report may not net it into a single
  /// row (§18).
  Quantity signedDeltaFor(String locationId) {
    final isIncoming = toLocationId == locationId;
    final isOutgoing = fromLocationId == locationId;
    if (isIncoming && !isOutgoing) return qty;
    if (isOutgoing && !isIncoming) return -qty;
    // `from == to` is refused by a CHECK on `stock_movements`, so both-true is
    // unreachable on a healthy row; answering zero rather than asserting keeps a
    // corrupt row from crashing a report somebody is trying to read.
    return Quantity.zero();
  }

  bool touches(String locationId) =>
      fromLocationId == locationId || toLocationId == locationId;
}

/// Every master row a report needs, keyed by id, **archived and inactive rows
/// included** (§51).
///
/// Lookups return `null` rather than throwing: a reference that is physically gone
/// is a warning on the report, not a reason to withhold a quantity the ledger is
/// certain about.
class ReportMasterData {
  const ReportMasterData({
    required this.items,
    required this.categories,
    required this.batches,
    required this.locations,
    required this.branches,
    required this.rooms,
    required this.users,
  });

  const ReportMasterData.empty()
    : items = const <String, MasterItem>{},
      categories = const <String, MasterCategory>{},
      batches = const <String, MasterBatch>{},
      locations = const <String, MasterLocation>{},
      branches = const <String, MasterBranch>{},
      rooms = const <String, MasterRoom>{},
      users = const <String, MasterUser>{};

  final Map<String, MasterItem> items;
  final Map<String, MasterCategory> categories;
  final Map<String, MasterBatch> batches;
  final Map<String, MasterLocation> locations;
  final Map<String, MasterBranch> branches;
  final Map<String, MasterRoom> rooms;
  final Map<String, MasterUser> users;

  MasterItem? item(String? id) => id == null ? null : items[id];

  MasterCategory? category(String? id) => id == null ? null : categories[id];

  MasterBatch? batch(String? id) => id == null ? null : batches[id];

  MasterLocation? location(String? id) => id == null ? null : locations[id];

  MasterBranch? branch(String? id) => id == null ? null : branches[id];

  MasterRoom? room(String? id) => id == null ? null : rooms[id];

  MasterUser? user(String? id) => id == null ? null : users[id];

  /// `Anestesi Lokal` or the historical fallback.
  String itemLabel(String? id) => item(id)?.name ?? ReportLabels.historicalItem;

  String skuLabel(String? id) => item(id)?.sku ?? ReportLabels.notApplicable;

  String unitLabel(String? id) => item(id)?.unit ?? '';

  String categoryLabel(String? id) =>
      category(id)?.name ?? ReportGroup.unresolvedCategoryName;

  String batchLabel(String? id) => id == null
      ? ReportLabels.notApplicable
      : (batch(id)?.batchNo ?? ReportLabels.historicalBatch);

  String userLabel(String? id) => id == null
      ? ReportLabels.notApplicable
      : (user(id)?.fullName ?? ReportLabels.historicalUser);

  String branchLabel(String? id) => id == null
      ? ReportLabels.notApplicable
      : (branch(id)?.code ?? ReportLabels.historicalBranch);

  String roomLabel(String? id) => id == null
      ? ReportLabels.notApplicable
      : (room(id)?.name ?? ReportLabels.historicalRoom);

  String locationLabel(String? id) => id == null
      ? ReportLabels.notApplicable
      : (location(id)?.name ?? ReportLabels.historicalLocation);

  /// The category of an item, resolved through the item. `null` when either hop
  /// is missing, which is what puts the row in the *Kategori historis* group
  /// rather than dropping it.
  MasterCategory? categoryOfItem(String? itemId) =>
      category(item(itemId)?.categoryId);
}

/// Everything one report reads, gathered in one pass.
///
/// A single object rather than a handful of parameters, because the *set* is the
/// unit of integrity: [ReportingRepository] verifies that the movements it loaded
/// are exactly the ones the id query listed, and hands the pair over together so a
/// builder cannot be handed a half-loaded source.
class ReportLedgerSource {
  const ReportLedgerSource({
    required this.movements,
    required this.master,
    this.warnings = const <String>[],
  });

  /// Sorted `createdAtUtc ASC, id ASC` by the repository, so a running balance is
  /// the same on every run (§18).
  final List<ReportLedgerMovement> movements;

  final ReportMasterData master;

  /// Historical-reference notes gathered while resolving master data.
  final List<String> warnings;
}

/// Everything one **document recap** reads, gathered in one pass.
///
/// Generic over the raw row type because the eight recaps differ only in that type:
/// each holds its document rows, the ledger movements those documents posted, and
/// the historical master data needed to name what the ids point at. Eight
/// near-identical classes would be eight places for the integrity contract to drift.
class ReportRecapSource<T> {
  const ReportRecapSource({
    required this.rows,
    required this.movements,
    required this.master,
    this.warnings = const <String>[],
  });

  /// One entry per document *line*, header repeated. A document with no lines
  /// appears once with its line columns null — see the DAO's note on why the line
  /// join is a LEFT one.
  final List<T> rows;

  /// The movements those documents posted, already sorted. Empty for a recap over
  /// documents that have not posted anything yet, which is an ordinary state.
  final List<ReportLedgerMovement> movements;

  final ReportMasterData master;
  final List<String> warnings;
}

/// How far each Purchase Request has actually been fulfilled, in ledger terms.
///
/// ### Why this is assembled rather than queried
///
/// A Purchase Request posts **nothing**. §2.5 is explicit — a PR has no stock
/// effect — so `movementsForDocuments(refDocType: 'PR')` would return an empty list
/// on a healthy database, and a recap built from it would show every request as
/// entirely unfulfilled. What actually fulfils a request is a chain of three other
/// documents: a Delivery Order ships, a Good Receipt accepts, a Retur sends back.
///
/// So the use case loads those three recaps at the same scope and hands their
/// mappings here. The three id maps are what let a `shipment` movement stamped with
/// a Delivery Order's id be attributed to the request that Delivery Order came from
/// — the ledger names the document that moved the stock, and only the document
/// tables know which request it belongs to (§25).
class PurchaseRequestFulfilmentSource {
  const PurchaseRequestFulfilmentSource({
    required this.deliveryOrderToPr,
    required this.goodReceiptToPr,
    required this.goodsReturnToPr,
    required this.shipmentMovements,
    required this.receiptMovements,
    required this.returnMovements,
  });

  const PurchaseRequestFulfilmentSource.empty()
    : deliveryOrderToPr = const <String, String>{},
      goodReceiptToPr = const <String, String>{},
      goodsReturnToPr = const <String, String>{},
      shipmentMovements = const <ReportLedgerMovement>[],
      receiptMovements = const <ReportLedgerMovement>[],
      returnMovements = const <ReportLedgerMovement>[];

  final Map<String, String> deliveryOrderToPr;
  final Map<String, String> goodReceiptToPr;
  final Map<String, String> goodsReturnToPr;

  /// `movement_type = shipment`, `ref_doc_type = DO`.
  final List<ReportLedgerMovement> shipmentMovements;

  /// `movement_type = good_receipt`, `ref_doc_type = GR`.
  final List<ReportLedgerMovement> receiptMovements;

  /// `movement_type = return`, `ref_doc_type = RET`.
  final List<ReportLedgerMovement> returnMovements;
}

// --- typed report rows -------------------------------------------------------

/// One position of the Stok Saat Ini report (§21).
class StockLocationReportRow {
  const StockLocationReportRow({
    required this.locationId,
    required this.locationName,
    required this.itemId,
    required this.batchId,
    required this.qty,
    required this.expiryDate,
    required this.expiryStatus,
    required this.isBelowMinimum,
    required this.minimum,
    required this.isHistorical,
  });

  final String locationId;
  final String locationName;
  final String itemId;
  final String? batchId;

  /// Ledger-derived, as of the report's cutoff. Never read from
  /// `stock_balances` (G-L4).
  final Quantity qty;

  final DateTime? expiryDate;
  final ReportExpiryStatus expiryStatus;

  /// Against `min_stock_branch` for a Gudang Cabang and `min_stock_room` for a
  /// room. Warehouse Pusat has no minimum in this schema, so the flag is always
  /// false there rather than measured against an invented threshold (§21).
  final bool isBelowMinimum;

  final Quantity? minimum;
  final bool isHistorical;
}

/// How close a batch is to its expiry date (G-E6, G-E8).
enum ReportExpiryStatus {
  expired('Kedaluwarsa'),
  nearExpiry('Segera kedaluwarsa'),
  safe('Aman'),

  /// The item does not track expiry at all, so the question does not apply.
  notTracked(ReportLabels.notApplicable);

  const ReportExpiryStatus(this.label);

  final String label;
}

/// One movement line of a Kartu Stok, with the balance after it (§22).
class StockCardReportRow {
  const StockCardReportRow({
    required this.movement,
    required this.incoming,
    required this.outgoing,
    required this.balanceAfter,
    required this.documentNumber,
    required this.isHistorical,
  });

  final ReportLedgerMovement movement;

  /// Exactly one of the two is non-null. A zero in the other column would read as
  /// *"nothing moved"* rather than *"this row is not that direction"* (§22).
  final Quantity? incoming;
  final Quantity? outgoing;

  /// Opening balance plus every signed delta up to and including this row.
  final Quantity balanceAfter;

  final String documentNumber;
  final bool isHistorical;
}

/// One batch position of the Laporan Kedaluwarsa (G-E8).
class ExpiryReportRow {
  const ExpiryReportRow({
    required this.locationId,
    required this.locationName,
    required this.itemId,
    required this.batchId,
    required this.batchNo,
    required this.expiryDate,
    required this.daysRemaining,
    required this.status,
    required this.qty,
    required this.isHistorical,
  });

  final String locationId;
  final String locationName;
  final String itemId;
  final String? batchId;
  final String batchNo;
  final DateTime expiryDate;

  /// Negative once the date has passed — *"sisa hari"* the specification asks for,
  /// counted in whole operational days.
  final int daysRemaining;

  final ReportExpiryStatus status;
  final Quantity qty;
  final bool isHistorical;
}

/// One counted position of the Rekap Opname (§24).
class OpnameRecapRow {
  const OpnameRecapRow({
    required this.opnameId,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.periodLabel,
    required this.status,
    required this.countedBy,
    required this.reviewedBy,
    required this.createdAtUtc,
    required this.submittedAtUtc,
    required this.reviewedAtUtc,
    required this.itemId,
    required this.batchId,
    required this.systemQty,
    required this.countedQty,
    required this.difference,
    required this.ledgerAdjustment,
    required this.note,
  });

  final String opnameId;
  final String docNumber;
  final String branchId;
  final String roomId;

  /// `2026-W31`.
  final String periodLabel;

  final StockOpnameStatus status;
  final String countedBy;
  final String? reviewedBy;
  final DateTime createdAtUtc;
  final DateTime? submittedAtUtc;
  final DateTime? reviewedAtUtc;
  final String? itemId;
  final String? batchId;

  /// Document figures — the snapshot the nurse counted against and what they
  /// counted (§3.5). Not stock effects.
  final Quantity? systemQty;
  final Quantity? countedQty;
  final Quantity? difference;

  /// The signed `opname_adjustment` the ledger actually recorded for this
  /// position, or `null` on a document that was never reviewed. Never inferred
  /// from [difference]: a draft has a difference and no movement, and inventing
  /// one would be the report asserting a posting that never happened (§24).
  final Quantity? ledgerAdjustment;

  final String? note;
}

/// One requested position of the Rekap Purchase Request (§25).
class PurchaseRequestRecapRow {
  const PurchaseRequestRecapRow({
    required this.prId,
    required this.docNumber,
    required this.branchId,
    required this.status,
    required this.neededDate,
    required this.requestedBy,
    required this.createdAtUtc,
    required this.submittedAtUtc,
    required this.processingAtUtc,
    required this.itemId,
    required this.suggestedQty,
    required this.requestedQty,
    required this.shippedQty,
    required this.acceptedQty,
    required this.returnedQty,
    required this.outstandingQty,
    required this.note,
  });

  final String prId;
  final String docNumber;
  final String branchId;
  final PurchaseRequestStatus status;
  final DateTime? neededDate;
  final String requestedBy;
  final DateTime createdAtUtc;
  final DateTime? submittedAtUtc;
  final DateTime? processingAtUtc;
  final String? itemId;

  /// Document intent (§25). Neither is a stock effect and neither is ever read
  /// from the ledger.
  final Quantity? suggestedQty;
  final Quantity? requestedQty;

  /// Ledger figures: `shipment` movements of this request's Delivery Orders,
  /// `good_receipt` movements of their receipts, `return` movements of the
  /// returns raised from those receipts.
  final Quantity shippedQty;
  final Quantity acceptedQty;
  final Quantity returnedQty;

  /// `max(0, requested − shipped)`, in exact fixed point. Defined against
  /// *shipped* rather than *accepted* on purpose: what is still owed is what the
  /// Warehouse has not sent, and goods rejected on arrival are the Retur
  /// workflow's business rather than an open order (§25).
  final Quantity outstandingQty;

  final String? note;
}

/// One shipped position of the Rekap Delivery Order (§26).
class DeliveryOrderRecapRow {
  const DeliveryOrderRecapRow({
    required this.doId,
    required this.docNumber,
    required this.prDocNumber,
    required this.branchId,
    required this.status,
    required this.preparedBy,
    required this.shippedBy,
    required this.createdAtUtc,
    required this.shippedAtUtc,
    required this.itemId,
    required this.batchId,
    required this.shippedQty,
    required this.nearExpiryConfirmed,
    required this.fefoOverrideReason,
    required this.note,
    required this.integrityWarning,
  });

  final String doId;
  final String docNumber;
  final String prDocNumber;
  final String branchId;
  final DeliveryOrderStatus status;
  final String preparedBy;
  final String? shippedBy;
  final DateTime createdAtUtc;
  final DateTime? shippedAtUtc;
  final String? itemId;
  final String? batchId;

  /// From the ledger. Zero on a `preparing` document — nothing has left the
  /// warehouse yet, and printing the allocation as though it had would overstate
  /// what was sent (§26).
  final Quantity shippedQty;

  final bool nearExpiryConfirmed;
  final String? fefoOverrideReason;
  final String? note;

  /// Set when the row describes something that should be impossible — an expired
  /// batch that was nonetheless shipped. Surfaced rather than hidden: G-E4 blocks
  /// it going forward, so a historical row that carries it is data somebody needs
  /// to see (§26).
  final String? integrityWarning;
}

/// One checked position of the Rekap Penerimaan dan Selisih GR (§27).
class GoodReceiptRecapRow {
  const GoodReceiptRecapRow({
    required this.grId,
    required this.docNumber,
    required this.doDocNumber,
    required this.prDocNumber,
    required this.branchId,
    required this.status,
    required this.receivedBy,
    required this.createdAtUtc,
    required this.postedAtUtc,
    required this.itemId,
    required this.batchId,
    required this.shippedQty,
    required this.receivedQty,
    required this.acceptedQty,
    required this.shortageQty,
    required this.rejectedQty,
    required this.discrepancy,
    required this.rejectReason,
    required this.returnStatusLabel,
  });

  final String grId;
  final String docNumber;
  final String doDocNumber;
  final String prDocNumber;
  final String branchId;
  final GoodReceiptStatus status;
  final String receivedBy;
  final DateTime createdAtUtc;
  final DateTime? postedAtUtc;
  final String? itemId;
  final String? batchId;

  /// Document snapshot of what the shipment said it contained.
  final Quantity shippedQty;

  /// Document decision — what the branch head keyed in.
  final Quantity receivedQty;

  /// Ledger: the `good_receipt` movement that actually credited the branch store.
  /// Zero on a `checking` document and on every rejected line (G-G5).
  final Quantity acceptedQty;

  /// `shipped − received` on a **checked** line. A shortage is a delivery
  /// discrepancy, never a return: nothing came back, it never arrived (§27).
  final Quantity shortageQty;

  /// The whole shipped quantity of a **rejected** line — what goes home.
  final Quantity rejectedQty;

  final GoodReceiptDiscrepancyFilter discrepancy;
  final String? rejectReason;

  /// The Retur this receipt produced, if any: `Belum dibuat`, `Draft`,
  /// `Dikirim`, `Diterima`.
  final String returnStatusLabel;
}

/// One distributed position of the Rekap Distribusi (§28).
class DistributionRecapRow {
  const DistributionRecapRow({
    required this.distributionId,
    required this.docNumber,
    required this.branchId,
    required this.status,
    required this.distributedBy,
    required this.createdAtUtc,
    required this.postedAtUtc,
    required this.sourceLocationId,
    required this.roomId,
    required this.itemId,
    required this.batchId,
    required this.qty,
    required this.fefoOverrideReason,
  });

  final String distributionId;
  final String docNumber;
  final String branchId;
  final DistributionStatus status;
  final String distributedBy;
  final DateTime createdAtUtc;
  final DateTime? postedAtUtc;

  /// The Gudang Cabang the stock left, taken from the movement rather than from
  /// the document — the document names a branch, the ledger names the shelf.
  final String? sourceLocationId;

  final String? roomId;
  final String? itemId;
  final String? batchId;

  /// From the ledger. Zero on a draft.
  final Quantity qty;

  final String? fefoOverrideReason;
}

/// One consumed position of the Rekap Pemakaian (§29).
class ConsumptionRecapRow {
  const ConsumptionRecapRow({
    required this.consumptionId,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.status,
    required this.createdBy,
    required this.createdAtUtc,
    required this.postedAtUtc,
    required this.itemId,
    required this.batchId,
    required this.qty,
    required this.note,
  });

  final String consumptionId;
  final String docNumber;
  final String branchId;
  final String roomId;
  final ConsumptionStatus status;

  /// The nurse. There is deliberately no patient anywhere in this model (§29).
  final String createdBy;

  final DateTime createdAtUtc;
  final DateTime? postedAtUtc;
  final String? itemId;
  final String? batchId;
  final Quantity qty;
  final String? note;
}

/// One destroyed position of the Rekap Pemusnahan (§30).
class DisposalRecapRow {
  const DisposalRecapRow({
    required this.disposalId,
    required this.docNumber,
    required this.sourceLocationId,
    required this.branchId,
    required this.status,
    required this.createdBy,
    required this.postedBy,
    required this.reason,
    required this.createdAtUtc,
    required this.postedAtUtc,
    required this.itemId,
    required this.batchId,
    required this.expiryDate,
    required this.daysExpired,
    required this.qty,
    required this.note,
  });

  final String disposalId;
  final String docNumber;
  final String sourceLocationId;

  /// Resolved from the source location. `null` for Warehouse Pusat, which belongs
  /// to no branch — that is the schema's CHECK, not a missing value.
  final String? branchId;

  final DisposalStatus status;
  final String createdBy;
  final String? postedBy;
  final String reason;
  final DateTime createdAtUtc;
  final DateTime? postedAtUtc;
  final String? itemId;
  final String? batchId;
  final DateTime? expiryDate;

  /// Whole operational days between the expiry date and the posting. `null` when
  /// either is unknown; negative would mean stock destroyed before it expired,
  /// which is legitimate and printed as it is.
  final int? daysExpired;

  final Quantity qty;
  final String? note;
}

/// One returned position of the Rekap Retur (§31).
class GoodsReturnRecapRow {
  const GoodsReturnRecapRow({
    required this.goodsReturnId,
    required this.docNumber,
    required this.grDocNumber,
    required this.doDocNumber,
    required this.prDocNumber,
    required this.branchId,
    required this.status,
    required this.createdBy,
    required this.shippedBy,
    required this.receivedBy,
    required this.createdAtUtc,
    required this.shippedAtUtc,
    required this.receivedAtUtc,
    required this.itemId,
    required this.batchId,
    required this.documentQty,
    required this.receivedQty,
    required this.rejectReason,
    required this.branchNote,
    required this.warehouseNote,
  });

  final String goodsReturnId;
  final String docNumber;
  final String grDocNumber;
  final String doDocNumber;
  final String prDocNumber;
  final String branchId;
  final GoodsReturnStatus status;
  final String createdBy;
  final String? shippedBy;
  final String? receivedBy;
  final DateTime createdAtUtc;
  final DateTime? shippedAtUtc;
  final DateTime? receivedAtUtc;
  final String? itemId;
  final String? batchId;

  /// The immutable snapshot on the return line — what is in the box.
  final Quantity documentQty;

  /// Ledger: the `return` movement that credited the Warehouse. Zero until a
  /// Petugas Warehouse confirms arrival, which is why a `shipped` return shows a
  /// quantity in the box and nothing on the shelf (§31).
  final Quantity receivedQty;

  final String rejectReason;
  final String? branchNote;
  final String? warehouseNote;
}
