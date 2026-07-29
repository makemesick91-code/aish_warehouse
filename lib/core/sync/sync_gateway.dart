/// Contract for the (not yet implemented) sync backend.
///
/// It exists at this milestone purely so repositories are written against an
/// abstraction instead of being locked to Supabase or a specific REST API.
/// Rows created offline carry `sync_status = pending`; a future implementation
/// pushes those and pulls server changes back (G-Y1).
abstract interface class SyncGateway {
  Future<void> pushPendingChanges();

  Future<void> pullServerChanges();
}

/// Placeholder used until the sync backend lands. It succeeds without doing
/// anything, which is the correct offline-first behaviour: the app is fully
/// usable and local changes simply stay `pending`.
class NoopSyncGateway implements SyncGateway {
  const NoopSyncGateway();

  @override
  Future<void> pushPendingChanges() async {}

  @override
  Future<void> pullServerChanges() async {}
}
