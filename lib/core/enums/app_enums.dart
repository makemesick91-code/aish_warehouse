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

  /// Indonesian label, for error messages and the session card.
  ///
  /// Here rather than in each caller because the same four words were being
  /// spelled out in the session, in the opname guards and in the Purchase Request
  /// guards — three copies of a mapping that has one right answer.
  String get label => switch (this) {
    perawat => 'Perawat',
    kepalaCabang => 'Kepala Cabang',
    warehouse => 'Petugas Warehouse',
    superAdmin => 'Super Admin',
  };

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

/// Lifecycle of a Purchase Request (schema v5, spec §2.3/§3.2).
///
/// ```
/// draft ──▶ submitted ──▶ processing ──▶ shipped ──▶ closed
///       └─▶ cancelled  └─▶ cancelled   └─▶ rejected
/// ```
///
/// The enum carries the whole vocabulary the database and the sync backend will
/// ever store, including the two states Milestone 3 does not open: `shipped` and
/// `closed` belong to Delivery Order and Good Receipt. They are values here so a
/// row written by a later version — or by the server — round-trips through this
/// converter instead of throwing, but no use case and no button in this
/// milestone can produce them. Which transitions are permitted, and which of
/// them a *user* may trigger, is [PurchaseRequestStatePolicy]'s to decide; this
/// enum only answers questions about a single status.
enum PurchaseRequestStatus {
  draft('draft'),
  submitted('submitted'),
  processing('processing'),
  shipped('shipped'),
  closed('closed'),
  rejected('rejected'),
  cancelled('cancelled');

  const PurchaseRequestStatus(this.dbValue);

  final String dbValue;

  bool get isDraft => this == draft;

  bool get isSubmitted => this == submitted;

  bool get isProcessing => this == processing;

  bool get isShipped => this == shipped;

  bool get isClosed => this == closed;

  bool get isRejected => this == rejected;

  bool get isCancelled => this == cancelled;

  /// G-P4 — the two states that occupy a branch's single active order slot.
  bool get isActiveOrder => this == submitted || this == processing;

  /// Read-only permanently (G-S2).
  ///
  /// `shipped` is deliberately **not** final: the goods are on their way but the
  /// document is still waiting for every Good Receipt before it becomes
  /// `closed`.
  bool get isFinal => this == closed || this == rejected || this == cancelled;

  /// G-P5 — only a draft may be edited at all. A submitted PR is corrected by
  /// cancelling it and creating a new one, never by editing.
  bool get isEditable => this == draft;

  /// G-P5/G-S3 — cancellation is only possible before the warehouse starts
  /// working on the order.
  bool get canCancel => this == draft || this == submitted;

  /// Indonesian label for chips and document timelines (§4.3).
  String get label => switch (this) {
    draft => 'Draft',
    submitted => 'Menunggu Diproses',
    processing => 'Sedang Diproses',
    shipped => 'Dikirim',
    closed => 'Selesai',
    rejected => 'Ditolak',
    cancelled => 'Dibatalkan',
  };

  static PurchaseRequestStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'Unknown PurchaseRequestStatus',
    ),
  );
}

/// Lifecycle of a Delivery Order / Surat Jalan (schema v6, spec §2.3/§3.2).
///
/// ```
/// preparing ──▶ shipped ──▶ received   (final)
/// ```
///
/// Only the first transition belongs to Milestone 4. `received` is a value here
/// because the database and the sync backend will store it and a row written by
/// a later version — or by the server — must round-trip through the converter
/// instead of throwing. Which transitions are permitted, and who may drive them,
/// is [DeliveryOrderStatePolicy]'s to decide; this enum only answers questions
/// about a single status.
enum DeliveryOrderStatus {
  preparing('preparing'),
  shipped('shipped'),
  received('received');

  const DeliveryOrderStatus(this.dbValue);

  final String dbValue;

  bool get isPreparing => this == preparing;

  bool get isShipped => this == shipped;

  bool get isReceived => this == received;

  /// Read-only permanently (G-S2). `shipped` is deliberately **not** final: the
  /// goods are on their way but the branch has not checked them in yet.
  bool get isFinal => this == received;

  /// Only a document that has not left the warehouse may be edited (G-S1/G-S2).
  bool get isEditable => this == preparing;

  /// Whether the warehouse may still post this document to the ledger.
  bool get canShip => this == preparing;

  /// Whether the goods have physically left the central warehouse — the two
  /// statuses whose quantities count towards G-D2's cumulative total.
  bool get countsAsShipped => this == shipped || this == received;

  /// Indonesian label for chips and document timelines (§4.3).
  String get label => switch (this) {
    preparing => 'Disiapkan',
    shipped => 'Dikirim',
    received => 'Diterima',
  };

  static DeliveryOrderStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'Unknown DeliveryOrderStatus',
    ),
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
