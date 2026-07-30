import 'dart:convert';
import 'dart:typed_data';

import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/reports/data/exporters/excel_report_exporter.dart';
import 'package:aish_warehouse/features/reports/data/exporters/pdf_report_exporter.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_grouping_engine.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// §5 — one document, three surfaces, one set of numbers.
///
/// The preview, the workbook and the PDF are three renderings of a single
/// [ReportDocument], and the only defensible relationship between them is that they
/// all say the same thing. This file takes **real** documents — the four recaps built
/// by the official workflows in the sibling `*_recap_report_test.dart` files — and
/// checks that relationship end to end:
///
/// * the preview shows every row the document has;
/// * the workbook contains exactly that many data rows, and its subtotal and total
///   cells are the document's own figures, character for character;
/// * the PDF renders without failing and is a real PDF.
///
/// ### What is deliberately *not* asserted about the PDF
///
/// Its text is not parsed back. A PDF reader would be a dependency added purely to
/// check something the workbook already proves — the numbers come from the document —
/// so the PDF is held to the two claims that can be made honestly at the byte level:
/// it is a PDF, and producing it did not throw.
///
/// ### The exporters cannot reach a database, and that is proven rather than argued
///
/// Each case disposes the database *before* exporting. An exporter that queried
/// anything would fail on a closed connection; one that renders what it was handed
/// does not notice. The source-level guards in `report_architecture_test.dart` say
/// the same thing statically; this says it at runtime.
void main() {
  const excelExporter = ExcelReportExporter();
  const pdfExporter = PdfReportExporter();

  /// A document plus the database it came from, so a case can close the database
  /// before exporting.
  ({TestContext context, ReportPreview preview}) pack(
    TestContext context,
    ReportPreview preview,
  ) => (context: context, preview: preview);

  /// *Rekap Stok Opname* — a reviewed count with a short and an over position.
  Future<({TestContext context, ReportPreview preview})> opnameCase() async {
    final wallClock = DateTime.now().toUtc();
    final submittedAtUtc = wallClock.add(const Duration(minutes: 1));
    final reviewedAtUtc = wallClock.add(const Duration(minutes: 2));
    final today = AppTimeZone.operationalDate(wallClock);

    final context = TestContext.create(clock: () => wallClock);
    final fixture = await buildOpnameFixture(context, now: wallClock);
    final opname = await context
        .createOpname(clock: () => wallClock)
        .call(actorUserId: fixture.nurse.id, roomId: fixture.room.id);

    final detail = await context.opnames.getDetail(opname.id);
    for (final line in detail!.lines) {
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: line.id,
        countedQty: line.itemId == fixture.simpleItem.id
            ? Quantity.parse('8')
            : Quantity.parse('3.375'),
        note: 'Dihitung ulang',
      );
    }
    await context
        .submitOpname(clock: () => submittedAtUtc)
        .call(actorUserId: fixture.nurse.id, opnameId: opname.id);
    await context
        .reviewOpname(clock: () => reviewedAtUtc)
        .call(actorUserId: fixture.branchHead.id, opnameId: opname.id);

    final preview = await context
        .buildReportPreview(clock: () => reviewedAtUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          draft: ReportRequestDraft(
            reportType: ReportType.rekapOpname,
            scopeType: ReportScopeType.branchAll,
            periodStart: DateOnly.addDays(today, -1),
            periodEnd: DateOnly.addDays(today, 1),
          ),
        );
    return pack(context, preview);
  }

  /// *Rekap Distribusi* — one document into two rooms, one request split by FEFO.
  Future<({TestContext context, ReportPreview preview})>
  distributionCase() async {
    final wallClock = DateTime.now().toUtc();
    final postedAtUtc = wallClock.add(const Duration(minutes: 1));
    final today = AppTimeZone.operationalDate(wallClock);

    final context = TestContext.create(clock: () => wallClock);
    final fixture = await buildDistributionFixture(context, nowUtc: wallClock);
    final distributionId = await createDistributionDraft(
      context,
      fixture,
      nowUtc: wallClock,
    );
    await addDistributionItem(
      context,
      fixture,
      distributionId: distributionId,
      roomId: fixture.roomOne.id,
      itemId: fixture.simpleItem.id,
      qty: '2.5',
      nowUtc: wallClock,
    );
    await addDistributionItem(
      context,
      fixture,
      distributionId: distributionId,
      roomId: fixture.roomOne.id,
      itemId: fixture.batchItem.id,
      qty: '3',
      nowUtc: wallClock,
    );
    await addDistributionItem(
      context,
      fixture,
      distributionId: distributionId,
      roomId: fixture.roomTwo.id,
      itemId: fixture.simpleItem.id,
      qty: '1.5',
      nowUtc: wallClock,
    );
    await context
        .postDistribution(clock: () => postedAtUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          distributionId: distributionId,
        );

    final preview = await context
        .buildReportPreview(clock: () => postedAtUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          draft: ReportRequestDraft(
            reportType: ReportType.rekapDistribusi,
            scopeType: ReportScopeType.branchAll,
            periodStart: DateOnly.addDays(today, -1),
            periodEnd: DateOnly.addDays(today, 1),
          ),
        );
    return pack(context, preview);
  }

  /// *Rekap Pemakaian* — one nurse's posted consumption, two units.
  Future<({TestContext context, ReportPreview preview})>
  consumptionCase() async {
    final wallClock = DateTime.now().toUtc();
    final postedAtUtc = wallClock.add(const Duration(minutes: 1));
    final today = AppTimeZone.operationalDate(wallClock);

    final context = TestContext.create(clock: () => wallClock);
    final fixture = await buildConsumptionFixture(context, nowUtc: wallClock);
    final consumptionId = await createConsumptionDraft(
      context,
      fixture,
      roomId: fixture.roomOne.id,
      nowUtc: wallClock,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: consumptionId,
      itemId: fixture.expiryItem.id,
      batchId: fixture.validBatch.id,
      qty: '2.375',
      nowUtc: wallClock,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: consumptionId,
      itemId: fixture.otherExpiryItem.id,
      batchId: fixture.otherItemBatch.id,
      qty: '1.5',
      nowUtc: wallClock,
    );
    await context
        .postConsumption(clock: () => postedAtUtc)
        .call(actorUserId: fixture.nurse.id, consumptionId: consumptionId);

    final preview = await context
        .buildReportPreview(clock: () => postedAtUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          draft: ReportRequestDraft(
            reportType: ReportType.rekapPemakaian,
            scopeType: ReportScopeType.branchAll,
            periodStart: DateOnly.addDays(today, -1),
            periodEnd: DateOnly.addDays(today, 1),
          ),
        );
    return pack(context, preview);
  }

  /// *Rekap Pemusnahan* — two batches destroyed at Warehouse Pusat.
  Future<({TestContext context, ReportPreview preview})> disposalCase() async {
    final wallClock = DateTime.now().toUtc();
    final postedAtUtc = wallClock.add(const Duration(minutes: 1));
    final today = AppTimeZone.operationalDate(wallClock);

    final context = TestContext.create(clock: () => wallClock);
    final fixture = await buildDisposalFixture(context, nowUtc: wallClock);
    final disposalId = await createDisposalDraft(
      context,
      fixture,
      sourceLocationId: fixture.warehouse.id,
      nowUtc: wallClock,
      reason: 'Kedaluwarsa gudang pusat',
    );
    await addDisposalPosition(
      context,
      fixture,
      disposalId: disposalId,
      itemId: fixture.expiryItem.id,
      batchId: fixture.expiredBatch.id,
      qty: '2.375',
      nowUtc: wallClock,
    );
    await addDisposalPosition(
      context,
      fixture,
      disposalId: disposalId,
      itemId: fixture.otherExpiryItem.id,
      batchId: fixture.otherExpiredBatch.id,
      qty: '0.5',
      nowUtc: wallClock,
    );
    await context
        .postDisposal(clock: () => postedAtUtc)
        .call(actorUserId: fixture.warehouseUser.id, disposalId: disposalId);

    final preview = await context
        .buildReportPreview(clock: () => postedAtUtc)
        .call(
          actorUserId: fixture.superAdmin.id,
          draft: ReportRequestDraft(
            reportType: ReportType.rekapPemusnahan,
            scopeType: ReportScopeType.allLocations,
            periodStart: DateOnly.addDays(today, -1),
            periodEnd: DateOnly.addDays(today, 1),
          ),
        );
    return pack(context, preview);
  }

  /// Every row of one sheet as plain strings, `null` cells included as `''`.
  List<List<String>> sheetRows(Excel workbook, String name) => [
    for (final row in workbook.tables[name]!.rows)
      [for (final cell in row) cell?.value?.toString() ?? ''],
  ];

  final cases =
      <
        String,
        Future<({TestContext context, ReportPreview preview})> Function()
      >{
        'Rekap Stok Opname': opnameCase,
        'Rekap Distribusi': distributionCase,
        'Rekap Pemakaian': consumptionCase,
        'Rekap Pemusnahan': disposalCase,
      };

  for (final entry in cases.entries) {
    group(entry.key, () {
      late TestContext context;
      late ReportPreview preview;
      late ReportDocument document;
      late Uint8List xlsx;
      late Uint8List pdf;
      late Excel workbook;

      setUp(() async {
        final built = await entry.value();
        context = built.context;
        preview = built.preview;
        document = preview.document;

        // Closed *before* exporting: an exporter that queried anything would fail
        // here, and one that renders what it was handed does not notice.
        await context.dispose();

        xlsx = await excelExporter.export(document);
        pdf = await pdfExporter.export(document);
        workbook = Excel.decodeBytes(xlsx);
      });

      test('dokumen tidak kosong, sehingga perbandingan ini berarti', () {
        expect(document.rows, isNotEmpty);
        expect(document.groups, isNotEmpty);
        expect(document.overallTotals.units, isNotEmpty);
      });

      test('preview menampilkan seluruh baris dokumen', () {
        expect(preview.displayedRowCount, document.rowCount);
        expect(preview.totalRowCount, document.rowCount);
        expect(preview.isTruncated, isFalse);
      });

      test('workbook memuat baris data sebanyak dokumen', () {
        // Column 0 of every recap is the document number, which no heading,
        // subtotal or total row carries — so counting them counts data rows.
        final docNumbers = document.rows
            .map((row) => row.cells.first.text)
            .toSet();
        final dataRows = sheetRows(
          workbook,
          ExcelReportExporter.dataSheetName,
        ).where((row) => row.isNotEmpty && docNumbers.contains(row.first));

        expect(dataRows, hasLength(document.rowCount));
      });

      test('setiap sel baris pertama tercetak apa adanya di workbook', () {
        final first = document.rows.first;
        final printed = sheetRows(workbook, ExcelReportExporter.dataSheetName)
            .firstWhere(
              (row) => row.isNotEmpty && row.first == first.cells.first.text,
            );

        for (var column = 0; column < first.cells.length; column++) {
          final text = first.cells[column].text;
          if (text.isEmpty) continue;
          expect(
            printed[column],
            SpreadsheetExpectation.of(text),
            reason: 'kolom ${document.columns[column].label}',
          );
        }
      });

      test('subtotal kategori di workbook sama dengan subtotal dokumen', () {
        final rows = sheetRows(workbook, ExcelReportExporter.dataSheetName);

        for (final group in document.groups) {
          final label = ReportGroupingEngine.subtotalLabel(group);
          for (final unit in group.subtotals.units) {
            final printed = rows.firstWhere(
              (row) => row.length > 2 && row[0] == label && row[1] == unit,
              orElse: () => throw StateError('Subtotal $label/$unit hilang.'),
            );
            // Through the sanitizer, because a negative total starts with `-` and
            // a spreadsheet would otherwise read it as a formula (§34).
            expect(
              printed[2],
              SpreadsheetExpectation.of(group.subtotals[unit]!.format()),
            );
          }
        }
      });

      test('total keseluruhan di workbook sama dengan total dokumen', () {
        final rows = sheetRows(workbook, ExcelReportExporter.dataSheetName);
        const label = ReportGroupingEngine.overallTotalLabel;

        for (final unit in document.overallTotals.units) {
          final printed = rows.firstWhere(
            (row) => row.length > 2 && row[0] == label && row[1] == unit,
            orElse: () => throw StateError('Total $unit hilang.'),
          );
          expect(
            printed[2],
            SpreadsheetExpectation.of(document.overallTotals[unit]!.format()),
          );
        }
      });

      test('satuan tidak pernah dijumlahkan menjadi satu angka', () {
        // One total row per unit, never one row summing them (§32).
        final rows = sheetRows(workbook, ExcelReportExporter.dataSheetName);
        const label = ReportGroupingEngine.overallTotalLabel;
        final totalRows = rows.where(
          (row) => row.isNotEmpty && row[0] == label,
        );

        expect(totalRows, hasLength(document.overallTotals.units.length));
      });

      test('jumlah baris tercetak di sheet Ringkasan', () {
        final summary = sheetRows(
          workbook,
          ExcelReportExporter.summarySheetName,
        ).expand((row) => row);

        expect(summary, contains('${document.rowCount}'));
      });

      test('PDF punya tanda tangan yang benar dan tidak gagal dirender', () {
        expect(utf8.decode(pdf.sublist(0, 4)), '%PDF');
        expect(pdf.length, greaterThan(1000));
      });

      test('XLSX punya tanda tangan ZIP dan terbuka kembali', () {
        expect(xlsx.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
        expect(
          workbook.tables.keys,
          containsAll(<String>[
            ExcelReportExporter.summarySheetName,
            ExcelReportExporter.dataSheetName,
          ]),
        );
      });

      test('mengekspor dua kali menghasilkan angka yang sama', () async {
        // Determinism across surfaces: nothing in an exporter may depend on the
        // clock, on a random id or on anything but the document it was given.
        final again = Excel.decodeBytes(await excelExporter.export(document));

        expect(
          sheetRows(again, ExcelReportExporter.dataSheetName),
          sheetRows(workbook, ExcelReportExporter.dataSheetName),
        );
      });
    });
  }
}

/// A cell as the workbook holds it, allowing for the leading `'` the sanitizer adds
/// to anything a spreadsheet would otherwise read as a formula (§34).
abstract final class SpreadsheetExpectation {
  static Matcher of(String text) => anyOf(equals(text), equals("'$text"));
}
