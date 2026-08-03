// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'entity_reconciler.dart';
import 'pull_sync_contracts.dart';
import 'sync_contracts.dart';
import 'sync_entity_policy.dart';
import 'sync_outbox_writer.dart';
import 'sync_value_codec.dart';

/// Key under which a document's baseline records the movement ids the server
/// reported. Prefixed so it can never collide with a real column name.
const serverMovementIdsKey = '__server_movement_ids';

/// What one batch did, for the cursor, the log and the Sync Center.
final class RemoteBatchOutcome {
  const RemoteBatchOutcome({
    required this.applied,
    required this.tombstones,
    required this.conflicts,
    required this.reconciledEntities,
    required this.finalRecoveries,
  });

  final int applied;
  final int tombstones;
  final int conflicts;

  /// Non-final entities whose local edits survived the merge and are still owed
  /// to the server, as `(entityType, entityId)`.
  final List<({String entityType, String entityId})> reconciledEntities;

  /// Final documents whose local state had to be replaced by the server's.
  final List<({String entityType, String entityId})> finalRecoveries;

  static const empty = RemoteBatchOutcome(
    applied: 0,
    tombstones: 0,
    conflicts: 0,
    reconciledEntities: [],
    finalRecoveries: [],
  );
}

/// Writes a pulled batch into the local database.
///
/// The caller runs this inside one Drift transaction together with the cursor
/// advance, so a failure on the Nth change rolls the whole batch back and the
/// cursor stays where it was. Every operation here is therefore written to be
/// re-runnable: applying the same batch twice must leave the database in exactly
/// the state applying it once does.
final class RemoteChangeApplier {
  RemoteChangeApplier(
    this._db, {
    EntityReconciler reconciler = const EntityReconciler(),
    DateTime Function()? clock,
  }) : _codec = SyncValueCodec(_db),
       _reconciler = reconciler,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final SyncValueCodec _codec;
  final EntityReconciler _reconciler;
  final DateTime Function() _clock;

  Future<RemoteBatchOutcome> applyAll(List<RemoteChange> changes) async {
    var applied = 0;
    var tombstones = 0;
    var conflicts = 0;
    final reconciled = <({String entityType, String entityId})>[];
    final recoveries = <({String entityType, String entityId})>[];

    for (final change in changes) {
      final policy = SyncEntityPolicies.forType(change.entityType);
      // An entity type this build does not know about is skipped rather than
      // failed. The cursor still advances past it, because refusing to move
      // would wedge every older client behind a newer server for good.
      if (policy == null) continue;

      final result = switch (change.operation) {
        RemoteChangeOperation.tombstone => await _applyTombstone(
          policy,
          change,
        ),
        RemoteChangeOperation.upsert => await _applyUpsert(policy, change),
      };
      applied += result.applied;
      tombstones += result.tombstones;
      conflicts += result.conflicts;
      reconciled.addAll(result.reconciledEntities);
      recoveries.addAll(result.finalRecoveries);
    }

    return RemoteBatchOutcome(
      applied: applied,
      tombstones: tombstones,
      conflicts: conflicts,
      reconciledEntities: reconciled,
      finalRecoveries: recoveries,
    );
  }

  // -------------------------------------------------------------------------
  // Tombstones
  // -------------------------------------------------------------------------

  Future<RemoteBatchOutcome> _applyTombstone(
    SyncEntityPolicy policy,
    RemoteChange change,
  ) async {
    if (!policy.tombstonable) {
      // The server should not have produced one, but an entity whose history is
      // load-bearing — a domain user, a branch that carries transactions, the
      // ledger — is never removed locally on the strength of a replicated
      // delete. G-A4 and G-A5 both point the same way.
      return RemoteBatchOutcome.empty;
    }

    final existing = await _tombstoneFor(change.entityType, change.entityId);
    if (existing != null && existing.serverVersion >= change.serverVersion) {
      // Already applied. Re-applying the same page must change nothing.
      return RemoteBatchOutcome.empty;
    }

    final local = await _localRow(policy.table, change.entityId);
    final now = _clock().toUtc();

    if (local != null) {
      // A soft delete, never a DELETE. Foreign keys keep resolving, the row
      // stays readable for history, and the audit trail survives (G-A5).
      await _db.customStatement(
        'UPDATE ${policy.table} SET deleted_at = ?, sync_status = ? '
        'WHERE id = ? AND deleted_at IS NULL;',
        [now.toIso8601String(), 'synced', change.entityId],
      );
      final child = policy.child;
      if (child != null) {
        await _db.customStatement(
          'UPDATE ${child.table} SET deleted_at = ?, sync_status = ? '
          'WHERE ${child.foreignKey} = ? AND deleted_at IS NULL;',
          [now.toIso8601String(), 'synced', change.entityId],
        );
      }
    }

    await _db.customStatement(
      'INSERT INTO sync_tombstones '
      '(id, entity_type, entity_id, server_version, tombstoned_at_utc, '
      'applied_at_utc, had_local_row) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(entity_type, entity_id) DO UPDATE SET '
      'server_version = excluded.server_version, '
      'tombstoned_at_utc = excluded.tombstoned_at_utc, '
      'applied_at_utc = excluded.applied_at_utc, '
      'had_local_row = had_local_row OR excluded.had_local_row;',
      [
        '${change.entityType}:${change.entityId}',
        change.entityType,
        change.entityId,
        change.serverVersion,
        change.serverChangedAtUtc.toIso8601String(),
        now.toIso8601String(),
        local != null ? 1 : 0,
      ],
    );

    // The baseline is no longer a description of anything, and leaving it would
    // let a later merge treat deleted values as a server opinion.
    await _db.customStatement(
      'DELETE FROM sync_entity_snapshots WHERE entity_type = ? AND entity_id = ?;',
      [change.entityType, change.entityId],
    );
    await _resolveOpenConflicts(
      change,
      SyncConflictResolution.tombstoneApplied,
    );

    return RemoteBatchOutcome(
      applied: local != null ? 1 : 0,
      tombstones: 1,
      conflicts: 0,
      reconciledEntities: const [],
      finalRecoveries: const [],
    );
  }

  // -------------------------------------------------------------------------
  // Upserts
  // -------------------------------------------------------------------------

  Future<RemoteBatchOutcome> _applyUpsert(
    SyncEntityPolicy policy,
    RemoteChange change,
  ) async {
    final payload = change.payload;
    if (payload == null) return RemoteBatchOutcome.empty;

    final tombstone = await _tombstoneFor(change.entityType, change.entityId);
    if (tombstone != null) {
      if (change.serverVersion <= tombstone.serverVersion) {
        // A device that was offline while this was deleted can still be holding
        // an older view of it. Applying that view would resurrect the record.
        return RemoteBatchOutcome.empty;
      }
      // A strictly newer version means the server itself brought it back. The
      // local soft delete has to be lifted explicitly: `deleted_at` is excluded
      // from the merge on purpose — deletion travels as a tombstone, not as a
      // negotiated column — so nothing else would ever clear it.
      await _db.customStatement(
        'DELETE FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?;',
        [change.entityType, change.entityId],
      );
      if (payload['deleted_at'] == null) {
        await _db.customStatement(
          'UPDATE ${policy.table} SET deleted_at = NULL WHERE id = ?;',
          [change.entityId],
        );
        final child = policy.child;
        if (child != null) {
          await _db.customStatement(
            'UPDATE ${child.table} SET deleted_at = NULL '
            'WHERE ${child.foreignKey} = ?;',
            [change.entityId],
          );
        }
      }
    }

    return switch (policy.entityClass) {
      SyncEntityClass.ledger => _applyLedgerRow(policy, change, payload),
      SyncEntityClass.balance => _applyReplacement(policy, change, payload),
      SyncEntityClass.master => _applyMaster(policy, change, payload),
      SyncEntityClass.document => _applyDocument(policy, change, payload),
    };
  }

  /// A movement is inserted once by its UUID and never touched again (G-A1,
  /// G-Y5). Re-applying a page cannot duplicate one, and no pulled state can
  /// rewrite one that already exists.
  Future<RemoteBatchOutcome> _applyLedgerRow(
    SyncEntityPolicy policy,
    RemoteChange change,
    Map<String, Object?> payload,
  ) async {
    final inserted = await _insertIfAbsent(policy.table, payload);
    await _recordSnapshot(policy, change, payload);
    return RemoteBatchOutcome(
      applied: inserted ? 1 : 0,
      tombstones: 0,
      conflicts: 0,
      reconciledEntities: const [],
      finalRecoveries: const [],
    );
  }

  /// A balance is a cache of the ledger and the server's copy is definitive.
  Future<RemoteBatchOutcome> _applyReplacement(
    SyncEntityPolicy policy,
    RemoteChange change,
    Map<String, Object?> payload,
  ) async {
    await _upsertRow(policy.table, payload, syncStatus: 'synced');
    await _recordSnapshot(policy, change, payload);
    return const RemoteBatchOutcome(
      applied: 1,
      tombstones: 0,
      conflicts: 0,
      reconciledEntities: [],
      finalRecoveries: [],
    );
  }

  Future<RemoteBatchOutcome> _applyMaster(
    SyncEntityPolicy policy,
    RemoteChange change,
    Map<String, Object?> payload,
  ) async {
    final serverRow = _codec.canonicalRow(policy.table, payload);
    final local = await _localRow(policy.table, change.entityId);

    if (local == null) {
      await _upsertRow(policy.table, payload, syncStatus: 'synced');
      await _recordSnapshot(policy, change, payload);
      await _recordFieldVersions(change);
      return const RemoteBatchOutcome(
        applied: 1,
        tombstones: 0,
        conflicts: 0,
        reconciledEntities: [],
        finalRecoveries: [],
      );
    }

    final baseline = await _baselineFor(policy, change.entityId);
    final decision = _reconciler.reconcile(
      policy: policy,
      serverRow: serverRow,
      localRow: local,
      baseline: baseline,
      fieldVersions: change.fieldVersions,
      baseServerVersion: await _baseServerVersion(change),
    );

    await _writeDecision(
      policy: policy,
      entityId: change.entityId,
      decision: decision,
      // A column this device still owes the server keeps the row pending, so the
      // push worker picks it up again rather than treating the pull as closure.
      syncStatus: decision.hasLocalWork ? 'pending' : 'synced',
    );
    await _recordSnapshot(policy, change, payload);
    await _recordFieldVersions(change);

    if (decision.hasLocalWork) {
      await _reEnqueuePreservedWork(policy, change);
    }

    final resolution = decision.resolution;
    if (resolution != null) {
      await _logConflict(
        change: change,
        code: decision.immutableConflictFields.isNotEmpty
            ? 'sync_immutable_field_conflict'
            : 'sync_field_merge',
        resolution: resolution,
        fields: {
          ...decision.supersededFields,
          ...decision.immutableConflictFields,
        },
      );
    }

    return RemoteBatchOutcome(
      applied: 1,
      tombstones: 0,
      conflicts: decision.hasConflict ? 1 : 0,
      reconciledEntities: decision.hasLocalWork
          ? [(entityType: change.entityType, entityId: change.entityId)]
          : const [],
      finalRecoveries: const [],
    );
  }

  /// A document is never merged per column. Once it leaves `draft` the server
  /// owns its state machine, its numbering and its posting facts (G-Y2), so the
  /// server snapshot is written whole — header, lines and movements together, in
  /// this transaction, which is what makes a partial document impossible.
  Future<RemoteBatchOutcome> _applyDocument(
    SyncEntityPolicy policy,
    RemoteChange change,
    Map<String, Object?> payload,
  ) async {
    final local = await _localRow(policy.table, change.entityId);
    final serverStatus = payload['status'] as String?;
    final localStatus = local?['status'] as String?;
    final isFinal = policy.isFinalStatus(serverStatus);

    final hadLocalDivergence =
        local != null &&
        (localStatus != serverStatus || local['sync_status'] != 'synced');

    await _upsertRow(policy.table, payload, syncStatus: 'synced');
    await _replaceChildren(policy, change.entityId, payload);
    await _applyDocumentMovements(policy, change.entityId, payload);
    await _recordSnapshot(policy, change, payload);

    if (hadLocalDivergence) {
      await _logConflict(
        change: change,
        code: isFinal
            ? 'sync_final_state_conflict'
            : 'sync_document_superseded',
        resolution: isFinal
            ? SyncConflictResolution.serverFinalApplied
            : SyncConflictResolution.localChangeSuperseded,
        fields: const {'status'},
      );
    } else {
      await _resolveOpenConflicts(
        change,
        SyncConflictResolution.serverFinalApplied,
      );
    }

    return RemoteBatchOutcome(
      applied: 1,
      tombstones: 0,
      conflicts: hadLocalDivergence ? 1 : 0,
      reconciledEntities: const [],
      finalRecoveries: isFinal && hadLocalDivergence
          ? [(entityType: change.entityType, entityId: change.entityId)]
          : const [],
    );
  }

  /// Lines the server no longer lists are soft-deleted rather than removed, for
  /// the reason G-A5 gives: the row is history even once it stops being current.
  Future<void> _replaceChildren(
    SyncEntityPolicy policy,
    String entityId,
    Map<String, Object?> payload,
  ) async {
    for (final child in [
      if (policy.child != null) policy.child!,
      ...policy.extraChildren,
    ]) {
      final rows = payload[child.payloadKey];
      if (rows is! List) continue;
      final keptIds = <String>[];
      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, Object?>.from(raw);
        final id = row['id'] as String?;
        if (id == null) continue;
        keptIds.add(id);
        await _upsertRow(child.table, row, syncStatus: 'synced');
      }
      final placeholders = List.filled(keptIds.length, '?').join(',');
      await _db.customStatement(
        'UPDATE ${child.table} SET deleted_at = ?, sync_status = ? '
        'WHERE ${child.foreignKey} = ? AND deleted_at IS NULL'
        '${keptIds.isEmpty ? '' : ' AND id NOT IN ($placeholders)'};',
        [_clock().toUtc().toIso8601String(), 'synced', entityId, ...keptIds],
      );
    }
  }

  Future<void> _applyDocumentMovements(
    SyncEntityPolicy policy,
    String entityId,
    Map<String, Object?> payload,
  ) async {
    if (policy.movementRefType == null) return;
    final movements = payload['movements'];
    if (movements is! List) return;
    for (final raw in movements) {
      if (raw is! Map) continue;
      await _insertIfAbsent('stock_movements', Map<String, Object?>.from(raw));
    }
  }

  // -------------------------------------------------------------------------
  // Row helpers
  // -------------------------------------------------------------------------

  Future<Map<String, Object?>?> _localRow(String table, String id) async {
    final row = await _db
        .customSelect(
          'SELECT * FROM $table WHERE id = ?;',
          variables: [Variable<String>(id)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return _codec.canonicalRow(table, row.data);
  }

  /// Insert-or-ignore by primary key. Returns whether a row was created.
  Future<bool> _insertIfAbsent(String table, Map<String, Object?> row) async {
    final columns = [
      for (final entry in row.entries)
        if (_codec.hasColumn(table, entry.key)) entry.key,
    ];
    if (columns.isEmpty) return false;
    final before = await _db
        .customSelect(
          'SELECT 1 AS present FROM $table WHERE id = ?;',
          variables: [Variable<String>(row['id'] as String)],
        )
        .getSingleOrNull();
    if (before != null) return false;
    await _db.customStatement(
      'INSERT OR IGNORE INTO $table (${columns.join(',')}) '
      'VALUES (${List.filled(columns.length, '?').join(',')});',
      [
        for (final column in columns)
          _codec.sqlValue(table, column, row[column]),
      ],
    );
    return true;
  }

  Future<void> _upsertRow(
    String table,
    Map<String, Object?> row, {
    required String syncStatus,
  }) async {
    final values = <String, Object?>{
      for (final entry in row.entries)
        if (_codec.hasColumn(table, entry.key)) entry.key: entry.value,
    };
    if (_codec.hasColumn(table, 'sync_status')) {
      values['sync_status'] = syncStatus;
    }
    final columns = values.keys.toList();
    final assignments = [
      for (final column in columns)
        if (column != 'id') '$column = excluded.$column',
    ];
    await _db.customStatement(
      'INSERT INTO $table (${columns.join(',')}) '
      'VALUES (${List.filled(columns.length, '?').join(',')}) '
      'ON CONFLICT(id) DO UPDATE SET ${assignments.join(', ')};',
      [
        for (final column in columns)
          _codec.sqlValue(table, column, values[column]),
      ],
    );
  }

  Future<void> _writeDecision({
    required SyncEntityPolicy policy,
    required String entityId,
    required EntityMergeDecision decision,
    required String syncStatus,
  }) async {
    final writable = <String, Object?>{
      for (final entry in decision.values.entries)
        if (_codec.hasColumn(policy.table, entry.key) &&
            entry.key != 'id' &&
            !SyncEntityPolicies.alwaysExcludedFields.contains(entry.key))
          entry.key: entry.value,
    };
    writable['sync_status'] = syncStatus;
    if (writable.isEmpty) return;
    final assignments = [for (final column in writable.keys) '$column = ?'];
    await _db.customStatement(
      'UPDATE ${policy.table} SET ${assignments.join(', ')} WHERE id = ?;',
      [
        for (final column in writable.keys)
          _codec.sqlValue(policy.table, column, writable[column]),
        entityId,
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Reconciliation bookkeeping
  // -------------------------------------------------------------------------

  /// Puts a merged aggregate back on the outbox so the column this device kept
  /// actually reaches the server.
  ///
  /// Without this the merge would be a private opinion: the row is marked
  /// `pending`, but the push worker only reads the outbox, and the queued entry
  /// it *would* have found still carries the pre-merge payload hash — so it would
  /// be rejected as `sync_payload_hash_mismatch` rather than sent.
  ///
  /// The actor is taken from the existing outbox entry, never from the session
  /// running the pull. A device can be shared, and attributing one user's
  /// surviving edit to whoever happens to be signed in would be exactly the
  /// reassignment Milestone 12B refuses to do. With no entry to read an actor
  /// from there is no provable author, so the row simply stays `pending` and
  /// waits for its own workflow to enqueue it.
  Future<void> _reEnqueuePreservedWork(
    SyncEntityPolicy policy,
    RemoteChange change,
  ) async {
    final existing = await _db.syncDao.existingOperation(
      operationType: SyncOperationType.upsertMaster.wireValue,
      aggregateType: change.entityType,
      aggregateId: change.entityId,
    );
    final actorUserId = existing?.actorUserId;
    if (actorUserId == null) return;
    final aggregateType = SyncAggregateType.values
        .where((value) => value.wireValue == change.entityType)
        .firstOrNull;
    if (aggregateType == null) return;
    await DriftSyncOutboxWriter(_db).enqueueCurrentAggregate(
      operation: SyncOperationType.upsertMaster,
      aggregateType: aggregateType,
      aggregateId: change.entityId,
      actorUserId: actorUserId,
      occurredAtUtc: _clock().toUtc(),
      // Rebased on what the server just told us, so the push is no longer stale.
      baseServerVersion: change.serverVersion,
    );
  }

  Future<Map<String, Object?>?> _baselineFor(
    SyncEntityPolicy policy,
    String entityId,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT snapshot_json FROM sync_entity_snapshots '
          'WHERE entity_type = ? AND entity_id = ?;',
          variables: [
            Variable<String>(policy.entityType),
            Variable<String>(entityId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final decoded = jsonDecode(row.read<String>('snapshot_json'));
    if (decoded is! Map) return null;
    return _codec.canonicalRow(
      policy.table,
      Map<String, Object?>.from(decoded),
    );
  }

  Future<int> _baseServerVersion(RemoteChange change) async {
    final row = await _db
        .customSelect(
          'SELECT server_version FROM sync_entity_states '
          'WHERE aggregate_type = ? AND aggregate_id = ?;',
          variables: [
            Variable<String>(change.entityType),
            Variable<String>(change.entityId),
          ],
        )
        .getSingleOrNull();
    if (row != null) return row.read<int>('server_version');
    final snapshot = await _db
        .customSelect(
          'SELECT server_version FROM sync_entity_snapshots '
          'WHERE entity_type = ? AND entity_id = ?;',
          variables: [
            Variable<String>(change.entityType),
            Variable<String>(change.entityId),
          ],
        )
        .getSingleOrNull();
    return snapshot?.read<int>('server_version') ?? 0;
  }

  /// Stores the server state as the baseline of the *next* merge.
  ///
  /// Only the header is kept. Lines and movements are replaced wholesale rather
  /// than merged, so a baseline for them would describe a decision nobody makes.
  Future<void> _recordSnapshot(
    SyncEntityPolicy policy,
    RemoteChange change,
    Map<String, Object?> payload,
  ) async {
    final header = <String, Object?>{
      for (final entry in payload.entries)
        if (_codec.hasColumn(policy.table, entry.key)) entry.key: entry.value,
    };
    // The ids — not the rows — of the movements the server says belong to this
    // document. Final-conflict recovery needs to tell a posting the server
    // accepted from one only this device made, and this is the only durable
    // record of which was which. Ids alone keep the baseline small and carry no
    // quantity or location that a later merge could misread as an opinion.
    final movements = payload['movements'];
    if (movements is List) {
      header[serverMovementIdsKey] = [
        for (final movement in movements)
          if (movement is Map && movement['id'] is String) movement['id'],
      ];
    }
    await _db.customStatement(
      'INSERT INTO sync_entity_snapshots '
      '(id, entity_type, entity_id, server_version, server_changed_at_utc, '
      'snapshot_json, applied_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(entity_type, entity_id) DO UPDATE SET '
      'server_version = excluded.server_version, '
      'server_changed_at_utc = excluded.server_changed_at_utc, '
      'snapshot_json = excluded.snapshot_json, '
      'applied_at_utc = excluded.applied_at_utc;',
      [
        '${change.entityType}:${change.entityId}',
        change.entityType,
        change.entityId,
        change.serverVersion,
        change.serverChangedAtUtc.toIso8601String(),
        jsonEncode(header),
        _clock().toUtc().toIso8601String(),
      ],
    );
    await _db.customStatement(
      'INSERT INTO sync_entity_states '
      '(id, aggregate_type, aggregate_id, server_version, server_updated_at_utc) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(aggregate_type, aggregate_id) DO UPDATE SET '
      'server_version = excluded.server_version, '
      'server_updated_at_utc = excluded.server_updated_at_utc;',
      [
        'pull:${change.entityType}:${change.entityId}',
        change.entityType,
        change.entityId,
        change.serverVersion,
        change.serverChangedAtUtc.toIso8601String(),
      ],
    );
  }

  Future<void> _recordFieldVersions(RemoteChange change) async {
    for (final entry in change.fieldVersions.entries) {
      await _db.customStatement(
        'INSERT INTO sync_field_versions '
        '(id, entity_type, entity_id, field_name, field_version) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(entity_type, entity_id, field_name) DO UPDATE SET '
        'field_version = excluded.field_version;',
        [
          '${change.entityType}:${change.entityId}:${entry.key}',
          change.entityType,
          change.entityId,
          entry.key,
          entry.value,
        ],
      );
    }
  }

  Future<SyncTombstoneRow?> _tombstoneFor(String entityType, String entityId) =>
      (_db.select(_db.syncTombstones)..where(
            (row) =>
                row.entityType.equals(entityType) &
                row.entityId.equals(entityId),
          ))
          .getSingleOrNull();

  /// Conflict detail is deliberately thin: the field names involved and a stable
  /// code. No value, no server message, no identifier beyond the ones the device
  /// already holds.
  Future<void> _logConflict({
    required RemoteChange change,
    required String code,
    required String resolution,
    required Set<String> fields,
  }) async {
    final now = _clock().toUtc();
    await _db
        .into(_db.syncConflictLogs)
        .insert(
          SyncConflictLogsCompanion.insert(
            requestId: 'pull:${change.changeSeq}',
            aggregateType: change.entityType,
            aggregateId: change.entityId,
            operationType: 'pull_reconcile',
            conflictCode: code,
            baseVersion: await _baseServerVersion(change),
            serverVersion: Value(change.serverVersion),
            safeDetailJson: Value(
              jsonEncode({
                'fields': fields.toList()..sort(),
                'resolution': resolution,
              }),
            ),
            detectedAt: Value(now),
            resolvedAt: Value(now),
            resolution: Value(resolution),
          ),
        );
  }

  /// Closes conflicts the server has now answered, so the Sync Center never
  /// shows a permanent unexplained conflict for an entity that has since been
  /// reconciled.
  Future<void> _resolveOpenConflicts(
    RemoteChange change,
    String resolution,
  ) => _db.customStatement(
    'UPDATE sync_conflict_logs SET resolved_at = ?, resolution = ? '
    'WHERE aggregate_type = ? AND aggregate_id = ? AND resolved_at IS NULL;',
    [
      _clock().toUtc().toIso8601String(),
      resolution,
      change.entityType,
      change.entityId,
    ],
  );
}
