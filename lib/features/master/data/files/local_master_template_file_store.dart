import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/gateways/master_import_gateways.dart';
import '../../domain/models/import_models.dart';
import '../../domain/models/master_admin_models.dart';

/// Sanitizes a name before it becomes part of a path.
///
/// One function, used by both file stores in this module, because there is
/// exactly one rule: a file name is a *name*, never a path. Anything that could
/// traverse — a separator, a `..`, a drive letter, a NUL — is replaced rather
/// than escaped, and a name that sanitizes to nothing gets a fallback rather than
/// producing a path ending in a directory separator.
abstract final class MasterImportPathSanitizer {
  static const int _maxNameLength = 120;

  static String safeFileName(String raw, {String fallback = 'file.xlsx'}) {
    // `basename` first, so `../../etc/passwd` is reduced to `passwd` before the
    // character filter ever runs — the filter alone would leave `......etcpasswd`,
    // which is harmless but unrecognisable.
    var name = p.basename(raw.trim());
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._\- ]'), '_');
    name = name.replaceAll(RegExp(r'\.{2,}'), '.');
    name = name.replaceAll(RegExp(r'^[.\s]+'), '');
    name = name.trim();
    if (name.isEmpty) return fallback;
    if (name.length <= _maxNameLength) return name;
    // Truncate the stem, keep the extension: a name cut mid-extension stops
    // being recognisable as a workbook.
    final extension = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    final keep = (_maxNameLength - extension.length).clamp(1, _maxNameLength);
    return '${stem.substring(0, keep.clamp(0, stem.length))}$extension';
  }

  /// Whether [value] is a plain name with no path in it.
  static bool isPlainName(String value) =>
      value.isNotEmpty &&
      value == p.basename(value) &&
      !value.contains('/') &&
      !value.contains(r'\') &&
      value != '.' &&
      value != '..';
}

/// Writes generated templates into the app's own directory (§26).
///
/// ```text
/// <app documents>/aish_master_templates/<entity>/<canonical name>
/// ```
///
/// The **user never sees the path**, and the UI must never claim the file was
/// *"saved to Downloads"* — it was not. It is in the app's own storage until the
/// user shares it somewhere, which is also why no storage permission is requested
/// anywhere in this project.
///
/// A template is regenerated on every download rather than cached, so overwriting
/// the previous file of the same name is correct: the newer one carries the newer
/// category list.
class LocalMasterTemplateFileStore implements MasterTemplateFileStore {
  const LocalMasterTemplateFileStore();

  static const String rootFolderName = 'aish_master_templates';

  @override
  Future<MasterTemplateArtifact> writeTemplate({
    required MasterEntityType entity,
    required String version,
    required String fileName,
    required Uint8List bytes,
  }) async {
    // Belt to the catalogue's braces. The name is built from an enum and a
    // constant, so this cannot fire through the normal path — which is precisely
    // why it is here: the one call that builds a path from a name refuses to
    // build one from a name that could escape.
    if (!MasterImportPathSanitizer.isPlainName(fileName)) {
      throw ImportSourceFileWriteFailure(
        'Nama file template tidak valid.',
        fileName: fileName,
      );
    }

    try {
      final root = await _rootDirectory();
      final directory = Directory(p.join(root.path, entity.dbValue));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(bytes, flush: true);

      return MasterTemplateArtifact(
        entity: entity,
        version: version,
        fileName: fileName,
        path: file.path,
        byteLength: bytes.length,
      );
    } on ImportSourceFileWriteFailure {
      rethrow;
    } catch (_) {
      // The OS error names an internal path, and §45 keeps paths out of anything
      // a user reads.
      throw ImportSourceFileWriteFailure(
        'Template gagal disimpan di perangkat. Silakan coba lagi.',
        fileName: fileName,
      );
    }
  }

  @override
  Future<bool> exists(MasterTemplateArtifact artifact) =>
      File(artifact.path).exists();

  @override
  Future<Uint8List> readBytes(MasterTemplateArtifact artifact) =>
      File(artifact.path).readAsBytes();

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
