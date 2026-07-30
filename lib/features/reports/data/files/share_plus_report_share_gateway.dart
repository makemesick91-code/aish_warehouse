import 'package:share_plus/share_plus.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/gateways/report_gateways.dart';
import '../../domain/models/reporting_models.dart';

/// Opens the platform share sheet through `share_plus` (§41, §4.3).
///
/// ### The only platform channel in the whole module
///
/// Building the report, folding the ledger, rendering the workbook, writing the
/// file and recording the audit row are all pure Dart over local SQLite. This one
/// class talks to the OS, which is why it is behind an interface: every test in this
/// milestone runs against a fake, and none of them invokes a real share sheet.
///
/// ### A dismissed sheet is a success
///
/// By the time this is called the file exists on disk and the export has been
/// recorded (§36). So a user who opens the sheet and taps *back* has a report,
/// and the audit row describing it is correct. [ReportShareOutcome.cancelled] and
/// [ReportShareOutcome.unavailable] are therefore *outcomes*, not errors — the UI
/// says the file was created either way, and never deletes it.
///
/// [ReportShareFailure] is thrown only when the sheet could not be opened at all,
/// which is still not a failed export: the caller reports a failed hand-off.
class SharePlusReportShareGateway implements ReportShareGateway {
  const SharePlusReportShareGateway();

  @override
  Future<ReportShareOutcome> shareGeneratedReport(
    ReportArtifactHandle handle,
  ) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(handle.path, name: handle.fileName)],
          // The canonical G-L5 name, so what the recipient sees matches what the
          // audit row records.
          fileNameOverrides: [handle.fileName],
          subject: handle.fileName,
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => ReportShareOutcome.shared,
        ShareResultStatus.dismissed => ReportShareOutcome.cancelled,
        ShareResultStatus.unavailable => ReportShareOutcome.unavailable,
      };
    } catch (_) {
      throw ReportShareFailure(
        'Berbagi file gagal dibuka. File laporan tetap tersimpan di perangkat.',
        fileName: handle.fileName,
      );
    }
  }
}
