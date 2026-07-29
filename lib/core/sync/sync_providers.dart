import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_gateway.dart';

/// Swapped for a real implementation once the sync backend exists.
final syncGatewayProvider = Provider<SyncGateway>(
  (ref) => const NoopSyncGateway(),
);
