import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/report_raw_rows.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';

/// Everything the reporting module reads and the one thing it writes.
///
/// ### Domain in, domain out
///
/// Not one method returns a drift row. `ReportMovementRawRow` and the eight
/// `…RecapRawRow` types are the DAO's vocabulary and stop at the implementation of
/// this interface — above it there are [ReportLedgerMovement]s, [Quantity]s and
/// `Master…` models. That boundary is what keeps a report builder testable without
/// a database and unable to reach one.
///
/// ### Integrity is this layer's job, not the builders'
///
/// Every load below verifies that the rows it returns are the rows the scope query
/// said exist (§35), and the two possible mismatches are treated as different kinds
/// of problem on purpose:
///
/// * **A movement is missing.** The quantity itself is gone, so no fallback can be
///   honest — [ReportLedgerIntegrityFailure] is thrown and no report is produced. A
///   stock report that quietly totalled less than the ledger would be worse than no
///   report at all.
/// * **A master reference is missing.** The quantity is still known; only its label
///   is not. The row survives with a *"Data historis tidak tersedia"* label and the
///   source carries a warning that every surface prints (§51).
///
/// ### The one writer
///
/// [insertExportLog] appends. There is deliberately no update, no delete and no
/// soft-delete anywhere in this interface: `export_logs` is an audit trail, and an
/// audit trail with an edit path is a log nobody can rely on (§42).
abstract interface class ReportingRepository {
  /// Turns a scope *type* plus the ids a screen chose into the resolved set of
  /// stock locations the report may read.
  ///
  /// Archived locations are included: a `branch_all` report still has to name the
  /// room an administrator tidied away, because the ledger rows against it did not
  /// disappear with it (§51).
  Future<ReportScope> resolveScope({
    required ReportScopeType scopeType,
    String? locationId,
    String? branchId,
  });

  /// One stock location, archived rows included. Used to revalidate a scope's
  /// location against [ReportAccessPolicy] before anything is read.
  Future<MasterLocation?> locationById(String id);

  Future<MasterCategory?> categoryById(String id);

  Future<MasterItem?> itemById(String id);

  Future<MasterBranch?> branchById(String id);

  Future<MasterRoom?> roomById(String id);

  Future<MasterUser?> userById(String id);

  /// The room whose stock lives at a `room` location — needed for G-L5's
  /// `CAB-01-R1` token.
  Future<MasterRoom?> roomOfLocation(MasterLocation location);

  /// Every ledger row the scope touches, with the master data needed to name it.
  ///
  /// Throws [ReportLedgerIntegrityFailure] when the detailed read comes back with
  /// fewer movements than the id query listed.
  Future<ReportLedgerSource> loadLedgerSource({
    required ReportScope scope,
    String? itemId,
    String? categoryId,
  });

  /// Document numbers for every `(ref_doc_type, ref_doc_id)` a movement list
  /// names, keyed by id.
  ///
  /// Soft-deleted documents are included, and unknown type codes simply produce no
  /// entry — the Kartu Stok then prints its fallback rather than a blank (§22).
  Future<Map<String, String>> resolveDocumentNumbers(
    Iterable<ReportLedgerMovement> movements,
  );

  /// [roomId] narrows to one room — the scope a Perawat runs this recap at, so the
  /// heading and the rows describe the same place (§16).
  Future<ReportRecapSource<OpnameRecapRawRow>> loadOpnameRecap({
    String? branchId,
    String? countedBy,
    String? roomId,
  });

  Future<ReportRecapSource<PurchaseRequestRecapRawRow>>
  loadPurchaseRequestRecap({String? branchId});

  Future<ReportRecapSource<DeliveryOrderRecapRawRow>> loadDeliveryOrderRecap({
    String? branchId,
  });

  Future<ReportRecapSource<GoodReceiptRecapRawRow>> loadGoodReceiptRecap({
    String? branchId,
  });

  Future<ReportRecapSource<DistributionRecapRawRow>> loadDistributionRecap({
    String? branchId,
  });

  Future<ReportRecapSource<ConsumptionRecapRawRow>> loadConsumptionRecap({
    String? branchId,
    String? createdBy,
    String? roomId,
  });

  /// Pemusnahan is scoped by **source location**, not by branch: `disposals` has no
  /// branch column, because the stock may have left Warehouse Pusat — which belongs
  /// to no branch at all (§30).
  ///
  /// A `null` [sourceLocationIds] means every location, which only a cross-branch or
  /// all-locations scope ever asks for.
  Future<ReportRecapSource<DisposalRecapRawRow>> loadDisposalRecap({
    Set<String>? sourceLocationIds,
  });

  Future<ReportRecapSource<GoodsReturnRecapRawRow>> loadGoodsReturnRecap({
    String? branchId,
  });

  // --- export audit ---------------------------------------------------------

  /// Appends one row for a file that has already been written (§36). The only
  /// writer in this interface.
  Future<ExportLog> insertExportLog({
    required ReportType reportType,
    required ReportFormat format,
    required ReportScopeType scopeType,
    String? locationId,
    String? categoryId,
    String? branchId,
    String? itemId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String exportedBy,
    required String fileName,
    required DateTime dataCutoffAtUtc,
    required String syncSummary,
    required int rowCount,
  });

  /// Every export ever recorded, newest first.
  ///
  /// Sorted on parsed `DateTime`s rather than by SQL, because `created_at` is
  /// ISO-8601 TEXT and a SQL `ORDER BY` on it is a lexical sort.
  Stream<List<ExportLog>> watchExportHistory();

  /// One person's exports, newest first.
  Stream<List<ExportLog>> watchExportHistoryOf(String userId);

  /// One person's most recent exports, read once.
  ///
  /// A `Future` rather than a stream, and deliberately: this feeds a dashboard
  /// card, which wants an answer rather than a subscription. A live query stream
  /// behind a small card keeps a subscription open on every screen that shows the
  /// home page, and an indeterminate progress indicator waiting on one is an
  /// animation that never ends — which is a real hazard, not only a test one.
  Future<List<ExportLog>> recentExportsOf(String userId, {int limit});

  /// Every export, read once — what the dashboard counters fold.
  Future<List<ExportLog>> listExportHistory();

  Future<ExportLog?> getExportLog(String id);

  /// One log with every id resolved to a label, archived rows included.
  Future<ExportLogDetail?> getExportLogDetail(String id);

  /// The same resolution for a whole list, in one pass rather than N.
  Future<List<ExportLogDetail>> resolveExportLogDetails(List<ExportLog> logs);
}
