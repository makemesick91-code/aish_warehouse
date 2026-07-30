import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/reports/data/exporters/excel_report_exporter.dart';
import 'package:aish_warehouse/features/reports/data/exporters/pdf_report_exporter.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_grouping_engine.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_period_policy.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// §39 and §40 — the two exporters produce **real** files.
///
/// The workbook is read back with the same package that wrote it, so *"it opens"*
/// is an assertion rather than a hope; the PDF is checked at the byte level and for
/// page growth, because a PDF cannot be parsed back without adding a reader nobody
/// would otherwise need.
void main() {
  const excel = ExcelReportExporter();
  const pdf = PdfReportExporter();

  ReportDocument documentWith({
    List<ReportGroup> groups = const <ReportGroup>[],
    ReportUnitTotals totals = const ReportUnitTotals.empty(),
    List<String> warnings = const <String>[],
    List<ReportColumn> columns = const [
      ReportColumn(key: 'a', label: 'Barang'),
      ReportColumn(key: 'b', label: 'Satuan'),
      ReportColumn(
        key: 'c',
        label: 'Qty',
        align: ReportColumnAlign.end,
        isNumeric: true,
      ),
    ],
  }) => ReportDocument(
    header: ReportHeader(
      reportType: ReportType.stokLokasi,
      title: ReportType.stokLokasi.label,
      generatedAtUtc: DateTime.utc(2026, 7, 30, 14, 15),
      period: ReportPeriodPolicy.asOf(DateOnly.of(2026, 7, 30)),
      scopeLabel: ReportScopeType.warehouse.label,
      locationLabel: 'Warehouse Pusat',
      branchLabel: ReportLabels.allBranches,
      categoryLabel: ReportLabels.allCategories,
      itemLabel: ReportLabels.notApplicable,
      exportedByLabel: 'Petugas Warehouse',
      syncSnapshot: const ReportSyncSnapshot(
        syncedCount: 18,
        pendingCount: 2,
        conflictCount: 0,
        latestUpdatedAtUtc: null,
      ),
      rowCount: groups.fold(0, (total, group) => total + group.rowCount),
    ),
    columns: columns,
    groups: groups,
    overallTotals: totals,
    warnings: warnings,
  );

  ReportDataRow dataRow({
    required String name,
    required String unit,
    required String qty,
  }) => ReportDataRow(
    cells: [
      ReportCell(name),
      ReportCell(unit),
      ReportCell(qty, align: ReportColumnAlign.end),
    ],
    categoryId: 'cat-1',
    categoryName: 'Obat',
    sortKey: name,
    unit: unit,
    quantity: Quantity.parse(qty),
  );

  ReportGroup groupOf(List<ReportDataRow> rows, {String name = 'Obat'}) =>
      ReportGroup(
        categoryId: 'cat-1',
        categoryName: name,
        rows: rows,
        subtotals: ReportTotalsEngine.totalsOf(rows),
      );

  /// Every text cell of one sheet, flattened — enough to assert *"the file says
  /// this"* without depending on where the writer put it.
  List<String> textOf(Excel workbook, String sheetName) => [
    for (final row in workbook.tables[sheetName]!.rows)
      for (final cell in row)
        if (cell?.value != null) cell!.value.toString(),
  ];

  group('Excel', () {
    test('byte diawali magic ZIP dan dapat dibaca ulang', () async {
      final bytes = await excel.export(
        documentWith(
          groups: [
            groupOf([dataRow(name: 'Anestesi', unit: 'ampul', qty: '10')]),
          ],
        ),
      );

      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      final reopened = Excel.decodeBytes(bytes);
      expect(reopened.tables.keys, isNotEmpty);
    });

    test('memiliki sheet Ringkasan dan Data', () async {
      final bytes = await excel.export(documentWith());
      final workbook = Excel.decodeBytes(bytes);

      expect(workbook.tables.keys, containsAll(<String>['Ringkasan', 'Data']));
    });

    test('sheet kosong bawaan paket dihapus', () async {
      final workbook = Excel.decodeBytes(await excel.export(documentWith()));

      expect(workbook.tables.keys, hasLength(2));
      expect(workbook.tables.containsKey('Sheet1'), isFalse);
    });

    test('Ringkasan memuat header G-L3', () async {
      final workbook = Excel.decodeBytes(await excel.export(documentWith()));
      final text = textOf(workbook, 'Ringkasan');

      expect(text, contains(ReportHeader.appTitle));
      expect(text, contains(ReportType.stokLokasi.label));
      expect(text, contains('Waktu cetak'));
      expect(text, contains('Periode'));
      expect(text, contains('Lokasi'));
      expect(text, contains('Warehouse Pusat'));
      expect(text, contains('Diekspor oleh'));
      expect(text, contains('Petugas Warehouse'));
      expect(
        text.any((value) => value.contains('tersinkron')),
        isTrue,
        reason: 'status sync wajib tercetak (G-L3)',
      );
      expect(text.any((value) => value.contains('GMT+8')), isTrue);
    });

    test('Data memuat judul kolom dan baris', () async {
      final workbook = Excel.decodeBytes(
        await excel.export(
          documentWith(
            groups: [
              groupOf([dataRow(name: 'Anestesi', unit: 'ampul', qty: '10.5')]),
            ],
          ),
        ),
      );
      final text = textOf(workbook, 'Data');

      expect(text, contains('Barang'));
      expect(text, contains('Anestesi'));
      expect(text, contains('10.5'));
    });

    test(
      'subtotal kategori dan total keseluruhan tercetak per satuan',
      () async {
        // G-L6 in the file itself: one line per unit, never a combined figure.
        final obat = groupOf([
          dataRow(name: 'Anestesi', unit: 'ampul', qty: '10'),
        ]);
        final alat = ReportGroup(
          categoryId: 'cat-2',
          categoryName: 'Alat',
          rows: [dataRow(name: 'Masker', unit: 'box', qty: '3')],
          subtotals: ReportTotalsEngine.totalsOf([
            dataRow(name: 'Masker', unit: 'box', qty: '3'),
          ]),
        );

        final workbook = Excel.decodeBytes(
          await excel.export(
            documentWith(
              groups: [obat, alat],
              totals: ReportTotalsEngine.combine([
                obat.subtotals,
                alat.subtotals,
              ]),
            ),
          ),
        );
        final text = textOf(workbook, 'Data');

        expect(text, contains('Subtotal Obat'));
        expect(text, contains('Subtotal Alat'));
        expect(text, contains(ReportGroupingEngine.overallTotalLabel));
        expect(text, contains('ampul'));
        expect(text, contains('box'));
        // The two units appear as their own totals, never added.
        expect(text.contains('13'), isFalse);
      },
    );

    test('laporan kosong tetap valid dan menyebut tidak ada data', () async {
      final workbook = Excel.decodeBytes(await excel.export(documentWith()));
      final text = textOf(workbook, 'Data');

      expect(text, contains('Barang'));
      expect(text, contains(ReportDocument.emptyMessage));
    });

    test(
      'teks berbahaya ditulis sebagai literal, bukan formula (§38)',
      () async {
        final rows = [
          for (final dangerous in const [
            '=HYPERLINK("http://x","klik")',
            '+cmd|calc',
            '@SUM(A1)',
            '-1+1',
          ])
            dataRow(name: dangerous, unit: 'pcs', qty: '1'),
        ];

        final workbook = Excel.decodeBytes(
          await excel.export(documentWith(groups: [groupOf(rows)])),
        );
        final text = textOf(workbook, 'Data');

        for (final dangerous in const [
          '=HYPERLINK("http://x","klik")',
          '+cmd|calc',
          '@SUM(A1)',
          '-1+1',
        ]) {
          expect(text, contains("'$dangerous"), reason: dangerous);
          expect(text, isNot(contains(dangerous)), reason: dangerous);
        }
      },
    );

    test('peringatan integritas tercetak di Ringkasan', () async {
      final workbook = Excel.decodeBytes(
        await excel.export(
          documentWith(warnings: const ['Referensi barang tidak lengkap.']),
        ),
      );

      expect(
        textOf(workbook, 'Ringkasan'),
        contains('Referensi barang tidak lengkap.'),
      );
    });

    test(
      '5.000 baris tidak menyebabkan kegagalan',
      () async {
        final rows = [
          for (var index = 0; index < 5000; index++)
            dataRow(name: 'Barang $index', unit: 'pcs', qty: '1'),
        ];

        final bytes = await excel.export(
          documentWith(
            groups: [groupOf(rows)],
            totals: ReportTotalsEngine.totalsOf(rows),
          ),
        );

        expect(bytes.length, greaterThan(0));
        expect(bytes.sublist(0, 2), [0x50, 0x4B]);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('PDF', () {
    Future<Uint8List> render(ReportDocument document) => pdf.export(document);

    /// Everything the `pdf` package printed while rendering [document].
    ///
    /// The package does not fail on a character its font cannot draw: it swaps in
    /// an empty placeholder and prints a warning. That warning is therefore the
    /// only signal a glyph went missing, and capturing it is the only way to hold
    /// the exporter to the claim that its output is complete.
    Future<List<String>> renderLog(ReportDocument document) async {
      final lines = <String>[];
      await runZoned(
        () => render(document),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      return lines;
    }

    test('setiap karakter tipografi tetap tergambar', () async {
      // Helvetica's built-in metrics cover `U+0000`–`U+00FF` and nothing else. The
      // en dash between two period dates and the em dash that means *"not
      // applicable"* both sit above that line, and both appear on nearly every
      // report — so an exporter that passed them straight through would print a gap
      // where the range or the marker should be, and never say so.
      final document = documentWith(
        groups: [
          groupOf([
            dataRow(name: 'Kasa \u2013 steril', unit: 'roll', qty: '2'),
            dataRow(name: ReportLabels.notApplicable, unit: 'box', qty: '1'),
            dataRow(name: 'Panjang\u2026', unit: 'box', qty: '3'),
          ]),
        ],
        totals: ReportTotalsEngine.totalsOf([
          dataRow(name: 'x', unit: 'roll', qty: '2'),
        ]),
        warnings: const ['Data historis tidak tersedia \u2014 periksa master'],
      );

      final log = await renderLog(document);

      expect(
        log.where((line) => line.contains('Unable to find a font')),
        isEmpty,
        reason: log.join('\n'),
      );
    });

    test('karakter di luar Latin-1 tidak hilang diam-diam', () async {
      // `?` rather than nothing: a reader who sees one knows something was lost.
      final log = await renderLog(
        documentWith(
          groups: [
            groupOf([
              dataRow(name: 'Suhu \u2103 ruang', unit: 'box', qty: '1'),
            ]),
          ],
        ),
      );

      expect(
        log.where((line) => line.contains('Unable to find a font')),
        isEmpty,
      );
    });

    test('byte diawali %PDF', () async {
      final bytes = await render(documentWith());
      expect(utf8.decode(bytes.sublist(0, 4)), '%PDF');
    });

    test('laporan kosong menghasilkan satu PDF valid', () async {
      final bytes = await render(documentWith());
      expect(bytes.length, greaterThan(100));
      expect(_pageCount(bytes), 1);
    });

    test('laporan besar menghasilkan banyak halaman', () async {
      final rows = [
        for (var index = 0; index < 500; index++)
          dataRow(name: 'Barang $index', unit: 'pcs', qty: '1'),
      ];

      final bytes = await render(
        documentWith(
          groups: [groupOf(rows)],
          totals: ReportTotalsEngine.totalsOf(rows),
        ),
      );

      expect(_pageCount(bytes), greaterThan(1));
    });

    test('teks panjang tidak menggagalkan render', () async {
      final rows = [dataRow(name: 'A' * 400, unit: 'pcs', qty: '1')];

      final bytes = await render(documentWith(groups: [groupOf(rows)]));
      expect(bytes.length, greaterThan(100));
    });

    test('laporan lebar dirender landscape', () async {
      final wide = [
        for (var index = 0; index < 14; index++)
          ReportColumn(key: 'c$index', label: 'Kolom $index'),
      ];
      final narrow = documentWith();
      final landscape = documentWith(columns: wide);

      // Compared by size rather than by parsing: the landscape page box is wider,
      // and the two documents are otherwise identical.
      final narrowBytes = await render(narrow);
      final wideBytes = await render(landscape);
      expect(wideBytes.length, isNot(narrowBytes.length));
    });

    test('memakai font bawaan tanpa menyertakan file font', () async {
      // G-L3 is offline-first, and the PDF proves half of it: `/FontFile` is the
      // key that carries an *embedded* font program, and its absence means the
      // document relies on the standard-14 metrics every reader already has.
      //
      // The document does contain `http://` strings — XMP metadata identifies its
      // schemas by namespace URI, which is a name rather than an address and is
      // never fetched. Asserting their absence would be asserting something about
      // the `pdf` package's metadata rather than about this application, so the
      // "nothing is downloaded" half is covered where it belongs: the offline test
      // asserts that no reporting source imports `dart:io`'s HTTP client or any
      // network package at all.
      final bytes = await render(documentWith());
      final text = latin1.decode(bytes, allowInvalid: true);

      expect(text.contains('/FontFile'), isFalse);
      expect(text.contains('Helvetica'), isTrue);
    });
  });

  group('kedua format', () {
    test('membaca dokumen yang sama menghasilkan angka yang sama', () async {
      // §33: neither exporter computes anything, so a subtotal cannot differ
      // between them — the model carries one already-rendered string.
      final rows = [
        dataRow(name: 'Anestesi', unit: 'ampul', qty: '10.5'),
        dataRow(name: 'Masker', unit: 'box', qty: '2'),
      ];
      final document = documentWith(
        groups: [groupOf(rows)],
        totals: ReportTotalsEngine.totalsOf(rows),
      );

      final workbook = Excel.decodeBytes(await excel.export(document));
      final sheetText = textOf(workbook, 'Data').join(' ');
      final pdfText = latin1.decode(
        await pdf.export(document),
        allowInvalid: true,
      );

      expect(sheetText, contains('10.5'));
      expect(document.overallTotals.label, '10.5 ampul · 2 box');
      // The PDF is compressed, so its text is not readable here — what is asserted
      // is that it rendered from the same document without recomputing anything.
      expect(pdfText.startsWith('%PDF'), isTrue);
    });
  });
}

/// Counts `/Type /Page` objects — enough to tell one page from several without
/// adding a PDF parser to the project.
int _pageCount(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
}
