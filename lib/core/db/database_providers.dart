import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'daos/delivery_order_dao.dart';
import 'daos/disposal_dao.dart';
import 'daos/distribution_dao.dart';
import 'daos/good_receipt_dao.dart';
import 'daos/inventory_dao.dart';
import 'daos/master_data_dao.dart';
import 'daos/opname_dao.dart';
import 'daos/purchase_request_dao.dart';
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

final purchaseRequestDaoProvider = Provider<PurchaseRequestDao>(
  (ref) => ref.watch(appDatabaseProvider).purchaseRequestDao,
);

final deliveryOrderDaoProvider = Provider<DeliveryOrderDao>(
  (ref) => ref.watch(appDatabaseProvider).deliveryOrderDao,
);

final goodReceiptDaoProvider = Provider<GoodReceiptDao>(
  (ref) => ref.watch(appDatabaseProvider).goodReceiptDao,
);

final distributionDaoProvider = Provider<DistributionDao>(
  (ref) => ref.watch(appDatabaseProvider).distributionDao,
);

final disposalDaoProvider = Provider<DisposalDao>(
  (ref) => ref.watch(appDatabaseProvider).disposalDao,
);
