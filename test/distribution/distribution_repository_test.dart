import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/distribution/domain/models/distribution_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The Distribusi repository and the streams behind the screens (§45).
///
/// Everything here goes through the real Drift implementation against a real in-memory
/// database, because the two things worth asserting about a repository are exactly the
/// two a stub cannot check: that the milli-unit boundary is crossed correctly (Q-4), and
/// that a stream *emits* when the rows underneath it change.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draft() =>
      createDistributionDraft(context, fixture, nowUtc: nowUtc);

  Future<void> add({
    required String id,
    required String roomId,
    required String itemId,
    required String qty,
  }) => addDistributionItem(
    context,
    fixture,
    distributionId: id,
    roomId: roomId,
    itemId: itemId,
    qty: qty,
    nowUtc: nowUtc,
  );

  group('pemetaan', () {
    test('milli-unit dipetakan ke Quantity dan kembali', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2.375',
      );

      // Stored as an integer, read back as a `Quantity` — and nothing above the
      // repository ever sees the scale (Q-4).
      final rows = await context.distributionLineRows(id);
      expect(rows.values.single['qty'], 2375);

      final references = await context.distributions.lineReferences(id);
      expect(references.single.qty, Quantity.parse('2.375'));
      expect(references.single.qty.format(), '2.375');
    });

    test('status teks dipetakan ke enum', () async {
      final id = await draft();
      final distribution = await context.distributions.getById(id);
      expect(distribution!.status, DistributionStatus.draft);
      expect(await context.distributionStatusOf(id), 'draft');
    });

    test('timestamp UTC bertahan melewati round-trip', () async {
      final id = await draft();
      final distribution = await context.distributions.getById(id);

      expect(distribution!.createdAt, nowUtc);
      expect(distribution.createdAt.isUtc, isTrue);
      expect(distribution.updatedAt.isUtc, isTrue);
    });

    test('tanggal ED dibaca sebagai tanggal sipil', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '1',
      );

      final detail = await context.distributions.getDetail(id);
      final expiry = detail!.lines.single.expiryDate!;
      // T-9: read back verbatim, never timezone converted.
      expect(expiry, DateOnly.from(expiry));
      expect(expiry.hour, 0);
      expect(
        DateOnly.formatIso(expiry),
        DateOnly.formatIso(DateOnly.addDays(DateOnly.of(2026, 7, 30), 10)),
      );
    });

    test('sync status awal pending', () async {
      final id = await draft();
      final distribution = await context.distributions.getById(id);
      expect(distribution!.syncStatus, SyncStatus.pending);
      expect(distribution.isPendingSync, isTrue);
    });

    test('tidak ada kelas Drift yang bocor ke domain', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      final detail = await context.distributions.getDetail(id);
      // Types the domain declares, not generated row classes.
      expect(detail, isA<DistributionDetail>());
      expect(detail!.distribution, isA<Distribution>());
      expect(detail.lines.single, isA<DistributionLine>());
      expect(detail.roomGroups.single, isA<DistributionRoomGroup>());
    });
  });

  group('daftar dan detail', () {
    test('draft baru muncul pada daftar cabang', () async {
      final id = await draft();
      final rows = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows.map((summary) => summary.id), contains(id));
      expect(rows.first.lineCount, 0);
      expect(rows.first.roomCount, 0);
    });

    test('daftar terurut dokumen terbaru lebih dahulu', () async {
      final first = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc.subtract(const Duration(hours: 2)),
      );
      final second = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      final rows = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows.map((summary) => summary.id).toList(), [second, first]);
    });

    test('filter status menyaring daftar', () async {
      final drafted = await draft();
      final posted = await draft();
      await add(
        id: posted,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: posted);

      final drafts = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
        statuses: const {DistributionStatus.draft},
      );
      expect(drafts.map((summary) => summary.id), [drafted]);

      final posts = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
        statuses: const {DistributionStatus.posted},
      );
      expect(posts.map((summary) => summary.id), [posted]);
    });

    test('pencarian menemukan nomor dokumen, ruangan dan barang', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      final distribution = await context.distributions.getById(id);

      Future<List<String>> search(String query) async =>
          (await context.distributions.listForBranch(
            branchId: fixture.branch.id,
            searchQuery: query,
          )).map((summary) => summary.id).toList();

      // Case-insensitive, entirely local (G-Y1).
      expect(await search(distribution!.docNumber.toLowerCase()), [id]);
      expect(await search('ruang dental 2'), [id]);
      expect(await search('R2'), [id]);
      expect(await search('masker'), [id]);
      expect(await search('MASKER BEDAH'), [id]);
      expect(await search('DIST-0001'), [id]);
      expect(await search('tidak ada apa pun'), isEmpty);
    });

    test('pencarian tidak memotong hitungan baris', () async {
      // The counts come from a `LEFT JOIN` the search predicate must not filter away:
      // a document found by its number has to report *all* its lines, not only the
      // matching ones.
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.batchItem.id,
        qty: '1',
      );
      final distribution = await context.distributions.getById(id);

      final rows = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
        searchQuery: distribution!.docNumber,
      );
      expect(rows.single.lineCount, 2);
      expect(rows.single.roomCount, 2);
    });

    test('ringkasan menghitung ruangan, baris dan override', () async {
      final id = await draft();
      // R1 takes 1 of `B-OLD`, leaving 1 behind — so R2 choosing `A-NEW` genuinely skips
      // older stock and is the override this count is about (G-E3).
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '1',
      );
      await addManualDistributionAllocation(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.batchItem.id,
        batchId: fixture.newBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        fefoOverrideReason: 'Permintaan dokter',
      );

      final rows = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows.single.lineCount, 2);
      expect(rows.single.roomCount, 2);
      expect(rows.single.overrideCount, 1);
      expect(rows.single.label, '2 ruangan · 2 baris');
    });

    test('detail mengelompokkan per ruangan dan per item', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
      );

      final detail = await context.distributions.getDetail(id);
      expect(detail!.roomGroups.map((group) => group.roomCode), <String>[
        'R1',
        'R2',
      ]);
      expect(detail.linesForItem(fixture.batchItem.id), hasLength(2));
      expect(detail.linesForRoom(fixture.roomTwo.id), hasLength(1));
      expect(detail.totalForItem(fixture.batchItem.id), Quantity.parse('3'));
      expect(
        detail.totalForSourcePosition(
          itemId: fixture.batchItem.id,
          batchId: fixture.oldBatch.id,
        ),
        Quantity.parse('2'),
      );
    });
  });

  group('stream', () {
    test('menambah baris memancarkan detail baru', () async {
      final id = await draft();
      final stream = context.distributions.watchForBranch(
        distributionId: id,
        branchId: fixture.branch.id,
      );

      final emissions = <int>[];
      final subscription = stream.listen((detail) {
        if (detail != null) emissions.add(detail.lineCount);
      });
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      await pumpEventQueue();

      expect(emissions, contains(0));
      expect(emissions.last, 1);
    });

    test('mengubah qty memancarkan detail baru', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      final lines = await distributionLineIdsByPosition(context, id);
      final lineId = lines.values.single;

      final quantities = <String>[];
      final subscription = context.distributions
          .watchForBranch(distributionId: id, branchId: fixture.branch.id)
          .listen((detail) {
            if (detail != null && detail.lines.isNotEmpty) {
              quantities.add(detail.lines.single.qty.format());
            }
          });
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await context
          .updateDistributionLine(clock: () => nowUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            distributionId: id,
            lineId: lineId,
            qty: Quantity.parse('4.5'),
          );
      await pumpEventQueue();

      expect(quantities.last, '4.5');
    });

    test('menghapus baris memancarkan detail baru', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      final lines = await distributionLineIdsByPosition(context, id);

      final counts = <int>[];
      final subscription = context.distributions
          .watchForBranch(distributionId: id, branchId: fixture.branch.id)
          .listen((detail) {
            if (detail != null) counts.add(detail.lineCount);
          });
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await context.removeDistributionLine.call(
        actorUserId: fixture.branchHead.id,
        distributionId: id,
        lineId: lines.values.single,
      );
      await pumpEventQueue();

      expect(counts.last, 0);
    });

    test('posting memancarkan perubahan status', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      final statuses = <DistributionStatus>[];
      final subscription = context.distributions
          .watchForBranch(distributionId: id, branchId: fixture.branch.id)
          .listen((detail) {
            if (detail != null) statuses.add(detail.status);
          });
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);
      await pumpEventQueue();

      expect(statuses.first, DistributionStatus.draft);
      expect(statuses.last, DistributionStatus.posted);
    });

    test('daftar memancarkan dokumen baru', () async {
      final counts = <int>[];
      final subscription = context.distributions
          .watchListForBranch(branchId: fixture.branch.id)
          .listen((rows) => counts.add(rows.length));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await draft();
      await pumpEventQueue();

      expect(counts.first, 0);
      expect(counts.last, 1);
    });

    test('saldo ruangan dan gudang memancarkan perubahan', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2',
      );

      final storeTotals = <String>[];
      final storeSubscription = context.inventory
          .watchBalancesAtLocation(fixture.branchStore.id)
          .listen((rows) {
            final match = rows.where(
              (row) => row.itemId == fixture.simpleItem.id,
            );
            if (match.isNotEmpty) {
              storeTotals.add(match.first.qtyOnHand.format());
            }
          });
      addTearDown(storeSubscription.cancel);

      final roomTotals = <String>[];
      final roomSubscription = context.inventory
          .watchBalancesAtLocation(fixture.locationOne.id)
          .listen((rows) {
            final match = rows.where(
              (row) => row.itemId == fixture.simpleItem.id,
            );
            if (match.isNotEmpty) {
              roomTotals.add(match.first.qtyOnHand.format());
            }
          });
      addTearDown(roomSubscription.cancel);

      await pumpEventQueue();
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);
      await pumpEventQueue();

      expect(storeTotals.first, '10.5');
      expect(storeTotals.last, '8.5');
      expect(roomTotals.last, '2');
    });
  });

  group('pencarian stok gudang cabang', () {
    Future<List<DistributionStockItem>> search({
      String query = '',
      String? categoryId,
      int limit = 8,
    }) => context.distributions.searchBranchStock(
      branchStoreLocationId: fixture.branchStore.id,
      nowUtc: nowUtc,
      searchQuery: query,
      categoryId: categoryId,
      limit: limit,
    );

    test('hanya barang bersaldo positif muncul', () async {
      final rows = await search();
      final ids = rows.map((row) => row.itemId).toSet();

      expect(ids, contains(fixture.simpleItem.id));
      expect(ids, contains(fixture.batchItem.id));
      expect(ids, contains(fixture.tieItem.id));
      // Deliberately unstocked, so it must not be offered (§15).
      expect(ids, isNot(contains(fixture.emptyItem.id)));
    });

    test('total mengabaikan batch kedaluwarsa', () async {
      final rows = await search(query: 'Anestesi');
      // 2 + 4 usable; the expired 3 never counts (G-E4).
      expect(rows.single.availableQty, Quantity.parse('6'));
      expect(rows.single.batchCount, 2);
      expect(rows.single.expiredCandidates, hasLength(1));
      expect(rows.single.hasExpiredStock, isTrue);
    });

    test('pencarian nama dan SKU tidak peka huruf besar', () async {
      expect((await search(query: 'masker')).single.sku, 'DIST-0001');
      expect((await search(query: 'MASKER')).single.sku, 'DIST-0001');
      expect((await search(query: 'dist-0002')).single.sku, 'DIST-0002');
      expect(await search(query: 'tidak ada'), isEmpty);
    });

    test('filter kategori menyaring hasil', () async {
      final consumables = await search(categoryId: fixture.category.id);
      expect(
        consumables.map((row) => row.itemId),
        containsAll([fixture.simpleItem.id, fixture.tieItem.id]),
      );
      expect(
        consumables.map((row) => row.itemId),
        isNot(contains(fixture.batchItem.id)),
      );

      final drugs = await search(categoryId: fixture.otherCategory.id);
      expect(drugs.map((row) => row.itemId), [fixture.batchItem.id]);
    });

    test('batas hasil membatasi jumlah barang, bukan jumlah baris', () async {
      // `batchItem` has three balance rows. A row-level `LIMIT` would cut it off
      // mid-item and report a total lower than the store holds.
      final limited = await search(limit: 1);
      expect(limited, hasLength(1));

      final all = await search(limit: 8);
      expect(all.length, greaterThan(1));
      final batchRow = all.firstWhere(
        (row) => row.itemId == fixture.batchItem.id,
      );
      expect(batchRow.availableQty, Quantity.parse('6'));
    });

    test('kandidat terurut ED terdekat lebih dahulu', () async {
      final rows = await search(query: 'Anestesi');
      expect(
        rows.single.candidates.map((candidate) => candidate.batchNo),
        <String>['B-OLD', 'A-NEW'],
      );
      expect(rows.single.nearestExpiryDate, isNotNull);
      expect(rows.single.hasNearExpiryBatch(nowUtc), isTrue);
    });

    test('barang tanpa ED tidak menyertakan kandidat batch', () async {
      final rows = await search(query: 'Masker');
      expect(rows.single.hasExpiry, isFalse);
      expect(rows.single.candidates, isEmpty);
      expect(rows.single.expiredCandidates, isEmpty);
      expect(rows.single.availableQty, Quantity.parse('10.5'));
    });

    test('barang nonaktif tidak muncul pada pencarian baru', () async {
      await context.deactivate('items', fixture.simpleItem.id);
      final rows = await search(query: 'Masker');
      expect(rows, isEmpty);

      // But it is still readable for a line that already exists — which is what an edit
      // needs (G-A4/§32).
      final stock = await context.distributions.branchStockFor(
        branchStoreLocationId: fixture.branchStore.id,
        itemId: fixture.simpleItem.id,
        nowUtc: nowUtc,
        activeItemsOnly: false,
      );
      expect(stock, isNotNull);
      expect(stock!.availableQty, Quantity.parse('10.5'));
    });

    test(
      'branchStockFor melaporkan barang yang seluruhnya kedaluwarsa',
      () async {
        // Drain the two usable batches, leaving only the expired one.
        final id = await draft();
        await add(
          id: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          qty: '6',
        );
        await context
            .postDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, distributionId: id);

        final stock = await context.distributions.branchStockFor(
          branchStoreLocationId: fixture.branchStore.id,
          itemId: fixture.batchItem.id,
          nowUtc: nowUtc,
        );
        // Reported rather than absent, so the add path can say *"expired, dispose of it"*
        // rather than *"no such item"*.
        expect(stock, isNotNull);
        expect(stock!.availableQty, Quantity.zero());
        expect(stock.expiredCandidates, hasLength(1));
      },
    );
  });

  group('ruangan', () {
    test('branchRooms hanya ruangan aktif cabang, urut kode', () async {
      final rooms = await context.distributions.branchRooms(fixture.branch.id);
      expect(rooms.map((room) => room.code), <String>['R1', 'R2', 'R3']);

      await context.deactivate('rooms', fixture.roomTwo.id);
      final after = await context.distributions.branchRooms(fixture.branch.id);
      expect(after.map((room) => room.code), <String>['R1', 'R3']);
    });

    test('watchBranchRooms memancarkan perubahan', () async {
      // The change is made through the repository rather than with
      // `TestContext.deactivate`: raw `customStatement` does not notify drift's query
      // streams, so a hand-written UPDATE would prove nothing about the stream. Adding a
      // fourth room is exactly what an administrator does, and it is what the form's
      // chips have to pick up without a reload.
      final counts = <int>[];
      final subscription = context.distributions
          .watchBranchRooms(fixture.branch.id)
          .listen((rows) => counts.add(rows.length));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await context.master.ensureRoom(
        branchId: fixture.branch.id,
        code: 'R4',
        name: 'Ruang Dental 4',
      );
      await pumpEventQueue();

      expect(counts.first, 3);
      expect(counts.last, 4);
    });

    test('barang tanpa saldo tetap dihitung sebagai stok menipis', () async {
      // `balancesAtLocation` returns positive rows only, so an item the store has run out
      // of has no row at all — and a product at zero against `min_stock_branch = 9` is
      // the most low-stock thing there is. The dashboard counts from the catalogue for
      // exactly this reason.
      final balances = await context.inventory.balancesAtLocation(
        fixture.branchStore.id,
      );
      expect(
        balances.map((row) => row.itemId),
        isNot(contains(fixture.emptyItem.id)),
      );
      expect(fixture.emptyItem.minStockBranch, greaterThan(0));
    });

    test('historicalRoomById menyertakan ruangan yang diarsipkan', () async {
      await context.archive('rooms', fixture.roomTwo.id);
      final room = await context.distributions.historicalRoomById(
        fixture.roomTwo.id,
      );
      expect(room, isNotNull);
      expect(room!.isArchived, isTrue);
    });
  });

  group('penulisan terjaga', () {
    test('update baris basi ditolak setelah dokumen diposting', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      final lines = await distributionLineIdsByPosition(context, id);
      final lineId = lines.values.single;
      await context
          .postDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, distributionId: id);

      // The guard is inside the statement, so even a caller that bypassed the use case
      // affects no rows.
      expect(
        await context.distributions.updateDraftLine(
          distributionId: id,
          lineId: lineId,
          qty: Quantity.parse('9'),
        ),
        isFalse,
      );
      expect(
        await context.distributions.removeDraftLine(
          distributionId: id,
          lineId: lineId,
        ),
        isFalse,
      );
      expect(
        await context.distributions.updateDraftNote(
          distributionId: id,
          note: 'Sesudah posting',
        ),
        isFalse,
      );

      final rows = await context.distributionLineRows(id);
      expect(rows[lineId]!['qty'], 1000);
      expect(await context.distributionColumn(id, 'note'), isNull);
    });

    test('markPosted kedua kali mengembalikan false', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      expect(
        await context.distributions.markPosted(
          distributionId: id,
          postedAtUtc: nowUtc,
        ),
        isTrue,
      );
      expect(
        await context.distributions.markPosted(
          distributionId: id,
          postedAtUtc: nowUtc,
        ),
        isFalse,
      );
    });

    test('markPosted menolak dokumen tanpa baris', () async {
      final id = await draft();
      // The `EXISTS` predicate in the same statement is what makes an empty document
      // unpostable even to a caller that skipped the use case.
      expect(
        await context.distributions.markPosted(
          distributionId: id,
          postedAtUtc: nowUtc,
        ),
        isFalse,
      );
      expect(await context.distributionStatusOf(id), 'draft');
    });

    test('addAllocations menolak posisi ganda dengan kegagalan bisnis', () async {
      final id = await draft();
      final allocation = DistributionAllocation(
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: Quantity.parse('1'),
      );
      await context.distributions.addAllocations(
        distributionId: id,
        allocations: [allocation],
      );

      // A driver error would be useless to a branch head; the repository turns the
      // partial unique index into a sentence.
      expect(
        () => context.distributions.addAllocations(
          distributionId: id,
          allocations: [allocation],
        ),
        throwsA(isA<DuplicateDistributionLineFailure>()),
      );
    });

    test(
      'addAllocations menyimpan seluruh alokasi atau tidak sama sekali',
      () async {
        final id = await draft();
        final first = DistributionAllocation(
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          batchId: fixture.oldBatch.id,
          qty: Quantity.parse('1'),
        );
        // The second collides with the first: same position, twice in one batch insert.
        expect(
          () => context.distributions.addAllocations(
            distributionId: id,
            allocations: [first, first],
          ),
          throwsA(isA<DuplicateDistributionLineFailure>()),
        );
        expect(await context.distributionLineCount(id), 0);
      },
    );

    test('transaksi yang gagal tidak menyisakan baris', () async {
      final id = await draft();

      await expectLater(
        context.distributions.runInTransaction(() async {
          await context.distributions.addAllocations(
            distributionId: id,
            allocations: [
              DistributionAllocation(
                roomId: fixture.roomOne.id,
                itemId: fixture.simpleItem.id,
                qty: Quantity.parse('1'),
              ),
            ],
          );
          throw const ValidationFailure('Batal.');
        }),
        throwsA(isA<ValidationFailure>()),
      );

      expect(await context.distributionLineCount(id), 0);
    });
  });

  group('id polos untuk pemeriksaan integritas', () {
    test('setiap kumpulan id dibaca tanpa join', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
      );
      await add(
        id: id,
        roomId: fixture.roomTwo.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );

      expect(await context.distributions.lineIds(id), hasLength(3));
      expect((await context.distributions.lineRoomIds(id)).toSet(), {
        fixture.roomOne.id,
        fixture.roomTwo.id,
      });
      expect((await context.distributions.lineItemIds(id)).toSet(), {
        fixture.batchItem.id,
        fixture.simpleItem.id,
      });
      // NULL batches are dropped: an item without expiry has no batch to verify.
      expect((await context.distributions.lineBatchIds(id)).toSet(), {
        fixture.oldBatch.id,
        fixture.newBatch.id,
      });
    });

    test('baris yang dihapus tidak muncul pada kumpulan id', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      final lines = await distributionLineIdsByPosition(context, id);
      await context.removeDistributionLine.call(
        actorUserId: fixture.branchHead.id,
        distributionId: id,
        lineId: lines.values.single,
      );

      expect(await context.distributions.lineIds(id), isEmpty);
      expect(await context.distributions.lineRoomIds(id), isEmpty);
    });

    test('lineReferenceById membawa distribution_id untuk otorisasi', () async {
      final id = await draft();
      await add(
        id: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
      );
      final lines = await distributionLineIdsByPosition(context, id);

      final reference = await context.distributions.lineReferenceById(
        lines.values.single,
      );
      expect(reference!.distributionId, id);
      expect(reference.sourceKey, '${fixture.simpleItem.id}|');
      expect(
        reference.positionKey,
        '${fixture.roomOne.id}|${fixture.simpleItem.id}|',
      );
      expect(reference.isBatched, isFalse);
    });
  });
}
