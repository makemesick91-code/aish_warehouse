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
///
/// `null` covers three cases on purpose: not seeded, no warehouse, and *more than
/// one* warehouse. A screen has nothing useful to say about the third — which of two
/// warehouses did it mean? — and reading the list rather than asking for "the"
/// warehouse is what keeps it from throwing a driver error on a dashboard. The
/// precise failure is produced where it matters, when a shipment is actually
/// posted (G-D3).
final warehouseLocationProvider = FutureProvider<MasterLocation?>((ref) async {
  final locations = await ref
      .watch(masterDataRepositoryProvider)
      .activeWarehouseLocations();
  return locations.length == 1 ? locations.single : null;
});
