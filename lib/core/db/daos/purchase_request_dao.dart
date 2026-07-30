import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../app_database.dart';
import '../tables/master_tables.dart';
import '../tables/opname_tables.dart';
import '../tables/purchase_request_tables.dart';

part 'purchase_request_dao.g.dart';

/// A Purchase Request header joined with everything a list row or a detail
/// header needs to render, plus the two counts a summary shows.
///
/// None of the joins filter `is_active` or `deleted_at`, which is what keeps a
/// submitted document readable after its branch, its author or one of its items
/// is retired (§7.6 of the opname hardening, applied here). The repository turns
/// that into `…IsHistorical` flags the screens can label.
class PurchaseRequestWithContext {
  const PurchaseRequestWithContext({
    required this.request,
    required this.branch,
    required this.requestedBy,
    this.processedBy,
    this.cancelledBy,
    this.rejectedBy,
    required this.lineCount,
    required this.linkedOpnameCount,
  });

  final PurchaseRequestRow request;
  final Branch branch;
  final AppUser requestedBy;
  final AppUser? processedBy;
  final AppUser? cancelledBy;
  final AppUser? rejectedBy;
  final int lineCount;
  final int linkedOpnameCount;
}

/// The four columns [PurchaseRequestDao.accessScope] returns — everything an
/// authorization check needs and nothing else.
class PurchaseRequestAccessRow {
  const PurchaseRequestAccessRow({
    required this.prId,
    required this.branchId,
    required this.status,
    required this.requestedBy,
  });

  final String prId;
  final String branchId;
  final PurchaseRequestStatus status;
  final String requestedBy;
}

/// One requested line joined with its item.
class PurchaseRequestLineWithDetails {
  const PurchaseRequestLineWithDetails({
    required this.line,
    required this.item,
  });

  final PurchaseRequestLineRow line;
  final Item item;
}

/// One cited opname, joined with the room it counted and the nurse who counted
/// it.
class PurchaseRequestOpnameWithDetails {
  const PurchaseRequestOpnameWithDetails({
    required this.link,
    required this.opname,
    required this.room,
    required this.countedBy,
    required this.differenceLineCount,
  });

  final PurchaseRequestOpnameRow link;
  final StockOpnameRow opname;
  final Room room;
  final AppUser countedBy;
  final int differenceLineCount;
}

/// One opname a branch head may cite, with the context the picker shows.
class EligibleOpnameRow {
  const EligibleOpnameRow({
    required this.opname,
    required this.room,
    required this.countedBy,
    required this.differenceLineCount,
  });

  final StockOpnameRow opname;
  final Room room;
  final AppUser countedBy;
  final int differenceLineCount;
}

/// An ISO week of the operational calendar, as the database sees it: two
/// integers. Passed in by the eligibility policy so the *rule* lives in the
/// domain and only the resulting `(year, week)` pairs reach SQL.
typedef OpnamePeriodKey = ({int year, int week});

/// Purchase Request persistence.
///
/// The same three absences that shape [OpnameDao] shape this one, and for the
/// same reasons:
///
/// * **No unrestricted status writer.** There is no `setStatus`. Each transition
///   has its own method that names the status it expects to move *from*, so the
///   predicate travels into the same statement as the write and a stale screen
///   or a racing device cannot move a document twice (G-P5, G-S1). Every guarded
///   write returns the number of affected rows; zero means the guard fired.
/// * **No unrestricted line writer.** A line can only be updated, added or
///   removed while its parent is a `draft`, checked inside the statement rather
///   than before it.
/// * **No hard delete.** Nothing here removes a row (G-A5), and no method can
///   soft-delete a document that has left `draft`.
///
/// There is also deliberately **no writer for `shipped` or `closed`**. Those
/// transitions belong to Delivery Order and Good Receipt; offering them here
/// would be a button waiting to be wired up before the documents that justify
/// them exist.
///
/// Like the other DAOs this is a milli-unit layer (Q-4): `suggested_qty` and
/// `requested_qty` are INTEGER columns holding `unit * 1000`, and the repository
/// above converts them to `Quantity`.
@DriftAccessor(
  tables: [
    PurchaseRequests,
    PurchaseRequestOpnames,
    PurchaseRequestLines,
    StockOpnames,
    StockOpnameLines,
    Items,
    Rooms,
    Branches,
    Users,
  ],
)
class PurchaseRequestDao extends DatabaseAccessor<AppDatabase>
    with _$PurchaseRequestDaoMixin {
  PurchaseRequestDao(super.db);

  /// Runs [action] in one transaction. Creating a draft — header, opname links
  /// and suggested lines — uses this so a half-built document is never
  /// observable.
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      transaction(action);

  // --- writes ---------------------------------------------------------------

  Future<PurchaseRequestRow> insertHeader(PurchaseRequestsCompanion header) =>
      into(purchaseRequests).insertReturning(header);

  Future<void> insertOpnameLinks(
    List<PurchaseRequestOpnamesCompanion> links,
  ) async {
    if (links.isEmpty) return;
    await batch((b) => b.insertAll(purchaseRequestOpnames, links));
  }

  Future<void> insertLines(List<PurchaseRequestLinesCompanion> lines) async {
    if (lines.isEmpty) return;
    await batch((b) => b.insertAll(purchaseRequestLines, lines));
  }

  /// Adds one line to a document that is still a draft.
  ///
  /// Returns `null` when the parent is not an editable draft. The status check
  /// and the insert share a transaction: without it a submit committing in the
  /// gap between them would let this insert land on a document nobody can edit
  /// any more (G-P5).
  Future<PurchaseRequestLineRow?> insertDraftLine({
    required String prId,
    required PurchaseRequestLinesCompanion line,
  }) {
    return transaction(() async {
      if (!await isDraft(prId)) return null;
      return into(purchaseRequestLines).insertReturning(line);
    });
  }

  /// Adds one opname link to a draft. Guarded exactly like [insertDraftLine].
  Future<PurchaseRequestOpnameRow?> insertDraftOpnameLink({
    required String prId,
    required PurchaseRequestOpnamesCompanion link,
  }) {
    return transaction(() async {
      if (!await isDraft(prId)) return null;
      return into(purchaseRequestOpnames).insertReturning(link);
    });
  }

  /// Needed date and header note of a draft.
  ///
  /// The `status = 'draft'` predicate is evaluated by SQLite in the same
  /// statement as the write, so there is no window between reading the status
  /// and applying the change. Returns the number of updated rows: 0 means the
  /// document is gone or is no longer a draft.
  ///
  /// `needed_date` is a civil date and is written verbatim — no timezone
  /// conversion (T-9).
  Future<int> updateDraftHeader({
    required String prId,
    required DateTime? neededDate,
    required String? note,
  }) {
    return (update(purchaseRequests)..where(
          (t) =>
              t.id.equals(prId) &
              t.status.equalsValue(PurchaseRequestStatus.draft) &
              t.deletedAt.isNull(),
        ))
        .write(
          PurchaseRequestsCompanion(
            neededDate: Value(neededDate),
            note: Value(note),
            updatedAt: Value(DateTime.now().toUtc()),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  /// The requested quantity and note of one draft line.
  ///
  /// `suggested_qty` is not in the SET list: it is a snapshot the branch head
  /// cannot edit, and the only path that rewrites it is
  /// [updateDraftLineSuggestion], which the recompute uses.
  Future<int> updateDraftLine({
    required String lineId,
    required int requestedQtyMilliUnits,
    required String? note,
  }) {
    return customUpdate(
      'UPDATE purchase_request_lines '
      'SET requested_qty = ?, note = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND deleted_at IS NULL AND pr_id IN ('
      '  SELECT id FROM purchase_requests '
      "  WHERE status = 'draft' AND deleted_at IS NULL"
      ');',
      variables: [
        Variable<int>(requestedQtyMilliUnits),
        Variable<String>(note),
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
      ],
      updates: {purchaseRequestLines},
      updateKind: UpdateKind.update,
    );
  }

  /// Rewrites the system's suggestion for one draft line.
  ///
  /// Reached only when the draft's opname selection changes, which is the one
  /// moment the snapshot is allowed to move (§14). It is a separate method from
  /// [updateDraftLine] on purpose: the branch head's editor must have no way to
  /// reach this column, and a single method taking both quantities would be one
  /// careless call site away from letting it.
  Future<int> updateDraftLineSuggestion({
    required String lineId,
    required int suggestedQtyMilliUnits,
  }) {
    return customUpdate(
      'UPDATE purchase_request_lines '
      'SET suggested_qty = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND deleted_at IS NULL AND pr_id IN ('
      '  SELECT id FROM purchase_requests '
      "  WHERE status = 'draft' AND deleted_at IS NULL"
      ');',
      variables: [
        Variable<int>(suggestedQtyMilliUnits),
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
      ],
      updates: {purchaseRequestLines},
      updateKind: UpdateKind.update,
    );
  }

  /// Soft-deletes a line of a draft. Lines of submitted and later documents
  /// survive every call (G-P5).
  Future<int> softDeleteDraftLine(String lineId) {
    return customUpdate(
      'UPDATE purchase_request_lines '
      'SET deleted_at = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND deleted_at IS NULL AND pr_id IN ('
      '  SELECT id FROM purchase_requests '
      "  WHERE status = 'draft' AND deleted_at IS NULL"
      ');',
      variables: [
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(lineId),
      ],
      updates: {purchaseRequestLines},
      updateKind: UpdateKind.update,
    );
  }

  /// Soft-deletes one opname link of a draft.
  Future<int> softDeleteDraftOpnameLink(String linkId) {
    return customUpdate(
      'UPDATE purchase_request_opnames '
      'SET deleted_at = ?, updated_at = ?, sync_status = ? '
      'WHERE id = ? AND deleted_at IS NULL AND pr_id IN ('
      '  SELECT id FROM purchase_requests '
      "  WHERE status = 'draft' AND deleted_at IS NULL"
      ');',
      variables: [
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<String>(SyncStatus.pending.dbValue),
        Variable<String>(linkId),
      ],
      updates: {purchaseRequestOpnames},
      updateKind: UpdateKind.update,
    );
  }

  /// `draft → submitted`.
  ///
  /// The `WHERE status = 'draft'` clause makes a lost update impossible: a
  /// return value of 0 means somebody else moved the document first. The
  /// instant is forced to UTC here rather than trusted from the caller (T-1) —
  /// drift serialises a non-UTC `DateTime` with an offset suffix, so a value
  /// that arrived in operational time would be *stored* as a different instant
  /// than the one the domain validated.
  Future<int> submit({required String prId, required DateTime submittedAtUtc}) {
    return _transition(
      prId: prId,
      from: PurchaseRequestStatus.draft,
      to: PurchaseRequestStatus.submitted,
      values: PurchaseRequestsCompanion(
        submittedAt: Value(submittedAtUtc.toUtc()),
      ),
    );
  }

  /// `submitted → processing`. Records who took the order on and when.
  Future<int> markProcessing({
    required String prId,
    required String processedBy,
    required DateTime processingAtUtc,
  }) {
    return _transition(
      prId: prId,
      from: PurchaseRequestStatus.submitted,
      to: PurchaseRequestStatus.processing,
      values: PurchaseRequestsCompanion(
        processingAt: Value(processingAtUtc.toUtc()),
        processedBy: Value(processedBy),
      ),
    );
  }

  /// `draft → cancelled` or `submitted → cancelled`.
  ///
  /// [from] is required rather than inferred, so the caller states the
  /// transition it believes it is making and `processing` can never be reached
  /// by passing the wrong argument (G-S3).
  Future<int> cancel({
    required String prId,
    required PurchaseRequestStatus from,
    required String cancelledBy,
    required DateTime cancelledAtUtc,
    required String reason,
  }) {
    return _transition(
      prId: prId,
      from: from,
      to: PurchaseRequestStatus.cancelled,
      values: PurchaseRequestsCompanion(
        cancelledAt: Value(cancelledAtUtc.toUtc()),
        cancelledBy: Value(cancelledBy),
        cancelReason: Value(reason),
      ),
    );
  }

  /// `processing → rejected`.
  Future<int> reject({
    required String prId,
    required String rejectedBy,
    required DateTime rejectedAtUtc,
    required String reason,
  }) {
    return _transition(
      prId: prId,
      from: PurchaseRequestStatus.processing,
      to: PurchaseRequestStatus.rejected,
      values: PurchaseRequestsCompanion(
        rejectedAt: Value(rejectedAtUtc.toUtc()),
        rejectedBy: Value(rejectedBy),
        rejectReason: Value(reason),
      ),
    );
  }

  /// Soft-deletes a draft. Submitted and later documents are permanent
  /// (G-S2/G-A5) and this guard is what makes the workflow unable to remove
  /// them.
  Future<int> softDeleteDraft(String prId) {
    return (update(purchaseRequests)..where(
          (t) =>
              t.id.equals(prId) &
              t.status.equalsValue(PurchaseRequestStatus.draft) &
              t.deletedAt.isNull(),
        ))
        .write(
          PurchaseRequestsCompanion(
            deletedAt: Value(DateTime.now().toUtc()),
            updatedAt: Value(DateTime.now().toUtc()),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  /// The one status writer, private so no caller can invent a transition.
  ///
  /// Every public transition above funnels through here with its `from` spelled
  /// out, so the predicate and the write are always one statement.
  Future<int> _transition({
    required String prId,
    required PurchaseRequestStatus from,
    required PurchaseRequestStatus to,
    required PurchaseRequestsCompanion values,
  }) {
    return (update(purchaseRequests)..where(
          (t) =>
              t.id.equals(prId) &
              t.status.equalsValue(from) &
              t.deletedAt.isNull(),
        ))
        .write(
          values.copyWith(
            status: Value(to),
            updatedAt: Value(DateTime.now().toUtc()),
            // Once the document leaves the device it is the server's to confirm
            // (G-Y2), so every transition queues a sync.
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
  }

  // --- reads ----------------------------------------------------------------

  Future<PurchaseRequestRow?> headerById(String id) => (select(
    purchaseRequests,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  Future<bool> isDraft(String prId) async {
    final row = await headerById(prId);
    return row?.status == PurchaseRequestStatus.draft;
  }

  /// The four columns that decide whether somebody may open this document.
  ///
  /// Deliberately not `headerById` and deliberately not the joined summary: an
  /// authorization check must not be the reason a foreign document's number,
  /// note, quantities or cited opnames are read. When [branchId] is supplied the
  /// predicate is in the statement, so a row from another branch never leaves
  /// SQLite at all and the caller cannot leak what it never received.
  ///
  /// Returns `null` both for "no such document" and for "not this branch", and
  /// that ambiguity is the point: telling them apart would turn the address bar
  /// into a way to enumerate documents across the clinic group.
  ///
  /// [branchId] is `null` for the warehouse, whose workflow spans every branch.
  Future<PurchaseRequestAccessRow?> accessScope({
    required String prId,
    String? branchId,
  }) async {
    final row =
        await (selectOnly(purchaseRequests)
              ..addColumns([
                purchaseRequests.id,
                purchaseRequests.branchId,
                purchaseRequests.status,
                purchaseRequests.requestedBy,
              ])
              ..where(
                purchaseRequests.id.equals(prId) &
                    purchaseRequests.deletedAt.isNull() &
                    (branchId == null
                        ? const Constant(true)
                        : purchaseRequests.branchId.equals(branchId)),
              ))
            .getSingleOrNull();
    if (row == null) return null;

    return PurchaseRequestAccessRow(
      prId: row.read(purchaseRequests.id)!,
      branchId: row.read(purchaseRequests.branchId)!,
      status: row.readWithConverter(purchaseRequests.status)!,
      requestedBy: row.read(purchaseRequests.requestedBy)!,
    );
  }

  /// The G-P4 lookup: the branch's live `submitted`/`processing` document, if
  /// any. The partial unique index guarantees there is at most one.
  Future<PurchaseRequestRow?> activeRequestForBranch(String branchId) {
    return (select(purchaseRequests)
          ..where(
            (t) =>
                t.branchId.equals(branchId) &
                t.deletedAt.isNull() &
                t.status.isIn(_activeStatusValues),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  static final List<String> _activeStatusValues = [
    PurchaseRequestStatus.submitted.dbValue,
    PurchaseRequestStatus.processing.dbValue,
  ];

  /// Whether this item already has a live line on the document — the check
  /// behind "do not request the same item twice" (G-P2).
  Future<PurchaseRequestLineRow?> findLineByItem({
    required String prId,
    required String itemId,
  }) {
    return (select(purchaseRequestLines)..where(
          (t) =>
              t.prId.equals(prId) &
              t.itemId.equals(itemId) &
              t.deletedAt.isNull(),
        ))
        .getSingleOrNull();
  }

  Future<PurchaseRequestLineRow?> lineById(String id) => (select(
    purchaseRequestLines,
  )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();

  /// The item id of every live line, read **without joining `items`**.
  ///
  /// [detailLines] inner-joins the item so a line can render its name and unit,
  /// which means a line whose item row is physically gone silently vanishes from
  /// the result instead of raising anything. On a draft that is merely wrong; at
  /// submit it would validate a document against fewer lines than it has, and a
  /// warehouse would then be shown an order that is missing a position nobody
  /// noticed. This query is the honest count those paths check themselves
  /// against — a join can hide a row, a plain select cannot.
  Future<List<String>> lineItemIds(String prId) async {
    final rows =
        await (selectOnly(purchaseRequestLines)
              ..addColumns([purchaseRequestLines.itemId])
              ..where(
                purchaseRequestLines.prId.equals(prId) &
                    purchaseRequestLines.deletedAt.isNull(),
              ))
            .get();
    return rows
        .map((row) => row.read(purchaseRequestLines.itemId)!)
        .toList(growable: false);
  }

  /// The opname id of every live link, read without joining `stock_opnames`.
  /// The counterpart of [lineItemIds] for the citation half of the document.
  Future<List<String>> linkedOpnameIds(String prId) async {
    final rows =
        await (selectOnly(purchaseRequestOpnames)
              ..addColumns([purchaseRequestOpnames.opnameId])
              ..where(
                purchaseRequestOpnames.prId.equals(prId) &
                    purchaseRequestOpnames.deletedAt.isNull(),
              ))
            .get();
    return rows
        .map((row) => row.read(purchaseRequestOpnames.opnameId)!)
        .toList(growable: false);
  }

  /// Live link rows of a document, without any join at all — used by the
  /// recompute to decide which links to soft-delete.
  Future<List<PurchaseRequestOpnameRow>> opnameLinksOf(String prId) => (select(
    purchaseRequestOpnames,
  )..where((t) => t.prId.equals(prId) & t.deletedAt.isNull())).get();

  Future<List<PurchaseRequestLineRow>> linesOf(String prId) => (select(
    purchaseRequestLines,
  )..where((t) => t.prId.equals(prId) & t.deletedAt.isNull())).get();

  // --- joined line reads ----------------------------------------------------

  JoinedSelectStatement<HasResultSet, dynamic> _detailLinesQuery(String prId) {
    return select(purchaseRequestLines).join([
        innerJoin(items, items.id.equalsExp(purchaseRequestLines.itemId)),
      ])
      ..where(
        purchaseRequestLines.prId.equals(prId) &
            purchaseRequestLines.deletedAt.isNull(),
      )
      ..orderBy([OrderingTerm.asc(items.name)]);
  }

  List<PurchaseRequestLineWithDetails> _mapLines(List<TypedResult> rows) {
    return rows
        .map(
          (row) => PurchaseRequestLineWithDetails(
            line: row.readTable(purchaseRequestLines),
            item: row.readTable(items),
          ),
        )
        .toList(growable: false);
  }

  Future<List<PurchaseRequestLineWithDetails>> detailLines(String prId) async =>
      _mapLines(await _detailLinesQuery(prId).get());

  Stream<List<PurchaseRequestLineWithDetails>> watchDetailLines(String prId) =>
      _detailLinesQuery(prId).watch().map(_mapLines);

  // --- joined opname-link reads ---------------------------------------------

  late final $UsersTable _counters = alias(users, 'counted_by_user');

  Expression<int> get _opnameDifferenceCount => stockOpnameLines.id.count(
    distinct: true,
    filter:
        stockOpnameLines.difference.isNotValue(0) &
        stockOpnameLines.deletedAt.isNull(),
  );

  JoinedSelectStatement<HasResultSet, dynamic> _linkedOpnamesQuery(
    String prId,
  ) {
    final query =
        (select(
          purchaseRequestOpnames,
        )..where((t) => t.prId.equals(prId) & t.deletedAt.isNull())).join([
          innerJoin(
            stockOpnames,
            stockOpnames.id.equalsExp(purchaseRequestOpnames.opnameId),
          ),
          innerJoin(rooms, rooms.id.equalsExp(stockOpnames.roomId)),
          innerJoin(_counters, _counters.id.equalsExp(stockOpnames.countedBy)),
          leftOuterJoin(
            stockOpnameLines,
            stockOpnameLines.opnameId.equalsExp(stockOpnames.id) &
                stockOpnameLines.deletedAt.isNull(),
          ),
        ]);

    return query
      ..addColumns([_opnameDifferenceCount])
      ..groupBy([purchaseRequestOpnames.id])
      ..orderBy([
        OrderingTerm.desc(stockOpnames.periodYear),
        OrderingTerm.desc(stockOpnames.periodWeek),
        OrderingTerm.asc(rooms.code),
      ]);
  }

  List<PurchaseRequestOpnameWithDetails> _mapLinkedOpnames(
    List<TypedResult> rows,
  ) {
    return rows
        .map(
          (row) => PurchaseRequestOpnameWithDetails(
            link: row.readTable(purchaseRequestOpnames),
            opname: row.readTable(stockOpnames),
            room: row.readTable(rooms),
            countedBy: row.readTable(_counters),
            differenceLineCount: row.read(_opnameDifferenceCount) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<List<PurchaseRequestOpnameWithDetails>> linkedOpnames(
    String prId,
  ) async => _mapLinkedOpnames(await _linkedOpnamesQuery(prId).get());

  Stream<List<PurchaseRequestOpnameWithDetails>> watchLinkedOpnames(
    String prId,
  ) => _linkedOpnamesQuery(prId).watch().map(_mapLinkedOpnames);

  /// Every live opname line of one document, with its item — the raw material
  /// the suggestion calculator works from.
  ///
  /// Reads the *snapshot* (`counted_qty`), never a current balance: the whole
  /// point of basing a Purchase Request on an opname is that the numbers are the
  /// ones somebody physically counted.
  Future<List<StockOpnameLineRow>> opnameLinesOf(String opnameId) => (select(
    stockOpnameLines,
  )..where((t) => t.opnameId.equals(opnameId) & t.deletedAt.isNull())).get();

  // --- eligible opnames (G-P1) ----------------------------------------------

  /// The opnames a branch head may cite, restricted **inside the statement** to
  /// their own branch, to `submitted`/`reviewed`, and to the operational ISO
  /// weeks [periods] names.
  ///
  /// The periods arrive as `(year, week)` pairs rather than as a week number and
  /// a tolerance, because "current or previous week" is not a numeric range: at
  /// new year `2026-W01`'s predecessor is `2025-W52` or `2025-W53` depending on
  /// the year. Working that out is `OperationalIsoWeek`'s job; this query only
  /// matches the pairs it was given.
  Future<List<EligibleOpnameRow>> eligibleOpnames({
    required String branchId,
    required List<OpnamePeriodKey> periods,
  }) async {
    if (periods.isEmpty) return const <EligibleOpnameRow>[];

    var periodPredicate = const Constant(false) as Expression<bool>;
    for (final period in periods) {
      periodPredicate =
          periodPredicate |
          (stockOpnames.periodYear.equals(period.year) &
              stockOpnames.periodWeek.equals(period.week));
    }

    final rows = await _opnameReferenceQuery(
      stockOpnames.branchId.equals(branchId) &
          stockOpnames.status.isIn(_referenceableOpnameStatuses) &
          periodPredicate,
    ).get();
    return _mapOpnameReferences(rows);
  }

  /// G-O4/G-P1: only a count that has left the nurse's hands may back a PR.
  static final List<String> _referenceableOpnameStatuses = [
    StockOpnameStatus.submitted.dbValue,
    StockOpnameStatus.reviewed.dbValue,
  ];

  /// One opname with its room and nurse, **unscoped and unfiltered by status**.
  ///
  /// Deliberately not [eligibleOpnames] with an extra id predicate: the create
  /// and submit validation has to be able to tell a branch head *why* a citation
  /// was refused — wrong branch, still a draft, too old — and a query that already
  /// filters those cases away can only ever answer "not found". Loading the row
  /// first and applying `PurchaseRequestOpnameEligibilityPolicy` to it is what
  /// makes a precise message possible.
  ///
  /// The row is not a document the caller may *read*: it is the actor's own branch
  /// in every legitimate case, and the one illegitimate case — another branch's
  /// count — is refused by the policy before anything is rendered.
  Future<EligibleOpnameRow?> opnameReferenceById(String opnameId) async {
    final rows = await _opnameReferenceQuery(
      stockOpnames.id.equals(opnameId),
    ).get();
    return rows.isEmpty ? null : _mapOpnameReferences(rows).single;
  }

  JoinedSelectStatement<HasResultSet, dynamic> _opnameReferenceQuery(
    Expression<bool> predicate,
  ) {
    // The room and the nurse are inner-joined without an `is_active` filter, so a
    // citation whose room was retired after the count still resolves — the
    // repository turns that into a historical badge rather than a vanished row.
    return (select(stockOpnames)..where((t) => t.deletedAt.isNull())).join([
        innerJoin(rooms, rooms.id.equalsExp(stockOpnames.roomId)),
        innerJoin(_counters, _counters.id.equalsExp(stockOpnames.countedBy)),
        leftOuterJoin(
          stockOpnameLines,
          stockOpnameLines.opnameId.equalsExp(stockOpnames.id) &
              stockOpnameLines.deletedAt.isNull(),
        ),
      ])
      ..addColumns([_opnameDifferenceCount])
      ..where(predicate)
      ..groupBy([stockOpnames.id])
      ..orderBy([
        OrderingTerm.desc(stockOpnames.periodYear),
        OrderingTerm.desc(stockOpnames.periodWeek),
        OrderingTerm.asc(rooms.code),
      ]);
  }

  List<EligibleOpnameRow> _mapOpnameReferences(List<TypedResult> rows) {
    return rows
        .map(
          (row) => EligibleOpnameRow(
            opname: row.readTable(stockOpnames),
            room: row.readTable(rooms),
            countedBy: row.readTable(_counters),
            differenceLineCount: row.read(_opnameDifferenceCount) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  // --- summaries ------------------------------------------------------------

  late final $UsersTable _processors = alias(users, 'processed_by_user');
  late final $UsersTable _cancellers = alias(users, 'cancelled_by_user');
  late final $UsersTable _rejecters = alias(users, 'rejected_by_user');

  // Both counters are DISTINCT because the query left-joins lines *and* opname
  // links, and those two produce a cross product. Without `distinct` a document
  // with 3 lines and 2 citations would report 6 of each.
  Expression<int> get _lineCount => purchaseRequestLines.id.count(
    distinct: true,
    filter: purchaseRequestLines.deletedAt.isNull(),
  );

  Expression<int> get _linkedOpnameCount => purchaseRequestOpnames.id.count(
    distinct: true,
    filter: purchaseRequestOpnames.deletedAt.isNull(),
  );

  JoinedSelectStatement<HasResultSet, dynamic> _summaryQuery(
    Expression<bool> predicate,
  ) {
    final query = (select(purchaseRequests)..where((t) => t.deletedAt.isNull()))
        .join([
          innerJoin(branches, branches.id.equalsExp(purchaseRequests.branchId)),
          innerJoin(users, users.id.equalsExp(purchaseRequests.requestedBy)),
          leftOuterJoin(
            _processors,
            _processors.id.equalsExp(purchaseRequests.processedBy),
          ),
          leftOuterJoin(
            _cancellers,
            _cancellers.id.equalsExp(purchaseRequests.cancelledBy),
          ),
          leftOuterJoin(
            _rejecters,
            _rejecters.id.equalsExp(purchaseRequests.rejectedBy),
          ),
          // Left joins so a document with no lines and no citations still
          // produces a row, and soft-deleted children never inflate the counts.
          leftOuterJoin(
            purchaseRequestLines,
            purchaseRequestLines.prId.equalsExp(purchaseRequests.id) &
                purchaseRequestLines.deletedAt.isNull(),
          ),
          leftOuterJoin(
            purchaseRequestOpnames,
            purchaseRequestOpnames.prId.equalsExp(purchaseRequests.id) &
                purchaseRequestOpnames.deletedAt.isNull(),
          ),
        ]);

    return query
      ..addColumns([_lineCount, _linkedOpnameCount])
      ..where(predicate)
      ..groupBy([purchaseRequests.id])
      ..orderBy([OrderingTerm.desc(purchaseRequests.createdAt)]);
  }

  List<PurchaseRequestWithContext> _mapSummaries(List<TypedResult> rows) {
    return rows
        .map(
          (row) => PurchaseRequestWithContext(
            request: row.readTable(purchaseRequests),
            branch: row.readTable(branches),
            requestedBy: row.readTable(users),
            processedBy: row.readTableOrNull(_processors),
            cancelledBy: row.readTableOrNull(_cancellers),
            rejectedBy: row.readTableOrNull(_rejecters),
            lineCount: row.read(_lineCount) ?? 0,
            linkedOpnameCount: row.read(_linkedOpnameCount) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  /// The document predicate, optionally pinned to one branch.
  ///
  /// When [branchId] is supplied the check happens **inside the statement**, so
  /// a document from another branch is never read, never mapped and never
  /// reaches a stream a widget could be listening to. Filtering the result in
  /// Dart would look equivalent and would not be.
  Expression<bool> _document(String prId, String? branchId) {
    final byId = purchaseRequests.id.equals(prId);
    return branchId == null
        ? byId
        : byId & purchaseRequests.branchId.equals(branchId);
  }

  Future<PurchaseRequestWithContext?> summaryById(
    String prId, {
    String? branchId,
  }) async {
    final rows = await _summaryQuery(_document(prId, branchId)).get();
    return rows.isEmpty ? null : _mapSummaries(rows).single;
  }

  Stream<PurchaseRequestWithContext?> watchSummaryById(
    String prId, {
    String? branchId,
  }) {
    return _summaryQuery(
      _document(prId, branchId),
    ).watch().map((rows) => rows.isEmpty ? null : _mapSummaries(rows).single);
  }

  Expression<bool> _scope({
    String? branchId,
    Set<PurchaseRequestStatus> statuses = const {},
    String? searchQuery,
  }) {
    var predicate = const Constant(true) as Expression<bool>;
    if (branchId != null) {
      predicate = predicate & purchaseRequests.branchId.equals(branchId);
    }
    if (statuses.isNotEmpty) {
      predicate =
          predicate &
          purchaseRequests.status.isIn(
            statuses.map((status) => status.dbValue).toList(growable: false),
          );
    }
    final needle = searchQuery?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      // Document number or branch name, case-insensitive, entirely local so the
      // warehouse queue keeps searching offline (G-Y1).
      final pattern = '%$needle%';
      predicate =
          predicate &
          (purchaseRequests.docNumber.lower().like(pattern) |
              branches.name.lower().like(pattern));
    }
    return predicate;
  }

  Future<List<PurchaseRequestWithContext>> listRequests({
    String? branchId,
    Set<PurchaseRequestStatus> statuses = const {},
    String? searchQuery,
  }) async {
    final rows = await _summaryQuery(
      _scope(branchId: branchId, statuses: statuses, searchQuery: searchQuery),
    ).get();
    return _mapSummaries(rows);
  }

  Stream<List<PurchaseRequestWithContext>> watchRequests({
    String? branchId,
    Set<PurchaseRequestStatus> statuses = const {},
    String? searchQuery,
  }) {
    return _summaryQuery(
      _scope(branchId: branchId, statuses: statuses, searchQuery: searchQuery),
    ).watch().map(_mapSummaries);
  }

  /// Items a branch head may add to a draft by hand — active items only, filtered
  /// the way the SearchableDropdown filters (name or SKU, case-insensitive,
  /// optional category). Runs entirely against the local database (G-Y1).
  Future<List<Item>> searchAddableItems({
    required String query,
    String? categoryId,
    int limit = 8,
  }) {
    final pattern = '%${query.trim().toLowerCase()}%';
    return (select(items)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.isActive.equals(true) &
                (t.name.lower().like(pattern) | t.sku.lower().like(pattern)) &
                (categoryId == null
                    ? const Constant(true)
                    : t.categoryId.equals(categoryId)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(limit))
        .get();
  }
}
