import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../data/repositories/drift_inventory_repository.dart';
import '../../domain/models/inventory_models.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/services/stock_posting_service.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => DriftInventoryRepository(ref.watch(inventoryDaoProvider)),
);

/// The only component allowed to change stock.
final stockPostingServiceProvider = Provider<StockPostingService>(
  (ref) => StockPostingService(
    inventory: ref.watch(inventoryRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
  ),
);

/// Live balances for one location, keyed by location id.
final locationBalancesProvider =
    StreamProvider.family<List<StockBalanceView>, String>(
      (ref, locationId) => ref
          .watch(inventoryRepositoryProvider)
          .watchBalancesAtLocation(locationId),
    );
