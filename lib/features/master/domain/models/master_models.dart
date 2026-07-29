import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';

/// Domain models for master data. They intentionally mirror only the business
/// columns so the rest of the app never depends on Drift row classes.
///
/// Master rows carry two independent "no longer in use" signals, and the
/// difference matters to every historic document that points at them:
///
/// * `isActive == false` — deactivated (G-A4). The row may not be chosen for
///   anything new, but it is entirely intact.
/// * `isArchived == true` — soft deleted (G-A5), i.e. `deleted_at IS NOT NULL`.
///   Also intact; only hidden from the lists a user picks from.
///
/// Neither is deletion. A Stok Opname that is already `submitted` has no way
/// back to `draft`, so it must stay readable and reviewable against both
/// (§7.2) — the screens simply mark it as historic.
class MasterBranch {
  const MasterBranch({
    required this.id,
    required this.code,
    required this.name,
    this.address,
    required this.isActive,
    this.isArchived = false,
  });

  final String id;
  final String code;
  final String name;
  final String? address;
  final bool isActive;
  final bool isArchived;
}

class MasterRoom {
  const MasterRoom({
    required this.id,
    required this.branchId,
    required this.code,
    required this.name,
    required this.isActive,
    this.isArchived = false,
  });

  final String id;
  final String branchId;
  final String code;
  final String name;
  final bool isActive;
  final bool isArchived;
}

class MasterUser {
  const MasterUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.branchId,
    required this.isActive,
  });

  final String id;
  final String fullName;
  final String email;
  final UserRole role;
  final String? branchId;
  final bool isActive;
}

class MasterCategory {
  const MasterCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class MasterItem {
  const MasterItem({
    required this.id,
    required this.sku,
    required this.name,
    required this.categoryId,
    required this.unit,
    required this.minStockRoom,
    required this.minStockBranch,
    required this.hasExpiry,
    required this.expiryAlertDays,
    required this.isActive,
  });

  final String id;
  final String sku;
  final String name;
  final String categoryId;
  final String unit;
  final int minStockRoom;
  final int minStockBranch;
  final bool hasExpiry;
  final int expiryAlertDays;
  final bool isActive;
}

class MasterBatch {
  const MasterBatch({
    required this.id,
    required this.itemId,
    required this.batchNo,
    required this.expiryDate,
  });

  final String id;
  final String itemId;
  final String batchNo;

  /// Civil date, carried as a UTC midnight value and never converted (T-8).
  final DateTime expiryDate;

  /// A batch is usable until the end of its expiry date (G-E4), where "end of
  /// day" means the operational day in GMT+8 rather than the device's (T-10).
  ///
  /// [referenceUtc] is a UTC instant — typically the injected clock.
  bool isExpiredOn(DateTime referenceUtc) => DateOnly.isBeforeDate(
    expiryDate,
    AppTimeZone.operationalDate(referenceUtc),
  );
}

class MasterLocation {
  const MasterLocation({
    required this.id,
    required this.type,
    this.branchId,
    this.roomId,
    required this.name,
    this.isArchived = false,
  });

  final String id;
  final StockLocationType type;
  final String? branchId;
  final String? roomId;
  final String name;

  /// `deleted_at IS NOT NULL`. Locations have no `is_active` column, so this is
  /// the only historic marker they carry — and it never means the balances
  /// stored against it stopped existing.
  final bool isArchived;
}

/// Row counts shown on the development home page.
class MasterSummary {
  const MasterSummary({
    required this.branches,
    required this.rooms,
    required this.categories,
    required this.items,
    required this.locations,
    required this.users,
  });

  final int branches;
  final int rooms;
  final int categories;
  final int items;
  final int locations;
  final int users;

  bool get isEmpty => branches == 0 && items == 0 && locations == 0;
}
