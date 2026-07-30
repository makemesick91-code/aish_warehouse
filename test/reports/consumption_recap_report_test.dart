import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_date_time_formatter.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// *Rekap Pemakaian* (§29) against documents driven through the **real** workflow:
/// `draft → posted`, with the posting service writing the ledger.
///
/// ### What the fixture is arranged to prove
///
/// * One nurse posts a consumption in room 1 covering a batch-tracked item, a second
///   batch of the same item, and an item without expiry — so the batch column, the
///   unit split and the fixed-point path all have something real behind them.
/// * A **second nurse in the same room** posts their own. G-L1's ownership rule is
///   the only thing that can tell the two apart here: same branch, same room, same
///   period. If the report leaked, this is where it would show.
/// * A third document is left in `draft`, which is how "document intent is not a
///   stock effect" is asserted: it has a line, it has a quantity, and the ledger has
///   never heard of it.
///
/// ### There is no patient anywhere, and that is asserted
///
/// The schema holds no patient data and this report will not imply any. The column
/// set is checked against that claim rather than left to be noticed.
///
/// ### Clocks
///
/// `consumptions.created_at` comes from the table's own `clientDefault` (the wall
/// clock), so the report window has to cover today. `posted_at` is stamped from an
/// injected clock a minute ahead, which keeps `created_at < posted_at` without
/// depending on how fast the suite runs (T-7).
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;
  late DateTime wallClock;
  late DateTime postedAtUtc;
  late DateTime today;
  late String consumptionId;
  late String colleagueId;
  late String draftId;
  late String docNumber;
  late String colleagueNumber;
  late String draftNumber;

  /// Column indexes of [ConsumptionRecapReportBuilder.columns], named once.
  const docNumberColumn = 0;
  const branchColumn = 1;
  const roomColumn = 2;
  const nurseColumn = 3;
  const statusColumn = 4;
  const postedAtColumn = 5;
  const categoryColumn = 6;
  const skuColumn = 7;
  const itemColumn = 8;
  const unitColumn = 9;
  const batchColumn = 10;
  const expiryColumn = 11;
  const qtyColumn = 12;
  const noteColumn = 13;

  Future<String> numberOf(String id) => context.database
      .customSelect("SELECT doc_number FROM consumptions WHERE id = '$id';")
      .getSingle()
      .then((row) => row.read<String>('doc_number'));

  setUp(() async {
    wallClock = DateTime.now().toUtc();
    postedAtUtc = wallClock.add(const Duration(minutes: 1));
    today = AppTimeZone.operationalDate(wallClock);

    context = TestContext.create(clock: () => wallClock);
    fixture = await buildConsumptionFixture(context, nowUtc: wallClock);

    consumptionId = await createConsumptionDraft(
      context,
      fixture,
      roomId: fixture.roomOne.id,
      nowUtc: wallClock,
      note: 'Pemakaian harian',
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: consumptionId,
      itemId: fixture.expiryItem.id,
      batchId: fixture.validBatch.id,
      qty: '2.375',
      nowUtc: wallClock,
      note: 'Tindakan pagi',
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: consumptionId,
      itemId: fixture.expiryItem.id,
      batchId: fixture.nearBatch.id,
      qty: '0.5',
      nowUtc: wallClock,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: consumptionId,
      itemId: fixture.plainItem.id,
      qty: '1.25',
      nowUtc: wallClock,
    );
    await context
        .postConsumption(clock: () => postedAtUtc)
        .call(actorUserId: fixture.nurse.id, consumptionId: consumptionId);

    // The colleague: same branch, same room, same day. Only ownership separates the
    // two documents.
    colleagueId = await createConsumptionDraft(
      context,
      fixture,
      roomId: fixture.roomOne.id,
      nowUtc: wallClock,
      actorUserId: fixture.otherNurse.id,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: colleagueId,
      itemId: fixture.otherExpiryItem.id,
      batchId: fixture.otherItemBatch.id,
      qty: '1',
      nowUtc: wallClock,
      actorUserId: fixture.otherNurse.id,
    );
    await context
        .postConsumption(clock: () => postedAtUtc)
        .call(actorUserId: fixture.otherNurse.id, consumptionId: colleagueId);

    // Never posted — document intent with no stock effect.
    draftId = await createConsumptionDraft(
      context,
      fixture,
      roomId: fixture.roomOne.id,
      nowUtc: wallClock,
      note: 'Belum diposting',
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: draftId,
      itemId: fixture.otherPlainItem.id,
      qty: '2',
      nowUtc: wallClock,
    );

    docNumber = await numberOf(consumptionId);
    colleagueNumber = await numberOf(colleagueId);
    draftNumber = await numberOf(draftId);
  });

  tearDown(() => context.dispose());

  Future<ReportPreview> recap({
    MasterUser? actor,
    ReportScopeType? scopeType,
    String? branchId,
    String? roomLocationId,
    String? categoryId,
    Set<String> statuses = const <String>{},
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final who = actor ?? fixture.nurse;
    final isNurse = who.role == UserRole.perawat;
    return context
        .buildReportPreview(clock: () => postedAtUtc)
        .call(
          actorUserId: who.id,
          draft: ReportRequestDraft(
            reportType: ReportType.rekapPemakaian,
            scopeType:
                scopeType ??
                (isNurse ? ReportScopeType.room : ReportScopeType.branchAll),
            periodStart: periodStart ?? DateOnly.addDays(today, -1),
            periodEnd: periodEnd ?? DateOnly.addDays(today, 1),
            branchId: branchId,
            locationId: isNurse
                ? (roomLocationId ?? fixture.locationOne.id)
                : null,
            filter: ReportFilter(categoryId: categoryId, statuses: statuses),
          ),
        );
  }

  /// The row for one position, addressed the way the database identifies it.
  ReportDataRow rowFor(
    ReportDocument document, {
    required String sku,
    String? batch,
  }) => document.rows.firstWhere(
    (row) =>
        row.cells[skuColumn].text == sku &&
        row.cells[batchColumn].text == (batch ?? ReportLabels.notApplicable),
    orElse: () => throw StateError('Baris $sku/$batch tidak ada.'),
  );

  group('metadata dokumen', () {
    test('nomor, branch, ruangan, perawat dan status', () async {
      final document = (await recap()).document;
      final posted = document.rows
          .where((row) => row.cells[docNumberColumn].text == docNumber)
          .toList();

      expect(posted, hasLength(3));
      for (final row in posted) {
        expect(row.cells[branchColumn].text, fixture.branch.code);
        expect(row.cells[roomColumn].text, fixture.roomOne.name);
        expect(row.cells[nurseColumn].text, fixture.nurse.fullName);
        expect(row.cells[statusColumn].text, ConsumptionStatus.posted.label);
      }
    });

    test('posted_at berasal dari transisi, bukan dari jam laporan', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          sku: fixture.expiryItem.sku,
          batch: fixture.validBatch.batchNo,
        ).cells[postedAtColumn].text,
        AppDateTimeFormatter.dateTime(postedAtUtc),
      );
    });

    test('catatan baris tampil apa adanya', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          sku: fixture.expiryItem.sku,
          batch: fixture.validBatch.batchNo,
        ).cells[noteColumn].text,
        'Tindakan pagi',
      );
    });

    test('tidak ada kolom pasien di mana pun', () async {
      // Asserted rather than left to be noticed: this is the report where somebody
      // would most plausibly want one, and the application holds no clinical data.
      final document = (await recap()).document;
      final labels = document.columns
          .map((column) => column.label.toLowerCase())
          .toList();

      for (final forbidden in ['pasien', 'patient', 'diagnos', 'tindakan']) {
        expect(
          labels.any((label) => label.contains(forbidden)),
          isFalse,
          reason: 'kolom "$forbidden" tidak boleh ada',
        );
      }
      expect(labels, hasLength(14));
    });
  });

  group('kolom barang', () {
    test('SKU, nama, kategori, batch, expiry dan satuan', () async {
      final document = (await recap()).document;
      final batched = rowFor(
        document,
        sku: fixture.expiryItem.sku,
        batch: fixture.validBatch.batchNo,
      );
      final plain = rowFor(document, sku: fixture.plainItem.sku);

      expect(batched.cells[itemColumn].text, fixture.expiryItem.name);
      expect(batched.cells[categoryColumn].text, fixture.category.name);
      expect(batched.cells[unitColumn].text, fixture.expiryItem.unit);
      expect(
        batched.cells[expiryColumn].text,
        AppDateTimeFormatter.civilDate(fixture.validBatch.expiryDate),
      );

      // G-E2: an item without expiry is consumed without a batch, and the report has
      // to say so rather than invent one.
      expect(plain.cells[batchColumn].text, ReportLabels.notApplicable);
      expect(plain.cells[expiryColumn].text, ReportLabels.notApplicable);
      expect(plain.cells[unitColumn].text, fixture.plainItem.unit);
    });

    test('dua batch dari satu barang tetap dua baris', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          sku: fixture.expiryItem.sku,
          batch: fixture.validBatch.batchNo,
        ).cells[qtyColumn].text,
        '2.375',
      );
      expect(
        rowFor(
          document,
          sku: fixture.expiryItem.sku,
          batch: fixture.nearBatch.batchNo,
        ).cells[qtyColumn].text,
        '0.5',
      );
    });
  });

  group('kuantitas berasal dari ledger', () {
    test('setiap baris sama dengan movement-nya', () async {
      // Read straight from `stock_movements` and compared against the printed
      // column: the report may not be the only witness to its own number (G-L4).
      final movements = await context.database
          .customSelect(
            'SELECT item_id, batch_id, qty, from_location_id, to_location_id '
            "FROM stock_movements WHERE ref_doc_type = 'CONS' "
            "AND ref_doc_id = '$consumptionId';",
          )
          .get();
      expect(movements, hasLength(3));

      final byPosition = <String, Quantity>{};
      for (final row in movements) {
        // A consumption leaves a room and goes nowhere (G-E7's shape, applied here).
        expect(row.read<String?>('to_location_id'), isNull);
        expect(row.read<String?>('from_location_id'), fixture.locationOne.id);
        final key =
            '${row.read<String>('item_id')}|${row.read<String?>('batch_id') ?? ''}';
        byPosition[key] = Quantity.fromMilliUnits(row.read<int>('qty'));
      }

      final document = (await recap()).document;
      expect(
        rowFor(
          document,
          sku: fixture.expiryItem.sku,
          batch: fixture.validBatch.batchNo,
        ).cells[qtyColumn].text,
        byPosition['${fixture.expiryItem.id}|${fixture.validBatch.id}']!
            .format(),
      );
      expect(
        rowFor(document, sku: fixture.plainItem.sku).cells[qtyColumn].text,
        byPosition['${fixture.plainItem.id}|']!.format(),
      );
    });

    test('ledger dipakai apa adanya, bukan angka baris dokumen', () async {
      // The ledger is corrupted behind the application's back and the report has to
      // follow it. Deliberate raw SQL: an intentional-corruption test (§6), which no
      // official API can or should express.
      await context.database.customStatement(
        'UPDATE stock_movements SET qty = 4000 '
        "WHERE ref_doc_type = 'CONS' AND ref_doc_id = '$consumptionId' "
        "AND item_id = '${fixture.plainItem.id}';",
      );

      final document = (await recap()).document;

      expect(
        rowFor(document, sku: fixture.plainItem.sku).cells[qtyColumn].text,
        '4',
      );
    });

    test('stock_balances yang rusak tidak mengubah laporan', () async {
      // G-L4: the cache is not a source. Deliberate raw SQL: an intentional
      // corruption of a table reporting must never read (§6).
      await context.database.customStatement(
        'UPDATE stock_balances SET qty_on_hand = 999000;',
      );

      final document = (await recap()).document;

      expect(document.overallTotals['ampul'], Quantity.parse('2.875'));
      expect(document.overallTotals['box'], Quantity.parse('1.25'));
    });
  });

  group('draft tidak memiliki efek stok', () {
    test('baris draft tampil dengan qty nol', () async {
      final document = (await recap()).document;
      final draft = document.rows.singleWhere(
        (row) => row.cells[docNumberColumn].text == draftNumber,
      );

      expect(draft.cells[statusColumn].text, ConsumptionStatus.draft.label);
      expect(draft.cells[qtyColumn].text, '0');
      expect(draft.cells[postedAtColumn].text, ReportLabels.notApplicable);
    });

    test('draft tidak menulis movement apa pun', () async {
      final count = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM stock_movements '
            "WHERE ref_doc_type = 'CONS' AND ref_doc_id = '$draftId';",
          )
          .getSingle()
          .then((row) => row.read<int>('c'));

      expect(count, 0);
    });

    test('filter status posted menyembunyikan draft', () async {
      final document = (await recap(
        statuses: {ConsumptionStatus.posted.dbValue},
      )).document;

      expect(
        document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
        {docNumber},
      );
    });
  });

  group('total per satuan (§32)', () {
    test('ampul dan box tidak pernah dijumlahkan bersama', () async {
      final document = (await recap()).document;

      expect(document.overallTotals.units, ['ampul', 'box']);
      // 2.375 + 0.5, exactly — the fixed-point path, not a double.
      expect(document.overallTotals['ampul'], Quantity.parse('2.875'));
      expect(document.overallTotals['box'], Quantity.parse('1.25'));
    });

    test('subtotal satu kategori sama dengan total keseluruhan', () async {
      // The nurse's *posted* document holds only `Obat` positions, so this is the
      // case where the two must agree exactly. The draft is filtered out because it
      // sits in the other category and would add a second, all-zero group.
      final document = (await recap(
        statuses: {ConsumptionStatus.posted.dbValue},
      )).document;

      expect(document.groups, hasLength(1));
      expect(document.groups.single.categoryName, fixture.category.name);
      expect(document.groups.single.subtotals, document.overallTotals);
    });

    test('dua kategori memberi dua subtotal yang tidak bercampur', () async {
      final document = (await recap(
        actor: fixture.branchHead,
        statuses: {ConsumptionStatus.posted.dbValue},
      )).document;
      final byCategory = {
        for (final group in document.groups) group.categoryName: group,
      };

      expect(
        byCategory[fixture.category.name]!.subtotals['ampul'],
        Quantity.parse('2.875'),
      );
      expect(
        byCategory[fixture.otherCategory.name]!.subtotals['roll'],
        Quantity.parse('1'),
      );
      expect(
        byCategory[fixture.otherCategory.name]!.subtotals['ampul'],
        isNull,
      );
    });
  });

  group('kepemilikan dokumen (G-L1)', () {
    test('perawat melihat dokumennya sendiri', () async {
      final document = (await recap()).document;

      expect(document.rows.map((row) => row.cells[nurseColumn].text).toSet(), {
        fixture.nurse.fullName,
      });
    });

    test('dokumen perawat lain di ruangan yang sama tidak terlihat', () async {
      // Same branch, same room, same day: ownership is the only rule that can hide
      // it, so this is where a leak would show.
      final document = (await recap()).document;

      expect(
        document.rows.map((row) => row.cells[docNumberColumn].text),
        isNot(contains(colleagueNumber)),
      );
    });

    test(
      'perawat kedua melihat dokumennya sendiri dan bukan yang lain',
      () async {
        final document = (await recap(actor: fixture.otherNurse)).document;

        expect(
          document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
          {colleagueNumber},
        );
      },
    );

    test('cakupan ruangan lain menghasilkan laporan kosong', () async {
      final document = (await recap(
        roomLocationId: fixture.locationTwo.id,
      )).document;

      expect(document.isEmpty, isTrue);
    });
  });

  group('cakupan peran lain', () {
    test('kepala cabang melihat seluruh dokumen cabangnya', () async {
      final document = (await recap(actor: fixture.branchHead)).document;

      expect(document.header.branchLabel, fixture.branch.name);
      expect(
        document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
        {docNumber, colleagueNumber, draftNumber},
      );
    });

    test('kepala cabang lain tidak melihat dokumen ini', () async {
      final document = (await recap(actor: fixture.otherBranchHead)).document;

      expect(document.isEmpty, isTrue);
    });

    test('perawat cabang lain tidak melihat dokumen ini', () async {
      final document = (await recap(
        actor: fixture.otherBranchNurse,
        roomLocationId: fixture.otherBranchRoomLocation.id,
      )).document;

      expect(document.isEmpty, isTrue);
    });

    test('perawat tidak dapat menunjuk ruangan cabang lain', () async {
      await expectLater(
        recap(roomLocationId: fixture.otherBranchRoomLocation.id),
        throwsA(isA<AppFailure>()),
      );
    });

    test('warehouse lintas cabang melihat dokumen cabang', () async {
      final document = (await recap(
        actor: fixture.warehouseUser,
        scopeType: ReportScopeType.crossBranch,
      )).document;

      expect(
        document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
        {docNumber, colleagueNumber, draftNumber},
      );
    });
  });

  group('filter dan periode', () {
    test('kategori menyaring baris dan total sekaligus', () async {
      final document = (await recap(
        actor: fixture.branchHead,
        categoryId: fixture.otherCategory.id,
        statuses: {ConsumptionStatus.posted.dbValue},
      )).document;

      expect(document.overallTotals.units, ['roll']);
      expect(document.overallTotals['roll'], Quantity.parse('1'));
    });

    test('periode sebelum dokumen menghasilkan laporan kosong', () async {
      final document = (await recap(
        periodStart: DateOnly.addDays(today, -20),
        periodEnd: DateOnly.addDays(today, -10),
      )).document;

      expect(document.isEmpty, isTrue);
    });

    test('batas periode GMT+8 memasukkan hari ini seutuhnya', () async {
      // Operational midnight, not UTC midnight: a document created at 07:00 GMT+8 is
      // 23:00 UTC *yesterday*, and a UTC window would lose it.
      final document = (await recap(
        periodStart: today,
        periodEnd: today,
      )).document;

      expect(document.rowCount, 4);
      expect(
        document.header.period.startUtc,
        AppTimeZone.startOfOperationalDayUtc(today),
      );
      expect(
        document.header.period.endExclusiveUtc,
        AppTimeZone.startOfOperationalDayUtc(DateOnly.addDays(today, 1)),
      );
    });
  });

  group('determinisme dan pemulihan historis', () {
    test(
      'dua kali menjalankan laporan menghasilkan urutan yang sama',
      () async {
        final first = (await recap()).document;
        final second = (await recap()).document;

        expect(
          first.rows.map((row) => row.sortKey),
          second.rows.map((row) => row.sortKey),
        );
      },
    );

    test('menonaktifkan barang dan ruangan tidak menghapus baris', () async {
      // §51: a posted consumption is permanent, and tidying master data afterwards
      // may not make it unreadable. An `active = 1` join anywhere in this path
      // would drop these rows.
      await context.deactivate('items', fixture.plainItem.id);
      await context.deactivate('rooms', fixture.roomOne.id);
      await context.archive('item_batches', fixture.nearBatch.id);

      final document = (await recap()).document;

      expect(document.rowCount, 4);
      expect(
        rowFor(document, sku: fixture.plainItem.sku).cells[itemColumn].text,
        fixture.plainItem.name,
      );
      expect(document.rows.first.cells[roomColumn].text, fixture.roomOne.name);
      expect(document.overallTotals['ampul'], Quantity.parse('2.875'));
    });

    test('menonaktifkan perawat tidak menghapus namanya dari laporan', () async {
      await context.deactivate('users', fixture.nurse.id);

      // Read by the branch head: an inactive account may not run a report at all,
      // which is a different rule and not the one under test.
      final document = (await recap(actor: fixture.branchHead)).document;

      expect(
        document.rows
            .where((row) => row.cells[docNumberColumn].text == docNumber)
            .map((row) => row.cells[nurseColumn].text)
            .toSet(),
        {fixture.nurse.fullName},
      );
    });
  });
}
