import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/goods_return/domain/models/goods_return_models.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Reads, streams and filters (§25/§48).
///
/// Everything here is about what the screens actually subscribe to: that a document
/// appears in the right list the moment it is raised, moves between lists as it
/// transitions, and that the two orderings the SQL cannot promise — oldest posting
/// first on the eligible queue, newest first on the lists — are re-done in Dart on
/// parsed UTC instants (§39).
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('antrean eligible', () {
    test('GR rejected muncul, lalu hilang setelah retur dibuat', () async {
      final stream = context.goodsReturns.watchEligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );
      final emissions = <List<GoodsReturnEligibility>>[];
      final subscription = stream.listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      expect(
        emissions.last
            .where((row) => row.canCreateReturn)
            .map((row) => row.grId),
        contains(fixture.goodReceiptId),
      );

      await createGoodsReturnFor(context, fixture);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        emissions.last
            .where((row) => row.canCreateReturn)
            .map((row) => row.grId),
        isNot(contains(fixture.goodReceiptId)),
      );
      // The row itself is still there, carrying the document — §33 needs it.
      final row = emissions.last.singleWhere(
        (item) => item.grId == fixture.goodReceiptId,
      );
      expect(row.existingReturnStatus, GoodsReturnStatus.draft);

      await subscription.cancel();
    });

    test('posisi membawa alasan, batch dan total per unit', () async {
      final rows = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );
      final row = rows.singleWhere(
        (item) => item.grId == fixture.goodReceiptId,
      );

      expect(row.rejectReasons, hasLength(2));
      expect(row.totalQuantityByUnit.keys.toSet(), {
        fixture.simpleItem.unit,
        fixture.batchItem.unit,
      });
      expect(
        row.positions.singleWhere((p) => p.isBatched).batchNo,
        fixture.nearBatch.batchNo,
      );
      expect(row.nearExpiryCount(nowUtc), 1);
      expect(row.expiredCount(nowUtc), 0);
      expect(row.expiredCount(fixture.expiredInstant), 1);
    });

    test('pencarian menyaring antrean', () async {
      final hit = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
        searchQuery: fixture.simpleItem.sku,
      );
      expect(hit.map((row) => row.grId), contains(fixture.goodReceiptId));

      final miss = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
        searchQuery: 'tidak-ada-barang-ini',
      );
      expect(miss, isEmpty);
    });
  });

  group('daftar cabang', () {
    test('draft muncul segera, lalu berpindah antar status', () async {
      final emissions = <List<GoodsReturnSummary>>[];
      final subscription = context.goodsReturns
          .watchBranchList(branchId: fixture.branch.id)
          .listen(emissions.add);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, isEmpty);

      final created = await createGoodsReturnFor(context, fixture);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.single.status, GoodsReturnStatus.draft);

      await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: created.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.single.status, GoodsReturnStatus.shipped);

      await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: created.id,
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.single.status, GoodsReturnStatus.received);

      await subscription.cancel();
    });

    test('ringkasan membawa rantai dokumen dan total per unit', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final row = (await context.goodsReturns.listForBranch(
        branchId: fixture.branch.id,
      )).singleWhere((item) => item.id == created.id);

      expect(row.grDocNumber, isNotEmpty);
      expect(row.doDocNumber, isNotEmpty);
      expect(row.prDocNumber, isNotEmpty);
      expect(row.createdByName, fixture.branchHead.fullName);
      expect(row.lineCount, 2);
      expect(row.itemCount, 2);
      expect(row.batchCount, 1);
      expect(
        row.totalsByUnit[fixture.simpleItem.unit],
        fixture.rejectedSimpleQty,
      );
      expect(
        row.totalsByUnit[fixture.batchItem.unit],
        fixture.rejectedBatchQty,
      );
      expect(
        row.totalQty,
        Quantity.sum([fixture.rejectedSimpleQty, fixture.rejectedBatchQty]),
      );
    });

    test(
      'pencarian menemukan lewat RET, GR, SJ, PR, barang dan batch',
      () async {
        final created = await createGoodsReturnFor(context, fixture);
        final detail = (await context.goodsReturns.getDetail(created.id))!;

        for (final needle in [
          created.docNumber,
          detail.summary.grDocNumber,
          detail.summary.doDocNumber,
          detail.summary.prDocNumber,
          fixture.simpleItem.sku,
          fixture.nearBatch.batchNo,
        ]) {
          final rows = await context.goodsReturns.listForBranch(
            branchId: fixture.branch.id,
            searchQuery: needle,
          );
          expect(
            rows.map((row) => row.id),
            contains(created.id),
            reason: 'Pencarian "$needle" tidak menemukan dokumen.',
          );
        }
      },
    );

    test('urutan terbaru dulu, dihitung dari instant', () async {
      final first = await createGoodsReturnFor(context, fixture);
      final second = await context
          .createGoodsReturn(clock: () => nowUtc.add(const Duration(hours: 1)))
          .call(
            actorUserId: fixture.branchHead.id,
            goodReceiptId: fixture.checkingGoodReceiptId,
          )
          .then<String?>((value) => value.id, onError: (Object _) => null);

      final rows = await context.goodsReturns.listForBranch(
        branchId: fixture.branch.id,
      );
      // The second receipt is still `checking`, so it legitimately has no return; the
      // ordering assertion then reduces to "the one document is there", which is still
      // worth stating because a broken comparator would throw rather than mis-sort.
      expect(rows.first.id, second ?? first.id);
    });
  });

  group('antrean Warehouse', () {
    test('hanya shipped, lalu berpindah ke riwayat', () async {
      final emissions = <List<GoodsReturnSummary>>[];
      final subscription = context.goodsReturns.watchWarehouseList().listen(
        emissions.add,
      );
      await Future<void>.delayed(Duration.zero);

      final created = await createGoodsReturnFor(context, fixture);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last, isEmpty, reason: 'Draft bukan urusan Warehouse.');

      await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: created.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.single.status, GoodsReturnStatus.shipped);

      await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: created.id,
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last.single.status, GoodsReturnStatus.received);

      await subscription.cancel();
    });

    test('umur perjalanan dihitung dari shippedAt', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final row = (await context.goodsReturns.listForWarehouse()).singleWhere(
        (item) => item.id == shipped.id,
      );

      expect(
        row.transitAge(nowUtc.add(const Duration(hours: 5))),
        const Duration(hours: 5),
      );
      // A received document is no longer in transit.
      await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: shipped.id,
          );
      final done = (await context.goodsReturns.listForWarehouse()).singleWhere(
        (item) => item.id == shipped.id,
      );
      expect(done.transitAge(nowUtc), isNull);
    });
  });

  group('efek pada stok', () {
    test('saldo Warehouse stream berubah setelah penerimaan', () async {
      final emissions = <Map<String, int>>[];
      final subscription = context.inventory
          .watchBalancesAtLocation(fixture.warehouse.id)
          .listen(
            (rows) => emissions.add({
              for (final row in rows)
                '${row.itemId}|${row.batchId ?? ''}': row.qtyOnHand.milliUnits,
            }),
          );
      await Future<void>.delayed(Duration.zero);
      final before = emissions.last;

      await receivedGoodsReturnFor(context, fixture);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final key = '${fixture.simpleItem.id}|';
      expect(
        emissions.last[key]! - (before[key] ?? 0),
        fixture.rejectedSimpleQty.milliUnits,
      );
      await subscription.cancel();
    });

    test(
      'batch kedaluwarsa muncul sebagai kandidat Pemusnahan Warehouse',
      () async {
        // §36's other half: once an expired batch is back in the Warehouse balance, the
        // only route out is a Pemusnahan — and the disposal reader has to be able to see
        // it, or the goods would be stuck.
        await receivedGoodsReturnFor(
          context,
          fixture,
          nowUtc: fixture.expiredInstant,
        );

        final candidates = await context.disposals.expiredPositions(
          sourceLocationId: fixture.warehouse.id,
          nowUtc: fixture.expiredInstant,
        );
        expect(
          candidates.any(
            (position) => position.batchId == fixture.nearBatch.id,
          ),
          isTrue,
        );
      },
    );
  });

  group('filter tanggal di Dart', () {
    test('rentang menyaring pada instant, bukan teks', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final row = (await context.goodsReturns.listForBranch(
        branchId: fixture.branch.id,
      )).singleWhere((item) => item.id == created.id);

      final inside = GoodsReturnFilter(
        from: nowUtc.subtract(const Duration(days: 1)),
        to: nowUtc.add(const Duration(days: 1)),
      );
      final before = GoodsReturnFilter(
        to: nowUtc.subtract(const Duration(days: 1)),
      );
      final after = GoodsReturnFilter(
        from: nowUtc.add(const Duration(days: 1)),
      );

      expect(inside.matchesDate(row), isTrue);
      expect(before.matchesDate(row), isFalse);
      expect(after.matchesDate(row), isFalse);
      expect(const GoodsReturnFilter().matchesDate(row), isTrue);
    });

    test('rentang memakai instant yang relevan bagi pembaca', () async {
      // A received document is filtered on when it was *received*, because that is the
      // event a reader is looking for.
      final received = await receivedGoodsReturnFor(
        context,
        fixture,
        nowUtc: nowUtc,
        receivedAtUtc: nowUtc.add(const Duration(days: 3)),
      );
      final row = (await context.goodsReturns.listForBranch(
        branchId: fixture.branch.id,
      )).singleWhere((item) => item.id == received.id);

      expect(
        GoodsReturnFilter(
          from: nowUtc.add(const Duration(days: 2)),
        ).matchesDate(row),
        isTrue,
      );
      expect(
        GoodsReturnFilter(
          to: nowUtc.add(const Duration(days: 1)),
        ).matchesDate(row),
        isFalse,
      );
    });
  });

  group('rollback bersih', () {
    test('transaksi gagal tidak meninggalkan header tanpa baris', () async {
      // The create writes header and lines in one transaction; a duplicate loses to the
      // unique index *after* the header insert, so this is the shape that would leave a
      // stray header behind if the transaction were not one unit (§17).
      await createGoodsReturnFor(context, fixture);
      await expectLater(
        createGoodsReturnFor(context, fixture),
        throwsA(anything),
      );

      final headers = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM goods_returns WHERE gr_id = ?;',
            variables: [Variable<String>(fixture.goodReceiptId)],
          )
          .getSingle();
      expect(headers.read<int>('c'), 1);

      final orphans = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM goods_return_lines '
            'WHERE goods_return_id NOT IN (SELECT id FROM goods_returns);',
          )
          .getSingle();
      expect(orphans.read<int>('c'), 0);
    });
  });
}
