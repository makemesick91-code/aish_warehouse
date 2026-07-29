import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../data/repositories/drift_master_data_repository.dart';
import '../../domain/models/master_models.dart';
import '../../domain/repositories/master_data_repository.dart';

final masterDataRepositoryProvider = Provider<MasterDataRepository>(
  (ref) => DriftMasterDataRepository(ref.watch(masterDataDaoProvider)),
);

/// Row counts for the development home page.
final masterSummaryProvider = FutureProvider<MasterSummary>(
  (ref) => ref.watch(masterDataRepositoryProvider).summary(),
);

/// The single central warehouse location, if master data has been seeded.
final warehouseLocationProvider = FutureProvider<MasterLocation?>(
  (ref) => ref.watch(masterDataRepositoryProvider).warehouseLocation(),
);
