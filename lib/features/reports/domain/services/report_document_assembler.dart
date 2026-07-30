import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/models/master_models.dart';
import '../builders/consumption_recap_report_builder.dart';
import '../builders/delivery_order_recap_report_builder.dart';
import '../builders/disposal_recap_report_builder.dart';
import '../builders/distribution_recap_report_builder.dart';
import '../builders/expiry_report_builder.dart';
import '../builders/good_receipt_recap_report_builder.dart';
import '../builders/goods_return_recap_report_builder.dart';
import '../builders/opname_recap_report_builder.dart';
import '../builders/purchase_request_recap_report_builder.dart';
import '../builders/report_build_context.dart';
import '../builders/stock_card_report_builder.dart';
import '../builders/stock_location_report_builder.dart';
import '../models/report_source_models.dart';
import '../models/reporting_models.dart';
import '../repositories/reporting_repository.dart';
import 'report_access_policy.dart';
import 'report_filter_policy.dart';
import 'report_period_policy.dart';

/// A finished report, plus everything the export path needs to name and audit it.
class ReportBuildResult {
  const ReportBuildResult({
    required this.document,
    required this.request,
    required this.branch,
    required this.room,
    required this.category,
    required this.item,
  });

  final ReportDocument document;

  /// The **resolved** request — scope expanded to real location ids, period
  /// normalised. What the export log records.
  final ReportRequest request;

  /// Resolved master rows, archived ones included, for G-L5's file-name tokens.
  final MasterBranch? branch;
  final MasterRoom? room;
  final MasterCategory? category;
  final MasterItem? item;

  DateTime get cutoffUtc => document.header.generatedAtUtc;

  int get rowCount => document.rowCount;
}

/// The one path from *"a person asked for a report"* to a [ReportDocument].
///
/// ### Preview and export run exactly this code
///
/// Both use cases call [assemble], and that is the point (§36). The alternative —
/// export re-using the document a preview produced — would mean an export could
/// carry data that was current five minutes and one role change ago, and would make
/// the export log describe a snapshot nobody took. Building fresh costs a query and
/// buys an audit row that is true.
///
/// ### The order of the checks is the security design
///
/// 1. **Reload the actor** from the database. Role, branch and `is_active` all
///    change under an open session (O-8), and every decision below rests on the
///    stored row rather than on the session's claim about itself.
/// 2. **Resolve the scope's location** — needed before the access check, because
///    the check asks what *type* the location is and which branch owns it.
/// 3. **Access** ([ReportAccessPolicy]). Refuses first and says as little as
///    possible, so the form cannot be used to enumerate rooms (§52).
/// 4. **Filter validity** ([ReportFilterPolicy]). Only reached once access is
///    granted, which is why it can afford to be specific about what is wrong.
/// 5. **Capture the cutoff** from the injected clock — once, so the header, the
///    balances and `export_logs.data_cutoff_at` are the same instant.
/// 6. Load, verify set integrity, build.
///
/// Swapping steps 3 and 4 would leak: *"lokasi bukan ruangan"* on a location the
/// actor may not see confirms both that it exists and what it is.
class ReportDocumentAssembler {
  ReportDocumentAssembler({
    required ReportingRepository reporting,
    DateTime Function()? clock,
  }) : this._(reporting: reporting, clock: clock ?? _wallClock);

  ReportDocumentAssembler._({required this._reporting, required this._clock});

  /// The default "now". Injected in every test (T-7): the cutoff decides which
  /// movements are counted, which batches read as expired, and what the audit row
  /// says the data is *as of*.
  static DateTime _wallClock() => DateTime.now().toUtc();

  final ReportingRepository _reporting;
  final DateTime Function() _clock;

  Future<ReportBuildResult> assemble({
    required MasterUser actor,
    required ReportRequestDraft draft,
  }) async {
    // 2 — the location, archived rows included, before any decision about it.
    final location = draft.locationId == null
        ? null
        : await _reporting.locationById(draft.locationId!);

    // 3 — access. Deliberately before filter validation.
    final access = ReportAccessPolicy.forRequest(
      user: actor,
      reportType: draft.reportType,
      scopeType: draft.scopeType,
      locationType: location?.type,
      locationBranchId: location?.branchId,
      requestedBranchId: _effectiveBranchId(actor, draft),
    );
    if (access.isDenied) {
      throw ReportAccessDeniedFailure(
        'Anda tidak memiliki akses ke laporan ini.',
        reportType: draft.reportType,
        scopeType: draft.scopeType,
      );
    }

    final category = draft.filter.categoryId == null
        ? null
        : await _reporting.categoryById(draft.filter.categoryId!);
    final item = draft.filter.itemId == null
        ? null
        : await _reporting.itemById(draft.filter.itemId!);

    // 4 — shape of the question.
    ReportFilterPolicy.validate(
      reportType: draft.reportType,
      scopeType: draft.scopeType,
      filter: draft.filter,
      locationId: draft.locationId,
      location: location,
      category: category,
      item: item,
    );

    // 5 — one instant for the whole report.
    final cutoffUtc = _clock().toUtc();
    final period = ReportPeriodPolicy.forReport(
      reportType: draft.reportType,
      periodStart: draft.periodStart,
      periodEnd: draft.periodEnd,
    );

    final branchId = _effectiveBranchId(actor, draft);
    final scope = await _reporting.resolveScope(
      scopeType: draft.scopeType,
      locationId: draft.locationId,
      branchId: branchId,
    );
    final request = ReportRequest(
      reportType: draft.reportType,
      scope: scope,
      period: period,
      filter: draft.filter,
    );

    final branch = branchId == null
        ? null
        : await _reporting.branchById(branchId);
    final room = location == null
        ? null
        : await _reporting.roomOfLocation(location);

    final context = ReportBuildContext(
      request: request,
      generatedAtUtc: cutoffUtc,
      exportedByLabel: actor.fullName,
      scopeLabel: draft.scopeType.label,
      locationLabel: _locationLabel(
        scopeType: draft.scopeType,
        location: location,
        branch: branch,
      ),
      branchLabel: branch?.name ?? ReportLabels.allBranches,
      categoryLabel: category?.name ?? ReportLabels.allCategories,
      itemLabel: item == null
          ? ReportLabels.notApplicable
          : '${item.sku} · ${item.name}',
    );

    final document = await _build(
      actor: actor,
      draft: draft,
      request: request,
      context: context,
      // Only a `room` scope pins a recap to a room; every wider scope passes null
      // and the branch predicate alone decides (§16).
      scopedRoomId: draft.scopeType == ReportScopeType.room ? room?.id : null,
    );

    return ReportBuildResult(
      document: document,
      request: request,
      branch: branch,
      room: room,
      category: category,
      item: item,
    );
  }

  /// The branch a report's data is pinned to.
  ///
  /// A branch-scoped role always gets **their own**, whatever the draft says — the
  /// policy decides, not the form (§16). An unscoped role may pass one as a filter,
  /// which only removes rows they were already entitled to see.
  String? _effectiveBranchId(MasterUser actor, ReportRequestDraft draft) =>
      ReportAccessPolicy.requiresOwnBranch(actor.role)
      ? actor.branchId
      : draft.branchId;

  String _locationLabel({
    required ReportScopeType scopeType,
    required MasterLocation? location,
    required MasterBranch? branch,
  }) {
    if (location != null) return location.name;
    return switch (scopeType) {
      ReportScopeType.branchAll =>
        'Semua lokasi ${branch?.name ?? ReportLabels.historicalBranch}',
      ReportScopeType.crossBranch => ReportScopeType.crossBranch.label,
      ReportScopeType.allLocations => ReportLabels.allLocations,
      // The three single-location scopes cannot reach here: the filter policy
      // already refused a missing location.
      ReportScopeType.warehouse ||
      ReportScopeType.branchStore ||
      ReportScopeType.room => ReportLabels.historicalLocation,
    };
  }

  Future<ReportDocument> _build({
    required MasterUser actor,
    required ReportRequestDraft draft,
    required ReportRequest request,
    required ReportBuildContext context,
    String? scopedRoomId,
  }) async {
    final ownDocuments =
        ReportAccessPolicy.requiresOwnDocuments(
          role: actor.role,
          reportType: draft.reportType,
        )
        ? actor.id
        : null;
    // `null` for a cross-branch or all-locations recap, which is what makes those
    // reads span branches; anything else is the branch the policy pinned.
    final recapBranchId = request.scope.branchId;

    switch (draft.reportType) {
      case ReportType.stokLokasi:
        return StockLocationReportBuilder.build(
          source: await _loadLedger(request),
          context: context,
        );

      case ReportType.kadaluarsa:
        return ExpiryReportBuilder.build(
          source: await _loadLedger(request),
          context: context,
        );

      case ReportType.kartuStok:
        final source = await _loadLedger(request);
        return StockCardReportBuilder.build(
          source: source,
          context: context,
          // Both are guaranteed non-null: the filter policy refuses a Kartu Stok
          // without exactly one location and one item.
          locationId: request.scope.locationId!,
          itemId: request.filter.itemId!,
          documentNumbers: await _reporting.resolveDocumentNumbers(
            source.movements,
          ),
        );

      case ReportType.rekapOpname:
        return OpnameRecapReportBuilder.build(
          source: await _reporting.loadOpnameRecap(
            branchId: recapBranchId,
            countedBy: ownDocuments,
            roomId: scopedRoomId,
          ),
          context: context,
        );

      case ReportType.rekapPr:
        return PurchaseRequestRecapReportBuilder.build(
          source: await _reporting.loadPurchaseRequestRecap(
            branchId: recapBranchId,
          ),
          fulfilment: await _loadFulfilment(recapBranchId),
          context: context,
        );

      case ReportType.rekapDo:
        return DeliveryOrderRecapReportBuilder.build(
          source: await _reporting.loadDeliveryOrderRecap(
            branchId: recapBranchId,
          ),
          context: context,
        );

      case ReportType.rekapGr:
        return GoodReceiptRecapReportBuilder.build(
          source: await _reporting.loadGoodReceiptRecap(
            branchId: recapBranchId,
          ),
          context: context,
        );

      case ReportType.rekapDistribusi:
        return DistributionRecapReportBuilder.build(
          source: await _reporting.loadDistributionRecap(
            branchId: recapBranchId,
          ),
          context: context,
        );

      case ReportType.rekapPemakaian:
        return ConsumptionRecapReportBuilder.build(
          source: await _reporting.loadConsumptionRecap(
            branchId: recapBranchId,
            createdBy: ownDocuments,
            roomId: scopedRoomId,
          ),
          context: context,
        );

      case ReportType.rekapPemusnahan:
        return DisposalRecapReportBuilder.build(
          source: await _reporting.loadDisposalRecap(
            // Scoped by source location, because `disposals` has no branch column
            // and Warehouse Pusat belongs to no branch (§30). A cross-branch or
            // all-locations scope passes `null`, meaning every location.
            sourceLocationIds: request.scope.type == ReportScopeType.crossBranch
                ? null
                : (request.scope.locationIds.isEmpty
                      ? null
                      : request.scope.locationIds),
          ),
          context: context,
        );

      case ReportType.rekapRetur:
        return GoodsReturnRecapReportBuilder.build(
          source: await _reporting.loadGoodsReturnRecap(
            branchId: recapBranchId,
          ),
          context: context,
        );
    }
  }

  Future<ReportLedgerSource> _loadLedger(ReportRequest request) =>
      _reporting.loadLedgerSource(
        scope: request.scope,
        itemId: request.reportType.requiresItem ? request.filter.itemId : null,
        categoryId: request.filter.categoryId,
      );

  /// The three document chains that fulfil a Purchase Request (§25).
  ///
  /// Loaded at the *same* branch scope as the request recap itself, so a movement
  /// posted against a document the actor cannot see is never attributed to a request
  /// they can.
  Future<PurchaseRequestFulfilmentSource> _loadFulfilment(
    String? branchId,
  ) async {
    final deliveries = await _reporting.loadDeliveryOrderRecap(
      branchId: branchId,
    );
    final receipts = await _reporting.loadGoodReceiptRecap(branchId: branchId);
    final returns = await _reporting.loadGoodsReturnRecap(branchId: branchId);

    final goodReceiptToPr = {
      for (final row in receipts.rows) row.grId: row.prId,
    };
    return PurchaseRequestFulfilmentSource(
      deliveryOrderToPr: {
        for (final row in deliveries.rows) row.doId: row.prId,
      },
      goodReceiptToPr: goodReceiptToPr,
      goodsReturnToPr: {
        for (final row in returns.rows)
          if (goodReceiptToPr[row.grId] != null)
            row.goodsReturnId: goodReceiptToPr[row.grId]!,
      },
      shipmentMovements: deliveries.movements,
      receiptMovements: receipts.movements,
      returnMovements: returns.movements,
    );
  }
}
