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

  /// Retur barang rejected dari Good Receipt, kembali ke Warehouse Pusat
  /// (schema v11, G-G5).
  ///
  /// The database value is `return`, exactly as §2.2 lists it. The Dart identifier
  /// cannot be: `return` is a reserved keyword. `itemReturn` is therefore the name
  /// the code uses and `'return'` the string the ledger stores — the split the
  /// `dbValue` field on every enum in this library exists for, so a Dart rename can
  /// never change the database contract.
  itemReturn('return'),
  disposal('disposal'),
  reversal('reversal');

  const StockMovementType(this.dbValue);

  final String dbValue;

  /// Movement types that always move stock between two known locations.
  ///
  /// [itemReturn] is deliberately **not** here, and that is a Milestone 9 correction
  /// rather than an oversight. A Good Receipt rejection never entered the branch
  /// store's balance — G-G5 credits only `checked` lines — so the goods have no source
  /// location to leave: the shipment already debited the Warehouse and left them in
  /// transit. The return therefore posts `from_location_id = NULL` and credits the
  /// Warehouse alone (§12/§22), which is the same one-legged shape
  /// [inboundWarehouse] has. Listing it here would make [StockPostingService.postTransfer]
  /// accept it and then demand two locations it must not have.
  bool get isLocationToLocation =>
      this == shipment || this == goodReceipt || this == distribution;

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

/// Lifecycle of a Pemakaian / Consumption (schema v10, §7).
///
/// ```
/// draft ──▶ posted   (final)
/// ```
///
/// There is no third value and there never will be one on this document: a
/// consumption is not submitted for approval, not cancelled, not un-posted and not
/// reopened. A mistake in a posted consumption is corrected by a reversal movement
/// against the ledger, never by editing the document — the same rule `reviewed`,
/// `received`, the Good Receipt's `posted`, the Distribusi's `posted` and the
/// Pemusnahan's `posted` follow (G-S1/G-S2).
///
/// ### Why there is no `submitted` / `approved` / `rejected`
///
/// **This is an extension decision, not a rule the specification states.** §2.3
/// lists no Consumption table and §3.2 gives it no state machine; what the
/// specification does state is that `stock_movements.movement_type` has a
/// `consumption` value and that `to_location_id` is *"NULL jika barang keluar
/// sistem (pemakaian/buang)"* (§2.2). Milestone 8 therefore wraps that movement in
/// the smallest auditable document that can carry the room, the actor and the
/// timestamps, and stops there.
///
/// Inventing an approval stage would be inventing a rule. G-R4 — *"tidak ada satu
/// peran pun yang bisa membuat sekaligus menyetujui dokumen yang sama"* — forbids
/// one person doing both halves of a *two-half* workflow, which is a reason not to
/// invent a second half here rather than a licence to. Posting is not approving: it
/// is the moment the goods physically leave the room, performed by the nurse who
/// used them. The UI wording follows: *Posting Pemakaian*, never *Setujui*.
enum ConsumptionStatus {
  draft('draft'),
  posted('posted');

  const ConsumptionStatus(this.dbValue);

  final String dbValue;

  bool get isDraft => this == draft;

  bool get isPosted => this == posted;

  /// Only a draft may have its lines, quantities or note changed (G-S2). A posted
  /// consumption is read-only permanently.
  bool get isEditable => this == draft;

  /// Read-only permanently (G-S2).
  bool get isFinal => this == posted;

  /// Whether the nurse may still post this consumption to the ledger.
  ///
  /// Says nothing about whether the document has any lines — that is a fact about
  /// the *lines*, which this enum cannot see. `ConsumptionDetail.canPost` asks both
  /// halves.
  bool get canPost => this == draft;

  /// The single source of truth for allowed transitions on one status.
  /// Everything else — `posted → draft`, `posted → posted`, re-entering `draft` —
  /// is refused.
  bool canTransitionTo(ConsumptionStatus next) => switch (this) {
    draft => next == posted,
    posted => false,
  };

  /// Indonesian label for chips and document timelines.
  ///
  /// Deliberately *not* approval wording: there is no "Menunggu Persetujuan" and no
  /// "Disetujui" anywhere in this workflow, because there is no approval stage to
  /// describe. The action label the form shows is *Posting Pemakaian*.
  String get label => switch (this) {
    draft => 'Draft',
    posted => 'Sudah Diposting',
  };

  static ConsumptionStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown ConsumptionStatus'),
  );
}

/// Lifecycle of a Retur Barang / Goods Return (schema v11, §8).
///
/// ```
/// draft ──▶ shipped ──▶ received   (final)
/// ```
///
/// ### Every one of these three states is an extension decision
///
/// **The specification defines no Return document.** §2.3 lists no such table and
/// §3.2 gives it no state machine. What it does state is that
/// `stock_movements.movement_type` has a `return` value (§2.2), that a rejected Good
/// Receipt line *"masuk daftar retur ke Warehouse"* (G-G5), that rejected lines stay
/// as audit records carrying a reason (G-G4), and that the Warehouse UI shows
/// *"daftar barang rejected dari GR cabang untuk ditindaklanjuti"* (§4.2). Milestone 9
/// therefore wraps that movement in the smallest auditable document that can carry
/// the two physical events the specification implies — the goods leaving the branch
/// and the goods arriving at the Warehouse — and stops there. **The three states
/// below, their names and their actors are documented decisions rather than rules the
/// specification states.**
///
/// ### Why `shipped` exists at all
///
/// Because the goods spend real time in transit, and the ledger must not pretend
/// otherwise. G-A2 forbids a negative balance and G-A1 makes the ledger append-only,
/// so a Warehouse balance credited the moment a branch says *"sent"* would be stock
/// the Warehouse could distribute before the box arrives. `shipped` is therefore a
/// purely documentary state: it records that a Kepala Cabang handed the goods over,
/// and posts **nothing** (§20).
///
/// ### Why there is no approval, cancel, un-ship or un-receive
///
/// G-R4 — *"tidak ada satu peran pun yang bisa membuat sekaligus menyetujui dokumen
/// yang sama"* — is satisfied structurally here: the branch ships and the Warehouse
/// receives, two different roles, and the receiving actor may be neither the creator
/// nor the shipper. Adding an approval stage on top would be inventing a third half
/// of a two-half workflow. `received` is final for the reason `reviewed`, `received`
/// and every `posted` in this schema are final (G-S1/G-S2): a mistake is corrected by
/// a new adjusting document or a reversal movement, never by editing history.
///
/// Which transitions are permitted, and who may drive them, is
/// [GoodsReturnStatePolicy]'s to decide; this enum only answers questions about a
/// single status.
enum GoodsReturnStatus {
  draft('draft'),
  shipped('shipped'),
  received('received');

  const GoodsReturnStatus(this.dbValue);

  final String dbValue;

  bool get isDraft => this == draft;

  bool get isShipped => this == shipped;

  bool get isReceived => this == received;

  /// Only a draft may have its note changed (§19). The *lines* are immutable from
  /// the moment they are snapshotted, in every status including this one — see
  /// `GoodsReturnSnapshotPolicy` — so "editable" here means the header note and
  /// nothing else.
  bool get isEditable => this == draft;

  /// Read-only permanently (G-S2).
  ///
  /// `shipped` is deliberately **not** final: the goods are in transit but the
  /// Warehouse has not confirmed them yet.
  bool get isFinal => this == received;

  /// Whether the Kepala Cabang may still mark the goods as handed over (§20).
  bool get canShip => this == draft;

  /// Whether the Petugas Warehouse may still confirm arrival and post the ledger
  /// (§21).
  bool get canReceive => this == shipped;

  /// The single source of truth for allowed transitions on one status. Everything
  /// else — `draft → received` (skipping the transit leg), `shipped → draft` (no
  /// un-ship), any move out of `received` (no un-receive, no reopen) and re-entering
  /// the current state (no double ship, no double receive) — is refused.
  bool canTransitionTo(GoodsReturnStatus next) => switch (this) {
    draft => next == shipped,
    shipped => next == received,
    received => false,
  };

  /// Indonesian label for chips and document timelines (§8).
  ///
  /// Deliberately *not* approval wording: there is no "Menunggu Persetujuan" and no
  /// "Disetujui" anywhere in this workflow, because there is no approval stage to
  /// describe. The two action labels the screens show are *Kirim Retur* and
  /// *Terima Retur*.
  String get label => switch (this) {
    draft => 'Draft',
    shipped => 'Dikirim ke Warehouse',
    received => 'Diterima Warehouse',
  };

  static GoodsReturnStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown GoodsReturnStatus'),
  );
}

/// Which Retur documents a query is allowed to reach (§15/§24).
///
/// The third enum in this library that is **not** persisted anywhere, and it carries no
/// `dbValue` for exactly that reason: it is a *query scope*, resolved into a predicate
/// on `goods_returns` by `GoodsReturnDao`, and stored nowhere. It lives here rather
/// than beside either of them for the reason [DisposalLocationScope] spells out: both
/// the DAO and the domain access policy have to name it, and `lib/core/db/daos` may not
/// import a feature while a feature policy may not import drift — so a shared
/// vocabulary needs a home neither side owns.
///
/// A closed set of two rather than a free predicate: the scope a screen may ask for is a
/// property of the *role*, not of the request. There is deliberately no value meaning
/// "every return" — no screen in this milestone is allowed one, and the unscoped reads
/// the use cases perform pass no scope at all.
enum GoodsReturnQueryScope {
  /// Every return of one branch, in every status — the Kepala Cabang's own section.
  /// Needs a branch id; a scope asked for without one matches nothing.
  branch,

  /// Every return that has physically left a branch — the Petugas Warehouse's queue and
  /// history, across every branch. The `status IN ('shipped', 'received')` half is baked
  /// into the DAO's predicate rather than left to the caller's status set: a Warehouse
  /// user must never see a branch's unfinished draft (§15), and a rule that depended on
  /// a parameter being passed correctly would be one call site away from leaking one.
  warehouseInTransitOrReceived,
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

/// Which Pemakaian documents a query is allowed to reach (§14/§23).
///
/// The second enum in this library that is **not** persisted anywhere, and it carries
/// no `dbValue` for exactly that reason: it is a *query scope*, resolved into a
/// predicate on `consumptions` by `ConsumptionDao`, and stored nowhere. It lives here
/// rather than beside either of them for the reason [DisposalLocationScope] spells
/// out: both the DAO and the domain access policy have to name it, and
/// `lib/core/db/daos` may not import a feature while a feature policy may not import
/// drift — so a shared vocabulary needs a home neither side owns.
///
/// A closed set of two rather than a free predicate: the scope a screen may ask for is
/// a property of the *role*, not of the request. There is deliberately no value
/// meaning "every consumption" — no screen in this milestone is allowed one, and the
/// unscoped reads the use cases perform pass no scope at all.
enum ConsumptionQueryScope {
  /// Documents one user created — the Perawat's own drafts *and* their own posted
  /// history. Needs a user id; a scope asked for without one matches nothing.
  ///
  /// The first *ownership* scope in the application. Every earlier document is scoped
  /// by place; a Pemakaian draft is one nurse's account of a shift, so a second nurse
  /// editing it would be rewriting a record of work they did not do.
  ownDocuments,

  /// Every **posted** document of one branch — the Kepala Cabang's read-only history.
  /// Needs a branch id, and the `posted` half is baked into the DAO's predicate rather
  /// than left to the caller's status set: a branch head must never see a nurse's
  /// unfinished draft, and a rule that depended on a parameter being passed correctly
  /// would be one call site away from leaking one.
  branchPosted,
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

  /// Pemakaian barang di ruangan (schema v10, §10).
  ///
  /// Deliberately not `DIST`, `DSP` or `SO`. Every one of those already names a
  /// document type, and a `ref_doc_type` two types shared would make the stock card
  /// unable to say which document a movement came from — `movementsByRef` would
  /// return both. §2.2 lists only `PR / DO / GR / DIST / SO`, so this value, like
  /// `DSP`, is an extension this milestone documents rather than a rule the
  /// specification states.
  static const consumption = 'CONS';

  /// Retur barang rejected ke Warehouse Pusat (schema v11, §9).
  ///
  /// Deliberately not `GR`, which is the Good Receipt's. A return is *raised from* a
  /// Good Receipt and snapshots its rejected lines, so sharing `GR` would be the most
  /// tempting mistake here — and the most damaging: `movementsByRef` would return the
  /// receipt's inbound credits and the return's alongside each other, and a stock card
  /// could no longer say which document moved which quantity. §2.2 lists only
  /// `PR / DO / GR / DIST / SO`, so this value, like `DSP` and `CONS`, is an extension
  /// this milestone documents rather than a rule the specification states.
  static const goodsReturn = 'RET';

  /// Only used by the development seed so opening balances stay idempotent.
  static const seed = 'SEED';
}

// --- Reporting & Export (Milestone 10, schema v12) ---------------------------

/// Which report is being previewed or exported (§9).
///
/// The `dbValue` of each is what `export_logs.report_type` stores, and the values
/// are the snake_case names the specification uses in G-L5's filename pattern —
/// so the audit row, the file name and the enum can never drift apart.
///
/// ### Seven values are the specification's, four are this milestone's
///
/// §4.2 names `stok_lokasi`, `kartu_stok`, `rekap_opname`, `rekap_pr`,
/// `rekap_gr`, `rekap_distribusi` and — through G-E8 — `kadaluarsa`. The other
/// four are a **documented extension** rather than a rule the specification
/// states:
///
/// * `rekap_do` — §4.2's Warehouse *Laporan* screen asks for *"rekap PR/DO per
///   cabang & per periode"* in the same breath, so leaving the DO half out would
///   contradict the screen the specification describes.
/// * `rekap_pemakaian`, `rekap_pemusnahan`, `rekap_retur` — Pemakaian, Pemusnahan
///   and Retur became first-class workflows in Milestones 7–9 and each posts its
///   own `movement_type`. A reporting module that could not recap them would be
///   unable to explain three of the eight ways stock moves.
///
/// None of them changes a stock rule: every one is a *view* over ledger rows and
/// documents that already exist.
///
/// ### What this enum deliberately does not know
///
/// **Who may run it.** The access matrix is [ReportAccessPolicy]'s, per role and
/// per scope, and putting a `allowedRoles` getter here would be a second copy of
/// it that has to agree by hand. The helpers below answer only questions about the
/// *shape* of a report — questions whose answer is the same for every role.
enum ReportType {
  /// Saldo per lokasi as of one date, derived from the ledger (G-L4).
  stokLokasi('stok_lokasi'),

  /// Mutasi one item at one location across a period, with a running balance.
  kartuStok('kartu_stok'),

  rekapOpname('rekap_opname'),

  rekapPr('rekap_pr'),

  /// Extension — see the class note.
  rekapDo('rekap_do'),

  rekapGr('rekap_gr'),

  rekapDistribusi('rekap_distribusi'),

  /// Extension — see the class note.
  rekapPemakaian('rekap_pemakaian'),

  /// Extension — see the class note.
  rekapPemusnahan('rekap_pemusnahan'),

  /// Extension — see the class note.
  rekapRetur('rekap_retur'),

  /// Sisa per batch urut ED terdekat (G-E8).
  kadaluarsa('kadaluarsa');

  const ReportType(this.dbValue);

  final String dbValue;

  /// Indonesian title, shown on screen and printed in every export header.
  String get label => switch (this) {
    ReportType.stokLokasi => 'Stok Saat Ini',
    ReportType.kartuStok => 'Kartu Stok',
    ReportType.rekapOpname => 'Rekap Stok Opname',
    ReportType.rekapPr => 'Rekap Purchase Request',
    ReportType.rekapDo => 'Rekap Delivery Order',
    ReportType.rekapGr => 'Rekap Penerimaan dan Selisih GR',
    ReportType.rekapDistribusi => 'Rekap Distribusi',
    ReportType.rekapPemakaian => 'Rekap Pemakaian',
    ReportType.rekapPemusnahan => 'Rekap Pemusnahan',
    ReportType.rekapRetur => 'Rekap Retur',
    ReportType.kadaluarsa => 'Laporan Kedaluwarsa',
  };

  /// Whether the report is meaningless without exactly one stock location.
  ///
  /// True for [kartuStok] alone: a stock card with a running balance is a
  /// statement about *one shelf*. Summing two locations into one running balance
  /// would produce a column of numbers that reconciles against nothing.
  bool get requiresExactLocation => this == ReportType.kartuStok;

  /// Whether the report is meaningless without exactly one item — again
  /// [kartuStok] alone, for the same reason.
  bool get requiresItem => this == ReportType.kartuStok;

  /// Whether the report describes a *position* at one instant rather than what
  /// happened over a period.
  ///
  /// [stokLokasi] and [kadaluarsa] are both "what is on the shelf as of this
  /// date", so their period collapses to a single as-of date and the export log
  /// stores `period_start == period_end` (§3.9).
  bool get isAsOfReport =>
      this == ReportType.stokLokasi || this == ReportType.kadaluarsa;

  /// The complement of [isAsOfReport]: a report over a date range.
  bool get isPeriodReport => !isAsOfReport;

  /// Whether every quantity this report prints comes from `stock_movements`.
  ///
  /// True for the three stock reports. The recaps are *mixed*: their document
  /// columns (requested qty, counted qty, status, actor) come from the document
  /// tables, and every column describing a stock effect still comes from the
  /// ledger (§3.6). So this is not "does it read the ledger" — they all do — but
  /// "is the ledger the only source it reads".
  bool get isLedgerPrimary =>
      this == ReportType.stokLokasi ||
      this == ReportType.kartuStok ||
      this == ReportType.kadaluarsa;

  /// Whether the report can be run over a whole branch — its store plus every
  /// room — in one pass.
  ///
  /// False for [kartuStok] (see [requiresExactLocation]) and for every recap: a
  /// recap is already scoped by the documents it reads, and `branch_all` is a
  /// *location* scope with nothing to say about a Purchase Request.
  bool get supportsBranchAll =>
      this == ReportType.stokLokasi || this == ReportType.kadaluarsa;

  /// Whether the report can span branches for a Warehouse account.
  ///
  /// True for the recaps and false for the three stock reports, and the asymmetry
  /// is G-L1: a Petugas Warehouse reports on *documents* across every branch, but
  /// their stock view is Warehouse Pusat. Reading a room's current balance is a
  /// branch matter.
  bool get supportsCrossBranch => !isLedgerPrimary;

  static ReportType fromDbValue(String value) => values.firstWhere(
    (type) => type.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown ReportType'),
  );
}

/// The file a report is exported as (§10).
///
/// Two values, and there will not quietly be a third: G-L5 names `.xlsx` and
/// `.pdf`, and a CSV masquerading as a spreadsheet would lose the category
/// subtotals G-L6 requires and the formatting an auditor reads.
enum ReportFormat {
  xlsx('xlsx'),
  pdf('pdf');

  const ReportFormat(this.dbValue);

  final String dbValue;

  String get label => switch (this) {
    ReportFormat.xlsx => 'Excel',
    ReportFormat.pdf => 'PDF',
  };

  /// The filename suffix, dot included.
  String get fileExtension => switch (this) {
    ReportFormat.xlsx => '.xlsx',
    ReportFormat.pdf => '.pdf',
  };

  static ReportFormat fromDbValue(String value) => values.firstWhere(
    (format) => format.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown ReportFormat'),
  );
}

/// How wide a report reaches (§11).
///
/// Persisted in `export_logs.scope_type`, and the reason it is a stored column
/// rather than something derivable from `location_id`/`branch_id` is that three of
/// the six carry neither: an audit row has to say *what was asked for*, not leave a
/// reader to infer it from two NULLs.
///
/// ### `branch_all` never means "every branch"
///
/// The specification's vocabulary is `warehouse` / `branch_store` / `room` /
/// `branch_all`, and the temptation with only those four is to write
/// `branch_all` with `branch_id = NULL` and call it cross-branch. That is
/// precisely the shape this enum refuses: a NULL would make an audit row
/// ambiguous — was this one branch whose id was lost, or every branch? — and the
/// database CHECK that pins `branch_all` to a non-NULL branch is what makes the
/// question unanswerable-by-accident impossible. [crossBranch] and [allLocations]
/// are therefore explicit values, and both are a documented extension rather than
/// specification vocabulary.
enum ReportScopeType {
  /// Exactly one Warehouse Pusat location.
  warehouse('warehouse'),

  /// Exactly one Gudang Cabang location.
  branchStore('branch_store'),

  /// Exactly one Ruangan location.
  room('room'),

  /// One branch's store **and** every room in it. The rows stay grouped per
  /// location — a branch total that netted a distribution between the store and a
  /// room would hide where the stock actually is (§21).
  branchAll('branch_all'),

  /// Extension: document recaps across every branch, for a Petugas Warehouse.
  /// Carries no location and no branch — it is not a place.
  crossBranch('cross_branch'),

  /// Extension: everything, everywhere, for a Super Admin.
  allLocations('all_locations');

  const ReportScopeType(this.dbValue);

  final String dbValue;

  String get label => switch (this) {
    ReportScopeType.warehouse => 'Warehouse Pusat',
    ReportScopeType.branchStore => 'Gudang Cabang',
    ReportScopeType.room => 'Ruangan',
    ReportScopeType.branchAll => 'Semua Lokasi Cabang',
    ReportScopeType.crossBranch => 'Lintas Cabang',
    ReportScopeType.allLocations => 'Semua Lokasi',
  };

  /// Whether the scope names exactly one stock location.
  bool get requiresLocation =>
      this == ReportScopeType.warehouse ||
      this == ReportScopeType.branchStore ||
      this == ReportScopeType.room;

  /// Whether the scope names exactly one branch.
  ///
  /// [warehouse] is deliberately excluded: Warehouse Pusat belongs to no branch
  /// (`stock_locations` CHECKs it), so an export log naming both would describe a
  /// location that cannot exist.
  bool get requiresBranch =>
      this == ReportScopeType.branchStore ||
      this == ReportScopeType.room ||
      this == ReportScopeType.branchAll;

  /// The stock location type this scope's location must be, or `null` when the
  /// scope names no single location.
  ///
  /// SQLite cannot enforce this — the CHECK on `export_logs` can only see its own
  /// columns — so the use cases revalidate it against `stock_locations.type`.
  StockLocationType? get requiredLocationType => switch (this) {
    ReportScopeType.warehouse => StockLocationType.warehouse,
    ReportScopeType.branchStore => StockLocationType.branchStore,
    ReportScopeType.room => StockLocationType.room,
    ReportScopeType.branchAll ||
    ReportScopeType.crossBranch ||
    ReportScopeType.allLocations => null,
  };

  static ReportScopeType fromDbValue(String value) => values.firstWhere(
    (scope) => scope.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown ReportScopeType'),
  );
}

// --- Master Data & Template Import (Milestone 11) ----------------------------

/// The six master entities a Super Admin may import (G-M4, §9).
///
/// One entity per workbook, deliberately. A multi-entity workbook would have to
/// decide what happens when sheet 2 fails after sheet 1 validated — and the only
/// answers are "commit half of it", which G-M3 forbids, or "reject both", which
/// makes a 3000-row item sheet unusable because one category row was misspelled.
/// Per-entity files keep the atomic unit and the user's mental unit the same
/// thing.
///
/// The `dbValue`s are the physical table names, so a row in `import_logs` names
/// the table it touched without a second mapping to keep in step.
///
/// ### Why the header lists live here
///
/// [headers] is the single ordered source the template generator writes, the
/// parser validates against and the tests pin. Splitting it — a list in the
/// generator, a copy in the parser — is how a template stops matching the
/// importer that reads it, which is the exact failure G-M2 exists to prevent.
/// What is deliberately **not** here is any parsing, normalization or validation
/// logic: this enum answers *which columns*, never *what the values mean*.
enum ImportEntity {
  items('items'),
  itemCategories('item_categories'),
  branches('branches'),
  rooms('rooms'),
  users('users'),
  itemBatches('item_batches');

  const ImportEntity(this.dbValue);

  final String dbValue;

  /// Indonesian label (§9), for cards, dropdowns and audit rows.
  String get label => switch (this) {
    items => 'Barang',
    itemCategories => 'Kategori',
    branches => 'Cabang',
    rooms => 'Ruangan',
    users => 'Pengguna',
    itemBatches => 'Batch',
  };

  /// The filename stem of this entity's template, without version or extension.
  ///
  /// `template_master_barang` + `_aish-master-v1` + `.xlsx` (§26).
  String get templateFileStem => switch (this) {
    items => 'template_master_barang',
    itemCategories => 'template_master_kategori',
    branches => 'template_master_cabang',
    rooms => 'template_master_ruangan',
    users => 'template_master_pengguna',
    itemBatches => 'template_master_batch',
  };

  /// Every column of the Data sheet, **in the exact order** row 1 must carry.
  List<String> get headers => switch (this) {
    branches => const ['code', 'name', 'address', 'is_active'],
    rooms => const ['branch_code', 'code', 'name', 'is_active'],
    users => const ['full_name', 'email', 'role', 'branch_code', 'is_active'],
    itemCategories => const ['name'],
    items => const [
      'sku',
      'name',
      'category_name',
      'unit',
      'min_stock_room',
      'min_stock_branch',
      'has_expiry',
      'expiry_alert_days',
      'is_active',
    ],
    itemBatches => const ['item_sku', 'batch_no', 'expiry_date'],
  };

  /// Columns a row may not leave blank.
  ///
  /// `address` is optional on a branch because a clinic genuinely may not have
  /// one recorded yet; `branch_code` is optional on a user because two of the
  /// four roles must leave it blank (§14.3) — "optional" here means *the header
  /// may hold nothing*, and the role rule decides whether nothing is correct.
  List<String> get requiredHeaders => switch (this) {
    branches => const ['code', 'name', 'is_active'],
    rooms => const ['branch_code', 'code', 'name', 'is_active'],
    users => const ['full_name', 'email', 'role', 'is_active'],
    itemCategories => const ['name'],
    items => headers,
    itemBatches => headers,
  };

  List<String> get optionalHeaders =>
      headers.where((header) => !requiredHeaders.contains(header)).toList();

  /// The columns whose normalized values form the natural key (G-M4, §3.1).
  ///
  /// A room's key is `branch_code + code` rather than `code` alone: the schema
  /// already allows `R1` in every branch (`UNIQUE(branch_id, code)`), so a global
  /// match would make one branch's import silently rewrite another's rooms.
  List<String> get naturalKeyColumns => switch (this) {
    branches => const ['code'],
    rooms => const ['branch_code', 'code'],
    users => const ['email'],
    itemCategories => const ['name'],
    items => const ['sku'],
    itemBatches => const ['item_sku', 'batch_no'],
  };

  /// How the natural key reads to a user, e.g. *"Kode cabang + kode ruangan"*.
  String get naturalKeyLabel => switch (this) {
    branches => 'Kode cabang',
    rooms => 'Kode cabang + kode ruangan',
    users => 'Email',
    itemCategories => 'Nama kategori',
    items => 'SKU',
    itemBatches => 'SKU barang + nomor batch',
  };

  /// Whether this entity carries an `is_active` column (§3.6).
  ///
  /// False for categories and batches, which have no such column in the schema.
  /// Their lifecycle is `deleted_at` — archived or live — and a column was
  /// deliberately **not** added just to make all six look alike: that would be a
  /// schema change to six months of existing rows in service of symmetry.
  bool get supportsArchiveColumn => switch (this) {
    branches || rooms || users || items => true,
    itemCategories || itemBatches => false,
  };

  /// The sentinel each natural-key column carries in the template's sample row
  /// (§3.7).
  ///
  /// Row 2 must be a *filled* example (G-M2) and must also not be importable by
  /// accident. A sentinel key solves both: the row is complete and readable, and
  /// the importer skips exactly the row whose key still says `__CONTOH_…__`. The
  /// moment a user types over it, it is data like any other.
  Map<String, String> get sampleSentinels => switch (this) {
    branches => const {'code': _contohKode},
    rooms => const {'branch_code': _contohKode, 'code': _contohKode},
    users => const {'email': _contohEmail},
    itemCategories => const {'name': _contohKategori},
    items => const {'sku': _contohSku},
    itemBatches => const {'item_sku': _contohSku, 'batch_no': _contohBatch},
  };

  /// The sentinel of the first natural-key column — what a test or a message
  /// names when it needs one token rather than the map.
  String get sampleSentinel => sampleSentinels[naturalKeyColumns.first]!;

  static const String _contohSku = '__CONTOH_SKU__';
  static const String _contohKode = '__CONTOH_KODE__';
  static const String _contohEmail = '__CONTOH_EMAIL__';
  static const String _contohKategori = '__CONTOH_KATEGORI__';
  static const String _contohBatch = '__CONTOH_BATCH__';

  static ImportEntity fromDbValue(String value) => values.firstWhere(
    (entity) => entity.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown ImportEntity'),
  );
}

/// The life of one import (§3.4, §10).
///
/// ```text
/// validated → committed
/// validated → discarded
/// ```
///
/// Both ends are final. There is no `committed → discarded`, because master rows
/// have already been written and an audit row that walked backwards would claim
/// they had not; and no `discarded → committed`, because the whole point of
/// discarding is that the operator looked at the preview and said no.
///
/// `validated` is written **after** every row has been checked and before any
/// master row is touched — the audit side effect §3.3 spells out, not a
/// master-data mutation.
enum ImportStatus {
  validated('validated'),
  committed('committed'),
  discarded('discarded');

  const ImportStatus(this.dbValue);

  final String dbValue;

  String get label => switch (this) {
    validated => 'Tervalidasi',
    committed => 'Diterapkan',
    discarded => 'Dibatalkan',
  };

  bool get isValidated => this == validated;

  bool get isCommitted => this == committed;

  bool get isDiscarded => this == discarded;

  /// Whether nothing may change this import again.
  bool get isFinal => this == committed || this == discarded;

  bool get canCommit => this == validated;

  bool get canDiscard => this == validated;

  static ImportStatus fromDbValue(String value) => values.firstWhere(
    (status) => status.dbValue == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unknown ImportStatus'),
  );
}
