// ignore_for_file: prefer_initializing_formals

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

abstract interface class SyncFileUploadQueue {
  Future<String> enqueue({
    required String entityType,
    required String entityId,
    required String actorUserId,
    required String localFilePath,
    required String originalFileName,
    required String sha256,
    required int sizeBytes,
    required String mimeType,
    required String remoteBucket,
  });
}

final class NoopSyncFileUploadQueue implements SyncFileUploadQueue {
  const NoopSyncFileUploadQueue();

  @override
  Future<String> enqueue({
    required String entityType,
    required String entityId,
    required String actorUserId,
    required String localFilePath,
    required String originalFileName,
    required String sha256,
    required int sizeBytes,
    required String mimeType,
    required String remoteBucket,
  }) async => '00000000-0000-4000-8000-000000000000';
}

final class DriftSyncFileUploadQueue implements SyncFileUploadQueue {
  DriftSyncFileUploadQueue(this._database, {Uuid uuid = const Uuid()})
    : _uuid = uuid;

  final AppDatabase _database;
  final Uuid _uuid;

  @override
  Future<String> enqueue({
    required String entityType,
    required String entityId,
    required String actorUserId,
    required String localFilePath,
    required String originalFileName,
    required String sha256,
    required int sizeBytes,
    required String mimeType,
    required String remoteBucket,
  }) async {
    final existing =
        await (_database.select(_database.syncFileUploads)..where(
              (row) =>
                  row.entityType.equals(entityType) &
                  row.entityId.equals(entityId) &
                  row.actorUserId.equals(actorUserId) &
                  row.sha256.equals(sha256),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.requestId;

    final requestId = _uuid.v4();
    await _database.syncDao.enqueueFileUpload(
      SyncFileUploadsCompanion.insert(
        requestId: requestId,
        entityType: entityType,
        entityId: entityId,
        actorUserId: actorUserId,
        localFilePath: localFilePath,
        originalFileName: originalFileName,
        sha256: sha256,
        sizeBytes: sizeBytes,
        mimeType: mimeType,
        remoteBucket: remoteBucket,
      ),
    );
    return requestId;
  }
}
