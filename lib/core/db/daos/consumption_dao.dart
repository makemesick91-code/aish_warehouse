import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/consumption_tables.dart';
import '../tables/inventory_tables.dart';
import '../tables/master_tables.dart';

part 'consumption_dao.g.dart';

/// A Pemakaian header joined with everything a list row or a detail header needs,
/// plus the per-document counts a summary shows.
///
/// None of the joins filter `is_active` or `deleted_at`, which is what keeps a posted
/// consumption readable after its branch, its room or the nurse who posted it is
/// retired. The repository turns that into `…IsHistorical` flags the screens can label
/// rather than into a row that quietly disappears (§33).
class ConsumptionWithContext {
  const ConsumptionWithContext({
    required this.consumption,
    required this.branch,
    required this.room,
    required this.createdBy,
    this.postedBy,
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
  });

  final ConsumptionRow consumption;

  /// Always present — the foreign key guarantees the row exists, and the join filters
  /// nothing.
  final Branch branch;

  /// The room the goods were used in. Always present, for the same reason.
  final Room room;

  final AppUser createdBy;

  /// `null` exactly while the document is a draft.
  final AppUser? postedBy;

  final int lineCount;
  final int itemCount;

  /// Distinct batches. An item without expiry contributes none, so this can be lower
  /// than [lineCount] on a compliant document.
  final int batchCount;
}

/// The four facts an authorization check needs, and nothing else.
///
/// Deliberately not the joined summary: deciding whether a consumption may be shown
/// must not be the reason its number, its room, its items, its batches, its
/// quantities or its note are read.
class ConsumptionAccessRow {
  const ConsumptionAccessRow({
    required this.consumptionId,
    required this.branchId,
    required this.roomId,
    required this.createdBy,
    required this.status,
  });

  final String consumptionId;
  final String branchId;
  final String roomId;
  final String createdBy;
  final ConsumptionStatus status;
}

/// One consumption line joined with its item and, when it has one, its batch.
///
/// `batch` is nullable because `consumption_lines.batch_id` is: an item without an
/// expiry date is consumed without one (G-E2).
class ConsumptionLineWithDetails {
  const ConsumptionLineWithDetails({
    required this.line,
    required this.item,
    this.batch,
  });

  final ConsumptionLineRow line;
  final Item item;
  final ItemBatch? batch;
}

/// One balance row of a room, joined with its item and — when it has one — its batch.
///
/// The input the candidate picker and the posting revalidation both work from. Expiry
/// is deliberately **not** filtered here: `expiry_date` is ISO-8601 TEXT
/// (`build.yaml`), so a SQL comparison against "now" would compare characters rather
/// than dates — the trap schema v4 removed from `stock_opnames`.
/// `ConsumptionExpiryPolicy` decides eligibility, in Dart, on civil dates.
class RoomBatchStockRow {
  const RoomBatchStockRow({
    required this.item,
    required this.qtyOnHandMilliUnits,
    this.batch,
  });

  final Item item;

  /// Milli-units (Q-3); the repository converts.
  final int qtyOnHandMilliUnits;

  /// `null` for an item without expiry.
  final ItemBatch? batch;
}

/// Pemakaian persistence (schema v10, §23).
///
/// The same absences that shape [OpnameDao], [PurchaseRequestDao],
/// [DeliveryOrderDao], [GoodReceiptDao], [DistributionDao] and [DisposalDao] shape
/// this one, and for the same reasons:
///
/// * **No unrestricted status writer.** There is no `setStatus`. The one transition
///   this milestone opens — `draft → posted` — has its own method that names the
///   status it expects to move *from* **and** the creator it expects to belong to, so
///   both predicates travel into the same statement as the write and a stale screen
///   or a racing device cannot post a consumption twice (G-S1). Every guarded write
///   returns the number of affected rows; zero means the guard fired.
/// * **No un-post and no reopen.** `posted` has no outgoing transition at all, so
///   there is no method that could express one.
/// * **No unrestricted line writer.** A line can only be changed while its parent is
///   `draft` *and* belongs to the acting nurse, checked inside the statement rather
///   than before it. And no writer here reaches `consumption_id`, `item_id` or
///   `batch_id`: a different batch is a *different* position with its own expiry date
///   and its own balance, and changing one in place would slip past both checks.
///   Changing a position is remove-then-add, both validated.
/// * **No hard delete.** Nothing here removes a row (G-A5). A draft line is soft
///   deleted; a posted document cannot be touched by any method on this class.
/// * **No room or branch writer.** `room_id` and `branch_id` are set once, by the
///   insert, and there is no statement that updates either. Moving a document to
///   another room would move it into — or out of — somebody else's scope while its
///   lines still described the old room's stock.
/// * **No destination anywhere.** A consumption has no `to_location_id` to write and
///   no parameter to pass one: the goods leave the system (§19).
/// * **No arbitrary location input.** The room's stock location is resolved by type
///   from `room_id` by the caller, so no screen can nominate a warehouse or a branch
///   store as the source. That is the database half of *"consumption is only from a
///   room"*: there is no column to write and no parameter to pass.
/// * **No balance writer.** Stock changes only through `StockPostingService`, and a
///   DAO that could also decrement a balance would be a second way into the ledger.
/// * **No cross-scope read.** Every summary and access read takes a
///   [ConsumptionQueryScope] whose predicate goes into the statement, and the branch
///   scope carries `status = 'posted'` inside it. A branch head's query cannot return
///   a draft even if a caller passed a status set that asked for one.
///
/// Like the other DAOs this is a milli-unit layer (Q-4): `qty` and `qty_on_hand` are
/// INTEGER columns holding `unit * 1000`, and the repository above converts them to
/// `Quantity`.
@DriftAccessor(
  tables: [
    Consumptions,
    ConsumptionLines,
    StockBalances,
    Items,
    ItemBatches,
    Rooms,
    Branches,
    Users,
    StockLocations,
  ],
)
class ConsumptionDao extends DatabaseAccessor<AppDatabase>
    with _$ConsumptionDaoMixin {
  ConsumptionDao(super.db);

  /// Runs [action] in one transaction.
  ///
  /// The posting owns exactly one of these, and every write it performs — the ledger
  /// movements, the room balance updates, the document status, its timestamp and its
  /// posting actor — happens inside it. Nothing below opens a transaction of its own
  /// for a single line, because a failure on the last movement must roll the first
  /// one back (§20).
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      transaction(action);

  // --- writes ---------------------------------------------------------------

  Future<ConsumptionRow> insertHeader(ConsumptionsCompanion header) =>
      into(consumptions).insertReturning(header);

  Future<ConsumptionLineRow> insertLine(ConsumptionLinesCompanion line) =>
      into(consumptionLines).insertReturning(line);

  /// Updates the note of a **draft** the acting nurse created.
  ///
  /// Both predicates are in the statement: `status = 'draft'`, so a note cannot be
  /// rewritten on a posted document however stale the screen that tried, and
  /// `created_by = ?`, so one nurse cannot edit another's draft even if a use-case
  /// check were somehow skipped (§43).
  Future<int> updateOwnDraftNote({
    required String consumptionId,
    required String createdBy,
    required String? note,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE consumptions '
      'SET note = ?, updated_at = ?, sync_status = ? '
      "WHERE id = ? AND created_by = ? AND status = 'draft' "
      '  AND deleted_at IS NULL;',
      variables: [
        if (note == null)
          const Variable<String>(null)
        else
          Variable<String>(note),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(consumptionId),
        Variable<String>(createdBy),
      ],
      updates: {consumptions},
      updateKind: UpdateKind.update,
    );
  }

  /// Changes the quantity and the note of one **draft** line.
  ///
  /// Five predicates travel into the statement, and each is a rule rather than a
  /// convenience: the line must belong to [consumptionId], its parent must still be
  /// `draft` *and* have been created by [createdBy], neither row may be soft-deleted,
  /// and the quantity must be strictly positive — expressed as `? > 0` in SQL rather
  /// than trusted from the caller, so a stale screen cannot store a zero even if the
  /// domain check were somehow skipped.
  ///
  /// `item_id` and `batch_id` are deliberately out of reach: another batch is a
  /// *different* position with its own expiry date and its own balance, and changing
  /// one in place would slip past both checks. Swapping a position is remove-then-add.
  Future<int> updateOwnDraftLine({
    required String consumptionId,
    required String createdBy,
    required String lineId,
    required int qtyMilliUnits,
    required String? note,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE consumption_lines '
      'SET qty = ?, note = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND consumption_id = ? AND deleted_at IS NULL '
      '  AND ? > 0 '
      '  AND consumption_id IN ('
      '    SELECT id FROM consumptions '
      "    WHERE status = 'draft' AND created_by = ? AND deleted_at IS NULL"
      '  );',
      variables: [
        Variable<int>(qtyMilliUnits),
        if (note == null)
          const Variable<String>(null)
        else
          Variable<String>(note),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
        Variable<String>(consumptionId),
        Variable<int>(qtyMilliUnits),
        Variable<String>(createdBy),
      ],
      updates: {consumptionLines},
      updateKind: UpdateKind.update,
    );
  }

  /// Soft-deletes one **draft** line (G-A5).
  ///
  /// Guarded on the parent's status *and* its creator inside the same statement, so a
  /// line cannot be removed from a document that has already posted — which would
  /// leave the ledger describing usage the document no longer admits to — and cannot
  /// be removed from another nurse's draft.
  Future<int> softDeleteOwnDraftLine({
    required String consumptionId,
    required String createdBy,
    required String lineId,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE consumption_lines '
      'SET deleted_at = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND consumption_id = ? AND deleted_at IS NULL '
      '  AND consumption_id IN ('
      '    SELECT id FROM consumptions '
      "    WHERE status = 'draft' AND created_by = ? AND deleted_at IS NULL"
      '  );',
      variables: [
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
        Variable<String>(consumptionId),
        Variable<String>(createdBy),
      ],
      updates: {consumptionLines},
      updateKind: UpdateKind.update,
    );
  }

  /// `draft → posted`.
  ///
  /// Four predicates make a double post — and an empty one, and one driven by the
  /// wrong nurse — impossible at the moment of the write rather than at the moment of
  /// the read:
  ///
  /// * `status = 'draft'`, so a second device cannot post the same document;
  /// * `created_by = ?`, so only the nurse who recorded the usage posts it;
  /// * `deleted_at IS NULL`;
  /// * `EXISTS` at least one live line, so removing the last line in between is
  ///   caught.
  ///
  /// There is deliberately **no** note predicate, unlike the disposal's equivalent: a
  /// consumption note is optional (§8), so requiring one here would refuse compliant
  /// documents.
  ///
  /// A return value of 0 means one of them fired, and the caller rolls the whole
  /// transaction — ledger movements included — back.
  ///
  /// The instant is forced to UTC here rather than trusted from the caller (T-1),
  /// because drift serialises a non-UTC `DateTime` with an offset suffix and a value
  /// that arrived in operational time would be *stored* as a different instant than
  /// the one the domain validated.
  Future<int> markPosted({
    required String consumptionId,
    required String createdBy,
    required DateTime postedAtUtc,
    required String postedBy,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE consumptions '
      'SET status = ?, posted_at = ?, posted_by = ?, updated_at = ?, '
      '    sync_status = ? '
      "WHERE id = ? AND created_by = ? AND status = 'draft' "
      '  AND deleted_at IS NULL '
      '  AND EXISTS ('
      '    SELECT 1 FROM consumption_lines '
      '    WHERE consumption_id = consumptions.id AND deleted_at IS NULL'
      '  );',
      variables: [
        Variable<String>(ConsumptionStatus.posted.dbValue),
        Variable<DateTime>(postedAtUtc.toUtc()),
        Variable<String>(postedBy),
        Variable<DateTime>(now),
        // Once the document leaves the device it is the server's to confirm (G-Y2),
        // so every transition queues a sync.
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(consumptionId),
        Variable<String>(createdBy),
      ],
      updates: {consumptions},
      updateKind: UpdateKind.update,
    );
  }

  // --- plain reads (no join can hide a row) ----------------------------------

  Future<ConsumptionRow?> headerById(String id) => (select(
    consumptions,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// Live lines of one document, without any join.
  ///
  /// A join can hide a row whose item or batch is physically gone; a plain select
  /// cannot. This is the honest inventory the posting path checks the joined read
  /// against, so a corrupt reference is reported instead of silently reducing the
  /// document by one line (§22).
  Future<List<ConsumptionLineRow>> linesOf(String consumptionId) =>
      (select(consumptionLines)..where(
            (t) => t.consumptionId.equals(consumptionId) & t.deletedAt.isNull(),
          ))
          .get();

  Future<ConsumptionLineRow?> lineById(String id) => (select(
    consumptionLines,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// The ids of every live line of one document — one column, no join (§22).
  Future<List<String>> lineIdsOf(String consumptionId) =>
      _lineColumn(consumptionId, consumptionLines.id);

  /// The distinct item ids of one document.
  Future<List<String>> lineItemIdsOf(String consumptionId) =>
      _lineColumn(consumptionId, consumptionLines.itemId, distinct: true);

  /// The distinct **non-null** batch ids of one document.
  ///
  /// A line for an item without expiry contributes none, so this list can be shorter
  /// than [lineIdsOf]'s — which is why the integrity check compares it against the
  /// batched lines only rather than against every line.
  Future<List<String>> lineBatchIdsOf(String consumptionId) async {
    final query = selectOnly(consumptionLines, distinct: true)
      ..addColumns([consumptionLines.batchId])
      ..where(
        consumptionLines.consumptionId.equals(consumptionId) &
            consumptionLines.deletedAt.isNull() &
            consumptionLines.batchId.isNotNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.read(consumptionLines.batchId))
        .whereType<String>()
        .toList(growable: false);
  }

  Future<List<String>> _lineColumn(
    String consumptionId,
    GeneratedColumn<String> column, {
    bool distinct = false,
  }) async {
    final query = selectOnly(consumptionLines, distinct: distinct)
      ..addColumns([column])
      ..where(
        consumptionLines.consumptionId.equals(consumptionId) &
            consumptionLines.deletedAt.isNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.read(column))
        .whereType<String>()
        .toList(growable: false);
  }

  /// The facts that decide whether somebody may open this consumption.
  ///
  /// Five columns and no join at all — the scope predicate needs nothing but
  /// `created_by` and `branch_id`, both of which live on this table. When [scope] is
  /// supplied it is in the statement, so a document outside it never leaves SQLite
  /// and the caller cannot leak what it never received. [statuses] narrows the same
  /// way.
  ///
  /// Returns `null` both for "no such consumption" and for "not yours", and that
  /// ambiguity is the point: telling them apart would turn the address bar into a way
  /// to enumerate documents across the clinic group.
  Future<ConsumptionAccessRow?> accessScope({
    required String consumptionId,
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    Set<ConsumptionStatus> statuses = const {},
  }) async {
    final query = selectOnly(consumptions)
      ..addColumns([
        consumptions.id,
        consumptions.branchId,
        consumptions.roomId,
        consumptions.createdBy,
        consumptions.status,
      ])
      ..where(
        consumptions.id.equals(consumptionId) &
            consumptions.deletedAt.isNull() &
            _scopePredicate(
              scope: scope,
              actorUserId: actorUserId,
              branchId: branchId,
            ) &
            _statusPredicate(statuses),
      );

    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return ConsumptionAccessRow(
      consumptionId: row.read(consumptions.id)!,
      branchId: row.read(consumptions.branchId)!,
      roomId: row.read(consumptions.roomId)!,
      createdBy: row.read(consumptions.createdBy)!,
      status: row.readWithConverter(consumptions.status)!,
    );
  }

  // --- scope ----------------------------------------------------------------

  /// The document scope, expressed as a predicate on `consumptions` itself.
  ///
  /// No subquery is needed, unlike the disposal's location scope: both facts the
  /// scope turns on — who created the document and which branch it belongs to — are
  /// columns on this table. Written this way the rule travels into the statement, so
  /// a document outside the scope is never read at all.
  ///
  /// [ConsumptionQueryScope.branchPosted] ANDs `status = 'posted'` into the predicate
  /// *in addition to* whatever [_statusPredicate] the caller asked for. A branch head
  /// reads history, never work in progress (§14), and expressing that here rather
  /// than relying on every call site to pass the right status set is what makes it a
  /// property of the query instead of a convention.
  Expression<bool> _scopePredicate({
    required ConsumptionQueryScope? scope,
    required String? actorUserId,
    required String? branchId,
  }) {
    if (scope == null) return const Constant(true);

    switch (scope) {
      case ConsumptionQueryScope.ownDocuments:
        // An own scope with no user matches nothing rather than everything: a
        // provider that lost its session must see no documents, not all of them.
        if (actorUserId == null) return const Constant(false);
        return consumptions.createdBy.equals(actorUserId);
      case ConsumptionQueryScope.branchPosted:
        if (branchId == null) return const Constant(false);
        return consumptions.branchId.equals(branchId) &
            consumptions.status.equals(ConsumptionStatus.posted.dbValue);
    }
  }

  Expression<bool> _statusPredicate(Set<ConsumptionStatus> statuses) =>
      statuses.isEmpty
      ? const Constant(true)
      : consumptions.status.isIn(
          statuses.map((status) => status.dbValue).toList(growable: false),
        );

  // --- joined line reads ----------------------------------------------------

  JoinedSelectStatement<HasResultSet, dynamic> _detailLinesQuery(
    String consumptionId,
  ) {
    return (select(consumptionLines)..where(
          (t) => t.consumptionId.equals(consumptionId) & t.deletedAt.isNull(),
        ))
        .join([
          // No `is_active` and no `deleted_at` filter on the master joins: a posted
          // consumption whose item or batch was withdrawn afterwards must stay
          // readable, and the repository labels it instead of hiding it (§33).
          innerJoin(items, items.id.equalsExp(consumptionLines.itemId)),
          // Left join, unlike the disposal's: `batch_id` is nullable here, and an
          // inner join would make every line for an item without expiry vanish —
          // exactly the silent data loss §22 is about.
          leftOuterJoin(
            itemBatches,
            itemBatches.id.equalsExp(consumptionLines.batchId),
          ),
        ])
      // Item first, then nearest expiry: a nurse reads the document by product, and
      // within one product the batch that expires soonest is the one they should have
      // reached for (§17).
      ..orderBy([
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(itemBatches.batchNo),
        OrderingTerm.asc(consumptionLines.id),
      ]);
  }

  List<ConsumptionLineWithDetails> _mapLines(List<TypedResult> rows) {
    return rows
        .map(
          (row) => ConsumptionLineWithDetails(
            line: row.readTable(consumptionLines),
            item: row.readTable(items),
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ConsumptionLineWithDetails>> detailLines(
    String consumptionId,
  ) async => _mapLines(await _detailLinesQuery(consumptionId).get());

  Stream<List<ConsumptionLineWithDetails>> watchDetailLines(
    String consumptionId,
  ) => _detailLinesQuery(consumptionId).watch().map(_mapLines);

  // --- summaries ------------------------------------------------------------

  Expression<int> get _lineCount => consumptionLines.id.count(
    distinct: true,
    filter: consumptionLines.deletedAt.isNull(),
  );

  Expression<int> get _itemCount => consumptionLines.itemId.count(
    distinct: true,
    filter: consumptionLines.deletedAt.isNull(),
  );

  Expression<int> get _batchCount => consumptionLines.batchId.count(
    distinct: true,
    filter: consumptionLines.deletedAt.isNull(),
  );

  JoinedSelectStatement<HasResultSet, dynamic> _summaryQuery(
    Expression<bool> predicate,
  ) {
    final query = (select(consumptions)..where((t) => t.deletedAt.isNull())).join([
      // Inner joins on branch, room and creator: all three are NOT NULL foreign
      // keys, and none of the joins filters `is_active` or `deleted_at`, so a
      // retired room or a deactivated nurse still produces a row (§33).
      innerJoin(branches, branches.id.equalsExp(consumptions.branchId)),
      innerJoin(rooms, rooms.id.equalsExp(consumptions.roomId)),
      innerJoin(users, users.id.equalsExp(consumptions.createdBy)),
      leftOuterJoin(
        _postedByUsers,
        _postedByUsers.id.equalsExp(consumptions.postedBy),
      ),
      // Left join so a draft with no lines yet still produces a row, and
      // soft-deleted lines never inflate the counts.
      leftOuterJoin(
        consumptionLines,
        consumptionLines.consumptionId.equalsExp(consumptions.id) &
            consumptionLines.deletedAt.isNull(),
      ),
    ]);

    return query
      ..addColumns([_lineCount, _itemCount, _batchCount])
      ..where(predicate)
      ..groupBy([consumptions.id])
      ..orderBy([OrderingTerm.desc(consumptions.createdAt)]);
  }

  /// A second alias of `users`, so one query can join the creator and the poster.
  ///
  /// Without the alias both foreign keys would resolve to the same table instance and
  /// the join condition of one would overwrite the other's — a document would then
  /// report its creator as its poster, which is precisely the audit fact G-A3 exists
  /// to keep straight. On this document the two are usually the same person, which is
  /// exactly why a bug here would be invisible.
  late final $UsersTable _postedByUsers = alias(users, 'posted_by_user');

  List<ConsumptionWithContext> _mapSummaries(List<TypedResult> rows) {
    return rows
        .map(
          (row) => ConsumptionWithContext(
            consumption: row.readTable(consumptions),
            branch: row.readTable(branches),
            room: row.readTable(rooms),
            createdBy: row.readTable(users),
            postedBy: row.readTableOrNull(_postedByUsers),
            lineCount: row.read(_lineCount) ?? 0,
            itemCount: row.read(_itemCount) ?? 0,
            batchCount: row.read(_batchCount) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  /// The document predicate, optionally pinned to one scope and one status set.
  ///
  /// Both checks happen **inside the statement**, so a consumption outside them is
  /// never read, never mapped and never reaches a stream a widget could be listening
  /// to. Filtering the result in Dart would look equivalent and would not be.
  Expression<bool> _document(
    String consumptionId,
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    Set<ConsumptionStatus> statuses,
  ) =>
      consumptions.id.equals(consumptionId) &
      _scopePredicate(
        scope: scope,
        actorUserId: actorUserId,
        branchId: branchId,
      ) &
      _statusPredicate(statuses);

  Future<ConsumptionWithContext?> summaryById(
    String consumptionId, {
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    Set<ConsumptionStatus> statuses = const {},
  }) async {
    final rows = await _summaryQuery(
      _document(consumptionId, scope, actorUserId, branchId, statuses),
    ).get();
    return rows.isEmpty ? null : _mapSummaries(rows).single;
  }

  Stream<ConsumptionWithContext?> watchSummaryById(
    String consumptionId, {
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    Set<ConsumptionStatus> statuses = const {},
  }) {
    return _summaryQuery(
      _document(consumptionId, scope, actorUserId, branchId, statuses),
    ).watch().map((rows) => rows.isEmpty ? null : _mapSummaries(rows).single);
  }

  Expression<bool> _scope({
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    String? roomId,
    String? createdBy,
    Set<ConsumptionStatus> statuses = const {},
    String? searchQuery,
  }) {
    var predicate =
        _scopePredicate(
          scope: scope,
          actorUserId: actorUserId,
          branchId: branchId,
        ) &
        _statusPredicate(statuses);

    if (roomId != null) {
      // Narrowing *within* an already-scoped read — the room filter on both list
      // screens. It can only ever restrict what the scope already allowed, because
      // both predicates are ANDed.
      predicate = predicate & consumptions.roomId.equals(roomId);
    }
    if (createdBy != null) {
      // The branch head's *Perawat* filter. Same reasoning: it narrows within the
      // branch scope and can never widen it.
      predicate = predicate & consumptions.createdBy.equals(createdBy);
    }

    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      // Document number, room, or a consumed item — case-insensitive and entirely
      // local, so the clinic keeps searching offline (G-Y1).
      final pattern = '%$needle%';
      predicate =
          predicate &
          (consumptions.docNumber.lower().like(pattern) |
              rooms.name.lower().like(pattern) |
              rooms.code.lower().like(pattern) |
              _consumesMatchingItem(pattern));
    }
    return predicate;
  }

  /// Whether a document carries a line whose item name, SKU or batch number matches
  /// [pattern].
  ///
  /// A subquery rather than a join, because the summary query already left-joins
  /// `consumption_lines` to count them: adding `items` to that join would make the
  /// `WHERE` filter away the very rows the counts are derived from, and a document
  /// found by its number would then report only its matching lines.
  Expression<bool> _consumesMatchingItem(String pattern) {
    final matchingItems = selectOnly(items)
      ..addColumns([items.id])
      ..where(
        items.name.lower().like(pattern) | items.sku.lower().like(pattern),
      );
    final matchingBatches = selectOnly(itemBatches)
      ..addColumns([itemBatches.id])
      ..where(itemBatches.batchNo.lower().like(pattern));

    final matching = selectOnly(consumptionLines)
      ..addColumns([consumptionLines.consumptionId])
      ..where(
        consumptionLines.deletedAt.isNull() &
            (consumptionLines.itemId.isInQuery(matchingItems) |
                consumptionLines.batchId.isInQuery(matchingBatches)),
      );

    return consumptions.id.isInQuery(matching);
  }

  Future<List<ConsumptionWithContext>> listConsumptions({
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    String? roomId,
    String? createdBy,
    Set<ConsumptionStatus> statuses = const {},
    String? searchQuery,
  }) async {
    final rows = await _summaryQuery(
      _scope(
        scope: scope,
        actorUserId: actorUserId,
        branchId: branchId,
        roomId: roomId,
        createdBy: createdBy,
        statuses: statuses,
        searchQuery: searchQuery,
      ),
    ).get();
    return _mapSummaries(rows);
  }

  Stream<List<ConsumptionWithContext>> watchConsumptions({
    ConsumptionQueryScope? scope,
    String? actorUserId,
    String? branchId,
    String? roomId,
    String? createdBy,
    Set<ConsumptionStatus> statuses = const {},
    String? searchQuery,
  }) {
    return _summaryQuery(
      _scope(
        scope: scope,
        actorUserId: actorUserId,
        branchId: branchId,
        roomId: roomId,
        createdBy: createdBy,
        statuses: statuses,
        searchQuery: searchQuery,
      ),
    ).watch().map(_mapSummaries);
  }

  // --- rooms ----------------------------------------------------------------

  /// Every live, active room of one branch, ordered by code.
  ///
  /// The room selector is built from this rather than from a hard-coded
  /// `R1 / R2 / R3`: spec §2.1 makes rooms master data managed by the Super Admin,
  /// and a branch with four rooms must show four choices.
  Future<List<Room>> activeRoomsOfBranch(String branchId) =>
      _activeRoomsQuery(branchId).get();

  Stream<List<Room>> watchActiveRoomsOfBranch(String branchId) =>
      _activeRoomsQuery(branchId).watch();

  SimpleSelectStatement<$RoomsTable, Room> _activeRoomsQuery(String branchId) =>
      select(rooms)
        ..where(
          (t) =>
              t.branchId.equals(branchId) &
              t.isActive.equals(true) &
              t.deletedAt.isNull(),
        )
        ..orderBy([(t) => OrderingTerm.asc(t.code)]);

  /// One room by id, soft-deleted rows included — for reading a posted document whose
  /// room was archived afterwards (§33).
  Future<Room?> roomById(String id) =>
      (select(rooms)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Every `room` stock location of one room, soft-deleted rows included.
  ///
  /// Returned as a *list* rather than as "the" location, because the caller has to be
  /// able to tell "there is none" from "there are two": a consumption reduces exactly
  /// one location per document and may not guess which (§15). [activeOnly] is the
  /// distinction §15 draws — new work needs a live location, whereas reading a posted
  /// document must still resolve one that has since been tidied away.
  Future<List<StockLocation>> roomLocationsOf(
    String roomId, {
    bool activeOnly = true,
  }) {
    final query = select(stockLocations)
      ..where(
        (t) =>
            t.roomId.equals(roomId) &
            t.type.equals(StockLocationType.room.dbValue) &
            (activeOnly ? t.deletedAt.isNull() : const Constant(true)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    return query.get();
  }

  // --- room stock -----------------------------------------------------------

  /// Positive balances at one room location, joined with item and — when it has one —
  /// batch.
  ///
  /// Three filters live in the SQL, and each is a rule:
  ///
  /// * `location_id = ?` — a candidate for this document comes from this document's
  ///   own room and nowhere else (§16). A warehouse or branch-store balance has no
  ///   query here that could surface it;
  /// * `qty_on_hand > 0` — a zero balance is not stock anybody can consume;
  /// * `items.is_active` when [activeItemsOnly] — adding a line is *new* work, so
  ///   master data that has been withdrawn may not be picked (G-A4). A document
  ///   already holding such a line keeps it: that read goes through [detailLines],
  ///   which filters neither flag.
  ///
  /// What is **not** in the SQL is expiry: `expiry_date` is ISO-8601 TEXT, so
  /// comparing it against a serialised "now" would compare characters.
  /// `ConsumptionExpiryPolicy` decides that in Dart on civil dates, and it is the
  /// reason an expired batch never reaches the picker.
  ///
  /// [searchQuery] matches item name, SKU or batch number, case-insensitively and
  /// entirely locally (G-Y1). [categoryId] follows the active category chip. Neither
  /// is applied with a row `LIMIT`: the caller caps the number of *positions* after
  /// the expiry filter has run, because cutting the row set off in SQL would drop
  /// positions the policy was about to keep.
  Future<List<RoomBatchStockRow>> roomStock({
    required String locationId,
    String? itemId,
    String? batchId,
    String? searchQuery,
    String? categoryId,
    bool activeItemsOnly = true,
  }) async => _mapStock(
    await _roomStockQuery(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
      searchQuery: searchQuery,
      categoryId: categoryId,
      activeItemsOnly: activeItemsOnly,
    ).get(),
  );

  Stream<List<RoomBatchStockRow>> watchRoomStock({
    required String locationId,
    String? itemId,
    String? batchId,
    String? searchQuery,
    String? categoryId,
    bool activeItemsOnly = true,
  }) => _roomStockQuery(
    locationId: locationId,
    itemId: itemId,
    batchId: batchId,
    searchQuery: searchQuery,
    categoryId: categoryId,
    activeItemsOnly: activeItemsOnly,
  ).watch().map(_mapStock);

  JoinedSelectStatement<HasResultSet, dynamic> _roomStockQuery({
    required String locationId,
    String? itemId,
    String? batchId,
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
    if (batchId != null) {
      predicate = predicate & stockBalances.batchId.equals(batchId);
    }
    if (activeItemsOnly) {
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
          (items.name.lower().like(pattern) |
              items.sku.lower().like(pattern) |
              itemBatches.batchNo.lower().like(pattern));
    }

    return select(stockBalances).join([
        innerJoin(items, items.id.equalsExp(stockBalances.itemId)),
        // Left join: an item without expiry has a balance row with `batch_id IS
        // NULL`, and an inner join would hide exactly the positions §9 says are
        // legitimate.
        leftOuterJoin(
          itemBatches,
          itemBatches.id.equalsExp(stockBalances.batchId),
        ),
      ])
      ..where(predicate)
      // Item, then nearest expiry, then batch number, then batch id — four keys,
      // because the first three can tie and a list that depended on the order rows
      // happened to come back in would differ between two devices holding the same
      // stock. Nearest expiry first is operational help, not a FEFO requirement
      // (§17): the nurse still records the batch they actually took.
      //
      // Ordering ISO-8601 `yyyy-MM-dd` text lexically *is* chronological order — the
      // trap the timestamp columns fall into needs two different serialisations of
      // the same instant, and a civil date has only one form.
      ..orderBy([
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(itemBatches.batchNo),
        OrderingTerm.asc(itemBatches.id),
      ]);
  }

  List<RoomBatchStockRow> _mapStock(List<TypedResult> rows) {
    return rows
        .map(
          (row) => RoomBatchStockRow(
            item: row.readTable(items),
            qtyOnHandMilliUnits: row.readTable(stockBalances).qtyOnHand,
            batch: row.readTableOrNull(itemBatches),
          ),
        )
        .toList(growable: false);
  }
}
