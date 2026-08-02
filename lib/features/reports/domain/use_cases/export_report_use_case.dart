import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_file_upload_queue.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../gateways/report_gateways.dart';
import '../models/reporting_models.dart';
import '../repositories/reporting_repository.dart';
import '../services/report_document_assembler.dart';
import '../services/report_file_name_policy.dart';

/// Produces a report file, records it, and offers it to the share sheet (§36).
///
/// ### The order is the audit guarantee
///
/// ```text
/// reload actor → re-check access → build FRESH → render bytes
///              → write file → insert export_logs → open share sheet
/// ```
///
/// Every step's failure behaviour is chosen so that **no file can exist without an
/// audit row, and no audit row can exist without a file**:
///
/// | fails | file | log | share |
/// |---|---|---|---|
/// | build / render | none | none | not opened |
/// | file write | none | none | not opened |
/// | audit insert | **deleted best-effort** | none | not opened |
/// | share | kept | kept | reported as an outcome |
///
/// The third row is the one worth arguing about. The file was written successfully —
/// deleting it destroys work the user asked for. But G-L2 exists so that every
/// exported copy of clinic data is accounted for, and a file on disk that no audit
/// row mentions is precisely the thing it forbids. So the export is treated as
/// failed, the artifact is removed, and the share sheet is never opened: better to
/// ask the user to try again than to leave an unaccounted copy behind (§3.17).
///
/// The fourth row is the opposite call, for the same reason. Once the audit row
/// exists, the export *happened* — a user who dismisses the share sheet still has a
/// report, and deleting it would leave an audit row pointing at nothing (§3.16).
///
/// ### Built fresh, never reused from a preview
///
/// [ReportDocumentAssembler.assemble] runs again, with a new cutoff. A preview may
/// be minutes old, the actor's role may have changed since, and the numbers may have
/// moved — and `export_logs.data_cutoff_at` claims to describe *this* file. Reusing
/// a preview snapshot would make that claim false.
///
/// ### Two taps make two exports
///
/// The UI disables the buttons while one is running, but two deliberate exports are
/// two exports: two audit rows, two directories, and — by [ReportFileNamePolicy] —
/// the same canonical file name in each. That is G-L5's shape, and the per-export
/// directory is what keeps them from overwriting one another (§37).
class ExportReportUseCase {
  ExportReportUseCase({
    required ReportingRepository reporting,
    required this._master,
    required this._excelExporter,
    required this._pdfExporter,
    required this._fileStore,
    required this._shareGateway,
    this._outboxWriter = const NoopSyncOutboxWriter(),
    this._fileUploadQueue = const NoopSyncFileUploadQueue(),
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _reporting = reporting,
       _idGenerator = idGenerator ?? _uuidV4,
       _assembler = ReportDocumentAssembler(reporting: reporting, clock: clock);

  static const Uuid _uuid = Uuid();

  static String _uuidV4() => _uuid.v4();

  final ReportingRepository _reporting;
  final MasterDataRepository _master;
  final ReportExcelExporter _excelExporter;
  final ReportPdfExporter _pdfExporter;
  final ReportFileStore _fileStore;
  final ReportShareGateway _shareGateway;
  final SyncOutboxWriter _outboxWriter;
  final SyncFileUploadQueue _fileUploadQueue;
  final String Function() _idGenerator;
  final ReportDocumentAssembler _assembler;

  Future<GeneratedReportArtifact> call({
    required String actorUserId,
    required ReportRequestDraft draft,
    required ReportFormat format,
  }) async {
    final actor = await _master.userById(actorUserId);
    if (actor == null || !actor.isActive) {
      throw ReportAccessDeniedFailure(
        'Anda tidak memiliki akses ke laporan ini.',
        reportType: draft.reportType,
        scopeType: draft.scopeType,
      );
    }

    // Fresh, with its own cutoff — see the class note. `assemble` re-checks access
    // against the reloaded actor, so this is the second of two independent checks.
    final result = await _assembler.assemble(actor: actor, draft: draft);
    final document = result.document;

    final bytes = switch (format) {
      ReportFormat.xlsx => await _excelExporter.export(document),
      ReportFormat.pdf => await _pdfExporter.export(document),
    };
    if (bytes.isEmpty) {
      throw ReportGenerationFailure(
        'Laporan gagal dibuat. Silakan coba lagi.',
        reportType: draft.reportType,
      );
    }

    final fileName = ReportFileNamePolicy.build(
      reportType: draft.reportType,
      format: format,
      scopeType: draft.scopeType,
      period: result.request.period,
      branch: result.branch,
      room: result.room,
      category: result.category,
    );

    final exportId = _idGenerator();
    final handle = await _fileStore.writeArtifact(
      exportId: exportId,
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
    );

    final ExportLog log;
    try {
      log = await _reporting.transaction(() async {
        final inserted = await _reporting.insertExportLog(
          reportType: draft.reportType,
          format: format,
          scopeType: draft.scopeType,
          locationId: result.request.scope.locationId,
          categoryId: result.category?.id,
          branchId: result.request.scope.branchId,
          itemId: result.item?.id,
          periodStart: result.request.period.periodStart,
          periodEnd: result.request.period.periodEnd,
          exportedBy: actor.id,
          fileName: fileName,
          dataCutoffAtUtc: document.header.generatedAtUtc,
          syncSummary: document.header.syncSnapshot.label,
          rowCount: document.rowCount,
        );
        await _outboxWriter.enqueueCurrentAggregate(
          operation: SyncOperationType.appendExportAudit,
          aggregateType: SyncAggregateType.exportAudit,
          aggregateId: inserted.id,
          actorUserId: actor.id,
          occurredAtUtc: document.header.generatedAtUtc,
        );
        await _fileUploadQueue.enqueue(
          entityType: 'report_artifact',
          entityId: inserted.id,
          actorUserId: actor.id,
          localFilePath: handle.path,
          originalFileName: fileName,
          sha256: sha256.convert(bytes).toString(),
          sizeBytes: handle.byteLength,
          mimeType: switch (format) {
            ReportFormat.xlsx =>
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ReportFormat.pdf => 'application/pdf',
          },
          remoteBucket: 'report-artifacts',
        );
        return inserted;
      });
    } catch (_) {
      // No audit row means no export. Remove the artifact so nothing untracked is
      // left behind, and refuse — see the class note's third table row.
      await _fileStore.deleteArtifactBestEffort(handle);
      throw ReportAuditWriteFailure(
        'Laporan gagal dicatat pada jejak audit, sehingga ekspor dibatalkan. '
        'Silakan coba lagi.',
        fileName: fileName,
      );
    }

    // Only now, and never before: the file exists and the export is recorded.
    ReportShareOutcome shareOutcome;
    try {
      shareOutcome = await _shareGateway.shareGeneratedReport(handle);
    } on ReportShareFailure {
      // The hand-off failed; the export did not. The artifact and the audit row
      // both stay, and the caller tells the user the file was created (§3.16).
      shareOutcome = ReportShareOutcome.unavailable;
    }

    return GeneratedReportArtifact(
      exportLogId: log.id,
      fileName: fileName,
      format: format,
      byteLength: handle.byteLength,
      rowCount: document.rowCount,
      shareOutcome: shareOutcome,
    );
  }
}
