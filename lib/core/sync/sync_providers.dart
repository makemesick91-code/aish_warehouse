import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_providers.dart';
import '../supabase/supabase_client_provider.dart';
import '../supabase/supabase_push_sync_gateway.dart';
import '../supabase/supabase_trusted_file_upload_gateway.dart';
import 'drift_sync_operation_planner.dart';
import 'push_sync_worker.dart';
import 'rebuild_pending_outbox_use_case.dart';
import 'sync_acknowledgement_applier.dart';
import 'sync_contracts.dart';
import 'sync_file_upload_queue.dart';
import 'sync_gateway.dart';
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
