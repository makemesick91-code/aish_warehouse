/// The four boundaries between the reporting domain and the outside world.
///
/// Every one of them is an interface with a production implementation under
/// `data/` and a fake in the tests, and that split is what makes this milestone
/// testable at all: rendering a workbook, writing a file and opening a share sheet
/// are the three things a unit test cannot do, and all three are behind these
/// types.
///
/// **No widget build context appears in any signature here, and none may.** The
/// share sheet is a platform call, not a widget operation; passing a widget context
/// into the domain would make [ExportReportUseCase] impossible to run without a
/// widget tree and would tie an audit-critical path to whether a screen was still
/// mounted (§41). The application's architecture tests enforce that by grepping
/// every `domain/` file for the Flutter type's name, comments included — which is
/// why this paragraph spells it out in prose rather than naming it.
library;

import 'dart:typed_data';

import '../models/reporting_models.dart';

/// Renders a [ReportDocument] as a real `.xlsx` workbook (§39).
///
/// The implementation **may not query anything**. It receives a finished document —
/// header, columns, grouped rows, subtotals, totals, warnings — and turns it into
/// cells. Every number it writes was computed by a builder, so the workbook and the
/// PDF and the screen cannot disagree about a subtotal (§33).
abstract interface class ReportExcelExporter {
  /// The workbook bytes. Begins with the ZIP magic `PK\x03\x04`, because an
  /// `.xlsx` is a ZIP of OOXML parts.
  ///
  /// Throws [ReportExcelGenerationFailure] if the workbook cannot be produced. An
  /// empty report is **not** a failure: it yields a valid workbook carrying the
  /// header and *"Tidak ada data"* (§52).
  Future<Uint8List> export(ReportDocument document);
}

/// Renders a [ReportDocument] as a real PDF (§40).
///
/// Same rule: no queries, no business logic, no recomputation.
abstract interface class ReportPdfExporter {
  /// The PDF bytes, beginning with `%PDF`.
  ///
  /// Throws [ReportPdfGenerationFailure] on a rendering failure. An empty report
  /// yields one valid page carrying the header and the empty message.
  Future<Uint8List> export(ReportDocument document);
}

/// A file that has been written and is ready to be shared.
class ReportArtifactHandle {
  const ReportArtifactHandle({
    required this.exportId,
    required this.fileName,
    required this.path,
    required this.byteLength,
  });

  /// The export this file belongs to. Also the name of the directory it sits in,
  /// which is what lets two exports share a canonical file name without either
  /// overwriting the other (§37).
  final String exportId;

  /// The canonical G-L5 name — what the user sees in the share sheet.
  final String fileName;

  /// Absolute path on this device.
  ///
  /// **Never shown to a user and never stored in `export_logs`.** An app-private
  /// cache path tells a nurse nothing, and putting one in an audit row would be
  /// recording an internal detail that the OS may invalidate at any time (§42).
  final String path;

  final int byteLength;
}

/// Writes report files into app-private storage (§41).
///
/// ### Why nothing here needs a storage permission
///
/// Files are written under the app's own directory. Sharing one hands the platform
/// a file the app already owns, so no `WRITE_EXTERNAL_STORAGE`, no
/// `MANAGE_EXTERNAL_STORAGE`, and no permission prompt — which is also why the UI
/// must never claim the file was "saved to Downloads" (§47). It was not; it is in
/// the app's cache until the user shares it somewhere.
abstract interface class ReportFileStore {
  /// Writes [bytes] as `<app dir>/aish_reports/<exportId>/<fileName>`.
  ///
  /// [exportId] gives each export its own directory, so the deterministic file name
  /// G-L5 requires never collides with an earlier export of the same report.
  ///
  /// Throws [ReportFileWriteFailure] when the write fails, and
  /// [InvalidReportFileNameFailure] when [fileName] is not a plain file name — the
  /// second is unreachable through [ReportFileNamePolicy] and enforced anyway.
  Future<ReportArtifactHandle> writeArtifact({
    required String exportId,
    required String fileName,
    required Uint8List bytes,
  });

  /// Removes an artifact and its directory, swallowing every error.
  ///
  /// Called on exactly one path: the audit insert failed after the file was
  /// written, so the file must not survive as an export nothing recorded (§3.17).
  /// It is best-effort because the *export* has already failed — a delete that
  /// itself failed would replace one honest error with a confusing one.
  Future<void> deleteArtifactBestEffort(ReportArtifactHandle handle);

  Future<bool> exists(ReportArtifactHandle handle);

  /// The bytes back off disk. Exists for the tests, which assert that what was
  /// written is what the exporter produced.
  Future<Uint8List> readBytes(ReportArtifactHandle handle);
}

/// Opens the platform share sheet (§41, §4.3).
///
/// The **only** platform channel this module touches. Everything else — building
/// the report, rendering it, writing it, auditing it — is pure Dart and pure SQLite,
/// which is what makes G-L3's *"dihasilkan lokal"* true rather than aspirational.
abstract interface class ReportShareGateway {
  /// Offers [handle] to the platform share sheet.
  ///
  /// Returns how it ended. A cancellation is **not** an error: by the time this is
  /// called the file exists and the audit row exists, so the user who dismissed the
  /// sheet still has a report and the export still happened (§36).
  ///
  /// Throws [ReportShareFailure] only when the sheet could not be opened at all.
  Future<ReportShareOutcome> shareGeneratedReport(ReportArtifactHandle handle);
}
