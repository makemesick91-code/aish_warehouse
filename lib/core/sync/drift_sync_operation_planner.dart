import '../db/app_database.dart';
import 'sync_contracts.dart';
import 'drift_sync_snapshot_reader.dart';
import 'sync_outbox_writer.dart';

final class DriftSyncOperationPlanner implements SyncOperationPlanner {
  DriftSyncOperationPlanner(this._db)
    : _snapshots = DriftSyncSnapshotReader(_db);
  final AppDatabase _db;
  final DriftSyncSnapshotReader _snapshots;

  @override
  Future<SyncOperationEnvelope> build(SyncOutboxRow row) async {
    final aggregateType = SyncAggregateType.values.firstWhere(
      (value) => value.wireValue == row.aggregateType,
    );
    final payload = await _snapshots.read(
      aggregateType: aggregateType,
      aggregateId: row.aggregateId,
    );
    final device = await _db.syncDao.device();
    if (device == null) {
      throw const SyncPermanentFailure(
        'sync_invalid_payload',
        'Identitas perangkat tidak tersedia.',
      );
    }
    return SyncOperationEnvelope(
      requestId: SyncRequestId(row.requestId),
      deviceId: device.id,
      operation: SyncOperationType.values.firstWhere(
        (value) => value.wireValue == row.operationType,
      ),
      aggregateType: aggregateType,
      aggregateId: row.aggregateId,
      baseServerVersion: row.baseServerVersion,
      occurredAtUtc: row.occurredAtUtc.toUtc(),
      payload: payload,
    );
  }
}
