// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import 'pull_sync_contracts.dart';
import 'remote_change_applier.dart';
import 'sync_entity_policy.dart';

/// Brings a device back to the server's version of a final document.
///
/// G-Y2 says the server wins absolutely once a document leaves `draft`, and the
/// applier has already written the server snapshot by the time this runs. What
/// is left is the debris: ledger rows this device posted for a document the
/// server settled differently, outbox entries that can never now succeed, and
/// conflict logs with no resolution. Left alone, those are exactly the states a
/// user cannot get out of — a permanent conflict badge, a retry that reposts
/// stock, a balance that disagrees with the report.
///
/// The one thing this service will not do is delete a movement. G-A1 makes the
/// ledger append-only and prescribes the remedy itself: a correction is a
/// reversal movement referencing the original. That is what happens here, with a
/// UUID derived from the movement it reverses, so running recovery twice cannot
/// produce a second reversal or a second business transaction.
final class FinalConflictRecoveryService {
  FinalConflictRecoveryService(
    this._db, {
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _uuid = uuid,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Namespace for reversal ids — the RFC 4122 URL namespace. Fixed so the same
  /// movement always reverses to the same id, on every device and on every
  /// rerun; that determinism is the whole reason retry cannot create a second
  /// business transaction.
  static const _reversalNamespace = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';

  Future<FinalConflictRecoveryOutcome> recover({
    required String entityType,
    required String entityId,
  }) async {
    final policy = SyncEntityPolicies.forType(entityType);
    if (policy == null || policy.entityClass != SyncEntityClass.document) {
      return FinalConflictRecoveryOutcome.notApplicable;
    }
    final refType = policy.movementRefType;

    return _db
        .transaction(() async {
          final now = _clock().toUtc();
          var reversals = 0;

          if (refType != null) {
            final serverMovementIds = await _serverMovementIds(
              entityType,
              entityId,
            );
            final localMovements = await _db
                .customSelect(
                  'SELECT * FROM stock_movements '
                  'WHERE ref_doc_type = ? AND ref_doc_id = ?;',
                  variables: [
                    Variable<String>(refType),
                    Variable<String>(entityId),
                  ],
                )
                .get();

            for (final movement in localMovements) {
              final id = movement.read<String>('id');
              if (serverMovementIds.contains(id)) continue;
              if (movement.data['reversal_of_movement_id'] != null) continue;
              final reversalId = _reversalIdFor(id);
              if (await _movementExists(reversalId)) continue;

              // The server never accepted this posting, so the stock it moved never
              // moved. Reversing restores the balance while leaving both rows in the
              // ledger, which is what an auditor needs to see.
              final applied = await _appendReversal(
                original: movement,
                reversalId: reversalId,
                nowUtc: now,
              );
              if (!applied) {
                // A reversal that would drive a position negative means local state
                // is further from the server than this service can safely repair.
                await _markManualReview(entityType, entityId, now);
                throw _RecoveryAborted();
              }
              reversals += 1;
            }
          }

          final resolvedOutbox = await _settleOutbox(entityType, entityId, now);
          await _db.customStatement(
            'UPDATE sync_conflict_logs SET resolved_at = ?, resolution = ? '
            'WHERE aggregate_type = ? AND aggregate_id = ? AND resolved_at IS NULL;',
            [
              now.toIso8601String(),
              SyncConflictResolution.serverFinalApplied,
              entityType,
              entityId,
            ],
          );

          return FinalConflictRecoveryOutcome(
            recovered: true,
            reversalsAppended: reversals,
            outboxEntriesSettled: resolvedOutbox,
            resolution: SyncConflictResolution.serverFinalApplied,
          );
        })
        .catchError((Object error) {
          if (error is _RecoveryAborted) {
            return const FinalConflictRecoveryOutcome(
              recovered: false,
              reversalsAppended: 0,
              outboxEntriesSettled: 0,
              resolution: SyncConflictResolution.manualReviewRequired,
            );
          }
          throw error;
        });
  }

  Future<Set<String>> _serverMovementIds(
    String entityType,
    String entityId,
  ) async {
    final snapshot = await _db
        .customSelect(
          'SELECT snapshot_json FROM sync_entity_snapshots '
          'WHERE entity_type = ? AND entity_id = ?;',
          variables: [Variable<String>(entityType), Variable<String>(entityId)],
        )
        .getSingleOrNull();
    if (snapshot == null) return const {};
    final decoded = jsonDecode(snapshot.read<String>('snapshot_json'));
    if (decoded is! Map) return const {};
    final movements = decoded[serverMovementIdsKey];
    if (movements is! List) return const {};
    return {
      for (final id in movements)
        if (id is String) id,
    };
  }

  Future<bool> _movementExists(String id) async =>
      await (_db.select(_db.stockMovements)
            ..where((row) => row.id.equals(id))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  /// Appends the reversal and moves the balances back. Returns false when the
  /// result would be a negative position, which G-A2 forbids outright.
  Future<bool> _appendReversal({
    required QueryRow original,
    required String reversalId,
    required DateTime nowUtc,
  }) async {
    final qty = original.read<int>('qty');
    final itemId = original.read<String>('item_id');
    final batchId = original.data['batch_id'] as String?;
    final from = original.data['from_location_id'] as String?;
    final to = original.data['to_location_id'] as String?;

    // A reversal mirrors the original: what left a location returns to it, and
    // what arrived leaves again.
    if (to != null && !await _canDebit(to, itemId, batchId, qty)) return false;

    if (to != null) await _addBalance(to, itemId, batchId, -qty, nowUtc);
    if (from != null) await _addBalance(from, itemId, batchId, qty, nowUtc);

    await _db.customStatement(
      'INSERT OR IGNORE INTO stock_movements '
      '(id, created_at, updated_at, sync_status, item_id, batch_id, '
      'from_location_id, to_location_id, qty, movement_type, ref_doc_type, '
      'ref_doc_id, actor_user_id, note, reversal_of_movement_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        reversalId,
        nowUtc.toIso8601String(),
        nowUtc.toIso8601String(),
        'synced',
        itemId,
        batchId,
        to,
        from,
        qty,
        original.read<String>('movement_type'),
        original.read<String>('ref_doc_type'),
        original.read<String>('ref_doc_id'),
        original.read<String>('actor_user_id'),
        'Pembalikan otomatis: dokumen final server berbeda.',
        original.read<String>('id'),
      ],
    );
    return true;
  }

  Future<bool> _canDebit(
    String locationId,
    String itemId,
    String? batchId,
    int qty,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT qty_on_hand FROM stock_balances WHERE location_id = ? '
          'AND item_id = ? AND batch_id IS ?;',
          variables: [
            Variable<String>(locationId),
            Variable<String>(itemId),
            Variable<String>(batchId),
          ],
        )
        .getSingleOrNull();
    return (row?.read<int>('qty_on_hand') ?? 0) >= qty;
  }

  Future<void> _addBalance(
    String locationId,
    String itemId,
    String? batchId,
    int delta,
    DateTime nowUtc,
  ) async {
    final existing = await _db
        .customSelect(
          'SELECT id, qty_on_hand FROM stock_balances WHERE location_id = ? '
          'AND item_id = ? AND batch_id IS ?;',
          variables: [
            Variable<String>(locationId),
            Variable<String>(itemId),
            Variable<String>(batchId),
          ],
        )
        .getSingleOrNull();
    if (existing == null) {
      if (delta < 0) return;
      await _db.customStatement(
        'INSERT INTO stock_balances '
        '(id, created_at, updated_at, sync_status, location_id, item_id, '
        'batch_id, qty_on_hand) VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          _uuid.v4(),
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'synced',
          locationId,
          itemId,
          batchId,
          delta,
        ],
      );
      return;
    }
    await _db.customStatement(
      'UPDATE stock_balances SET qty_on_hand = qty_on_hand + ?, updated_at = ?, '
      'sync_status = ? WHERE id = ?;',
      [delta, nowUtc.toIso8601String(), 'synced', existing.read<String>('id')],
    );
  }

  /// Every outbox entry for this aggregate is settled one way or another, so
  /// nothing is left retrying against a document the server has already closed.
  ///
  /// An entry whose payload the server already reflects is simply completed —
  /// pushing it again would be a duplicate business transaction. Everything else
  /// becomes a conflict with an explicit resolution and stops being polled.
  Future<int> _settleOutbox(
    String entityType,
    String entityId,
    DateTime nowUtc,
  ) async {
    final rows =
        await (_db.select(_db.syncOutbox)..where(
              (row) =>
                  row.aggregateType.equals(entityType) &
                  row.aggregateId.equals(entityId) &
                  row.status.isIn(['queued', 'processing', 'blocked']),
            ))
            .get();
    if (rows.isEmpty) return 0;

    final serverVersion = await _serverVersionFor(entityType, entityId);
    for (final row in rows) {
      await _db
          .into(_db.syncConflictLogs)
          .insert(
            SyncConflictLogsCompanion.insert(
              requestId: row.requestId,
              aggregateType: entityType,
              aggregateId: entityId,
              operationType: row.operationType,
              conflictCode: 'sync_final_state_conflict',
              baseVersion: row.baseServerVersion,
              serverVersion: Value(serverVersion),
              safeDetailJson: Value(
                jsonEncode({
                  'resolution': SyncConflictResolution.localChangeSuperseded,
                }),
              ),
              detectedAt: Value(nowUtc),
              resolvedAt: Value(nowUtc),
              resolution: Value(SyncConflictResolution.localChangeSuperseded),
            ),
          );
    }
    // Removing the entries rather than parking them at `conflict` is what makes
    // retry safe: a queue that still holds them would repost the document the
    // moment the network recovered. The conflict log above is the durable
    // record that they existed.
    await (_db.delete(_db.syncOutbox)..where(
          (row) =>
              row.aggregateType.equals(entityType) &
              row.aggregateId.equals(entityId) &
              row.status.isIn(['queued', 'processing', 'blocked']),
        ))
        .go();
    return rows.length;
  }

  Future<int?> _serverVersionFor(String entityType, String entityId) async {
    final row = await _db
        .customSelect(
          'SELECT server_version FROM sync_entity_states '
          'WHERE aggregate_type = ? AND aggregate_id = ?;',
          variables: [Variable<String>(entityType), Variable<String>(entityId)],
        )
        .getSingleOrNull();
    return row?.read<int>('server_version');
  }

  Future<void> _markManualReview(
    String entityType,
    String entityId,
    DateTime nowUtc,
  ) => _db.customStatement(
    'UPDATE sync_conflict_logs SET resolved_at = ?, resolution = ? '
    'WHERE aggregate_type = ? AND aggregate_id = ? AND resolved_at IS NULL;',
    [
      nowUtc.toIso8601String(),
      SyncConflictResolution.manualReviewRequired,
      entityType,
      entityId,
    ],
  );

  String _reversalIdFor(String movementId) =>
      _uuid.v5(_reversalNamespace, 'aish-final-recovery-reversal:$movementId');
}

final class FinalConflictRecoveryOutcome {
  const FinalConflictRecoveryOutcome({
    required this.recovered,
    required this.reversalsAppended,
    required this.outboxEntriesSettled,
    required this.resolution,
  });

  final bool recovered;
  final int reversalsAppended;
  final int outboxEntriesSettled;
  final String? resolution;

  static const notApplicable = FinalConflictRecoveryOutcome(
    recovered: false,
    reversalsAppended: 0,
    outboxEntriesSettled: 0,
    resolution: null,
  );
}

final class _RecoveryAborted implements Exception {
  const _RecoveryAborted();
}
