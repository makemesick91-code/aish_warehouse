/// The row shapes the reporting DAO reads and the reporting domain consumes.
///
/// ### Why these live in the domain rather than beside the DAO
///
/// They are plain data — ids, strings, milli-units, `DateTime`s — with no drift
/// type anywhere in them, and [ReportingRepository]'s recap methods return them.
/// Declaring them next to the queries would put a `db/daos/` import in the domain's
/// own contract, which is exactly the layering the application's architecture tests
/// forbid: a use case must be constructible without a database.
///
/// The DAO imports this file instead. That direction is the one already established
/// by `core/db/seed/development_seed.dart` and `core/session/acting_user_providers.dart`,
/// both of which reach into feature code — the database layer may know about domain
/// shapes; the domain may not know about the database.
///
/// Quantities are still **milli-units** here (Q-4). They become [Quantity] in
/// `DriftReportingRepository`, which is the only place that knows the scale.
library;

import '../../../../core/enums/app_enums.dart';

/// One ledger row, exactly as the reporting engine needs it.
///
/// A hand-rolled class rather than drift's [StockMovement] for one reason: it
/// carries `syncStatus` as the enum and quantity as raw milli-units, and it is the
/// only movement shape the reporting stack passes around — so nothing above the
/// repository has to know that two different row classes describe the same table.
class ReportMovementRawRow {
  const ReportMovementRawRow({
    required this.id,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.syncStatus,
    required this.itemId,
    required this.batchId,
    required this.fromLocationId,
    required this.toLocationId,
    required this.qtyMilliUnits,
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
  final int qtyMilliUnits;
  final StockMovementType movementType;
  final String? refDocType;
  final String? refDocId;
  final String actorUserId;
  final String? note;
  final String? reversalOfMovementId;
}

/// One `(document header, document line)` pair of a Stok Opname recap.
class OpnameRecapRawRow {
  const OpnameRecapRawRow({
    required this.opnameId,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.periodYear,
    required this.periodWeek,
    required this.status,
    required this.countedBy,
    required this.reviewedBy,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.submittedAtUtc,
    required this.reviewedAtUtc,
    required this.syncStatus,
    required this.lineId,
    required this.itemId,
    required this.batchId,
    required this.systemQtyMilliUnits,
    required this.countedQtyMilliUnits,
    required this.differenceMilliUnits,
    required this.lineNote,
  });

  final String opnameId;
  final String docNumber;
  final String branchId;
  final String roomId;
  final int periodYear;
  final int periodWeek;
  final String status;
  final String countedBy;
  final String? reviewedBy;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? submittedAtUtc;
  final DateTime? reviewedAtUtc;
  final SyncStatus syncStatus;
  final String? lineId;
  final String? itemId;
  final String? batchId;
  final int? systemQtyMilliUnits;
  final int? countedQtyMilliUnits;
  final int? differenceMilliUnits;
  final String? lineNote;
}

/// One `(header, line)` pair of a Purchase Request recap.
class PurchaseRequestRecapRawRow {
  const PurchaseRequestRecapRawRow({
    required this.prId,
    required this.docNumber,
    required this.branchId,
    required this.status,
    required this.requestedBy,
    required this.neededDate,
    required this.headerNote,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.submittedAtUtc,
    required this.processingAtUtc,
    required this.syncStatus,
    required this.lineId,
    required this.itemId,
    required this.suggestedQtyMilliUnits,
    required this.requestedQtyMilliUnits,
    required this.lineNote,
  });

  final String prId;
  final String docNumber;
  final String branchId;
  final String status;
  final String requestedBy;
  final DateTime? neededDate;
  final String? headerNote;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? submittedAtUtc;
  final DateTime? processingAtUtc;
  final SyncStatus syncStatus;
  final String? lineId;
  final String? itemId;
  final int? suggestedQtyMilliUnits;
  final int? requestedQtyMilliUnits;
  final String? lineNote;
}

/// One `(header, line)` pair of a Delivery Order recap.
class DeliveryOrderRecapRawRow {
  const DeliveryOrderRecapRawRow({
    required this.doId,
    required this.docNumber,
    required this.prId,
    required this.prDocNumber,
    required this.branchId,
    required this.status,
    required this.preparedBy,
    required this.shippedBy,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.shippedAtUtc,
    required this.headerNote,
    required this.syncStatus,
    required this.lineId,
    required this.prLineId,
    required this.itemId,
    required this.batchId,
    required this.shippedQtyMilliUnits,
    required this.fefoOverrideReason,
    required this.nearExpiryConfirmed,
    required this.nearExpiryNote,
  });

  final String doId;
  final String docNumber;
  final String prId;
  final String prDocNumber;
  final String branchId;
  final String status;
  final String preparedBy;
  final String? shippedBy;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? shippedAtUtc;
  final String? headerNote;
  final SyncStatus syncStatus;
  final String? lineId;
  final String? prLineId;
  final String? itemId;
  final String? batchId;
  final int? shippedQtyMilliUnits;
  final String? fefoOverrideReason;
  final bool? nearExpiryConfirmed;
  final String? nearExpiryNote;
}

/// One `(header, line)` pair of a Good Receipt recap, plus whatever Retur the
/// receipt has.
class GoodReceiptRecapRawRow {
  const GoodReceiptRecapRawRow({
    required this.grId,
    required this.docNumber,
    required this.doId,
    required this.doDocNumber,
    required this.prId,
    required this.prDocNumber,
    required this.branchId,
    required this.status,
    required this.receivedBy,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.postedAtUtc,
    required this.syncStatus,
    required this.returnDocNumber,
    required this.returnStatus,
    required this.lineId,
    required this.doLineId,
    required this.itemId,
    required this.batchId,
    required this.shippedQtyMilliUnits,
    required this.receivedQtyMilliUnits,
    required this.lineStatus,
    required this.rejectReason,
  });

  final String grId;
  final String docNumber;
  final String doId;
  final String doDocNumber;
  final String prId;
  final String prDocNumber;
  final String branchId;
  final String status;
  final String receivedBy;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? postedAtUtc;
  final SyncStatus syncStatus;
  final String? returnDocNumber;
  final String? returnStatus;
  final String? lineId;
  final String? doLineId;
  final String? itemId;
  final String? batchId;
  final int? shippedQtyMilliUnits;
  final int? receivedQtyMilliUnits;
  final String? lineStatus;
  final String? rejectReason;
}

/// One `(header, line)` pair of a Distribusi recap.
class DistributionRecapRawRow {
  const DistributionRecapRawRow({
    required this.distributionId,
    required this.docNumber,
    required this.branchId,
    required this.status,
    required this.distributedBy,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.postedAtUtc,
    required this.headerNote,
    required this.syncStatus,
    required this.lineId,
    required this.roomId,
    required this.itemId,
    required this.batchId,
    required this.qtyMilliUnits,
    required this.fefoOverrideReason,
  });

  final String distributionId;
  final String docNumber;
  final String branchId;
  final String status;
  final String distributedBy;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? postedAtUtc;
  final String? headerNote;
  final SyncStatus syncStatus;
  final String? lineId;
  final String? roomId;
  final String? itemId;
  final String? batchId;
  final int? qtyMilliUnits;
  final String? fefoOverrideReason;
}

/// One `(header, line)` pair of a Pemakaian recap.
class ConsumptionRecapRawRow {
  const ConsumptionRecapRawRow({
    required this.consumptionId,
    required this.docNumber,
    required this.branchId,
    required this.roomId,
    required this.status,
    required this.createdBy,
    required this.postedBy,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.postedAtUtc,
    required this.headerNote,
    required this.syncStatus,
    required this.lineId,
    required this.itemId,
    required this.batchId,
    required this.qtyMilliUnits,
    required this.lineNote,
  });

  final String consumptionId;
  final String docNumber;
  final String branchId;
  final String roomId;
  final String status;
  final String createdBy;
  final String? postedBy;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? postedAtUtc;
  final String? headerNote;
  final SyncStatus syncStatus;
  final String? lineId;
  final String? itemId;
  final String? batchId;
  final int? qtyMilliUnits;
  final String? lineNote;
}

/// One `(header, line)` pair of a Pemusnahan recap.
class DisposalRecapRawRow {
  const DisposalRecapRawRow({
    required this.disposalId,
    required this.docNumber,
    required this.sourceLocationId,
    required this.status,
    required this.createdBy,
    required this.postedBy,
    required this.reason,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.postedAtUtc,
    required this.syncStatus,
    required this.lineId,
    required this.itemId,
    required this.batchId,
    required this.qtyMilliUnits,
    required this.lineNote,
  });

  final String disposalId;
  final String docNumber;
  final String sourceLocationId;
  final String status;
  final String createdBy;
  final String? postedBy;
  final String reason;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? postedAtUtc;
  final SyncStatus syncStatus;
  final String? lineId;
  final String? itemId;
  final String? batchId;
  final int? qtyMilliUnits;
  final String? lineNote;
}

/// One `(header, line)` pair of a Retur recap.
class GoodsReturnRecapRawRow {
  const GoodsReturnRecapRawRow({
    required this.goodsReturnId,
    required this.docNumber,
    required this.grId,
    required this.grDocNumber,
    required this.doDocNumber,
    required this.prDocNumber,
    required this.branchId,
    required this.status,
    required this.createdBy,
    required this.shippedBy,
    required this.receivedBy,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.shippedAtUtc,
    required this.receivedAtUtc,
    required this.branchNote,
    required this.warehouseNote,
    required this.syncStatus,
    required this.lineId,
    required this.itemId,
    required this.batchId,
    required this.qtyMilliUnits,
    required this.rejectReasonSnapshot,
  });

  final String goodsReturnId;
  final String docNumber;
  final String grId;
  final String grDocNumber;
  final String doDocNumber;
  final String prDocNumber;
  final String branchId;
  final String status;
  final String createdBy;
  final String? shippedBy;
  final String? receivedBy;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? shippedAtUtc;
  final DateTime? receivedAtUtc;
  final String? branchNote;
  final String? warehouseNote;
  final SyncStatus syncStatus;
  final String? lineId;
  final String? itemId;
  final String? batchId;
  final int? qtyMilliUnits;
  final String? rejectReasonSnapshot;
}
