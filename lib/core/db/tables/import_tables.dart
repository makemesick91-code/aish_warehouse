import 'package:drift/drift.dart';

import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';

/// One row per **import that reached full validation** (schema v13, G-M6).
///
/// ### What this table is, and when the row appears
///
/// G-M6 asks for *"setiap impor dicatat di `import_logs` (file, jumlah baris
/// masuk/update/gagal, siapa, kapan); file sumber disimpan untuk audit"*. G-M3
/// separately forbids the preview stage from touching master data. §2.3 of the
/// specification lists `validated` among this table's statuses, so the two rules
/// have to be reconciled rather than picked between, and the reading this schema
/// implements is stated once here:
///
/// > A row is written when validation **completes** — every row parsed,
/// > normalized and checked — and before a single master row is written. That is
/// > an audit side effect, not a master-data mutation: the six master tables,
/// > `stock_locations`, the balances, the ledger and every workflow table are
/// > byte-for-byte what they were.
///
/// The consequence is deliberate: an import that was previewed and then
/// abandoned still leaves a trail. Somebody uploaded a file of 400 users, saw 87
/// errors, and walked away — that happened, and an audit that only recorded the
/// imports which succeeded would be an audit of successes.
///
/// ### Unlike `export_logs`, this row is updated — exactly twice at most
///
/// An export log is written once and never touched (§2.3 of Milestone 10). An
/// import log has a life: `validated → committed` or `validated → discarded`
/// (§3.4), and both transitions are guarded on the *current* status inside the
/// commit transaction, so two devices racing to commit the same preview produce
/// one winner and one `ImportAlreadyCommittedFailure`. There is no transition
/// out of either end state, and no writer anywhere in `lib/` deletes a row or
/// sets `deleted_at`.
///
/// `deleted_at` exists only because [BusinessColumns] gives every table in this
/// schema the same five columns (§2). Nothing writes it, and the history reads do
/// not filter on it — a "live rows only" predicate would be a qualification with
/// nothing behind it, and the one thing it would reliably do is let a
/// hand-written UPDATE hide an import from the audit.
///
/// ### No unique index, anywhere
///
/// The same file may be imported twice, and that is two events: a second person
/// may have run it, against data that had moved on, and the second run's counts
/// are genuinely different. A unique index on `file_sha256` — the tempting one —
/// would collapse the second import out of the trail, which is the one outcome an
/// audit may never have. `file_sha256` is indexed for *lookup*, not uniqueness.
///
/// ### The four extension columns
///
/// §2.3's list is `entity`, `file_name`, `total_rows`, `inserted_rows`,
/// `updated_rows`, `failed_rows`, `error_detail`, `status`, `imported_by`. Four
/// more are added here, and each answers a question the audit could not otherwise
/// answer:
///
/// * `stored_file_path` — where the retained source copy lives. Unlike
///   `export_logs`, which stores no path because the artifact may be swept from a
///   cache directory, G-M6 *requires* the source file to survive, so it is written
///   to app documents rather than to a cache and the row points at it. It is an
///   internal detail and is never rendered to a user (§28).
/// * `file_sha256` — lets a commit prove the bytes it re-parses are the bytes the
///   preview validated, and lets an auditor prove the retained copy was not
///   swapped afterwards.
/// * `file_size_bytes` — the second half of the same check, and the cheapest one.
/// * `template_version` — which template generation the file came from (§13).
///   Without it, an import that failed on a header can never be explained after
///   the template moves on.
@DataClassName('ImportLogRow')
@TableIndex(
  name: 'idx_import_logs_entity_status',
  columns: {#entity, #status, #createdAt},
)
@TableIndex(name: 'idx_import_logs_status', columns: {#status, #createdAt})
@TableIndex(name: 'idx_import_logs_actor', columns: {#importedBy, #createdAt})
@TableIndex(name: 'idx_import_logs_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_import_logs_sha256', columns: {#fileSha256})
@TableIndex(name: 'idx_import_logs_sync', columns: {#syncStatus, #createdAt})
class ImportLogs extends Table with BusinessColumns {
  /// Which master entity was imported. Stored as the enum's `dbValue`, which is
  /// the physical table name — so the audit row names the table it touched.
  TextColumn get entity => text().map(const ImportEntityConverter())();

  /// The name the user's file had when they picked it. Not a path.
  TextColumn get fileName => text().withLength(min: 1, max: 255)();

  /// Data rows the workbook held, blank rows and the template's sample row
  /// excluded. Zero is legitimate: an empty-but-valid template is a thing a user
  /// can upload, and an import of nothing is exactly what the audit should say.
  IntColumn get totalRows => integer()();

  IntColumn get insertedRows => integer()();

  IntColumn get updatedRows => integer()();

  IntColumn get failedRows => integer()();

  /// Structured JSON, one object per issue, deterministically ordered (§32).
  ///
  /// NULL when nothing failed. Never the raw rows: a workbook of users would put
  /// every full name and email into a column that outlives the file.
  TextColumn get errorDetail => text().nullable()();

  TextColumn get status => text().map(const ImportStatusConverter())();

  /// Who ran it (G-M6). Never nullable: an import with no actor is not an audit
  /// record.
  TextColumn get importedBy => text().references(Users, #id)();

  /// Absolute path of the retained source copy under app documents (§3.8).
  ///
  /// **Never rendered to a user.** An app-private path tells an administrator
  /// nothing they can act on, and §36 keeps paths out of every screen.
  TextColumn get storedFilePath => text().withLength(min: 1, max: 1024)();

  /// Lowercase hex SHA-256 of the source bytes.
  TextColumn get fileSha256 => text().withLength(min: 64, max: 64)();

  IntColumn get fileSizeBytes => integer()();

  /// The template generation the workbook declared, e.g. `aish-master-v1`.
  TextColumn get templateVersion => text().withLength(min: 1, max: 64)();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the two type converters: a hand-written UPDATE
    // cannot introduce a value the Dart enums do not know.
    "CHECK (entity IN ('items', 'item_categories', 'branches', 'rooms', "
        "'users', 'item_batches'))",
    "CHECK (status IN ('validated', 'committed', 'discarded'))",
    // `IS NOT NULL` is written out rather than left to `trim(...) <> ''`, and
    // that is load-bearing: SQLite treats a CHECK whose result is **NULL as
    // satisfied**, and `trim(NULL) <> ''` is NULL. All four columns are already
    // NOT NULL, so this is defence in depth against a future migration relaxing
    // one.
    "CHECK (file_name IS NOT NULL AND trim(file_name) <> '')",
    "CHECK (stored_file_path IS NOT NULL AND trim(stored_file_path) <> '')",
    "CHECK (template_version IS NOT NULL AND trim(template_version) <> '')",
    // 64 lowercase hex characters. `GLOB` rather than `LIKE` because SQLite's
    // `LIKE` is case-insensitive by default, which would let `ABC…` through and
    // make two rows describing one file compare unequal.
    "CHECK (file_sha256 IS NOT NULL AND length(file_sha256) = 64 "
        "AND file_sha256 GLOB '[0-9a-f]*' "
        "AND file_sha256 NOT GLOB '*[^0-9a-f]*')",
    'CHECK (file_size_bytes > 0)',
    'CHECK (total_rows >= 0)',
    'CHECK (inserted_rows >= 0)',
    'CHECK (updated_rows >= 0)',
    'CHECK (failed_rows >= 0)',
    // The counting invariant of §31, in the database rather than only in the use
    // case: every row the workbook held was inserted, updated, or failed.
    'CHECK (total_rows = inserted_rows + updated_rows + failed_rows)',
    // G-M3's *"hanya bisa dijalankan jika 0 error"*, stated where a hand-written
    // UPDATE cannot get around it.
    "CHECK (status <> 'committed' OR failed_rows = 0)",
    // A failure count with no explanation is an audit row that says something
    // went wrong and refuses to say what.
    "CHECK (failed_rows = 0 OR (error_detail IS NOT NULL "
        "AND trim(error_detail) <> ''))",
  ];
}
