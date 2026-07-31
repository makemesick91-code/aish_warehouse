import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../gateways/master_import_gateways.dart';
import '../models/import_models.dart';
import '../models/master_admin_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_import_normalization_policy.dart';
import '../services/master_import_validation_engine.dart';
import 'master_admin_guard.dart';
import 'validate_master_import_use_case.dart';

/// Stage 2 of G-M3: **apply the import, atomically, in one transaction**.
///
/// ### It does not trust the preview
///
/// The UI hands this use case an *id*, and nothing else. Not the rows, not the
/// counts, not which rows were inserts. Everything is rebuilt from the retained
/// source file:
///
/// ```text
/// reload actor → load log → status must be validated
///   → read stored file → verify SHA-256 and size → reparse → revalidate
///   → BEGIN → recheck keys and usage → apply every row
///           → create locations → guarded validated→committed → COMMIT
/// ```
///
/// The re-parse is not belt-and-braces. Minutes can pass between preview and
/// commit, and in them another device can create the SKU this file was going to
/// insert, post a movement that locks a unit this file was going to change, or
/// deactivate the actor. A commit that replayed the preview's decisions would
/// apply a plan built against a database that no longer exists.
///
/// The hash check is the other half: it proves the bytes being re-parsed are the
/// bytes that were validated, so a source file swapped on disk cannot smuggle
/// rows past a preview somebody approved.
///
/// ### One transaction, and what "atomic" costs
///
/// [MasterAdminRepository.transaction] is opened **once**, around every write.
/// Not one per row and not one per chunk — every writer in the repository is
/// deliberately transaction-free for exactly this reason (§24). A failure on row
/// 9,998 of 10,000 rolls back all 9,997 before it, plus every stock location
/// created along the way, plus the status transition.
///
/// ### The guarded transition is the concurrency control
///
/// `UPDATE import_logs SET status='committed' WHERE id=? AND status='validated'`
/// runs **inside** the transaction. Two devices committing the same preview both
/// reach it; one matches a row and one matches none, and the loser throws
/// [ImportConcurrentUpdateFailure] from inside its transaction — taking every
/// master write it had queued down with it. Exactly one commit wins, exactly one
/// set of master effects lands, and no duplicate stock location is created.
///
/// ### A revalidation failure leaves everything as it was
///
/// Status stays `validated`, the source file stays, no master row moves, and the
/// operator can look at the new errors and decide. Nothing is silently repaired.
class CommitMasterImportUseCase with MasterAdminGuard {
  CommitMasterImportUseCase({
    required this.repository,
    required this.workbookReader,
    required this.sourceFileStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  @override
  final MasterAdminRepository repository;

  final MasterImportWorkbookReader workbookReader;
  final ImportSourceFileStore sourceFileStore;
  final DateTime Function() _clock;

  /// How many row writes are issued before the loop yields.
  ///
  /// Chunking is about not blocking the event loop for the whole of a 10,000-row
  /// commit; it is **not** about splitting the transaction, which stays open
  /// across every chunk (§58). A chunk boundary is a yield point, nothing more.
  static const int chunkSize = 250;

  Future<ImportCommitResult> call({
    required String actorUserId,
    required String importLogId,
  }) async {
    // 1–2. The actor, re-read. Checked again inside the transaction below.
    final actor = await requireSuperAdmin(actorUserId);

    // 3–4. The log, and its status.
    final log = await repository.importLogById(importLogId);
    if (log == null) {
      throw ImportInvalidStateFailure(
        'Data impor tidak ditemukan.',
        importId: importLogId,
        current: ImportStatus.discarded,
      );
    }
    _ensureCommittable(log);

    // 5–6. The retained bytes, and proof they are the ones that were validated.
    final storedPath = await repository.importLogStoredPath(importLogId);
    if (storedPath == null || !await sourceFileStore.exists(storedPath)) {
      throw ImportSourceFileMissingFailure(
        'File sumber impor ini tidak ditemukan lagi di perangkat, sehingga '
        'impor tidak dapat diterapkan. Unggah ulang file lalu validasi kembali.',
        importId: importLogId,
      );
    }
    final hashMatches = await sourceFileStore.verifyHash(
      storedPath: storedPath,
      expectedSha256: log.fileSha256,
      expectedSizeBytes: log.fileSizeBytes,
    );
    if (!hashMatches) {
      throw ImportSourceFileHashMismatchFailure(
        'File sumber impor ini sudah berubah sejak divalidasi, sehingga impor '
        'tidak dapat diterapkan. Unggah ulang file lalu validasi kembali.',
        importId: importLogId,
      );
    }
    final bytes = await sourceFileStore.readStoredSource(
      importId: importLogId,
      storedPath: storedPath,
    );

    // 7–9. Reparse and revalidate against the database **as it is now**.
    final workbook = workbookReader.read(
      entity: log.entity,
      bytes: bytes,
      fileName: log.fileName,
    );
    final snapshot = await MasterImportReferenceSnapshot.load(
      repository: repository,
      entity: log.entity,
      actorId: actor.id,
    );
    final revalidated = MasterImportValidationEngine.validate(
      entity: log.entity,
      workbook: workbook,
      snapshot: snapshot,
    );
    if (revalidated.summary.hasErrors) {
      // No master write, status unchanged, source retained. The operator sees
      // what changed under them and decides.
      throw ImportHasErrorsFailure(
        'Validasi ulang menemukan ${revalidated.summary.failedRows} baris '
        'bermasalah — data master berubah sejak pratinjau dibuat. Tidak ada '
        'data yang diterapkan. Unggah ulang file lalu validasi kembali.',
        failedRows: revalidated.summary.failedRows,
      );
    }
    if (revalidated.summary.totalRows == 0) {
      throw ImportHasErrorsFailure(
        'File ini tidak memiliki baris data untuk diterapkan.',
        failedRows: 0,
      );
    }

    // 10–20. One transaction, everything inside it.
    return repository.transaction(() async {
      // 11. The actor and the status, rechecked where a race would matter. The
      //     status recheck is the guarded UPDATE at the end; the actor is
      //     rechecked here because a demotion between step 1 and here must not
      //     be applied under the old authority.
      final reloadedActor = await repository.adminUserById(actorUserId);
      if (reloadedActor == null ||
          !reloadedActor.isActive ||
          reloadedActor.role != UserRole.superAdmin) {
        throw const MasterAdminAccessDeniedFailure(
          'Halaman Master Data & Import hanya untuk Super Admin.',
        );
      }

      // 12–13. Keys and historical usage, re-read *inside* the transaction. The
      //        snapshot above was taken outside it, and the two can differ by a
      //        movement posted a millisecond ago.
      final transactionSnapshot = await MasterImportReferenceSnapshot.load(
        repository: repository,
        entity: log.entity,
        actorId: reloadedActor.id,
      );
      final plan = MasterImportValidationEngine.validate(
        entity: log.entity,
        workbook: workbook,
        snapshot: transactionSnapshot,
      );
      if (plan.summary.hasErrors) {
        throw ImportHasErrorsFailure(
          'Validasi ulang menemukan ${plan.summary.failedRows} baris '
          'bermasalah saat impor dijalankan. Tidak ada data yang diterapkan.',
          failedRows: plan.summary.failedRows,
        );
      }

      // 14–16. Apply.
      final applied = await _apply(
        entity: log.entity,
        rows: plan.plan,
        snapshot: transactionSnapshot,
      );

      // 17–19. The guarded transition. Zero rows means somebody else won.
      final nowUtc = _clock().toUtc();
      final transitioned = await repository.transitionImportStatus(
        id: importLogId,
        from: ImportStatus.validated,
        to: ImportStatus.committed,
        // The **actual** counts, not the preview's prediction. They normally
        // match; when they do not, the audit records what happened rather than
        // what was expected.
        insertedRows: applied.inserted,
        updatedRows: applied.updated,
        nowUtc: nowUtc,
      );
      if (transitioned == 0) {
        throw ImportConcurrentUpdateFailure(
          'Impor ini baru saja diproses di perangkat lain. Muat ulang riwayat '
          'impor untuk melihat hasilnya.',
          importId: importLogId,
        );
      }

      return ImportCommitResult(
        importId: importLogId,
        entity: log.entity,
        insertedRows: applied.inserted,
        updatedRows: applied.updated,
        committedAtUtc: nowUtc,
      );
    });
  }

  void _ensureCommittable(ImportLog log) {
    if (log.status.isCommitted) {
      throw ImportAlreadyCommittedFailure(
        'Impor ini sudah diterapkan sebelumnya dan tidak dapat dijalankan '
        'ulang.',
        importId: log.id,
      );
    }
    if (log.status.isDiscarded) {
      throw ImportAlreadyDiscardedFailure(
        'Impor ini sudah dibatalkan dan tidak dapat diterapkan.',
        importId: log.id,
      );
    }
    if (!log.status.canCommit) {
      throw ImportInvalidStateFailure(
        'Impor ini belum siap diterapkan.',
        importId: log.id,
        current: log.status,
      );
    }
    if (log.failedRows > 0) {
      throw ImportHasErrorsFailure(
        'Impor ini memiliki ${log.failedRows} baris gagal, sehingga tidak '
        'dapat diterapkan. Perbaiki file lalu validasi ulang.',
        failedRows: log.failedRows,
      );
    }
  }

  // --- the row writers ---------------------------------------------------------
  //
  // Every one runs inside the caller's transaction and opens none of its own
  // (§24). None of them writes a balance, a movement or a workflow row: an
  // import creates master data and — for branches and rooms — the one stock
  // location §22 requires, and nothing else (§30, §57).

  Future<({int inserted, int updated})> _apply({
    required MasterEntityType entity,
    required List<ValidatedImportRow> rows,
    required MasterImportReferenceSnapshot snapshot,
  }) async {
    var inserted = 0;
    var updated = 0;
    var sinceYield = 0;

    for (final planned in rows) {
      switch (entity) {
        case MasterEntityType.branches:
          await _applyBranch(planned);
        case MasterEntityType.rooms:
          await _applyRoom(planned, snapshot);
        case MasterEntityType.users:
          await _applyUser(planned, snapshot);
        case MasterEntityType.itemCategories:
          await _applyCategory(planned);
        case MasterEntityType.items:
          await _applyItem(planned, snapshot);
        case MasterEntityType.itemBatches:
          await _applyBatch(planned, snapshot);
      }
      if (planned.action == ImportRowAction.insert) {
        inserted++;
      } else {
        updated++;
      }

      // A yield point, not a transaction boundary — see [chunkSize].
      sinceYield++;
      if (sinceYield >= chunkSize) {
        sinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }

    return (inserted: inserted, updated: updated);
  }

  Future<void> _applyBranch(ValidatedImportRow planned) async {
    final row = planned.row as BranchImportRow;
    if (planned.action == ImportRowAction.insert) {
      final branch = await repository.insertBranch(
        code: row.code,
        name: row.name,
        address: row.address,
        isActive: row.isActive,
      );
      // The same path the CRUD use case takes (§22): a branch created by
      // workbook gets its store exactly as one created by form does. An import
      // that inserted the row directly would produce branches that cannot
      // receive a shipment.
      await repository.ensureBranchStoreLocation(
        branchId: branch.id,
        branchName: row.name,
      );
      _requireExactlyOneLocation(
        await repository.branchStoreLocationCount(branch.id),
        MasterEntityType.branches,
      );
      return;
    }

    final id = planned.existingId!;
    final rowsAffected = await repository.updateBranch(
      id: id,
      name: row.name,
      address: row.address,
      isActive: row.isActive,
    );
    _requireRowWritten(rowsAffected);
    await repository.renameBranchStoreLocation(
      branchId: id,
      branchName: row.name,
    );
  }

  Future<void> _applyRoom(
    ValidatedImportRow planned,
    MasterImportReferenceSnapshot snapshot,
  ) async {
    final row = planned.row as RoomImportRow;
    final branchKey = MasterImportNormalizationPolicy.key(row.branchCode);
    final branch = snapshot.branchesByCode[branchKey]!.single;

    if (planned.action == ImportRowAction.insert) {
      final room = await repository.insertRoom(
        branchId: branch.id,
        code: row.code,
        name: row.name,
        isActive: row.isActive,
      );
      await repository.ensureRoomLocation(
        branchId: branch.id,
        roomId: room.id,
        roomName: row.name,
      );
      _requireExactlyOneLocation(
        await repository.roomLocationCount(room.id),
        MasterEntityType.rooms,
      );
      return;
    }

    final id = planned.existingId!;
    final rowsAffected = await repository.updateRoom(
      id: id,
      name: row.name,
      isActive: row.isActive,
    );
    _requireRowWritten(rowsAffected);
    await repository.renameRoomLocation(roomId: id, roomName: row.name);
  }

  Future<void> _applyUser(
    ValidatedImportRow planned,
    MasterImportReferenceSnapshot snapshot,
  ) async {
    final row = planned.row as UserImportRow;
    String? branchId;
    if (row.branchCode != null) {
      final key = MasterImportNormalizationPolicy.key(row.branchCode);
      branchId = snapshot.branchesByCode[key]!.single.id;
    }

    if (planned.action == ImportRowAction.insert) {
      await repository.insertUser(
        fullName: row.fullName,
        email: row.email,
        role: row.role,
        branchId: branchId,
        isActive: row.isActive,
      );
      return;
    }

    final rowsAffected = await repository.updateUser(
      id: planned.existingId!,
      fullName: row.fullName,
      role: row.role,
      branchId: branchId,
      isActive: row.isActive,
    );
    _requireRowWritten(rowsAffected);
  }

  Future<void> _applyCategory(ValidatedImportRow planned) async {
    final row = planned.row as CategoryImportRow;
    if (planned.action == ImportRowAction.insert) {
      await repository.insertCategory(row.name);
      return;
    }

    final id = planned.existingId!;
    // A category has no `is_active`, so restoring it *is* the update (§3.6). The
    // restore is attempted first and its zero-row result is fine: it means the
    // category was never archived.
    await repository.restoreCategory(id);
    final rowsAffected = await repository.updateCategory(
      id: id,
      name: row.name,
    );
    _requireRowWritten(rowsAffected);
  }

  Future<void> _applyItem(
    ValidatedImportRow planned,
    MasterImportReferenceSnapshot snapshot,
  ) async {
    final row = planned.row as ItemImportRow;
    final categoryKey = MasterImportNormalizationPolicy.key(row.categoryName);
    final category = snapshot.categoriesByName[categoryKey]!.single;

    if (planned.action == ImportRowAction.insert) {
      await repository.insertItem(
        sku: row.sku,
        name: row.name,
        categoryId: category.id,
        unit: row.unit,
        minStockRoom: row.minStockRoom,
        minStockBranch: row.minStockBranch,
        hasExpiry: row.hasExpiry,
        expiryAlertDays: row.expiryAlertDays,
        isActive: row.isActive,
      );
      return;
    }

    // Only the fields the historical policy allowed — the revalidation above
    // already refused the row if any protected one differed, so reaching here
    // means every value in this call is one the policy permits.
    final rowsAffected = await repository.updateItem(
      id: planned.existingId!,
      name: row.name,
      categoryId: category.id,
      unit: row.unit,
      minStockRoom: row.minStockRoom,
      minStockBranch: row.minStockBranch,
      hasExpiry: row.hasExpiry,
      expiryAlertDays: row.expiryAlertDays,
      isActive: row.isActive,
    );
    _requireRowWritten(rowsAffected);
  }

  Future<void> _applyBatch(
    ValidatedImportRow planned,
    MasterImportReferenceSnapshot snapshot,
  ) async {
    final row = planned.row as ItemBatchImportRow;
    final itemKey = MasterImportNormalizationPolicy.key(row.itemSku);
    final item = snapshot.itemsBySku[itemKey]!.single;

    if (planned.action == ImportRowAction.insert) {
      // A batch, and nothing else. No balance row, no inbound movement — stock
      // arrives through a document somebody raises (§30).
      await repository.insertBatch(
        itemId: item.id,
        batchNo: row.batchNo,
        expiryDate: row.expiryDate,
      );
      return;
    }

    final id = planned.existingId!;
    await repository.restoreBatch(id);
    final rowsAffected = await repository.updateBatch(
      id: id,
      expiryDate: row.expiryDate,
    );
    _requireRowWritten(rowsAffected);
  }

  void _requireRowWritten(int rowsAffected) {
    if (rowsAffected > 0) return;
    // Thrown from inside the transaction, so it takes every write before it back.
    throw const ImportCommitFailure(
      'Salah satu baris gagal diterapkan karena datanya baru saja berubah. '
      'Tidak ada data yang diterapkan.',
      importId: '',
    );
  }

  void _requireExactlyOneLocation(int count, MasterEntityType entity) {
    if (count == 1) return;
    throw MasterStockLocationIntegrityFailure(
      'Lokasi stok gagal disiapkan saat impor. Tidak ada data yang '
      'diterapkan.',
      entity: entity,
      locationCount: count,
    );
  }
}

/// Discards a validated import (§35).
///
/// Master data is untouched — it always was, because the preview never wrote any.
/// What changes is the audit row: `validated → discarded`, guarded on the current
/// status exactly as the commit's transition is, so a double discard produces one
/// winner and one refusal.
///
/// **The source file is retained.** A discarded import is still an import that
/// happened: somebody uploaded a file, looked at what it would do, and said no.
/// The counts and `error_detail` are retained for the same reason. Nothing in this
/// module deletes an audit row or its file, ever (G-M6).
class DiscardMasterImportUseCase with MasterAdminGuard {
  DiscardMasterImportUseCase({
    required this.repository,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  @override
  final MasterAdminRepository repository;

  final DateTime Function() _clock;

  Future<ImportLog> call({
    required String actorUserId,
    required String importLogId,
  }) async {
    await requireSuperAdmin(actorUserId);

    return repository.transaction(() async {
      final log = await repository.importLogById(importLogId);
      if (log == null) {
        throw ImportInvalidStateFailure(
          'Data impor tidak ditemukan.',
          importId: importLogId,
          current: ImportStatus.discarded,
        );
      }
      if (log.status.isCommitted) {
        throw ImportAlreadyCommittedFailure(
          'Impor ini sudah diterapkan dan tidak dapat dibatalkan.',
          importId: importLogId,
        );
      }
      if (log.status.isDiscarded) {
        throw ImportAlreadyDiscardedFailure(
          'Impor ini sudah dibatalkan sebelumnya.',
          importId: importLogId,
        );
      }

      final rows = await repository.transitionImportStatus(
        id: importLogId,
        from: ImportStatus.validated,
        to: ImportStatus.discarded,
        nowUtc: _clock().toUtc(),
      );
      if (rows == 0) {
        throw ImportConcurrentUpdateFailure(
          'Impor ini baru saja diproses di perangkat lain. Muat ulang riwayat '
          'impor untuk melihat hasilnya.',
          importId: importLogId,
        );
      }

      return (await repository.importLogById(importLogId))!;
    });
  }
}
