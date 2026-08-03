// ignore_for_file: prefer_initializing_formals

import 'dart:async';

/// Where a "remote state may have moved" hint came from.
///
/// Kept only so the Sync Center can say why it is syncing. No path is trusted
/// more than another: each one does the same thing, which is to schedule a pull.
enum SyncInvalidationSource {
  realtime,
  appResume,
  reconnect,
  signIn,
  manual,
  periodic,
  push,
}

/// Turns "something may have changed" into "run a pull", once.
///
/// The whole point of this class is that Realtime is never the source of truth.
/// An event carries no business meaning here — it is not applied, not written,
/// not even read beyond the fact that it arrived. It marks the remote state
/// dirty, and a deterministic pull from the durable cursor decides what actually
/// happened.
///
/// That indirection is what makes every awkward case fall out for free. A late
/// event pulls slightly later. A lost event changes nothing, because the resume,
/// reconnect and periodic paths mark the same flag. A duplicate event coalesces
/// into the burst already pending. An out-of-order event is meaningless, because
/// order comes from `change_seq` rather than from delivery. And with the
/// subscription down entirely, manual sync and app resume still reach the same
/// state — slower, not wronger.
final class RealtimeInvalidationCoordinator {
  RealtimeInvalidationCoordinator({
    required Future<void> Function(SyncInvalidationSource source) onPullDue,
    Duration debounce = const Duration(milliseconds: 750),
    Timer Function(Duration, void Function())? scheduler,
  }) : _onPullDue = onPullDue,
       _debounce = debounce,
       _scheduler = scheduler ?? Timer.new;

  final Future<void> Function(SyncInvalidationSource source) _onPullDue;
  final Duration _debounce;
  final Timer Function(Duration, void Function()) _scheduler;

  Timer? _pending;
  bool _disposed = false;
  bool _running = false;

  /// Set while a pull is running and another hint arrives. Exactly one further
  /// pull follows — not one per event.
  bool _dirtyDuringRun = false;
  SyncInvalidationSource? _queuedSource;

  int _pullCount = 0;

  /// How many pulls this coordinator has actually started. A burst of events
  /// must not move this by more than one.
  int get pullCount => _pullCount;

  bool get hasPendingPull => _pending != null || _dirtyDuringRun;

  /// Marks remote state as possibly changed.
  ///
  /// Immediate sources — a manual tap, a fresh sign-in — skip the debounce,
  /// because a person is waiting and there is no burst to absorb.
  void invalidate(SyncInvalidationSource source) {
    if (_disposed) return;
    if (_running) {
      _dirtyDuringRun = true;
      _queuedSource ??= source;
      return;
    }
    final immediate =
        source == SyncInvalidationSource.manual ||
        source == SyncInvalidationSource.signIn;
    if (immediate) {
      _pending?.cancel();
      _pending = null;
      unawaited(_drain(source));
      return;
    }
    _queuedSource ??= source;
    // Restarting the timer is what collapses a burst: a hundred events inside
    // the window schedule one pull, not a hundred.
    _pending?.cancel();
    _pending = _scheduler(_debounce, () {
      _pending = null;
      final queued = _queuedSource ?? source;
      _queuedSource = null;
      unawaited(_drain(queued));
    });
  }

  Future<void> _drain(SyncInvalidationSource source) async {
    if (_disposed || _running) {
      _dirtyDuringRun = true;
      return;
    }
    _running = true;
    try {
      _pullCount += 1;
      await _onPullDue(source);
    } finally {
      _running = false;
    }
    if (_dirtyDuringRun && !_disposed) {
      _dirtyDuringRun = false;
      final queued = _queuedSource ?? SyncInvalidationSource.realtime;
      _queuedSource = null;
      await _drain(queued);
    }
  }

  /// Runs any pull the debounce is still holding. Used by manual sync so a user
  /// never waits out a timer they cannot see.
  Future<void> flush(SyncInvalidationSource source) async {
    _pending?.cancel();
    _pending = null;
    _queuedSource = null;
    await _drain(source);
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _pending = null;
    _dirtyDuringRun = false;
    _queuedSource = null;
  }
}
