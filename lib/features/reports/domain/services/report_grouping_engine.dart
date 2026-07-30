import '../../../../core/quantity/quantity.dart';
import '../models/reporting_models.dart';

/// Per-unit totals, and the one arithmetic rule this module will not bend (§32).
///
/// **pcs and box are not addable.** A "grand total" that summed them would be a
/// number with no physical meaning printed under a column an auditor is supposed to
/// check, so [ReportUnitTotals] holds one exact [Quantity] per unit and there is no
/// method anywhere that collapses them. A row that carries no unit — a document row
/// with no stock effect — contributes to nothing rather than to a nameless bucket.
abstract final class ReportTotalsEngine {
  /// Sums [rows] into one total per unit.
  ///
  /// Rows with a `null` [ReportDataRow.quantity] or a blank unit are skipped: a
  /// `preparing` Delivery Order line has an allocation but no stock effect, and
  /// counting it would overstate what was shipped (§26).
  static ReportUnitTotals totalsOf(Iterable<ReportDataRow> rows) {
    final byUnit = <String, Quantity>{};
    for (final row in rows) {
      final quantity = row.quantity;
      final unit = row.unit?.trim();
      if (quantity == null || unit == null || unit.isEmpty) continue;
      byUnit[unit] = (byUnit[unit] ?? Quantity.zero()) + quantity;
    }
    return ReportUnitTotals(byUnit);
  }

  /// Sums a list of already-computed subtotals.
  ///
  /// The overall total is derived from the group subtotals rather than recomputed
  /// from the rows, so the printed subtotals provably add up to the printed total —
  /// two independent folds could disagree by a rounding rule somebody changed in
  /// one of them.
  static ReportUnitTotals combine(Iterable<ReportUnitTotals> totals) =>
      totals.fold(const ReportUnitTotals.empty(), (sum, next) => sum + next);
}

/// G-L6's grouping: rows by category, each with its own subtotal.
///
/// > *"Semua laporan dapat difilter per kategori barang; tanpa filter, hasil ekspor
/// > Excel/PDF dikelompokkan per kategori dengan subtotal per kategori + total
/// > keseluruhan."*
///
/// The grouping happens **always**, filter or no filter, and the model has exactly
/// one shape for it (see [ReportDocument.groups]). With a category filter the result
/// is a single group; the surfaces decide whether to draw a heading for it. Two
/// shapes — "grouped" and "flat" — would mean two rendering paths in each of the
/// three surfaces, and six chances for a subtotal to be computed differently.
abstract final class ReportGroupingEngine {
  /// Groups [rows] by category and computes each group's per-unit subtotal.
  ///
  /// Ordering is fully deterministic and stated here once:
  ///
  /// * groups by category name, case-insensitively, with the *Kategori historis*
  ///   bucket last — it is a fallback, not a category, so sorting it among real
  ///   ones would put it in a different place depending on the alphabet;
  /// * rows inside a group by [ReportDataRow.sortKey], which each builder ends with
  ///   an id so two runs cannot disagree.
  static List<ReportGroup> group(Iterable<ReportDataRow> rows) {
    final buckets = <String?, List<ReportDataRow>>{};
    final names = <String?, String>{};
    for (final row in rows) {
      buckets.putIfAbsent(row.categoryId, () => <ReportDataRow>[]).add(row);
      names[row.categoryId] = row.categoryName;
    }

    final keys = buckets.keys.toList()
      ..sort((a, b) {
        // The unresolved bucket always sinks, whichever name it carries.
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        final byName = names[a]!.toLowerCase().compareTo(
          names[b]!.toLowerCase(),
        );
        return byName != 0 ? byName : a.compareTo(b);
      });

    return List.unmodifiable([
      for (final key in keys)
        () {
          final groupRows = buckets[key]!..sort(_bySortKey);
          return ReportGroup(
            categoryId: key,
            categoryName: key == null
                ? ReportGroup.unresolvedCategoryName
                : names[key]!,
            rows: List.unmodifiable(groupRows),
            subtotals: ReportTotalsEngine.totalsOf(groupRows),
          );
        }(),
    ]);
  }

  static int _bySortKey(ReportDataRow a, ReportDataRow b) =>
      a.sortKey.toLowerCase().compareTo(b.sortKey.toLowerCase());

  /// `Subtotal Bahan Tambal` — the label printed above a group's per-unit figures.
  static String subtotalLabel(ReportGroup group) =>
      'Subtotal ${group.categoryName}';

  /// The label printed above the report's per-unit figures.
  static const String overallTotalLabel = 'Total Keseluruhan';
}
