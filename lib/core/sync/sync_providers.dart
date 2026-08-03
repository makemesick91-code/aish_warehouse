import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_providers.dart';
import '../supabase/supabase_client_provider.dart';
import '../supabase/supabase_pull_sync_gateway.dart';
import '../supabase/supabase_push_sync_gateway.dart';
import '../supabase/supabase_realtime_sync_signal.dart';
import '../supabase/supabase_trusted_file_upload_gateway.dart';
import 'drift_sync_operation_planner.dart';
import 'final_conflict_recovery_service.dart';
import 'pull_sync_contracts.dart';
import 'pull_sync_worker.dart';
import 'push_sync_worker.dart';
import 'realtime_invalidation_coordinator.dart';
import 'rebuild_pending_outbox_use_case.dart';
import 'sync_acknowledgement_applier.dart';
import 'sync_contracts.dart';
import 'sync_cursor_repository.dart';
import 'sync_file_upload_queue.dart';
import 'sync_gateway.dart';
import 'sync_orchestrator.dart';
import 'sync_outbox_writer.dart';
import 'trusted_file_upload_worker.dart';

/// Swapped for a real implementation once the sync backend exists.
final syncGatewayProvider = Provider<SyncGateway>(
  (ref) => const NoopSyncGateway(),
);

final syncOutboxWriterProvider = Provider<SyncOutboxWriter>(
  (ref) => DriftSyncOutboxWriter(ref.watch(appDatabaseProvider)),
);

final syncFileUploadQueueProvider = Provider<SyncFileUploadQueue>(
  (ref) => DriftSyncFileUploadQueue(ref.watch(appDatabaseProvider)),
);

final rebuildPendingOutboxProvider = Provider<RebuildPendingOutboxUseCase>(
  (ref) => RebuildPendingOutboxUseCase(
    ref.watch(appDatabaseProvider),
    ref.watch(syncOutboxWriterProvider),
    ref.watch(syncFileUploadQueueProvider),
  ),
);

final pushSyncGatewayProvider = Provider<PushSyncGateway?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabasePushSyncGateway(client);
});

final pullSyncGatewayProvider = Provider<PullSyncGateway?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabasePullSyncGateway(client);
});

final syncCursorRepositoryProvider = Provider<SyncCursorRepository>(
  (ref) => SyncCursorRepository(ref.watch(appDatabaseProvider)),
);

final finalConflictRecoveryProvider = Provider<FinalConflictRecoveryService>(
  (ref) => FinalConflictRecoveryService(ref.watch(appDatabaseProvider)),
);

final pullSyncWorkerProvider = Provider<PullSyncWorker?>((ref) {
  final gateway = ref.watch(pullSyncGatewayProvider);
  if (gateway == null) return null;
  final database = ref.watch(appDatabaseProvider);
  final worker = PullSyncWorker(
    database: database,
    gateway: gateway,
    cursors: ref.watch(syncCursorRepositoryProvider),
    recovery: ref.watch(finalConflictRecoveryProvider),
  );
  ref.onDispose(worker.cancel);
  return worker;
});

final pushSyncCoordinatorProvider = Provider<PushSyncCoordinator?>((ref) {
  final gateway = ref.watch(pushSyncGatewayProvider);
  if (gateway == null) return null;
  final database = ref.watch(appDatabaseProvider);
  final uploadWorker = TrustedFileUploadWorker(
    database: database,
    gateway: SupabaseTrustedFileUploadGateway(
      ref.watch(supabaseClientProvider)!,
    ),
  );
  final coordinator = PushSyncCoordinator(
    PushSyncWorker(
      database: database,
      gateway: gateway,
      planner: DriftSyncOperationPlanner(database),
      acknowledgement: DriftSyncAcknowledgementApplier(database),
      deviceGateway: SupabaseSyncDeviceGateway(
        ref.watch(supabaseClientProvider)!,
      ),
    ),
    beforePush: (actorUserId) => uploadWorker.run(actorUserId: actorUserId),
    onDispose: uploadWorker.cancel,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Push and pull as one cycle. Null until a production Supabase client exists,
/// which is what keeps every widget test free of a network dependency.
final syncOrchestratorProvider = Provider<SyncOrchestrator?>((ref) {
  final push = ref.watch(pushSyncCoordinatorProvider);
  final pull = ref.watch(pullSyncWorkerProvider);
  if (push == null || pull == null) return null;
  final database = ref.watch(appDatabaseProvider);
  final orchestrator = SyncOrchestrator(
    database: database,
    push: push,
    pull: pull,
    deviceIdProvider: () async => (await database.syncDao.device())?.id,
  );
  ref.onDispose(orchestrator.dispose);
  return orchestrator;
});

/// Debounces every "remote may have changed" hint into a bounded number of
/// pulls. Created even without a Supabase client so callers do not have to
/// branch; with no orchestrator it simply does nothing.
final syncInvalidationCoordinatorProvider =
    Provider<RealtimeInvalidationCoordinator>((ref) {
      final coordinator = RealtimeInvalidationCoordinator(
        onPullDue: (_) async {
          final orchestrator = ref.read(syncOrchestratorProvider);
          final actorUserId = ref.read(syncActorUserIdProvider);
          if (orchestrator == null || actorUserId == null) return;
          await orchestrator.run(actorUserId: actorUserId);
        },
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

/// The actor a sync cycle belongs to.
///
/// Overridden by the auth layer. It is a separate provider so `core/sync` never
/// imports a feature package, and so a test can drive a cycle without standing
/// up authentication.
final syncActorUserIdProvider = Provider<String?>((ref) => null);

final realtimeSyncSignalProvider = Provider<SupabaseRealtimeSyncSignal?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  final signal = SupabaseRealtimeSyncSignal(
    client: client,
    coordinator: ref.watch(syncInvalidationCoordinatorProvider),
  );
  ref.onDispose(signal.dispose);
  return signal;
});
