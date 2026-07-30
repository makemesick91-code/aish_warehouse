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

/// Lifecycle of a Good Receipt (schema v7, spec §2.3/§3.2).
///
/// ```
/// checking ──▶ posted   (final)
/// ```
///
/// There is no third value and there never will be one on this document: a Good
/// Receipt is not cancelled, not un-posted and not reopened. A mistake in a
/// posted receipt is corrected by a new adjusting document — the same rule
/// `reviewed` and `received` follow (G-S2). Which transitions are permitted, and
/// who may drive them, is [GoodReceiptStatePolicy]'s to decide; this enum only
/// answers questions about a single status.
enum GoodReceiptStatus {
  checking('checking'),
  posted('posted');

  const GoodReceiptStatus(this.dbValue);

  final String dbValue;

  bool get isChecking => this == checking;

  bool get isPosted => this == posted;

  /// Only a document still being checked may have its lines decided or revised
  /// (G-G2). A posted receipt is read-only permanently.
  bool get isEditable => this == checking;

  /// Read-only permanently (G-S2).
  bool get isFinal => this == posted;

  /// Whether the branch head may still post this receipt to the ledger (G-G5).
  ///
  /// Says nothing about whether every line has been decided — that is a fact
  /// about the *lines*, which this enum cannot see. `GoodReceiptDetail.canPost`
  /// asks both halves.
  bool get canPost => this == checking;

  /// The single source of truth for allowed transitions on one status.
  /// Everything else — `posted → checking`, `posted → posted`, re-entering
  /// `checking` — is refused.
  bool canTransitionTo(GoodReceiptStatus next) => switch (this) {
    checking => next == posted,
    posted => false,
  };

  /// Indonesian label for chips and document timelines (§4.3).
  String get label => switch (this) {
    checking => 'Diperiksa',
    posted => 'Selesai Diposting',
  };

  static GoodReceiptStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown GoodReceiptStatus'),
  );
}

/// The decision recorded against one checked position of a Good Receipt (G-G2).
///
/// ```
/// pending ──▶ checked   (✔ sesuai)
///         └─▶ rejected  (✘ tidak sesuai)
/// ```
///
/// `rejected` is a **decision**, not a deletion. Spec §3.6 spells that out —
/// *"Hapus yang tidak sesuai" = tandai `rejected` — bukan menghapus record* — so
/// there is no fourth value for "removed" and no writer anywhere that takes a
/// line out of a document.
///
/// While the parent receipt is `checking` a decision may be revised in either
/// direction, which is why this enum deliberately does **not** declare `checked`
/// and `rejected` terminal: what freezes them is the parent's status, not their
/// own.
enum GoodReceiptLineStatus {
  pending('pending'),
  checked('checked'),
  rejected('rejected');

  const GoodReceiptLineStatus(this.dbValue);

  final String dbValue;

  bool get isPending => this == pending;

  bool get isChecked => this == checked;

  bool get isRejected => this == rejected;

  /// G-G2 — whether the branch head has said something about this position. A
  /// receipt cannot be posted while any line answers `false`.
  bool get isDecided => this != pending;

  /// Whether this decision adds stock to the branch store (G-G5). Only
  /// `checked` does — and then only for the quantity actually received.
  bool get addsStock => this == checked;

  /// Whether a stored reject reason is mandatory (G-G4).
  bool get requiresRejectReason => this == rejected;

  /// Indonesian label for line chips (§4.2).
  String get label => switch (this) {
    pending => 'Belum diperiksa',
    checked => 'Sesuai',
    rejected => 'Ditolak',
  };

  static GoodReceiptLineStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'Unknown GoodReceiptLineStatus',
    ),
  );
}

/// Lifecycle of a Distribusi (schema v8, spec §2.3/§3.2).
///
/// ```
/// draft ──▶ posted   (final)
/// ```
///
/// There is no third value and there never will be one on this document: a
/// distribution is not cancelled, not un-posted and not reopened. A mistake in a
/// posted distribution is corrected by a new adjusting document — the same rule
/// `reviewed`, `received` and the Good Receipt's `posted` follow (G-S1/G-S2).
/// Which transitions are permitted, and who may drive them, is
/// [DistributionStatePolicy]'s to decide; this enum only answers questions about
/// a single status.
enum DistributionStatus {
  draft('draft'),
  posted('posted');

  const DistributionStatus(this.dbValue);

  final String dbValue;

  bool get isDraft => this == draft;

  bool get isPosted => this == posted;

  /// Only a draft may have its rooms, items, quantities or batch allocations
  /// changed (G-S2). A posted distribution is read-only permanently.
  bool get isEditable => this == draft;

  /// Read-only permanently (G-S2).
  bool get isFinal => this == posted;

  /// Whether the branch head may still post this distribution to the ledger
  /// (G-T4).
  ///
  /// Says nothing about whether the document has any lines — that is a fact
  /// about the *lines*, which this enum cannot see. `DistributionDetail.canPost`
  /// asks both halves.
  bool get canPost => this == draft;

  /// The single source of truth for allowed transitions on one status.
  /// Everything else — `posted → draft`, `posted → posted`, re-entering
  /// `draft` — is refused.
  bool canTransitionTo(DistributionStatus next) => switch (this) {
    draft => next == posted,
    posted => false,
  };

  /// Indonesian label for chips and document timelines (§4.2).
  String get label => switch (this) {
    draft => 'Draft',
    posted => 'Selesai Diposting',
  };

  static DistributionStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown DistributionStatus'),
  );
}

/// Lifecycle of a Pemusnahan / Disposal (schema v9, G-E7).
///
/// ```
/// draft ──▶ posted   (final)
/// ```
///
/// There is no third value and there never will be one on this document: a
/// disposal is not submitted for approval, not cancelled, not un-posted and not
/// reopened. A mistake in a posted disposal is corrected by a reversal movement
/// against the ledger, never by editing the document — the same rule `reviewed`,
/// `received`, the Good Receipt's `posted` and the Distribusi's `posted` follow
/// (G-S1/G-S2).
///
/// ### Why there is no `submitted` / `approved` / `rejected`
///
/// The specification does not define a Disposal document at all — §2.3 lists no
/// such table and §3.2 no such state machine. What it does state is G-E7:
/// expired stock leaves *only* through a `disposal` movement carrying a note and
/// an actor. Milestone 7 therefore wraps that movement in the smallest auditable
/// document that can carry the note, the actor and the timestamps, and stops
/// there. Inventing an approval stage would be inventing a rule — and G-R4
/// (segregation of duties) is about not letting one person create *and approve*
/// the same document, which is a reason to have no approval stage here rather
/// than a licence to make one up. Posting is not approving: it is the moment the
/// stock physically leaves, performed by the one person the location's scope
/// allows.
enum DisposalStatus {
  draft('draft'),
  posted('posted');

  const DisposalStatus(this.dbValue);

  final String dbValue;

  bool get isDraft => this == draft;

  bool get isPosted => this == posted;

  /// Only a draft may have its source lines, quantities or reason changed
  /// (G-S2). A posted disposal is read-only permanently.
  bool get isEditable => this == draft;

  /// Read-only permanently (G-S2).
  bool get isFinal => this == posted;

  /// Whether the actor may still post this disposal to the ledger.
  ///
  /// Says nothing about whether the document has any lines or a reason — those
  /// are facts about the *lines* and the *header text*, which this enum cannot
  /// see. `DisposalDetail.canPost` asks all three.
  bool get canPost => this == draft;

  /// The single source of truth for allowed transitions on one status.
  /// Everything else — `posted → draft`, `posted → posted`, re-entering
  /// `draft` — is refused.
  bool canTransitionTo(DisposalStatus next) => switch (this) {
    draft => next == posted,
    posted => false,
  };

  /// Indonesian label for chips and document timelines.
  ///
  /// Deliberately *not* approval wording: there is no "Menunggu Persetujuan" and
  /// no "Disetujui" anywhere in this workflow, because there is no approval
  /// stage to describe.
  String get label => switch (this) {
    draft => 'Draft',
    posted => 'Sudah Diposting',
  };

  static DisposalStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown DisposalStatus'),
  );
}

/// Which locations a Pemusnahan query is allowed to reach (§14/§26).
///
/// The one enum in this library that is **not** persisted anywhere, and it carries
/// no `dbValue` for exactly that reason: it is a *query scope*, resolved into a
/// predicate on `stock_locations` by `DisposalDao`, and stored nowhere. It lives
/// here rather than beside either of them because both the DAO and the domain
/// access policy have to name it, and `lib/core/db/daos` may not import a feature
/// while a feature policy may not import drift — so a shared vocabulary needs a
/// home neither side owns.
///
/// A closed set of two rather than a free location id: the scope a screen may ask
/// for is a property of the *role*, not of the request. There is deliberately no
/// value meaning "any location" — no screen in this milestone is allowed one, and
/// the unscoped reads the use cases perform pass no scope at all.
enum DisposalLocationScope {
  /// Every `warehouse` location. The Petugas Warehouse's own shelves.
  warehouse,

  /// Every `branch_store` and `room` location of one branch — the Kepala Cabang's
  /// scope, which is why it needs a branch id and [warehouse] does not.
  branch,
}

/// Document types referenced by ledger entries (`ref_doc_type`).
abstract final class RefDocType {
  static const stockOpname = 'SO';
  static const purchaseRequest = 'PR';
  static const deliveryOrder = 'DO';
  static const goodReceipt = 'GR';
  static const distribution = 'DIST';

  /// Pemusnahan stok kedaluwarsa (schema v9, G-E7).
  ///
  /// Deliberately not `DIST`, which is the Distribusi's: a `ref_doc_type` that
  /// two document types shared would make the stock card unable to say which
  /// document a movement came from, and `movementsByRef` would return both.
  static const disposal = 'DSP';

  /// Only used by the development seed so opening balances stay idempotent.
  static const seed = 'SEED';
}
