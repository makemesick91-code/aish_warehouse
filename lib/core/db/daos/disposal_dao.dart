import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/disposal_tables.dart';
import '../tables/inventory_tables.dart';
import '../tables/master_tables.dart';

part 'disposal_dao.g.dart';

/// A Pemusnahan header joined with everything a list row or a detail header
/// needs, plus the per-document counts a summary shows.
///
/// None of the joins filter `is_active` or `deleted_at`, which is what keeps a
/// posted disposal readable after its source location, its branch, its room or
/// the person who posted it is retired. The repository turns that into
/// `…IsHistorical` flags the screens can label rather than into a row that
/// quietly disappears (§34).
class DisposalWithContext {
  const DisposalWithContext({
    required this.disposal,
    required this.sourceLocation,
    this.branch,
    this.room,
    required this.createdBy,
    this.postedBy,
    required this.lineCount,
    required this.itemCount,
    required this.batchCount,
  });

  final DisposalRow disposal;

  /// The location the goods left. Always present — the foreign key guarantees the
  /// row exists, and the join filters nothing.
  final StockLocation sourceLocation;

  /// The branch the source belongs to, or `null` for Warehouse Pusat.
  final Branch? branch;

  /// The room the source belongs to, or `null` for a warehouse or branch store.
  final Room? room;

  final AppUser createdBy;

  /// `null` exactly while the document is a draft.
  final AppUser? postedBy;

  final int lineCount;
  final int itemCount;
  final int batchCount;
}

/// The four facts an authorization check needs, and nothing else.
///
/// Deliberately not the joined summary: deciding whether a disposal may be shown
/// must not be the reason its number, its items, its batches, its quantities or
/// its reason are read.
class DisposalAccessRow {
  const DisposalAccessRow({
    required this.disposalId,
    required this.sourceLocationId,
    required this.createdBy,
    required this.status,
  });

  final String disposalId;
  final String sourceLocationId;
  final String createdBy;
  final DisposalStatus status;
}

/// One disposal line joined with its item and its batch.
///
/// `batch` is non-null because `disposal_lines.batch_id` is: this milestone
/// disposes of expired batches and nothing else.
class DisposalLineWithDetails {
  const DisposalLineWithDetails({
    required this.line,
    required this.item,
    required this.batch,
  });

  final DisposalLineRow line;
  final Item item;
  final ItemBatch batch;
}

/// One balance row of a source location, joined with its item and batch.
///
/// The input the candidate picker and the posting revalidation both work from.
/// Expiry is deliberately **not** filtered here: `expiry_date` is ISO-8601 TEXT
/// (`build.yaml`), so a SQL comparison against "now" would compare characters
/// rather than dates — the trap schema v4 removed from `stock_opnames`.
/// `DisposalExpiryPolicy` decides eligibility, in Dart, on civil dates.
class LocationBatchStockRow {
  const LocationBatchStockRow({
    required this.item,
    required this.batch,
    required this.qtyOnHandMilliUnits,
  });

  final Item item;
  final ItemBatch batch;

  /// Milli-units (Q-3); the repository converts.
  final int qtyOnHandMilliUnits;
}

/// Pemusnahan persistence (schema v9, G-E7).
///
/// The same absences that shape [OpnameDao], [PurchaseRequestDao],
/// [DeliveryOrderDao], [GoodReceiptDao] and [DistributionDao] shape this one, and
/// for the same reasons:
///
/// * **No unrestricted status writer.** There is no `setStatus`. The one
///   transition this milestone opens — `draft → posted` — has its own method that
///   names the status it expects to move *from*, so the predicate travels into the
///   same statement as the write and a stale screen or a racing device cannot post
///   a disposal twice (G-S1). Every guarded write returns the number of affected
///   rows; zero means the guard fired.
/// * **No un-post and no reopen.** `posted` has no outgoing transition at all, so
///   there is no method that could express one.
/// * **No unrestricted line writer.** A line can only be changed while its parent
///   is `draft`, checked inside the statement rather than before it. And no writer
///   here reaches `disposal_id`, `item_id` or `batch_id`: a different batch is a
///   *different* position, and moving one in place would slip past the expiry and
///   balance validation the add path performs. Changing a position is
///   remove-then-add, both validated.
/// * **No hard delete.** Nothing here removes a row (G-A5). A draft line is soft
///   deleted; a posted document cannot be touched by any method on this class.
/// * **No source location writer.** `source_location_id` is set once, by the
///   insert, and there is no statement that updates it. Moving a document to
///   another shelf would move it into — or out of — somebody else's scope while
///   its lines still described the old one's stock.
/// * **No destination anywhere.** A disposal has no `to_location_id` to write and
///   no parameter to pass one: the goods leave the system (§20).
/// * **No balance writer.** Stock changes only through `StockPostingService`, and
///   a DAO that could also decrement a balance would be a second way into the
///   ledger.
/// * **No "dispose anything" read.** [expiredStock] returns batch positions only,
///   for expiry-tracked items only. An item without expiry has no query here to
///   surface it, which is the database half of *"this milestone disposes of
///   expired stock and nothing else"*.
///
/// Like the other DAOs this is a milli-unit layer (Q-4): `qty` and `qty_on_hand`
/// are INTEGER columns holding `unit * 1000`, and the repository above converts
/// them to `Quantity`.
@DriftAccessor(
  tables: [
    Disposals,
    DisposalLines,
    StockBalances,
    Items,
    ItemBatches,
    Rooms,
    Branches,
    Users,
    StockLocations,
  ],
)
class DisposalDao extends DatabaseAccessor<AppDatabase>
    with _$DisposalDaoMixin {
  DisposalDao(super.db);

  /// Runs [action] in one transaction.
  ///
  /// The posting owns exactly one of these, and every write it performs — the
  /// ledger movements, the source balance updates, the document status, its
  /// timestamp and its posting actor — happens inside it. Nothing below opens a
  /// transaction of its own for a single line, because a failure on the last
  /// movement must roll the first one back (§21).
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      transaction(action);

  // --- writes ---------------------------------------------------------------

  Future<DisposalRow> insertHeader(DisposalsCompanion header) =>
      into(disposals).insertReturning(header);

  Future<DisposalLineRow> insertLine(DisposalLinesCompanion line) =>
      into(disposalLines).insertReturning(line);

  /// Updates the reason of a **draft**.
  ///
  /// The status predicate is in the statement, so a reason cannot be rewritten on
  /// a posted document however stale the screen that tried — which matters more
  /// here than on any other document, because G-E7 makes this text the audit
  /// record of why stock disappeared.
  Future<int> updateDraftReason({
    required String disposalId,
    required String? reason,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE disposals '
      'SET reason = ?, updated_at = ?, sync_status = ? '
      "WHERE id = ? AND status = 'draft' AND deleted_at IS NULL;",
      variables: [
        if (reason == null)
          const Variable<String>(null)
        else
          Variable<String>(reason),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(disposalId),
      ],
      updates: {disposals},
      updateKind: UpdateKind.update,
    );
  }

  /// Changes the quantity and the note of one **draft** line.
  ///
  /// Four predicates travel into the statement, and each is a rule rather than a
  /// convenience: the line must belong to [disposalId], its parent must still be
  /// `draft`, neither row may be soft-deleted, and the quantity must be strictly
  /// positive — expressed as `? > 0` in SQL rather than trusted from the caller,
  /// so a stale screen cannot store a zero even if the domain check were somehow
  /// skipped.
  ///
  /// `item_id` and `batch_id` are deliberately out of reach: another batch is a
  /// *different* position with its own expiry date and its own balance, and
  /// changing one in place would slip past both checks. Swapping a position is
  /// remove-then-add.
  Future<int> updateDraftLine({
    required String disposalId,
    required String lineId,
    required int qtyMilliUnits,
    required String? note,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE disposal_lines '
      'SET qty = ?, note = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND disposal_id = ? AND deleted_at IS NULL '
      '  AND ? > 0 '
      '  AND disposal_id IN ('
      '    SELECT id FROM disposals '
      "    WHERE status = 'draft' AND deleted_at IS NULL"
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
        Variable<String>(disposalId),
        Variable<int>(qtyMilliUnits),
      ],
      updates: {disposalLines},
      updateKind: UpdateKind.update,
    );
  }

  /// Soft-deletes one **draft** line (G-A5).
  ///
  /// Guarded on the parent's status inside the same statement, so a line cannot be
  /// removed from a document that has already posted — which would leave the
  /// ledger describing a destruction the document no longer admits to.
  Future<int> softDeleteDraftLine({
    required String disposalId,
    required String lineId,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE disposal_lines '
      'SET deleted_at = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND disposal_id = ? AND deleted_at IS NULL '
      '  AND disposal_id IN ('
      '    SELECT id FROM disposals '
      "    WHERE status = 'draft' AND deleted_at IS NULL"
      '  );',
      variables: [
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
        Variable<String>(disposalId),
      ],
      updates: {disposalLines},
      updateKind: UpdateKind.update,
    );
  }

  /// `draft → posted`.
  ///
  /// Four predicates make a double post — and an empty or unexplained one —
  /// impossible at the moment of the write rather than at the moment of the read:
  ///
  /// * `status = 'draft'`, so a second device cannot post the same document;
  /// * `EXISTS` at least one live line, so removing the last line in between is
  ///   caught;
  /// * `reason IS NOT NULL AND trim(reason) <> ''`, G-E7's floor, so a reason
  ///   cleared in between is caught too.
  ///
  /// A return value of 0 means one of them fired, and the caller rolls the whole
  /// transaction — ledger movements included — back.
  ///
  /// The instant is forced to UTC here rather than trusted from the caller (T-1),
  /// because drift serialises a non-UTC `DateTime` with an offset suffix and a
  /// value that arrived in operational time would be *stored* as a different
  /// instant than the one the domain validated.
  Future<int> markPosted({
    required String disposalId,
    required DateTime postedAtUtc,
    required String postedBy,
  }) {
    final now = DateTime.now().toUtc();
    return customUpdate(
      'UPDATE disposals '
      'SET status = ?, posted_at = ?, posted_by = ?, updated_at = ?, '
      '    sync_status = ? '
      "WHERE id = ? AND status = 'draft' AND deleted_at IS NULL "
      "  AND reason IS NOT NULL AND trim(reason) <> '' "
      '  AND EXISTS ('
      '    SELECT 1 FROM disposal_lines '
      '    WHERE disposal_id = disposals.id AND deleted_at IS NULL'
      '  );',
      variables: [
        Variable<String>(DisposalStatus.posted.dbValue),
        Variable<DateTime>(postedAtUtc.toUtc()),
        Variable<String>(postedBy),
        Variable<DateTime>(now),
        // Once the document leaves the device it is the server's to confirm
        // (G-Y2), so every transition queues a sync.
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(disposalId),
      ],
      updates: {disposals},
      updateKind: UpdateKind.update,
    );
  }

  // --- plain reads (no join can hide a row) ----------------------------------

  Future<DisposalRow?> headerById(String id) => (select(
    disposals,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// Live lines of one document, without any join.
  ///
  /// A join can hide a row whose item or batch is physically gone; a plain select
  /// cannot. This is the honest inventory the posting path checks the joined read
  /// against, so a corrupt reference is reported instead of silently reducing the
  /// document by one line (§23).
  Future<List<DisposalLineRow>> linesOf(String disposalId) =>
      (select(disposalLines)..where(
            (t) => t.disposalId.equals(disposalId) & t.deletedAt.isNull(),
          ))
          .get();

  Future<DisposalLineRow?> lineById(String id) => (select(
    disposalLines,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// The ids of every live line of one document — one column, no join (§23).
  Future<List<String>> lineIdsOf(String disposalId) =>
      _lineColumn(disposalId, disposalLines.id);

  /// The distinct item ids of one document.
  Future<List<String>> lineItemIdsOf(String disposalId) =>
      _lineColumn(disposalId, disposalLines.itemId, distinct: true);

  /// The distinct batch ids of one document.
  ///
  /// No NULL filtering, unlike the Distribusi's equivalent: `batch_id` is NOT NULL
  /// here, so every live line contributes one.
  Future<List<String>> lineBatchIdsOf(String disposalId) =>
      _lineColumn(disposalId, disposalLines.batchId, distinct: true);

  Future<List<String>> _lineColumn(
    String disposalId,
    GeneratedColumn<String> column, {
    bool distinct = false,
  }) async {
    final query = selectOnly(disposalLines, distinct: distinct)
      ..addColumns([column])
      ..where(
        disposalLines.disposalId.equals(disposalId) &
            disposalLines.deletedAt.isNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.read(column))
        .whereType<String>()
        .toList(growable: false);
  }

  /// The facts that decide whether somebody may open this disposal.
  ///
  /// Four columns and one join — to `stock_locations`, and only because the scope
  /// predicate needs the location's type and branch. When [scope] is supplied it is
  /// in the statement, so a document outside it never leaves SQLite and the caller
  /// cannot leak what it never received. [statuses] narrows the same way.
  ///
  /// Returns `null` both for "no such disposal" and for "not yours", and that
  /// ambiguity is the point: telling them apart would turn the address bar into a
  /// way to enumerate documents across the clinic group.
  Future<DisposalAccessRow?> accessScope({
    required String disposalId,
    DisposalLocationScope? scope,
    String? branchId,
    Set<DisposalStatus> statuses = const {},
  }) async {
    final query = selectOnly(disposals)
      ..addColumns([
        disposals.id,
        disposals.sourceLocationId,
        disposals.createdBy,
        disposals.status,
      ])
      ..where(
        disposals.id.equals(disposalId) &
            disposals.deletedAt.isNull() &
            _scopePredicate(scope: scope, branchId: branchId) &
            _statusPredicate(statuses),
      );

    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return DisposalAccessRow(
      disposalId: row.read(disposals.id)!,
      sourceLocationId: row.read(disposals.sourceLocationId)!,
      createdBy: row.read(disposals.createdBy)!,
      status: row.readWithConverter(disposals.status)!,
    );
  }

  // --- scope ----------------------------------------------------------------

  /// The location scope, expressed as a subquery on `stock_locations`.
  ///
  /// A subquery rather than a resolved list of ids, and deliberately: resolving
  /// the ids first would mean a location added between the resolve and the read is
  /// silently outside the scope, and — worse — it would put the decision in Dart
  /// where a caller could pass an arbitrary list. Written this way the rule
  /// travels into the statement, so a document whose source is not in scope is
  /// never read at all.
  ///
  /// `warehouse` matches by **type**, which is the only honest way to say
  /// *"Warehouse Pusat"*: there is no branch to compare and hard-coding a seed id
  /// would break on any other installation. `branch` matches by `branch_id`, which
  /// covers exactly the branch store and the rooms of that branch — a warehouse
  /// location carries `branch_id IS NULL` and therefore never matches.
  Expression<bool> _scopePredicate({
    required DisposalLocationScope? scope,
    required String? branchId,
  }) {
    if (scope == null) return const Constant(true);

    final locations = selectOnly(stockLocations)
      ..addColumns([stockLocations.id]);
    switch (scope) {
      case DisposalLocationScope.warehouse:
        locations.where(
          stockLocations.type.equals(StockLocationType.warehouse.dbValue),
        );
      case DisposalLocationScope.branch:
        // A branch scope with no branch matches nothing rather than everything: a
        // role that has lost its branch must see no documents, not all of them.
        if (branchId == null) return const Constant(false);
        locations.where(stockLocations.branchId.equals(branchId));
    }
    return disposals.sourceLocationId.isInQuery(locations);
  }

  Expression<bool> _statusPredicate(Set<DisposalStatus> statuses) =>
      statuses.isEmpty
      ? const Constant(true)
      : disposals.status.isIn(
          statuses.map((status) => status.dbValue).toList(growable: false),
        );

  // --- joined line reads ----------------------------------------------------

  JoinedSelectStatement<HasResultSet, dynamic> _detailLinesQuery(
    String disposalId,
  ) {
    return (select(
          disposalLines,
        )..where((t) => t.disposalId.equals(disposalId) & t.deletedAt.isNull()))
        .join([
          // No `is_active` and no `deleted_at` filter on the master joins: a posted
          // disposal whose item or batch was withdrawn afterwards must stay
          // readable, and the repository labels it instead of hiding it (§34).
          innerJoin(items, items.id.equalsExp(disposalLines.itemId)),
          innerJoin(
            itemBatches,
            itemBatches.id.equalsExp(disposalLines.batchId),
          ),
        ])
      // Oldest expiry first — the risk order §17 asks for, since every line on
      // this document is already past its date.
      ..orderBy([
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.batchNo),
      ]);
  }

  List<DisposalLineWithDetails> _mapLines(List<TypedResult> rows) {
    return rows
        .map(
          (row) => DisposalLineWithDetails(
            line: row.readTable(disposalLines),
            item: row.readTable(items),
            batch: row.readTable(itemBatches),
          ),
        )
        .toList(growable: false);
  }

  Future<List<DisposalLineWithDetails>> detailLines(String disposalId) async =>
      _mapLines(await _detailLinesQuery(disposalId).get());

  Stream<List<DisposalLineWithDetails>> watchDetailLines(String disposalId) =>
      _detailLinesQuery(disposalId).watch().map(_mapLines);

  // --- summaries ------------------------------------------------------------

  Expression<int> get _lineCount => disposalLines.id.count(
    distinct: true,
    filter: disposalLines.deletedAt.isNull(),
  );

  Expression<int> get _itemCount => disposalLines.itemId.count(
    distinct: true,
    filter: disposalLines.deletedAt.isNull(),
  );

  Expression<int> get _batchCount => disposalLines.batchId.count(
    distinct: true,
    filter: disposalLines.deletedAt.isNull(),
  );

  JoinedSelectStatement<HasResultSet, dynamic> _summaryQuery(
    Expression<bool> predicate,
  ) {
    final query = (select(disposals)..where((t) => t.deletedAt.isNull())).join([
      innerJoin(
        stockLocations,
        stockLocations.id.equalsExp(disposals.sourceLocationId),
      ),
      // Left joins: Warehouse Pusat has neither a branch nor a room, and a branch
      // store has no room. An inner join would make the warehouse's own disposals
      // vanish from every list — the exact failure §34 is about.
      leftOuterJoin(branches, branches.id.equalsExp(stockLocations.branchId)),
      leftOuterJoin(rooms, rooms.id.equalsExp(stockLocations.roomId)),
      innerJoin(users, users.id.equalsExp(disposals.createdBy)),
      leftOuterJoin(
        _postedByUsers,
        _postedByUsers.id.equalsExp(disposals.postedBy),
      ),
      // Left join so a draft with no lines yet still produces a row, and
      // soft-deleted lines never inflate the counts.
      leftOuterJoin(
        disposalLines,
        disposalLines.disposalId.equalsExp(disposals.id) &
            disposalLines.deletedAt.isNull(),
      ),
    ]);

    return query
      ..addColumns([_lineCount, _itemCount, _batchCount])
      ..where(predicate)
      ..groupBy([disposals.id])
      ..orderBy([OrderingTerm.desc(disposals.createdAt)]);
  }

  /// A second alias of `users`, so one query can join the creator and the poster.
  ///
  /// Without the alias both foreign keys would resolve to the same table instance
  /// and the join condition of one would overwrite the other's — a document would
  /// then report its creator as its poster, which is precisely the audit fact
  /// G-A3 exists to keep straight.
  late final $UsersTable _postedByUsers = alias(users, 'posted_by_user');

  List<DisposalWithContext> _mapSummaries(List<TypedResult> rows) {
    return rows
        .map(
          (row) => DisposalWithContext(
            disposal: row.readTable(disposals),
            sourceLocation: row.readTable(stockLocations),
            branch: row.readTableOrNull(branches),
            room: row.readTableOrNull(rooms),
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
  /// Both checks happen **inside the statement**, so a disposal outside them is
  /// never read, never mapped and never reaches a stream a widget could be
  /// listening to. Filtering the result in Dart would look equivalent and would
  /// not be.
  Expression<bool> _document(
    String disposalId,
    DisposalLocationScope? scope,
    String? branchId,
    Set<DisposalStatus> statuses,
  ) =>
      disposals.id.equals(disposalId) &
      _scopePredicate(scope: scope, branchId: branchId) &
      _statusPredicate(statuses);

  Future<DisposalWithContext?> summaryById(
    String disposalId, {
    DisposalLocationScope? scope,
    String? branchId,
    Set<DisposalStatus> statuses = const {},
  }) async {
    final rows = await _summaryQuery(
      _document(disposalId, scope, branchId, statuses),
    ).get();
    return rows.isEmpty ? null : _mapSummaries(rows).single;
  }

  Stream<DisposalWithContext?> watchSummaryById(
    String disposalId, {
    DisposalLocationScope? scope,
    String? branchId,
    Set<DisposalStatus> statuses = const {},
  }) {
    return _summaryQuery(
      _document(disposalId, scope, branchId, statuses),
    ).watch().map((rows) => rows.isEmpty ? null : _mapSummaries(rows).single);
  }

  Expression<bool> _scope({
    DisposalLocationScope? scope,
    String? branchId,
    String? sourceLocationId,
    Set<DisposalStatus> statuses = const {},
    String? searchQuery,
  }) {
    var predicate =
        _scopePredicate(scope: scope, branchId: branchId) &
        _statusPredicate(statuses);

    if (sourceLocationId != null) {
      // Narrowing *within* an already-scoped read — the branch head's location
      // selector. It can only ever restrict what the scope already allowed,
      // because both predicates are ANDed.
      predicate =
          predicate & disposals.sourceLocationId.equals(sourceLocationId);
    }

    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      // Document number, source location, or a destroyed item — case-insensitive
      // and entirely local, so the clinic keeps searching offline (G-Y1).
      final pattern = '%$needle%';
      predicate =
          predicate &
          (disposals.docNumber.lower().like(pattern) |
              stockLocations.name.lower().like(pattern) |
              _disposesMatchingItem(pattern));
    }
    return predicate;
  }

  /// Whether a document carries a line whose item name, SKU or batch number
  /// matches [pattern].
  ///
  /// A subquery rather than a join, because the summary query already left-joins
  /// `disposal_lines` to count them: adding `items` to that join would make the
  /// `WHERE` filter away the very rows the counts are derived from, and a document
  /// found by its number would then report only its matching lines.
  Expression<bool> _disposesMatchingItem(String pattern) {
    final matchingItems = selectOnly(items)
      ..addColumns([items.id])
      ..where(
        items.name.lower().like(pattern) | items.sku.lower().like(pattern),
      );
    final matchingBatches = selectOnly(itemBatches)
      ..addColumns([itemBatches.id])
      ..where(itemBatches.batchNo.lower().like(pattern));

    final matching = selectOnly(disposalLines)
      ..addColumns([disposalLines.disposalId])
      ..where(
        disposalLines.deletedAt.isNull() &
            (disposalLines.itemId.isInQuery(matchingItems) |
                disposalLines.batchId.isInQuery(matchingBatches)),
      );

    return disposals.id.isInQuery(matching);
  }

  Future<List<DisposalWithContext>> listDisposals({
    DisposalLocationScope? scope,
    String? branchId,
    String? sourceLocationId,
    Set<DisposalStatus> statuses = const {},
    String? searchQuery,
  }) async {
    final rows = await _summaryQuery(
      _scope(
        scope: scope,
        branchId: branchId,
        sourceLocationId: sourceLocationId,
        statuses: statuses,
        searchQuery: searchQuery,
      ),
    ).get();
    return _mapSummaries(rows);
  }

  Stream<List<DisposalWithContext>> watchDisposals({
    DisposalLocationScope? scope,
    String? branchId,
    String? sourceLocationId,
    Set<DisposalStatus> statuses = const {},
    String? searchQuery,
  }) {
    return _summaryQuery(
      _scope(
        scope: scope,
        branchId: branchId,
        sourceLocationId: sourceLocationId,
        statuses: statuses,
        searchQuery: searchQuery,
      ),
    ).watch().map(_mapSummaries);
  }

  // --- locations ------------------------------------------------------------

  /// Every live central-warehouse location, ordered by name.
  Future<List<StockLocation>> warehouseLocations() => _locationsQuery(
    stockLocations.type.equals(StockLocationType.warehouse.dbValue),
  ).get();

  /// Every live `branch_store` and `room` location of one branch, ordered so the
  /// store comes before the rooms.
  ///
  /// The source selector on the Kepala Cabang's screen is built from this rather
  /// than from a hard-coded `Gudang Cabang / R1 / R2 / R3`: spec §2.1 makes rooms
  /// master data managed by the Super Admin, and a branch with four rooms must
  /// show five choices.
  Future<List<StockLocation>> branchSourceLocations(String branchId) =>
      _branchSourceLocationsQuery(branchId).get();

  Stream<List<StockLocation>> watchBranchSourceLocations(String branchId) =>
      _branchSourceLocationsQuery(branchId).watch();

  SimpleSelectStatement<$StockLocationsTable, StockLocation>
  _branchSourceLocationsQuery(String branchId) {
    final query = _locationsQuery(
      stockLocations.branchId.equals(branchId) &
          stockLocations.type.isIn([
            StockLocationType.branchStore.dbValue,
            StockLocationType.room.dbValue,
          ]),
    );
    // `branch_store` sorts before `room` alphabetically, which happens to be the
    // order a branch head thinks in — the store first, then the treatment rooms.
    return query..orderBy([
      (t) => OrderingTerm.asc(t.type),
      (t) => OrderingTerm.asc(t.name),
    ]);
  }

  SimpleSelectStatement<$StockLocationsTable, StockLocation> _locationsQuery(
    Expression<bool> predicate,
  ) => select(stockLocations)
    ..where((t) => t.deletedAt.isNull() & predicate)
    ..orderBy([(t) => OrderingTerm.asc(t.name)]);

  /// One location by id, soft-deleted rows included — for reading a posted
  /// document whose source was archived afterwards (§34).
  Future<StockLocation?> locationById(String id) =>
      (select(stockLocations)..where((t) => t.id.equals(id))).getSingleOrNull();

  // --- expired stock at a location ------------------------------------------

  /// Positive **batch** balances at one location, joined with item and batch.
  ///
  /// Four filters live in the SQL, and each is a rule:
  ///
  /// * `location_id = ?` — a candidate for this document comes from this
  ///   document's own shelf and nowhere else (§17);
  /// * `qty_on_hand > 0` — a zero balance is not stock anybody can destroy;
  /// * `batch_id IS NOT NULL` and `items.has_expiry` — only a batch-tracked item
  ///   has an expiry date to be past, so an item without one has no row here at
  ///   all. That is the database half of *"this milestone disposes of expired
  ///   stock and nothing else"*.
  ///
  /// What is **not** in the SQL is expiry itself: `expiry_date` is ISO-8601 TEXT,
  /// so comparing it against a serialised "now" would compare characters.
  /// `DisposalExpiryPolicy` decides that in Dart on civil dates.
  ///
  /// Nor is `is_active`. A product withdrawn from the catalogue, or a batch
  /// archived by an administrator, can still be physically expired on a shelf —
  /// and refusing to show it would leave stock nobody can ever remove. §17 states
  /// this directly, and the repository labels those rows as historical instead.
  ///
  /// [searchQuery] matches item name, SKU or batch number, case-insensitively and
  /// entirely locally (G-Y1). [categoryId] follows the active category chip.
  Future<List<LocationBatchStockRow>> expiredStock({
    required String locationId,
    String? itemId,
    String? batchId,
    String? searchQuery,
    String? categoryId,
  }) async => _mapStock(
    await _expiredStockQuery(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
      searchQuery: searchQuery,
      categoryId: categoryId,
    ).get(),
  );

  Stream<List<LocationBatchStockRow>> watchExpiredStock({
    required String locationId,
    String? itemId,
    String? batchId,
    String? searchQuery,
    String? categoryId,
  }) => _expiredStockQuery(
    locationId: locationId,
    itemId: itemId,
    batchId: batchId,
    searchQuery: searchQuery,
    categoryId: categoryId,
  ).watch().map(_mapStock);

  JoinedSelectStatement<HasResultSet, dynamic> _expiredStockQuery({
    required String locationId,
    String? itemId,
    String? batchId,
    String? searchQuery,
    String? categoryId,
  }) {
    var predicate =
        stockBalances.locationId.equals(locationId) &
        stockBalances.deletedAt.isNull() &
        stockBalances.qtyOnHand.isBiggerThanValue(0) &
        stockBalances.batchId.isNotNull() &
        items.hasExpiry.equals(true);

    if (itemId != null) {
      predicate = predicate & stockBalances.itemId.equals(itemId);
    }
    if (batchId != null) {
      predicate = predicate & stockBalances.batchId.equals(batchId);
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
        innerJoin(itemBatches, itemBatches.id.equalsExp(stockBalances.batchId)),
      ])
      ..where(predicate)
      // Oldest expiry first: every row here is already expired, so the one that
      // has been sitting there longest is the one to deal with first (§17).
      // Ordering ISO-8601 `yyyy-MM-dd` text lexically *is* chronological order —
      // the trap the timestamp columns fall into needs two different
      // serialisations of the same instant, and a civil date has only one form.
      ..orderBy([
        OrderingTerm.asc(itemBatches.expiryDate),
        OrderingTerm.asc(items.name),
        OrderingTerm.asc(itemBatches.batchNo),
        OrderingTerm.asc(itemBatches.id),
      ]);
  }

  List<LocationBatchStockRow> _mapStock(List<TypedResult> rows) {
    return rows
        .map(
          (row) => LocationBatchStockRow(
            item: row.readTable(items),
            batch: row.readTable(itemBatches),
            qtyOnHandMilliUnits: row.readTable(stockBalances).qtyOnHand,
          ),
        )
        .toList(growable: false);
  }
}
