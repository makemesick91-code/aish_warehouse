import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
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
