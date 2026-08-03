/// What may be merged, what the server owns outright, and what may never be
/// touched — per entity, per state.
///
/// This file exists so that reconciliation is never a generic merge over
/// whatever JSON arrived. G-Y3 permits last-write-wins *per column* on non-final
/// documents; it does not permit a server payload to rewrite a document number,
/// a posting timestamp, a ledger row, or the natural key a whole workflow keys
/// off. An allowlist is the only way to say that precisely, and it has to be
/// stated per entity because the same column name means different things in
/// different tables.
library;

/// How a change to this entity is reconciled with local state.
enum SyncEntityClass {
  /// Master data. Mutable, non-final, and the only class that merges per column
  /// (G-Y3). Deletion is a soft delete; deactivation is `is_active = false`
  /// and is an ordinary field change (G-A4).
  master,

  /// A workflow document. Device-authoritative while `draft` and never pushed;
  /// server-authoritative from `submitted` onward (G-Y2). Never merged per
  /// column — the server decides the state machine.
  document,

  /// `stock_movements`. Append-only, never updated, never deleted, never merged
  /// (G-A1, G-Y5). A movement is applied by UUID or not at all.
  ledger,

  /// `stock_balances`. A cache position derived from the ledger; the server
  /// value replaces the local one outright.
  balance,
}

/// A child collection a document payload carries, and the key it arrives under.
///
/// The payload key is declared rather than inferred from position: a document
/// with two child collections would otherwise depend on their order in the
/// policy, and getting that wrong would write one collection's rows into the
/// other's table.
typedef SyncChildTable = ({String table, String foreignKey, String payloadKey});

/// Everything the pull path needs to know about one entity type.
final class SyncEntityPolicy {
  const SyncEntityPolicy({
    required this.entityType,
    required this.table,
    required this.entityClass,
    this.child,
    this.movementRefType,
    this.mergeableFields = const <String>{},
    this.immutableFields = const <String>{},
    this.finalStatuses = const <String>{},
    this.tombstonable = false,
    this.extraChildren = const <SyncChildTable>[],
  });

  final String entityType;
  final String table;
  final SyncEntityClass entityClass;
  final SyncChildTable? child;
  final List<SyncChildTable> extraChildren;

  /// `ref_doc_type` for the movements this document posts, or null when it posts
  /// nothing to the ledger.
  final String? movementRefType;

  /// Columns that take part in field-level last-write-wins. Must mirror
  /// `app_private.pull_mergeable_fields` on the server; the pgTAP suite pins the
  /// server half and `sync_entity_policy_test.dart` pins this half against it.
  final Set<String> mergeableFields;

  /// Columns that identify the row to the rest of the system. A difference here
  /// is never merged and never silently overwritten — it is a conflict.
  final Set<String> immutableFields;

  /// Statuses after which the server wins absolutely (G-Y2).
  final Set<String> finalStatuses;

  /// Whether a soft delete of this entity is replicated as a tombstone.
  final bool tombstonable;

  bool isFinalStatus(String? status) =>
      status != null && finalStatuses.contains(status);
}

abstract final class SyncEntityPolicies {
  /// Columns the server owns on every table. A client never writes these from a
  /// merge decision and never treats a difference in them as a user edit.
  static const serverControlledFields = <String>{
    'server_version',
    'server_updated_at',
    'server_received_at',
    'sync_status',
    'doc_number',
  };

  /// Columns present on every business table that are bookkeeping rather than
  /// content. `updated_at` is deliberately here: it is a device clock value, and
  /// G-Y3's "berdasarkan `updated_at`" is honoured through the server's
  /// per-field version rather than by trusting it.
  static const alwaysExcludedFields = <String>{
    'id',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  static const _byType = <String, SyncEntityPolicy>{
    'branch': SyncEntityPolicy(
      entityType: 'branch',
      table: 'branches',
      entityClass: SyncEntityClass.master,
      mergeableFields: {'name', 'address', 'is_active'},
      immutableFields: {'code'},
      // G-A4: a branch that carries transactions is deactivated, never deleted.
      tombstonable: false,
    ),
    'room': SyncEntityPolicy(
      entityType: 'room',
      table: 'rooms',
      entityClass: SyncEntityClass.master,
      mergeableFields: {'code', 'name', 'is_active'},
      immutableFields: {'branch_id'},
      tombstonable: false,
    ),
    'user': SyncEntityPolicy(
      entityType: 'user',
      table: 'users',
      entityClass: SyncEntityClass.master,
      mergeableFields: {'full_name', 'role', 'branch_id', 'is_active'},
      immutableFields: {'email'},
      // A domain user is a historical actor on every document ever posted. The
      // server refuses to delete one at all; replicating a deletion would strand
      // every audit row that names them.
      tombstonable: false,
    ),
    'category': SyncEntityPolicy(
      entityType: 'category',
      table: 'item_categories',
      entityClass: SyncEntityClass.master,
      mergeableFields: {'name'},
      tombstonable: true,
    ),
    'item': SyncEntityPolicy(
      entityType: 'item',
      table: 'items',
      entityClass: SyncEntityClass.master,
      mergeableFields: {
        'name',
        'category_id',
        'unit',
        'min_stock_room',
        'min_stock_branch',
        'expiry_alert_days',
        'is_active',
      },
      // `sku` is the natural import key (G-M4) and `has_expiry` decides whether
      // the item is batch-tracked at all — changing either would re-point
      // history at a different thing.
      immutableFields: {'sku', 'has_expiry'},
      tombstonable: false,
    ),
    'batch': SyncEntityPolicy(
      entityType: 'batch',
      table: 'item_batches',
      entityClass: SyncEntityClass.master,
      mergeableFields: {'expiry_date'},
      immutableFields: {'item_id', 'batch_no'},
      tombstonable: true,
    ),
    'stock_location': SyncEntityPolicy(
      entityType: 'stock_location',
      table: 'stock_locations',
      entityClass: SyncEntityClass.master,
      mergeableFields: {'name'},
      immutableFields: {'type', 'branch_id', 'room_id'},
      tombstonable: true,
    ),
    'stock_balance': SyncEntityPolicy(
      entityType: 'stock_balance',
      table: 'stock_balances',
      entityClass: SyncEntityClass.balance,
      immutableFields: {'location_id', 'item_id', 'batch_id'},
      tombstonable: false,
    ),
    'stock_movement': SyncEntityPolicy(
      entityType: 'stock_movement',
      table: 'stock_movements',
      entityClass: SyncEntityClass.ledger,
      tombstonable: false,
    ),
    'stock_opname': SyncEntityPolicy(
      entityType: 'stock_opname',
      table: 'stock_opnames',
      entityClass: SyncEntityClass.document,
      child: (
        table: 'stock_opname_lines',
        foreignKey: 'opname_id',
        payloadKey: 'lines',
      ),
      movementRefType: 'SO',
      finalStatuses: {'reviewed'},
      tombstonable: true,
    ),
    'purchase_request': SyncEntityPolicy(
      entityType: 'purchase_request',
      table: 'purchase_requests',
      entityClass: SyncEntityClass.document,
      child: (
        table: 'purchase_request_lines',
        foreignKey: 'pr_id',
        payloadKey: 'lines',
      ),
      extraChildren: [
        (
          table: 'purchase_request_opnames',
          foreignKey: 'pr_id',
          payloadKey: 'opname_links',
        ),
      ],
      finalStatuses: {'rejected', 'cancelled', 'completed'},
      tombstonable: true,
    ),
    'delivery_order': SyncEntityPolicy(
      entityType: 'delivery_order',
      table: 'delivery_orders',
      entityClass: SyncEntityClass.document,
      child: (
        table: 'delivery_order_lines',
        foreignKey: 'do_id',
        payloadKey: 'lines',
      ),
      movementRefType: 'DO',
      finalStatuses: {'shipped', 'received'},
      tombstonable: true,
    ),
    'good_receipt': SyncEntityPolicy(
      entityType: 'good_receipt',
      table: 'good_receipts',
      entityClass: SyncEntityClass.document,
      child: (
        table: 'good_receipt_lines',
        foreignKey: 'gr_id',
        payloadKey: 'lines',
      ),
      movementRefType: 'GR',
      finalStatuses: {'posted'},
      tombstonable: true,
    ),
    'distribution': SyncEntityPolicy(
      entityType: 'distribution',
      table: 'distributions',
      entityClass: SyncEntityClass.document,
      child: (
        table: 'distribution_lines',
        foreignKey: 'distribution_id',
        payloadKey: 'lines',
      ),
      movementRefType: 'DIST',
      finalStatuses: {'posted'},
      tombstonable: true,
    ),
    'disposal': SyncEntityPolicy(
      entityType: 'disposal',
      table: 'disposals',
      entityClass: SyncEntityClass.document,
      child: (
        table: 'disposal_lines',
        foreignKey: 'disposal_id',
        payloadKey: 'lines',
      ),
      movementRefType: 'DSP',
      finalStatuses: {'posted'},
      tombstonable: true,
    ),
    'consumption': SyncEntityPolicy(
      entityType: 'consumption',
      table: 'consumptions',
      entityClass: SyncEntityClass.document,
      child: (
        table: 'consumption_lines',
        foreignKey: 'consumption_id',
        payloadKey: 'lines',
      ),
      movementRefType: 'CONS',
      finalStatuses: {'posted'},
      tombstonable: true,
    ),
    'goods_return': SyncEntityPolicy(
      entityType: 'goods_return',
      table: 'goods_returns',
      entityClass: SyncEntityClass.document,
      child: (
        table: 'goods_return_lines',
        foreignKey: 'goods_return_id',
        payloadKey: 'lines',
      ),
      movementRefType: 'RET',
      finalStatuses: {'shipped', 'received'},
      tombstonable: true,
    ),
  };

  static SyncEntityPolicy? forType(String entityType) => _byType[entityType];

  static Iterable<SyncEntityPolicy> get all => _byType.values;

  static Iterable<String> get pullableTypes => _byType.keys;

  /// Columns that must never be written from a merge decision, whatever the
  /// entity. Kept as one query so no caller has to remember all three sources.
  static bool isReservedField(String field) =>
      serverControlledFields.contains(field) ||
      alwaysExcludedFields.contains(field);
}
