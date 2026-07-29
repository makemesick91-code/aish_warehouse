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

/// Lifecycle of a Stok Opname document (schema v3).
///
/// The state machine only ever moves forward — `draft → submitted → reviewed` —
/// and `reviewed` is terminal (G-S1/G-S2). There is no un-submit and no
/// un-review: a mistake in a final document is corrected by a new adjusting
/// document, never by editing the old one.
enum StockOpnameStatus {
  draft('draft'),
  submitted('submitted'),
  reviewed('reviewed');

  const StockOpnameStatus(this.dbValue);

  final String dbValue;

  bool get isDraft => this == draft;

  bool get isSubmitted => this == submitted;

  bool get isReviewed => this == reviewed;

  /// Final documents — and their lines — are read-only permanently (G-S2).
  bool get isFinal => this == reviewed;

  /// Only a document that has left the nurse's hands may back a Purchase
  /// Request (G-O4). The PR module does not exist yet; this predicate is what
  /// it will ask.
  bool get isPurchaseRequestReference => this == submitted || this == reviewed;

  /// The single source of truth for allowed transitions (G-S1). Everything
  /// else — `draft → reviewed`, `submitted → draft`, any move out of
  /// `reviewed`, and re-entering the current state — is rejected.
  bool canTransitionTo(StockOpnameStatus next) => switch (this) {
    draft => next == submitted,
    submitted => next == reviewed,
    reviewed => false,
  };

  /// Indonesian label for chips and document timelines.
  String get label => switch (this) {
    draft => 'Draft',
    submitted => 'Menunggu Review',
    reviewed => 'Selesai Direview',
  };

  static StockOpnameStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown StockOpnameStatus'),
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
