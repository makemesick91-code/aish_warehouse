import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'sync_contracts.dart';
import 'sync_file_upload_queue.dart';
import 'sync_outbox_writer.dart';

/// Reconstructs only facts that are provable from the pre-v14 business schema.
///
/// No session identity is accepted by this API. Each workflow stage uses the
/// actor and timestamp stored by that stage. Pending master rows have no actor
/// provenance in schemas 1-13 and are therefore reconstructed as blocked.
final class RebuildPendingOutboxUseCase {
  RebuildPendingOutboxUseCase(
    this._db,
    this._writer, [
    this._fileQueue = const NoopSyncFileUploadQueue(),
  ]);

  final AppDatabase _db;
  final SyncOutboxWriter _writer;
  final SyncFileUploadQueue _fileQueue;

  static const _legacyStages = <_LegacyStage>[
    _LegacyStage(
      table: 'stock_opnames',
      actorColumn: 'counted_by',
      occurredAtColumn: 'submitted_at',
      condition: "status IN ('submitted','reviewed')",
      operation: SyncOperationType.submitOpname,
      aggregateType: SyncAggregateType.stockOpname,
    ),
    _LegacyStage(
      table: 'stock_opnames',
      actorColumn: 'reviewed_by',
      occurredAtColumn: 'reviewed_at',
      condition: "status = 'reviewed'",
      operation: SyncOperationType.reviewOpname,
      aggregateType: SyncAggregateType.stockOpname,
    ),
    _LegacyStage(
      table: 'purchase_requests',
      actorColumn: 'requested_by',
      occurredAtColumn: 'submitted_at',
      condition: "submitted_at IS NOT NULL AND status <> 'draft'",
      operation: SyncOperationType.submitPurchaseRequest,
      aggregateType: SyncAggregateType.purchaseRequest,
    ),
    _LegacyStage(
      table: 'purchase_requests',
      actorColumn: 'processed_by',
      occurredAtColumn: 'processing_at',
      condition: 'processing_at IS NOT NULL',
      operation: SyncOperationType.processPurchaseRequest,
      aggregateType: SyncAggregateType.purchaseRequest,
    ),
    _LegacyStage(
      table: 'purchase_requests',
      actorColumn: 'rejected_by',
      occurredAtColumn: 'rejected_at',
      condition: "status = 'rejected'",
      operation: SyncOperationType.rejectPurchaseRequest,
      aggregateType: SyncAggregateType.purchaseRequest,
    ),
    _LegacyStage(
      table: 'purchase_requests',
      actorColumn: 'cancelled_by',
      occurredAtColumn: 'cancelled_at',
      // A locally-cancelled draft was never submitted and has no remote effect.
      condition: "status = 'cancelled' AND submitted_at IS NOT NULL",
      operation: SyncOperationType.cancelPurchaseRequest,
      aggregateType: SyncAggregateType.purchaseRequest,
    ),
    _LegacyStage(
      table: 'delivery_orders',
      actorColumn: 'shipped_by',
      occurredAtColumn: 'shipped_at',
      condition: "status = 'shipped'",
      operation: SyncOperationType.shipDeliveryOrder,
      aggregateType: SyncAggregateType.deliveryOrder,
    ),
    _LegacyStage(
      table: 'good_receipts',
      actorColumn: 'received_by',
      occurredAtColumn: 'posted_at',
      condition: "status = 'posted'",
      operation: SyncOperationType.postGoodReceipt,
      aggregateType: SyncAggregateType.goodReceipt,
    ),
    _LegacyStage(
      table: 'distributions',
      actorColumn: 'distributed_by',
      occurredAtColumn: 'posted_at',
      condition: "status = 'posted'",
      operation: SyncOperationType.postDistribution,
      aggregateType: SyncAggregateType.distribution,
    ),
    _LegacyStage(
      table: 'disposals',
      actorColumn: 'posted_by',
      occurredAtColumn: 'posted_at',
      condition: "status = 'posted'",
      operation: SyncOperationType.postDisposal,
      aggregateType: SyncAggregateType.disposal,
    ),
    _LegacyStage(
      table: 'consumptions',
      actorColumn: 'posted_by',
      occurredAtColumn: 'posted_at',
      condition: "status = 'posted'",
      operation: SyncOperationType.postConsumption,
      aggregateType: SyncAggregateType.consumption,
    ),
    _LegacyStage(
      table: 'goods_returns',
      actorColumn: 'shipped_by',
      occurredAtColumn: 'shipped_at',
      condition: "status IN ('shipped','received')",
      operation: SyncOperationType.shipGoodsReturn,
      aggregateType: SyncAggregateType.goodsReturn,
    ),
    _LegacyStage(
      table: 'goods_returns',
      actorColumn: 'received_by',
      occurredAtColumn: 'received_at',
      condition: "status = 'received'",
      operation: SyncOperationType.receiveGoodsReturn,
      aggregateType: SyncAggregateType.goodsReturn,
    ),
    _LegacyStage(
      table: 'import_logs',
      actorColumn: 'imported_by',
      occurredAtColumn: 'updated_at',
      condition: '1 = 1',
      operation: SyncOperationType.appendImportAudit,
      aggregateType: SyncAggregateType.importAudit,
    ),
    _LegacyStage(
      table: 'export_logs',
      actorColumn: 'exported_by',
      occurredAtColumn: 'updated_at',
      condition: '1 = 1',
      operation: SyncOperationType.appendExportAudit,
      aggregateType: SyncAggregateType.exportAudit,
    ),
  ];

  static const _masterTables = <(String, SyncAggregateType)>[
    ('branches', SyncAggregateType.branch),
    ('rooms', SyncAggregateType.room),
    ('users', SyncAggregateType.user),
    ('item_categories', SyncAggregateType.category),
    ('items', SyncAggregateType.item),
    ('item_batches', SyncAggregateType.batch),
    ('stock_locations', SyncAggregateType.stockLocation),
  ];

  /// Auditable schema-to-operation provenance map used by migration tests.
  static List<
    ({
      SyncOperationType operation,
      SyncAggregateType aggregateType,
      String actorColumn,
      String occurredAtColumn,
    })
  >
  get auditedActorSources => List.unmodifiable([
    for (final stage in _legacyStages)
      (
        operation: stage.operation,
        aggregateType: stage.aggregateType,
        actorColumn: stage.actorColumn,
        occurredAtColumn: stage.occurredAtColumn,
      ),
  ]);

  Future<int> call() => _db.transaction(() async {
    var count = 0;
    for (final stage in _legacyStages) {
      final rows = await _db
          .customSelect(
            'SELECT id, ${stage.actorColumn} AS original_actor, '
            '${stage.occurredAtColumn} AS occurred_at '
            'FROM ${stage.table} WHERE sync_status = ? '
            'AND deleted_at IS NULL AND (${stage.condition}) ORDER BY id;',
            variables: [const Variable<String>('pending')],
          )
          .get();
      for (final row in rows) {
        final aggregateId = row.read<String>('id');
        final actor = row.readNullable<String>('original_actor');
        final occurredAt = row.readNullable<DateTime>('occurred_at');
        if (stage.aggregateType == SyncAggregateType.importAudit &&
            actor != null &&
            actor.trim().isNotEmpty) {
          // File-queue reconstruction is independently idempotent. Do it even
          // when the audit outbox already exists (for example after a crash
          // between the two inserts).
          await _enqueueImportFile(row, actor);
        }
        if (await _exists(stage, aggregateId)) continue;
        if (actor == null || actor.trim().isEmpty || occurredAt == null) {
          await _writer.enqueueBlockedOriginalActorUnknown(
            operation: stage.operation,
            aggregateType: stage.aggregateType,
            aggregateId: aggregateId,
            occurredAtUtc:
                occurredAt ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );
        } else {
          await _writer.enqueueCurrentAggregate(
            operation: stage.operation,
            aggregateType: stage.aggregateType,
            aggregateId: aggregateId,
            actorUserId: actor,
            occurredAtUtc: occurredAt.toUtc(),
          );
        }
        count++;
      }
    }

    // Schemas 1-13 did not persist actor provenance on master rows. A remote
    // mutation can therefore never be attributed safely. Existing remote
    // dependencies may still satisfy document RPC checks, but this local master
    // mutation itself remains blocked for administrative reconciliation in 12C.
    for (final entry in _masterTables) {
      final rows = await _db
          .customSelect(
            'SELECT id, updated_at FROM ${entry.$1} '
            'WHERE sync_status = ? ORDER BY id;',
            variables: [const Variable<String>('pending')],
          )
          .get();
      for (final row in rows) {
        final aggregateId = row.read<String>('id');
        final stage = _LegacyStage(
          table: entry.$1,
          actorColumn: '',
          occurredAtColumn: 'updated_at',
          condition: '',
          operation: SyncOperationType.upsertMaster,
          aggregateType: entry.$2,
        );
        if (await _exists(stage, aggregateId)) continue;
        await _writer.enqueueBlockedOriginalActorUnknown(
          operation: SyncOperationType.upsertMaster,
          aggregateType: entry.$2,
          aggregateId: aggregateId,
          occurredAtUtc: row.read<DateTime>('updated_at').toUtc(),
        );
        count++;
      }
    }
    return count;
  });

  Future<bool> _exists(_LegacyStage stage, String aggregateId) async =>
      await _db.syncDao.existingOperation(
        operationType: stage.operation.wireValue,
        aggregateType: stage.aggregateType.wireValue,
        aggregateId: aggregateId,
      ) !=
      null;

  Future<void> _enqueueImportFile(QueryRow summary, String actor) async {
    final row = await _db
        .customSelect(
          'SELECT stored_file_path, file_sha256, file_size_bytes, file_name '
          'FROM import_logs WHERE id = ?;',
          variables: [Variable<String>(summary.read<String>('id'))],
        )
        .getSingle();
    final path = row.readNullable<String>('stored_file_path');
    final hash = row.readNullable<String>('file_sha256');
    final size = row.readNullable<int>('file_size_bytes');
    if (path == null || hash == null || size == null || size <= 0) return;
    await _fileQueue.enqueue(
      entityType: 'import_audit',
      entityId: summary.read<String>('id'),
      actorUserId: actor,
      localFilePath: path,
      originalFileName: row.read<String>('file_name'),
      sha256: hash,
      sizeBytes: size,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      remoteBucket: 'import-audit',
    );
  }
}

final class _LegacyStage {
  const _LegacyStage({
    required this.table,
    required this.actorColumn,
    required this.occurredAtColumn,
    required this.condition,
    required this.operation,
    required this.aggregateType,
  });

  final String table;
  final String actorColumn;
  final String occurredAtColumn;
  final String condition;
  final SyncOperationType operation;
  final SyncAggregateType aggregateType;
}
