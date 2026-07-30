import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/delivery_tables.dart';
import '../tables/good_receipt_tables.dart';
import '../tables/master_tables.dart';
import '../tables/purchase_request_tables.dart';

part 'good_receipt_dao.g.dart';

/// A Good Receipt header joined with everything a list row or a detail header
/// needs, plus the per-status line counts a progress indicator shows.
///
/// None of the joins filter `is_active` or `deleted_at`, which is what keeps a
/// receipt readable — and postable — after its branch, the officer who shipped it
/// or one of its items is retired. The repository turns that into
/// `…IsHistorical` flags the screens can label rather than into a row that
/// quietly disappears.
class GoodReceiptWithContext {
  const GoodReceiptWithContext({
    required this.receipt,
    required this.order,
    required this.request,
    required this.branch,
    required this.receivedBy,
    this.shippedBy,
    required this.lineCount,
    required this.pendingCount,
    required this.checkedCount,
    required this.rejectedCount,
    required this.shortageCount,
  });

  final GoodReceiptRow receipt;
  final DeliveryOrderRow order;
  final PurchaseRequestRow request;
  final Branch branch;
  final AppUser receivedBy;
  final AppUser? shippedBy;

  final int lineCount;
  final int pendingCount;
  final int checkedCount;
  final int rejectedCount;

  /// `checked` lines that accepted less than was shipped (G-G3).
  final int shortageCount;
}

/// The five facts an authorization check needs, and nothing else.
///
/// Deliberately not the joined summary: deciding whether a receipt may be shown
/// must not be the reason its number, its items, its batches, its quantities or
/// its reject reasons are read.
class GoodReceiptAccessRow {
  const GoodReceiptAccessRow({
    required this.grId,
    required this.doId,
    required this.prId,
    required this.branchId,
    required this.status,
  });

  final String grId;
  final String doId;
  final String prId;
  final String branchId;
  final GoodReceiptStatus status;
}

/// One receipt line joined with the shipped allocation it answers, its item and
/// — when the item is batch-tracked — its batch.
class GoodReceiptLineWithDetails {
  const GoodReceiptLineWithDetails({
    required this.line,
    required this.doLine,
    required this.item,
    this.batch,
  });

  final GoodReceiptLineRow line;
  final DeliveryOrderLineRow doLine;
  final Item item;
  final ItemBatch? batch;
}

/// One shipped Delivery Order the branch has not checked in yet, with the facts
/// the reminder and the "Mulai Pemeriksaan" row need.
///
/// `receipt` is `null` while no Good Receipt exists at all, and carries the
/// `checking` document once the branch head has started. A `posted` receipt takes
/// the shipment out of this queue entirely — its Delivery Order is `received` by
/// then, and the queue only asks about `shipped` ones.
class AwaitingGoodReceiptRow {
  const AwaitingGoodReceiptRow({
    required this.order,
    required this.request,
    required this.branch,
    this.shippedBy,
    this.receipt,
    required this.lineCount,
    required this.decidedCount,
  });

  final DeliveryOrderRow order;
  final PurchaseRequestRow request;
  final Branch branch;
  final AppUser? shippedBy;
  final GoodReceiptRow? receipt;

  /// Allocations on the shipment — what a receipt will snapshot.
  final int lineCount;

  /// Receipt lines already decided, or `0` when there is no receipt yet.
  final int decidedCount;
}

/// One posted receipt line that did not arrive complete — the raw row behind the
/// warehouse's selisih/retur queue (G-G3/G-G5).
class GoodReceiptDiscrepancyRow {
  const GoodReceiptDiscrepancyRow({
    required this.line,
    required this.receipt,
    required this.order,
    required this.request,
    required this.branch,
    required this.item,
    this.batch,
  });

  final GoodReceiptLineRow line;
  final GoodReceiptRow receipt;
  final DeliveryOrderRow order;
  final PurchaseRequestRow request;
  final Branch branch;
  final Item item;
  final ItemBatch? batch;
}

/// The status of one Delivery Order raised against a Purchase Request — the input
/// to the closure decision (G-G5 → PR `shipped → closed`).
class PurchaseRequestShipmentRow {
  const PurchaseRequestShipmentRow({required this.doId, required this.status});

  final String doId;
  final DeliveryOrderStatus status;
}

/// Good Receipt persistence.
///
/// The same absences that shape [OpnameDao], [PurchaseRequestDao] and
/// [DeliveryOrderDao] shape this one, and for the same reasons:
///
/// * **No unrestricted status writer.** There is no `setStatus`. The one
///   transition this milestone opens — `checking → posted` — has its own method
///   that names the status it expects to move *from*, so the predicate travels
///   into the same statement as the write and a stale screen or a racing device
///   cannot post a receipt twice (G-S1). Every guarded write returns the number
///   of affected rows; zero means the guard fired.
/// * **No unrestricted line writer.** A line's decision can only be changed while
///   its parent is `checking`, checked inside the statement rather than before it.
///   And no writer here reaches `item_id`, `batch_id` or `shipped_qty`: those are
///   the snapshot the shipment left, and editing them would make the ledger a
///   lie.
/// * **No line deletion at all.** Not a soft delete, not a hard one. *"Hapus yang
///   tidak sesuai"* means `rejected` (G-G4), and the audit trail is the point.
/// * **No hard delete and no soft delete of a receipt.** Nothing here removes a
///   row (G-A5), and a posted receipt cannot be touched by any method on this
///   class.
///
/// Two foreign writers *do* live here, and that is deliberate. `DO shipped →
/// received` and `PR shipped → closed` are both driven by a Good Receipt rather
/// than by anybody pressing a button — `DeliveryOrderStatePolicy` classifies the
/// first as a `goodReceipt` transition and `PurchaseRequestStatePolicy` the second
/// as a `system` one — and both have to commit in the **same transaction** as the
/// posting they follow from. Putting them in their own DAOs would mean those DAOs
/// offering a `received` and a `closed` writer to every caller, including the
/// warehouse's shipment editor and the branch head's request editor.
///
/// Like the other DAOs this is a milli-unit layer (Q-4): `shipped_qty` and
/// `received_qty` are INTEGER columns holding `unit * 1000`, and the repository
/// above converts them to `Quantity`.
@DriftAccessor(
  tables: [
    GoodReceipts,
    GoodReceiptLines,
    DeliveryOrders,
    DeliveryOrderLines,
    PurchaseRequests,
    Items,
    ItemBatches,
    Branches,
    Users,
  ],
)
class GoodReceiptDao extends DatabaseAccessor<AppDatabase>
    with _$GoodReceiptDaoMixin {
  GoodReceiptDao(super.db);

  /// Runs [action] in one transaction.
  ///
  /// The posting owns exactly one of these, and every write it performs — the
  /// ledger movements, the balance updates, the receipt status and timestamp, the
  /// Delivery Order transition and the Purchase Request closure that may follow —
  /// happens inside it. Nothing below opens a transaction of its own for a single
  /// line, because a failure on the last movement must roll the first one back.
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      transaction(action);

  // --- writes ---------------------------------------------------------------

  Future<GoodReceiptRow> insertHeader(GoodReceiptsCompanion header) =>
      into(goodReceipts).insertReturning(header);

  Future<void> insertLines(List<GoodReceiptLinesCompanion> lines) async {
    if (lines.isEmpty) return;
    await batch((b) => b.insertAll(goodReceiptLines, lines));
  }

  /// `pending`/`rejected` → `checked` with an accepted quantity (G-G2/G-G3).
  ///
  /// Four predicates travel into the statement, and each of them is a rule rather
  /// than a convenience: the line must belong to [grId], its parent must still be
  /// `checking`, neither row may be soft-deleted, and the quantity must not exceed
  /// the shipped snapshot. The last one is expressed as
  /// `? <= shipped_qty` in SQL rather than trusted from the caller, so a stale
  /// screen cannot receive more than was sent even if the domain check were
  /// somehow skipped.
  ///
  /// `reject_reason` is cleared in the same statement: an accepted line carrying
  /// the reason it was once refused would be an audit trail for a decision that
  /// was reversed.
  Future<int> markLineChecked({
    required String grId,
    required String lineId,
    required int receivedQtyMilliUnits,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE good_receipt_lines '
      'SET line_status = ?, received_qty = ?, reject_reason = NULL, '
      '    updated_at = ?, sync_status = ? '
      'WHERE id = ? AND gr_id = ? AND deleted_at IS NULL '
      '  AND ? >= 0 AND ? <= shipped_qty '
      '  AND gr_id IN ('
      '    SELECT id FROM good_receipts '
      "    WHERE status = 'checking' AND deleted_at IS NULL"
      '  );',
      variables: [
        Variable<String>(GoodReceiptLineStatus.checked.dbValue),
        Variable<int>(receivedQtyMilliUnits),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
        Variable<String>(grId),
        Variable<int>(receivedQtyMilliUnits),
        Variable<int>(receivedQtyMilliUnits),
      ],
      updates: {goodReceiptLines},
      updateKind: UpdateKind.update,
    );
  }

  /// `pending`/`checked` → `rejected` (G-G4).
  ///
  /// `received_qty` is forced to zero in the same statement, because a refused
  /// position accepted nothing and G-G5 reads `received_qty` to decide what enters
  /// the branch store. The row itself is never removed — the reason it carries is
  /// exactly what the warehouse's retur queue reports.
  Future<int> markLineRejected({
    required String grId,
    required String lineId,
    required String reason,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE good_receipt_lines '
      'SET line_status = ?, received_qty = 0, reject_reason = ?, '
      '    updated_at = ?, sync_status = ? '
      'WHERE id = ? AND gr_id = ? AND deleted_at IS NULL '
      "  AND trim(?) <> '' "
      '  AND gr_id IN ('
      '    SELECT id FROM good_receipts '
      "    WHERE status = 'checking' AND deleted_at IS NULL"
      '  );',
      variables: [
        Variable<String>(GoodReceiptLineStatus.rejected.dbValue),
        Variable<String>(reason),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
        Variable<String>(grId),
        Variable<String>(reason),
      ],
      updates: {goodReceiptLines},
      updateKind: UpdateKind.update,
    );
  }

  /// Back to `pending`, with the received quantity returned to the shipped
  /// snapshot and the reason cleared.
  ///
  /// A named operation rather than a generic update, so "undo this decision" is a
  /// reachable, guarded action and "write whatever you like into a line" is not.
  /// `received_qty = shipped_qty` because that is the default a fresh snapshot
  /// carries: the branch head is back to confirming the shipment rather than
  /// holding a quantity nobody entered.
  Future<int> resetLine({required String grId, required String lineId}) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE good_receipt_lines '
      'SET line_status = ?, received_qty = shipped_qty, reject_reason = NULL, '
      '    updated_at = ?, sync_status = ? '
      'WHERE id = ? AND gr_id = ? AND deleted_at IS NULL '
      '  AND gr_id IN ('
      '    SELECT id FROM good_receipts '
      "    WHERE status = 'checking' AND deleted_at IS NULL"
      '  );',
      variables: [
        Variable<String>(GoodReceiptLineStatus.pending.dbValue),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
        Variable<String>(grId),
      ],
      updates: {goodReceiptLines},
      updateKind: UpdateKind.update,
    );
  }

  /// `checking → posted`.
  ///
  /// Two predicates make a double post impossible: `status = 'checking'` and — in
  /// the same statement — `NOT EXISTS` a line that is still `pending`. The second
  /// is G-G2 enforced at the moment of the write rather than at the moment of the
  /// read, which is what a second device deciding a line in between would
  /// otherwise defeat. A return value of 0 means one of them fired, and the caller
  /// rolls the whole transaction — ledger movements included — back.
  ///
  /// The instant is forced to UTC here rather than trusted from the caller (T-1),
  /// because drift serialises a non-UTC `DateTime` with an offset suffix and a
  /// value that arrived in operational time would be *stored* as a different
  /// instant than the one the domain validated.
  Future<int> markPosted({
    required String grId,
    required DateTime postedAtUtc,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE good_receipts '
      'SET status = ?, posted_at = ?, updated_at = ?, sync_status = ? '
      "WHERE id = ? AND status = 'checking' AND deleted_at IS NULL "
      '  AND NOT EXISTS ('
      '    SELECT 1 FROM good_receipt_lines '
      "    WHERE gr_id = good_receipts.id AND deleted_at IS NULL "
      "      AND line_status = 'pending'"
      '  );',
      variables: [
        Variable<String>(GoodReceiptStatus.posted.dbValue),
        Variable<DateTime>(postedAtUtc.toUtc()),
        Variable<DateTime>(now),
        // Once the document leaves the device it is the server's to confirm
        // (G-Y2), so every transition queues a sync.
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(grId),
      ],
      updates: {goodReceipts},
      updateKind: UpdateKind.update,
    );
  }

  // --- foreign transitions driven by a Good Receipt --------------------------

  /// `shipped → received` on the Delivery Order this receipt checked in.
  ///
  /// The guard is `status = 'shipped'` inside the statement, so two devices
  /// posting receipts for the same shipment produce one transition and one zero.
  /// No `received_at` column is written, and none exists: the instant the
  /// shipment was received is the `posted_at` of its Good Receipt, which the
  /// database already holds. Inventing a `delivery_orders.received_at` would be a
  /// second copy of it that could disagree.
  Future<int> markDeliveryOrderReceived(String doId) {
    return (update(deliveryOrders)..where(
          (t) =>
              t.id.equals(doId) &
              t.status.equalsValue(DeliveryOrderStatus.shipped) &
              t.deletedAt.isNull(),
        ))
        .write(
          DeliveryOrdersCompanion(
            status: const Value(DeliveryOrderStatus.received),
            updatedAt: Value(DateTime.now().toUtc()),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  /// `shipped → closed` on the Purchase Request, applied when the receipt being
  /// posted was the last shipment still outstanding.
  ///
  /// No new timestamp column is written, and none exists: a request's closing
  /// instant is the `posted_at` of its last Good Receipt, which is a fact the
  /// database already holds.
  Future<int> markPurchaseRequestClosed(String prId) {
    return (update(purchaseRequests)..where(
          (t) =>
              t.id.equals(prId) &
              t.status.equalsValue(PurchaseRequestStatus.shipped) &
              t.deletedAt.isNull(),
        ))
        .write(
          PurchaseRequestsCompanion(
            status: const Value(PurchaseRequestStatus.closed),
            updatedAt: Value(DateTime.now().toUtc()),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  // --- reads ----------------------------------------------------------------

  Future<GoodReceiptRow?> headerById(String id) => (select(
    goodReceipts,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// The receipt of one shipment, or `null` when the branch has not started.
  ///
  /// G-G1's read half. Soft-deleted rows are excluded here because this answers
  /// "is there a receipt to continue"; the unique index that stops a *second* one
  /// being created is deliberately not partial, so a soft-deleted row still holds
  /// the shipment.
  Future<GoodReceiptRow?> headerByDeliveryOrder(String doId) =>
      (select(goodReceipts)
            ..where((t) => t.doId.equals(doId) & t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<DeliveryOrderRow?> deliveryOrderById(String doId) => (select(
    deliveryOrders,
  )..where((t) => t.id.equals(doId) & t.deletedAt.isNull())).getSingleOrNull();

  /// Live receipt lines of one document, without any join.
  ///
  /// A join can hide a row whose item or batch is physically gone; a plain select
  /// cannot. This is the honest inventory the posting path checks the joined read
  /// against, so a corrupt reference is reported instead of silently reducing the
  /// receipt by one line.
  Future<List<GoodReceiptLineRow>> linesOf(String grId) => (select(
    goodReceiptLines,
  )..where((t) => t.grId.equals(grId) & t.deletedAt.isNull())).get();

  Future<GoodReceiptLineRow?> lineById(String id) => (select(
    goodReceiptLines,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// Live allocations of one shipment, without any join — the expected line set a
  /// receipt must mirror exactly.
  Future<List<DeliveryOrderLineRow>> deliveryOrderLinesOf(String doId) =>
      (select(
        deliveryOrderLines,
      )..where((t) => t.doId.equals(doId) & t.deletedAt.isNull())).get();

  /// Every live Delivery Order of one Purchase Request, with its status.
  ///
  /// The input to the closure decision. Status-agnostic on purpose: the caller
  /// decides which statuses count as a shipment that has to be received, because
  /// that is a domain rule (`preparing` documents have no shipment ledger at all)
  /// and it belongs above this layer.
  Future<List<PurchaseRequestShipmentRow>> shipmentsOfPurchaseRequest(
    String prId,
  ) async {
    final rows =
        await (select(deliveryOrders)
              ..where((t) => t.prId.equals(prId) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return rows
        .map(
          (row) => PurchaseRequestShipmentRow(doId: row.id, status: row.status),
        )
        .toList(growable: false);
  }

  /// The facts that decide whether somebody may open this receipt.
  ///
  /// When [branchId] is supplied the predicate is in the statement, so a receipt
  /// belonging to another branch never leaves SQLite and the caller cannot leak
  /// what it never received. [statuses] narrows the same way: the warehouse may
  /// only read receipts that have actually been posted, and a `checking` one is
  /// invisible to them however the URL is typed.
  ///
  /// Returns `null` both for "no such receipt" and for "not yours", and that
  /// ambiguity is the point: telling them apart would turn the address bar into a
  /// way to enumerate documents across the clinic group.
  Future<GoodReceiptAccessRow?> accessScope({
    required String grId,
    String? branchId,
    Set<GoodReceiptStatus> statuses = const {},
  }) async {
    final row =
        await (selectOnly(goodReceipts).join([
                innerJoin(
                  deliveryOrders,
                  deliveryOrders.id.equalsExp(goodReceipts.doId),
                ),
                innerJoin(
                  purchaseRequests,
                  purchaseRequests.id.equalsExp(deliveryOrders.prId),
                ),
              ])
              ..addColumns([
                goodReceipts.id,
                goodReceipts.status,
                deliveryOrders.id,
                purchaseRequests.id,
                purchaseRequests.branchId,
              ])
              ..where(
                goodReceipts.id.equals(grId) &
                    goodReceipts.deletedAt.isNull() &
                    deliveryOrders.deletedAt.isNull() &
                    purchaseRequests.deletedAt.isNull() &
                    (branchId == null
                        ? const Constant(true)
                        : purchaseRequests.branchId.equals(branchId)) &
                    (statuses.isEmpty
                        ? const Constant(true)
                        : goodReceipts.status.isIn(
                            statuses
                                .map((status) => status.dbValue)
                                .toList(growable: false),
                          )),
              ))
            .getSingleOrNull();
    if (row == null) return null;

    return GoodReceiptAccessRow(
      grId: row.read(goodReceipts.id)!,
      status: row.readWithConverter(goodReceipts.status)!,
      doId: row.read(deliveryOrders.id)!,
      prId: row.read(purchaseRequests.id)!,
      branchId: row.read(purchaseRequests.branchId)!,
    );
  }

  // --- joined line reads ----------------------------------------------------

  JoinedSelectStatement<HasResultSet, dynamic> _detailLinesQuery(String grId) {
    return (select(
        goodReceiptLines,
      )..where((t) => t.grId.equals(grId) & t.deletedAt.isNull())).join([
        // No `is_active` and no `deleted_at` filter on the master joins: a
        // receipt whose item was withdrawn afterwards must stay readable and
        // stay postable, and the repository labels it instead of hiding it.
        innerJoin(
          deliveryOrderLines,
          deliveryOrderLines.id.equalsExp(goodReceiptLines.doLineId),
        ),
        innerJoin(items, items.id.equalsExp(goodReceiptLines.itemId)),
        leftOuterJoin(
          itemBatches,
          itemBatches.id.equalsExp(goodReceiptLines.batchId),
        ),
      ])
      ..orderBy([
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(itemBatches.batchNo),
      ]);
  }

  List<GoodReceiptLineWithDetails> _mapLines(List<TypedResult> rows) {
    return rows
        .map(
          (row) => GoodReceiptLineWithDetails(
            line: row.readTable(goodReceiptLines),
            doLine: row.readTable(deliveryOrderLines),
            item: row.readTable(items),
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Future<List<GoodReceiptLineWithDetails>> detailLines(String grId) async =>
      _mapLines(await _detailLinesQuery(grId).get());

  Stream<List<GoodReceiptLineWithDetails>> watchDetailLines(String grId) =>
      _detailLinesQuery(grId).watch().map(_mapLines);

  // --- summaries ------------------------------------------------------------

  late final $UsersTable _receivers = alias(users, 'received_by_user');
  late final $UsersTable _shippers = alias(users, 'shipped_by_user');

  Expression<int> _lineCountWhere([Expression<bool>? extra]) {
    var filter = goodReceiptLines.deletedAt.isNull();
    if (extra != null) filter = filter & extra;
    return goodReceiptLines.id.count(distinct: true, filter: filter);
  }

  Expression<int> get _lineCount => _lineCountWhere();

  Expression<int> get _pendingCount => _lineCountWhere(
    goodReceiptLines.lineStatus.equalsValue(GoodReceiptLineStatus.pending),
  );

  Expression<int> get _checkedCount => _lineCountWhere(
    goodReceiptLines.lineStatus.equalsValue(GoodReceiptLineStatus.checked),
  );

  Expression<int> get _rejectedCount => _lineCountWhere(
    goodReceiptLines.lineStatus.equalsValue(GoodReceiptLineStatus.rejected),
  );

  Expression<int> get _shortageCount => _lineCountWhere(
    goodReceiptLines.lineStatus.equalsValue(GoodReceiptLineStatus.checked) &
        goodReceiptLines.receivedQty.isSmallerThan(goodReceiptLines.shippedQty),
  );

  JoinedSelectStatement<HasResultSet, dynamic> _summaryQuery(
    Expression<bool> predicate,
  ) {
    final query = (select(goodReceipts)..where((t) => t.deletedAt.isNull()))
        .join([
          innerJoin(
            deliveryOrders,
            deliveryOrders.id.equalsExp(goodReceipts.doId),
          ),
          innerJoin(
            purchaseRequests,
            purchaseRequests.id.equalsExp(deliveryOrders.prId),
          ),
          innerJoin(branches, branches.id.equalsExp(purchaseRequests.branchId)),
          innerJoin(
            _receivers,
            _receivers.id.equalsExp(goodReceipts.receivedBy),
          ),
          leftOuterJoin(
            _shippers,
            _shippers.id.equalsExp(deliveryOrders.shippedBy),
          ),
          // Left join so a receipt with no lines still produces a row, and
          // soft-deleted lines never inflate the counts.
          leftOuterJoin(
            goodReceiptLines,
            goodReceiptLines.grId.equalsExp(goodReceipts.id) &
                goodReceiptLines.deletedAt.isNull(),
          ),
        ]);

    return query
      ..addColumns([
        _lineCount,
        _pendingCount,
        _checkedCount,
        _rejectedCount,
        _shortageCount,
      ])
      ..where(predicate)
      ..groupBy([goodReceipts.id])
      ..orderBy([OrderingTerm.desc(goodReceipts.createdAt)]);
  }

  List<GoodReceiptWithContext> _mapSummaries(List<TypedResult> rows) {
    return rows
        .map(
          (row) => GoodReceiptWithContext(
            receipt: row.readTable(goodReceipts),
            order: row.readTable(deliveryOrders),
            request: row.readTable(purchaseRequests),
            branch: row.readTable(branches),
            receivedBy: row.readTable(_receivers),
            shippedBy: row.readTableOrNull(_shippers),
            lineCount: row.read(_lineCount) ?? 0,
            pendingCount: row.read(_pendingCount) ?? 0,
            checkedCount: row.read(_checkedCount) ?? 0,
            rejectedCount: row.read(_rejectedCount) ?? 0,
            shortageCount: row.read(_shortageCount) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  /// The document predicate, optionally pinned to one branch and one status set.
  ///
  /// Both checks happen **inside the statement**, so a receipt outside them is
  /// never read, never mapped and never reaches a stream a widget could be
  /// listening to. Filtering the result in Dart would look equivalent and would
  /// not be.
  Expression<bool> _document(
    String grId,
    String? branchId,
    Set<GoodReceiptStatus> statuses,
  ) {
    var predicate = goodReceipts.id.equals(grId);
    if (branchId != null) {
      predicate = predicate & purchaseRequests.branchId.equals(branchId);
    }
    if (statuses.isNotEmpty) {
      predicate =
          predicate &
          goodReceipts.status.isIn(
            statuses.map((status) => status.dbValue).toList(growable: false),
          );
    }
    return predicate;
  }

  Future<GoodReceiptWithContext?> summaryById(
    String grId, {
    String? branchId,
    Set<GoodReceiptStatus> statuses = const {},
  }) async {
    final rows = await _summaryQuery(_document(grId, branchId, statuses)).get();
    return rows.isEmpty ? null : _mapSummaries(rows).single;
  }

  Stream<GoodReceiptWithContext?> watchSummaryById(
    String grId, {
    String? branchId,
    Set<GoodReceiptStatus> statuses = const {},
  }) {
    return _summaryQuery(
      _document(grId, branchId, statuses),
    ).watch().map((rows) => rows.isEmpty ? null : _mapSummaries(rows).single);
  }

  Expression<bool> _scope({
    String? branchId,
    Set<GoodReceiptStatus> statuses = const {},
    String? searchQuery,
  }) {
    var predicate = const Constant(true) as Expression<bool>;
    if (branchId != null) {
      predicate = predicate & purchaseRequests.branchId.equals(branchId);
    }
    if (statuses.isNotEmpty) {
      predicate =
          predicate &
          goodReceipts.status.isIn(
            statuses.map((status) => status.dbValue).toList(growable: false),
          );
    }
    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      // Receipt number, Surat Jalan number, Purchase Request number, branch or a
      // received item, case-insensitive and entirely local so the clinic keeps
      // searching offline (G-Y1).
      final pattern = '%$needle%';
      predicate =
          predicate &
          (goodReceipts.docNumber.lower().like(pattern) |
              deliveryOrders.docNumber.lower().like(pattern) |
              purchaseRequests.docNumber.lower().like(pattern) |
              branches.name.lower().like(pattern) |
              branches.code.lower().like(pattern) |
              _receivesMatchingItem(pattern));
    }
    return predicate;
  }

  /// Whether a receipt carries an item whose name or SKU matches [pattern].
  ///
  /// Two single-column subqueries rather than a join, because the summary query
  /// already left-joins `good_receipt_lines` to count them: adding `items` to that
  /// join would make the `WHERE` filter away the very rows the counts are derived
  /// from, and a receipt found by its number would then report only its matching
  /// lines.
  Expression<bool> _receivesMatchingItem(String pattern) {
    final matchingItems = selectOnly(items)
      ..addColumns([items.id])
      ..where(
        items.name.lower().like(pattern) | items.sku.lower().like(pattern),
      );

    final matchingReceipts = selectOnly(goodReceiptLines)
      ..addColumns([goodReceiptLines.grId])
      ..where(
        goodReceiptLines.deletedAt.isNull() &
            goodReceiptLines.itemId.isInQuery(matchingItems),
      );

    return goodReceipts.id.isInQuery(matchingReceipts);
  }

  Future<List<GoodReceiptWithContext>> listReceipts({
    String? branchId,
    Set<GoodReceiptStatus> statuses = const {},
    String? searchQuery,
  }) async {
    final rows = await _summaryQuery(
      _scope(branchId: branchId, statuses: statuses, searchQuery: searchQuery),
    ).get();
    return _mapSummaries(rows);
  }

  Stream<List<GoodReceiptWithContext>> watchReceipts({
    String? branchId,
    Set<GoodReceiptStatus> statuses = const {},
    String? searchQuery,
  }) {
    return _summaryQuery(
      _scope(branchId: branchId, statuses: statuses, searchQuery: searchQuery),
    ).watch().map(_mapSummaries);
  }

  // --- awaiting shipments ---------------------------------------------------

  Expression<int> get _doLineCount => deliveryOrderLines.id.count(
    distinct: true,
    filter: deliveryOrderLines.deletedAt.isNull(),
  );

  Expression<int> get _decidedCount => goodReceiptLines.id.count(
    distinct: true,
    filter:
        goodReceiptLines.deletedAt.isNull() &
        goodReceiptLines.lineStatus
            .equalsValue(GoodReceiptLineStatus.pending)
            .not(),
  );

  /// Shipments the branch still has to check in: `shipped` Delivery Orders, with
  /// their `checking` receipt attached when one exists.
  ///
  /// Deliberately keyed on the **Delivery Order** rather than on the receipt,
  /// because the two rows a branch head needs to act on are "nothing started yet"
  /// and "started, not finished", and only the first has no receipt to key on. A
  /// `posted` receipt is absent from this query by construction: posting moves its
  /// shipment to `received`, and the predicate asks for `shipped`.
  JoinedSelectStatement<HasResultSet, dynamic> _awaitingQuery(
    String? branchId,
  ) {
    var predicate =
        deliveryOrders.status.equalsValue(DeliveryOrderStatus.shipped) &
        deliveryOrders.deletedAt.isNull() &
        purchaseRequests.deletedAt.isNull();
    if (branchId != null) {
      predicate = predicate & purchaseRequests.branchId.equals(branchId);
    }

    final query = select(deliveryOrders).join([
      innerJoin(
        purchaseRequests,
        purchaseRequests.id.equalsExp(deliveryOrders.prId),
      ),
      innerJoin(branches, branches.id.equalsExp(purchaseRequests.branchId)),
      leftOuterJoin(
        _shippers,
        _shippers.id.equalsExp(deliveryOrders.shippedBy),
      ),
      leftOuterJoin(
        goodReceipts,
        goodReceipts.doId.equalsExp(deliveryOrders.id) &
            goodReceipts.deletedAt.isNull(),
      ),
      leftOuterJoin(
        deliveryOrderLines,
        deliveryOrderLines.doId.equalsExp(deliveryOrders.id) &
            deliveryOrderLines.deletedAt.isNull(),
      ),
      leftOuterJoin(
        goodReceiptLines,
        goodReceiptLines.grId.equalsExp(goodReceipts.id) &
            goodReceiptLines.deletedAt.isNull(),
      ),
    ]);

    return query
      ..addColumns([_doLineCount, _decidedCount])
      ..where(predicate)
      ..groupBy([deliveryOrders.id])
      // Oldest shipment first: the one closest to its 2×24 hour deadline (G-G6).
      ..orderBy([OrderingTerm.asc(deliveryOrders.shippedAt)]);
  }

  List<AwaitingGoodReceiptRow> _mapAwaiting(List<TypedResult> rows) {
    return rows
        .map(
          (row) => AwaitingGoodReceiptRow(
            order: row.readTable(deliveryOrders),
            request: row.readTable(purchaseRequests),
            branch: row.readTable(branches),
            shippedBy: row.readTableOrNull(_shippers),
            receipt: row.readTableOrNull(goodReceipts),
            lineCount: row.read(_doLineCount) ?? 0,
            decidedCount: row.read(_decidedCount) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<AwaitingGoodReceiptRow>> awaitingReceipts({
    String? branchId,
  }) async => _mapAwaiting(await _awaitingQuery(branchId).get());

  Stream<List<AwaitingGoodReceiptRow>> watchAwaitingReceipts({
    String? branchId,
  }) => _awaitingQuery(branchId).watch().map(_mapAwaiting);

  // --- discrepancy / return queue -------------------------------------------

  /// Posted receipt lines that did not arrive complete (G-G3/G-G5).
  ///
  /// Two shapes qualify, and the caller classifies them: a `checked` line that
  /// accepted less than was shipped (a *shortage*), and a `rejected` line, which
  /// accepted nothing and is therefore a *return*. Both are read from the same
  /// query because the warehouse looks at one list.
  ///
  /// Only `posted` receipts appear. A `checking` one is a branch head part way
  /// through a decision, and reporting its intermediate state to the warehouse
  /// would raise a return for goods that have not been refused yet.
  ///
  /// There is deliberately **no `posted_at` window here**. Timestamps are persisted as
  /// ISO-8601 TEXT (see `build.yaml`), so a SQL `>=` on `posted_at` compares characters
  /// rather than instants — the same trap schema v4 removed from `stock_opnames`, and the
  /// one `DocumentTimestampPolicy` exists to keep out of this codebase. The repository
  /// applies the window in Dart, on UTC `DateTime`s. The branch predicate stays here
  /// because it is a *security* boundary and must never be a Dart filter; a display date
  /// range is not.
  JoinedSelectStatement<HasResultSet, dynamic> _discrepancyQuery({
    String? branchId,
    String? searchQuery,
    bool? rejectedOnly,
  }) {
    var predicate =
        goodReceiptLines.deletedAt.isNull() &
        goodReceipts.deletedAt.isNull() &
        goodReceipts.status.equalsValue(GoodReceiptStatus.posted) &
        (goodReceiptLines.lineStatus.equalsValue(
              GoodReceiptLineStatus.rejected,
            ) |
            (goodReceiptLines.lineStatus.equalsValue(
                  GoodReceiptLineStatus.checked,
                ) &
                goodReceiptLines.receivedQty.isSmallerThan(
                  goodReceiptLines.shippedQty,
                )));

    if (branchId != null) {
      predicate = predicate & purchaseRequests.branchId.equals(branchId);
    }
    if (rejectedOnly != null) {
      final isRejected = goodReceiptLines.lineStatus.equalsValue(
        GoodReceiptLineStatus.rejected,
      );
      predicate = predicate & (rejectedOnly ? isRejected : isRejected.not());
    }
    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      final pattern = '%$needle%';
      predicate =
          predicate &
          (goodReceipts.docNumber.lower().like(pattern) |
              deliveryOrders.docNumber.lower().like(pattern) |
              purchaseRequests.docNumber.lower().like(pattern) |
              branches.name.lower().like(pattern) |
              branches.code.lower().like(pattern) |
              items.name.lower().like(pattern) |
              items.sku.lower().like(pattern));
    }

    return select(goodReceiptLines).join([
        innerJoin(
          goodReceipts,
          goodReceipts.id.equalsExp(goodReceiptLines.grId),
        ),
        innerJoin(
          deliveryOrders,
          deliveryOrders.id.equalsExp(goodReceipts.doId),
        ),
        innerJoin(
          purchaseRequests,
          purchaseRequests.id.equalsExp(deliveryOrders.prId),
        ),
        innerJoin(branches, branches.id.equalsExp(purchaseRequests.branchId)),
        innerJoin(items, items.id.equalsExp(goodReceiptLines.itemId)),
        leftOuterJoin(
          itemBatches,
          itemBatches.id.equalsExp(goodReceiptLines.batchId),
        ),
      ])
      ..where(predicate)
      ..orderBy([
        OrderingTerm.desc(goodReceipts.postedAt),
        OrderingTerm.asc(items.name),
      ]);
  }

  List<GoodReceiptDiscrepancyRow> _mapDiscrepancies(List<TypedResult> rows) {
    return rows
        .map(
          (row) => GoodReceiptDiscrepancyRow(
            line: row.readTable(goodReceiptLines),
            receipt: row.readTable(goodReceipts),
            order: row.readTable(deliveryOrders),
            request: row.readTable(purchaseRequests),
            branch: row.readTable(branches),
            item: row.readTable(items),
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Future<List<GoodReceiptDiscrepancyRow>> discrepancies({
    String? branchId,
    String? searchQuery,
    bool? rejectedOnly,
  }) async => _mapDiscrepancies(
    await _discrepancyQuery(
      branchId: branchId,
      searchQuery: searchQuery,
      rejectedOnly: rejectedOnly,
    ).get(),
  );

  Stream<List<GoodReceiptDiscrepancyRow>> watchDiscrepancies({
    String? branchId,
    String? searchQuery,
    bool? rejectedOnly,
  }) => _discrepancyQuery(
    branchId: branchId,
    searchQuery: searchQuery,
    rejectedOnly: rejectedOnly,
  ).watch().map(_mapDiscrepancies);
}
