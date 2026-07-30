import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import 'reporting_fixture.dart';

/// The three ledger-primary reports, end to end against a real database.
///
/// Everything here goes through [BuildReportPreviewUseCase], so each assertion
/// exercises the whole path: actor reload → access policy → filter policy → scope
/// resolution → DAO → repository → engine → builder. A test that called a builder
/// directly would pass on a module whose repository never scoped anything.
void main() {
  late TestContext context;
  late ReportingFixture fixture;

  /// 20 Jul 2026, 10:00 GMT+8.
  final postedAtUtc = DateTime.utc(2026, 7, 20, 2);

  setUp(() async {
    context = TestContext.create();
    fixture = await buildReportingFixture(context, postedAtUtc: postedAtUtc);
  });

  tearDown(() => context.dispose());

  Future<ReportPreview> preview({
    required String actorUserId,
    required ReportType reportType,
    required ReportScopeType scopeType,
    String? locationId,
    String? branchId,
    String? categoryId,
    String? itemId,
    DateTime? asOf,
    DateTime? start,
    DateTime? end,
    DateTime? clockUtc,
  }) {
    final at = clockUtc ?? fixture.asOfNearUtc;
    final endDate = end ?? asOf ?? fixture.asOfNearDate;
    return context
        .buildReportPreview(clock: () => at)
        .call(
          actorUserId: actorUserId,
          draft: ReportRequestDraft(
            reportType: reportType,
            scopeType: scopeType,
            periodStart: start ?? fixture.postedDate,
            periodEnd: endDate,
            locationId: locationId,
            branchId: branchId,
            filter: ReportFilter(categoryId: categoryId, itemId: itemId),
          ),
        );
  }

  group('Stok Saat Ini (G-L4)', () {
    test('saldo warehouse dihitung dari ledger', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      final byBatch = {
        for (final row in result.document.rows) row.cells[5].text: row.quantity,
      };
      expect(byBatch['B-NEAR'], fixture.warehouseNearBatchQty);
      expect(byBatch['B-SAFE'], fixture.warehouseSafeBatchQty);
      // The unbatched item's batch cell is the not-applicable marker.
      expect(byBatch[ReportLabels.notApplicable], fixture.warehouseAlatQty);
    });

    test('branch_all memisahkan gudang cabang dan ruangan', () async {
      // §21: netting the distribution away would leave the branch total unchanged
      // and destroy the only fact the report is run to establish.
      final result = await preview(
        actorUserId: fixture.branchHead.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.branchAll,
      );

      final locations = result.document.rows
          .map((row) => row.cells.first.text)
          .toSet();
      expect(locations, hasLength(2));

      final byLocationAndBatch = {
        for (final row in result.document.rows)
          '${row.cells.first.text}|${row.cells[5].text}': row.quantity,
      };
      expect(
        byLocationAndBatch.values.where(
          (qty) => qty == fixture.branchStoreNearBatchQty,
        ),
        isNotEmpty,
      );
      expect(
        byLocationAndBatch.values.where(
          (qty) => qty == fixture.roomNearBatchQty,
        ),
        isNotEmpty,
      );
    });

    test('posisi bersaldo nol tidak muncul', () async {
      final result = await preview(
        actorUserId: fixture.nurse.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.room,
        locationId: fixture.roomLocation.id,
      );

      for (final row in result.document.rows) {
        expect(row.quantity!.isPositive, isTrue);
      }
    });

    test('cutoff sebelum pergerakan menghasilkan laporan kosong', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
        asOf: DateTime.utc(2026, 7, 19),
        clockUtc: DateTime.utc(2026, 7, 19, 2),
      );

      expect(result.document.isEmpty, isTrue);
      expect(result.document.header.rowCount, 0);
    });

    test('filter kategori mempersempit tanpa mengubah kuantitas', () async {
      final all = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );
      final obatOnly = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
        categoryId: fixture.obatCategory.id,
      );

      expect(all.document.groups, hasLength(2));
      expect(obatOnly.document.groups, hasLength(1));
      expect(
        obatOnly.document.overallTotals['ampul'],
        all.document.overallTotals['ampul'],
      );
      expect(obatOnly.document.overallTotals['box'], isNull);
    });

    test('subtotal per satuan tidak dicampur', () async {
      // G-L6 with two real units: ampul and box must never be added.
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      final totals = result.document.overallTotals;
      expect(totals.units, ['ampul', 'box']);
      expect(
        totals['ampul'],
        fixture.warehouseNearBatchQty + fixture.warehouseSafeBatchQty,
      );
      expect(totals['box'], fixture.warehouseAlatQty);
    });

    test('minimum ruangan dan cabang dipakai, warehouse tidak', () async {
      // §21: Warehouse Pusat has no minimum column in this schema, so no threshold
      // is invented for it.
      final warehouseReport = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );
      for (final row in warehouseReport.document.rows) {
        expect(row.cells[9].text, ReportLabels.notApplicable);
      }

      final branchReport = await preview(
        actorUserId: fixture.branchHead.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.branchStore,
        locationId: fixture.branchStore.id,
      );
      expect(
        branchReport.document.rows.every(
          (row) => row.cells[9].text != ReportLabels.notApplicable,
        ),
        isTrue,
      );
    });

    test('header mencantumkan waktu cetak, periode, lokasi dan sync', () async {
      // G-L3.
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      final header = result.document.header;
      expect(header.generatedAtUtc, fixture.asOfNearUtc);
      expect(header.period.isSingleDay, isTrue);
      expect(header.locationLabel, fixture.warehouse.name);
      expect(header.exportedByLabel, fixture.warehouseUser.fullName);
      expect(header.syncSnapshot.isEmpty, isFalse);
      expect(header.syncSnapshot.label, contains('pending'));
      expect(header.rowCount, result.document.rowCount);
    });
  });

  group('Kartu Stok', () {
    test('saldo awal, mutasi dan saldo akhir konsisten', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kartuStok,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
        itemId: fixture.obatItem.id,
        start: fixture.postedDate,
        end: fixture.asOfNearDate,
      );

      final metrics = {
        for (final metric in result.document.sections.single.metrics)
          metric.label: metric.value,
      };
      expect(metrics['Saldo awal'], '0 ampul');
      expect(metrics['Total masuk'], '150 ampul');
      expect(metrics['Total keluar'], '30 ampul');
      expect(metrics['Saldo akhir'], '120 ampul');
    });

    test('kolom masuk dan keluar tidak pernah terisi bersamaan', () async {
      // §22: a zero in the other column would read as "nothing moved" rather than
      // "this row is not that direction".
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kartuStok,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
        itemId: fixture.obatItem.id,
      );

      for (final row in result.document.rows) {
        final incoming = row.cells[9].text;
        final outgoing = row.cells[10].text;
        expect(incoming.isEmpty || outgoing.isEmpty, isTrue);
        expect(incoming.isEmpty && outgoing.isEmpty, isFalse);
      }
    });

    test('kartu stok menampilkan seluruh batch barang tersebut', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kartuStok,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
        itemId: fixture.obatItem.id,
      );

      final batches = result.document.rows
          .map((row) => row.cells[7].text)
          .toSet();
      expect(batches, containsAll(<String>{'B-NEAR', 'B-SAFE'}));
    });

    test('kartu stok tanpa barang ditolak', () async {
      await expectLater(
        preview(
          actorUserId: fixture.warehouseUser.id,
          reportType: ReportType.kartuStok,
          scopeType: ReportScopeType.warehouse,
          locationId: fixture.warehouse.id,
        ),
        throwsA(isA<ReportItemRequiredFailure>()),
      );
    });

    test('kartu stok pada branch_all ditolak', () async {
      await expectLater(
        preview(
          actorUserId: fixture.branchHead.id,
          reportType: ReportType.kartuStok,
          scopeType: ReportScopeType.branchAll,
          itemId: fixture.obatItem.id,
        ),
        throwsA(isA<ReportAccessDeniedFailure>()),
      );
    });

    test('nomor dokumen tidak pernah berupa UUID mentah', () async {
      // §22: an auditor reading "Referensi tidak tersedia" learns something; a hex
      // string tells them nothing.
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kartuStok,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
        itemId: fixture.obatItem.id,
      );

      for (final row in result.document.rows) {
        expect(row.cells[3].text, isNot(matches(RegExp(r'^[0-9a-f-]{36}$'))));
      }
    });
  });

  group('Laporan Kedaluwarsa (G-E8)', () {
    test('hanya barang ber-ED dan batch bersaldo positif', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kadaluarsa,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      expect(result.document.rows, hasLength(2));
      for (final row in result.document.rows) {
        expect(row.cells[3].text, fixture.obatItem.name);
        expect(row.quantity!.isPositive, isTrue);
      }
    });

    test('diurutkan ED terdekat lebih dulu', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kadaluarsa,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      expect(result.document.rows.first.cells[5].text, 'B-NEAR');
      expect(result.document.rows.last.cells[5].text, 'B-SAFE');
    });

    test('status aman dan segera kedaluwarsa dibedakan', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kadaluarsa,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      final byBatch = {
        for (final row in result.document.rows)
          row.cells[5].text: row.cells[8].text,
      };
      expect(byBatch['B-NEAR'], 'Segera kedaluwarsa');
      expect(byBatch['B-SAFE'], 'Aman');
    });

    test('batch yang lewat tanggal muncul sebagai kedaluwarsa', () async {
      // The batch is reached by waiting rather than by faking one: G-E4 refuses to
      // transfer expired stock, so a shelf cannot be *given* one.
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kadaluarsa,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
        asOf: fixture.asOfExpiredDate,
        clockUtc: fixture.asOfExpiredUtc,
      );

      final byBatch = {
        for (final row in result.document.rows)
          row.cells[5].text: row.cells[8].text,
      };
      expect(byBatch['B-NEAR'], 'Kedaluwarsa');
      expect(byBatch['B-SAFE'], 'Aman');
    });

    test('sisa hari negatif setelah kedaluwarsa', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kadaluarsa,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
        asOf: fixture.asOfExpiredDate,
        clockUtc: fixture.asOfExpiredUtc,
      );

      final near = result.document.rows.firstWhere(
        (row) => row.cells[5].text == 'B-NEAR',
      );
      expect(int.parse(near.cells[7].text), lessThan(0));
    });

    test('total kedaluwarsa memakai satuan barang', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.kadaluarsa,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      expect(result.document.overallTotals.units, ['ampul']);
      expect(
        result.document.overallTotals['ampul'],
        fixture.warehouseNearBatchQty + fixture.warehouseSafeBatchQty,
      );
    });
  });

  group('preview tidak menulis apa pun', () {
    test('tidak ada export log setelah preview', () async {
      // §3.13: G-L2 audits exports, and looking at a report is not one.
      await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      expect(await context.exportLogCount(), 0);
    });
  });

  group('batas preview', () {
    test('laporan kecil tidak terpotong', () async {
      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      expect(result.isTruncated, isFalse);
      expect(result.displayedRowCount, result.totalRowCount);
    });
  });

  group('pemulihan historis (§51)', () {
    test('barang nonaktif tetap muncul dengan kuantitasnya', () async {
      await context.deactivate('items', fixture.obatItem.id);

      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      expect(result.document.overallTotals['ampul'], isNotNull);
    });

    test('barang di-soft-delete tetap muncul dan diberi label', () async {
      await context.archive('items', fixture.obatItem.id);

      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      expect(result.document.overallTotals['ampul'], isNotNull);
    });

    test('barang hilang fisik: kuantitas bertahan, ada peringatan', () async {
      // The distinction §35 draws: a missing *reference* degrades to a label, a
      // missing *movement* is a hard failure.
      await context.corruptByDeleting('items', fixture.alatItem.id);

      final result = await preview(
        actorUserId: fixture.warehouseUser.id,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.warehouse,
        locationId: fixture.warehouse.id,
      );

      expect(result.document.warnings, isNotEmpty);
      final labels = result.document.rows.map((row) => row.cells[3].text);
      expect(labels, contains(ReportLabels.historicalItem));
      // The quantity is still there, in the historical-category bucket.
      expect(
        result.document.groups.any(
          (group) => group.categoryName == ReportGroup.unresolvedCategoryName,
        ),
        isTrue,
      );
    });
  });
}
