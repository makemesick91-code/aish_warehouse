// ignore_for_file: prefer_initializing_formals

import '../db/app_database.dart';
import '../db/daos/sync_dao.dart';
import 'push_sync_worker.dart';
import 'sync_contracts.dart';

/// Foreground-only, bounded trusted upload worker. It stores no bytes in logs
/// and filters every row by the original local actor.
final class TrustedFileUploadWorker {
  TrustedFileUploadWorker({
    required AppDatabase database,
    required TrustedFileUploadGateway gateway,
    PushRetryPolicy? retryPolicy,
    SyncLeasePolicy? leasePolicy,
    DateTime Function()? clock,
    this.batchSize = 5,
  }) : _dao = database.syncDao,
       _database = database,
       _gateway = gateway,
       _retryPolicy = retryPolicy ?? PushRetryPolicy(),
       _leasePolicy = leasePolicy ?? const SyncLeasePolicy(),
       _clock = clock ?? DateTime.now;

  final SyncDao _dao;
  final AppDatabase _database;
  final TrustedFileUploadGateway _gateway;
  final PushRetryPolicy _retryPolicy;
  final SyncLeasePolicy _leasePolicy;
  final DateTime Function() _clock;
  final int batchSize;
  bool _running = false;
  bool _cancelled = false;

  bool get isRunning => _running;

  void cancel() => _cancelled = true;

  Future<void> run({required String actorUserId}) async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    try {
      final now = _clock().toUtc();
      await _dao.recoverExpiredFileUploadLeases(
        expiredBeforeEpochMs: now
            .subtract(_leasePolicy.duration)
            .millisecondsSinceEpoch,
      );
      while (!_cancelled) {
        final rows = await _dao.dueFileUploadsForActor(
          actorUserId: actorUserId,
          nowEpochMs: _clock().toUtc().millisecondsSinceEpoch,
          limit: batchSize,
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          if (_cancelled) break;
          final leaseAt = _clock().toUtc();
          if (!await _dao.acquireFileUploadLease(
            requestId: row.requestId,
            nowEpochMs: leaseAt.millisecondsSinceEpoch,
          )) {
            continue;
          }
          await _uploadOne(row);
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _uploadOne(SyncFileUploadRow row) async {
    try {
      final result = await _gateway.upload(
        requestId: row.requestId,
        entityType: row.entityType,
        entityId: row.entityId,
        localFilePath: row.localFilePath,
        originalFileName: row.originalFileName,
        sha256: row.sha256,
        sizeBytes: row.sizeBytes,
        mimeType: row.mimeType,
        remoteBucket: row.remoteBucket,
      );
      // As with push acknowledgement, do not mutate local session state after
      // logout/account-switch cancellation. The finalized server object is
      // idempotently discoverable on the next original-actor run.
      if (_cancelled) return;
      final now = _clock().toUtc();
      await _database.transaction(() async {
        await _dao.finalizeFileUpload(
          requestId: row.requestId,
          remoteObjectId: result.remoteObjectId,
          remoteObjectKey: result.remoteObjectKey,
        );
        await _dao.unblockAuditForFinalizedFile(
          fileEntityType: row.entityType,
          entityId: row.entityId,
          actorUserId: row.actorUserId,
          nowUtc: now,
        );
      });
    } on SyncRetryableFailure catch (failure) {
      final now = _clock().toUtc();
      final attempt = row.attemptCount + 1;
      await _dao.requeueFileUpload(
        requestId: row.requestId,
        attemptCount: attempt,
        nextAttemptEpochMs: now
            .add(_retryPolicy.delayForAttempt(attempt))
            .millisecondsSinceEpoch,
        code: failure.code,
        message: failure.safeMessage,
      );
    } on SyncPermanentFailure catch (failure) {
      await _dao.conflictFileUpload(
        requestId: row.requestId,
        attemptCount: row.attemptCount + 1,
        code: failure.code,
        message: failure.safeMessage,
      );
    }
  }
}
