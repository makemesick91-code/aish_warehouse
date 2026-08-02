import 'dart:async';
import 'dart:math';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/push_sync_worker.dart';
import 'package:aish_warehouse/core/sync/sync_contracts.dart';
import 'package:aish_warehouse/core/sync/sync_file_upload_queue.dart';
import 'package:aish_warehouse/core/sync/trusted_file_upload_worker.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSyncFileUploadQueue queue;
  final now = DateTime.utc(2026, 8, 2);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    queue = DriftSyncFileUploadQueue(database);
  });

  tearDown(() => database.close());

  Future<String> enqueue(String actor, String entity) => queue.enqueue(
    entityType: 'report_artifact',
    entityId: entity,
    actorUserId: actor,
    localFilePath: '/private/not-rendered.pdf',
    originalFileName: 'laporan.pdf',
    sha256: List.filled(64, 'a').join(),
    sizeBytes: 12,
    mimeType: 'application/pdf',
    remoteBucket: 'report-artifacts',
  );

  test('finalizes only uploads owned by the current actor', () async {
    await enqueue('actor-1', 'export-1');
    await enqueue('actor-2', 'export-2');
    final gateway = _FakeUploadGateway();
    final worker = TrustedFileUploadWorker(
      database: database,
      gateway: gateway,
      clock: () => now,
    );

    await worker.run(actorUserId: 'actor-1');

    expect(gateway.entities, ['export-1']);
    final rows = await database.select(database.syncFileUploads).get();
    expect(
      rows.singleWhere((row) => row.entityId == 'export-1').status,
      'finalized',
    );
    expect(
      rows.singleWhere((row) => row.entityId == 'export-2').status,
      'queued',
    );
  });

  test('retryable failure is queued with bounded backoff', () async {
    await enqueue('actor-1', 'export-1');
    final worker = TrustedFileUploadWorker(
      database: database,
      gateway: _FakeUploadGateway(
        failure: const SyncRetryableFailure(
          'sync_retry_later',
          'Akan dicoba lagi.',
        ),
      ),
      retryPolicy: PushRetryPolicy(random: Random(1)),
      clock: () => now,
    );

    await worker.run(actorUserId: 'actor-1');

    final row = (await database.select(database.syncFileUploads).get()).single;
    expect(row.status, 'queued');
    expect(row.attemptCount, 1);
    expect(row.nextAttemptEpochMs, greaterThan(now.millisecondsSinceEpoch));
    expect(row.lastErrorCode, 'sync_retry_later');
  });

  test('permanent failure becomes conflict and is not retried', () async {
    await enqueue('actor-1', 'export-1');
    final gateway = _FakeUploadGateway(
      failure: const SyncPermanentFailure(
        'sync_upload_hash_mismatch',
        'Hash tidak cocok.',
      ),
    );
    final worker = TrustedFileUploadWorker(
      database: database,
      gateway: gateway,
      clock: () => now,
    );

    await worker.run(actorUserId: 'actor-1');
    await worker.run(actorUserId: 'actor-1');

    final row = (await database.select(database.syncFileUploads).get()).single;
    expect(row.status, 'conflict');
    expect(row.attemptCount, 1);
    expect(gateway.entities, ['export-1']);
  });

  test('expired processing upload lease is recovered', () async {
    final requestId = await enqueue('actor-1', 'export-1');
    expect(
      await database.syncDao.acquireFileUploadLease(
        requestId: requestId,
        nowEpochMs: 10,
      ),
      isTrue,
    );

    expect(
      await database.syncDao.recoverExpiredFileUploadLeases(
        expiredBeforeEpochMs: 11,
      ),
      1,
    );
    expect(
      (await database.select(database.syncFileUploads).get()).single.status,
      'queued',
    );
  });

  test('logout cancellation does not finalize an in-flight upload', () async {
    await enqueue('actor-1', 'export-1');
    final gateway = _BlockingUploadGateway();
    final worker = TrustedFileUploadWorker(
      database: database,
      gateway: gateway,
      clock: () => now,
    );

    final inFlight = worker.run(actorUserId: 'actor-1');
    await gateway.started.future;
    worker.cancel();
    gateway.release.complete();
    await inFlight;

    final row = (await database.select(database.syncFileUploads).get()).single;
    expect(row.status, 'processing');
    expect(row.remoteObjectId, isNull);
  });
}

final class _FakeUploadGateway implements TrustedFileUploadGateway {
  _FakeUploadGateway({this.failure});

  final SyncPushFailure? failure;
  final List<String> entities = [];

  @override
  Future<TrustedFileUploadResult> upload({
    required String requestId,
    required String entityType,
    required String entityId,
    required String localFilePath,
    required String originalFileName,
    required String sha256,
    required int sizeBytes,
    required String mimeType,
    required String remoteBucket,
  }) async {
    entities.add(entityId);
    if (failure case final value?) throw value;
    return TrustedFileUploadResult(
      remoteObjectId: 'remote-$entityId',
      remoteObjectKey: 'safe/$entityId/$originalFileName',
    );
  }
}

final class _BlockingUploadGateway implements TrustedFileUploadGateway {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<TrustedFileUploadResult> upload({
    required String requestId,
    required String entityType,
    required String entityId,
    required String localFilePath,
    required String originalFileName,
    required String sha256,
    required int sizeBytes,
    required String mimeType,
    required String remoteBucket,
  }) async {
    started.complete();
    await release.future;
    return const TrustedFileUploadResult(
      remoteObjectId: 'remote-after-cancel',
      remoteObjectKey: 'safe/after-cancel',
    );
  }
}
