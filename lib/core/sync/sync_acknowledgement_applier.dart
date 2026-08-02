import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'drift_sync_snapshot_reader.dart';
import 'push_sync_worker.dart';
import 'sync_contracts.dart';
import 'sync_outbox_writer.dart';
import 'sync_payload_hasher.dart';

final class DriftSyncAcknowledgementApplier
    implements SyncAcknowledgementApplier {
  DriftSyncAcknowledgementApplier(this._db);
  final AppDatabase _db;

  static const _businessTable = <String, String>{
    'branch': 'branches',
    'room': 'rooms',
    'user': 'users',
    'category': 'item_categories',
    'item': 'items',
    'batch': 'item_batches',
    'stock_location': 'stock_locations',
    'stock_opname': 'stock_opnames',
    'purchase_request': 'purchase_requests',
    'delivery_order': 'delivery_orders',
    'good_receipt': 'good_receipts',
    'distribution': 'distributions',
    'disposal': 'disposals',
    'consumption': 'consumptions',
    'goods_return': 'goods_returns',
    'import_audit': 'import_logs',
    'export_audit': 'export_logs',
  };
  static const _refType = <String, String>{
    'stock_opname': 'SO',
    'delivery_order': 'DO',
    'good_receipt': 'GR',
    'distribution': 'DIST',
    'disposal': 'DSP',
    'consumption': 'CONS',
    'goods_return': 'RET',
  };
  static const _children = <String, (String, String)>{
    'stock_opname': ('stock_opname_lines', 'opname_id'),
    'purchase_request': ('purchase_request_lines', 'pr_id'),
    'delivery_order': ('delivery_order_lines', 'do_id'),
    'good_receipt': ('good_receipt_lines', 'gr_id'),
    'distribution': ('distribution_lines', 'distribution_id'),
    'disposal': ('disposal_lines', 'disposal_id'),
    'consumption': ('consumption_lines', 'consumption_id'),
    'goods_return': ('goods_return_lines', 'goods_return_id'),
  };

  @override
  Future<void> accept({
    required SyncOutboxRow outbox,
    required String pushedPayloadHash,
    required SyncAcceptedResult result,
  }) => _db.transaction(() async {
    final current =
        await (_db.select(_db.syncOutbox)
              ..where((row) => row.requestId.equals(outbox.requestId)))
            .getSingleOrNull();
    if (current == null || current.payloadHash != pushedPayloadHash) return;
    final table = _businessTable[current.aggregateType];
    if (table == null) return;
    final aggregateType = SyncAggregateType.values.firstWhere(
      (value) => value.wireValue == current.aggregateType,
    );
    final latestPayload = await DriftSyncSnapshotReader(
      _db,
    ).read(aggregateType: aggregateType, aggregateId: current.aggregateId);
    final latestEnvelope = SyncOperationEnvelope(
      requestId: SyncRequestId(current.requestId),
      deviceId: current.deviceId,
      operation: SyncOperationType.values.firstWhere(
        (value) => value.wireValue == current.operationType,
      ),
      aggregateType: aggregateType,
      aggregateId: current.aggregateId,
      baseServerVersion: current.baseServerVersion,
      occurredAtUtc: current.occurredAtUtc,
      payload: latestPayload,
    );
    final aggregateChanged =
        const Sha256SyncPayloadHasher().hash(latestEnvelope.toJson()) !=
        pushedPayloadHash;
    final finalNumber = result.finalDocumentNumber;
    if (finalNumber != null) {
      await _db.customStatement(
        'UPDATE $table SET doc_number = CASE WHEN doc_number LIKE ? '
        'THEN ? ELSE doc_number END WHERE id = ?;',
        ['TMP-%', finalNumber, current.aggregateId],
      );
    }
    final successors =
        await (_db.select(_db.syncOutbox)..where(
              (row) =>
                  row.requestId.equals(current.requestId).not() &
                  row.aggregateType.equals(current.aggregateType) &
                  row.aggregateId.equals(current.aggregateId) &
                  row.status.isIn(['queued', 'processing', 'blocked']),
            ))
            .get();
    if (!aggregateChanged && successors.isEmpty) {
      await _db.customStatement(
        'UPDATE $table SET sync_status = ? WHERE id = ?;',
        ['synced', current.aggregateId],
      );
      final child = _children[current.aggregateType];
      if (child != null) {
        await _db.customStatement(
          'UPDATE ${child.$1} SET sync_status = ? WHERE ${child.$2} = ? '
          'AND deleted_at IS NULL;',
          ['synced', current.aggregateId],
        );
      }
    }
    final ref = _refType[current.aggregateType];
    if (ref != null && !aggregateChanged && successors.isEmpty) {
      await _db.customStatement(
        'UPDATE stock_movements SET sync_status = ? '
        'WHERE ref_doc_type = ? AND ref_doc_id = ?;',
        ['synced', ref, current.aggregateId],
      );
    }
    await _db
        .into(_db.syncEntityStates)
        .insertOnConflictUpdate(
          SyncEntityStatesCompanion.insert(
            aggregateType: current.aggregateType,
            aggregateId: current.aggregateId,
            serverVersion: Value(result.serverVersion),
            serverUpdatedAtUtc: Value(result.serverUpdatedAtUtc),
            lastSyncedPayloadHash: Value(pushedPayloadHash),
            lastSyncedRequestId: Value(current.requestId),
          ),
        );
    await _db
        .into(_db.syncAttemptLogs)
        .insert(
          SyncAttemptLogsCompanion.insert(
            requestId: current.requestId,
            attemptNumber: current.attemptCount + 1,
            startedAt: current.updatedAt,
            finishedAt: DateTime.now().toUtc(),
            outcome: result is SyncReplayResult ? 'replayed' : 'accepted',
          ),
        );
    await (_db.delete(
      _db.syncOutbox,
    )..where((row) => row.requestId.equals(current.requestId))).go();
    if (!aggregateChanged && successors.isNotEmpty) {
      final successorPayload = await DriftSyncSnapshotReader(
        _db,
      ).read(aggregateType: aggregateType, aggregateId: current.aggregateId);
      final now = DateTime.now().toUtc();
      for (final successor in successors) {
        // An unknown-actor operation remains blocked. Refreshing its snapshot
        // is harmless but unnecessary; more importantly, no code path may turn
        // it into an executable operation.
        if (successor.actorUserId == null) continue;
        final envelope = SyncOperationEnvelope(
          requestId: SyncRequestId(successor.requestId),
          deviceId: successor.deviceId,
          operation: SyncOperationType.values.firstWhere(
            (value) => value.wireValue == successor.operationType,
          ),
          aggregateType: aggregateType,
          aggregateId: successor.aggregateId,
          baseServerVersion: result.serverVersion,
          occurredAtUtc: successor.occurredAtUtc,
          payload: successorPayload,
        );
        await _db.syncDao.refreshSnapshotPreservingState(
          requestId: successor.requestId,
          payloadHash: const Sha256SyncPayloadHasher().hash(envelope.toJson()),
          baseServerVersion: result.serverVersion,
          nowUtc: now,
        );
      }
    }
    if (aggregateChanged) {
      await DriftSyncOutboxWriter(_db).enqueueCurrentAggregate(
        operation: latestEnvelope.operation,
        aggregateType: aggregateType,
        aggregateId: current.aggregateId,
        actorUserId: current.actorUserId!,
        occurredAtUtc: DateTime.now().toUtc(),
        baseServerVersion: result.serverVersion,
      );
    }
  });

  @override
  Future<void> conflict({
    required SyncOutboxRow outbox,
    required SyncConflictResult result,
  }) => _db.transaction(() async {
    final table = _businessTable[outbox.aggregateType];
    if (table != null) {
      await _db.customStatement(
        'UPDATE $table SET sync_status = ? WHERE id = ?;',
        ['conflict', outbox.aggregateId],
      );
      final child = _children[outbox.aggregateType];
      if (child != null) {
        await _db.customStatement(
          'UPDATE ${child.$1} SET sync_status = ? WHERE ${child.$2} = ? '
          'AND deleted_at IS NULL;',
          ['conflict', outbox.aggregateId],
        );
      }
      final ref = _refType[outbox.aggregateType];
      if (ref != null) {
        await _db.customStatement(
          'UPDATE stock_movements SET sync_status = ? '
          'WHERE ref_doc_type = ? AND ref_doc_id = ?;',
          ['conflict', ref, outbox.aggregateId],
        );
      }
    }
    await _db
        .into(_db.syncConflictLogs)
        .insert(
          SyncConflictLogsCompanion.insert(
            requestId: outbox.requestId,
            aggregateType: outbox.aggregateType,
            aggregateId: outbox.aggregateId,
            operationType: outbox.operationType,
            conflictCode: result.code,
            baseVersion: result.baseVersion,
            serverVersion: Value(result.serverVersion),
            safeDetailJson: Value(jsonEncode({'message': result.safeMessage})),
          ),
        );
    await (_db.update(
      _db.syncOutbox,
    )..where((row) => row.requestId.equals(outbox.requestId))).write(
      SyncOutboxCompanion(
        status: const Value('conflict'),
        leaseStartedEpochMs: const Value(null),
        lastErrorCode: Value(result.code),
        lastErrorMessage: Value(result.safeMessage),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    await _db
        .into(_db.syncAttemptLogs)
        .insert(
          SyncAttemptLogsCompanion.insert(
            requestId: outbox.requestId,
            attemptNumber: outbox.attemptCount + 1,
            startedAt: outbox.updatedAt,
            finishedAt: DateTime.now().toUtc(),
            outcome: 'conflict',
            safeErrorCode: Value(result.code),
            safeErrorMessage: Value(result.safeMessage),
          ),
        );
  });
}
