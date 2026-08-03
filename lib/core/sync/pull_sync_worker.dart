// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'final_conflict_recovery_service.dart';
import 'pull_sync_contracts.dart';
import 'remote_change_applier.dart';
import 'sync_cursor_repository.dart';

/// Backoff for a pull that could not complete. Mirrors the push worker's policy
/// so a device under a failing network behaves the same in both directions.
final class PullRetryPolicy {
  PullRetryPolicy({Random? random}) : _random = random ?? Random.secure();
  final Random _random;

  Duration delayForAttempt(int attempt) {
    final exponent = max(0, min(attempt - 1, 8));
    final baseMs = min(300000, 1000 * (1 << exponent));
    final jitterMs = _random.nextInt(max(1, baseMs ~/ 4));
    return Duration(milliseconds: min(300000, baseMs + jitterMs));
  }
}

/// One completed pull cycle, as the orchestrator and the UI see it.
final class PullCycleResult {
  const PullCycleResult({
    required this.batches,
    required this.applied,
    required this.tombstones,
    required this.conflicts,
    required this.cursor,
    required this.reachedEnd,
    this.scopeReset = false,
    this.failureCode,
    this.retryAfter,
    this.reconciledEntities = const [],
  });

  final int batches;
  final int applied;
  final int tombstones;
  final int conflicts;
  final int cursor;
  final bool reachedEnd;
  final bool scopeReset;
  final String? failureCode;
  final Duration? retryAfter;

  /// Non-final entities whose local edits survived and are owed to the server.
  final List<({String entityType, String entityId})> reconciledEntities;

  bool get succeeded => failureCode == null;
}

/// Drains the server change feed into the local database.
///
/// Single-flight, bounded per batch, and cancellable. The invariant the whole
/// design rests on lives in [_applyBatch]: the batch and the cursor move inside
/// one transaction, so there is no state in which a change has been applied but
/// forgotten, or forgotten but applied.
final class PullSyncWorker {
  PullSyncWorker({
    required AppDatabase database,
    required PullSyncGateway gateway,
    required SyncCursorRepository cursors,
    RemoteChangeApplier? applier,
    FinalConflictRecoveryService? recovery,
    PullRetryPolicy? retryPolicy,
    DateTime Function()? clock,
    this.batchSize = 200,
    this.maxBatchesPerCycle = 50,
  }) : _db = database,
       _gateway = gateway,
       _cursors = cursors,
       _applier = applier ?? RemoteChangeApplier(database, clock: clock),
       _recovery =
           recovery ?? FinalConflictRecoveryService(database, clock: clock),
       _retryPolicy = retryPolicy ?? PullRetryPolicy(),
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final PullSyncGateway _gateway;
  final SyncCursorRepository _cursors;
  final RemoteChangeApplier _applier;
  final FinalConflictRecoveryService _recovery;
  final PullRetryPolicy _retryPolicy;
  final DateTime Function() _clock;
  final int batchSize;

  /// A stop so a device that is very far behind cannot hold the app in one
  /// unbounded cycle. The remaining pages are picked up by the next trigger,
  /// which is safe precisely because the cursor is durable.
  final int maxBatchesPerCycle;

  bool _running = false;
  bool _cancelled = false;
  int _attempt = 0;

  bool get isRunning => _running;

  void cancel() => _cancelled = true;

  Future<PullCycleResult> run({
    required String actorUserId,
    required String deviceId,
    List<String>? entityTypes,
  }) async {
    if (_running) {
      return const PullCycleResult(
        batches: 0,
        applied: 0,
        tombstones: 0,
        conflicts: 0,
        cursor: 0,
        reachedEnd: false,
      );
    }
    _running = true;
    _cancelled = false;
    final startedAt = _clock().toUtc();
    var batches = 0;
    var applied = 0;
    var tombstones = 0;
    var conflicts = 0;
    var scopeReset = false;
    final reconciled = <({String entityType, String entityId})>[];
    String? knownFingerprint;
    var cursor = 0;
    var startCursor = 0;

    try {
      while (!_cancelled && batches < maxBatchesPerCycle) {
        // The fingerprint is only known after the first response, so the first
        // request of a cycle asks from whatever position any scope of this actor
        // last reached; a mismatch is corrected below before anything is applied.
        cursor = knownFingerprint == null
            ? await _resumeCursor(actorUserId)
            : await _cursors.cursorFor(
                actorUserId: actorUserId,
                scopeFingerprint: knownFingerprint,
              );
        if (batches == 0) startCursor = cursor;

        final RemoteChangeBatch batch;
        try {
          batch = await _gateway.pull(
            cursor: cursor,
            limit: batchSize,
            deviceId: deviceId,
            entityTypes: entityTypes,
          );
        } on PullSyncCursorResetRequired {
          // The position no longer addresses anything readable. Applied rows,
          // baselines and tombstones stay; only the position is discarded, and
          // re-applying from zero is idempotent.
          await _resetEveryScope(actorUserId);
          scopeReset = true;
          knownFingerprint = null;
          if (batches > 0) break;
          continue;
        }

        if (_cancelled) break;

        if (knownFingerprint != null &&
            batch.scopeFingerprint != knownFingerprint) {
          // Role or branch changed mid-cycle. Stop rather than apply a page
          // fetched under one scope against a cursor stored for another.
          break;
        }
        if (knownFingerprint == null) {
          knownFingerprint = batch.scopeFingerprint;
          final storedCursor = await _cursors.cursorFor(
            actorUserId: actorUserId,
            scopeFingerprint: knownFingerprint,
          );
          if (storedCursor != cursor) {
            // The first request used another scope's position. Discard this
            // page and re-ask from the right one; nothing has been applied.
            continue;
          }
        }

        final outcome = await _applyBatch(
          actorUserId: actorUserId,
          scopeFingerprint: knownFingerprint,
          batch: batch,
        );
        batches += 1;
        applied += outcome.applied;
        tombstones += outcome.tombstones;
        conflicts += outcome.conflicts;
        reconciled.addAll(outcome.reconciledEntities);
        cursor = batch.nextCursor;

        for (final recovery in outcome.finalRecoveries) {
          if (_cancelled) break;
          await _recovery.recover(
            entityType: recovery.entityType,
            entityId: recovery.entityId,
          );
        }

        if (!batch.hasMore) {
          _attempt = 0;
          await _log(
            actorUserId: actorUserId,
            scopeFingerprint: knownFingerprint,
            fromCursor: startCursor,
            toCursor: cursor,
            changes: applied,
            tombstones: tombstones,
            conflicts: conflicts,
            outcome: scopeReset
                ? 'scope_reset'
                : (applied == 0 && tombstones == 0 ? 'empty' : 'applied'),
            startedAt: startedAt,
          );
          return PullCycleResult(
            batches: batches,
            applied: applied,
            tombstones: tombstones,
            conflicts: conflicts,
            cursor: cursor,
            reachedEnd: true,
            scopeReset: scopeReset,
            reconciledEntities: reconciled,
          );
        }
      }

      await _log(
        actorUserId: actorUserId,
        scopeFingerprint: knownFingerprint,
        fromCursor: startCursor,
        toCursor: cursor,
        changes: applied,
        tombstones: tombstones,
        conflicts: conflicts,
        outcome: _cancelled ? 'cancelled' : 'applied',
        startedAt: startedAt,
      );
      return PullCycleResult(
        batches: batches,
        applied: applied,
        tombstones: tombstones,
        conflicts: conflicts,
        cursor: cursor,
        reachedEnd: false,
        scopeReset: scopeReset,
        reconciledEntities: reconciled,
      );
    } on PullSyncFailure catch (failure) {
      _attempt += 1;
      final retryAfter = failure is PullSyncRetryableFailure
          ? _retryPolicy.delayForAttempt(_attempt)
          : null;
      await _log(
        actorUserId: actorUserId,
        scopeFingerprint: knownFingerprint,
        fromCursor: startCursor,
        toCursor: cursor,
        changes: applied,
        tombstones: tombstones,
        conflicts: conflicts,
        outcome: 'failed',
        startedAt: startedAt,
        code: failure.code,
        message: failure.safeMessage,
      );
      return PullCycleResult(
        batches: batches,
        applied: applied,
        tombstones: tombstones,
        conflicts: conflicts,
        cursor: cursor,
        reachedEnd: false,
        failureCode: failure.code,
        retryAfter: retryAfter,
        reconciledEntities: reconciled,
      );
    } finally {
      _running = false;
    }
  }

  /// Applies a page and advances the cursor in one transaction.
  ///
  /// If anything inside throws — a constraint, a corrupt payload, a crash
  /// between two changes — Drift rolls the whole thing back, the cursor stays
  /// where it was, and the next attempt fetches and applies exactly the same
  /// page to exactly the same effect.
  Future<RemoteBatchOutcome> _applyBatch({
    required String actorUserId,
    required String scopeFingerprint,
    required RemoteChangeBatch batch,
  }) => _db.transaction(() async {
    final outcome = await _applier.applyAll(batch.changes);
    await _cursors.advance(
      actorUserId: actorUserId,
      scopeFingerprint: scopeFingerprint,
      cursor: batch.nextCursor,
      appliedChanges: outcome.applied,
      nowUtc: _clock().toUtc(),
      serverTimeUtc: batch.serverTimeUtc,
    );
    return outcome;
  });

  /// The most recently used position for this actor, across scopes.
  ///
  /// Used only for the first request of a cycle, before the server has named the
  /// scope. If it turns out to belong to a different scope the page is discarded
  /// unapplied and re-fetched, so a wrong guess costs one round trip and never
  /// costs correctness.
  Future<int> _resumeCursor(String actorUserId) async {
    final row =
        await (_db.select(_db.syncPullCursors)
              ..where((row) => row.actorUserId.equals(actorUserId))
              ..orderBy([(row) => OrderingTerm.desc(row.lastPulledAtUtc)])
              ..limit(1))
            .getSingleOrNull();
    return row?.cursorValue ?? 0;
  }

  Future<void> _resetEveryScope(String actorUserId) =>
      _cursors.resetActor(actorUserId);

  Future<void> _log({
    required String actorUserId,
    required String? scopeFingerprint,
    required int fromCursor,
    required int toCursor,
    required int changes,
    required int tombstones,
    required int conflicts,
    required String outcome,
    required DateTime startedAt,
    String? code,
    String? message,
  }) => _db
      .into(_db.syncPullLogs)
      .insert(
        SyncPullLogsCompanion.insert(
          actorUserId: actorUserId,
          scopeFingerprint: Value(scopeFingerprint),
          fromCursor: fromCursor,
          toCursor: toCursor,
          changeCount: Value(changes),
          tombstoneCount: Value(tombstones),
          conflictCount: Value(conflicts),
          outcome: outcome,
          safeErrorCode: Value(code),
          safeErrorMessage: Value(message),
          startedAt: startedAt,
          finishedAt: _clock().toUtc(),
        ),
      );
}
