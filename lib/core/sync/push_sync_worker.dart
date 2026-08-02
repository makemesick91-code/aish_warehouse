// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/daos/sync_dao.dart';
import 'sync_contracts.dart';
import 'sync_dependency_planner.dart';
import 'sync_outbox_writer.dart';
import 'sync_payload_hasher.dart';

abstract interface class SyncAcknowledgementApplier {
  Future<void> accept({
    required SyncOutboxRow outbox,
    required String pushedPayloadHash,
    required SyncAcceptedResult result,
  });

  Future<void> conflict({
    required SyncOutboxRow outbox,
    required SyncConflictResult result,
  });
}

final class PushRetryPolicy {
  PushRetryPolicy({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  Duration delayForAttempt(int attempt) {
    final exponent = max(0, min(attempt - 1, 8));
    final baseMs = min(300000, 1000 * (1 << exponent));
    final jitterMs = _random.nextInt(max(1, baseMs ~/ 4));
    return Duration(milliseconds: min(300000, baseMs + jitterMs));
  }
}

final class SyncLeasePolicy {
  const SyncLeasePolicy({this.duration = const Duration(minutes: 2)});
  final Duration duration;
}

final class PushSyncWorker {
  PushSyncWorker({
    required AppDatabase database,
    required PushSyncGateway gateway,
    required SyncOperationPlanner planner,
    required SyncAcknowledgementApplier acknowledgement,
    SyncDeviceGateway? deviceGateway,
    PushRetryPolicy? retryPolicy,
    this.dependencyPlanner = const SyncDependencyPlanner(),
    this.leasePolicy = const SyncLeasePolicy(),
    DateTime Function()? clock,
    this.batchSize = 20,
  }) : _dao = database.syncDao,
       _gateway = gateway,
       _planner = planner,
       _acknowledgement = acknowledgement,
       _deviceGateway = deviceGateway,
       _retryPolicy = retryPolicy ?? PushRetryPolicy(),
       _clock = clock ?? DateTime.now;

  final SyncDao _dao;
  final PushSyncGateway _gateway;
  final SyncOperationPlanner _planner;
  final SyncAcknowledgementApplier _acknowledgement;
  final SyncDeviceGateway? _deviceGateway;
  final PushRetryPolicy _retryPolicy;
  final SyncDependencyPlanner dependencyPlanner;
  final SyncLeasePolicy leasePolicy;
  final DateTime Function() _clock;
  final int batchSize;
  bool _running = false;
  bool _cancelled = false;

  bool get isRunning => _running;

  void cancel() => _cancelled = true;

  Future<void> run({required String actorUserId}) async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    try {
      final now = _clock().toUtc();
      final device = await _dao.device();
      if (device != null && _deviceGateway != null) {
        await _deviceGateway.register(
          deviceId: device.id,
          appInstallId: device.appInstallId,
        );
        if (_cancelled) return;
      }
      await _dao.recoverExpiredLeases(
        expiredBeforeEpochMs: now
            .subtract(leasePolicy.duration)
            .millisecondsSinceEpoch,
        nowUtc: now,
      );
      while (!_cancelled) {
        final rows = dependencyPlanner.order(
          await _dao.dueForActor(
            actorUserId: actorUserId,
            nowEpochMs: _clock().toUtc().millisecondsSinceEpoch,
            limit: batchSize,
          ),
        );
        if (rows.isEmpty) break;
        for (final candidate in rows) {
          if (_cancelled) break;
          final leaseAt = _clock().toUtc();
          if (await _dao.hasUnfinalizedFileForAggregate(
            aggregateType: candidate.aggregateType,
            aggregateId: candidate.aggregateId,
            actorUserId: candidate.actorUserId!,
          )) {
            await _dao.blockForDependency(
              requestId: candidate.requestId,
              message: 'Menunggu file audit selesai diunggah.',
              nowUtc: leaseAt,
            );
            continue;
          }
          if (!await _dao.acquireLease(
            requestId: candidate.requestId,
            nowEpochMs: leaseAt.millisecondsSinceEpoch,
          )) {
            continue;
          }
          await _pushOne(candidate);
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _pushOne(SyncOutboxRow row) async {
    try {
      final envelope = await _planner.build(row);
      final pushedHash = const Sha256SyncPayloadHasher().hash(
        envelope.toJson(),
      );
      if (pushedHash != row.payloadHash) {
        await _acknowledgement.conflict(
          outbox: row,
          result: SyncConflictResult(
            requestId: SyncRequestId(row.requestId),
            code: 'sync_payload_hash_mismatch',
            safeMessage: 'Data lokal berubah sebelum dapat dikirim.',
            baseVersion: envelope.baseServerVersion,
          ),
        );
        return;
      }
      final result = await _gateway.push(envelope);
      // A logout/account switch may happen while the authenticated request is
      // in flight. The server result remains replay-safe, but applying it after
      // the session was disposed could acknowledge data under stale UI/session
      // state. Leave the lease for normal crash recovery and replay instead.
      if (_cancelled) return;
      switch (result) {
        case SyncAcceptedResult():
          await _acknowledgement.accept(
            outbox: row,
            pushedPayloadHash: pushedHash,
            result: result,
          );
        case SyncConflictResult():
          await _acknowledgement.conflict(outbox: row, result: result);
      }
    } on SyncRetryableFailure catch (failure) {
      final now = _clock().toUtc();
      final delay = _retryPolicy.delayForAttempt(row.attemptCount + 1);
      await _dao.appendAttempt(
        SyncAttemptLogsCompanion.insert(
          requestId: row.requestId,
          attemptNumber: row.attemptCount + 1,
          startedAt: row.updatedAt,
          finishedAt: now,
          outcome: 'retryable',
          httpStatus: Value(failure.httpStatus),
          safeErrorCode: Value(failure.code),
          safeErrorMessage: Value(failure.safeMessage),
        ),
      );
      await _dao.requeue(
        requestId: row.requestId,
        nextAttemptEpochMs: now.add(delay).millisecondsSinceEpoch,
        code: failure.code,
        message: failure.safeMessage,
        nowUtc: now,
      );
    } on SyncPermanentFailure catch (failure) {
      await _acknowledgement.conflict(
        outbox: row,
        result: SyncConflictResult(
          requestId: SyncRequestId(row.requestId),
          code: failure.code,
          safeMessage: failure.safeMessage,
          baseVersion: 0,
        ),
      );
    }
  }
}

final class PushSyncCoordinator {
  PushSyncCoordinator(this._worker, {this.beforePush, this.onDispose});
  final PushSyncWorker _worker;
  final Future<void> Function(String actorUserId)? beforePush;
  final void Function()? onDispose;
  Future<void>? _inFlight;

  Future<void> trigger({required String actorUserId}) =>
      _inFlight ??= _run(actorUserId).whenComplete(() => _inFlight = null);

  Future<void> _run(String actorUserId) async {
    await beforePush?.call(actorUserId);
    await _worker.run(actorUserId: actorUserId);
  }

  void dispose() {
    _worker.cancel();
    onDispose?.call();
    _inFlight = null;
  }
}
