import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../gateways/master_import_gateways.dart';
import '../models/import_models.dart';
import '../models/master_admin_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_import_validation_engine.dart';
import '../services/master_import_workbook_validator.dart';
import 'master_admin_guard.dart';

/// Parses an uploaded `.xlsx` into an [ImportWorkbook].
///
/// An interface rather than the concrete parser, so the domain never imports the
/// spreadsheet package and every test can hand in rows directly (§57).
abstract interface class MasterImportWorkbookReader {
  ImportWorkbook read({
    required MasterEntityType entity,
    required Uint8List bytes,
    required String fileName,
  });
}

/// Stage 1 of G-M3: **validate and preview, without touching master data**.
///
/// ### What this use case writes, and what it does not
///
/// It writes exactly two things, both at the very end and both audit:
///
/// 1. a copy of the source file, under app documents (G-M6);
/// 2. one `import_logs` row with status `validated`.
///
/// It writes **nothing** to `branches`, `rooms`, `users`, `item_categories`,
/// `items`, `item_batches`, `stock_locations`, `stock_balances`,
/// `stock_movements` or any workflow table. G-M3 forbids the preview from
/// changing master data, §2.3 of the specification defines a `validated` status
/// for this table, and §3.3 reconciles the two: retaining the file and recording
/// that a validation happened is an *audit side effect*, not a master-data
/// mutation. The consequence is deliberate — an import somebody previewed and
/// abandoned still leaves a trail, because that happened.
///
/// ### Ordering, and what survives each failure (§28)
///
/// ```text
/// reload actor → extension → size → parse → sheets → version → headers
///   → rows → normalize → duplicates → entity rules   [nothing written yet]
///   → store source file                              [file exists, no log]
///   → insert validated log                           [both exist]
/// ```
///
/// A workbook-level failure — wrong extension, corrupt bytes, missing sheet,
/// unsupported version, bad headers, too many rows — throws **before** the file
/// is stored, so it produces no source copy and no audit row. That is the choice
/// §29 asks to be documented: a file that never reached row validation has no
/// counts to record, and a log row with `total_rows = 0` and a header error in
/// `error_detail` would be indistinguishable from an empty-but-valid import. The
/// operator sees the failure on screen; nothing is retained.
///
/// A file that *does* reach row validation always produces a log, errors or not.
/// A 400-row user file with 87 bad rows is a real event with real counts.
///
/// If storing the file fails: no log, no master mutation. If the log insert
/// fails: the stored file is deleted best-effort, because a copy of somebody's
/// user list sitting in app storage that nothing points at is worse than losing
/// the import.
///
/// ### Row errors never stop the pass
///
/// [MasterImportValidationEngine] checks every row for every rule (§29). An
/// operator who has to discover one error per upload will upload eleven times.
class ValidateMasterImportUseCase with MasterAdminGuard {
  ValidateMasterImportUseCase({
    required this.repository,
    required this.workbookReader,
    required this.sourceFileStore,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _newId = idGenerator ?? _defaultIdGenerator;

  @override
  final MasterAdminRepository repository;

  final MasterImportWorkbookReader workbookReader;
  final ImportSourceFileStore sourceFileStore;
  final DateTime Function() _clock;
  final String Function() _newId;

  Future<ImportPreviewSession> call({
    required String actorUserId,
    required MasterEntityType entity,
    required PickedImportFile file,
  }) async {
    // 1–3. The actor, re-read from the database. Not the session's claim (O-8).
    final actor = await requireSuperAdmin(actorUserId);

    // 4. The file, before a byte is parsed.
    MasterImportWorkbookValidator.ensureSupportedExtension(file);
    MasterImportWorkbookValidator.ensureWithinSizeLimit(file);

    // 5–7. Structure: bytes, sheets, template version, headers, row limit, and
    //      the blank/sample rows dropped. Every one of these throws rather than
    //      collecting, because a workbook whose headers are wrong has no rows
    //      worth reporting on.
    final workbook = workbookReader.read(
      entity: entity,
      bytes: file.bytes,
      fileName: file.originalFileName,
    );

    // 8–17. Normalize, detect duplicates, resolve foreign keys, decide
    //       insert/update, apply the entity rules and the historical-integrity
    //       rules, and count. Pure, and nothing written.
    final snapshot = await MasterImportReferenceSnapshot.load(
      repository: repository,
      entity: entity,
      actorId: actor.id,
    );
    final result = MasterImportValidationEngine.validate(
      entity: entity,
      workbook: workbook,
      snapshot: snapshot,
    );

    // 18–20. The audit side effect, and only now.
    final importId = _newId();
    final nowUtc = _clock().toUtc();

    final sourceFile = await sourceFileStore.storeValidatedSource(
      importId: importId,
      originalFileName: file.originalFileName,
      bytes: file.bytes,
    );

    final ImportLog log;
    try {
      log = await repository.insertValidatedImportLog(
        id: importId,
        entity: entity,
        // The name as the operator saw it in the picker, not the sanitized name
        // the copy was written under — they have to recognise their own upload.
        fileName: file.originalFileName,
        totalRows: result.summary.totalRows,
        insertedRows: result.summary.insertedRows,
        updatedRows: result.summary.updatedRows,
        failedRows: result.summary.failedRows,
        errorDetail: ImportErrorDetail.encode(result.issues),
        importedBy: actor.id,
        storedFilePath: sourceFile.path,
        fileSha256: sourceFile.sha256,
        fileSizeBytes: sourceFile.sizeBytes,
        templateVersion: workbook.templateVersion,
        nowUtc: nowUtc,
      );
    } catch (error) {
      // The one ordering §28 makes load-bearing.
      await sourceFileStore.deleteBestEffortForFailedAudit(sourceFile.path);
      if (error is AppFailure) rethrow;
      throw ImportAuditWriteFailure(
        'Catatan impor gagal disimpan, sehingga impor dibatalkan. Tidak ada '
        'data master yang berubah. Silakan coba lagi.',
        fileName: file.originalFileName,
      );
    }

    return ImportPreviewSession(
      importId: log.id,
      entity: entity,
      fileName: log.fileName,
      templateVersion: log.templateVersion,
      summary: result.summary,
      rows: result.previews,
      issues: result.issues,
      sourceFile: sourceFile,
      validatedAtUtc: log.createdAtUtc,
    );
  }

  /// The client-side UUID v4 every other table's `id` uses (§2), so an import id
  /// and a document id come from one source and an offline device never
  /// collides with another.
  static String _defaultIdGenerator() => _uuid.v4();
}

final Uuid _uuid = Uuid();
