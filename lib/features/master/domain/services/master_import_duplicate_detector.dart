import '../models/import_models.dart';
import '../models/master_admin_models.dart';

/// Finds natural keys that appear more than once in one workbook (§17).
///
/// ### Every row involved fails, not just the second one
///
/// A file with `DEN-0001` on rows 4 and 90 has two wrong rows, and both are
/// reported. The alternative — last-row-wins — is the behaviour most spreadsheet
/// tools have and the one this module refuses: which of the two the operator meant
/// is a question only they can answer, and silently applying the later one makes
/// the import's result depend on row order rather than on content. Merging them is
/// worse still: it invents a row that appears in no file.
///
/// ### O(n), and why that is written down
///
/// One pass to bucket rows by key, one pass to emit issues for the buckets with
/// more than one row. No nested scan, so a 10,000-row workbook costs 10,000
/// comparisons rather than 50 million (§58). The `Map` is doing the work a nested
/// loop would otherwise do badly.
abstract final class MasterImportDuplicateDetector {
  /// Row numbers per natural key, insertion-ordered.
  static Map<String, List<int>> groupRowNumbers(
    Iterable<ImportNormalizedRow> rows,
  ) {
    final grouped = <String, List<int>>{};
    for (final row in rows) {
      (grouped[row.naturalKey] ??= <int>[]).add(row.rowNumber);
    }
    return grouped;
  }

  /// The natural keys carried by more than one row.
  static Set<String> duplicateKeys(Iterable<ImportNormalizedRow> rows) {
    final grouped = groupRowNumbers(rows);
    return {
      for (final entry in grouped.entries)
        if (entry.value.length > 1) entry.key,
    };
  }

  /// One issue per *involved row*, naming every row that shares the key.
  ///
  /// The message names the others so an operator can jump straight to them
  /// instead of searching the file for a key they have to work out first.
  static List<ImportRowIssue> detect({
    required MasterEntityType entity,
    required Iterable<ImportNormalizedRow> rows,
  }) {
    final grouped = groupRowNumbers(rows);
    final displayByKey = <String, String>{};
    for (final row in rows) {
      displayByKey.putIfAbsent(row.naturalKey, () => row.naturalKeyDisplay);
    }

    final issues = <ImportRowIssue>[];
    for (final entry in grouped.entries) {
      if (entry.value.length < 2) continue;
      final rowNumbers = entry.value;
      final display = displayByKey[entry.key] ?? entry.key;
      for (final rowNumber in rowNumbers) {
        final others = rowNumbers.where((n) => n != rowNumber).join(', ');
        issues.add(
          ImportRowIssue(
            rowNumber: rowNumber,
            // The key's *first* column, so the issue lands on a real header the
            // preview can highlight. A composite key highlights `branch_code`
            // and `item_sku` respectively, which is where an operator looks
            // first anyway.
            column: entity.naturalKeyColumns.first,
            code: ImportIssueCode.duplicateNaturalKey,
            message:
                '${entity.naturalKeyLabel} "$display" muncul lebih dari sekali '
                'dalam file ini (baris $others). Gabungkan menjadi satu baris '
                'atau hapus baris yang tidak diperlukan.',
          ),
        );
      }
    }
    issues.sort();
    return issues;
  }
}
