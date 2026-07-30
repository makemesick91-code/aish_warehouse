import 'package:drift/drift.dart';

import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';

/// One row per **file that was successfully written** (schema v12, G-L2).
///
/// ### What this table is, and what it is not
///
/// It is the audit trail G-L2 demands — *"setiap ekspor (Excel/PDF) dicatat di
/// `export_logs` (siapa, laporan apa, lokasi & periode apa, kapan)"*. It is **not**
/// a file archive: the artifacts live in an app-private cache directory the OS may
/// clear at any time, and nothing here points at bytes that are guaranteed to still
/// exist. `file_name` records the name the user saw and shared, not a path — a
/// stored path would be a promise this module cannot keep, and an absolute path is
/// an internal detail that has no business in an audit row.
///
/// ### Append-only, and stricter than the ledger about it
///
/// `stock_movements` is append-only because a correction is a new movement (G-A1);
/// this table is append-only because an audit trail somebody can edit is not one.
/// [ReportingDao] therefore exposes exactly one writer — an insert — and no update,
/// no soft delete and no hard delete. Re-exporting the same report produces a
/// *second* row rather than touching the first, because it is a second export: a
/// different person may have run it, at a different time, against data that had
/// moved on.
///
/// The `deleted_at` column exists only because [BusinessColumns] gives every table
/// in this schema the same five columns (§2). Nothing in `lib/` ever writes it, and
/// the history reads do not filter on it — a "live rows only" predicate would be a
/// qualification with nothing behind it, and the one thing it would reliably do is
/// let a hand-written UPDATE hide an export from the audit.
///
/// ### The scope columns, and why the CHECK is written the way it is
///
/// Six scope shapes (§11), and each one pins `location_id` and `branch_id` to a
/// specific presence or absence. The CHECK states all six exhaustively rather than
/// as a handful of implications, so a seventh scope value added later fails every
/// branch and is refused by the database until somebody decides which shape it has.
///
/// Two things the CHECK deliberately **cannot** say:
///
/// * That a `room` scope's location is really a room. `stock_locations.type` is in
///   another table, and SQLite has no cross-table CHECK. [ReportFilterPolicy]
///   revalidates it against the location row on every preview and every export.
/// * Anything about `period_start <= period_end`. Both are civil dates stored as
///   TEXT, so a SQL comparison would be lexical — the exact trap schema v4 removed
///   from `stock_opnames`. Ordering is decided by [ReportPeriodPolicy] on
///   [DateOnly] values before the row is ever built.
///
/// ### The four extension columns
///
/// §2.3's list is `report_type`, `format`, `scope_type`, `location_id`,
/// `category_id`, `branch_id`, `period_start`, `period_end`, `exported_by`,
/// `file_name`. Four more are added here, and each answers a question the audit
/// could not otherwise answer:
///
/// * `item_id` — a Kartu Stok is a report *about one item*. Without it the row says
///   "somebody exported a stock card" and cannot say of what.
/// * `data_cutoff_at` — the UTC instant the snapshot was taken. G-L3 requires the
///   header to state *"data per kapan"*; storing it is what lets an auditor
///   reproduce the same numbers later.
/// * `sync_summary` — the synced/pending/conflict counts that header carried. Two
///   exports of the same filter minutes apart can legitimately differ, and this is
///   the column that explains why.
/// * `row_count` — how many data rows the file held. The cheapest possible check
///   that a file somebody still has is the file this row describes.
@DataClassName('ExportLogRow')
@TableIndex(name: 'idx_export_logs_actor', columns: {#exportedBy, #createdAt})
@TableIndex(name: 'idx_export_logs_type', columns: {#reportType, #createdAt})
@TableIndex(name: 'idx_export_logs_format', columns: {#format, #createdAt})
@TableIndex(name: 'idx_export_logs_scope', columns: {#scopeType, #createdAt})
@TableIndex(name: 'idx_export_logs_branch', columns: {#branchId, #createdAt})
@TableIndex(
  name: 'idx_export_logs_location',
  columns: {#locationId, #createdAt},
)
@TableIndex(
  name: 'idx_export_logs_category',
  columns: {#categoryId, #createdAt},
)
@TableIndex(name: 'idx_export_logs_item', columns: {#itemId, #createdAt})
@TableIndex(name: 'idx_export_logs_created_at', columns: {#createdAt})
class ExportLogs extends Table with BusinessColumns {
  /// Which report. Stored as the enum's `dbValue`, so the audit string and G-L5's
  /// filename token are the same token.
  TextColumn get reportType => text().map(const ReportTypeConverter())();

  TextColumn get format => text().map(const ReportFormatConverter())();

  TextColumn get scopeType => text().map(const ReportScopeTypeConverter())();

  /// The single stock location, for the three single-location scopes. NULL for
  /// `branch_all`, `cross_branch` and `all_locations` — see the class note.
  TextColumn get locationId =>
      text().nullable().references(StockLocations, #id)();

  /// The category filter that was applied, or NULL when the report was run across
  /// every category and grouped with subtotals instead (G-L6).
  TextColumn get categoryId =>
      text().nullable().references(ItemCategories, #id)();

  TextColumn get branchId => text().nullable().references(Branches, #id)();

  /// The item a Kartu Stok was run for. NULL on every other report, and NULL is
  /// also legitimate on a `stok_lokasi` run without an item filter.
  TextColumn get itemId => text().nullable().references(Items, #id)();

  /// Civil dates (T-8), carried as UTC midnights and never converted. For an as-of
  /// report both hold the same date (§3.9) — an audit row that left `period_start`
  /// NULL would make "as of one day" and "range whose start was lost" the same row.
  DateTimeColumn get periodStart => dateTime()();

  DateTimeColumn get periodEnd => dateTime()();

  /// Who ran it (G-L2). Never nullable: an export with no actor is not an audit
  /// record.
  TextColumn get exportedBy => text().references(Users, #id)();

  /// The canonical name the file was written and shared under (G-L5). Not a path.
  TextColumn get fileName => text().withLength(min: 1, max: 255)();

  /// UTC instant the report snapshot was taken — the "data per" of G-L3.
  DateTimeColumn get dataCutoffAt => dateTime()();

  /// Human-readable sync snapshot, e.g. *"18 tersinkron · 2 pending · 0 konflik"*.
  /// Non-blank: a header that printed nothing here would be a header that did not
  /// answer G-L3.
  TextColumn get syncSummary => text()();

  /// Data rows in the exported file. Zero is legitimate — an empty report still
  /// produces a valid file carrying its header and *"Tidak ada data"* (§52), and
  /// an export that found nothing is exactly the kind of thing an audit should
  /// record rather than swallow.
  IntColumn get rowCount => integer()();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the three type converters: a hand-written UPDATE
    // cannot introduce a value the Dart enums do not know.
    "CHECK (report_type IN ('stok_lokasi', 'kartu_stok', 'rekap_opname', "
        "'rekap_pr', 'rekap_do', 'rekap_gr', 'rekap_distribusi', "
        "'rekap_pemakaian', 'rekap_pemusnahan', 'rekap_retur', 'kadaluarsa'))",
    "CHECK (format IN ('xlsx', 'pdf'))",
    "CHECK (scope_type IN ('warehouse', 'branch_store', 'room', 'branch_all', "
        "'cross_branch', 'all_locations'))",
    // All six scopes, stated exhaustively — see the class note. `branch_all` with
    // a NULL branch is the one this most exists to refuse: it would make an audit
    // row unable to say whether one branch or every branch was exported.
    "CHECK ((scope_type = 'warehouse' AND location_id IS NOT NULL "
        'AND branch_id IS NULL) '
        "OR (scope_type = 'branch_store' AND location_id IS NOT NULL "
        'AND branch_id IS NOT NULL) '
        "OR (scope_type = 'room' AND location_id IS NOT NULL "
        'AND branch_id IS NOT NULL) '
        "OR (scope_type = 'branch_all' AND location_id IS NULL "
        'AND branch_id IS NOT NULL) '
        "OR (scope_type = 'cross_branch' AND location_id IS NULL "
        'AND branch_id IS NULL) '
        "OR (scope_type = 'all_locations' AND location_id IS NULL "
        'AND branch_id IS NULL))',
    // `IS NOT NULL` is written out rather than left to `trim(...) <> ''`, and that
    // is load-bearing: SQLite treats a CHECK whose result is **NULL as satisfied**,
    // and `trim(NULL) <> ''` is NULL. Both columns are already NOT NULL, so this is
    // defence in depth against a future migration relaxing one.
    "CHECK (file_name IS NOT NULL AND trim(file_name) <> '')",
    "CHECK (sync_summary IS NOT NULL AND trim(sync_summary) <> '')",
    'CHECK (row_count >= 0)',
  ];
}
