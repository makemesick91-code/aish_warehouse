import 'package:flutter/material.dart';

import '../../../../core/widgets/historical_master_badge.dart';
import '../../domain/models/opname_models.dart';

export '../../../../core/widgets/historical_master_badge.dart';

/// Names which parts of an opname header are historic, e.g. `Ruangan, Perawat`.
String _historicalMasterDetail(StockOpnameSummary summary) => [
  if (summary.branchIsHistorical) 'Cabang',
  if (summary.roomIsHistorical) 'Ruangan',
  if (summary.countedByIsHistorical) 'Perawat',
].join(', ');

/// The "Data historis" badge for one Stok Opname header, or nothing at all when
/// the document rests entirely on current master data.
///
/// A function rather than a static on [HistoricalMasterBadge], because the badge
/// itself is shared with Purchase Request and must not know what a Stok Opname
/// summary looks like. What is feature-specific is only *which* three flags to
/// read, which is exactly what stays here.
Widget opnameHistoricalBadge(StockOpnameSummary summary) =>
    HistoricalMasterBadge.forDetail(_historicalMasterDetail(summary));
