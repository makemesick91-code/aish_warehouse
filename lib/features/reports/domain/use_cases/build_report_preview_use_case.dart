import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/reporting_models.dart';
import '../repositories/reporting_repository.dart';
import '../services/report_document_assembler.dart';

/// Builds a report for the screen (§36).
///
/// ### It writes nothing
///
/// No file, and — the load-bearing half — **no `export_logs` row** (§3.13). G-L2
/// audits *exports*, and looking at a report on screen is not one: nothing left the
/// device, nothing was shared, and there is no artifact for the audit row to
/// describe. Logging previews would fill the Super Admin's audit trail with
/// browsing noise and make the one thing it exists to show — who took a copy of what
/// — impossible to find.
///
/// ### The actor is re-read, every time
///
/// From the database by id, never from the session object. A session opened as a
/// Kepala Cabang stays open across a role change or a deactivation, and every
/// authorization decision below rests on the row as it is *now* (O-8). An actor who
/// no longer exists, or is no longer active, is refused here rather than at the
/// repository — the point is that no scoped read happens at all.
///
/// ### The preview cap is a rendering decision
///
/// [maxPreviewRows] limits what the widget builds, not what the report contains:
/// [ReportPreview.document] holds every row, and the export path rebuilds from the
/// same request and is never truncated (§46).
class BuildReportPreviewUseCase {
  BuildReportPreviewUseCase({
    required ReportingRepository reporting,
    required this._master,
    DateTime Function()? clock,
  }) : _assembler = ReportDocumentAssembler(reporting: reporting, clock: clock);

  /// How many rows the preview widget builds before it stops and says so.
  ///
  /// 200 is enough to see the shape of a report — several categories, their
  /// subtotals, the overall total — and few enough that a five-thousand-row stock
  /// report does not build five thousand widgets on a clinic tablet.
  static const int maxPreviewRows = 200;

  final MasterDataRepository _master;
  final ReportDocumentAssembler _assembler;

  Future<ReportPreview> call({
    required String actorUserId,
    required ReportRequestDraft draft,
  }) async {
    final actor = await _master.userById(actorUserId);
    if (actor == null || !actor.isActive) {
      throw ReportAccessDeniedFailure(
        'Anda tidak memiliki akses ke laporan ini.',
        reportType: draft.reportType,
        scopeType: draft.scopeType,
      );
    }

    final result = await _assembler.assemble(actor: actor, draft: draft);
    final total = result.document.rowCount;
    return ReportPreview(
      document: result.document,
      displayedRowCount: total < maxPreviewRows ? total : maxPreviewRows,
    );
  }
}
