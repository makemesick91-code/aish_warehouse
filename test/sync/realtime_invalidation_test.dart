import 'dart:async';

import 'package:aish_warehouse/core/sync/realtime_invalidation_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Acceptance 18, 29 and 30: Realtime is a doorbell, never a source of truth.
///
/// Every test here is really the same claim from a different angle — the number
/// of pulls depends on how many times the system became dirty, not on how many
/// frames arrived, in what order, or whether any arrived at all.
void main() {
  late List<SyncInvalidationSource> pulls;
  late List<_FakeTimer> pendingTimers;
  late Completer<void>? gate;

  /// A scheduler that hands the test the timer callback instead of waiting, so
  /// debounce behaviour is asserted rather than slept through.
  ///
  /// Cancellation has to be modelled faithfully: restarting the timer is exactly
  /// how the coordinator collapses a burst, and a fake that ignored `cancel`
  /// would fire every superseded callback and hide the behaviour under test.
  Timer fakeScheduler(Duration duration, void Function() callback) {
    final timer = _FakeTimer(callback, pendingTimers);
    pendingTimers.add(timer);
    return timer;
  }

  void fireDebounce() {
    final due = List.of(pendingTimers);
    pendingTimers.clear();
    for (final timer in due) {
      timer.fire();
    }
  }

  RealtimeInvalidationCoordinator build() => RealtimeInvalidationCoordinator(
    onPullDue: (source) async {
      pulls.add(source);
      if (gate != null) await gate!.future;
    },
    scheduler: fakeScheduler,
  );

  setUp(() {
    pulls = [];
    pendingTimers = [];
    gate = null;
  });

  group('acceptance 18: a burst becomes one pull', () {
    test('many events inside the window schedule a single pull', () async {
      final coordinator = build();

      for (var i = 0; i < 50; i++) {
        coordinator.invalidate(SyncInvalidationSource.realtime);
      }
      expect(pulls, isEmpty, reason: 'nothing runs before the window closes');
      fireDebounce();
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.pullCount, 1);
      expect(pulls, [SyncInvalidationSource.realtime]);
      coordinator.dispose();
    });

    test('events during a running pull cause exactly one more', () async {
      gate = Completer<void>();
      final coordinator = build();

      coordinator.invalidate(SyncInvalidationSource.manual);
      await Future<void>.delayed(Duration.zero);
      expect(pulls, hasLength(1));

      for (var i = 0; i < 20; i++) {
        coordinator.invalidate(SyncInvalidationSource.realtime);
      }
      gate!.complete();
      gate = null;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        coordinator.pullCount,
        2,
        reason: 'twenty events during a pull are one follow-up, not twenty',
      );
      coordinator.dispose();
    });
  });

  group('acceptance 30: duplicate and out-of-order events change nothing', () {
    test('the same event repeated is indistinguishable from one', () async {
      final coordinator = build();

      coordinator.invalidate(SyncInvalidationSource.realtime);
      coordinator.invalidate(SyncInvalidationSource.realtime);
      coordinator.invalidate(SyncInvalidationSource.realtime);
      fireDebounce();
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.pullCount, 1);
      coordinator.dispose();
    });

    test('the source of an event does not change what happens', () async {
      final coordinator = build();

      coordinator.invalidate(SyncInvalidationSource.realtime);
      coordinator.invalidate(SyncInvalidationSource.appResume);
      coordinator.invalidate(SyncInvalidationSource.reconnect);
      fireDebounce();
      await Future<void>.delayed(Duration.zero);

      expect(
        coordinator.pullCount,
        1,
        reason: 'the pull re-derives truth from the cursor either way',
      );
      coordinator.dispose();
    });
  });

  group('acceptance 29: the system is correct without Realtime at all', () {
    test(
      'a manual sync runs immediately without waiting on a window',
      () async {
        final coordinator = build();

        await coordinator.flush(SyncInvalidationSource.manual);

        expect(pulls, [SyncInvalidationSource.manual]);
        expect(
          pendingTimers,
          isEmpty,
          reason: 'a person waiting must not sit out a timer they cannot see',
        );
        coordinator.dispose();
      },
    );

    test('a manual sync absorbs a pending debounced pull', () async {
      final coordinator = build();

      coordinator.invalidate(SyncInvalidationSource.realtime);
      await coordinator.flush(SyncInvalidationSource.manual);
      fireDebounce();
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.pullCount, 1);
      coordinator.dispose();
    });

    test(
      'resume and sign-in reach the same place a Realtime frame would',
      () async {
        final coordinator = build();

        coordinator.invalidate(SyncInvalidationSource.appResume);
        fireDebounce();
        await Future<void>.delayed(Duration.zero);
        await coordinator.flush(SyncInvalidationSource.signIn);

        expect(coordinator.pullCount, 2);
        expect(pulls, [
          SyncInvalidationSource.appResume,
          SyncInvalidationSource.signIn,
        ]);
        coordinator.dispose();
      },
    );

    test('sign-in does not wait for the debounce window', () async {
      final coordinator = build();

      coordinator.invalidate(SyncInvalidationSource.signIn);
      await Future<void>.delayed(Duration.zero);

      expect(pulls, [SyncInvalidationSource.signIn]);
      coordinator.dispose();
    });
  });

  group('the coordinator stops when the session does', () {
    test('a disposed coordinator ignores every later event', () async {
      final coordinator = build();

      coordinator.dispose();
      coordinator.invalidate(SyncInvalidationSource.realtime);
      coordinator.invalidate(SyncInvalidationSource.manual);
      fireDebounce();
      await Future<void>.delayed(Duration.zero);

      expect(pulls, isEmpty);
      expect(coordinator.pullCount, 0);
    });

    test('disposing mid-pull does not schedule the follow-up', () async {
      gate = Completer<void>();
      final coordinator = build();

      coordinator.invalidate(SyncInvalidationSource.manual);
      await Future<void>.delayed(Duration.zero);
      coordinator.invalidate(SyncInvalidationSource.realtime);
      coordinator.dispose();
      gate!.complete();
      gate = null;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.pullCount, 1);
    });

    test('a pending pull is visible before it runs', () async {
      final coordinator = build();

      coordinator.invalidate(SyncInvalidationSource.realtime);

      expect(coordinator.hasPendingPull, isTrue);
      fireDebounce();
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.hasPendingPull, isFalse);
      coordinator.dispose();
    });
  });
}

/// A timer that only fires when the test says so, and genuinely forgets its
/// callback when cancelled.
final class _FakeTimer implements Timer {
  _FakeTimer(this._callback, this._registry);

  final void Function() _callback;
  final List<_FakeTimer> _registry;
  bool _cancelled = false;

  void fire() {
    if (_cancelled) return;
    _callback();
  }

  @override
  void cancel() {
    _cancelled = true;
    _registry.remove(this);
  }

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;
}
