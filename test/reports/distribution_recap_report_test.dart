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

/// *Rekap Distribusi* (§28) against documents driven through the **real** workflow:
/// `draft → posted`, with the posting service writing the ledger.
///
/// ### The shape of the fixture, and why each part of it is there
///
/// One branch store feeds two rooms out of one document, because that is the state
/// G-T3 permits and the one this report is most likely to get wrong: an aggregation
/// per item per document would answer *"how much gauze left the store"* while
/// destroying the only question a branch head runs the report to ask — *which room
/// got it*.
///
/// * `roomOne` receives `simpleItem` (no batch) and `batchItem` split across **two
///   batches** by FEFO, so one requested quantity becomes two ledger rows.
/// * `roomTwo` receives `simpleItem` again — the same item, the same document, a
///   different destination — and `tieItem` from the batch FEFO would *not* have
///   chosen, with an override reason attached.
///
/// A second document is left in `draft`, which is how "document intent is not a
/// stock effect" is asserted: it has lines, it has quantities, and the ledger has
/// never heard of it.
///
/// ### Clocks
///
/// `distributions.created_at` comes from the table's own `clientDefault` (the wall
/// clock), so the report window has to cover today. `posted_at` is stamped from an
/// injected clock a minute ahead, which keeps `created_at < posted_at` without
/// depending on how fast the suite runs (T-7).
void main() {
  late TestContext context;
  late DistributionFixture fixture;
  late DateTime wallClock;
  late DateTime postedAtUtc;
  late DateTime today;
  late String distributionId;
  late String draftId;
  late String docNumber;
  late String draftNumber;

  /// Column indexes of [DistributionRecapReportBuilder.columns], named once.
  const docNumberColumn = 0;
  const branchColumn = 1;
  const statusColumn = 2;
  const distributedByColumn = 3;
  const postedAtColumn = 4;
  const sourceColumn = 5;
  const roomColumn = 6;
  const categoryColumn = 7;
  const skuColumn = 8;
  const itemColumn = 9;
  const unitColumn = 10;
  const batchColumn = 11;
  const expiryColumn = 12;
  const qtyColumn = 13;
  const fefoColumn = 14;

  /// How [ReportBuilderSupport.locationLabel] prints a branch store: the branch
  /// code disambiguates a name that is only unique inside its own branch.
  String branchStoreLabel() =>
      '${fixture.branch.code} \u00b7 ${fixture.branchStore.name}';

  Future<String> numberOf(String id) => context.database
      .customSelect("SELECT doc_number FROM distributions WHERE id = '$id';")
      .getSingle()
      .then((row) => row.read<String>('doc_number'));

  setUp(() async {
    wallClock = DateTime.now().toUtc();
    postedAtUtc = wallClock.add(const Duration(minutes: 1));
    today = AppTimeZone.operationalDate(wallClock);

    context = TestContext.create(clock: () => wallClock);
    fixture = await buildDistributionFixture(context, nowUtc: wallClock);

    distributionId = await createDistributionDraft(
      context,
      fixture,
      nowUtc: wallClock,
      note: 'Distribusi rutin',
    );

    // The override goes on **first**, and the order is the whole point: `B-OLD`
    // expires first and is still untouched here, so hand-picking `A-NEW` is a real
    // FEFO violation and the guard records a reason for it. Added after room one had
    // already emptied `B-OLD` it would be the only batch left, therefore compliant,
    // and the column under test would be legitimately blank.
    await addManualDistributionAllocation(
      context,
      fixture,
      distributionId: distributionId,
      roomId: fixture.roomTwo.id,
      itemId: fixture.batchItem.id,
      batchId: fixture.newBatch.id,
      qty: '1',
      nowUtc: wallClock,
      fefoOverrideReason: 'Diminta ruangan, kemasan sudah dibuka',
    );

    // Room one: an item without expiry, then a batch-tracked item whose requested
    // quantity FEFO has to split across `B-OLD` (2) and `A-NEW` (the remainder).
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

    // Room two on the same document: the same simple item — the pair that must not
    // be folded together — plus a third unit, so the totals have three to keep apart.
    await addDistributionItem(
      context,
      fixture,
      distributionId: distributionId,
      roomId: fixture.roomTwo.id,
      itemId: fixture.simpleItem.id,
      qty: '1.5',
      nowUtc: wallClock,
    );
    await addDistributionItem(
      context,
      fixture,
      distributionId: distributionId,
      roomId: fixture.roomTwo.id,
      itemId: fixture.tieItem.id,
      qty: '1',
      nowUtc: wallClock,
    );

    await context
        .postDistribution(clock: () => postedAtUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          distributionId: distributionId,
        );

    // A second document that is never posted — document intent with no stock effect.
    draftId = await createDistributionDraft(
      context,
      fixture,
      nowUtc: wallClock,
      note: 'Belum diposting',
    );
    await addDistributionItem(
      context,
      fixture,
      distributionId: draftId,
      roomId: fixture.roomThree.id,
      itemId: fixture.simpleItem.id,
      qty: '2',
      nowUtc: wallClock,
    );

    docNumber = await numberOf(distributionId);
    draftNumber = await numberOf(draftId);
  });

  tearDown(() => context.dispose());

  Future<ReportPreview> recap({
    MasterUser? actor,
    ReportScopeType? scopeType,
    String? branchId,
    String? categoryId,
    Set<String> statuses = const <String>{},
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final who = actor ?? fixture.branchHead;
    return context
        .buildReportPreview(clock: () => postedAtUtc)
        .call(
          actorUserId: who.id,
          draft: ReportRequestDraft(
            reportType: ReportType.rekapDistribusi,
            scopeType: scopeType ?? ReportScopeType.branchAll,
            periodStart: periodStart ?? DateOnly.addDays(today, -1),
            periodEnd: periodEnd ?? DateOnly.addDays(today, 1),
            branchId: branchId,
            filter: ReportFilter(categoryId: categoryId, statuses: statuses),
          ),
        );
  }

  /// The row for one position, addressed the way the ledger identifies it: the room
  /// is part of the key, because the item alone is not unique on this document.
  ReportDataRow rowFor(
    ReportDocument document, {
    required String room,
    required String sku,
    String? batch,
  }) => document.rows.firstWhere(
    (row) =>
        row.cells[roomColumn].text == room &&
        row.cells[skuColumn].text == sku &&
        row.cells[batchColumn].text == (batch ?? ReportLabels.notApplicable),
    orElse: () => throw StateError('Baris $room/$sku/$batch tidak ada.'),
  );

  group('metadata dokumen', () {
    test('nomor, branch, status dan pelaku', () async {
      final document = (await recap()).document;
      final posted = document.rows
          .where((row) => row.cells[docNumberColumn].text == docNumber)
          .toList();

      expect(posted, hasLength(6));
      for (final row in posted) {
        expect(row.cells[branchColumn].text, fixture.branch.code);
        expect(row.cells[statusColumn].text, DistributionStatus.posted.label);
        expect(
          row.cells[distributedByColumn].text,
          fixture.branchHead.fullName,
        );
      }
    });

    test('posted_at berasal dari transisi, bukan dari jam laporan', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          room: fixture.roomOne.name,
          sku: fixture.simpleItem.sku,
        ).cells[postedAtColumn].text,
        AppDateTimeFormatter.dateTime(postedAtUtc),
      );
    });

    test('gudang sumber dibaca dari ledger, bukan dari header', () async {
      // `distributions` names only a branch; the movement names the shelf. On a
      // branch that ever grows a second store, this column is the only one that can
      // still be right.
      final document = (await recap()).document;
      final fromLocationIds = await context.database
          .customSelect(
            'SELECT DISTINCT from_location_id FROM stock_movements '
            "WHERE ref_doc_type = 'DIST' AND ref_doc_id = '$distributionId';",
          )
          .get()
          .then(
            (rows) => rows.map((row) => row.read<String>('from_location_id')),
          );

      expect(fromLocationIds, {fixture.branchStore.id});
      for (final row in document.rows.where(
        (row) => row.cells[docNumberColumn].text == docNumber,
      )) {
        expect(row.cells[sourceColumn].text, branchStoreLabel());
      }
    });
  });

  group('satu baris per ruangan tujuan (G-T3)', () {
    test('barang yang sama ke dua ruangan tidak digabung', () async {
      final document = (await recap()).document;
      final one = rowFor(
        document,
        room: fixture.roomOne.name,
        sku: fixture.simpleItem.sku,
      );
      final two = rowFor(
        document,
        room: fixture.roomTwo.name,
        sku: fixture.simpleItem.sku,
      );

      expect(one.cells[qtyColumn].text, '2.5');
      expect(two.cells[qtyColumn].text, '1.5');
      expect(one.cells[docNumberColumn].text, two.cells[docNumberColumn].text);
    });

    test('ringkasan menghitung ruangan tujuan yang berbeda', () async {
      final document = (await recap()).document;
      final rooms = document.sections.single.metrics.firstWhere(
        (metric) => metric.label == 'Ruangan tujuan',
      );

      // Room one and room two from the posted document, room three from the draft.
      expect(rooms.value, '3');
    });

    test('satu permintaan terpecah FEFO menjadi dua baris batch', () async {
      final document = (await recap()).document;
      final old = rowFor(
        document,
        room: fixture.roomOne.name,
        sku: fixture.batchItem.sku,
        batch: fixture.oldBatch.batchNo,
      );
      final fresh = rowFor(
        document,
        room: fixture.roomOne.name,
        sku: fixture.batchItem.sku,
        batch: fixture.newBatch.batchNo,
      );

      // `B-OLD` expires first and holds exactly 2, so FEFO empties it and takes the
      // remaining 1 from `A-NEW`.
      expect(old.cells[qtyColumn].text, '2');
      expect(fresh.cells[qtyColumn].text, '1');
      expect(
        old.cells[expiryColumn].text,
        AppDateTimeFormatter.civilDate(fixture.oldBatch.expiryDate),
      );
    });
  });

  group('kuantitas berasal dari ledger', () {
    test('setiap baris sama dengan movement-nya', () async {
      // Read straight from `stock_movements` and compared against the printed
      // column: the report may not be the only witness to its own number (G-L4).
      final movements = await context.database
          .customSelect(
            'SELECT item_id, batch_id, to_location_id, qty FROM stock_movements '
            "WHERE ref_doc_type = 'DIST' AND ref_doc_id = '$distributionId';",
          )
          .get();
      expect(movements, hasLength(6));

      final byPosition = <String, Quantity>{};
      for (final row in movements) {
        final key =
            '${row.read<String>('to_location_id')}|${row.read<String>('item_id')}'
            '|${row.read<String?>('batch_id') ?? ''}';
        byPosition[key] =
            (byPosition[key] ?? Quantity.zero()) +
            Quantity.fromMilliUnits(row.read<int>('qty'));
      }

      final document = (await recap()).document;
      String key(
        MasterLocation location,
        MasterItem item,
        MasterBatch? batch,
      ) => '${location.id}|${item.id}|${batch?.id ?? ''}';

      expect(
        rowFor(
          document,
          room: fixture.roomOne.name,
          sku: fixture.simpleItem.sku,
        ).cells[qtyColumn].text,
        byPosition[key(fixture.locationOne, fixture.simpleItem, null)]!
            .format(),
      );
      expect(
        rowFor(
          document,
          room: fixture.roomTwo.name,
          sku: fixture.tieItem.sku,
          batch: fixture.tieBatchA.batchNo,
        ).cells[qtyColumn].text,
        byPosition[key(
              fixture.locationTwo,
              fixture.tieItem,
              fixture.tieBatchA,
            )]!
            .format(),
      );
    });

    test('ledger dipakai apa adanya, bukan angka baris dokumen', () async {
      // The ledger is corrupted behind the application's back and the report has to
      // follow it. Deliberate raw SQL: an intentional-corruption test (§6), which no
      // official API can or should express.
      await context.database.customStatement(
        'UPDATE stock_movements SET qty = 9000 '
        "WHERE ref_doc_type = 'DIST' AND ref_doc_id = '$distributionId' "
        "AND item_id = '${fixture.simpleItem.id}' "
        "AND to_location_id = '${fixture.locationOne.id}';",
      );

      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          room: fixture.roomOne.name,
          sku: fixture.simpleItem.sku,
        ).cells[qtyColumn].text,
        '9',
      );
    });

    test('stock_balances yang rusak tidak mengubah laporan', () async {
      // G-L4: the cache is not a source. Deliberate raw SQL: an intentional
      // corruption of a table reporting must never read (§6).
      await context.database.customStatement(
        'UPDATE stock_balances SET qty_on_hand = 123456;',
      );

      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          room: fixture.roomOne.name,
          sku: fixture.simpleItem.sku,
        ).cells[qtyColumn].text,
        '2.5',
      );
      expect(document.overallTotals['box'], Quantity.parse('4'));
    });
  });

  group('draft tidak memiliki efek stok', () {
    test('baris draft tampil dengan qty nol', () async {
      final document = (await recap()).document;
      final draft = document.rows.singleWhere(
        (row) => row.cells[docNumberColumn].text == draftNumber,
      );

      expect(draft.cells[statusColumn].text, DistributionStatus.draft.label);
      expect(draft.cells[qtyColumn].text, '0');
      expect(draft.cells[postedAtColumn].text, ReportLabels.notApplicable);
    });

    test('draft tidak menulis movement apa pun', () async {
      final count = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM stock_movements '
            "WHERE ref_doc_type = 'DIST' AND ref_doc_id = '$draftId';",
          )
          .getSingle()
          .then((row) => row.read<int>('c'));

      expect(count, 0);
    });

    test('draft tidak menambah total satuan mana pun', () async {
      final document = (await recap()).document;

      // 2.5 + 1.5 posted; the draft's 2 boxes are intent and must not appear.
      expect(document.overallTotals['box'], Quantity.parse('4'));
    });

    test('filter status posted menyembunyikan draft', () async {
      final document = (await recap(
        statuses: {DistributionStatus.posted.dbValue},
      )).document;

      expect(document.rowCount, 6);
      expect(
        document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
        {docNumber},
      );
    });
  });

  group('FEFO override', () {
    test('alasan override tampil pada baris yang menggunakannya', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          room: fixture.roomTwo.name,
          sku: fixture.batchItem.sku,
          batch: fixture.newBatch.batchNo,
        ).cells[fefoColumn].text,
        'Diminta ruangan, kemasan sudah dibuka',
      );
    });

    test('baris FEFO biasa tidak mengarang alasan', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          room: fixture.roomOne.name,
          sku: fixture.batchItem.sku,
          batch: fixture.oldBatch.batchNo,
        ).cells[fefoColumn].text,
        ReportLabels.notApplicable,
      );
    });
  });

  group('total per satuan (§32)', () {
    test('box, ampul dan roll tidak pernah dijumlahkan bersama', () async {
      final document = (await recap()).document;

      expect(document.overallTotals.units, ['ampul', 'box', 'roll']);
      expect(document.overallTotals['box'], Quantity.parse('4'));
      expect(document.overallTotals['ampul'], Quantity.parse('4'));
      expect(document.overallTotals['roll'], Quantity.parse('1'));
    });

    test('subtotal kategori dijumlahkan menjadi total keseluruhan', () async {
      final document = (await recap()).document;
      final byCategory = {
        for (final group in document.groups) group.categoryName: group,
      };

      expect(
        byCategory.keys,
        containsAll([fixture.category.name, fixture.otherCategory.name]),
      );
      expect(
        byCategory[fixture.category.name]!.subtotals['box'],
        Quantity.parse('4'),
      );
      expect(
        byCategory[fixture.category.name]!.subtotals['roll'],
        Quantity.parse('1'),
      );
      expect(
        byCategory[fixture.otherCategory.name]!.subtotals['ampul'],
        Quantity.parse('4'),
      );
      expect(byCategory[fixture.otherCategory.name]!.subtotals['box'], isNull);
    });

    test('satuan tiap baris ikut baris, bukan laporan', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          room: fixture.roomOne.name,
          sku: fixture.batchItem.sku,
          batch: fixture.oldBatch.batchNo,
        ).cells[unitColumn].text,
        fixture.batchItem.unit,
      );
      expect(
        rowFor(
          document,
          room: fixture.roomTwo.name,
          sku: fixture.tieItem.sku,
          batch: fixture.tieBatchA.batchNo,
        ).cells[unitColumn].text,
        fixture.tieItem.unit,
      );
    });
  });

  group('filter dan periode', () {
    test('kategori menyaring baris dan total sekaligus', () async {
      final document = (await recap(
        categoryId: fixture.otherCategory.id,
      )).document;

      expect(document.rowCount, 3);
      expect(document.overallTotals.units, ['ampul']);
      expect(document.overallTotals['ampul'], Quantity.parse('4'));
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

      expect(document.rowCount, 7);
      expect(
        document.header.period.startUtc,
        AppTimeZone.startOfOperationalDayUtc(today),
      );
    });
  });

  group('cakupan (G-L1)', () {
    test('kepala cabang melihat distribusi cabangnya', () async {
      final document = (await recap()).document;

      expect(document.header.branchLabel, fixture.branch.name);
      expect(document.rowCount, 7);
    });

    test('kepala cabang lain tidak melihat dokumen ini', () async {
      final document = (await recap(actor: fixture.otherBranchHead)).document;

      expect(document.isEmpty, isTrue);
    });

    test('perawat tidak boleh menjalankan rekap distribusi', () async {
      // §3.1 gives a nurse no view of a distribution at all — not a narrowed one.
      await expectLater(
        recap(actor: fixture.nurse, scopeType: ReportScopeType.room),
        throwsA(isA<ReportAccessDeniedFailure>()),
      );
    });

    test('warehouse lintas cabang melihat dokumen cabang', () async {
      final document = (await recap(
        actor: fixture.warehouseUser,
        scopeType: ReportScopeType.crossBranch,
      )).document;

      expect(document.rowCount, 7);
    });

    test('warehouse dapat mempersempit ke satu cabang', () async {
      final other = (await recap(
        actor: fixture.warehouseUser,
        scopeType: ReportScopeType.branchAll,
        branchId: fixture.otherBranch.id,
      )).document;

      expect(other.isEmpty, isTrue);
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

    test(
      'menonaktifkan barang, batch, ruangan dan pengguna tidak menghapus baris',
      () async {
        // §51: a posted distribution is permanent, and tidying master data
        // afterwards may not make it unreadable. An `active = 1` join anywhere in
        // this path would drop these rows.
        await context.deactivate('items', fixture.simpleItem.id);
        // `item_batches` and `item_categories` carry no `is_active`; archiving is the
        // soft-removal they do have (G-A5).
        await context.archive('item_batches', fixture.tieBatchA.id);
        await context.deactivate('rooms', fixture.roomTwo.id);
        await context.deactivate('users', fixture.branchHead.id);

        // Read by the Super Admin, because the branch head who distributed is now
        // one of the deactivated rows and an inactive account may not run a report
        // at all — a different rule, and not the one under test here.
        final document = (await recap(
          actor: fixture.superAdmin,
          branchId: fixture.branch.id,
        )).document;

        expect(document.rowCount, 7);
        expect(
          rowFor(
            document,
            room: fixture.roomTwo.name,
            sku: fixture.tieItem.sku,
            batch: fixture.tieBatchA.batchNo,
          ).cells[itemColumn].text,
          fixture.tieItem.name,
        );
        expect(document.overallTotals['box'], Quantity.parse('4'));
      },
    );

    test('mengarsipkan lokasi tetap menampilkan gudang sumber', () async {
      await context.archive('stock_locations', fixture.branchStore.id);

      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          room: fixture.roomOne.name,
          sku: fixture.simpleItem.sku,
        ).cells[sourceColumn].text,
        branchStoreLabel(),
      );
    });

    test('kategori barang tetap terbaca setelah diarsipkan', () async {
      await context.archive('item_categories', fixture.otherCategory.id);

      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          room: fixture.roomOne.name,
          sku: fixture.batchItem.sku,
          batch: fixture.newBatch.batchNo,
        ).cells[categoryColumn].text,
        fixture.otherCategory.name,
      );
    });
  });
}
