import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/consumption_tables.dart';
import '../tables/delivery_tables.dart';
import '../tables/disposal_tables.dart';
import '../tables/distribution_tables.dart';
import '../tables/good_receipt_tables.dart';
import '../tables/goods_return_tables.dart';
import '../tables/inventory_tables.dart';
import '../tables/master_tables.dart';
import '../tables/opname_tables.dart';
import '../tables/purchase_request_tables.dart';
import '../tables/reporting_tables.dart';
// The row shapes below are declared in the domain, not here: the reporting
// repository *contract* returns them, and a `db/daos/` import in a domain file is
// the layering the architecture tests forbid. See the note in that file.
import '../../../features/reports/domain/models/report_raw_rows.dart';

export '../../../features/reports/domain/models/report_raw_rows.dart';

part 'reporting_dao.g.dart';

/// Read access for the reporting module, plus the single writer of `export_logs`.
///
/// ### Four rules this DAO is built around
///
/// **1. No `stock_balances`, ever.** G-L4 says report figures come from the ledger,
/// and the reason is auditability: a cached balance is a number nobody can trace to
/// an event. There is deliberately no method here that reads that table, and an
/// architecture test asserts the string does not appear in this file — so the rule
/// survives the next person who "just needs a quick total".
///
/// **2. Timestamps are never compared or ordered in SQL.** `created_at` is
/// ISO-8601 TEXT (see `build.yaml`), and SQLite would compare it character by
/// character — the exact trap schema v4 removed from `stock_opnames`. Every method
/// below therefore filters only on things SQL can decide without ambiguity (ids,
/// branch, location, movement type, status) and hands back *every* matching row.
/// The period window is applied by [ReportPeriodPolicy] on parsed UTC `DateTime`s,
/// one layer up. This costs some rows on the way out and buys a boundary that is
/// right on both sides of midnight GMT+8.
///
/// **3. Master data is joined *out*, not *in*.** No query here inner-joins `items`,
/// `item_batches`, `users` or `stock_locations` to decorate a row, because an
/// inner join silently drops a movement whose item was archived — and a stock
/// report that quietly loses rows is worse than one that says *"data historis tidak
/// tersedia"*. Ids come back raw; the repository resolves labels through the
/// `historical…` lookups below, which filter on **nothing**: not `deleted_at`, not
/// `is_active`.
///
/// **4. Nothing here is unscoped.** Every method takes the scope as a required
/// argument. There is no `allMovements()` and no `allDocuments()` for a screen to
/// reach for — the scope is decided by [ReportAccessPolicy] against a re-read actor
/// and carried into the SQL, so a report cannot be widened by a caller that forgot
/// a filter.
@DriftAccessor(
  tables: [
    StockMovements,
    Items,
    ItemCategories,
    ItemBatches,
    StockLocations,
    Branches,
    Rooms,
    Users,
    StockOpnames,
    StockOpnameLines,
    PurchaseRequests,
    PurchaseRequestLines,
    DeliveryOrders,
    DeliveryOrderLines,
    GoodReceipts,
    GoodReceiptLines,
    Distributions,
    DistributionLines,
    Disposals,
    DisposalLines,
    Consumptions,
    ConsumptionLines,
    GoodsReturns,
    GoodsReturnLines,
    ExportLogs,
  ],
)
class ReportingDao extends DatabaseAccessor<AppDatabase>
    with _$ReportingDaoMixin {
  ReportingDao(super.db);

  // --- ledger ---------------------------------------------------------------

  /// `id IN (?, ?, …)` written by hand, because the number of placeholders varies.
  ///
  /// Values are always bound as [Variable]s — never interpolated — so an id that
  /// somehow carried a quote cannot change the shape of the statement.
  String _placeholders(int count) => List.filled(count, '?').join(', ');

  /// The **ids** of every ledger row touching [locationIds], with no join at all.
  ///
  /// Exists so [movementsForScope] can be checked against it: if the detailed read
  /// returns fewer rows than this one, some join dropped a movement, and a stock
  /// report that lost a movement is a stock report whose totals are wrong. The
  /// repository compares the two sets and fails loudly rather than reporting a
  /// smaller number (§35).
  Future<Set<String>> movementIdsForScope({
    required Set<String> locationIds,
    String? itemId,
    String? categoryId,
  }) async {
    if (locationIds.isEmpty) return <String>{};
    final buffer = StringBuffer('SELECT id FROM stock_movements WHERE ');
    final variables = <Variable<Object>>[];
    _writeScopePredicate(
      buffer,
      variables,
      locationIds: locationIds,
      itemId: itemId,
      categoryId: categoryId,
    );
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {stockMovements, items},
    ).get();
    return rows.map((row) => row.read<String>('id')).toSet();
  }

  /// Every ledger row touching one of [locationIds], unfiltered in time.
  ///
  /// The caller narrows to a period afterwards; see rule 2 in the class note. An
  /// opening balance needs everything *before* the period anyway, so a SQL window
  /// would have to be widened to "everything" for the stock card regardless.
  Future<List<ReportMovementRawRow>> movementsForScope({
    required Set<String> locationIds,
    String? itemId,
    String? categoryId,
  }) async {
    if (locationIds.isEmpty) return const <ReportMovementRawRow>[];
    final buffer = StringBuffer(
      'SELECT id, created_at, updated_at, sync_status, item_id, batch_id, '
      'from_location_id, to_location_id, qty, movement_type, ref_doc_type, '
      'ref_doc_id, actor_user_id, note, reversal_of_movement_id '
      'FROM stock_movements WHERE ',
    );
    final variables = <Variable<Object>>[];
    _writeScopePredicate(
      buffer,
      variables,
      locationIds: locationIds,
      itemId: itemId,
      categoryId: categoryId,
    );
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {stockMovements, items},
    ).get();
    return rows.map(_readMovement).toList(growable: false);
  }

  /// Every ledger row of one movement type, across every location.
  ///
  /// The recap counterpart of [movementsForScope]: a `rekap_distribusi` needs the
  /// `distribution` movements of the documents it lists, and those touch two
  /// locations each — enumerating the locations first would be a second, weaker way
  /// of asking the same question. Scoped by `ref_doc_id` instead, which is exactly
  /// the set of documents the caller already resolved and is already allowed to see.
  Future<List<ReportMovementRawRow>> movementsForDocuments({
    required String refDocType,
    required Set<String> refDocIds,
  }) async {
    if (refDocIds.isEmpty) return const <ReportMovementRawRow>[];
    final rows = await customSelect(
      'SELECT id, created_at, updated_at, sync_status, item_id, batch_id, '
      'from_location_id, to_location_id, qty, movement_type, ref_doc_type, '
      'ref_doc_id, actor_user_id, note, reversal_of_movement_id '
      'FROM stock_movements WHERE ref_doc_type = ? '
      'AND ref_doc_id IN (${_placeholders(refDocIds.length)});',
      variables: [
        Variable<String>(refDocType),
        ...refDocIds.map(Variable<String>.new),
      ],
      readsFrom: {stockMovements},
    ).get();
    return rows.map(_readMovement).toList(growable: false);
  }

  void _writeScopePredicate(
    StringBuffer buffer,
    List<Variable<Object>> variables, {
    required Set<String> locationIds,
    String? itemId,
    String? categoryId,
  }) {
    final placeholders = _placeholders(locationIds.length);
    buffer.write(
      '(from_location_id IN ($placeholders) '
      'OR to_location_id IN ($placeholders))',
    );
    variables
      ..addAll(locationIds.map(Variable<String>.new))
      ..addAll(locationIds.map(Variable<String>.new));
    if (itemId != null) {
      buffer.write(' AND item_id = ?');
      variables.add(Variable<String>(itemId));
    }
    if (categoryId != null) {
      // A subquery rather than a join: a join to `items` would decide which
      // movements exist, and an archived item would take its ledger rows with it.
      // `IN (SELECT …)` narrows without ever removing a row the predicate matches.
      buffer.write(
        ' AND item_id IN (SELECT id FROM items WHERE category_id = ?)',
      );
      variables.add(Variable<String>(categoryId));
    }
  }

  ReportMovementRawRow _readMovement(QueryRow row) => ReportMovementRawRow(
    id: row.read<String>('id'),
    createdAtUtc: row.read<DateTime>('created_at'),
    updatedAtUtc: row.read<DateTime>('updated_at'),
    syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
    itemId: row.read<String>('item_id'),
    batchId: row.read<String?>('batch_id'),
    fromLocationId: row.read<String?>('from_location_id'),
    toLocationId: row.read<String?>('to_location_id'),
    qtyMilliUnits: row.read<int>('qty'),
    movementType: StockMovementType.fromDbValue(
      row.read<String>('movement_type'),
    ),
    refDocType: row.read<String?>('ref_doc_type'),
    refDocId: row.read<String?>('ref_doc_id'),
    actorUserId: row.read<String>('actor_user_id'),
    note: row.read<String?>('note'),
    reversalOfMovementId: row.read<String?>('reversal_of_movement_id'),
  );

  // --- historical master lookups --------------------------------------------
  //
  // Every one of these filters on **nothing**: not `deleted_at`, not `is_active`.
  // A report of what happened has to be able to name the item that was moved even
  // after an administrator deactivated it, and dropping the row would be dropping
  // the quantity with it (§51).

  Future<List<Item>> historicalItems(Set<String> ids) =>
      _byIds(items, ids, (table) => table.id);

  Future<List<ItemCategory>> historicalCategories(Set<String> ids) =>
      _byIds(itemCategories, ids, (table) => table.id);

  Future<List<ItemBatch>> historicalBatches(Set<String> ids) =>
      _byIds(itemBatches, ids, (table) => table.id);

  Future<List<StockLocation>> historicalLocations(Set<String> ids) =>
      _byIds(stockLocations, ids, (table) => table.id);

  Future<List<Branch>> historicalBranches(Set<String> ids) =>
      _byIds(branches, ids, (table) => table.id);

  Future<List<Room>> historicalRooms(Set<String> ids) =>
      _byIds(rooms, ids, (table) => table.id);

  Future<List<AppUser>> historicalUsers(Set<String> ids) =>
      _byIds(users, ids, (table) => table.id);

  Future<List<D>> _byIds<T extends Table, D>(
    TableInfo<T, D> table,
    Set<String> ids,
    Expression<String> Function(T) idOf,
  ) async {
    if (ids.isEmpty) return <D>[];
    return (select(table)..where((row) => idOf(row).isIn(ids))).get();
  }

  /// Every stock location of one branch — its store and its rooms — archived rows
  /// included, so a `branch_all` report still names a room somebody tidied away.
  Future<List<StockLocation>> locationsOfBranch(String branchId) => (select(
    stockLocations,
  )..where((row) => row.branchId.equals(branchId))).get();

  /// Every stock location there is. Only reachable behind an `all_locations`
  /// scope, which [ReportAccessPolicy] grants to Super Admin alone.
  Future<List<StockLocation>> allLocations() => select(stockLocations).get();

  /// Every location of one type — how the Warehouse scope resolves *"Warehouse
  /// Pusat"* without a screen naming an id.
  Future<List<StockLocation>> locationsOfType(StockLocationType type) =>
      (select(
        stockLocations,
      )..where((row) => row.type.equalsValue(type))).get();

  /// Document numbers for a set of ledger references, keyed by `ref_doc_id`.
  ///
  /// The Kartu Stok's *Nomor Dokumen* column. The ledger stores a type code and an
  /// id and no number (§2.2), so resolving one means looking in the table that code
  /// names — which is why this is a `switch` over [RefDocType] rather than a join:
  /// a stock card row can come from any of eight document types, and joining all
  /// eight to fill one column would be seven outer joins per row.
  ///
  /// **No `deleted_at` filter.** A movement whose document was soft-deleted still
  /// moved stock, and a card that showed *"Referensi tidak tersedia"* for a document
  /// that is right there would be hiding evidence (§51).
  ///
  /// Codes this build does not recognise return no entries at all rather than
  /// throwing: a row written by a later version, or by the sync backend, must render
  /// with a fallback rather than crash a screen an auditor is reading.
  Future<Map<String, String>> documentNumbers({
    required String refDocType,
    required Set<String> refDocIds,
  }) async {
    if (refDocIds.isEmpty) return const <String, String>{};
    final table = switch (refDocType) {
      RefDocType.stockOpname => 'stock_opnames',
      RefDocType.purchaseRequest => 'purchase_requests',
      RefDocType.deliveryOrder => 'delivery_orders',
      RefDocType.goodReceipt => 'good_receipts',
      RefDocType.distribution => 'distributions',
      RefDocType.disposal => 'disposals',
      RefDocType.consumption => 'consumptions',
      RefDocType.goodsReturn => 'goods_returns',
      _ => null,
    };
    if (table == null) return const <String, String>{};

    final rows = await customSelect(
      'SELECT id, doc_number FROM $table '
      'WHERE id IN (${_placeholders(refDocIds.length)});',
      variables: refDocIds.map(Variable<String>.new).toList(growable: false),
    ).get();
    return {
      for (final row in rows)
        row.read<String>('id'): row.read<String>('doc_number'),
    };
  }

  // --- document recaps ------------------------------------------------------
  //
  // Each returns one row per document *line*, with the header repeated. A document
  // with no lines still comes back once, with every line column NULL — that is what
  // the LEFT JOIN buys, and it matters because a `preparing` Delivery Order with no
  // allocations yet is a real document a status filter may legitimately ask for.
  //
  // Line joins are LEFT and document-to-document joins are INNER, and the split is
  // deliberate: a Good Receipt without its Delivery Order is corrupt data, while a
  // Good Receipt without lines is an ordinary state.

  /// [roomId] narrows to one room — the scope a Perawat runs this recap at (§16).
  /// `null` means every room the branch predicate already allowed.
  Future<List<OpnameRecapRawRow>> opnameRecap({
    String? branchId,
    String? countedBy,
    String? roomId,
  }) async {
    final buffer = StringBuffer(
      'SELECT o.id AS opname_id, o.doc_number, o.branch_id, o.room_id, '
      'o.period_year, o.period_week, o.status, o.counted_by, o.reviewed_by, '
      'o.created_at, o.updated_at, o.submitted_at, o.reviewed_at, '
      'o.sync_status, l.id AS line_id, l.item_id, l.batch_id, l.system_qty, '
      'l.counted_qty, l.difference, l.note AS line_note '
      'FROM stock_opnames o '
      'LEFT JOIN stock_opname_lines l '
      'ON l.opname_id = o.id AND l.deleted_at IS NULL '
      'WHERE o.deleted_at IS NULL',
    );
    final variables = <Variable<Object>>[];
    if (branchId != null) {
      buffer.write(' AND o.branch_id = ?');
      variables.add(Variable<String>(branchId));
    }
    if (countedBy != null) {
      buffer.write(' AND o.counted_by = ?');
      variables.add(Variable<String>(countedBy));
    }
    if (roomId != null) {
      buffer.write(' AND o.room_id = ?');
      variables.add(Variable<String>(roomId));
    }
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {stockOpnames, stockOpnameLines},
    ).get();
    return rows
        .map(
          (row) => OpnameRecapRawRow(
            opnameId: row.read<String>('opname_id'),
            docNumber: row.read<String>('doc_number'),
            branchId: row.read<String>('branch_id'),
            roomId: row.read<String>('room_id'),
            periodYear: row.read<int>('period_year'),
            periodWeek: row.read<int>('period_week'),
            status: row.read<String>('status'),
            countedBy: row.read<String>('counted_by'),
            reviewedBy: row.read<String?>('reviewed_by'),
            createdAtUtc: row.read<DateTime>('created_at'),
            updatedAtUtc: row.read<DateTime>('updated_at'),
            submittedAtUtc: row.read<DateTime?>('submitted_at'),
            reviewedAtUtc: row.read<DateTime?>('reviewed_at'),
            syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
            lineId: row.read<String?>('line_id'),
            itemId: row.read<String?>('item_id'),
            batchId: row.read<String?>('batch_id'),
            systemQtyMilliUnits: row.read<int?>('system_qty'),
            countedQtyMilliUnits: row.read<int?>('counted_qty'),
            differenceMilliUnits: row.read<int?>('difference'),
            lineNote: row.read<String?>('line_note'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<PurchaseRequestRecapRawRow>> purchaseRequestRecap({
    String? branchId,
  }) async {
    final buffer = StringBuffer(
      'SELECT p.id AS pr_id, p.doc_number, p.branch_id, p.status, '
      'p.requested_by, p.needed_date, p.note AS header_note, p.created_at, '
      'p.updated_at, p.submitted_at, p.processing_at, p.sync_status, '
      'l.id AS line_id, l.item_id, l.suggested_qty, l.requested_qty, '
      'l.note AS line_note '
      'FROM purchase_requests p '
      'LEFT JOIN purchase_request_lines l '
      'ON l.pr_id = p.id AND l.deleted_at IS NULL '
      'WHERE p.deleted_at IS NULL',
    );
    final variables = <Variable<Object>>[];
    if (branchId != null) {
      buffer.write(' AND p.branch_id = ?');
      variables.add(Variable<String>(branchId));
    }
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {purchaseRequests, purchaseRequestLines},
    ).get();
    return rows
        .map(
          (row) => PurchaseRequestRecapRawRow(
            prId: row.read<String>('pr_id'),
            docNumber: row.read<String>('doc_number'),
            branchId: row.read<String>('branch_id'),
            status: row.read<String>('status'),
            requestedBy: row.read<String>('requested_by'),
            neededDate: row.read<DateTime?>('needed_date'),
            headerNote: row.read<String?>('header_note'),
            createdAtUtc: row.read<DateTime>('created_at'),
            updatedAtUtc: row.read<DateTime>('updated_at'),
            submittedAtUtc: row.read<DateTime?>('submitted_at'),
            processingAtUtc: row.read<DateTime?>('processing_at'),
            syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
            lineId: row.read<String?>('line_id'),
            itemId: row.read<String?>('item_id'),
            suggestedQtyMilliUnits: row.read<int?>('suggested_qty'),
            requestedQtyMilliUnits: row.read<int?>('requested_qty'),
            lineNote: row.read<String?>('line_note'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<DeliveryOrderRecapRawRow>> deliveryOrderRecap({
    String? branchId,
  }) async {
    final buffer = StringBuffer(
      'SELECT d.id AS do_id, d.doc_number, d.pr_id, '
      'p.doc_number AS pr_doc_number, p.branch_id, d.status, d.prepared_by, '
      'd.shipped_by, d.created_at, d.updated_at, d.shipped_at, '
      'd.note AS header_note, d.sync_status, l.id AS line_id, l.pr_line_id, '
      'l.item_id, l.batch_id, l.shipped_qty, l.fefo_override_reason, '
      'l.near_expiry_confirmed, l.near_expiry_note '
      'FROM delivery_orders d '
      'INNER JOIN purchase_requests p ON p.id = d.pr_id '
      'LEFT JOIN delivery_order_lines l '
      'ON l.do_id = d.id AND l.deleted_at IS NULL '
      'WHERE d.deleted_at IS NULL',
    );
    final variables = <Variable<Object>>[];
    if (branchId != null) {
      buffer.write(' AND p.branch_id = ?');
      variables.add(Variable<String>(branchId));
    }
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {deliveryOrders, deliveryOrderLines, purchaseRequests},
    ).get();
    return rows
        .map(
          (row) => DeliveryOrderRecapRawRow(
            doId: row.read<String>('do_id'),
            docNumber: row.read<String>('doc_number'),
            prId: row.read<String>('pr_id'),
            prDocNumber: row.read<String>('pr_doc_number'),
            branchId: row.read<String>('branch_id'),
            status: row.read<String>('status'),
            preparedBy: row.read<String>('prepared_by'),
            shippedBy: row.read<String?>('shipped_by'),
            createdAtUtc: row.read<DateTime>('created_at'),
            updatedAtUtc: row.read<DateTime>('updated_at'),
            shippedAtUtc: row.read<DateTime?>('shipped_at'),
            headerNote: row.read<String?>('header_note'),
            syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
            lineId: row.read<String?>('line_id'),
            prLineId: row.read<String?>('pr_line_id'),
            itemId: row.read<String?>('item_id'),
            batchId: row.read<String?>('batch_id'),
            shippedQtyMilliUnits: row.read<int?>('shipped_qty'),
            fefoOverrideReason: row.read<String?>('fefo_override_reason'),
            nearExpiryConfirmed: row.read<bool?>('near_expiry_confirmed'),
            nearExpiryNote: row.read<String?>('near_expiry_note'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<GoodReceiptRecapRawRow>> goodReceiptRecap({
    String? branchId,
  }) async {
    final buffer = StringBuffer(
      'SELECT g.id AS gr_id, g.doc_number, g.do_id, '
      'd.doc_number AS do_doc_number, d.pr_id, '
      'p.doc_number AS pr_doc_number, p.branch_id, g.status, g.received_by, '
      'g.created_at, g.updated_at, g.posted_at, g.sync_status, '
      'r.doc_number AS return_doc_number, r.status AS return_status, '
      'l.id AS line_id, l.do_line_id, l.item_id, l.batch_id, l.shipped_qty, '
      'l.received_qty, l.line_status, l.reject_reason '
      'FROM good_receipts g '
      'INNER JOIN delivery_orders d ON d.id = g.do_id '
      'INNER JOIN purchase_requests p ON p.id = d.pr_id '
      // `deleted_at IS NULL` like every other join here: the unique index on
      // `gr_id` is unconditional, so a soft-deleted Retur keeps its slot forever —
      // and a receipt whose return was withdrawn must stop naming it (G-A5).
      'LEFT JOIN goods_returns r ON r.gr_id = g.id AND r.deleted_at IS NULL '
      'LEFT JOIN good_receipt_lines l '
      'ON l.gr_id = g.id AND l.deleted_at IS NULL '
      'WHERE g.deleted_at IS NULL',
    );
    final variables = <Variable<Object>>[];
    if (branchId != null) {
      buffer.write(' AND p.branch_id = ?');
      variables.add(Variable<String>(branchId));
    }
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {
        goodReceipts,
        goodReceiptLines,
        deliveryOrders,
        purchaseRequests,
        goodsReturns,
      },
    ).get();
    return rows
        .map(
          (row) => GoodReceiptRecapRawRow(
            grId: row.read<String>('gr_id'),
            docNumber: row.read<String>('doc_number'),
            doId: row.read<String>('do_id'),
            doDocNumber: row.read<String>('do_doc_number'),
            prId: row.read<String>('pr_id'),
            prDocNumber: row.read<String>('pr_doc_number'),
            branchId: row.read<String>('branch_id'),
            status: row.read<String>('status'),
            receivedBy: row.read<String>('received_by'),
            createdAtUtc: row.read<DateTime>('created_at'),
            updatedAtUtc: row.read<DateTime>('updated_at'),
            postedAtUtc: row.read<DateTime?>('posted_at'),
            syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
            returnDocNumber: row.read<String?>('return_doc_number'),
            returnStatus: row.read<String?>('return_status'),
            lineId: row.read<String?>('line_id'),
            doLineId: row.read<String?>('do_line_id'),
            itemId: row.read<String?>('item_id'),
            batchId: row.read<String?>('batch_id'),
            shippedQtyMilliUnits: row.read<int?>('shipped_qty'),
            receivedQtyMilliUnits: row.read<int?>('received_qty'),
            lineStatus: row.read<String?>('line_status'),
            rejectReason: row.read<String?>('reject_reason'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<DistributionRecapRawRow>> distributionRecap({
    String? branchId,
  }) async {
    final buffer = StringBuffer(
      'SELECT d.id AS distribution_id, d.doc_number, d.branch_id, d.status, '
      'd.distributed_by, d.created_at, d.updated_at, d.posted_at, '
      'd.note AS header_note, d.sync_status, l.id AS line_id, l.room_id, '
      'l.item_id, l.batch_id, l.qty, l.fefo_override_reason '
      'FROM distributions d '
      'LEFT JOIN distribution_lines l '
      'ON l.distribution_id = d.id AND l.deleted_at IS NULL '
      'WHERE d.deleted_at IS NULL',
    );
    final variables = <Variable<Object>>[];
    if (branchId != null) {
      buffer.write(' AND d.branch_id = ?');
      variables.add(Variable<String>(branchId));
    }
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {distributions, distributionLines},
    ).get();
    return rows
        .map(
          (row) => DistributionRecapRawRow(
            distributionId: row.read<String>('distribution_id'),
            docNumber: row.read<String>('doc_number'),
            branchId: row.read<String>('branch_id'),
            status: row.read<String>('status'),
            distributedBy: row.read<String>('distributed_by'),
            createdAtUtc: row.read<DateTime>('created_at'),
            updatedAtUtc: row.read<DateTime>('updated_at'),
            postedAtUtc: row.read<DateTime?>('posted_at'),
            headerNote: row.read<String?>('header_note'),
            syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
            lineId: row.read<String?>('line_id'),
            roomId: row.read<String?>('room_id'),
            itemId: row.read<String?>('item_id'),
            batchId: row.read<String?>('batch_id'),
            qtyMilliUnits: row.read<int?>('qty'),
            fefoOverrideReason: row.read<String?>('fefo_override_reason'),
          ),
        )
        .toList(growable: false);
  }

  /// [roomId] narrows to one room, as [opnameRecap] does and for the same reason.
  Future<List<ConsumptionRecapRawRow>> consumptionRecap({
    String? branchId,
    String? createdBy,
    String? roomId,
  }) async {
    final buffer = StringBuffer(
      'SELECT c.id AS consumption_id, c.doc_number, c.branch_id, c.room_id, '
      'c.status, c.created_by, c.posted_by, c.created_at, c.updated_at, '
      'c.posted_at, c.note AS header_note, c.sync_status, l.id AS line_id, '
      'l.item_id, l.batch_id, l.qty, l.note AS line_note '
      'FROM consumptions c '
      'LEFT JOIN consumption_lines l '
      'ON l.consumption_id = c.id AND l.deleted_at IS NULL '
      'WHERE c.deleted_at IS NULL',
    );
    final variables = <Variable<Object>>[];
    if (branchId != null) {
      buffer.write(' AND c.branch_id = ?');
      variables.add(Variable<String>(branchId));
    }
    if (createdBy != null) {
      buffer.write(' AND c.created_by = ?');
      variables.add(Variable<String>(createdBy));
    }
    if (roomId != null) {
      buffer.write(' AND c.room_id = ?');
      variables.add(Variable<String>(roomId));
    }
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {consumptions, consumptionLines},
    ).get();
    return rows
        .map(
          (row) => ConsumptionRecapRawRow(
            consumptionId: row.read<String>('consumption_id'),
            docNumber: row.read<String>('doc_number'),
            branchId: row.read<String>('branch_id'),
            roomId: row.read<String>('room_id'),
            status: row.read<String>('status'),
            createdBy: row.read<String>('created_by'),
            postedBy: row.read<String?>('posted_by'),
            createdAtUtc: row.read<DateTime>('created_at'),
            updatedAtUtc: row.read<DateTime>('updated_at'),
            postedAtUtc: row.read<DateTime?>('posted_at'),
            headerNote: row.read<String?>('header_note'),
            syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
            lineId: row.read<String?>('line_id'),
            itemId: row.read<String?>('item_id'),
            batchId: row.read<String?>('batch_id'),
            qtyMilliUnits: row.read<int?>('qty'),
            lineNote: row.read<String?>('line_note'),
          ),
        )
        .toList(growable: false);
  }

  /// Pemusnahan recap, scoped by **source location** rather than by branch.
  ///
  /// `disposals` carries no `branch_id`: its scope is the location the stock left
  /// (§30), which may be Warehouse Pusat, a Gudang Cabang or a room. Passing the
  /// resolved location set is therefore the only way to scope this recap that does
  /// not restate the location→branch mapping inside the SQL.
  Future<List<DisposalRecapRawRow>> disposalRecap({
    Set<String>? sourceLocationIds,
  }) async {
    if (sourceLocationIds != null && sourceLocationIds.isEmpty) {
      return const <DisposalRecapRawRow>[];
    }
    final buffer = StringBuffer(
      'SELECT d.id AS disposal_id, d.doc_number, d.source_location_id, '
      'd.status, d.created_by, d.posted_by, d.reason, d.created_at, '
      'd.updated_at, d.posted_at, d.sync_status, l.id AS line_id, l.item_id, '
      'l.batch_id, l.qty, l.note AS line_note '
      'FROM disposals d '
      'LEFT JOIN disposal_lines l '
      'ON l.disposal_id = d.id AND l.deleted_at IS NULL '
      'WHERE d.deleted_at IS NULL',
    );
    final variables = <Variable<Object>>[];
    if (sourceLocationIds != null) {
      buffer.write(
        ' AND d.source_location_id IN '
        '(${_placeholders(sourceLocationIds.length)})',
      );
      variables.addAll(sourceLocationIds.map(Variable<String>.new));
    }
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {disposals, disposalLines},
    ).get();
    return rows
        .map(
          (row) => DisposalRecapRawRow(
            disposalId: row.read<String>('disposal_id'),
            docNumber: row.read<String>('doc_number'),
            sourceLocationId: row.read<String>('source_location_id'),
            status: row.read<String>('status'),
            createdBy: row.read<String>('created_by'),
            postedBy: row.read<String?>('posted_by'),
            reason: row.read<String>('reason'),
            createdAtUtc: row.read<DateTime>('created_at'),
            updatedAtUtc: row.read<DateTime>('updated_at'),
            postedAtUtc: row.read<DateTime?>('posted_at'),
            syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
            lineId: row.read<String?>('line_id'),
            itemId: row.read<String?>('item_id'),
            batchId: row.read<String?>('batch_id'),
            qtyMilliUnits: row.read<int?>('qty'),
            lineNote: row.read<String?>('line_note'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<GoodsReturnRecapRawRow>> goodsReturnRecap({
    String? branchId,
  }) async {
    final buffer = StringBuffer(
      'SELECT r.id AS goods_return_id, r.doc_number, r.gr_id, '
      'g.doc_number AS gr_doc_number, d.doc_number AS do_doc_number, '
      'p.doc_number AS pr_doc_number, r.branch_id, r.status, r.created_by, '
      'r.shipped_by, r.received_by, r.created_at, r.updated_at, r.shipped_at, '
      'r.received_at, r.note AS branch_note, r.warehouse_note, r.sync_status, '
      'l.id AS line_id, l.item_id, l.batch_id, l.qty, '
      'l.reject_reason_snapshot '
      'FROM goods_returns r '
      'INNER JOIN good_receipts g ON g.id = r.gr_id '
      'INNER JOIN delivery_orders d ON d.id = g.do_id '
      'INNER JOIN purchase_requests p ON p.id = d.pr_id '
      'LEFT JOIN goods_return_lines l '
      'ON l.goods_return_id = r.id AND l.deleted_at IS NULL '
      'WHERE r.deleted_at IS NULL',
    );
    final variables = <Variable<Object>>[];
    if (branchId != null) {
      buffer.write(' AND r.branch_id = ?');
      variables.add(Variable<String>(branchId));
    }
    final rows = await customSelect(
      '$buffer;',
      variables: variables,
      readsFrom: {
        goodsReturns,
        goodsReturnLines,
        goodReceipts,
        deliveryOrders,
        purchaseRequests,
      },
    ).get();
    return rows
        .map(
          (row) => GoodsReturnRecapRawRow(
            goodsReturnId: row.read<String>('goods_return_id'),
            docNumber: row.read<String>('doc_number'),
            grId: row.read<String>('gr_id'),
            grDocNumber: row.read<String>('gr_doc_number'),
            doDocNumber: row.read<String>('do_doc_number'),
            prDocNumber: row.read<String>('pr_doc_number'),
            branchId: row.read<String>('branch_id'),
            status: row.read<String>('status'),
            createdBy: row.read<String>('created_by'),
            shippedBy: row.read<String?>('shipped_by'),
            receivedBy: row.read<String?>('received_by'),
            createdAtUtc: row.read<DateTime>('created_at'),
            updatedAtUtc: row.read<DateTime>('updated_at'),
            shippedAtUtc: row.read<DateTime?>('shipped_at'),
            receivedAtUtc: row.read<DateTime?>('received_at'),
            branchNote: row.read<String?>('branch_note'),
            warehouseNote: row.read<String?>('warehouse_note'),
            syncStatus: SyncStatus.fromDbValue(row.read<String>('sync_status')),
            lineId: row.read<String?>('line_id'),
            itemId: row.read<String?>('item_id'),
            batchId: row.read<String?>('batch_id'),
            qtyMilliUnits: row.read<int?>('qty'),
            rejectReasonSnapshot: row.read<String?>('reject_reason_snapshot'),
          ),
        )
        .toList(growable: false);
  }

  // --- export audit ---------------------------------------------------------
  //
  // One writer, and it inserts. There is deliberately no `update(exportLogs)`, no
  // `delete(exportLogs)` and no soft-delete helper anywhere in this class: an audit
  // trail somebody can edit is not one, and an architecture test asserts those
  // strings never appear in this file (§42).

  /// Records one successfully written file. The only write path into `export_logs`.
  Future<ExportLogRow> insertExportLog(ExportLogsCompanion log) =>
      into(exportLogs).insertReturning(log);

  /// Every export log there is, unordered.
  ///
  /// Unordered on purpose: `created_at` is TEXT, so `ORDER BY created_at DESC`
  /// would be a lexical sort (class note, rule 2). The repository sorts the parsed
  /// `DateTime`s instead.
  ///
  /// Unfiltered on `deleted_at` for the reason the table note gives: nothing writes
  /// that column, and a "live rows only" predicate would let a hand-written UPDATE
  /// hide an export from its own audit.
  Stream<List<ExportLogRow>> watchExportLogs() => select(exportLogs).watch();

  /// The same rows, read once — what the dashboard counters fold (§49).
  Future<List<ExportLogRow>> allExportLogs() => select(exportLogs).get();

  /// The logs one person produced — how the branch dashboard shows *"ekspor
  /// terbaru"* without handing a branch head everybody else's.
  Future<List<ExportLogRow>> exportLogsOf(String userId) =>
      (select(exportLogs)..where((row) => row.exportedBy.equals(userId))).get();

  Stream<List<ExportLogRow>> watchExportLogsOf(String userId) => (select(
    exportLogs,
  )..where((row) => row.exportedBy.equals(userId))).watch();

  Future<ExportLogRow?> exportLogById(String id) =>
      (select(exportLogs)..where((row) => row.id.equals(id))).getSingleOrNull();
}
