import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/opname/domain/models/opname_models.dart';
import 'package:aish_warehouse/features/opname/domain/repositories/opname_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Repository behaviour: reactive streams, guarded writes under concurrency,
/// soft deletes, and the offline item search behind the SearchableDropdown.
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  DateTime now = fixedWednesdayUtc();
  DateTime clock() => now;

  setUp(() async {
    now = fixedWednesdayUtc();
    context = TestContext.create(clock: clock);
    fixture = await buildOpnameFixture(context, now: now);
  });

  tearDown(() => context.dispose());

  Future<String> draft() async {
    final opname = await context.createOpname().call(
      actorUserId: fixture.nurse.id,
      roomId: fixture.room.id,
    );
    return opname.id;
  }

  StockOpnameFilter forNurse() => StockOpnameFilter(
    branchId: fixture.branch.id,
    countedBy: fixture.nurse.id,
  );

  group('stream', () {
    test('daftar memancarkan draft baru', () async {
      final emissions = <List<StockOpnameSummary>>[];
      final subscription = context.opnames
          .watchList(forNurse())
          .listen(emissions.add);

      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      await draft();
      await pumpEventQueue();

      expect(emissions.last, hasLength(1));
      expect(emissions.last.single.status, StockOpnameStatus.draft);
      expect(emissions.last.single.roomCode, 'R1');
      expect(emissions.last.single.countedByName, 'Perawat Uji');
      expect(emissions.last.single.lineCount, 3);
      expect(emissions.last.single.differenceLineCount, 0);

      await subscription.cancel();
    });

    test('detail memancarkan perubahan baris', () async {
      final id = await draft();
      final emissions = <StockOpnameDetail?>[];
      final subscription = context.opnames
          .watchDetail(id)
          .listen(emissions.add);

      await pumpEventQueue();
      final first = emissions.last!;
      final line = first.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );
      expect(line.countedQty, Quantity.parse('10.5'));

      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: line.id,
        countedQty: Quantity.parse('0.5'),
        note: 'Tersisa setengah',
      );
      await pumpEventQueue();

      final updated = emissions.last!.lines.firstWhere(
        (row) => row.id == line.id,
      );
      expect(updated.countedQty, Quantity.parse('0.5'));
      expect(updated.difference.format(), '-10');

      await subscription.cancel();
    });

    test('jumlah baris berselisih ikut terbarui', () async {
      final id = await draft();
      final detail = await context.opnames.getDetail(id);
      final line = detail!.lines.first;

      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: line.id,
        countedQty: line.systemQty + Quantity.parse('1'),
        note: 'Lebih satu',
      );

      final summaries = await context.opnames.list(forNurse());
      expect(summaries.single.differenceLineCount, 1);
      expect(summaries.single.hasDifference, isTrue);
      expect(await context.opnames.countDifferenceLines(id), 1);
    });

    test('daftar review berubah saat dokumen dikirim', () async {
      final inbox = <List<StockOpnameSummary>>[];
      final subscription = context.opnames
          .watchList(submittedForBranch(fixture.branch.id))
          .listen(inbox.add);

      final id = await draft();
      await pumpEventQueue();
      expect(inbox.last, isEmpty);

      await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: id,
      );
      await pumpEventQueue();
      expect(inbox.last, hasLength(1));

      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: id,
      );
      await pumpEventQueue();
      // Once reviewed it leaves the pending-review inbox.
      expect(inbox.last, isEmpty);

      await subscription.cancel();
    });

    test('dokumen terhapus lembut tidak muncul pada daftar aktif', () async {
      final id = await draft();
      expect(await context.opnames.list(forNurse()), hasLength(1));

      await context.opnames.removeDraft(id);

      expect(await context.opnames.list(forNurse()), isEmpty);
      expect(await context.opnames.getById(id), isNull);
      expect(await context.opnames.getDetail(id), isNull);
    });

    test('baris terhapus lembut tidak muncul pada detail', () async {
      final id = await draft();
      final detail = await context.opnames.getDetail(id);
      await context.opnames.removeDraftLine(detail!.lines.first.id);

      final after = await context.opnames.getDetail(id);
      expect(after!.lines, hasLength(2));

      final summaries = await context.opnames.list(forNurse());
      expect(summaries.single.lineCount, 2);
    });
  });

  group('filter', () {
    test('menyaring berdasarkan status', () async {
      final first = await draft();
      await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: first,
      );

      now = now.add(const Duration(days: 7));
      await draft();

      final drafts = await context.opnames.list(
        StockOpnameFilter(
          branchId: fixture.branch.id,
          statuses: const {StockOpnameStatus.draft},
        ),
      );
      expect(drafts, hasLength(1));
      expect(drafts.single.status, StockOpnameStatus.draft);

      final submitted = await context.opnames.list(
        submittedForBranch(fixture.branch.id),
      );
      expect(submitted.single.id, first);
    });

    test('menyaring berdasarkan ruangan', () async {
      await draft();
      await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.secondRoom.id,
      );

      final rows = await context.opnames.list(
        StockOpnameFilter(
          branchId: fixture.branch.id,
          roomId: fixture.secondRoom.id,
        ),
      );
      expect(rows, hasLength(1));
      expect(rows.single.roomCode, 'R2');
    });

    test('filter baris menyaring per kategori', () async {
      final id = await draft();
      final detail = await context.opnames.getDetail(id);

      final otherCategory = await context.master.ensureCategory('Obat');
      final otherItem = await context.master.ensureItem(
        sku: 'TEST-0099',
        name: 'Paracetamol',
        categoryId: otherCategory.id,
        unit: 'strip',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );
      await context.addOpnameLine(
        actorUserId: fixture.nurse.id,
        opnameId: id,
        itemId: otherItem.id,
        countedQty: Quantity.parse('2'),
        note: 'Ditemukan',
      );

      final reloaded = await context.opnames.getDetail(id);
      final filter = StockOpnameFilter(categoryId: fixture.category.id);
      final visible = reloaded!.lines.where(filter.matchesLine).toList();

      expect(visible, hasLength(detail!.lines.length));
      expect(
        visible.every((line) => line.categoryId == fixture.category.id),
        isTrue,
      );
    });

    test(
      'filter baris mencari nama, SKU dan batch tanpa peduli huruf besar',
      () async {
        final id = await draft();
        final detail = await context.opnames.getDetail(id);

        expect(
          detail!.lines
              .where(const StockOpnameFilter(searchQuery: 'MASKER').matchesLine)
              .map((line) => line.sku),
          ['TEST-0001'],
        );
        expect(
          detail.lines
              .where(
                const StockOpnameFilter(searchQuery: 'test-0002').matchesLine,
              )
              .length,
          2,
        );
        expect(
          detail.lines
              .where(
                const StockOpnameFilter(searchQuery: 'batch-ok').matchesLine,
              )
              .map((line) => line.batchNo),
          ['BATCH-OK'],
        );
        expect(
          detail.lines.where(
            const StockOpnameFilter(searchQuery: 'tidak ada').matchesLine,
          ),
          isEmpty,
        );
      },
    );

    test('filter kategori dapat dikosongkan kembali', () {
      const filter = StockOpnameFilter(categoryId: 'kategori-1');
      expect(filter.copyWith(categoryId: null).categoryId, isNull);
      expect(filter.copyWith(searchQuery: 'abc').categoryId, 'kategori-1');
    });
  });

  group('pencarian barang untuk dropdown', () {
    test('mencari berdasarkan nama tanpa peduli huruf besar', () async {
      final results = await context.opnames.searchAddableItems(query: 'masKer');
      expect(results.map((item) => item.sku), contains('TEST-0001'));
    });

    test('mencari berdasarkan SKU', () async {
      final results = await context.opnames.searchAddableItems(
        query: 'test-0002',
      );
      expect(results.single.name, 'Anestesi Lokal');
    });

    test('mengikuti kategori terpilih', () async {
      final otherCategory = await context.master.ensureCategory('APD');
      await context.master.ensureItem(
        sku: 'TEST-0100',
        name: 'Masker N95',
        categoryId: otherCategory.id,
        unit: 'box',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );

      final all = await context.opnames.searchAddableItems(query: 'masker');
      expect(all, hasLength(2));

      final filtered = await context.opnames.searchAddableItems(
        query: 'masker',
        categoryId: otherCategory.id,
      );
      expect(filtered.single.sku, 'TEST-0100');
    });

    test('membatasi jumlah hasil', () async {
      for (var i = 0; i < 12; i++) {
        await context.master.ensureItem(
          sku: 'BULK-${i.toString().padLeft(3, '0')}',
          name: 'Barang Massal $i',
          categoryId: fixture.category.id,
          unit: 'pcs',
          minStockRoom: 1,
          minStockBranch: 2,
          hasExpiry: false,
        );
      }

      final results = await context.opnames.searchAddableItems(
        query: 'Barang Massal',
      );
      expect(results, hasLength(8));

      final wider = await context.opnames.searchAddableItems(
        query: 'Barang Massal',
        limit: 20,
      );
      expect(wider, hasLength(12));
    });

    test('barang nonaktif tidak muncul', () async {
      final inactive = await context.master.ensureItem(
        sku: 'TEST-0200',
        name: 'Barang Pensiun',
        categoryId: fixture.category.id,
        unit: 'pcs',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );
      await context.database.customStatement(
        "UPDATE items SET is_active = 0 WHERE id = '${inactive.id}';",
      );

      final results = await context.opnames.searchAddableItems(
        query: 'Pensiun',
      );
      expect(results, isEmpty);
    });
  });

  group('konkurensi', () {
    test('submit ganda hanya berhasil sekali', () async {
      final id = await draft();

      final outcomes = await Future.wait([
        context
            .submitOpname()
            .call(actorUserId: fixture.nurse.id, opnameId: id)
            .then((_) => 'ok')
            .catchError((Object error) => error.runtimeType.toString()),
        context
            .submitOpname()
            .call(actorUserId: fixture.nurse.id, opnameId: id)
            .then((_) => 'ok')
            .catchError((Object error) => error.runtimeType.toString()),
      ]);

      expect(outcomes.where((outcome) => outcome == 'ok'), hasLength(1));
      expect(
        (await context.opnames.getById(id))!.status,
        StockOpnameStatus.submitted,
      );
    });

    test('review ganda hanya memposting sekali', () async {
      final id = await draft();
      final detail = await context.opnames.getDetail(id);
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: detail!.lines
            .firstWhere((line) => line.itemId == fixture.simpleItem.id)
            .id,
        countedQty: Quantity.parse('8'),
        note: 'Terpakai',
      );
      await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: id,
      );

      final outcomes = await Future.wait([
        context
            .reviewOpname()
            .call(actorUserId: fixture.branchHead.id, opnameId: id)
            .then((_) => 'ok')
            .catchError((Object error) => error.runtimeType.toString()),
        context
            .reviewOpname()
            .call(actorUserId: fixture.branchHead.id, opnameId: id)
            .then((_) => 'ok')
            .catchError((Object error) => error.runtimeType.toString()),
      ]);

      expect(outcomes.where((outcome) => outcome == 'ok'), hasLength(1));

      final movements = await context.inventory.movementsByRef(
        refDocType: RefDocType.stockOpname,
        refDocId: id,
      );
      expect(movements, hasLength(1));
      expect(
        await context.inventory.balanceQty(
          locationId: fixture.roomLocation.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.parse('8'),
      );
    });

    test('update pada dokumen yang sudah dikirim ditolak', () async {
      final id = await draft();
      final detail = await context.opnames.getDetail(id);
      final lineId = detail!.lines.first.id;

      await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: id,
      );

      // The repository write itself refuses, without any use-case guard.
      final updated = await context.opnames.updateDraftLine(
        lineId: lineId,
        countedQty: Quantity.parse('99'),
        note: 'Percobaan',
      );
      expect(updated, isFalse);
    });

    test('rollback transaksi tidak meninggalkan data sebagian', () async {
      // A create whose snapshot insert fails must leave no header behind.
      await expectLater(
        context.opnames.runInTransaction(() async {
          await context.opnames.createDraft(
            docNumber: 'TMP-SO-ROLLBACK',
            branchId: fixture.branch.id,
            roomId: fixture.room.id,
            periodYear: 2026,
            periodWeek: 31,
            countedBy: fixture.nurse.id,
            lines: const [],
          );
          throw const ValidationFailure('Batalkan transaksi.');
        }),
        throwsA(isA<ValidationFailure>()),
      );

      final rows = await context.database
          .customSelect('SELECT id FROM stock_opnames;')
          .get();
      expect(rows, isEmpty);
    });
  });

  group('soft delete dan unik', () {
    test('baris yang dihapus dapat ditambahkan kembali', () async {
      // Regression: the partial unique indexes must ignore soft-deleted rows,
      // otherwise removing a line from a draft would permanently block that
      // item/batch position from being counted again.
      final id = await draft();
      final detail = await context.opnames.getDetail(id);
      final line = detail!.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );

      expect(await context.opnames.removeDraftLine(line.id), isTrue);

      final readded = await context.addOpnameLine(
        actorUserId: fixture.nurse.id,
        opnameId: id,
        itemId: fixture.simpleItem.id,
        countedQty: Quantity.parse('7'),
        note: 'Dihitung ulang',
      );
      expect(readded.countedQty, Quantity.parse('7'));

      final after = await context.opnames.getDetail(id);
      expect(
        after!.lines.where((line) => line.itemId == fixture.simpleItem.id),
        hasLength(1),
      );
    });

    test('opname yang dihapus tidak memblokir minggu yang sama', () async {
      final first = await draft();
      await context.opnames.removeDraft(first);

      // G-O1 constrains live documents; a deleted draft is history.
      final second = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      expect(second.id, isNot(first));
      expect(
        second.periodWeek,
        (await context.opnames.getById(second.id))!.periodWeek,
      );
    });
  });

  group('ringkasan detail', () {
    test('mengelompokkan kelebihan dan kekurangan per satuan', () async {
      final id = await draft();
      final detail = await context.opnames.getDetail(id);

      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: detail!.lines
            .firstWhere((line) => line.itemId == fixture.simpleItem.id)
            .id,
        countedQty: Quantity.parse('8'),
        note: 'Berkurang 2.5 box',
      );
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: detail.lines
            .firstWhere((line) => line.batchId == fixture.validBatch.id)
            .id,
        countedQty: Quantity.parse('4.375'),
        note: 'Bertambah 2 ampul',
      );

      final after = await context.opnames.getDetail(id);
      expect(after!.shortageByUnit['box'], Quantity.parse('2.5'));
      expect(after.surplusByUnit['ampul'], Quantity.parse('2'));
      // Units are never mixed into one misleading total.
      expect(after.surplusByUnit.containsKey('box'), isFalse);
      expect(after.linesWithDifference, hasLength(2));
    });

    test('menandai baris yang belum memiliki catatan', () async {
      final id = await draft();
      final detail = await context.opnames.getDetail(id);
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: detail!.lines.first.id,
        countedQty: detail.lines.first.systemQty + Quantity.parse('1'),
      );

      final after = await context.opnames.getDetail(id);
      expect(after!.linesMissingNote, hasLength(1));
      expect(after.isSubmittable, isFalse);
    });
  });
}
