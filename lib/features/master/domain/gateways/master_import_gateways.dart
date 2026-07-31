/// The five boundaries between the master-import domain and the outside world.
///
/// Rendering a workbook, writing a file, opening a share sheet, opening a file
/// picker and hashing bytes off disk are the things a unit test cannot do, and all
/// five are behind these types. Every one has a production implementation under
/// `data/` and a fake in the tests — which is what makes G-M2, G-M3 and G-M6
/// assertable without a device.
///
/// **No widget build context appears in any signature here, and none may.** A
/// file picker is a platform call, not a widget operation. Passing a widget
/// context into the domain would make [ValidateMasterImportUseCase] impossible to
/// run without a widget tree and would tie an audit-critical path to whether a
/// screen was still mounted (§43). The architecture tests grep every `domain/`
/// file for the Flutter type's name, comments included — which is why this
/// paragraph spells it out in prose rather than naming it.
library;

import 'dart:typed_data';

import '../models/import_models.dart';
import '../models/master_admin_models.dart';

/// Renders a [MasterTemplateDefinition] as a real `.xlsx` workbook (§25).
///
/// The implementation **may not query anything**. It receives a finished
/// definition — columns, guidance, sample row, value lists — and turns it into
/// cells, so what the template says and what the importer expects come from one
/// source ([ImportEntity.headers]).
abstract interface class MasterTemplateGenerator {
  /// The workbook bytes. Begins with the ZIP magic `PK\x03\x04`, because an
  /// `.xlsx` is a ZIP of OOXML parts.
  ///
  /// Writes **no** database row — in particular no `import_logs` row. Downloading
  /// a template is not an import (§25).
  Future<Uint8List> generate(MasterTemplateDefinition definition);
}

/// Writes template files into app-private storage (§26).
///
/// Same permission story as the reporting file store: files go under the app's
/// own directory, so there is no `WRITE_EXTERNAL_STORAGE`, no
/// `MANAGE_EXTERNAL_STORAGE` and no prompt — and the UI must never claim the file
/// was *"saved to Downloads"*, because it was not.
abstract interface class MasterTemplateFileStore {
  /// Writes [bytes] under a directory of this build's choosing and returns a
  /// handle carrying the canonical §26 file name.
  ///
  /// Throws [ImportSourceFileWriteFailure] when the write fails.
  Future<MasterTemplateArtifact> writeTemplate({
    required MasterEntityType entity,
    required String version,
    required String fileName,
    required Uint8List bytes,
  });

  Future<bool> exists(MasterTemplateArtifact artifact);

  /// The bytes back off disk. Exists for the tests, which assert that what was
  /// written is what the generator produced.
  Future<Uint8List> readBytes(MasterTemplateArtifact artifact);
}

/// Opens the platform share sheet for a generated template (§26).
abstract interface class MasterTemplateShareGateway {
  /// Offers [artifact] to the platform share sheet.
  ///
  /// A cancellation is **not** an error: the file exists either way, and the UI
  /// says so rather than treating a dismissed sheet as a failed download.
  Future<MasterTemplateShareOutcome> shareTemplate(
    MasterTemplateArtifact artifact,
  );
}

/// Lets the operator choose one `.xlsx` from their device (§27).
///
/// ### What the gateway returns, and what it deliberately does not
///
/// Bytes and a name. Not a path: a content-provider URI on Android is not a file
/// system path, and a domain that held one would be holding something it cannot
/// re-open later. The audit copy is written by [ImportSourceFileStore] from these
/// bytes, and *that* path is the one that survives.
///
/// A cancelled picker returns `null`, which is an outcome rather than a failure —
/// the user changed their mind, and a screen that showed them an error for it
/// would be wrong.
abstract interface class MasterImportFilePicker {
  /// Opens the picker restricted to `.xlsx`, single selection.
  ///
  /// Returns `null` when the user dismissed it. Throws
  /// [ImportUnsupportedFileFailure] when the platform handed back something that
  /// is not an `.xlsx` despite the filter, and [ImportFileEmptyFailure] when the
  /// chosen file has no bytes.
  Future<PickedImportFile?> pickWorkbook();
}

/// Keeps the source file of every validated import, for audit (G-M6, §28).
///
/// ### Why app documents rather than a cache
///
/// The reporting module writes artifacts to a directory the OS may clear, and
/// says so, because an export log points at no bytes. This is the opposite: G-M6
/// requires the source file to be *kept*, the commit re-reads it rather than
/// trusting a preview, and the hash in the audit row is only meaningful while the
/// bytes it describes still exist.
///
/// ### The ordering this interface exists to make possible (§28)
///
/// Store the file, then hash it, then write the audit row. If the store fails,
/// there is no log and no master mutation. If the audit insert fails,
/// [deleteBestEffort] removes the orphan — a copy of somebody's user list sitting
/// in app storage that nothing points at is the one outcome worse than losing the
/// import.
abstract interface class ImportSourceFileStore {
  /// Writes [bytes] as `<app documents>/aish_import_audit/<importId>/<name>`,
  /// hashes them, and returns the handle.
  ///
  /// [originalFileName] is sanitized to a plain file name before it becomes part
  /// of a path — a name is user input, and the one call that turns user input
  /// into a path refuses to build one that could escape.
  ///
  /// Throws [ImportSourceFileWriteFailure] on any write failure.
  Future<ImportSourceFile> storeValidatedSource({
    required String importId,
    required String originalFileName,
    required Uint8List bytes,
  });

  /// The retained bytes, for the commit's re-parse.
  ///
  /// Throws [ImportSourceFileMissingFailure] when the copy is gone.
  Future<Uint8List> readStoredSource({
    required String importId,
    required String storedPath,
  });

  /// Whether the retained bytes still hash to [expectedSha256] and measure
  /// [expectedSizeBytes].
  ///
  /// Both, not just the hash: the size is the cheaper check and catches a
  /// truncated copy without reading it twice.
  Future<bool> verifyHash({
    required String storedPath,
    required String expectedSha256,
    required int expectedSizeBytes,
  });

  Future<bool> exists(String storedPath);

  /// Removes an orphaned copy, swallowing every error.
  ///
  /// Called on exactly one path: the audit insert failed after the file was
  /// written (§28). Best-effort because the *import* has already failed, and a
  /// delete that itself failed would replace one honest error with a confusing
  /// one.
  Future<void> deleteBestEffortForFailedAudit(String storedPath);
}
