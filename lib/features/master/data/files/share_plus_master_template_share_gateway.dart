import 'package:share_plus/share_plus.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/gateways/master_import_gateways.dart';
import '../../domain/models/import_models.dart';

/// Opens the platform share sheet for a generated template (§26).
///
/// The same shape as the reporting module's share gateway, and for the same
/// reasons: it is the one platform channel on this path, it is behind an
/// interface so tests never invoke a real sheet, and a **dismissed sheet is not
/// an error** — by the time this is called the template exists on disk, so a user
/// who taps back still has their file.
///
/// The UI says the file is ready to save or share, and never that it was *"saved
/// to Downloads"*: it is in app-private storage, which is exactly why no storage
/// permission was needed to write it.
class SharePlusMasterTemplateShareGateway
    implements MasterTemplateShareGateway {
  const SharePlusMasterTemplateShareGateway();

  @override
  Future<MasterTemplateShareOutcome> shareTemplate(
    MasterTemplateArtifact artifact,
  ) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(artifact.path, name: artifact.fileName)],
          // The canonical §26 name, so what the recipient sees is the name the
          // importer will later recognise as this entity's template.
          fileNameOverrides: [artifact.fileName],
          subject: artifact.fileName,
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => MasterTemplateShareOutcome.shared,
        ShareResultStatus.dismissed => MasterTemplateShareOutcome.cancelled,
        ShareResultStatus.unavailable => MasterTemplateShareOutcome.unavailable,
      };
    } catch (_) {
      throw ImportSourceFileWriteFailure(
        'Berbagi template gagal dibuka. File template tetap tersimpan di '
        'perangkat.',
        fileName: artifact.fileName,
      );
    }
  }
}
