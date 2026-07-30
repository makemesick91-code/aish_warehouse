import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/delivery_tables.dart';
import '../tables/master_tables.dart';
import '../tables/purchase_request_tables.dart';

part 'delivery_order_dao.g.dart';

/// A Delivery Order header joined with everything a list row, a detail header or
/// a Surat Jalan needs to render, plus the line count a summary shows.
///
/// None of the joins filter `is_active` or `deleted_at`, which is what keeps a
/// shipped document readable after its branch, the officer who prepared it or one
/// of its items is retired. The repository turns that into `…IsHistorical` flags
/// the screens can label rather than into a row that quietly disappears.
class DeliveryOrderWithContext {
  const DeliveryOrderWithContext({
    required this.order,
    required this.request,
    required this.branch,
    required this.preparedBy,
    required this.requestedBy,
    this.shippedBy,
    required this.lineCount,
  });

  final DeliveryOrderRow order;
  final PurchaseRequestRow request;
  final Branch branch;
  final AppUser preparedBy;
  final AppUser requestedBy;
  final AppUser? shippedBy;
  final int lineCount;
}

/// The four facts an authorization check needs, and nothing else.
///
/// Deliberately not the joined summary: deciding whether a document may be shown
/// must not be the reason its number, its items, its batches or its quantities
/// are read.
class DeliveryOrderAccessRow {
  const DeliveryOrderAccessRow({
    required this.doId,
    required this.prId,
    required this.branchId,
    required this.status,
  });

  final String doId;
  final String prId;
  final String branchId;
  final DeliveryOrderStatus status;
}

/// One allocation joined with the requested position it satisfies, its item and
/// — when the item is batch-tracked — its batch.
class DeliveryOrderLineWithDetails {
  const DeliveryOrderLineWithDetails({
    required this.line,
    required this.prLine,
    required this.item,
    this.batch,
  });

  final DeliveryOrderLineRow line;
  final PurchaseRequestLineRow prLine;
  final Item item;
  final ItemBatch? batch;
}

/// One requested position of a Purchase Request joined with its item — the raw
/// material the shipment-progress calculation and the allocation form work from.
class PurchaseRequestLineWithItem {
  const PurchaseRequestLineWithItem({required this.line, required this.item});

  final PurchaseRequestLineRow line;
  final Item item;
}

/// Delivery Order persistence.
///
/// The same absences that shape [OpnameDao] and [PurchaseRequestDao] shape this
/// one, and for the same reasons:
///
/// * **No unrestricted status writer.** There is no `setStatus`. The one
///   transition this milestone opens — `preparing → shipped` — has its own method
///   that names the status it expects to move *from*, so the predicate travels
///   into the same statement as the write and a stale screen or a racing device
///   cannot ship a document twice (G-S1). Every guarded write returns the number
///   of affected rows; zero means the guard fired.
/// * **No unrestricted line writer.** A line can only be inserted, updated or
///   removed while its parent is `preparing`, checked inside the statement rather
///   than before it. A shipped document's allocations are what the ledger was
///   posted from, so editing them would make the movements a lie.
/// * **No hard delete.** Nothing here removes a row (G-A5), and no method can
///   soft-delete a document that has left `preparing`.
/// * **No writer for `received`.** That transition belongs to Good Receipt.
///   Offering it here would be a button waiting to be wired up before the
///   document that justifies it exists.
///
/// Two Purchase Request writers *do* live here, and that is deliberate. G-D1's
/// `submitted → processing` and G-D5's `processing → shipped` are both driven by
/// a Delivery Order rather than by anybody pressing a button —
/// `PurchaseRequestStatePolicy` already classifies the second as a `system`
/// transition — and both have to commit in the **same transaction** as the
/// shipment they follow from. Putting them in the Purchase Request DAO would mean
/// that DAO offering a `shipped` writer to every caller, including the branch
/// head's editor.
///
/// Like the other DAOs this is a milli-unit layer (Q-4): `shipped_qty` and
/// `requested_qty` are INTEGER columns holding `unit * 1000`, and the repository
/// above converts them to `Quantity`.
@DriftAccessor(
  tables: [
    DeliveryOrders,
    DeliveryOrderLines,
    PurchaseRequests,
    PurchaseRequestLines,
    Items,
    ItemBatches,
    Branches,
    Users,
  ],
)
class DeliveryOrderDao extends DatabaseAccessor<AppDatabase>
    with _$DeliveryOrderDaoMixin {
  DeliveryOrderDao(super.db);

  /// Runs [action] in one transaction.
  ///
  /// The shipment posting owns exactly one of these, and every write it performs
  /// — the ledger movements, the balance updates, the document status, the
  /// timestamps and the Purchase Request transition that may follow — happens
  /// inside it. Nothing below opens a transaction of its own for a single line,
  /// because a failure on the last allocation must roll the first one back.
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      transaction(action);

  // --- writes ---------------------------------------------------------------

  Future<DeliveryOrderRow> insertHeader(DeliveryOrdersCompanion header) =>
      into(deliveryOrders).insertReturning(header);

  Future<void> insertLines(List<DeliveryOrderLinesCompanion> lines) async {
    if (lines.isEmpty) return;
    await batch((b) => b.insertAll(deliveryOrderLines, lines));
  }

  /// Adds one allocation to a document that is still `preparing`.
  ///
  /// Returns `null` when the parent is not editable. The status check and the
  /// insert share a transaction: without it a ship committing in the gap between
  /// them would let this insert land on a document whose ledger movements have
  /// already been written.
  Future<DeliveryOrderLineRow?> insertPreparingLine({
    required String doId,
    required DeliveryOrderLinesCompanion line,
  }) {
    return transaction(() async {
      if (!await isPreparing(doId)) return null;
      return into(deliveryOrderLines).insertReturning(line);
    });
  }

  /// Replaces every live allocation of a `preparing` document with [lines].
  ///
  /// One operation rather than "remove each, then add each", because the
  /// intermediate states are all wrong: a document with no allocations at all, or
  /// one holding a mixture of the old FEFO answer and the new one. Returns
  /// `false` when the document is no longer `preparing`.
  Future<bool> replacePreparingLines({
    required String doId,
    required List<DeliveryOrderLinesCompanion> lines,
  }) {
    return transaction(() async {
      if (!await isPreparing(doId)) return false;

      final existing = await linesOf(doId);
      for (final line in existing) {
        await softDeletePreparingLine(line.id);
      }
      await insertLines(lines);
      return true;
    });
  }

  /// The quantity, batch and expiry audit of one allocation on a `preparing`
  /// document.
  ///
  /// `pr_line_id` and `item_id` are **not** in the SET list: which requested
  /// position a line satisfies, and which item it moves, is decided when the line
  /// is created and is exactly what G-D4 forbids the warehouse from changing.
  /// Repointing a line is expressed as removing it and allocating another.
  Future<int> updatePreparingLine({
    required String lineId,
    required int shippedQtyMilliUnits,
    required String? batchId,
    required String? fefoOverrideReason,
    required bool nearExpiryConfirmed,
    required String? nearExpiryNote,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE delivery_order_lines '
      'SET shipped_qty = ?, batch_id = ?, fefo_override_reason = ?, '
      '    near_expiry_confirmed = ?, near_expiry_note = ?, '
      '    updated_at = ?, sync_status = ? '
      'WHERE id = ? AND deleted_at IS NULL AND do_id IN ('
      '  SELECT id FROM delivery_orders '
      "  WHERE status = 'preparing' AND deleted_at IS NULL"
      ');',
      variables: [
        Variable<int>(shippedQtyMilliUnits),
        Variable<String>(batchId),
        Variable<String>(fefoOverrideReason),
        Variable<bool>(nearExpiryConfirmed),
        Variable<String>(nearExpiryNote),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
      ],
      updates: {deliveryOrderLines},
      updateKind: UpdateKind.update,
    );
  }

  /// Soft-deletes one allocation of a `preparing` document. Lines of shipped and
  /// received documents survive every call (G-S2).
  Future<int> softDeletePreparingLine(String lineId) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE delivery_order_lines '
      'SET deleted_at = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND deleted_at IS NULL AND do_id IN ('
      '  SELECT id FROM delivery_orders '
      "  WHERE status = 'preparing' AND deleted_at IS NULL"
      ');',
      variables: [
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
      ],
      updates: {deliveryOrderLines},
      updateKind: UpdateKind.update,
    );
  }

  /// The header note of a `preparing` document.
  Future<int> updatePreparingHeader({
    required String doId,
    required String? note,
  }) {
    return (update(deliveryOrders)..where(
          (t) =>
              t.id.equals(doId) &
              t.status.equalsValue(DeliveryOrderStatus.preparing) &
              t.deletedAt.isNull(),
        ))
        .write(
          DeliveryOrdersCompanion(
            note: Value(note),
            updatedAt: Value(DateTime.now().toUtc()),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  /// `preparing → shipped`.
  ///
  /// The `WHERE status = 'preparing'` clause makes a lost update impossible: a
  /// return value of 0 means somebody else shipped the document first, and the
  /// caller rolls the whole transaction — ledger movements included — back. The
  /// instant is forced to UTC here rather than trusted from the caller (T-1),
  /// because drift serialises a non-UTC `DateTime` with an offset suffix and a
  /// value that arrived in operational time would be *stored* as a different
  /// instant than the one the domain validated.
  Future<int> markShipped({
    required String doId,
    required String shippedBy,
    required DateTime shippedAtUtc,
  }) {
    return (update(deliveryOrders)..where(
          (t) =>
              t.id.equals(doId) &
              t.status.equalsValue(DeliveryOrderStatus.preparing) &
              t.deletedAt.isNull(),
        ))
        .write(
          DeliveryOrdersCompanion(
            status: const Value(DeliveryOrderStatus.shipped),
            shippedAt: Value(shippedAtUtc.toUtc()),
            shippedBy: Value(shippedBy),
            updatedAt: Value(DateTime.now().toUtc()),
            // Once the document leaves the device it is the server's to confirm
            // (G-Y2), so every transition queues a sync.
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  /// Soft-deletes a `preparing` document. Shipped and received documents are
  /// permanent (G-S2/G-A5) and this guard is what makes the workflow unable to
  /// remove them.
  Future<int> softDeletePreparing(String doId) {
    final now = DateTime.now().toUtc();
    return (update(deliveryOrders)..where(
          (t) =>
              t.id.equals(doId) &
              t.status.equalsValue(DeliveryOrderStatus.preparing) &
              t.deletedAt.isNull(),
        ))
        .write(
          DeliveryOrdersCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  // --- Purchase Request transitions driven by a Delivery Order ---------------

  /// G-D1 — `submitted → processing`, applied when the first Delivery Order of a
  /// request is created.
  ///
  /// The guard is `status = 'submitted'` inside the statement, so two officers
  /// starting on the same request produce one transition and one zero.
  Future<int> markPurchaseRequestProcessing({
    required String prId,
    required String processedBy,
    required DateTime processingAtUtc,
  }) {
    return (update(purchaseRequests)..where(
          (t) =>
              t.id.equals(prId) &
              t.status.equalsValue(PurchaseRequestStatus.submitted) &
              t.deletedAt.isNull(),
        ))
        .write(
          PurchaseRequestsCompanion(
            status: const Value(PurchaseRequestStatus.processing),
            processingAt: Value(processingAtUtc.toUtc()),
            processedBy: Value(processedBy),
            updatedAt: Value(DateTime.now().toUtc()),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  /// G-D5 — `processing → shipped`, applied when the shipment being posted
  /// completes every requested position.
  ///
  /// No new timestamp column is written, and none exists: a request's shipping
  /// instant is the `shipped_at` of its last Delivery Order, which is a fact the
  /// database already holds. Inventing a `purchase_requests.shipped_at` would be
  /// a second copy of it that could disagree.
  ///
  /// There is deliberately **no** `closed` counterpart. That transition happens
  /// when every Delivery Order has been received through Good Receipt, which is
  /// the next milestone's document to write.
  Future<int> markPurchaseRequestShipped(String prId) {
    return (update(purchaseRequests)..where(
          (t) =>
              t.id.equals(prId) &
              t.status.equalsValue(PurchaseRequestStatus.processing) &
              t.deletedAt.isNull(),
        ))
        .write(
          PurchaseRequestsCompanion(
            status: const Value(PurchaseRequestStatus.shipped),
            updatedAt: Value(DateTime.now().toUtc()),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  // --- reads ----------------------------------------------------------------

  Future<DeliveryOrderRow?> headerById(String id) => (select(
    deliveryOrders,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<bool> isPreparing(String doId) async {
    final row = await headerById(doId);
    return row?.status == DeliveryOrderStatus.preparing;
  }

  Future<PurchaseRequestRow?> purchaseRequestById(String prId) => (select(
    purchaseRequests,
  )..where((t) => t.id.equals(prId) & t.deletedAt.isNull())).getSingleOrNull();

  /// Live allocation rows of one document, without any join.
  ///
  /// A join can hide a row whose item or batch is physically gone; a plain select
  /// cannot. This is the honest inventory the ship path checks the joined read
  /// against, so a corrupt reference is reported instead of silently reducing the
  /// shipment by one line.
  Future<List<DeliveryOrderLineRow>> linesOf(String doId) => (select(
    deliveryOrderLines,
  )..where((t) => t.doId.equals(doId) & t.deletedAt.isNull())).get();

  Future<DeliveryOrderLineRow?> lineById(String id) => (select(
    deliveryOrderLines,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// Live requested positions of one Purchase Request, without any join — the
  /// counterpart of [linesOf] for the ordered half of the workflow.
  Future<List<PurchaseRequestLineRow>> purchaseRequestLinesOf(String prId) =>
      (select(
        purchaseRequestLines,
      )..where((t) => t.prId.equals(prId) & t.deletedAt.isNull())).get();

  /// Requested positions joined with their items, ordered for display.
  Future<List<PurchaseRequestLineWithItem>> purchaseRequestLineDetails(
    String prId,
  ) async {
    final rows =
        await (select(
          purchaseRequestLines,
        )..where((t) => t.prId.equals(prId) & t.deletedAt.isNull())).join([
          innerJoin(items, items.id.equalsExp(purchaseRequestLines.itemId)),
        ]).get();
    return rows
        .map(
          (row) => PurchaseRequestLineWithItem(
            line: row.readTable(purchaseRequestLines),
            item: row.readTable(items),
          ),
        )
        .toList(growable: false);
  }

  /// G-D2's authority: how much of each requested position has **actually left
  /// the warehouse**, summed over every live Delivery Order in `shipped` or
  /// `received`.
  ///
  /// Three properties make this the number the rule is about:
  ///
  /// * `preparing` documents are excluded. A draft allocation is an intention,
  ///   not a shipment, and counting it would refuse a second officer's legitimate
  ///   partial while the first document sat unposted.
  /// * `received` documents are included. The goods left, and Good Receipt does
  ///   not send them back.
  /// * soft-deleted lines and documents are excluded on both sides.
  ///
  /// [excludeDoId] leaves the document being posted out, so the ship path can add
  /// its own quantities to the total rather than double-counting them.
  Future<Map<String, int>> cumulativeShippedByPrLine({
    required String prId,
    String? excludeDoId,
  }) async {
    final total = deliveryOrderLines.shippedQty.sum();
    final query =
        selectOnly(deliveryOrderLines).join([
            innerJoin(
              deliveryOrders,
              deliveryOrders.id.equalsExp(deliveryOrderLines.doId),
            ),
            innerJoin(
              purchaseRequestLines,
              purchaseRequestLines.id.equalsExp(deliveryOrderLines.prLineId),
            ),
          ])
          ..addColumns([deliveryOrderLines.prLineId, total])
          ..where(
            purchaseRequestLines.prId.equals(prId) &
                deliveryOrderLines.deletedAt.isNull() &
                deliveryOrders.deletedAt.isNull() &
                deliveryOrders.status.isIn(_shippedStatusValues) &
                (excludeDoId == null
                    ? const Constant(true)
                    : deliveryOrders.id.equals(excludeDoId).not()),
          )
          ..groupBy([deliveryOrderLines.prLineId]);

    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(deliveryOrderLines.prLineId)!: row.read(total) ?? 0,
    };
  }

  /// Quantities the given document itself allocates, per requested position.
  ///
  /// Status-agnostic on purpose: the ship path reads it for a `preparing`
  /// document, which [cumulativeShippedByPrLine] excludes by design.
  Future<Map<String, int>> allocatedByPrLine(String doId) async {
    final total = deliveryOrderLines.shippedQty.sum();
    final query = selectOnly(deliveryOrderLines)
      ..addColumns([deliveryOrderLines.prLineId, total])
      ..where(
        deliveryOrderLines.doId.equals(doId) &
            deliveryOrderLines.deletedAt.isNull(),
      )
      ..groupBy([deliveryOrderLines.prLineId]);

    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(deliveryOrderLines.prLineId)!: row.read(total) ?? 0,
    };
  }

  static final List<String> _shippedStatusValues = [
    DeliveryOrderStatus.shipped.dbValue,
    DeliveryOrderStatus.received.dbValue,
  ];

  /// The facts that decide whether somebody may open this document.
  ///
  /// When [branchId] is supplied the predicate is in the statement, so a document
  /// belonging to another branch never leaves SQLite and the caller cannot leak
  /// what it never received. [statuses] narrows the same way: a branch head may
  /// only see shipments that have actually been sent, and a `preparing` document
  /// is invisible to them however the URL is typed.
  ///
  /// Returns `null` both for "no such document" and for "not yours", and that
  /// ambiguity is the point: telling them apart would turn the address bar into a
  /// way to enumerate documents across the clinic group.
  Future<DeliveryOrderAccessRow?> accessScope({
    required String doId,
    String? branchId,
    Set<DeliveryOrderStatus> statuses = const {},
  }) async {
    final row =
        await (selectOnly(deliveryOrders).join([
                innerJoin(
                  purchaseRequests,
                  purchaseRequests.id.equalsExp(deliveryOrders.prId),
                ),
              ])
              ..addColumns([
                deliveryOrders.id,
                deliveryOrders.status,
                purchaseRequests.id,
                purchaseRequests.branchId,
              ])
              ..where(
                deliveryOrders.id.equals(doId) &
                    deliveryOrders.deletedAt.isNull() &
                    purchaseRequests.deletedAt.isNull() &
                    (branchId == null
                        ? const Constant(true)
                        : purchaseRequests.branchId.equals(branchId)) &
                    (statuses.isEmpty
                        ? const Constant(true)
                        : deliveryOrders.status.isIn(
                            statuses
                                .map((status) => status.dbValue)
                                .toList(growable: false),
                          )),
              ))
            .getSingleOrNull();
    if (row == null) return null;

    return DeliveryOrderAccessRow(
      doId: row.read(deliveryOrders.id)!,
      status: row.readWithConverter(deliveryOrders.status)!,
      prId: row.read(purchaseRequests.id)!,
      branchId: row.read(purchaseRequests.branchId)!,
    );
  }

  // --- joined line reads ----------------------------------------------------

  JoinedSelectStatement<HasResultSet, dynamic> _detailLinesQuery(String doId) {
    return (select(
        deliveryOrderLines,
      )..where((t) => t.doId.equals(doId) & t.deletedAt.isNull())).join([
        // No `is_active` and no `deleted_at` filter on the master joins: a
        // shipped document whose item was withdrawn afterwards must stay
        // readable, and the repository labels it instead of hiding it.
        innerJoin(
          purchaseRequestLines,
          purchaseRequestLines.id.equalsExp(deliveryOrderLines.prLineId),
        ),
        innerJoin(items, items.id.equalsExp(deliveryOrderLines.itemId)),
        leftOuterJoin(
          itemBatches,
          itemBatches.id.equalsExp(deliveryOrderLines.batchId),
        ),
      ])
      ..orderBy([
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(itemBatches.batchNo),
      ]);
  }

  List<DeliveryOrderLineWithDetails> _mapLines(List<TypedResult> rows) {
    return rows
        .map(
          (row) => DeliveryOrderLineWithDetails(
            line: row.readTable(deliveryOrderLines),
            prLine: row.readTable(purchaseRequestLines),
            item: row.readTable(items),
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Future<List<DeliveryOrderLineWithDetails>> detailLines(String doId) async =>
      _mapLines(await _detailLinesQuery(doId).get());

  Stream<List<DeliveryOrderLineWithDetails>> watchDetailLines(String doId) =>
      _detailLinesQuery(doId).watch().map(_mapLines);

  // --- summaries ------------------------------------------------------------

  late final $UsersTable _preparers = alias(users, 'prepared_by_user');
  late final $UsersTable _shippers = alias(users, 'shipped_by_user');
  late final $UsersTable _requesters = alias(users, 'requested_by_user');

  Expression<int> get _lineCount => deliveryOrderLines.id.count(
    distinct: true,
    filter: deliveryOrderLines.deletedAt.isNull(),
  );

  JoinedSelectStatement<HasResultSet, dynamic> _summaryQuery(
    Expression<bool> predicate,
  ) {
    final query = (select(deliveryOrders)..where((t) => t.deletedAt.isNull()))
        .join([
          innerJoin(
            purchaseRequests,
            purchaseRequests.id.equalsExp(deliveryOrders.prId),
          ),
          innerJoin(branches, branches.id.equalsExp(purchaseRequests.branchId)),
          innerJoin(
            _preparers,
            _preparers.id.equalsExp(deliveryOrders.preparedBy),
          ),
          innerJoin(
            _requesters,
            _requesters.id.equalsExp(purchaseRequests.requestedBy),
          ),
          leftOuterJoin(
            _shippers,
            _shippers.id.equalsExp(deliveryOrders.shippedBy),
          ),
          // Left join so a document with no allocations yet still produces a
          // row, and soft-deleted lines never inflate the count.
          leftOuterJoin(
            deliveryOrderLines,
            deliveryOrderLines.doId.equalsExp(deliveryOrders.id) &
                deliveryOrderLines.deletedAt.isNull(),
          ),
        ]);

    return query
      ..addColumns([_lineCount])
      ..where(predicate)
      ..groupBy([deliveryOrders.id])
      ..orderBy([OrderingTerm.desc(deliveryOrders.createdAt)]);
  }

  List<DeliveryOrderWithContext> _mapSummaries(List<TypedResult> rows) {
    return rows
        .map(
          (row) => DeliveryOrderWithContext(
            order: row.readTable(deliveryOrders),
            request: row.readTable(purchaseRequests),
            branch: row.readTable(branches),
            preparedBy: row.readTable(_preparers),
            requestedBy: row.readTable(_requesters),
            shippedBy: row.readTableOrNull(_shippers),
            lineCount: row.read(_lineCount) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  /// The document predicate, optionally pinned to one branch and one status set.
  ///
  /// Both checks happen **inside the statement**, so a document outside them is
  /// never read, never mapped and never reaches a stream a widget could be
  /// listening to. Filtering the result in Dart would look equivalent and would
  /// not be.
  Expression<bool> _document(
    String doId,
    String? branchId,
    Set<DeliveryOrderStatus> statuses,
  ) {
    var predicate = deliveryOrders.id.equals(doId);
    if (branchId != null) {
      predicate = predicate & purchaseRequests.branchId.equals(branchId);
    }
    if (statuses.isNotEmpty) {
      predicate =
          predicate &
          deliveryOrders.status.isIn(
            statuses.map((status) => status.dbValue).toList(growable: false),
          );
    }
    return predicate;
  }

  Future<DeliveryOrderWithContext?> summaryById(
    String doId, {
    String? branchId,
    Set<DeliveryOrderStatus> statuses = const {},
  }) async {
    final rows = await _summaryQuery(_document(doId, branchId, statuses)).get();
    return rows.isEmpty ? null : _mapSummaries(rows).single;
  }

  Stream<DeliveryOrderWithContext?> watchSummaryById(
    String doId, {
    String? branchId,
    Set<DeliveryOrderStatus> statuses = const {},
  }) {
    return _summaryQuery(
      _document(doId, branchId, statuses),
    ).watch().map((rows) => rows.isEmpty ? null : _mapSummaries(rows).single);
  }

  Expression<bool> _scope({
    String? branchId,
    Set<DeliveryOrderStatus> statuses = const {},
    String? searchQuery,
  }) {
    var predicate = const Constant(true) as Expression<bool>;
    if (branchId != null) {
      predicate = predicate & purchaseRequests.branchId.equals(branchId);
    }
    if (statuses.isNotEmpty) {
      predicate =
          predicate &
          deliveryOrders.status.isIn(
            statuses.map((status) => status.dbValue).toList(growable: false),
          );
    }
    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      // Delivery Order number, Purchase Request number, branch name or a
      // shipped item, case-insensitive and entirely local so the warehouse keeps
      // searching offline (G-Y1).
      final pattern = '%$needle%';
      predicate =
          predicate &
          (deliveryOrders.docNumber.lower().like(pattern) |
              purchaseRequests.docNumber.lower().like(pattern) |
              branches.name.lower().like(pattern) |
              branches.code.lower().like(pattern) |
              _shipsMatchingItem(pattern));
    }
    return predicate;
  }

  /// Whether a document allocates an item whose name or SKU matches [pattern].
  ///
  /// Two single-column subqueries rather than a join, because the summary query
  /// already left-joins `delivery_order_lines` to count them: adding `items` to
  /// that join would make the `WHERE` filter away the very rows the count is
  /// derived from, and a document found by its number would then report only its
  /// matching lines.
  Expression<bool> _shipsMatchingItem(String pattern) {
    final matchingItems = selectOnly(items)
      ..addColumns([items.id])
      ..where(
        items.name.lower().like(pattern) | items.sku.lower().like(pattern),
      );

    final matchingOrders = selectOnly(deliveryOrderLines)
      ..addColumns([deliveryOrderLines.doId])
      ..where(
        deliveryOrderLines.deletedAt.isNull() &
            deliveryOrderLines.itemId.isInQuery(matchingItems),
      );

    return deliveryOrders.id.isInQuery(matchingOrders);
  }

  Future<List<DeliveryOrderWithContext>> listOrders({
    String? branchId,
    Set<DeliveryOrderStatus> statuses = const {},
    String? searchQuery,
  }) async {
    final rows = await _summaryQuery(
      _scope(branchId: branchId, statuses: statuses, searchQuery: searchQuery),
    ).get();
    return _mapSummaries(rows);
  }

  Stream<List<DeliveryOrderWithContext>> watchOrders({
    String? branchId,
    Set<DeliveryOrderStatus> statuses = const {},
    String? searchQuery,
  }) {
    return _summaryQuery(
      _scope(branchId: branchId, statuses: statuses, searchQuery: searchQuery),
    ).watch().map(_mapSummaries);
  }

  /// Every Delivery Order raised against one Purchase Request, newest first.
  ///
  /// A list rather than a single row, because one request may ship in parts
  /// (spec §2.3) and the progress the form shows is the sum over all of them.
  Future<List<DeliveryOrderWithContext>> ordersOfPurchaseRequest(
    String prId, {
    Set<DeliveryOrderStatus> statuses = const {},
  }) async {
    var predicate = deliveryOrders.prId.equals(prId);
    if (statuses.isNotEmpty) {
      predicate =
          predicate &
          deliveryOrders.status.isIn(
            statuses.map((status) => status.dbValue).toList(growable: false),
          );
    }
    return _mapSummaries(await _summaryQuery(predicate).get());
  }

  Stream<List<DeliveryOrderWithContext>> watchOrdersOfPurchaseRequest(
    String prId,
  ) => _summaryQuery(
    deliveryOrders.prId.equals(prId),
  ).watch().map(_mapSummaries);
}
