import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/gateways/master_import_gateways.dart';
import '../../domain/models/import_models.dart';
import 'local_master_template_file_store.dart';

/// Keeps the source file of every validated import (G-M6, §28).
///
/// ```text
/// <app documents>/aish_import_audit/<import id>/<sanitized original name>
/// ```
///
/// ### Documents, not cache — and that is the whole difference from reporting
///
/// The reporting file store writes to a directory the OS may clear, and says so,
/// because an `export_logs` row points at no bytes. Here the opposite holds:
/// G-M6 requires the source to be *kept*, the commit re-parses it rather than
/// trusting the preview it was handed (§33), and `import_logs.file_sha256` is
/// only meaningful while the bytes it describes still exist. A cache directory
/// would make the audit trail true until the next time the device ran low on
/// space.
///
/// ### One directory per import
///
/// Two imports of `barang.xlsx` are two events (§11), and a flat directory would
/// have the second overwrite the first — leaving the first audit row pointing at
/// bytes that are now something else, with a hash that no longer matches. The
/// import id is a UUID, so the directory name is collision-free by construction.
///
/// ### The name is sanitized, the audit row keeps the original
///
/// `import_logs.file_name` records what the operator saw in the picker, so they
/// recognise their own upload. The *path* is built from a sanitized copy, because
/// a name is user input and the one call that turns user input into a path
/// refuses to build one that could escape.
class LocalImportSourceFileStore implements ImportSourceFileStore {
  const LocalImportSourceFileStore();

  static const String rootFolderName = 'aish_import_audit';

  @override
  Future<ImportSourceFile> storeValidatedSource({
    required String importId,
    required String originalFileName,
    required Uint8List bytes,
  }) async {
    if (!MasterImportPathSanitizer.isPlainName(importId)) {
      throw ImportSourceFileWriteFailure(
        'File sumber gagal disimpan. Silakan coba lagi.',
        fileName: originalFileName,
      );
    }
    final safeName = MasterImportPathSanitizer.safeFileName(
      originalFileName,
      fallback: 'import.xlsx',
    );

    try {
      final root = await _rootDirectory();
      final directory = Directory(p.join(root.path, importId));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, safeName));
      await file.writeAsBytes(bytes, flush: true);

      return ImportSourceFile(
        importId: importId,
        fileName: safeName,
        path: file.path,
        // Hashed from the bytes that were written, not from the picker's buffer:
        // what the audit row attests to is the copy that survives.
        sha256: _hash(bytes),
        sizeBytes: bytes.length,
      );
    } catch (_) {
      throw ImportSourceFileWriteFailure(
        'File sumber gagal disimpan di perangkat. Impor dibatalkan dan tidak '
        'ada data yang berubah.',
        fileName: originalFileName,
      );
    }
  }

  @override
  Future<Uint8List> readStoredSource({
    required String importId,
    required String storedPath,
  }) async {
    final file = File(storedPath);
    if (!await file.exists()) {
      throw ImportSourceFileMissingFailure(
        'File sumber impor ini tidak ditemukan lagi di perangkat, sehingga '
        'impor tidak dapat diterapkan. Unggah ulang file lalu validasi kembali.',
        importId: importId,
      );
    }
    try {
      return await file.readAsBytes();
    } catch (_) {
      throw ImportSourceFileMissingFailure(
        'File sumber impor ini tidak dapat dibaca lagi, sehingga impor tidak '
        'dapat diterapkan. Unggah ulang file lalu validasi kembali.',
        importId: importId,
      );
    }
  }

  @override
  Future<bool> verifyHash({
    required String storedPath,
    required String expectedSha256,
    required int expectedSizeBytes,
  }) async {
    final file = File(storedPath);
    if (!await file.exists()) return false;
    // Size first: it is the cheaper check and catches a truncated copy without
    // reading it twice.
    if (await file.length() != expectedSizeBytes) return false;
    final bytes = await file.readAsBytes();
    return _hash(bytes) == expectedSha256;
  }

  @override
  Future<bool> exists(String storedPath) => File(storedPath).exists();

  @override
  Future<void> deleteBestEffortForFailedAudit(String storedPath) async {
    // Every failure is swallowed, deliberately. This runs only when the audit
    // insert has *already* failed, and replacing that honest error with a delete
    // error would tell the operator about the wrong problem.
    try {
      final file = File(storedPath);
      if (file.existsSync()) await file.delete();
      final directory = file.parent;
      if (directory.existsSync() && directory.listSync().isEmpty) {
        await directory.delete();
      }
    } catch (_) {
      // Intentionally ignored — see above.
    }
  }

  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();

  Future<Directory> _rootDirectory() async {
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory();
    } catch (_) {
      base = Directory.systemTemp;
    }
    return Directory(p.join(base.path, rootFolderName));
  }
}
