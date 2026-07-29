import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'daos/inventory_dao.dart';
import 'daos/master_data_dao.dart';
import 'daos/opname_dao.dart';
import 'database_connection.dart';

/// Single owner of the database handle.
///
/// Tests override this provider with an in-memory database, which is why no
/// part of the app ever constructs [AppDatabase] directly.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase(openAppDatabaseConnection());
  ref.onDispose(database.close);
  return database;
});

final masterDataDaoProvider = Provider<MasterDataDao>(
  (ref) => ref.watch(appDatabaseProvider).masterDataDao,
);

final inventoryDaoProvider = Provider<InventoryDao>(
  (ref) => ref.watch(appDatabaseProvider).inventoryDao,
);

final opnameDaoProvider = Provider<OpnameDao>(
  (ref) => ref.watch(appDatabaseProvider).opnameDao,
);
