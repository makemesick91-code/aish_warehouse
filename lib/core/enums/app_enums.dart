/// Shared enums for Aish Warehouse.
///
/// Every enum carries the exact string persisted in SQLite (and later on the
/// sync backend) so the database contract stays stable even if a Dart
/// identifier is renamed.
library;

enum UserRole {
  perawat('perawat'),
  kepalaCabang('kepala_cabang'),
  warehouse('warehouse'),
  superAdmin('super_admin');

  const UserRole(this.dbValue);

  final String dbValue;

  /// Roles that operate inside a single branch and therefore require
  /// `users.branch_id` to be set.
  bool get requiresBranch => this == perawat || this == kepalaCabang;

  static UserRole fromDbValue(String value) => values.firstWhere(
    (role) => role.dbValue == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'Unknown UserRole'),
  );
}

enum SyncStatus {
  synced('synced'),
  pending('pending'),
  conflict('conflict');

  const SyncStatus(this.dbValue);

  final String dbValue;

  static SyncStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown SyncStatus'),
  );
}

enum StockLocationType {
  warehouse('warehouse'),
  branchStore('branch_store'),
  room('room');

  const StockLocationType(this.dbValue);

  final String dbValue;

  static StockLocationType fromDbValue(String value) => values.firstWhere(
    (type) => type.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown StockLocationType'),
  );
}

enum StockMovementType {
  inboundWarehouse('inbound_warehouse'),
  shipment('shipment'),
  goodReceipt('good_receipt'),
  distribution('distribution'),
  opnameAdjustment('opname_adjustment'),
  consumption('consumption'),
  itemReturn('return'),
  disposal('disposal'),
  reversal('reversal');

  const StockMovementType(this.dbValue);

  final String dbValue;

  /// Movement types that always move stock between two known locations.
  bool get isLocationToLocation =>
      this == shipment ||
      this == goodReceipt ||
      this == distribution ||
      this == itemReturn;

  static StockMovementType fromDbValue(String value) => values.firstWhere(
    (type) => type.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown StockMovementType'),
  );
}

/// Document types referenced by ledger entries (`ref_doc_type`).
abstract final class RefDocType {
  static const stockOpname = 'SO';
  static const purchaseRequest = 'PR';
  static const deliveryOrder = 'DO';
  static const goodReceipt = 'GR';
  static const distribution = 'DIST';

  /// Only used by the development seed so opening balances stay idempotent.
  static const seed = 'SEED';
}
