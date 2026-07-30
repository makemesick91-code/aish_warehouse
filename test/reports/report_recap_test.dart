import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The eight document recaps (§24–§31), against the real PR → DO → GR → Retur
/// chain the earlier milestones' fixtures build.
///
/// ### Why the period is "today"
///
/// Document rows take `created_at` from the table's own `clientDefault`, so a
/// fixture cannot place them in the past the way the ledger fixture back-dates
/// movements. Running every recap over the current operational day is therefore the
/// honest window — and it exercises the same [ReportPeriodPolicy] boundary the
/// period tests pin exactly.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;
  late DateTime nowUtc;
  late DateTime today;

  setUp(() async {
    context = TestContext.create();
    nowUtc = DateTime.now().toUtc();
    today = AppTimeZone.operationalDate(nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<ReportPreview> recap({
    required MasterUser actor,
    required ReportType reportType,
    ReportScopeType? scopeType,
    String? branchId,
    String? categoryId,
    Set<String> statuses = const <String>{},
    GoodReceiptDiscrepancyFilter discrepancy = GoodReceiptDiscrepancyFilter.all,
  }) => context
      .buildReportPreview(clock: () => nowUtc)
      .call(
        actorUserId: actor.id,
        draft: ReportRequestDraft(
          reportType: reportType,
          scopeType:
              scopeType ??
              (actor.role == UserRole.kepalaCabang
                  ? ReportScopeType.branchAll
                  : ReportScopeType.crossBranch),
          // A generous window either side of today, so a document created a second
          // before midnight is still in range.
          periodStart: DateOnly.addDays(today, -1),
          periodEnd: DateOnly.addDays(today, 1),
          branchId: branchId,
          filter: ReportFilter(
            categoryId: categoryId,
            statuses: statuses,
            discrepancy: discrepancy,
          ),
        ),
      );

  /// One cell of the first row whose leading cell equals [docNumber].
  String cellOf(ReportDocument document, String docNumber, int column) =>
      document.rows
          .firstWhere((row) => row.cells.first.text == docNumber)
          .cells[column]
          .text;

  group('setiap rekap dapat dijalankan (§24–§31)', () {
    for (final reportType in const [
      ReportType.rekapOpname,
      ReportType.rekapPr,
      ReportType.rekapDo,
      ReportType.rekapGr,
      ReportType.rekapDistribusi,
      ReportType.rekapPemakaian,
      ReportType.rekapPemusnahan,
      ReportType.rekapRetur,
    ]) {
      test('${reportType.dbValue} lintas cabang untuk Warehouse', () async {
        final result = await recap(
          actor: fixture.warehouseUser,
          reportType: reportType,
        );

        expect(result.document.columns, isNotEmpty);
        expect(result.document.header.title, reportType.label);
        expect(
          result.document.header.scopeLabel,
          ReportScopeType.crossBranch.label,
        );
        // Every recap totals per unit and never across them (§32).
        expect(
          result.document.overallTotals.units.length,
          lessThanOrEqualTo(result.document.overallTotals.asMap.length),
        );
      });

      test(
        '${reportType.dbValue} cakupan cabang untuk Kepala Cabang',
        () async {
          final result = await recap(
            actor: fixture.branchHead,
            reportType: reportType,
          );

          expect(result.document.header.branchLabel, fixture.branch.name);
        },
      );
    }
  });

  group('Rekap Purchase Request (§25)', () {
    test('memisahkan requested dari shipped', () async {
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapPr,
      );

      expect(result.document.rows, isNotEmpty);
      final columns = result.document.columns.map((c) => c.key).toList();
      expect(columns, contains('requested'));
      expect(columns, contains('shipped'));
      expect(columns, contains('accepted'));
      expect(columns, contains('returned'));
      expect(columns, contains('outstanding'));
    });

    test('outstanding tidak pernah negatif', () async {
      // §25: an over-shipment is refused by G-D2, so a negative "outstanding"
      // would read as the branch owing the Warehouse goods.
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapPr,
      );
      final outstandingColumn = result.document.columns.indexWhere(
        (column) => column.key == 'outstanding',
      );

      for (final row in result.document.rows) {
        expect(
          Quantity.parse(row.cells[outstandingColumn].text).isNegative,
          isFalse,
        );
      }
    });

    test('shipped berasal dari ledger, bukan dari dokumen PR', () async {
      // The Purchase Request posts nothing at all (§2.5), so a non-zero shipped
      // column can only have come from the shipments raised against it.
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapPr,
      );
      final shippedColumn = result.document.columns.indexWhere(
        (column) => column.key == 'shipped',
      );

      final anyShipped = result.document.rows.any(
        (row) => Quantity.parse(row.cells[shippedColumn].text).isPositive,
      );
      expect(anyShipped, isTrue);
    });
  });

  group('Rekap Delivery Order (§26)', () {
    test('mencantumkan nomor PR dan nomor DO', () async {
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapDo,
      );

      expect(result.document.rows, isNotEmpty);
      expect(result.document.columns[0].label, 'Nomor DO/SJ');
      expect(result.document.columns[1].label, 'Nomor PR');
    });

    test('dokumen preparing tidak menyumbang kuantitas', () async {
      // Its allocations exist; no `shipment` movement does (§26).
      final preparing = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapDo,
        statuses: {DeliveryOrderStatus.preparing.dbValue},
      );

      for (final row in preparing.document.rows) {
        expect(row.quantity, Quantity.zero());
      }
      expect(preparing.document.overallTotals.isEmpty, isTrue);
    });

    test('filter status mempersempit dokumen', () async {
      final all = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapDo,
      );
      final shipped = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapDo,
        statuses: {DeliveryOrderStatus.shipped.dbValue},
      );

      expect(
        shipped.document.rowCount,
        lessThanOrEqualTo(all.document.rowCount),
      );
    });
  });

  group('Rekap Penerimaan dan Selisih GR (§27)', () {
    test('shortage dan rejected adalah kolom berbeda', () async {
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
      );
      final columns = result.document.columns.map((column) => column.key);

      expect(columns, contains('shortage'));
      expect(columns, contains('rejected'));
      expect(columns, contains('accepted'));
    });

    test('baris rejected tidak dihitung sebagai shortage', () async {
      // The distinction the report exists for: a shortage never arrived, a
      // rejection is in the branch waiting to go home (§27).
      final rejected = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
        discrepancy: GoodReceiptDiscrepancyFilter.rejected,
      );
      final shortageColumn = rejected.document.columns.indexWhere(
        (column) => column.key == 'shortage',
      );

      expect(rejected.document.rows, isNotEmpty);
      for (final row in rejected.document.rows) {
        expect(Quantity.parse(row.cells[shortageColumn].text), Quantity.zero());
      }
    });

    test('baris shortage tidak dihitung sebagai rejected', () async {
      final shortage = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
        discrepancy: GoodReceiptDiscrepancyFilter.shortage,
      );
      final rejectedColumn = shortage.document.columns.indexWhere(
        (column) => column.key == 'rejected',
      );

      expect(shortage.document.rows, isNotEmpty);
      for (final row in shortage.document.rows) {
        expect(Quantity.parse(row.cells[rejectedColumn].text), Quantity.zero());
      }
    });

    test('filter tanpa selisih menyisakan baris bersih saja', () async {
      final clean = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
        discrepancy: GoodReceiptDiscrepancyFilter.none,
      );
      final discrepancyColumn = clean.document.columns.indexWhere(
        (column) => column.key == 'discrepancy',
      );

      for (final row in clean.document.rows) {
        expect(
          row.cells[discrepancyColumn].text,
          GoodReceiptDiscrepancyFilter.none.label,
        );
      }
    });

    test(
      'status retur terisi dari dokumen Retur, bukan dari penolakan',
      () async {
        // §27: "a line was rejected" and "a return was created for it" are different
        // facts, and the Warehouse's queue is exactly the gap between them.
        final result = await recap(
          actor: fixture.warehouseUser,
          reportType: ReportType.rekapGr,
          discrepancy: GoodReceiptDiscrepancyFilter.rejected,
        );
        final returnColumn = result.document.columns.indexWhere(
          (column) => column.key == 'returnStatus',
        );

        expect(
          result.document.rows.map((row) => row.cells[returnColumn].text),
          everyElement('Belum dibuat'),
        );
      },
    );
  });

  group('Rekap Retur (§31)', () {
    test('retur yang belum dibuat tidak muncul', () async {
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapRetur,
      );

      expect(result.document.isEmpty, isTrue);
    });

    test('retur draft muncul dengan qty diterima nol', () async {
      // §31: the gap between what is in the box and what is on the shelf is the
      // report — a draft has a quantity in the box and nothing received.
      final created = await context
          .createGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            goodReceiptId: fixture.goodReceiptId,
          );

      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapRetur,
      );

      expect(result.document.rows, isNotEmpty);
      final documentQtyColumn = result.document.columns.indexWhere(
        (column) => column.key == 'documentQty',
      );
      final receivedQtyColumn = result.document.columns.indexWhere(
        (column) => column.key == 'receivedQty',
      );

      for (final row in result.document.rows) {
        expect(
          Quantity.parse(row.cells[documentQtyColumn].text).isPositive,
          isTrue,
        );
        expect(
          Quantity.parse(row.cells[receivedQtyColumn].text),
          Quantity.zero(),
        );
      }
      expect(created.id, isNotEmpty);
    });
  });

  group('cakupan rekap (G-L1)', () {
    test('Kepala Cabang tidak melihat dokumen cabang lain', () async {
      final result = await recap(
        actor: fixture.branchHead,
        reportType: ReportType.rekapGr,
      );

      // The other branch's receipt exists; it must not appear.
      final numbers = result.document.rows.map((row) => row.cells.first.text);
      expect(numbers, isNotEmpty);
      final otherBranchNumber = await context.goodReceiptColumn(
        fixture.otherBranchGoodReceiptId,
        'doc_number',
      );
      expect(numbers.contains(otherBranchNumber), isFalse);
    });

    test('Warehouse melihat dokumen kedua cabang', () async {
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
      );

      final otherBranchNumber = await context.goodReceiptColumn(
        fixture.otherBranchGoodReceiptId,
        'doc_number',
      );
      expect(
        result.document.rows.map((row) => row.cells.first.text),
        contains(otherBranchNumber),
      );
    });

    test('Warehouse dapat mempersempit ke satu cabang', () async {
      // §4.2 asks the Warehouse screen for *"rekap PR/DO per cabang"* as well as
      // the cross-branch view, so narrowing is a **scope** (`branch_all`) rather
      // than a filter — which is also what lets the audit row record which branch
      // was exported (§12 pins `cross_branch` to a NULL `branch_id`).
      final filtered = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
        scopeType: ReportScopeType.branchAll,
        branchId: fixture.otherBranch.id,
      );

      final ownBranchNumber = await context.goodReceiptColumn(
        fixture.goodReceiptId,
        'doc_number',
      );
      expect(
        filtered.document.rows.map((row) => row.cells.first.text),
        isNot(contains(ownBranchNumber)),
      );
    });

    test('Super Admin melihat semuanya', () async {
      final result = await recap(
        actor: fixture.superAdmin,
        reportType: ReportType.rekapGr,
        scopeType: ReportScopeType.allLocations,
      );

      expect(result.document.rows, isNotEmpty);
    });

    test('cellOf menemukan baris berdasarkan nomor dokumen', () async {
      // A guard on the helper the assertions above lean on.
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
      );
      final first = result.document.rows.first.cells.first.text;

      expect(cellOf(result.document, first, 0), first);
    });
  });

  group('pengelompokan kategori pada rekap (G-L6)', () {
    test('tanpa filter kategori hasil dikelompokkan', () async {
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
      );

      expect(result.document.groups, isNotEmpty);
      expect(result.document.header.categoryLabel, ReportLabels.allCategories);
    });

    test('dengan filter kategori hanya satu grup', () async {
      final categories = await context.master.categories();
      final result = await recap(
        actor: fixture.warehouseUser,
        reportType: ReportType.rekapGr,
        categoryId: categories.first.id,
      );

      expect(result.document.groups.length, lessThanOrEqualTo(1));
      expect(result.document.header.categoryLabel, categories.first.name);
    });
  });
}
