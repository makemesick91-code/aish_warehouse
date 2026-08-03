// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/realtime_invalidation_coordinator.dart';

/// Subscribes to the server change journal purely to learn that a pull is due.
///
/// Nothing in the event payload is read. That is not laziness — it is the rule
/// the whole 12C design depends on. A Realtime frame is unauthenticated as far
/// as business meaning goes: it can arrive twice, arrive out of order, arrive
/// late, or never arrive. Treating one as a fact would put all of those failure
/// modes directly into the ledger. Treating it as a doorbell puts none of them
/// anywhere, because the deterministic pull re-derives the truth from the cursor
/// either way.
///
/// The subscription is scoped by RLS on `sync_change_journal`, so a device is
/// only woken by changes it would be allowed to read. It carries the session's
/// own token and never a service key.
final class SupabaseRealtimeSyncSignal {
  SupabaseRealtimeSyncSignal({
    required SupabaseClient client,
    required RealtimeInvalidationCoordinator coordinator,
  }) : _client = client,
       _coordinator = coordinator;

  final SupabaseClient _client;
  final RealtimeInvalidationCoordinator _coordinator;

  RealtimeChannel? _channel;
  bool _disposed = false;

  bool get isSubscribed => _channel != null;

  /// Starts listening for this session. Safe to call again; a second call
  /// replaces the channel rather than stacking a second listener.
  Future<void> start() async {
    if (_disposed) return;
    await stop();
    final channel = _client
        .channel('sync-change-journal')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sync_change_journal',
          callback: (_) =>
              _coordinator.invalidate(SyncInvalidationSource.realtime),
        )
        .onSystemEvents((payload) {
          // A reconnect means an unknown number of events were missed while the
          // socket was down. The cursor makes catching up a non-event: pull once
          // and the gap closes itself.
          if (payload is String && payload.toLowerCase().contains('ok')) {
            _coordinator.invalidate(SyncInvalidationSource.reconnect);
          }
        });
    _channel = channel;
    channel.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _coordinator.invalidate(SyncInvalidationSource.reconnect);
      }
    });
  }

  /// Stops listening. Called on sign-out and on dispose, so a channel opened
  /// under one identity never survives into another.
  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    await _client.removeChannel(channel);
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }
}
