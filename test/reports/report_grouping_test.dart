import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_grouping_engine.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_period_policy.dart';
import 'package:aish_warehouse/features/reports/domain/services/spreadsheet_cell_sanitizer.dart';
import 'package:aish_warehouse/features/reports/domain/use_cases/build_report_preview_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

/// G-L6 — *"tanpa filter, hasil dikelompokkan per kategori dengan subtotal per
/// kategori + total keseluruhan"* — and §32's rule that units are never added
/// together.
void main() {
  ReportDataRow row({
    required String category,
    String? categoryId,
    required String unit,
    required String qty,
    String sortKey = 'a',
  }) => ReportDataRow(
    cells: const [ReportCell('x')],
    categoryId: categoryId ?? 'cat-$category',
    categoryName: category,
    sortKey: sortKey,
    unit: unit,
    quantity: Quantity.parse(qty),
  );

  group('pengelompokan kategori', () {
    test('baris dikelompokkan per kategori', () {
      final groups = ReportGroupingEngine.group([
        row(category: 'Obat', unit: 'ampul', qty: '5'),
        row(category: 'Alat', unit: 'box', qty: '2'),
        row(category: 'Obat', unit: 'ampul', qty: '3'),
      ]);

      expect(groups.map((group) => group.categoryName), ['Alat', 'Obat']);
      expect(groups.first.rowCount, 1);
      expect(groups.last.rowCount, 2);
    });

    test('kategori diurutkan case-insensitive', () {
      final groups = ReportGroupingEngine.group([
        row(category: 'zinc', unit: 'pcs', qty: '1'),
        row(category: 'Alat', unit: 'pcs', qty: '1'),
        row(category: 'obat', unit: 'pcs', qty: '1'),
      ]);

      expect(groups.map((group) => group.categoryName), [
        'Alat',
        'obat',
        'zinc',
      ]);
    });

    test('kategori historis selalu terakhir', () {
      // A fallback bucket, not a category — sorting it among real ones would put it
      // in a different place depending on the alphabet.
      final groups = ReportGroupingEngine.group([
        ReportDataRow(
          cells: const [ReportCell('x')],
          categoryId: null,
          categoryName: ReportGroup.unresolvedCategoryName,
          sortKey: 'a',
          unit: 'pcs',
          quantity: Quantity.fromWhole(1),
        ),
        row(category: 'Zinc', unit: 'pcs', qty: '1'),
        row(category: 'Alat', unit: 'pcs', qty: '1'),
      ]);

      expect(groups.last.categoryId, isNull);
      expect(groups.last.categoryName, ReportGroup.unresolvedCategoryName);
    });

    test('baris di dalam grup diurutkan menurut sortKey', () {
      final groups = ReportGroupingEngine.group([
        row(category: 'Obat', unit: 'ampul', qty: '1', sortKey: 'c'),
        row(category: 'Obat', unit: 'ampul', qty: '1', sortKey: 'a'),
        row(category: 'Obat', unit: 'ampul', qty: '1', sortKey: 'b'),
      ]);

      expect(groups.single.rows.map((r) => r.sortKey), ['a', 'b', 'c']);
    });

    test('satu kategori tetap menghasilkan satu grup', () {
      // §32: the model has exactly one shape whether or not a category filter was
      // applied. Two shapes would mean two rendering paths in each of three
      // surfaces.
      final groups = ReportGroupingEngine.group([
        row(category: 'Obat', unit: 'ampul', qty: '1'),
      ]);

      expect(groups, hasLength(1));
    });

    test('tanpa baris menghasilkan tanpa grup', () {
      expect(ReportGroupingEngine.group(const []), isEmpty);
    });
  });

  group('subtotal per satuan', () {
    test('satuan berbeda tidak pernah dijumlahkan', () {
      // The rule §32 exists for: `pcs + box` is not a smaller truth, it is a false
      // one.
      final groups = ReportGroupingEngine.group([
        row(category: 'Campur', unit: 'pcs', qty: '10'),
        row(category: 'Campur', unit: 'box', qty: '2'),
        row(category: 'Campur', unit: 'botol', qty: '3'),
      ]);

      final subtotals = groups.single.subtotals;
      expect(subtotals.units, ['botol', 'box', 'pcs']);
      expect(subtotals['pcs'], Quantity.fromWhole(10));
      expect(subtotals['box'], Quantity.fromWhole(2));
      expect(subtotals['botol'], Quantity.fromWhole(3));
    });

    test('satuan sama dijumlahkan persis dalam fixed-point', () {
      final groups = ReportGroupingEngine.group([
        row(category: 'Obat', unit: 'ampul', qty: '0.1'),
        row(category: 'Obat', unit: 'ampul', qty: '0.2'),
      ]);

      expect(groups.single.subtotals['ampul']!.format(), '0.3');
    });

    test('baris tanpa kuantitas tidak menyumbang total', () {
      // A `preparing` Delivery Order line has an allocation and no stock effect.
      final groups = ReportGroupingEngine.group([
        row(category: 'Obat', unit: 'ampul', qty: '5'),
        const ReportDataRow(
          cells: [ReportCell('x')],
          categoryId: 'cat-Obat',
          categoryName: 'Obat',
          sortKey: 'b',
          unit: 'ampul',
        ),
      ]);

      expect(groups.single.subtotals['ampul'], Quantity.fromWhole(5));
    });

    test('baris tanpa satuan tidak menyumbang total', () {
      final groups = ReportGroupingEngine.group([
        ReportDataRow(
          cells: const [ReportCell('x')],
          categoryId: 'cat-Obat',
          categoryName: 'Obat',
          sortKey: 'a',
          quantity: Quantity.fromWhole(5),
        ),
      ]);

      expect(groups.single.subtotals.isEmpty, isTrue);
    });
  });

  group('total keseluruhan', () {
    test('menjumlahkan subtotal, bukan menghitung ulang dari baris', () {
      // Derived from the printed subtotals so the two provably add up: two
      // independent folds could disagree by a rule somebody changed in one of them.
      final groups = ReportGroupingEngine.group([
        row(category: 'Obat', unit: 'ampul', qty: '5'),
        row(category: 'Alat', unit: 'box', qty: '2'),
        row(category: 'Alat', unit: 'ampul', qty: '1'),
      ]);

      final overall = ReportTotalsEngine.combine(
        groups.map((group) => group.subtotals),
      );

      expect(overall['ampul'], Quantity.fromWhole(6));
      expect(overall['box'], Quantity.fromWhole(2));
    });

    test('label menyebut setiap satuan terpisah', () {
      final totals = ReportTotalsEngine.totalsOf([
        row(category: 'A', unit: 'pcs', qty: '10'),
        row(category: 'A', unit: 'box', qty: '2.5'),
      ]);

      expect(totals.label, '2.5 box · 10 pcs');
    });

    test('total kosong ditandai dengan strip', () {
      expect(const ReportUnitTotals.empty().label, '—');
    });

    test('penjumlahan mempertahankan satuan yang hanya ada di satu sisi', () {
      final a = ReportTotalsEngine.totalsOf([
        row(category: 'A', unit: 'pcs', qty: '1'),
      ]);
      final b = ReportTotalsEngine.totalsOf([
        row(category: 'B', unit: 'box', qty: '2'),
      ]);

      final sum = a + b;
      expect(sum.units, ['box', 'pcs']);
    });
  });

  group('label', () {
    test('subtotal menyebut nama kategori', () {
      final group = ReportGroupingEngine.group([
        row(category: 'Bahan Tambal', unit: 'pcs', qty: '1'),
      ]).single;

      expect(
        ReportGroupingEngine.subtotalLabel(group),
        'Subtotal Bahan Tambal',
      );
    });

    test('total keseluruhan memakai satu label baku', () {
      expect(ReportGroupingEngine.overallTotalLabel, 'Total Keseluruhan');
    });
  });

  group('batas preview (§46)', () {
    ReportDocument documentOf(int rowCount) {
      final rows = [
        for (var index = 0; index < rowCount; index++)
          row(
            category: 'Obat',
            unit: 'ampul',
            qty: '1',
            sortKey: index.toString().padLeft(5, '0'),
          ),
      ];
      final groups = ReportGroupingEngine.group(rows);
      return ReportDocument(
        header: ReportHeader(
          reportType: ReportType.stokLokasi,
          title: ReportType.stokLokasi.label,
          generatedAtUtc: DateTime.utc(2026, 7, 30),
          period: ReportPeriodPolicy.asOf(DateOnly.of(2026, 7, 30)),
          scopeLabel: ReportScopeType.warehouse.label,
          locationLabel: 'Warehouse Pusat',
          branchLabel: ReportLabels.allBranches,
          categoryLabel: ReportLabels.allCategories,
          itemLabel: ReportLabels.notApplicable,
          exportedByLabel: 'Petugas',
          syncSnapshot: const ReportSyncSnapshot.empty(),
          rowCount: rowCount,
        ),
        columns: const [ReportColumn(key: 'a', label: 'Barang')],
        groups: groups,
        overallTotals: ReportTotalsEngine.combine(
          groups.map((group) => group.subtotals),
        ),
      );
    }

    test('laporan kecil tidak dipotong', () {
      final preview = ReportPreview(
        document: documentOf(10),
        displayedRowCount: 10,
      );

      expect(preview.isTruncated, isFalse);
      expect(preview.totalRowCount, 10);
    });

    test('laporan besar dipotong dan mengatakannya', () {
      // §46: the cap is a property of the widget, not of the report — the document
      // still holds every row, and the export path is never truncated.
      final preview = ReportPreview(
        document: documentOf(5000),
        displayedRowCount: BuildReportPreviewUseCase.maxPreviewRows,
      );

      expect(preview.isTruncated, isTrue);
      expect(preview.totalRowCount, 5000);
      expect(preview.document.rowCount, 5000);
      expect(
        preview.truncationNotice,
        'Preview menampilkan 200 dari 5.000 baris. File ekspor memuat semuanya.',
      );
    });
  });

  group('sanitasi sel spreadsheet (§38)', () {
    test('teks berawalan = + - @ menjadi literal', () {
      for (final dangerous in const [
        '=HYPERLINK("http://x","klik")',
        '+cmd|"/c calc"!A1',
        '@SUM(1+1)',
        '-1+1',
      ]) {
        expect(
          SpreadsheetCellSanitizer.wouldBeFormula(dangerous),
          isTrue,
          reason: dangerous,
        );
        expect(
          SpreadsheetCellSanitizer.sanitize(dangerous),
          startsWith(SpreadsheetCellSanitizer.literalMarker),
          reason: dangerous,
        );
      }
    });

    test('nilai asli dipertahankan setelah penanda', () {
      // Stripping the character would change the data: `-1+1` is a legitimate note
      // and a report that printed `1+1` would have lied.
      expect(SpreadsheetCellSanitizer.sanitize('-1+1'), "'-1+1");
    });

    test('teks biasa tidak diubah', () {
      for (final safe in const ['Masker Bedah', 'OBT-0001', '10 ampul', '']) {
        expect(SpreadsheetCellSanitizer.sanitize(safe), safe, reason: safe);
      }
    });

    test('spasi di depan tidak menyembunyikan formula', () {
      // Checked on the cleaned string, so a value that becomes dangerous after
      // trimming cannot slip past.
      expect(SpreadsheetCellSanitizer.sanitize(' =SUM(A1)'), "'=SUM(A1)");
    });

    test('karakter kontrol dibuang, baris baru dipertahankan', () {
      final sanitized = SpreadsheetCellSanitizer.sanitize('a\rb\nc');
      expect(sanitized.contains('\r'), isFalse);
      expect(sanitized.contains('\n'), isTrue);
    });
  });
}
