import 'dart:async';
import 'dart:math';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/push_sync_worker.dart';
import 'package:aish_warehouse/core/sync/sync_contracts.dart';
import 'package:aish_warehouse/core/sync/sync_file_upload_queue.dart';
import 'package:aish_warehouse/core/sync/sync_outbox_writer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSyncOutboxWriter writer;
  final now = DateTime.utc(2026, 8, 2);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    writer = DriftSyncOutboxWriter(database, clock: () => now);
  });

  tearDown(() => database.close());

  Future<void> enqueue(String id, {String actor = 'actor-1'}) => writer.enqueue(
    operation: SyncOperationType.upsertMaster,
    aggregateType: SyncAggregateType.category,
    aggregateId: id,
    actorUserId: actor,
    occurredAtUtc: now,
    payload: JsonSyncPayload({'id': id, 'name': 'Category $id'}),
  );

  PushSyncWorker worker(
    PushSyncGateway gateway, {
    int batchSize = 20,
    SyncOperationPlanner? planner,
  }) => PushSyncWorker(
    database: database,
    gateway: gateway,
    planner: planner ?? const _StoredPlanner(),
    acknowledgement: _FakeAcknowledgement(database),
    retryPolicy: PushRetryPolicy(random: Random(1)),
    clock: () => now,
    batchSize: batchSize,
  );

  test(
    'accepted operations drain bounded batches until no due row remains',
    () async {
      await enqueue('one');
      await enqueue('two');
      await enqueue('three');
      final gateway = _AcceptedGateway();

      await worker(gateway, batchSize: 2).run(actorUserId: 'actor-1');

      expect(gateway.calls, 3);
      expect(await database.select(database.syncOutbox).get(), isEmpty);
    },
  );

  test('worker filters operations by original actor', () async {
    await enqueue('mine');
    await enqueue('theirs', actor: 'actor-2');
    final gateway = _AcceptedGateway();

    await worker(gateway).run(actorUserId: 'actor-1');

    expect(gateway.calls, 1);
    final remaining = await database.select(database.syncOutbox).get();
    expect(remaining.single.actorUserId, 'actor-2');
  });

  test(
    'unfinalized file blocks its dependent operation without retry',
    () async {
      await writer.enqueue(
        operation: SyncOperationType.appendImportAudit,
        aggregateType: SyncAggregateType.importAudit,
        aggregateId: 'file-blocked',
        actorUserId: 'actor-1',
        occurredAtUtc: now,
        payload: JsonSyncPayload({'id': 'file-blocked'}),
      );
      await DriftSyncFileUploadQueue(database).enqueue(
        entityType: SyncAggregateType.importAudit.wireValue,
        entityId: 'file-blocked',
        actorUserId: 'actor-1',
        localFilePath: '/private/not-rendered.xlsx',
        originalFileName: 'audit.xlsx',
        sha256: 'a' * 64,
        sizeBytes: 10,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        remoteBucket: 'import-audit',
      );
      final gateway = _AcceptedGateway();

      await worker(gateway).run(actorUserId: 'actor-1');

      final row = (await database.select(database.syncOutbox).get()).single;
      expect(gateway.calls, 0);
      expect(row.status, 'blocked');
      expect(row.attemptCount, 0);
    },
  );

  test('retryable failure increments attempt and schedules backoff', () async {
    await enqueue('retry');

    await worker(
      const _FailureGateway(
        SyncRetryableFailure('sync_retry_later', 'Coba lagi.'),
      ),
    ).run(actorUserId: 'actor-1');

    final row = (await database.select(database.syncOutbox).get()).single;
    expect(row.status, 'queued');
    expect(row.attemptCount, 1);
    expect(row.nextAttemptEpochMs, greaterThan(now.millisecondsSinceEpoch));
    expect(await database.select(database.syncAttemptLogs).get(), hasLength(1));
  });

  test('HTTP 429 is retryable and preserves its safe status', () async {
    await enqueue('rate-limited');

    await worker(
      const _FailureGateway(
        SyncRetryableFailure(
          'sync_retry_later',
          'Server sibuk.',
          httpStatus: 429,
        ),
      ),
    ).run(actorUserId: 'actor-1');

    final row = (await database.select(database.syncOutbox).get()).single;
    final attempt =
        (await database.select(database.syncAttemptLogs).get()).single;
    expect(row.status, 'queued');
    expect(attempt.httpStatus, 429);
  });

  test('security/permanent failure is conflicted without retry', () async {
    await enqueue('denied');
    final syncWorker = worker(
      const _FailureGateway(
        SyncPermanentFailure('sync_access_denied', 'Tidak diizinkan.'),
      ),
    );

    await syncWorker.run(actorUserId: 'actor-1');
    await syncWorker.run(actorUserId: 'actor-1');

    final row = (await database.select(database.syncOutbox).get()).single;
    expect(row.status, 'conflict');
    expect(row.attemptCount, 0);
  });

  test('changed aggregate hash is conflicted before network call', () async {
    await enqueue('changed');
    final gateway = _AcceptedGateway();

    await worker(
      gateway,
      planner: const _StoredPlanner(forceDifferentPayload: true),
    ).run(actorUserId: 'actor-1');

    expect(gateway.calls, 0);
    expect(
      (await database.select(database.syncOutbox).get()).single.status,
      'conflict',
    );
  });

  test(
    'coordinator is single-flight and cancellation is session-scoped',
    () async {
      await enqueue('single');
      final gateway = _BlockingGateway();
      final coordinator = PushSyncCoordinator(worker(gateway));

      final first = coordinator.trigger(actorUserId: 'actor-1');
      final second = coordinator.trigger(actorUserId: 'actor-1');
      expect(identical(first, second), isTrue);
      await gateway.started.future;
      expect(gateway.calls, 1);
      gateway.release.complete();
      await first;
      coordinator.dispose();
    },
  );

  test(
    'logout cancellation does not acknowledge an in-flight request',
    () async {
      await enqueue('logout');
      final gateway = _BlockingGateway();
      final coordinator = PushSyncCoordinator(worker(gateway));

      final inFlight = coordinator.trigger(actorUserId: 'actor-1');
      await gateway.started.future;
      coordinator.dispose();
      gateway.release.complete();
      await inFlight;

      final row = (await database.select(database.syncOutbox).get()).single;
      expect(row.status, 'processing');
      expect(row.leaseStartedEpochMs, isNotNull);
    },
  );
}

final class _StoredPlanner implements SyncOperationPlanner {
  const _StoredPlanner({this.forceDifferentPayload = false});
  final bool forceDifferentPayload;

  @override
  Future<SyncOperationEnvelope> build(SyncOutboxRow row) async =>
      SyncOperationEnvelope(
        requestId: SyncRequestId(row.requestId),
        deviceId: row.deviceId,
        operation: SyncOperationType.upsertMaster,
        aggregateType: SyncAggregateType.category,
        aggregateId: row.aggregateId,
        baseServerVersion: row.baseServerVersion,
        occurredAtUtc: row.occurredAtUtc,
        payload: JsonSyncPayload({
          'id': row.aggregateId,
          'name': forceDifferentPayload
              ? 'Changed'
              : 'Category ${row.aggregateId}',
        }),
      );
}

final class _FakeAcknowledgement implements SyncAcknowledgementApplier {
  const _FakeAcknowledgement(this.database);
  final AppDatabase database;

  @override
  Future<void> accept({
    required SyncOutboxRow outbox,
    required String pushedPayloadHash,
    required SyncAcceptedResult result,
  }) => database.syncDao.complete(outbox.requestId);

  @override
  Future<void> conflict({
    required SyncOutboxRow outbox,
    required SyncConflictResult result,
  }) => database.syncDao.markConflict(
    requestId: outbox.requestId,
    nowUtc: DateTime.utc(2026, 8, 2),
  );
}

class _AcceptedGateway implements PushSyncGateway {
  int calls = 0;

  @override
  Future<SyncPushResult> push(SyncOperationEnvelope envelope) async {
    calls++;
    return SyncAcceptedResult(
      requestId: envelope.requestId,
      serverVersion: 1,
      serverUpdatedAtUtc: DateTime.utc(2026, 8, 2),
    );
  }
}

final class _FailureGateway implements PushSyncGateway {
  const _FailureGateway(this.failure);
  final SyncPushFailure failure;

  @override
  Future<SyncPushResult> push(SyncOperationEnvelope envelope) =>
      Future<SyncPushResult>.error(failure);
}

final class _BlockingGateway extends _AcceptedGateway {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<SyncPushResult> push(SyncOperationEnvelope envelope) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    return SyncAcceptedResult(
      requestId: envelope.requestId,
      serverVersion: 1,
      serverUpdatedAtUtc: DateTime.utc(2026, 8, 2),
    );
  }
}
