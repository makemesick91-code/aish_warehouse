import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/distribution_tables.dart';
import '../tables/inventory_tables.dart';
import '../tables/master_tables.dart';

part 'distribution_dao.g.dart';

/// A Distribusi header joined with everything a list row or a detail header
/// needs, plus the per-document counts a summary shows.
///
/// None of the joins filter `is_active` or `deleted_at`, which is what keeps a
/// posted distribution readable after its branch or the branch head who
/// distributed is retired. The repository turns that into `…IsHistorical` flags
/// the screens can label rather than into a row that quietly disappears.
class DistributionWithContext {
  const DistributionWithContext({
    required this.distribution,
    required this.branch,
    required this.distributedBy,
    required this.lineCount,
    required this.roomCount,
    required this.overrideCount,
  });

  final DistributionRow distribution;
  final Branch branch;
  final AppUser distributedBy;

  final int lineCount;

  /// Distinct rooms the document targets (G-T3).
  final int roomCount;

  /// Lines carrying a FEFO override reason (G-E3).
  final int overrideCount;
}

/// The four facts an authorization check needs, and nothing else.
///
/// Deliberately not the joined summary: deciding whether a distribution may be
/// shown must not be the reason its number, its rooms, its items, its batches or
/// its quantities are read.
class DistributionAccessRow {
  const DistributionAccessRow({
    required this.distributionId,
    required this.branchId,
    required this.distributedBy,
    required this.status,
  });

  final String distributionId;
  final String branchId;
  final String distributedBy;
  final DistributionStatus status;
}

/// One distribution line joined with its room, its item and — when the item is
/// batch-tracked — its batch.
class DistributionLineWithDetails {
  const DistributionLineWithDetails({
    required this.line,
    required this.room,
    required this.item,
    this.batch,
  });

  final DistributionLineRow line;
  final Room room;
  final Item item;
  final ItemBatch? batch;
}

/// One balance row of the branch store, joined with its item and batch.
///
/// The input the item picker, the FEFO allocator and the posting revalidation all
/// work from. Expiry is deliberately **not** filtered here: the picker has to be
/// able to explain why a batch cannot be chosen, and comparing `expiry_date` in
/// SQL would be a lexical comparison of ISO-8601 TEXT — the trap schema v4 removed
/// from `stock_opnames`. `DistributionExpiryPolicy` decides usability, in Dart, on
/// civil dates.
class BranchStoreStockRow {
  const BranchStoreStockRow({
    required this.item,
    required this.qtyOnHandMilliUnits,
    this.batch,
  });

  final Item item;

  /// Milli-units (Q-3); the repository converts.
  final int qtyOnHandMilliUnits;
  final ItemBatch? batch;
}

/// Distribusi persistence.
///
/// The same absences that shape [OpnameDao], [PurchaseRequestDao],
/// [DeliveryOrderDao] and [GoodReceiptDao] shape this one, and for the same
/// reasons:
///
/// * **No unrestricted status writer.** There is no `setStatus`. The one
///   transition this milestone opens — `draft → posted` — has its own method that
///   names the status it expects to move *from*, so the predicate travels into the
///   same statement as the write and a stale screen or a racing device cannot post
///   a distribution twice (G-S1). Every guarded write returns the number of
///   affected rows; zero means the guard fired.
/// * **No unrestricted line writer.** A line can only be changed while its parent
///   is `draft`, checked inside the statement rather than before it. And no writer
///   here reaches `distribution_id`, `room_id` or `item_id`: moving a position to
///   another room or another item is a different position, and it is done by
///   removing the line and adding the right one — both validated.
/// * **No hard delete.** Nothing here removes a row (G-A5). A draft line is soft
///   deleted; a posted document cannot be touched by any method on this class.
/// * **No source or destination location input.** The store the goods leave and
///   the room location they enter are resolved from the branch and the room by
///   type (§14), so no caller — screen included — can nominate a location. That is
///   the database half of G-T1: there is no column to write and no parameter to
///   pass.
/// * **No balance writer.** Stock changes only through `StockPostingService`, and
///   a DAO that could also decrement a balance would be a second way into the
///   ledger.
///
/// Like the other DAOs this is a milli-unit layer (Q-4): `qty` and `qty_on_hand`
/// are INTEGER columns holding `unit * 1000`, and the repository above converts
/// them to `Quantity`.
@DriftAccessor(
  tables: [
    Distributions,
    DistributionLines,
    StockBalances,
    Items,
    ItemBatches,
    Rooms,
    Branches,
    Users,
    StockLocations,
  ],
)
class DistributionDao extends DatabaseAccessor<AppDatabase>
    with _$DistributionDaoMixin {
  DistributionDao(super.db);

  /// Runs [action] in one transaction.
  ///
  /// The posting owns exactly one of these, and every write it performs — the
  /// ledger movements, the source and destination balance updates, the document
  /// status and its timestamp — happens inside it. Nothing below opens a
  /// transaction of its own for a single line or a single room, because a failure
  /// on the last movement must roll the first one back (G-T4).
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      transaction(action);

  // --- writes ---------------------------------------------------------------

  Future<DistributionRow> insertHeader(DistributionsCompanion header) =>
      into(distributions).insertReturning(header);

  /// Inserts a whole allocation at once.
  ///
  /// A batch insert rather than a loop, because a FEFO allocation that spans three
  /// batches is one decision: either all three rows land or none does, and a
  /// partially stored allocation would silently distribute less than the branch
  /// head asked for.
  Future<void> insertLines(List<DistributionLinesCompanion> lines) async {
    if (lines.isEmpty) return;
    await batch((b) => b.insertAll(distributionLines, lines));
  }

  /// Updates the header note of a **draft**.
  ///
  /// The status predicate is in the statement, so a note cannot be appended to a
  /// posted document however stale the screen that tried.
  Future<int> updateDraftNote({
    required String distributionId,
    required String? note,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE distributions '
      'SET note = ?, updated_at = ?, sync_status = ? '
      "WHERE id = ? AND status = 'draft' AND deleted_at IS NULL;",
      variables: [
        if (note == null)
          const Variable<String>(null)
        else
          Variable<String>(note),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(distributionId),
      ],
      updates: {distributions},
      updateKind: UpdateKind.update,
    );
  }

  /// Changes the quantity, the batch and the FEFO reason of one **draft** line.
  ///
  /// Four predicates travel into the statement, and each is a rule rather than a
  /// convenience: the line must belong to [distributionId], its parent must still
  /// be `draft`, neither row may be soft-deleted, and the quantity must be
  /// strictly positive — expressed as `? > 0` in SQL rather than trusted from the
  /// caller, so a stale screen cannot store a zero even if the domain check were
  /// somehow skipped.
  ///
  /// `room_id` and `item_id` are deliberately out of reach: a position for another
  /// room or another item is a *different* position, and changing one in place
  /// would slip past the room/branch validation the add path performs. Moving an
  /// item between rooms is remove-then-add.
  Future<int> updateDraftLine({
    required String distributionId,
    required String lineId,
    required int qtyMilliUnits,
    required String? batchId,
    required String? fefoOverrideReason,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE distribution_lines '
      'SET qty = ?, batch_id = ?, fefo_override_reason = ?, '
      '    updated_at = ?, sync_status = ? '
      'WHERE id = ? AND distribution_id = ? AND deleted_at IS NULL '
      '  AND ? > 0 '
      '  AND distribution_id IN ('
      '    SELECT id FROM distributions '
      "    WHERE status = 'draft' AND deleted_at IS NULL"
      '  );',
      variables: [
        Variable<int>(qtyMilliUnits),
        if (batchId == null)
          const Variable<String>(null)
        else
          Variable<String>(batchId),
        if (fefoOverrideReason == null)
          const Variable<String>(null)
        else
          Variable<String>(fefoOverrideReason),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
        Variable<String>(distributionId),
        Variable<int>(qtyMilliUnits),
      ],
      updates: {distributionLines},
      updateKind: UpdateKind.update,
    );
  }

  /// Soft-deletes one **draft** line (G-A5).
  ///
  /// Guarded on the parent's status inside the same statement, so a line cannot be
  /// removed from a document that has already posted — which would leave the
  /// ledger describing a movement the document no longer admits to.
  Future<int> softDeleteDraftLine({
    required String distributionId,
    required String lineId,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE distribution_lines '
      'SET deleted_at = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND distribution_id = ? AND deleted_at IS NULL '
      '  AND distribution_id IN ('
      '    SELECT id FROM distributions '
      "    WHERE status = 'draft' AND deleted_at IS NULL"
      '  );',
      variables: [
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
        Variable<String>(distributionId),
      ],
      updates: {distributionLines},
      updateKind: UpdateKind.update,
    );
  }

  /// `draft → posted`.
  ///
  /// Two predicates make a double post impossible: `status = 'draft'` and — in the
  /// same statement — `EXISTS` at least one live line. The second is the "a
  /// distribution with nothing in it moves nothing" rule enforced at the moment of
  /// the write rather than at the moment of the read, which is what a second
  /// device removing the last line in between would otherwise defeat. A return
  /// value of 0 means one of them fired, and the caller rolls the whole
  /// transaction — ledger movements included — back.
  ///
  /// The instant is forced to UTC here rather than trusted from the caller (T-1),
  /// because drift serialises a non-UTC `DateTime` with an offset suffix and a
  /// value that arrived in operational time would be *stored* as a different
  /// instant than the one the domain validated.
  Future<int> markPosted({
    required String distributionId,
    required DateTime postedAtUtc,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE distributions '
      'SET status = ?, posted_at = ?, updated_at = ?, sync_status = ? '
      "WHERE id = ? AND status = 'draft' AND deleted_at IS NULL "
      '  AND EXISTS ('
      '    SELECT 1 FROM distribution_lines '
      '    WHERE distribution_id = distributions.id AND deleted_at IS NULL'
      '  );',
      variables: [
        Variable<String>(DistributionStatus.posted.dbValue),
        Variable<DateTime>(postedAtUtc.toUtc()),
        Variable<DateTime>(now),
        // Once the document leaves the device it is the server's to confirm
        // (G-Y2), so every transition queues a sync.
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(distributionId),
      ],
      updates: {distributions},
      updateKind: UpdateKind.update,
    );
  }

  // --- plain reads (no join can hide a row) ----------------------------------

  Future<DistributionRow?> headerById(String id) => (select(
    distributions,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// Live lines of one document, without any join.
  ///
  /// A join can hide a row whose room, item or batch is physically gone; a plain
  /// select cannot. This is the honest inventory the posting path checks the
  /// joined read against, so a corrupt reference is reported instead of silently
  /// reducing the document by one line (§22).
  Future<List<DistributionLineRow>> linesOf(String distributionId) =>
      (select(distributionLines)..where(
            (t) =>
                t.distributionId.equals(distributionId) & t.deletedAt.isNull(),
          ))
          .get();

  Future<DistributionLineRow?> lineById(String id) => (select(
    distributionLines,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// The ids of every live line of one document — one column, no join (§22).
  Future<List<String>> lineIdsOf(String distributionId) =>
      _lineColumn(distributionId, distributionLines.id);

  /// The distinct room ids of one document.
  Future<List<String>> lineRoomIdsOf(String distributionId) =>
      _lineColumn(distributionId, distributionLines.roomId, distinct: true);

  /// The distinct item ids of one document.
  Future<List<String>> lineItemIdsOf(String distributionId) =>
      _lineColumn(distributionId, distributionLines.itemId, distinct: true);

  /// The distinct, non-null batch ids of one document.
  ///
  /// NULLs are dropped rather than returned as such: an item without expiry has no
  /// batch to verify, and the caller's set comparison is about rows that must
  /// resolve.
  Future<List<String>> lineBatchIdsOf(String distributionId) async {
    final query = selectOnly(distributionLines, distinct: true)
      ..addColumns([distributionLines.batchId])
      ..where(
        distributionLines.distributionId.equals(distributionId) &
            distributionLines.deletedAt.isNull() &
            distributionLines.batchId.isNotNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.read(distributionLines.batchId))
        .whereType<String>()
        .toList(growable: false);
  }

  Future<List<String>> _lineColumn(
    String distributionId,
    GeneratedColumn<String> column, {
    bool distinct = false,
  }) async {
    final query = selectOnly(distributionLines, distinct: distinct)
      ..addColumns([column])
      ..where(
        distributionLines.distributionId.equals(distributionId) &
            distributionLines.deletedAt.isNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.read(column))
        .whereType<String>()
        .toList(growable: false);
  }

  /// The facts that decide whether somebody may open this distribution.
  ///
  /// No join at all: `branch_id` lives on the header, so the branch predicate is a
  /// single-table `WHERE`. When [branchId] is supplied it is in the statement, so a
  /// document belonging to another branch never leaves SQLite and the caller cannot
  /// leak what it never received. [statuses] narrows the same way.
  ///
  /// Returns `null` both for "no such distribution" and for "not yours", and that
  /// ambiguity is the point: telling them apart would turn the address bar into a
  /// way to enumerate documents across the clinic group.
  Future<DistributionAccessRow?> accessScope({
    required String distributionId,
    String? branchId,
    Set<DistributionStatus> statuses = const {},
  }) async {
    final query = selectOnly(distributions)
      ..addColumns([
        distributions.id,
        distributions.branchId,
        distributions.distributedBy,
        distributions.status,
      ])
      ..where(
        distributions.id.equals(distributionId) &
            distributions.deletedAt.isNull() &
            (branchId == null
                ? const Constant(true)
                : distributions.branchId.equals(branchId)) &
            (statuses.isEmpty
                ? const Constant(true)
                : distributions.status.isIn(
                    statuses
                        .map((status) => status.dbValue)
                        .toList(growable: false),
                  )),
      );

    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return DistributionAccessRow(
      distributionId: row.read(distributions.id)!,
      branchId: row.read(distributions.branchId)!,
      distributedBy: row.read(distributions.distributedBy)!,
      status: row.readWithConverter(distributions.status)!,
    );
  }

  // --- joined line reads ----------------------------------------------------

  JoinedSelectStatement<HasResultSet, dynamic> _detailLinesQuery(
    String distributionId,
  ) {
    return (select(distributionLines)..where(
          (t) => t.distributionId.equals(distributionId) & t.deletedAt.isNull(),
        ))
        .join([
          // No `is_active` and no `deleted_at` filter on the master joins: a
          // posted distribution whose room or item was withdrawn afterwards must
          // stay readable, and the repository labels it instead of hiding it
          // (§32).
          innerJoin(rooms, rooms.id.equalsExp(distributionLines.roomId)),
          innerJoin(items, items.id.equalsExp(distributionLines.itemId)),
          leftOuterJoin(
            itemBatches,
            itemBatches.id.equalsExp(distributionLines.batchId),
          ),
        ])
      ..orderBy([
        OrderingTerm.asc(rooms.code),
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(itemBatches.batchNo),
      ]);
  }

  List<DistributionLineWithDetails> _mapLines(List<TypedResult> rows) {
    return rows
        .map(
          (row) => DistributionLineWithDetails(
            line: row.readTable(distributionLines),
            room: row.readTable(rooms),
            item: row.readTable(items),
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Future<List<DistributionLineWithDetails>> detailLines(
    String distributionId,
  ) async => _mapLines(await _detailLinesQuery(distributionId).get());

  Stream<List<DistributionLineWithDetails>> watchDetailLines(
    String distributionId,
  ) => _detailLinesQuery(distributionId).watch().map(_mapLines);

  // --- summaries ------------------------------------------------------------

  Expression<int> get _lineCount => distributionLines.id.count(
    distinct: true,
    filter: distributionLines.deletedAt.isNull(),
  );

  Expression<int> get _roomCount => distributionLines.roomId.count(
    distinct: true,
    filter: distributionLines.deletedAt.isNull(),
  );

  Expression<int> get _overrideCount => distributionLines.id.count(
    distinct: true,
    filter:
        distributionLines.deletedAt.isNull() &
        distributionLines.fefoOverrideReason.isNotNull(),
  );

  JoinedSelectStatement<HasResultSet, dynamic> _summaryQuery(
    Expression<bool> predicate,
  ) {
    final query = (select(distributions)..where((t) => t.deletedAt.isNull()))
        .join([
          innerJoin(branches, branches.id.equalsExp(distributions.branchId)),
          innerJoin(users, users.id.equalsExp(distributions.distributedBy)),
          // Left join so a draft with no lines yet still produces a row, and
          // soft-deleted lines never inflate the counts.
          leftOuterJoin(
            distributionLines,
            distributionLines.distributionId.equalsExp(distributions.id) &
                distributionLines.deletedAt.isNull(),
          ),
        ]);

    return query
      ..addColumns([_lineCount, _roomCount, _overrideCount])
      ..where(predicate)
      ..groupBy([distributions.id])
      ..orderBy([OrderingTerm.desc(distributions.createdAt)]);
  }

  List<DistributionWithContext> _mapSummaries(List<TypedResult> rows) {
    return rows
        .map(
          (row) => DistributionWithContext(
            distribution: row.readTable(distributions),
            branch: row.readTable(branches),
            distributedBy: row.readTable(users),
            lineCount: row.read(_lineCount) ?? 0,
            roomCount: row.read(_roomCount) ?? 0,
            overrideCount: row.read(_overrideCount) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  /// The document predicate, optionally pinned to one branch and one status set.
  ///
  /// Both checks happen **inside the statement**, so a distribution outside them is
  /// never read, never mapped and never reaches a stream a widget could be
  /// listening to. Filtering the result in Dart would look equivalent and would
  /// not be.
  Expression<bool> _document(
    String distributionId,
    String? branchId,
    Set<DistributionStatus> statuses,
  ) {
    var predicate = distributions.id.equals(distributionId);
    if (branchId != null) {
      predicate = predicate & distributions.branchId.equals(branchId);
    }
    if (statuses.isNotEmpty) {
      predicate =
          predicate &
          distributions.status.isIn(
            statuses.map((status) => status.dbValue).toList(growable: false),
          );
    }
    return predicate;
  }

  Future<DistributionWithContext?> summaryById(
    String distributionId, {
    String? branchId,
    Set<DistributionStatus> statuses = const {},
  }) async {
    final rows = await _summaryQuery(
      _document(distributionId, branchId, statuses),
    ).get();
    return rows.isEmpty ? null : _mapSummaries(rows).single;
  }

  Stream<DistributionWithContext?> watchSummaryById(
    String distributionId, {
    String? branchId,
    Set<DistributionStatus> statuses = const {},
  }) {
    return _summaryQuery(
      _document(distributionId, branchId, statuses),
    ).watch().map((rows) => rows.isEmpty ? null : _mapSummaries(rows).single);
  }

  Expression<bool> _scope({
    String? branchId,
    Set<DistributionStatus> statuses = const {},
    String? searchQuery,
  }) {
    var predicate = const Constant(true) as Expression<bool>;
    if (branchId != null) {
      predicate = predicate & distributions.branchId.equals(branchId);
    }
    if (statuses.isNotEmpty) {
      predicate =
          predicate &
          distributions.status.isIn(
            statuses.map((status) => status.dbValue).toList(growable: false),
          );
    }
    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      // Document number, branch, a targeted room or a distributed item —
      // case-insensitive and entirely local, so the clinic keeps searching
      // offline (G-Y1).
      final pattern = '%$needle%';
      predicate =
          predicate &
          (distributions.docNumber.lower().like(pattern) |
              branches.name.lower().like(pattern) |
              branches.code.lower().like(pattern) |
              _distributesMatchingRoom(pattern) |
              _distributesMatchingItem(pattern));
    }
    return predicate;
  }

  /// Whether a document carries a line whose room name or code matches [pattern].
  ///
  /// A subquery rather than a join, because the summary query already left-joins
  /// `distribution_lines` to count them: adding `rooms` to that join would make the
  /// `WHERE` filter away the very rows the counts are derived from, and a document
  /// found by its number would then report only its matching lines.
  Expression<bool> _distributesMatchingRoom(String pattern) {
    final matchingRooms = selectOnly(rooms)
      ..addColumns([rooms.id])
      ..where(
        rooms.name.lower().like(pattern) | rooms.code.lower().like(pattern),
      );

    final matching = selectOnly(distributionLines)
      ..addColumns([distributionLines.distributionId])
      ..where(
        distributionLines.deletedAt.isNull() &
            distributionLines.roomId.isInQuery(matchingRooms),
      );

    return distributions.id.isInQuery(matching);
  }

  /// Whether a document carries an item whose name or SKU matches [pattern].
  Expression<bool> _distributesMatchingItem(String pattern) {
    final matchingItems = selectOnly(items)
      ..addColumns([items.id])
      ..where(
        items.name.lower().like(pattern) | items.sku.lower().like(pattern),
      );

    final matching = selectOnly(distributionLines)
      ..addColumns([distributionLines.distributionId])
      ..where(
        distributionLines.deletedAt.isNull() &
            distributionLines.itemId.isInQuery(matchingItems),
      );

    return distributions.id.isInQuery(matching);
  }

  Future<List<DistributionWithContext>> listDistributions({
    String? branchId,
    Set<DistributionStatus> statuses = const {},
    String? searchQuery,
  }) async {
    final rows = await _summaryQuery(
      _scope(branchId: branchId, statuses: statuses, searchQuery: searchQuery),
    ).get();
    return _mapSummaries(rows);
  }

  Stream<List<DistributionWithContext>> watchDistributions({
    String? branchId,
    Set<DistributionStatus> statuses = const {},
    String? searchQuery,
  }) {
    return _summaryQuery(
      _scope(branchId: branchId, statuses: statuses, searchQuery: searchQuery),
    ).watch().map(_mapSummaries);
  }

  // --- rooms and locations --------------------------------------------------

  /// Every live, active room of one branch, ordered by code.
  ///
  /// The room chips on the form are built from this rather than from a hard-coded
  /// `R1 / R2 / R3`: spec §2.1 makes rooms master data managed by the Super Admin,
  /// and a branch with four rooms must show four chips.
  Future<List<Room>> activeRoomsOfBranch(String branchId) =>
      (select(rooms)
            ..where(
              (t) =>
                  t.branchId.equals(branchId) &
                  t.isActive.equals(true) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .get();

  Stream<List<Room>> watchActiveRoomsOfBranch(String branchId) =>
      (select(rooms)
            ..where(
              (t) =>
                  t.branchId.equals(branchId) &
                  t.isActive.equals(true) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .watch();

  /// One room by id, soft-deleted rows included — for reading a posted document
  /// whose room was archived afterwards (§32).
  Future<Room?> roomById(String id) =>
      (select(rooms)..where((t) => t.id.equals(id))).getSingleOrNull();

  // --- branch-store stock ---------------------------------------------------

  /// Positive branch-store balances of one branch, joined with item and batch.
  ///
  /// `positive only` is in the SQL because a zero balance is not stock the picker
  /// may offer (§15). Expiry is **not**: `DistributionExpiryPolicy` decides that in
  /// Dart on civil dates, because `expiry_date` is ISO-8601 TEXT and a SQL
  /// comparison would be lexical.
  ///
  /// [searchQuery] matches item name or SKU, case-insensitively and entirely
  /// locally (G-Y1). [categoryId] follows the active category chip. Neither is
  /// applied with a row `LIMIT`: an item's total is the sum over its batches, and
  /// cutting the row set off mid-item would misreport it. The caller caps the
  /// number of *items* after grouping.
  Future<List<BranchStoreStockRow>> branchStoreStock({
    required String locationId,
    String? itemId,
    String? searchQuery,
    String? categoryId,
    bool activeItemsOnly = true,
  }) async {
    final rows = await _branchStoreStockQuery(
      locationId: locationId,
      itemId: itemId,
      searchQuery: searchQuery,
      categoryId: categoryId,
      activeItemsOnly: activeItemsOnly,
    ).get();
    return _mapStock(rows);
  }

  Stream<List<BranchStoreStockRow>> watchBranchStoreStock({
    required String locationId,
    String? itemId,
    String? searchQuery,
    String? categoryId,
    bool activeItemsOnly = true,
  }) => _branchStoreStockQuery(
    locationId: locationId,
    itemId: itemId,
    searchQuery: searchQuery,
    categoryId: categoryId,
    activeItemsOnly: activeItemsOnly,
  ).watch().map(_mapStock);

  JoinedSelectStatement<HasResultSet, dynamic> _branchStoreStockQuery({
    required String locationId,
    String? itemId,
    String? searchQuery,
    String? categoryId,
    required bool activeItemsOnly,
  }) {
    var predicate =
        stockBalances.locationId.equals(locationId) &
        stockBalances.deletedAt.isNull() &
        stockBalances.qtyOnHand.isBiggerThanValue(0);

    if (itemId != null) {
      predicate = predicate & stockBalances.itemId.equals(itemId);
    }
    if (activeItemsOnly) {
      // Adding a line is *new* work, so master data that has been withdrawn may
      // not be picked (G-A4). A document already holding such a line keeps it —
      // that read goes through `detailLines`, which filters neither flag.
      predicate =
          predicate & items.isActive.equals(true) & items.deletedAt.isNull();
    }
    if (categoryId != null) {
      predicate = predicate & items.categoryId.equals(categoryId);
    }
    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      final pattern = '%$needle%';
      predicate =
          predicate &
          (items.name.lower().like(pattern) | items.sku.lower().like(pattern));
    }

    return select(stockBalances).join([
        innerJoin(items, items.id.equalsExp(stockBalances.itemId)),
        leftOuterJoin(
          itemBatches,
          itemBatches.id.equalsExp(stockBalances.batchId),
        ),
      ])
      ..where(predicate)
      // The canonical FEFO order, so an in-memory allocation over these rows is
      // identical on two devices holding the same stock (G-E3).
      ..orderBy([
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(itemBatches.batchNo),
        OrderingTerm.asc(itemBatches.id),
      ]);
  }

  List<BranchStoreStockRow> _mapStock(List<TypedResult> rows) {
    return rows
        .map(
          (row) => BranchStoreStockRow(
            item: row.readTable(items),
            qtyOnHandMilliUnits: row.readTable(stockBalances).qtyOnHand,
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }
}
