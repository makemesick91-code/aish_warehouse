import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/gateways/report_gateways.dart';
import '../../domain/services/report_file_name_policy.dart';

/// Writes report files into the app's own directory (§41).
///
/// ### Layout, and why every export gets its own folder
///
/// ```text
/// <app documents>/aish_reports/<exportId>/<canonical file name>
/// ```
///
/// G-L5's name is deterministic — the same report exported twice on the same day
/// produces the same name — so a flat directory would have the second export
/// silently overwrite the first, and the audit row for the first would point at a
/// file that is now something else. The per-export directory is what lets the name
/// stay exactly what the specification says while two files coexist.
///
/// The **user never sees the path**. It is an app-private location, it is not stored
/// in `export_logs`, and the UI says *"file siap disimpan atau dibagikan"* rather
/// than naming a folder the user cannot navigate to (§47).
///
/// ### Why the directory is chosen this way
///
/// `getApplicationDocumentsDirectory` on Android and iOS, falling back to the system
/// temp directory when the platform has no such notion (tests, desktop shells
/// without the plugin). Either way it is inside the app sandbox, so **no storage
/// permission is requested anywhere in this project** — and sharing works because
/// `share_plus` hands the platform a file the app already owns.
class LocalReportFileStore implements ReportFileStore {
  const LocalReportFileStore();

  /// The folder every export directory lives under.
  static const String rootFolderName = 'aish_reports';

  @override
  Future<ReportArtifactHandle> writeArtifact({
    required String exportId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    // Belt to [ReportFileNamePolicy]'s braces. The policy already sanitizes every
    // token, so this cannot fire through the normal path — which is precisely why
    // it is here: the one call that ever builds a path from a name refuses to build
    // one from a name that could escape (§37).
    if (!ReportFileNamePolicy.isSafe(fileName)) {
      throw InvalidReportFileNameFailure(
        'Nama file laporan tidak valid.',
        fileName: fileName,
      );
    }
    if (!ReportFileNamePolicy.isSafe(exportId)) {
      throw InvalidReportFileNameFailure(
        'Nama file laporan tidak valid.',
        fileName: fileName,
      );
    }

    try {
      final root = await _rootDirectory();
      final directory = Directory(p.join(root.path, exportId));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(bytes, flush: true);

      return ReportArtifactHandle(
        exportId: exportId,
        fileName: fileName,
        path: file.path,
        byteLength: bytes.length,
      );
    } on InvalidReportFileNameFailure {
      rethrow;
    } catch (_) {
      // The OS error is not surfaced: it names an internal path, and §52 keeps
      // paths and stack traces out of anything a user reads.
      throw ReportFileWriteFailure(
        'File laporan gagal disimpan di perangkat. Silakan coba lagi.',
        fileName: fileName,
      );
    }
  }

  @override
  Future<void> deleteArtifactBestEffort(ReportArtifactHandle handle) async {
    // Every failure is swallowed, deliberately. This runs only when the export has
    // *already* failed (the audit insert did not land), and replacing that honest
    // error with a delete error would tell the user about the wrong problem.
    try {
      final file = File(handle.path);
      if (file.existsSync()) await file.delete();
      final directory = file.parent;
      if (directory.existsSync() &&
          directory.listSync().isEmpty &&
          p.basename(directory.path) == handle.exportId) {
        await directory.delete();
      }
    } catch (_) {
      // Intentionally ignored — see above.
    }
  }

  @override
  Future<bool> exists(ReportArtifactHandle handle) async =>
      File(handle.path).exists();

  @override
  Future<Uint8List> readBytes(ReportArtifactHandle handle) =>
      File(handle.path).readAsBytes();

  Future<Directory> _rootDirectory() async {
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory();
    } catch (_) {
      // No platform channel — a test host or a desktop shell without the plugin.
      // The temp directory is still inside the sandbox, so nothing about the
      // permission story changes.
      base = Directory.systemTemp;
    }
    return Directory(p.join(base.path, rootFolderName));
  }
}
