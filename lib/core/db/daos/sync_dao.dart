import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/sync_tables.dart';

part 'sync_dao.g.dart';

@DriftAccessor(
  tables: [
    SyncDevices,
    SyncOutbox,
    SyncEntityStates,
    SyncAttemptLogs,
    SyncConflictLogs,
    SyncFileUploads,
  ],
)
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  Future<void> putDevice(SyncDevicesCompanion row) =>
      into(syncDevices).insert(row, mode: InsertMode.insertOrIgnore);

  Future<SyncDeviceRow?> device() =>
      (select(syncDevices)..limit(1)).getSingleOrNull();

  Future<void> enqueue(SyncOutboxCompanion row) =>
      into(syncOutbox).insert(row, mode: InsertMode.insertOrIgnore);

  Future<void> enqueueFileUpload(SyncFileUploadsCompanion row) =>
      into(syncFileUploads).insert(row, mode: InsertMode.insertOrIgnore);

  Future<List<SyncFileUploadRow>> dueFileUploadsForActor({
    required String actorUserId,
    required int nowEpochMs,
    int limit = 10,
  }) =>
      (select(syncFileUploads)
            ..where(
              (row) =>
                  row.actorUserId.equals(actorUserId) &
                  row.status.equals('queued') &
                  row.nextAttemptEpochMs.isSmallerOrEqualValue(nowEpochMs),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.id)])
            ..limit(limit))
          .get();

  Future<bool> acquireFileUploadLease({
    required String requestId,
    required int nowEpochMs,
  }) async {
    final changed =
        await (update(syncFileUploads)..where(
              (row) =>
                  row.requestId.equals(requestId) & row.status.equals('queued'),
            ))
            .write(
              SyncFileUploadsCompanion(
                status: const Value('processing'),
                leaseStartedEpochMs: Value(nowEpochMs),
              ),
            );
    return changed == 1;
  }

  Future<int> recoverExpiredFileUploadLeases({
    required int expiredBeforeEpochMs,
  }) =>
      (update(syncFileUploads)..where(
            (row) =>
                row.status.equals('processing') &
                row.leaseStartedEpochMs.isSmallerThanValue(
                  expiredBeforeEpochMs,
                ),
          ))
          .write(
            const SyncFileUploadsCompanion(
              status: Value('queued'),
              leaseStartedEpochMs: Value(null),
            ),
          );

  Future<void> requeueFileUpload({
    required String requestId,
    required int attemptCount,
    required int nextAttemptEpochMs,
    required String code,
    required String message,
  }) =>
      (update(
        syncFileUploads,
      )..where((row) => row.requestId.equals(requestId))).write(
        SyncFileUploadsCompanion(
          status: const Value('queued'),
          attemptCount: Value(attemptCount),
          nextAttemptEpochMs: Value(nextAttemptEpochMs),
          leaseStartedEpochMs: const Value(null),
          lastErrorCode: Value(code),
          lastErrorMessage: Value(message),
        ),
      );

  Future<void> finalizeFileUpload({
    required String requestId,
    required String remoteObjectId,
    required String remoteObjectKey,
  }) =>
      (update(
        syncFileUploads,
      )..where((row) => row.requestId.equals(requestId))).write(
        SyncFileUploadsCompanion(
          status: const Value('finalized'),
          remoteObjectId: Value(remoteObjectId),
          remoteObjectKey: Value(remoteObjectKey),
          leaseStartedEpochMs: const Value(null),
          lastErrorCode: const Value(null),
          lastErrorMessage: const Value(null),
        ),
      );

  Future<void> conflictFileUpload({
    required String requestId,
    required int attemptCount,
    required String code,
    required String message,
  }) =>
      (update(
        syncFileUploads,
      )..where((row) => row.requestId.equals(requestId))).write(
        SyncFileUploadsCompanion(
          status: const Value('conflict'),
          attemptCount: Value(attemptCount),
          leaseStartedEpochMs: const Value(null),
          lastErrorCode: Value(code),
          lastErrorMessage: Value(message),
        ),
      );

  Future<void> appendAttempt(SyncAttemptLogsCompanion row) =>
      into(syncAttemptLogs).insert(row);

  Future<SyncOutboxRow?> existingOperation({
    required String operationType,
    required String aggregateType,
    required String aggregateId,
  }) =>
      (select(syncOutbox)
            ..where(
              (row) =>
                  row.operationType.equals(operationType) &
                  row.aggregateType.equals(aggregateType) &
                  row.aggregateId.equals(aggregateId),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> refreshQueuedSnapshot({
    required String requestId,
    required String payloadHash,
    required int baseServerVersion,
    required DateTime occurredAtUtc,
    required int nextAttemptEpochMs,
    required DateTime nowUtc,
  }) =>
      (update(syncOutbox)..where(
            (row) =>
                row.requestId.equals(requestId) &
                row.status.isIn(['queued', 'blocked']),
          ))
          .write(
            SyncOutboxCompanion(
              payloadHash: Value(payloadHash),
              baseServerVersion: Value(baseServerVersion),
              occurredAtUtc: Value(occurredAtUtc),
              status: const Value('queued'),
              nextAttemptEpochMs: Value(nextAttemptEpochMs),
              lastErrorCode: const Value(null),
              lastErrorMessage: const Value(null),
              updatedAt: Value(nowUtc),
            ),
          );

  Future<void> refreshSnapshotPreservingState({
    required String requestId,
    required String payloadHash,
    required int baseServerVersion,
    required DateTime nowUtc,
  }) => (update(syncOutbox)..where((row) => row.requestId.equals(requestId)))
      .write(
        SyncOutboxCompanion(
          payloadHash: Value(payloadHash),
          baseServerVersion: Value(baseServerVersion),
          updatedAt: Value(nowUtc),
        ),
      );

  Future<SyncOutboxRow?> coalescible({
    required String operationType,
    required String aggregateType,
    required String aggregateId,
    required String actorUserId,
  }) =>
      (select(syncOutbox)
            ..where(
              (row) =>
                  row.operationType.equals(operationType) &
                  row.aggregateType.equals(aggregateType) &
                  row.aggregateId.equals(aggregateId) &
                  row.actorUserId.equals(actorUserId) &
                  row.status.isIn(['queued', 'blocked']),
            )
            ..limit(1))
          .getSingleOrNull();

  Future<List<SyncOutboxRow>> dueForActor({
    required String actorUserId,
    required int nowEpochMs,
    int limit = 20,
  }) =>
      (select(syncOutbox)
            ..where(
              (row) =>
                  row.actorUserId.equals(actorUserId) &
                  row.status.equals('queued') &
                  row.nextAttemptEpochMs.isSmallerOrEqualValue(nowEpochMs),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
            ..limit(limit))
          .get();

  Future<bool> acquireLease({
    required String requestId,
    required int nowEpochMs,
  }) async {
    final changed =
        await (update(syncOutbox)..where(
              (row) =>
                  row.requestId.equals(requestId) & row.status.equals('queued'),
            ))
            .write(
              SyncOutboxCompanion(
                status: const Value('processing'),
                leaseStartedEpochMs: Value(nowEpochMs),
                updatedAt: Value(
                  DateTime.fromMillisecondsSinceEpoch(nowEpochMs, isUtc: true),
                ),
              ),
            );
    return changed == 1;
  }

  Future<int> recoverExpiredLeases({
    required int expiredBeforeEpochMs,
    required DateTime nowUtc,
  }) =>
      (update(syncOutbox)..where(
            (row) =>
                row.status.equals('processing') &
                row.leaseStartedEpochMs.isSmallerThanValue(
                  expiredBeforeEpochMs,
                ),
          ))
          .write(
            SyncOutboxCompanion(
              status: const Value('queued'),
              leaseStartedEpochMs: const Value(null),
              updatedAt: Value(nowUtc),
            ),
          );

  Future<void> requeue({
    required String requestId,
    required int nextAttemptEpochMs,
    required String code,
    required String message,
    required DateTime nowUtc,
  }) async {
    final row =
        await (select(syncOutbox)
              ..where((candidate) => candidate.requestId.equals(requestId)))
            .getSingleOrNull();
    if (row == null) return;

    await (update(
      syncOutbox,
    )..where((candidate) => candidate.requestId.equals(requestId))).write(
      SyncOutboxCompanion(
        status: const Value('queued'),
        attemptCount: Value(row.attemptCount + 1),
        nextAttemptEpochMs: Value(nextAttemptEpochMs),
        leaseStartedEpochMs: const Value(null),
        lastErrorCode: Value(code),
        lastErrorMessage: Value(message),
        updatedAt: Value(nowUtc),
      ),
    );
  }

  Future<void> markConflict({
    required String requestId,
    required DateTime nowUtc,
  }) => (update(syncOutbox)..where((row) => row.requestId.equals(requestId)))
      .write(
        SyncOutboxCompanion(
          status: const Value('conflict'),
          leaseStartedEpochMs: const Value(null),
          updatedAt: Value(nowUtc),
        ),
      );

  Future<void> blockForDependency({
    required String requestId,
    required String message,
    required DateTime nowUtc,
  }) =>
      (update(syncOutbox)..where(
            (row) =>
                row.requestId.equals(requestId) & row.status.equals('queued'),
          ))
          .write(
            SyncOutboxCompanion(
              status: const Value('blocked'),
              leaseStartedEpochMs: const Value(null),
              lastErrorCode: const Value('sync_dependency_pending'),
              lastErrorMessage: Value(message),
              updatedAt: Value(nowUtc),
            ),
          );

  Future<void> blockOriginalActorUnknown({
    required String requestId,
    required DateTime nowUtc,
  }) => (update(syncOutbox)..where((row) => row.requestId.equals(requestId))).write(
    SyncOutboxCompanion(
      status: const Value('blocked'),
      leaseStartedEpochMs: const Value(null),
      lastErrorCode: const Value('sync_original_actor_unknown'),
      lastErrorMessage: const Value(
        'Tidak dapat disinkronkan karena akun pembuat data lama tidak dapat ditentukan.',
      ),
      updatedAt: Value(nowUtc),
    ),
  );

  Future<bool> hasUnfinalizedFileForAggregate({
    required String aggregateType,
    required String aggregateId,
    required String actorUserId,
  }) async {
    final fileEntityType = switch (aggregateType) {
      'import_audit' => 'import_audit',
      _ => null,
    };
    if (fileEntityType == null) return false;
    final row =
        await (select(syncFileUploads)
              ..where(
                (file) =>
                    file.entityType.equals(fileEntityType) &
                    file.entityId.equals(aggregateId) &
                    file.actorUserId.equals(actorUserId) &
                    file.status.isNotIn(['finalized']),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> unblockAuditForFinalizedFile({
    required String fileEntityType,
    required String entityId,
    required String actorUserId,
    required DateTime nowUtc,
  }) {
    final aggregateType = fileEntityType == 'import_audit'
        ? 'import_audit'
        : 'export_audit';
    return (update(syncOutbox)..where(
          (row) =>
              row.aggregateType.equals(aggregateType) &
              row.aggregateId.equals(entityId) &
              row.actorUserId.equals(actorUserId) &
              row.status.equals('blocked') &
              row.lastErrorCode.equals('sync_dependency_pending'),
        ))
        .write(
          SyncOutboxCompanion(
            status: const Value('queued'),
            nextAttemptEpochMs: Value(nowUtc.millisecondsSinceEpoch),
            lastErrorCode: const Value(null),
            lastErrorMessage: const Value(null),
            updatedAt: Value(nowUtc),
          ),
        );
  }

  Future<void> complete(String requestId) => (delete(
    syncOutbox,
  )..where((row) => row.requestId.equals(requestId))).go();

  Stream<int> watchPendingCount() =>
      (selectOnly(syncOutbox)
            ..addColumns([syncOutbox.id.count()])
            ..where(
              syncOutbox.status.isIn(['queued', 'processing', 'blocked']),
            ))
          .watchSingle()
          .map((row) => row.read(syncOutbox.id.count()) ?? 0);
}
