// ignore_for_file: prefer_initializing_formals

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../db/daos/sync_dao.dart';
import 'drift_sync_snapshot_reader.dart';
import 'sync_contracts.dart';
import 'sync_payload_hasher.dart';

abstract interface class SyncOutboxWriter {
  /// Must be called inside the business repository's existing transaction.
  Future<SyncRequestId> enqueue({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required String actorUserId,
    required DateTime occurredAtUtc,
    required SyncPayload payload,
    int baseServerVersion = 0,
  });

  /// Builds the authoritative full local aggregate snapshot and enqueues it.
  /// Call this before the surrounding business transaction commits.
  Future<SyncRequestId> enqueueCurrentAggregate({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required String actorUserId,
    required DateTime occurredAtUtc,
    int? baseServerVersion,
  });

  /// Reconstructs a pre-v14 pending aggregate whose original actor cannot be
  /// proven. This operation is intentionally non-runnable and never adopts a
  /// session user.
  Future<SyncRequestId> enqueueBlockedOriginalActorUnknown({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required DateTime occurredAtUtc,
  });
}

final class NoopSyncOutboxWriter implements SyncOutboxWriter {
  const NoopSyncOutboxWriter();

  @override
  Future<SyncRequestId> enqueue({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required String actorUserId,
    required DateTime occurredAtUtc,
    required SyncPayload payload,
    int baseServerVersion = 0,
  }) async => const SyncRequestId('00000000-0000-4000-8000-000000000000');

  @override
  Future<SyncRequestId> enqueueCurrentAggregate({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required String actorUserId,
    required DateTime occurredAtUtc,
    int? baseServerVersion,
  }) async => const SyncRequestId('00000000-0000-4000-8000-000000000000');

  @override
  Future<SyncRequestId> enqueueBlockedOriginalActorUnknown({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required DateTime occurredAtUtc,
  }) async => const SyncRequestId('00000000-0000-4000-8000-000000000000');
}

final class DriftSyncOutboxWriter implements SyncOutboxWriter {
  DriftSyncOutboxWriter(
    AppDatabase database, {
    SyncPayloadHasher hasher = const Sha256SyncPayloadHasher(),
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _database = database,
       _dao = database.syncDao,
       _snapshots = DriftSyncSnapshotReader(database),
       _hasher = hasher,
       _uuid = uuid,
       _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final SyncDao _dao;
  final DriftSyncSnapshotReader _snapshots;
  final SyncPayloadHasher _hasher;
  final Uuid _uuid;
  final DateTime Function() _clock;

  Future<SyncDeviceRow> _requireDevice() async {
    final existing = await _dao.device();
    if (existing != null) return existing;
    final id = _uuid.v4();
    final now = _clock().toUtc();
    await _dao.putDevice(
      SyncDevicesCompanion.insert(
        id: Value(id),
        appInstallId: _uuid.v4(),
        createdAt: Value(now),
        lastSeenAt: Value(now),
      ),
    );
    return (await _dao.device())!;
  }

  @override
  Future<SyncRequestId> enqueue({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required String actorUserId,
    required DateTime occurredAtUtc,
    required SyncPayload payload,
    int baseServerVersion = 0,
  }) async {
    final device = await _requireDevice();
    final coalesced = await _dao.coalescible(
      operationType: operation.wireValue,
      aggregateType: aggregateType.wireValue,
      aggregateId: aggregateId,
      actorUserId: actorUserId,
    );
    final requestId = SyncRequestId(coalesced?.requestId ?? _uuid.v4());
    final envelope = SyncOperationEnvelope(
      requestId: requestId,
      deviceId: device.id,
      operation: operation,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      baseServerVersion: baseServerVersion,
      occurredAtUtc: occurredAtUtc,
      payload: payload,
    );
    final now = _clock().toUtc();
    final payloadHash = _hasher.hash(envelope.toJson());
    if (coalesced != null) {
      await _dao.refreshQueuedSnapshot(
        requestId: coalesced.requestId,
        payloadHash: payloadHash,
        baseServerVersion: baseServerVersion,
        occurredAtUtc: occurredAtUtc.toUtc(),
        nextAttemptEpochMs: now.millisecondsSinceEpoch,
        nowUtc: now,
      );
      return requestId;
    }
    await _dao.enqueue(
      SyncOutboxCompanion.insert(
        requestId: requestId.value,
        deviceId: device.id,
        operationType: operation.wireValue,
        aggregateType: aggregateType.wireValue,
        aggregateId: aggregateId,
        actorUserId: Value(actorUserId),
        baseServerVersion: Value(baseServerVersion),
        occurredAtUtc: occurredAtUtc.toUtc(),
        payloadHash: payloadHash,
        nextAttemptEpochMs: Value(now.millisecondsSinceEpoch),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return requestId;
  }

  @override
  Future<SyncRequestId> enqueueCurrentAggregate({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required String actorUserId,
    required DateTime occurredAtUtc,
    int? baseServerVersion,
  }) async {
    final payload = await _snapshots.read(
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    final state =
        await (_database.select(_database.syncEntityStates)..where(
              (row) =>
                  row.aggregateType.equals(aggregateType.wireValue) &
                  row.aggregateId.equals(aggregateId),
            ))
            .getSingleOrNull();
    return enqueue(
      operation: operation,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      actorUserId: actorUserId,
      occurredAtUtc: occurredAtUtc,
      payload: payload,
      baseServerVersion: baseServerVersion ?? state?.serverVersion ?? 0,
    );
  }

  @override
  Future<SyncRequestId> enqueueBlockedOriginalActorUnknown({
    required SyncOperationType operation,
    required SyncAggregateType aggregateType,
    required String aggregateId,
    required DateTime occurredAtUtc,
  }) async {
    final existing = await _dao.existingOperation(
      operationType: operation.wireValue,
      aggregateType: aggregateType.wireValue,
      aggregateId: aggregateId,
    );
    if (existing != null) return SyncRequestId(existing.requestId);
    final device = await _requireDevice();
    final requestId = SyncRequestId(_uuid.v4());
    final payload = await _snapshots.read(
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    final envelope = SyncOperationEnvelope(
      requestId: requestId,
      deviceId: device.id,
      operation: operation,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      baseServerVersion: 0,
      occurredAtUtc: occurredAtUtc,
      payload: payload,
    );
    final now = _clock().toUtc();
    await _dao.enqueue(
      SyncOutboxCompanion.insert(
        requestId: requestId.value,
        deviceId: device.id,
        operationType: operation.wireValue,
        aggregateType: aggregateType.wireValue,
        aggregateId: aggregateId,
        actorUserId: const Value(null),
        occurredAtUtc: occurredAtUtc.toUtc(),
        payloadHash: _hasher.hash(envelope.toJson()),
        status: const Value('blocked'),
        nextAttemptEpochMs: const Value(0),
        lastErrorCode: const Value(syncOriginalActorUnknownCode),
        lastErrorMessage: const Value(syncOriginalActorUnknownMessage),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return requestId;
  }
}

abstract interface class SyncOperationPlanner {
  Future<SyncOperationEnvelope> build(SyncOutboxRow row);
}
