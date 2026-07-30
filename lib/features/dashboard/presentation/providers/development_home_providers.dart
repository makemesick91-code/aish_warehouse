import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/db/seed/development_seed.dart';
import '../../../delivery/presentation/providers/delivery_providers.dart';
import '../../../inventory/domain/models/inventory_models.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../../opname/presentation/providers/opname_providers.dart';
import '../../../purchase_request/presentation/providers/purchase_request_providers.dart';

final developmentSeedProvider = Provider<DevelopmentSeed>(
  (ref) => DevelopmentSeed(
    master: ref.watch(masterDataRepositoryProvider),
    inventory: ref.watch(inventoryRepositoryProvider),
    posting: ref.watch(stockPostingServiceProvider),
    opnames: ref.watch(opnameRepositoryProvider),
    requests: ref.watch(purchaseRequestRepositoryProvider),
    deliveries: ref.watch(deliveryOrderRepositoryProvider),
  ),
);

/// Reports whether the local database can be opened at all, so the home page
/// can show a clear database status instead of a blank screen.
final databaseStatusProvider = FutureProvider<String>((ref) async {
  final database = ref.watch(appDatabaseProvider);
  final row = await database
      .customSelect('SELECT sqlite_version() AS version;')
      .getSingle();
  return row.read<String>('version');
});

/// Live balances of the central warehouse.
final warehouseBalancesProvider = StreamProvider<List<StockBalanceView>>((
  ref,
) async* {
  final warehouse = await ref.watch(warehouseLocationProvider.future);
  if (warehouse == null) {
    yield const <StockBalanceView>[];
    return;
  }
  yield* ref
      .watch(inventoryRepositoryProvider)
      .watchBalancesAtLocation(warehouse.id);
});

/// Runs the development seed and refreshes everything that depends on it.
class SeedController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> runSeed() async {
    state = const AsyncValue<void>.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(developmentSeedProvider).run();
      ref.invalidate(masterSummaryProvider);
      ref.invalidate(warehouseLocationProvider);
    });
  }
}

final seedControllerProvider = AsyncNotifierProvider<SeedController, void>(
  SeedController.new,
);
