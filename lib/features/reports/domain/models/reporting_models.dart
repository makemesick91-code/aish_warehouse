/// Domain models for the reporting module.
///
/// The shape of this file follows one decision (§33): **every report builder
/// produces the same [ReportDocument]**, and the preview widget, the Excel exporter
/// and the PDF exporter all render that one model. Nothing downstream of a builder
/// queries the database, decides a business rule or recomputes a total — so the
/// three surfaces cannot disagree about what a subtotal is, which is exactly the
/// failure mode a per-format formula would guarantee.
///
/// Every quantity here is a [Quantity]. There is no `double` anywhere in this file,
/// and no `grandTotalQuantity` scalar either: §32 forbids adding pcs to box, so a
/// single cross-unit total is a number that must not exist rather than one that is
/// merely inconvenient.
library;

import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/date_only.dart';

/// The date range a report covers, in operational (GMT+8) civil dates, together
/// with the UTC half-open window they map to.
///
/// Built only by `ReportPeriodPolicy` — the constructor is private to this library
/// through that policy's factory, because the whole point is that the UTC boundary
/// is derived once rather than by whoever needs it next.
class ReportPeriod {
  const ReportPeriod({
    required this.periodStart,
    required this.periodEnd,
    required this.startUtc,
    required this.endExclusiveUtc,
  });

  /// Civil date, inclusive (T-8).
  final DateTime periodStart;

  /// Civil date, inclusive.
  final DateTime periodEnd;

  /// First UTC instant belonging to the period — 00:00 GMT+8 on [periodStart].
  final DateTime startUtc;

  /// First UTC instant **after** the period — 00:00 GMT+8 on the day after
  /// [periodEnd]. Half-open, so a movement stamped exactly here belongs to the
  /// next period and is counted once, by that one.
  final DateTime endExclusiveUtc;

  bool get isSingleDay => DateOnly.isSameDate(periodStart, periodEnd);

  /// Whether [utc] falls inside the period: `start <= utc < endExclusive`.
  bool contains(DateTime utc) =>
      !utc.isBefore(startUtc) && utc.isBefore(endExclusiveUtc);

  /// Whether [utc] is at or before the cutoff — what an as-of report asks.
  bool isAtOrBeforeCutoff(DateTime utc) => utc.isBefore(endExclusiveUtc);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReportPeriod &&
          DateOnly.isSameDate(other.periodStart, periodStart) &&
          DateOnly.isSameDate(other.periodEnd, periodEnd));

  @override
  int get hashCode => Object.hash(
    DateOnly.formatIso(periodStart),
    DateOnly.formatIso(periodEnd),
  );

  @override
  String toString() =>
      'ReportPeriod(${DateOnly.formatIso(periodStart)}'
      '..${DateOnly.formatIso(periodEnd)})';
}

/// Where a report reaches, after the scope has been *resolved* against the
/// database.
///
/// [locationIds] is the resolved set — one id for a single-location scope, a
/// branch's store plus its rooms for `branch_all`, every location for
/// `all_locations`, and empty for `cross_branch`, which is not a place at all.
/// Resolving it in one step and carrying it is what stops each builder working the
/// set out for itself and one of them getting it wrong.
class ReportScope {
  const ReportScope({
    required this.type,
    required this.locationIds,
    this.locationId,
    this.branchId,
  });

  final ReportScopeType type;

  /// The single location, for the three single-location scopes. Always a member of
  /// [locationIds] when non-null.
  final String? locationId;

  final String? branchId;

  /// Every stock location the report may read balances at.
  ///
  /// Empty for [ReportScopeType.crossBranch]: a document recap is scoped by the
  /// documents it lists, not by a set of shelves.
  final Set<String> locationIds;

  bool get isCrossBranch => type == ReportScopeType.crossBranch;

  bool get isAllLocations => type == ReportScopeType.allLocations;
}

/// The optional narrowing a user applied on top of the scope.
///
/// All of it is optional by design: G-L6 makes the *absence* of a category filter
/// meaningful — it is what turns the report into a grouped one with subtotals.
class ReportFilter {
  const ReportFilter({
    this.categoryId,
    this.itemId,
    this.searchText,
    this.statuses = const <String>{},
    this.discrepancy = GoodReceiptDiscrepancyFilter.all,
  });

  final String? categoryId;
  final String? itemId;

  /// Free text over document number, item name, SKU, batch, actor or branch —
  /// applied in Dart over the built rows, case-insensitively.
  final String? searchText;

  /// Document statuses to keep, as their `dbValue` strings. Empty means "every
  /// status", which is not the same as "no status": an empty set is the default,
  /// and a caller that meant to exclude everything has nothing to express.
  final Set<String> statuses;

  /// Only meaningful on `rekap_gr` (§27).
  final GoodReceiptDiscrepancyFilter discrepancy;

  bool get hasCategory => categoryId != null;

  ReportFilter copyWith({
    String? categoryId,
    bool clearCategory = false,
    String? itemId,
    bool clearItem = false,
    String? searchText,
    bool clearSearch = false,
    Set<String>? statuses,
    GoodReceiptDiscrepancyFilter? discrepancy,
  }) => ReportFilter(
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    itemId: clearItem ? null : (itemId ?? this.itemId),
    searchText: clearSearch ? null : (searchText ?? this.searchText),
    statuses: statuses ?? this.statuses,
    discrepancy: discrepancy ?? this.discrepancy,
  );
}

/// The discrepancy lens on a Good Receipt recap (§27).
enum GoodReceiptDiscrepancyFilter {
  all('Semua'),
  none('Tidak ada selisih'),
  shortage('Kurang kirim'),
  rejected('Ditolak / retur');

  const GoodReceiptDiscrepancyFilter(this.label);

  final String label;
}

/// Everything needed to produce one report, before any data is read.
///
/// Deliberately carries no actor: the actor is re-read from the database by the use
/// case (§16), so a request object that carried one would be a claim rather than a
/// fact — and the one thing a security boundary must never take on trust is the
/// identity of the person crossing it.
class ReportRequest {
  const ReportRequest({
    required this.reportType,
    required this.scope,
    required this.period,
    this.filter = const ReportFilter(),
  });

  final ReportType reportType;
  final ReportScope scope;
  final ReportPeriod period;
  final ReportFilter filter;
}

/// What a screen asked for, before anything has been resolved or validated.
///
/// The **untrusted** input object: raw ids and raw dates, exactly as they came off
/// a form. It is deliberately separate from [ReportRequest], which only exists once
/// the scope has been resolved against the database and the access policy has said
/// yes — so a type signature alone tells you whether the values in front of you have
/// been checked (§16).
class ReportRequestDraft {
  const ReportRequestDraft({
    required this.reportType,
    required this.scopeType,
    required this.periodStart,
    required this.periodEnd,
    this.locationId,
    this.branchId,
    this.filter = const ReportFilter(),
  });

  final ReportType reportType;
  final ReportScopeType scopeType;

  /// Civil dates as the picker produced them. Normalised by [ReportPeriodPolicy],
  /// which also collapses an as-of report's start onto its end (§3.9).
  final DateTime periodStart;
  final DateTime periodEnd;

  final String? locationId;
  final String? branchId;
  final ReportFilter filter;

  ReportRequestDraft copyWith({
    ReportType? reportType,
    ReportScopeType? scopeType,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? locationId,
    bool clearLocation = false,
    String? branchId,
    bool clearBranch = false,
    ReportFilter? filter,
  }) => ReportRequestDraft(
    reportType: reportType ?? this.reportType,
    scopeType: scopeType ?? this.scopeType,
    periodStart: periodStart ?? this.periodStart,
    periodEnd: periodEnd ?? this.periodEnd,
    locationId: clearLocation ? null : (locationId ?? this.locationId),
    branchId: clearBranch ? null : (branchId ?? this.branchId),
    filter: filter ?? this.filter,
  );
}

/// Why a report was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can name the rule that fired.
enum ReportAccessDenialReason {
  /// No session yet — still loading, or master data has not been seeded.
  noSession,

  /// The role does not reach the reporting module, this report type, or this
  /// scope.
  role,

  /// A branch-scoped role with no branch.
  noBranch,

  /// The scope is not one this report type can be run at.
  scope,

  /// The location is outside the actor's reach, or of the wrong type — the same
  /// answer for both, so the address bar cannot be used to enumerate locations.
  location,
}

/// The outcome of a reporting access check.
class ReportAccessDecision {
  const ReportAccessDecision._(this.reason);

  const ReportAccessDecision.granted() : reason = null;

  const ReportAccessDecision.denied(ReportAccessDenialReason reason)
    : this._(reason);

  final ReportAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;
}

/// How fresh the data behind a report is (G-L3).
///
/// Counted from the **rows the report actually used**, never from a network flag: a
/// device that is online right now may still hold twenty pending movements, and the
/// question G-L3 asks is *"data per kapan"*, not *"is there signal"*.
class ReportSyncSnapshot {
  const ReportSyncSnapshot({
    required this.syncedCount,
    required this.pendingCount,
    required this.conflictCount,
    required this.latestUpdatedAtUtc,
  });

  const ReportSyncSnapshot.empty()
    : syncedCount = 0,
      pendingCount = 0,
      conflictCount = 0,
      latestUpdatedAtUtc = null;

  final int syncedCount;
  final int pendingCount;
  final int conflictCount;

  /// The newest `updated_at` among the source rows, or `null` when there were
  /// none.
  final DateTime? latestUpdatedAtUtc;

  int get totalCount => syncedCount + pendingCount + conflictCount;

  bool get isEmpty => totalCount == 0;

  bool get hasPending => pendingCount > 0;

  bool get hasConflict => conflictCount > 0;

  /// `18 tersinkron · 2 pending · 0 konflik`, or the empty-filter sentence.
  ///
  /// Stored verbatim in `export_logs.sync_summary`, so the audit row and the file
  /// header say the same thing.
  String get label => isEmpty
      ? emptyLabel
      : 'Status sync: $syncedCount tersinkron · $pendingCount pending · '
            '$conflictCount konflik';

  static const String emptyLabel = 'Tidak ada data pada filter ini';
}

/// The block every preview and every exported file starts with (§20).
class ReportHeader {
  const ReportHeader({
    required this.reportType,
    required this.title,
    required this.generatedAtUtc,
    required this.period,
    required this.scopeLabel,
    required this.locationLabel,
    required this.branchLabel,
    required this.categoryLabel,
    required this.itemLabel,
    required this.exportedByLabel,
    required this.syncSnapshot,
    required this.rowCount,
  });

  static const String appTitle = 'AISH WAREHOUSE';

  final ReportType reportType;
  final String title;

  /// The cutoff — the UTC instant the snapshot was taken, from an injected clock.
  /// Printed as the *waktu cetak* and stored as `export_logs.data_cutoff_at`.
  final DateTime generatedAtUtc;

  final ReportPeriod period;
  final String scopeLabel;

  /// `Semua lokasi cabang CAB-01`, `Warehouse Pusat`, `Lintas cabang`…
  final String locationLabel;

  /// `Semua cabang` when the report spans them.
  final String branchLabel;

  /// `Semua kategori` when no category filter was applied — which is also the
  /// signal that the body is grouped with subtotals (G-L6).
  final String categoryLabel;

  /// `—` on every report but Kartu Stok.
  final String itemLabel;

  final String exportedByLabel;
  final ReportSyncSnapshot syncSnapshot;
  final int rowCount;
}

/// Where a column's text sits, so Excel and PDF agree without either deciding.
enum ReportColumnAlign { start, center, end }

/// One column of the data table.
class ReportColumn {
  const ReportColumn({
    required this.key,
    required this.label,
    this.align = ReportColumnAlign.start,
    this.widthFlex = 1,
    this.isNumeric = false,
  });

  final String key;
  final String label;
  final ReportColumnAlign align;

  /// Relative width hint. The PDF turns it into a flex, the spreadsheet into a
  /// character width; neither invents its own.
  final int widthFlex;

  /// Whether the column holds a quantity. Numeric columns are still written as
  /// **text** in the spreadsheet (§38) — this flag drives alignment and the
  /// subtotal row, not a numeric cell type.
  final bool isNumeric;
}

/// One rendered cell. A string, deliberately.
///
/// Quantities arrive here already formatted by [Quantity.format], so no exporter
/// ever holds a number it could round. §38 spells out why the spreadsheet keeps
/// them as text: an exact fixed-point value written into a float cell is a value
/// that can come back as `2.2500000000000004`.
class ReportCell {
  const ReportCell(
    this.text, {
    this.align = ReportColumnAlign.start,
    this.emphasis = ReportCellEmphasis.none,
  });

  const ReportCell.empty()
    : text = '',
      align = ReportColumnAlign.start,
      emphasis = ReportCellEmphasis.none;

  final String text;
  final ReportColumnAlign align;
  final ReportCellEmphasis emphasis;

  bool get isEmpty => text.isEmpty;
}

/// Why a cell is highlighted. Not a colour: the PDF and the widget each map this
/// to their own palette, and a hex string in the domain would be a presentation
/// decision made in the wrong layer.
enum ReportCellEmphasis { none, positive, warning, danger, muted }

/// One data row of a report.
///
/// [categoryId] / [categoryName] drive G-L6's grouping, and [unit] / [quantity]
/// drive its subtotals. A row whose [quantity] is `null` contributes to no unit
/// total — which is how a document row that has no stock effect (a `preparing`
/// Delivery Order, a `draft` Distribusi) appears in the list without inventing a
/// number for the total.
class ReportDataRow {
  const ReportDataRow({
    required this.cells,
    required this.categoryId,
    required this.categoryName,
    required this.sortKey,
    this.unit,
    this.quantity,
    this.isHistorical = false,
  });

  final List<ReportCell> cells;

  /// `null` for a row whose item's category could not be resolved — grouped under
  /// [ReportGroup.unresolvedCategoryName] rather than dropped.
  final String? categoryId;
  final String categoryName;

  /// Deterministic within a group: category name, then SKU/item, then whatever the
  /// report sorts by. Ties broken by an id so two runs cannot disagree.
  final String sortKey;

  final String? unit;

  /// Exact fixed-point. Signed on a Kartu Stok, where the row's contribution to the
  /// period's net movement is what a subtotal there means.
  final Quantity? quantity;

  /// Whether the row names at least one master reference that no longer resolves,
  /// so the surfaces can mark it without re-deriving the condition.
  final bool isHistorical;
}

/// Totals held **per unit**, never summed across them (§32).
///
/// `pcs` and `box` are different physical things, and a single number combining
/// them is not a smaller truth — it is a false one. There is deliberately no
/// `total` getter on this class, and adding one is the change that would break
/// G-L6.
class ReportUnitTotals {
  const ReportUnitTotals(this._byUnit);

  const ReportUnitTotals.empty() : _byUnit = const <String, Quantity>{};

  final Map<String, Quantity> _byUnit;

  /// Units present, sorted so two runs render identically.
  List<String> get units => _byUnit.keys.toList()..sort();

  Quantity? operator [](String unit) => _byUnit[unit];

  bool get isEmpty => _byUnit.isEmpty;

  bool get isNotEmpty => _byUnit.isNotEmpty;

  Map<String, Quantity> get asMap => Map.unmodifiable(_byUnit);

  /// `10 pcs · 2.5 box`, in [units] order. `—` when there is nothing to total.
  String get label => isEmpty
      ? '—'
      : units.map((unit) => _byUnit[unit]!.formatWithUnit(unit)).join(' · ');

  /// This plus [other], unit by unit. Units present in only one side survive.
  ReportUnitTotals operator +(ReportUnitTotals other) {
    final merged = Map<String, Quantity>.from(_byUnit);
    other._byUnit.forEach((unit, quantity) {
      merged[unit] = (merged[unit] ?? Quantity.zero()) + quantity;
    });
    return ReportUnitTotals(merged);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReportUnitTotals) return false;
    if (other._byUnit.length != _byUnit.length) return false;
    for (final entry in _byUnit.entries) {
      if (other._byUnit[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    _byUnit.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

/// One category block: its rows and its per-unit subtotal (G-L6).
class ReportGroup {
  const ReportGroup({
    required this.categoryId,
    required this.categoryName,
    required this.rows,
    required this.subtotals,
  });

  /// Shown for rows whose category is gone. Not an error: the movement happened,
  /// and hiding it would make the totals disagree with the ledger.
  static const String unresolvedCategoryName = 'Kategori historis';

  final String? categoryId;
  final String categoryName;
  final List<ReportDataRow> rows;
  final ReportUnitTotals subtotals;

  int get rowCount => rows.length;
}

/// A named block of the report, above the data table.
///
/// Used for the summary metrics a specific report needs and the generic model
/// cannot: a Kartu Stok's opening and closing balance, a GR recap's shortage
/// count. Values are pre-rendered strings for the same reason [ReportCell] is.
class ReportSection {
  const ReportSection({required this.title, required this.metrics});

  final String title;

  /// Ordered label → value pairs. A `List` rather than a `Map` because the order
  /// is meaningful and two exporters must not sort it differently.
  final List<({String label, String value})> metrics;
}

/// The one model every report builder produces and every surface renders (§33).
class ReportDocument {
  const ReportDocument({
    required this.header,
    required this.columns,
    required this.groups,
    required this.overallTotals,
    this.sections = const <ReportSection>[],
    this.warnings = const <String>[],
  });

  final ReportHeader header;
  final List<ReportColumn> columns;

  /// Always grouped, even when a category filter left exactly one group. The
  /// surfaces decide whether to draw a heading for a single group (§32); the model
  /// does not have two shapes for one idea.
  final List<ReportGroup> groups;

  final ReportUnitTotals overallTotals;
  final List<ReportSection> sections;

  /// Integrity and historical notes, already worded in Indonesian. Printed in
  /// every surface — a warning that only the screen showed would be a warning the
  /// auditor reading the PDF never saw.
  final List<String> warnings;

  List<ReportDataRow> get rows => [for (final group in groups) ...group.rows];

  int get rowCount => groups.fold(0, (total, group) => total + group.rowCount);

  bool get isEmpty => rowCount == 0;

  /// Shown in place of the table when there is nothing to show.
  static const String emptyMessage = 'Tidak ada data pada filter ini';
}

/// A report prepared for the screen, with the row cap the preview applies (§46).
///
/// The cap is a *rendering* decision and lives here rather than in the builder, so
/// [ReportPreview.document] still holds every row and an export built from the same
/// request can never be truncated by what the screen chose to draw.
class ReportPreview {
  const ReportPreview({
    required this.document,
    required this.displayedRowCount,
  });

  final ReportDocument document;

  /// How many rows the widget will build. Equal to [ReportDocument.rowCount] when
  /// the report fits under the cap.
  final int displayedRowCount;

  int get totalRowCount => document.rowCount;

  bool get isTruncated => displayedRowCount < totalRowCount;

  /// `Preview menampilkan 200 dari 5.000 baris. File ekspor memuat semuanya.`
  String get truncationNotice =>
      'Preview menampilkan ${_thousands(displayedRowCount)} dari '
      '${_thousands(totalRowCount)} baris. File ekspor memuat semuanya.';

  static String _thousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

/// How the share sheet ended (§36).
///
/// `cancelled` and `unavailable` are **not** failures of the export: the file
/// exists and the audit row exists by the time the sheet opens, so a user who
/// dismissed it still has a report.
enum ReportShareOutcome { shared, cancelled, unavailable }

/// What one successful export produced.
class GeneratedReportArtifact {
  const GeneratedReportArtifact({
    required this.exportLogId,
    required this.fileName,
    required this.format,
    required this.byteLength,
    required this.rowCount,
    required this.shareOutcome,
  });

  final String exportLogId;

  /// The canonical G-L5 name the user saw. Never a path — see [ExportLog].
  final String fileName;

  final ReportFormat format;
  final int byteLength;
  final int rowCount;
  final ReportShareOutcome shareOutcome;

  String get successMessage =>
      'Laporan ${format.label} berhasil dibuat.\n'
      'File siap disimpan atau dibagikan.';
}

/// One row of the export audit, in domain terms (§42).
///
/// Read-only by construction: there is no `copyWith`, no writer on the repository
/// beyond an insert, and no path — the file it names may well be gone, because the
/// artifacts live in a cache directory the OS may clear. The audit records *that an
/// export happened*, not where the bytes are.
class ExportLog {
  const ExportLog({
    required this.id,
    required this.exportedAtUtc,
    required this.reportType,
    required this.format,
    required this.scopeType,
    required this.locationId,
    required this.categoryId,
    required this.branchId,
    required this.itemId,
    required this.periodStart,
    required this.periodEnd,
    required this.exportedBy,
    required this.fileName,
    required this.dataCutoffAtUtc,
    required this.syncSummary,
    required this.rowCount,
    required this.syncStatus,
  });

  final String id;

  /// `created_at` — the instant the file was recorded.
  final DateTime exportedAtUtc;

  final ReportType reportType;
  final ReportFormat format;
  final ReportScopeType scopeType;
  final String? locationId;
  final String? categoryId;
  final String? branchId;
  final String? itemId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String exportedBy;
  final String fileName;
  final DateTime dataCutoffAtUtc;
  final String syncSummary;
  final int rowCount;
  final SyncStatus syncStatus;

  bool get isAsOf => DateOnly.isSameDate(periodStart, periodEnd);
}

/// One export log with the labels the audit screen shows, resolved historically.
class ExportLogDetail {
  const ExportLogDetail({
    required this.log,
    required this.exportedByLabel,
    required this.branchLabel,
    required this.locationLabel,
    required this.categoryLabel,
    required this.itemLabel,
  });

  final ExportLog log;
  final String exportedByLabel;
  final String branchLabel;
  final String locationLabel;
  final String categoryLabel;
  final String itemLabel;
}

/// What the Super Admin's audit screen is filtered by (§48).
class ExportHistoryFilter {
  const ExportHistoryFilter({
    this.reportType,
    this.format,
    this.branchId,
    this.exportedBy,
    this.onOperationalDate,
    this.searchText,
  });

  final ReportType? reportType;
  final ReportFormat? format;
  final String? branchId;
  final String? exportedBy;

  /// One operational (GMT+8) calendar day, or `null` for every day.
  final DateTime? onOperationalDate;

  /// Free text over file name, report label and exporter name.
  final String? searchText;

  bool get isEmpty =>
      reportType == null &&
      format == null &&
      branchId == null &&
      exportedBy == null &&
      onOperationalDate == null &&
      (searchText == null || searchText!.trim().isEmpty);

  ExportHistoryFilter copyWith({
    ReportType? reportType,
    bool clearReportType = false,
    ReportFormat? format,
    bool clearFormat = false,
    String? branchId,
    bool clearBranch = false,
    String? exportedBy,
    bool clearExportedBy = false,
    DateTime? onOperationalDate,
    bool clearDate = false,
    String? searchText,
    bool clearSearch = false,
  }) => ExportHistoryFilter(
    reportType: clearReportType ? null : (reportType ?? this.reportType),
    format: clearFormat ? null : (format ?? this.format),
    branchId: clearBranch ? null : (branchId ?? this.branchId),
    exportedBy: clearExportedBy ? null : (exportedBy ?? this.exportedBy),
    onOperationalDate: clearDate
        ? null
        : (onOperationalDate ?? this.onOperationalDate),
    searchText: clearSearch ? null : (searchText ?? this.searchText),
  );
}

/// The fallback labels §20 and §51 require, in one place.
///
/// They exist so a report never prints a raw UUID at a person: an auditor reading
/// *"Lokasi historis"* learns something, and an auditor reading
/// `a3f1…-9b2c` learns nothing they can act on.
abstract final class ReportLabels {
  static const String missingMaster = 'Data historis tidak tersedia';
  static const String missingDocument = 'Referensi dokumen tidak tersedia';
  static const String historicalLocation = 'Lokasi historis';
  static const String historicalUser = 'Pengguna historis';
  static const String historicalBranch = 'Cabang historis';
  static const String historicalRoom = 'Ruangan historis';
  static const String historicalItem = 'Barang historis';
  static const String historicalBatch = 'Batch historis';
  static const String allCategories = 'Semua kategori';
  static const String allBranches = 'Semua cabang';
  static const String allLocations = 'Semua lokasi';
  static const String notApplicable = '—';
}
