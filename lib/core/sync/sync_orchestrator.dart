// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../db/app_database.dart';
import 'push_sync_worker.dart';
import 'pull_sync_worker.dart';
import 'realtime_invalidation_coordinator.dart';

/// Runs one sync cycle: push what is owed, pull what changed, then push again
/// only if reconciliation actually produced new work.
///
/// The ordering matters. Pushing first means the server has already seen this
/// device's operations before the pull decides what the truth is, so a document
/// this device just submitted comes back with its server number rather than
/// arriving as a conflict. Pulling second means reconciliation runs against the
/// freshest state. The second push exists because a field-level merge can leave
/// a column still owed to the server (G-Y3), and without it that column would
/// sit locally until some unrelated event happened to trigger another cycle.
///
/// That second push is capped at one round. A merge that re-enqueues work whose
/// push triggers another merge is exactly the shape of an infinite loop, and one
/// bounded round is enough to settle the case the merge actually creates.
final class SyncOrchestrator {
  SyncOrchestrator({
    required AppDatabase database,
    required PushSyncCoordinator push,
    required PullSyncWorker pull,
    required Future<String?> Function() deviceIdProvider,
    this.maxFollowUpPushRounds = 1,
  }) : _db = database,
       _push = push,
       _pull = pull,
       _deviceId = deviceIdProvider;

  final AppDatabase _db;
  final PushSyncCoordinator _push;
  final PullSyncWorker _pull;
  final Future<String?> Function() _deviceId;
  final int maxFollowUpPushRounds;

  Future<void>? _inFlight;
  bool _disposed = false;
  String? _activeActorUserId;

  SyncCycleReport? _lastReport;
  SyncCycleReport? get lastReport => _lastReport;

  /// Single-flight. A second trigger while a cycle runs joins the one in
  /// progress rather than starting a competing drain of the same queues.
  Future<void> run({
    required String actorUserId,
    SyncInvalidationSource source = SyncInvalidationSource.manual,
  }) {
    if (_disposed) return Future<void>.value();
    return _inFlight ??= _run(actorUserId, source).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _run(String actorUserId, SyncInvalidationSource source) async {
    _activeActorUserId = actorUserId;
    // A device row is created by the first outbox write. Until one exists this
    // installation has never had anything to say to the server, and a pull would
    // have nothing to authenticate with.
    final deviceId = await _deviceId();
    if (deviceId == null || deviceId.isEmpty) return;

    await _push.trigger(actorUserId: actorUserId);
    if (_disposed || _activeActorUserId != actorUserId) return;

    var result = await _pull.run(actorUserId: actorUserId, deviceId: deviceId);
    if (_disposed || _activeActorUserId != actorUserId) return;

    var rounds = 0;
    while (rounds < maxFollowUpPushRounds &&
        result.succeeded &&
        result.reconciledEntities.isNotEmpty) {
      rounds += 1;
      await _push.trigger(actorUserId: actorUserId);
      if (_disposed || _activeActorUserId != actorUserId) return;
      result = await _pull.run(actorUserId: actorUserId, deviceId: deviceId);
      if (_disposed || _activeActorUserId != actorUserId) return;
    }

    _lastReport = SyncCycleReport(
      source: source,
      applied: result.applied,
      tombstones: result.tombstones,
      conflicts: result.conflicts,
      cursor: result.cursor,
      reachedEnd: result.reachedEnd,
      scopeReset: result.scopeReset,
      failureCode: result.failureCode,
      followUpPushRounds: rounds,
    );
  }

  /// Ends the session's sync activity.
  ///
  /// Cancelling the workers rather than awaiting them is deliberate: an
  /// in-flight push must not acknowledge under a session that no longer exists,
  /// and an in-flight pull must not advance a cursor for an actor who has just
  /// logged out. Both workers already check their cancellation flag before they
  /// write anything, so the worst case is a repeated batch — which is exactly
  /// the case the whole apply path is built to survive.
  void cancelForActorChange() {
    _activeActorUserId = null;
    _pull.cancel();
  }

  /// Forgets an actor's pull positions entirely. Used on sign-out so a later
  /// session cannot inherit progress it never made.
  Future<void> forgetActor(String actorUserId) => (_db.delete(
    _db.syncPullCursors,
  )..where((row) => row.actorUserId.equals(actorUserId))).go();

  void dispose() {
    _disposed = true;
    _activeActorUserId = null;
    _pull.cancel();
    _push.dispose();
    _inFlight = null;
  }
}

final class SyncCycleReport {
  const SyncCycleReport({
    required this.source,
    required this.applied,
    required this.tombstones,
    required this.conflicts,
    required this.cursor,
    required this.reachedEnd,
    required this.scopeReset,
    required this.failureCode,
    required this.followUpPushRounds,
  });

  final SyncInvalidationSource source;
  final int applied;
  final int tombstones;
  final int conflicts;
  final int cursor;
  final bool reachedEnd;
  final bool scopeReset;
  final String? failureCode;
  final int followUpPushRounds;

  bool get succeeded => failureCode == null;
}
