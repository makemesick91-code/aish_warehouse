import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/sync/pull_sync_contracts.dart';
import '../../../../core/sync/sync_cursor_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

final syncPendingCountProvider = StreamProvider<int>(
  (ref) => ref.watch(appDatabaseProvider).syncDao.watchPendingCount(),
);

final syncProcessingCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.syncOutbox)
        ..where((row) => row.status.equals('processing')))
      .watch()
      .map((rows) => rows.length);
});

final syncConflictCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database
      .select(database.syncConflictLogs)
      .watch()
      .map((rows) => rows.length);
});

final syncUploadCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.syncFileUploads)
        ..where((row) => row.status.isNotIn(['finalized'])))
      .watch()
      .map((rows) => rows.length);
});

final syncWaitingForActorCountProvider = StreamProvider<int>((ref) {
  final actorId = ref.watch(currentDomainUserProvider)?.id;
  final database = ref.watch(appDatabaseProvider);
  if (actorId == null) return Stream<int>.value(0);
  return (database.select(database.syncOutbox)..where(
        (row) =>
            row.actorUserId.isNotNull() &
            row.actorUserId.equals(actorId).not() &
            row.status.isIn(['queued', 'processing', 'blocked']),
      ))
      .watch()
      .map((rows) => rows.length);
});

final syncUnknownActorCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.syncOutbox)..where(
        (row) =>
            row.status.equals('blocked') &
            row.lastErrorCode.equals('sync_original_actor_unknown'),
      ))
      .watch()
      .map((rows) => rows.length);
});

final syncGroupedPendingProvider = StreamProvider<List<SyncPendingGroup>>((
  ref,
) {
  final database = ref.watch(appDatabaseProvider);
  return database
      .customSelect(
        'SELECT aggregate_type, status, COUNT(*) AS total '
        "FROM sync_outbox WHERE status IN ('queued','processing','blocked') "
        'GROUP BY aggregate_type, status ORDER BY aggregate_type, status;',
        readsFrom: {database.syncOutbox},
      )
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            SyncPendingGroup(
              aggregateType: row.read<String>('aggregate_type'),
              status: row.read<String>('status'),
              count: row.read<int>('total'),
            ),
        ],
      );
});

final syncLastSuccessProvider = StreamProvider<DateTime?>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.syncAttemptLogs)
        ..where((row) => row.outcome.isIn(['accepted', 'replayed']))
        ..orderBy([(row) => OrderingTerm.desc(row.finishedAt)])
        ..limit(1))
      .watchSingleOrNull()
      .map((row) => row?.finishedAt);
});

final syncLastSafeErrorProvider = StreamProvider<String?>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.syncAttemptLogs)
        ..where((row) => row.safeErrorMessage.isNotNull())
        ..orderBy([(row) => OrderingTerm.desc(row.finishedAt)])
        ..limit(1))
      .watchSingleOrNull()
      .map((row) => row?.safeErrorMessage);
});

final syncUploadGroupsProvider = StreamProvider<List<SyncUploadGroup>>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database
      .customSelect(
        'SELECT status, COUNT(*) AS total FROM sync_file_uploads '
        'GROUP BY status ORDER BY status;',
        readsFrom: {database.syncFileUploads},
      )
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            SyncUploadGroup(
              status: row.read<String>('status'),
              count: row.read<int>('total'),
            ),
        ],
      );
});

/// The last pull this device completed for the active actor, whatever its
/// outcome. Null until one has run.
///
/// Mapped to a presentation model rather than surfacing the Drift row: the UI
/// layer does not import generated classes, and the page only ever needs these
/// four values.
final syncLastPullProvider = StreamProvider<SyncPullSummary?>((ref) {
  final actorId = ref.watch(currentDomainUserProvider)?.id;
  final database = ref.watch(appDatabaseProvider);
  if (actorId == null) return Stream<SyncPullSummary?>.value(null);
  return (database.select(database.syncPullLogs)
        ..where((row) => row.actorUserId.equals(actorId))
        ..orderBy([(row) => OrderingTerm.desc(row.finishedAt)])
        ..limit(1))
      .watchSingleOrNull()
      .map(
        (row) => row == null
            ? null
            : SyncPullSummary(
                outcome: row.outcome,
                changeCount: row.changeCount,
                tombstoneCount: row.tombstoneCount,
                safeErrorMessage: row.safeErrorMessage,
              ),
      );
});

/// When this device last reached the end of the server feed. Distinct from "last
/// attempt": a user needs to know their data is current, not that a request was
/// made.
final syncLastSuccessfulPullProvider = StreamProvider<DateTime?>((ref) {
  final actorId = ref.watch(currentDomainUserProvider)?.id;
  final database = ref.watch(appDatabaseProvider);
  if (actorId == null) return Stream<DateTime?>.value(null);
  return SyncCursorRepository(
    database,
  ).watchLatestFor(actorId).map((row) => row?.lastSuccessAtUtc);
});

final syncAppliedChangeCountProvider = StreamProvider<int>((ref) {
  final actorId = ref.watch(currentDomainUserProvider)?.id;
  final database = ref.watch(appDatabaseProvider);
  if (actorId == null) return Stream<int>.value(0);
  return SyncCursorRepository(
    database,
  ).watchLatestFor(actorId).map((row) => row?.appliedChangeCount ?? 0);
});

final syncTombstoneCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database
      .select(database.syncTombstones)
      .watch()
      .map((rows) => rows.length);
});

/// Conflicts that have been settled automatically, and those that still need a
/// person. Only the second kind is a problem, and the UI must not present them
/// as one number.
final syncResolvedConflictCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.syncConflictLogs)..where(
        (row) =>
            row.resolvedAt.isNotNull() &
            row.resolution
                .equals(SyncConflictResolution.manualReviewRequired)
                .not(),
      ))
      .watch()
      .map((rows) => rows.length);
});

final syncManualReviewCountProvider = StreamProvider<int>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.syncConflictLogs)..where(
        (row) =>
            row.resolvedAt.isNull() |
            row.resolution.equals(SyncConflictResolution.manualReviewRequired),
      ))
      .watch()
      .map((rows) => rows.length);
});

/// What the Sync Center needs to say about the last read from the server.
///
/// Deliberately narrow: an outcome, two counts, and an already-safe message.
/// No cursor, no entity name, no server text — the page is readable over a
/// user's shoulder.
final class SyncPullSummary {
  const SyncPullSummary({
    required this.outcome,
    required this.changeCount,
    required this.tombstoneCount,
    required this.safeErrorMessage,
  });

  final String outcome;
  final int changeCount;
  final int tombstoneCount;
  final String? safeErrorMessage;
}

final class SyncPendingGroup {
  const SyncPendingGroup({
    required this.aggregateType,
    required this.status,
    required this.count,
  });
  final String aggregateType;
  final String status;
  final int count;
}

final class SyncUploadGroup {
  const SyncUploadGroup({required this.status, required this.count});
  final String status;
  final int count;
}
