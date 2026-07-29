import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';

/// Stok Opname header — one physical count of one room for one ISO week
/// (schema v3, spec §2.3).
///
/// `UNIQUE(room_id, period_year, period_week)` is the database half of G-O1:
/// even if two devices race, only one weekly count per room can ever be
/// committed. The use case checks first for a friendly message; this constraint
/// is the guarantee.
///
/// The period is an **ISO week of the operational calendar (GMT+8)**, computed
/// by `AppTimeZone.isoWeekYear` / `AppTimeZone.isoWeekNumber` (T-3). It is
/// deliberately stored as two integers rather than a date range so the weekly
/// key is exact and indexable.
@DataClassName('StockOpnameRow')
@TableIndex(
  name: 'idx_stock_opnames_branch_status',
  columns: {#branchId, #status},
)
// The weekly key is a *partial* unique index rather than a plain UNIQUE
// constraint, because uniqueness must apply to live documents only: a draft
// that was soft deleted is history, and it must not block the room from being
// counted again that week. It doubles as the room/period query index.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_stock_opnames_room_period
  ON stock_opnames (room_id, period_year, period_week)
  WHERE deleted_at IS NULL;
''')
@TableIndex(
  name: 'idx_stock_opnames_counted_by_status',
  columns: {#countedBy, #status},
)
// Document numbers are unique among live documents, for the same reason the
// weekly key is: once the sync backend issues real numbers
// (`SO-{cabang}-{yyyyMMdd}-{seq}`), a soft-deleted document must not hold one
// hostage forever.
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_stock_opnames_doc_number
  ON stock_opnames (doc_number)
  WHERE deleted_at IS NULL;
''')
class StockOpnames extends Table with BusinessColumns {
  /// Temporary local number `TMP-SO-{uuid}` until a sync backend assigns the
  /// final `SO-{cabang}-{yyyyMMdd}-{seq}` on submit (G-Y4). Inventing a
  /// server-shaped number offline would produce duplicates across devices.
  /// Uniqueness is enforced by the partial index above, not by `.unique()`:
  /// a column-level UNIQUE would also bind soft-deleted rows.
  TextColumn get docNumber => text().withLength(min: 1, max: 64)();

  TextColumn get branchId => text().references(Branches, #id)();

  TextColumn get roomId => text().references(Rooms, #id)();

  /// ISO week-numbering year — differs from the calendar year around new year.
  IntColumn get periodYear => integer()();

  /// ISO week number, 1–53.
  IntColumn get periodWeek => integer()();

  /// The perawat who performs the count.
  TextColumn get countedBy => text().references(Users, #id)();

  TextColumn get status => text()
      .map(const StockOpnameStatusConverter())
      .clientDefault(() => StockOpnameStatus.draft.dbValue)();

  /// UTC instants (T-1); the UI converts to GMT+8 for display.
  DateTimeColumn get submittedAt => dateTime().nullable()();

  DateTimeColumn get reviewedAt => dateTime().nullable()();

  /// The kepala cabang who locked the document.
  @ReferenceName('reviewedOpnames')
  TextColumn get reviewedBy => text().nullable().references(Users, #id)();

  @override
  List<String> get customConstraints => [
    'CHECK (period_week BETWEEN 1 AND 53)',
    'CHECK (period_year BETWEEN 2000 AND 2999)',
    // Defence in depth behind the type converter: a hand-written UPDATE cannot
    // introduce a status the Dart enum does not know.
    "CHECK (status IN ('draft', 'submitted', 'reviewed'))",
    // Status and its metadata must agree. A draft carries neither timestamp; a
    // submitted document carries only `submitted_at`; a reviewed document
    // carries both plus its reviewer. This makes a half-applied review
    // impossible to persist even through raw SQL.
    "CHECK ((status = 'draft' AND submitted_at IS NULL "
        'AND reviewed_at IS NULL AND reviewed_by IS NULL) '
        "OR (status = 'submitted' AND submitted_at IS NOT NULL "
        'AND reviewed_at IS NULL AND reviewed_by IS NULL) '
        "OR (status = 'reviewed' AND submitted_at IS NOT NULL "
        'AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL))',
    // Segregation of duties (G-R4): nobody reviews their own count.
    'CHECK (reviewed_by IS NULL OR reviewed_by <> counted_by)',
    // Deliberately absent, and removed in schema v4: a CHECK comparing
    // `reviewed_at >= submitted_at`. Timestamps are stored as ISO-8601 TEXT,
    // so that operator is a *lexical* comparison — it orders characters, not
    // instants. Two equally valid serialisations of the same moment
    // (`…000Z` against `…000000Z`, or a `+08:00` suffix against a `Z` one)
    // would compare by their text, so the constraint could accept an
    // out-of-order pair and reject a correct one for no reason the data can
    // explain. Ordering is therefore decided by `DocumentTimestampPolicy` on
    // UTC `DateTime` instants, and the database restricts itself to the
    // question it can answer unambiguously: which timestamps a status must
    // and must not carry (the CHECK above).
  ];
}

/// One counted position of a Stok Opname.
///
/// Expiry-tracked items are counted **per batch** (one line per batch, G-E2);
/// items without expiry carry `batch_id IS NULL`. The two partial unique
/// indexes below express "one *live* line per item/batch" exactly. Both halves
/// of that matter: a plain UNIQUE would let several `NULL` batch rows through,
/// because SQLite treats every NULL as distinct, and without the
/// `deleted_at IS NULL` clause a line removed from a draft would permanently
/// block that position from being counted again.
///
/// All three quantities are INTEGER milli-units (Q-3). `difference` is a
/// **generated column**: the database computes `counted_qty - system_qty`
/// itself, so the stored difference can never disagree with its operands, and
/// it is the one quantity here that may be negative (Q-7).
@DataClassName('StockOpnameLineRow')
@TableIndex(name: 'idx_stock_opname_lines_opname', columns: {#opnameId})
@TableIndex(name: 'idx_stock_opname_lines_item', columns: {#itemId})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_stock_opname_lines_batched
  ON stock_opname_lines (opname_id, item_id, batch_id)
  WHERE batch_id IS NOT NULL AND deleted_at IS NULL;
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_stock_opname_lines_unbatched
  ON stock_opname_lines (opname_id, item_id)
  WHERE batch_id IS NULL AND deleted_at IS NULL;
''')
class StockOpnameLines extends Table with BusinessColumns {
  TextColumn get opnameId => text().references(StockOpnames, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  TextColumn get batchId => text().nullable().references(ItemBatches, #id)();

  /// Snapshot of the room balance at the moment the opname was created (G-O2).
  /// Nothing in the application updates this column after the insert.
  IntColumn get systemQty => integer()();

  /// Physically counted quantity in milli-units — `0.5` arrives here as 500.
  IntColumn get countedQty => integer()();

  /// `counted_qty - system_qty`, computed by SQLite. Negative means stock is
  /// missing, positive means there is more on the shelf than the system knew.
  IntColumn get difference =>
      integer().generatedAs(countedQty - systemQty, stored: true)();

  /// Reason for the difference. Mandatory when the difference is non-zero, but
  /// only *at submit time* (G-O3) — see the note on constraints below.
  TextColumn get note => text().nullable()();

  @override
  List<String> get customConstraints => [
    // G-O3, first half: a physical count is never negative.
    'CHECK (counted_qty >= 0)',
    // A snapshot of a balance, and balances are never negative (G-A2).
    'CHECK (system_qty >= 0)',
    // G-O3's "a difference needs a reason" is deliberately *not* a CHECK
    // constraint: a nurse must be able to save a draft with the count already
    // entered and the explanation still to be written. The rule is enforced
    // over the whole document by `SubmitStockOpnameUseCase`, which is also the
    // only moment at which it is meaningful.
  ];
}
