import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Where this device has got to in the server change journal, per scope.
///
/// Every read and write is keyed by `(actor, scopeFingerprint)`. That is not
/// defensive duplication: a cursor is a position in a feed the server already
/// filtered by role and branch, so the same number means different things to
/// different scopes, and sharing one across accounts would let a second user's
/// first pull skip everything the first user had already consumed.
final class SyncCursorRepository {
  const SyncCursorRepository(this._db);
  final AppDatabase _db;

  /// The stored position, or 0 when this scope has never pulled.
  ///
  /// A scope that has never been seen legitimately starts at zero and resyncs in
  /// full. That is the only safe default: any invented non-zero value would make
  /// the first pull skip every change below it, permanently, because a journal
  /// is only ever read forward.
  Future<int> cursorFor({
    required String actorUserId,
    required String scopeFingerprint,
  }) async =>
      (await _rowFor(
        actorUserId: actorUserId,
        scopeFingerprint: scopeFingerprint,
      ))?.cursorValue ??
      0;

  Future<SyncPullCursorRow?> _rowFor({
    required String actorUserId,
    required String scopeFingerprint,
  }) =>
      (_db.select(_db.syncPullCursors)..where(
            (row) =>
                row.actorUserId.equals(actorUserId) &
                row.scopeFingerprint.equals(scopeFingerprint),
          ))
          .getSingleOrNull();

  Future<SyncPullCursorRow?> readFor({
    required String actorUserId,
    required String scopeFingerprint,
  }) => _rowFor(actorUserId: actorUserId, scopeFingerprint: scopeFingerprint);

  /// Moves the cursor forward.
  ///
  /// Must be called inside the same transaction that applied the batch. The
  /// cursor and the rows it accounts for commit together or not at all — that
  /// single fact is what makes a crash mid-batch replay identically instead of
  /// leaving a gap nobody will ever read again.
  ///
  /// The value never moves backwards. A late or duplicated response carrying an
  /// older position is a no-op rather than a rewind.
  Future<void> advance({
    required String actorUserId,
    required String scopeFingerprint,
    required int cursor,
    required int appliedChanges,
    required DateTime nowUtc,
    DateTime? serverTimeUtc,
  }) async {
    final existing = await _rowFor(
      actorUserId: actorUserId,
      scopeFingerprint: scopeFingerprint,
    );
    if (existing == null) {
      await _db
          .into(_db.syncPullCursors)
          .insert(
            SyncPullCursorsCompanion.insert(
              actorUserId: actorUserId,
              scopeFingerprint: scopeFingerprint,
              cursorValue: Value(cursor),
              lastPulledAtUtc: Value(nowUtc),
              lastServerTimeUtc: Value(serverTimeUtc),
              lastSuccessAtUtc: Value(nowUtc),
              appliedChangeCount: Value(appliedChanges),
            ),
          );
      return;
    }
    await (_db.update(
      _db.syncPullCursors,
    )..where((row) => row.id.equals(existing.id))).write(
      SyncPullCursorsCompanion(
        cursorValue: Value(
          cursor > existing.cursorValue ? cursor : existing.cursorValue,
        ),
        lastPulledAtUtc: Value(nowUtc),
        lastServerTimeUtc: Value(serverTimeUtc),
        lastSuccessAtUtc: Value(nowUtc),
        appliedChangeCount: Value(existing.appliedChangeCount + appliedChanges),
      ),
    );
  }

  /// Drops this scope's position so the next pull starts from zero.
  ///
  /// Called when the server reports a fingerprint this device has not stored, or
  /// refuses a cursor outright. Only the cursor is discarded: applied entities,
  /// baselines and tombstones stay, because re-applying a change is idempotent
  /// and throwing them away would turn a cheap resync into a data loss window.
  Future<void> reset({
    required String actorUserId,
    required String scopeFingerprint,
  }) =>
      (_db.delete(_db.syncPullCursors)..where(
            (row) =>
                row.actorUserId.equals(actorUserId) &
                row.scopeFingerprint.equals(scopeFingerprint),
          ))
          .go();

  /// Forgets every scope belonging to an actor. Used on logout so a later
  /// session cannot inherit a position it never earned.
  Future<void> resetActor(String actorUserId) => (_db.delete(
    _db.syncPullCursors,
  )..where((row) => row.actorUserId.equals(actorUserId))).go();

  Stream<SyncPullCursorRow?> watchLatestFor(String actorUserId) =>
      (_db.select(_db.syncPullCursors)
            ..where((row) => row.actorUserId.equals(actorUserId))
            ..orderBy([(row) => OrderingTerm.desc(row.lastSuccessAtUtc)])
            ..limit(1))
          .watchSingleOrNull();
}
