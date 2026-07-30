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

/// *Rekap Pemusnahan* (§30) against documents driven through the **real** workflow:
/// `draft → posted`, with the posting service writing the ledger.
///
/// ### Two documents, because a disposal has no branch of its own
///
/// `disposals` carries a source location and no branch column, and that is not an
/// oversight: stock destroyed at Warehouse Pusat belongs to no branch at all. So the
/// fixture posts one document from the **warehouse** and one from a **room**, and
/// the report has to place the first outside every branch heading and the second
/// inside one — from the location, never from the document.
///
/// * The warehouse document destroys two batches with different amounts of overdue:
///   `expiredBatch` (3 days past) and `staleBatch` (30 days past). One number cannot
///   satisfy both, which is what makes *Days Expired* worth asserting.
/// * The room document destroys a decimal quantity of `expiredBatch` out of room 1,
///   under a different reason and with its own line note.
/// * A third document is left in `draft`, which is how "document intent is not a
///   stock effect" is asserted: it has a line, it has a quantity, and the ledger has
///   never heard of it.
///
/// ### Clocks
///
/// `disposals.created_at` comes from the table's own `clientDefault` (the wall
/// clock), so the report window has to cover today. `posted_at` is stamped from an
/// injected clock a minute ahead, which keeps `created_at < posted_at` without
/// depending on how fast the suite runs (T-7).
void main() {
  late TestContext context;
  late DisposalFixture fixture;
  late DateTime wallClock;
  late DateTime postedAtUtc;
  late DateTime today;
  late String warehouseDisposalId;
  late String roomDisposalId;
  late String draftId;
  late String warehouseNumber;
  late String roomNumber;
  late String draftNumber;

  /// Column indexes of [DisposalRecapReportBuilder.columns], named once.
  const docNumberColumn = 0;
  const sourceColumn = 1;
  const branchColumn = 2;
  const createdByColumn = 3;
  const postedByColumn = 4;
  const postedAtColumn = 5;
  const reasonColumn = 6;
  const categoryColumn = 7;
  const skuColumn = 8;
  const itemColumn = 9;
  const unitColumn = 10;
  const batchColumn = 11;
  const expiryColumn = 12;
  const daysExpiredColumn = 13;
  const qtyColumn = 14;
  const noteColumn = 15;

  Future<String> numberOf(String id) => context.database
      .customSelect("SELECT doc_number FROM disposals WHERE id = '$id';")
      .getSingle()
      .then((row) => row.read<String>('doc_number'));

  setUp(() async {
    wallClock = DateTime.now().toUtc();
    postedAtUtc = wallClock.add(const Duration(minutes: 1));
    today = AppTimeZone.operationalDate(wallClock);

    context = TestContext.create(clock: () => wallClock);
    fixture = await buildDisposalFixture(context, nowUtc: wallClock);

    // Warehouse Pusat: two batches, two different amounts of overdue.
    warehouseDisposalId = await createDisposalDraft(
      context,
      fixture,
      sourceLocationId: fixture.warehouse.id,
      nowUtc: wallClock,
      reason: 'Kedaluwarsa gudang pusat',
    );
    await addDisposalPosition(
      context,
      fixture,
      disposalId: warehouseDisposalId,
      itemId: fixture.expiryItem.id,
      batchId: fixture.expiredBatch.id,
      qty: '2.375',
      nowUtc: wallClock,
      note: 'Segel rusak',
    );
    await addDisposalPosition(
      context,
      fixture,
      disposalId: warehouseDisposalId,
      itemId: fixture.expiryItem.id,
      batchId: fixture.staleBatch.id,
      qty: '1.25',
      nowUtc: wallClock,
    );
    await context
        .postDisposal(clock: () => postedAtUtc)
        .call(
          actorUserId: fixture.warehouseUser.id,
          disposalId: warehouseDisposalId,
        );

    // Room 1 of the branch: the same batch, destroyed from a shelf that *does*
    // belong to a branch.
    roomDisposalId = await createDisposalDraft(
      context,
      fixture,
      sourceLocationId: fixture.locationOne.id,
      nowUtc: wallClock,
      actorUserId: fixture.branchHead.id,
      reason: 'Kedaluwarsa ruangan',
    );
    await addDisposalPosition(
      context,
      fixture,
      disposalId: roomDisposalId,
      itemId: fixture.expiryItem.id,
      batchId: fixture.expiredBatch.id,
      qty: '1.5',
      nowUtc: wallClock,
      actorUserId: fixture.branchHead.id,
      note: 'Sisa troli',
    );
    await context
        .postDisposal(clock: () => postedAtUtc)
        .call(actorUserId: fixture.branchHead.id, disposalId: roomDisposalId);

    // Never posted — document intent with no stock effect.
    draftId = await createDisposalDraft(
      context,
      fixture,
      sourceLocationId: fixture.branchStore.id,
      nowUtc: wallClock,
      actorUserId: fixture.branchHead.id,
      reason: 'Menunggu berita acara',
    );
    await addDisposalPosition(
      context,
      fixture,
      disposalId: draftId,
      itemId: fixture.expiryItem.id,
      batchId: fixture.expiredBatch.id,
      qty: '2',
      nowUtc: wallClock,
      actorUserId: fixture.branchHead.id,
    );

    warehouseNumber = await numberOf(warehouseDisposalId);
    roomNumber = await numberOf(roomDisposalId);
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
    final who = actor ?? fixture.superAdmin;
    return context
        .buildReportPreview(clock: () => postedAtUtc)
        .call(
          actorUserId: who.id,
          draft: ReportRequestDraft(
            reportType: ReportType.rekapPemusnahan,
            scopeType: scopeType ?? ReportScopeType.allLocations,
            periodStart: periodStart ?? DateOnly.addDays(today, -1),
            periodEnd: periodEnd ?? DateOnly.addDays(today, 1),
            branchId: branchId,
            filter: ReportFilter(categoryId: categoryId, statuses: statuses),
          ),
        );
  }

  /// The row for one position, addressed the way the database identifies it: the
  /// document number is part of the key, because one batch is destroyed twice.
  ReportDataRow rowFor(
    ReportDocument document, {
    required String docNumber,
    required String batch,
  }) => document.rows.firstWhere(
    (row) =>
        row.cells[docNumberColumn].text == docNumber &&
        row.cells[batchColumn].text == batch,
    orElse: () => throw StateError('Baris $docNumber/$batch tidak ada.'),
  );

  group('metadata dokumen', () {
    test('nomor, pelaku pembuat dan pelaku posting', () async {
      final document = (await recap()).document;
      final row = rowFor(
        document,
        docNumber: warehouseNumber,
        batch: fixture.expiredBatch.batchNo,
      );

      expect(row.cells[createdByColumn].text, fixture.warehouseUser.fullName);
      expect(row.cells[postedByColumn].text, fixture.warehouseUser.fullName);
      expect(
        row.cells[postedAtColumn].text,
        AppDateTimeFormatter.dateTime(postedAtUtc),
      );
    });

    test('alasan dokumen dan catatan baris adalah kolom berbeda', () async {
      final document = (await recap()).document;
      final withNote = rowFor(
        document,
        docNumber: warehouseNumber,
        batch: fixture.expiredBatch.batchNo,
      );
      final withoutNote = rowFor(
        document,
        docNumber: warehouseNumber,
        batch: fixture.staleBatch.batchNo,
      );

      expect(withNote.cells[reasonColumn].text, 'Kedaluwarsa gudang pusat');
      expect(withNote.cells[noteColumn].text, 'Segel rusak');
      // The header reason is shared; the line note is not invented for a line that
      // has none.
      expect(withoutNote.cells[reasonColumn].text, 'Kedaluwarsa gudang pusat');
      expect(withoutNote.cells[noteColumn].text, isEmpty);
    });

    test('status posted tercermin pada kedua dokumen', () async {
      final document = (await recap(
        statuses: {DisposalStatus.posted.dbValue},
      )).document;

      expect(
        document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
        {warehouseNumber, roomNumber},
      );
    });
  });

  group('sumber dan cabang berasal dari lokasi', () {
    test(
      'pemusnahan gudang pusat tidak berada di bawah cabang mana pun',
      () async {
        // `stock_locations` CHECKs that a warehouse has no branch, so forcing this row
        // under a branch heading would be a fabrication.
        final document = (await recap()).document;
        final row = rowFor(
          document,
          docNumber: warehouseNumber,
          batch: fixture.expiredBatch.batchNo,
        );

        expect(row.cells[sourceColumn].text, fixture.warehouse.name);
        expect(row.cells[branchColumn].text, ReportLabels.notApplicable);
      },
    );

    test('pemusnahan ruangan membawa cabang ruangan itu', () async {
      final document = (await recap()).document;
      final row = rowFor(
        document,
        docNumber: roomNumber,
        batch: fixture.expiredBatch.batchNo,
      );

      expect(
        row.cells[sourceColumn].text,
        '${fixture.branch.code} · ${fixture.locationOne.name}',
      );
      expect(row.cells[branchColumn].text, fixture.branch.code);
    });

    test('tidak ada kolom tujuan, karena tidak ada tujuan', () async {
      // A `disposal` movement carries a source and no destination (G-E7); a column
      // for one would have nothing true to put in it.
      final document = (await recap()).document;
      final labels = document.columns.map((column) => column.label).toList();

      expect(labels.any((label) => label.contains('Tujuan')), isFalse);
      expect(labels.any((label) => label.contains('Destination')), isFalse);

      final movements = await context.database
          .customSelect(
            'SELECT from_location_id, to_location_id FROM stock_movements '
            "WHERE ref_doc_type = 'DSP' AND ref_doc_id = '$roomDisposalId';",
          )
          .get();
      expect(movements, hasLength(1));
      expect(movements.single.read<String?>('to_location_id'), isNull);
      expect(
        movements.single.read<String?>('from_location_id'),
        fixture.locationOne.id,
      );
    });
  });

  group('days expired dihitung pada saat posting', () {
    test('tiga hari dan tiga puluh hari pada dokumen yang sama', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          docNumber: warehouseNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[daysExpiredColumn].text,
        '3',
      );
      expect(
        rowFor(
          document,
          docNumber: warehouseNumber,
          batch: fixture.staleBatch.batchNo,
        ).cells[daysExpiredColumn].text,
        '30',
      );
    });

    test('dihitung dalam hari operasional GMT+8', () async {
      // The arithmetic is on operational civil dates, not on a UTC subtraction: the
      // posting instant is converted to its GMT+8 day first, which is the day a
      // clinic would call it.
      final document = (await recap()).document;
      final expected = DateOnly.daysBetween(
        fixture.expiredBatch.expiryDate,
        AppTimeZone.operationalDate(postedAtUtc),
      );

      expect(expected, 3);
      expect(
        rowFor(
          document,
          docNumber: roomNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[daysExpiredColumn].text,
        '$expected',
      );
    });

    test('tanggal expiry batch tetap dicetak apa adanya', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          docNumber: warehouseNumber,
          batch: fixture.staleBatch.batchNo,
        ).cells[expiryColumn].text,
        AppDateTimeFormatter.civilDate(fixture.staleBatch.expiryDate),
      );
    });

    test(
      'draft belum memusnahkan apa pun, jadi belum ada umur kedaluwarsa',
      () async {
        final document = (await recap()).document;
        final draft = document.rows.singleWhere(
          (row) => row.cells[docNumberColumn].text == draftNumber,
        );

        expect(draft.cells[daysExpiredColumn].text, ReportLabels.notApplicable);
        expect(draft.cells[postedAtColumn].text, ReportLabels.notApplicable);
      },
    );
  });

  group('kuantitas berasal dari ledger', () {
    test('setiap baris sama dengan movement-nya', () async {
      // Read straight from `stock_movements` and compared against the printed
      // column: the report may not be the only witness to its own number (G-L4).
      final movements = await context.database
          .customSelect(
            'SELECT ref_doc_id, batch_id, qty FROM stock_movements '
            "WHERE ref_doc_type = 'DSP';",
          )
          .get();
      expect(movements, hasLength(3));

      final byPosition = {
        for (final row in movements)
          '${row.read<String>('ref_doc_id')}|${row.read<String?>('batch_id')}':
              Quantity.fromMilliUnits(row.read<int>('qty')),
      };

      final document = (await recap()).document;
      expect(
        rowFor(
          document,
          docNumber: warehouseNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[qtyColumn].text,
        byPosition['$warehouseDisposalId|${fixture.expiredBatch.id}']!.format(),
      );
      expect(
        rowFor(
          document,
          docNumber: roomNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[qtyColumn].text,
        byPosition['$roomDisposalId|${fixture.expiredBatch.id}']!.format(),
      );
    });

    test('satu batch dimusnahkan dua kali tetap dua baris terpisah', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          docNumber: warehouseNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[qtyColumn].text,
        '2.375',
      );
      expect(
        rowFor(
          document,
          docNumber: roomNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[qtyColumn].text,
        '1.5',
      );
    });

    test('ledger dipakai apa adanya, bukan angka baris dokumen', () async {
      // The ledger is corrupted behind the application's back and the report has to
      // follow it. Deliberate raw SQL: an intentional-corruption test (§6), which no
      // official API can or should express.
      await context.database.customStatement(
        'UPDATE stock_movements SET qty = 7000 '
        "WHERE ref_doc_type = 'DSP' AND ref_doc_id = '$roomDisposalId';",
      );

      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          docNumber: roomNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[qtyColumn].text,
        '7',
      );
    });

    test('stock_balances yang rusak tidak mengubah laporan', () async {
      // G-L4: the cache is not a source. Deliberate raw SQL: an intentional
      // corruption of a table reporting must never read (§6).
      await context.database.customStatement(
        'UPDATE stock_balances SET qty_on_hand = 555000;',
      );

      final document = (await recap()).document;

      expect(document.overallTotals['ampul'], Quantity.parse('5.125'));
    });

    test('draft tidak menulis movement apa pun', () async {
      final count = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM stock_movements '
            "WHERE ref_doc_type = 'DSP' AND ref_doc_id = '$draftId';",
          )
          .getSingle()
          .then((row) => row.read<int>('c'));
      final document = (await recap()).document;
      final draft = document.rows.singleWhere(
        (row) => row.cells[docNumberColumn].text == draftNumber,
      );

      expect(count, 0);
      expect(draft.cells[qtyColumn].text, '0');
    });
  });

  group('total per satuan (§32)', () {
    test('total menjumlahkan seluruh dokumen dalam satuan yang sama', () async {
      final document = (await recap()).document;

      // 2.375 + 1.25 + 1.5, exactly — the fixed-point path, not a double. The
      // draft's 2 are intent and must not appear.
      expect(document.overallTotals.units, ['ampul']);
      expect(document.overallTotals['ampul'], Quantity.parse('5.125'));
      expect(document.groups.single.subtotals, document.overallTotals);
    });

    test('barang kategori lain memberi subtotal terpisah', () async {
      // The other category's expired batch is destroyed too, and its unit must never
      // be folded into the first.
      final extra = await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.warehouse.id,
        nowUtc: wallClock,
        reason: 'Kedaluwarsa kategori lain',
      );
      await addDisposalPosition(
        context,
        fixture,
        disposalId: extra,
        itemId: fixture.otherExpiryItem.id,
        batchId: fixture.otherExpiredBatch.id,
        qty: '0.5',
        nowUtc: wallClock,
      );
      await context
          .postDisposal(clock: () => postedAtUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: extra);

      final document = (await recap()).document;
      final byCategory = {
        for (final group in document.groups) group.categoryName: group,
      };

      expect(
        byCategory[fixture.category.name]!.subtotals['ampul'],
        Quantity.parse('5.125'),
      );
      expect(
        byCategory[fixture.otherCategory.name]!.subtotals[fixture
            .otherExpiryItem
            .unit],
        Quantity.parse('0.5'),
      );
      expect(
        byCategory[fixture.otherCategory.name]!.subtotals['ampul'],
        isNull,
      );
    });

    test('SKU dan satuan mengikuti barang pada setiap baris', () async {
      final document = (await recap()).document;
      final row = rowFor(
        document,
        docNumber: roomNumber,
        batch: fixture.expiredBatch.batchNo,
      );

      expect(row.cells[skuColumn].text, fixture.expiryItem.sku);
      expect(row.cells[unitColumn].text, fixture.expiryItem.unit);
    });
  });

  group('cakupan (G-L1)', () {
    test('kepala cabang melihat pemusnahan cabangnya saja', () async {
      // Scoped by source location: the warehouse document is not the branch's, and a
      // report that showed it would be reporting on stock they never held.
      final document = (await recap(
        actor: fixture.branchHead,
        scopeType: ReportScopeType.branchAll,
      )).document;

      expect(
        document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
        {roomNumber, draftNumber},
      );
    });

    test('kepala cabang lain tidak melihat dokumen ini', () async {
      final document = (await recap(
        actor: fixture.otherBranchHead,
        scopeType: ReportScopeType.branchAll,
      )).document;

      expect(document.isEmpty, isTrue);
    });

    test('perawat tidak boleh menjalankan rekap pemusnahan', () async {
      // §3.1 gives a nurse no view of a disposal at all — not a narrowed one.
      await expectLater(
        recap(actor: fixture.nurse, scopeType: ReportScopeType.room),
        throwsA(isA<AppFailure>()),
      );
    });

    test('warehouse lintas cabang melihat kedua dokumen', () async {
      final document = (await recap(
        actor: fixture.warehouseUser,
        scopeType: ReportScopeType.crossBranch,
      )).document;

      expect(
        document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
        {warehouseNumber, roomNumber, draftNumber},
      );
    });

    test(
      'super admin seluruh lokasi melihat gudang pusat dan cabang',
      () async {
        final document = (await recap()).document;

        expect(
          document.rows.map((row) => row.cells[docNumberColumn].text).toSet(),
          {warehouseNumber, roomNumber, draftNumber},
        );
      },
    );
  });

  group('filter dan periode', () {
    test('kategori menyaring baris dan total sekaligus', () async {
      final document = (await recap(
        categoryId: fixture.otherCategory.id,
      )).document;

      expect(document.isEmpty, isTrue);
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

    test(
      'menonaktifkan barang dan mengarsipkan batch tidak menghapus baris',
      () async {
        // §51: a posted disposal is permanent, and tidying master data afterwards
        // may not make it unreadable. An `active = 1` join anywhere in this path
        // would drop these rows — and a destroyed batch is precisely the row an
        // administrator is most likely to tidy away.
        await context.deactivate('items', fixture.expiryItem.id);
        await context.archive('item_batches', fixture.staleBatch.id);

        final document = (await recap()).document;

        expect(document.rowCount, 4);
        expect(
          rowFor(
            document,
            docNumber: warehouseNumber,
            batch: fixture.staleBatch.batchNo,
          ).cells[itemColumn].text,
          fixture.expiryItem.name,
        );
        expect(document.overallTotals['ampul'], Quantity.parse('5.125'));
      },
    );

    test('mengarsipkan lokasi sumber tetap menampilkan namanya', () async {
      await context.archive('stock_locations', fixture.locationOne.id);

      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          docNumber: roomNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[sourceColumn].text,
        '${fixture.branch.code} · ${fixture.locationOne.name}',
      );
    });

    test('kategori barang tetap terbaca setelah diarsipkan', () async {
      await context.archive('item_categories', fixture.category.id);

      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          docNumber: roomNumber,
          batch: fixture.expiredBatch.batchNo,
        ).cells[categoryColumn].text,
        fixture.category.name,
      );
    });
  });
}
