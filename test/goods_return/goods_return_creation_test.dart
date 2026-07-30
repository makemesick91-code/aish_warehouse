import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/goods_return/domain/models/goods_return_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Eligibility and creation (§16/§17/§42).
///
/// G-G5 — *"Barang rejected masuk daftar retur ke Warehouse"* — is the sentence this
/// whole file is about, and the two halves of it that matter most are which receipts
/// qualify and what a qualifying one produces. The rule the tests keep returning to is
/// the one §16.10 draws: a **rejection** is goods that arrived and were refused and are
/// physically at the branch, while a **shortage** is a quantity that never arrived at
/// all. Only the first has a box to send back.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('kelayakan Penerimaan Barang', () {
    test('GR posted dengan baris rejected muncul di antrean', () async {
      final eligible = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );

      final row = eligible.singleWhere(
        (item) => item.grId == fixture.goodReceiptId,
      );
      expect(row.canCreateReturn, isTrue);
      expect(row.rejectedLineCount, 2);
      expect(row.hasReturn, isFalse);
      // The whole chain travels with the row, so the queue can be read without a
      // second query (§29).
      expect(row.doDocNumber, isNotEmpty);
      expect(row.prDocNumber, isNotEmpty);
      expect(row.branchId, fixture.branch.id);
    });

    test('baris shortage tidak ikut ke antrean retur', () async {
      final eligible = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );
      final row = eligible.singleWhere(
        (item) => item.grId == fixture.goodReceiptId,
      );

      // The receipt has three lines; only the two rejections are returnable. A
      // shortage is a delivery discrepancy, not goods coming back (§16.10).
      expect(row.positions.length, 2);
      expect(
        row.positions.map((position) => position.grLineId).toSet(),
        fixture.rejectedLineIds,
      );
      expect(
        row.positions.any(
          (position) => position.grLineId == fixture.shortageLineId,
        ),
        isFalse,
        reason: 'Selisih kirim bukan barang yang dikembalikan.',
      );
    });

    test('GR tanpa baris rejected tidak muncul', () async {
      final eligible = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );

      expect(
        eligible.any((item) => item.grId == fixture.cleanGoodReceiptId),
        isFalse,
      );
    });

    test('GR yang masih checking tidak muncul', () async {
      final eligible = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );

      expect(
        eligible.any((item) => item.grId == fixture.checkingGoodReceiptId),
        isFalse,
        reason:
            'Keputusan pada GR yang masih diperiksa dapat direvisi, sehingga '
            'belum boleh diretur.',
      );
    });

    test('GR cabang lain tidak muncul di antrean cabang ini', () async {
      final eligible = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );

      expect(
        eligible.any((item) => item.grId == fixture.otherBranchGoodReceiptId),
        isFalse,
      );
    });

    test('antrean urut dari posting terlama', () async {
      final eligible = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );

      // Ordering is on parsed UTC instants, never on the ISO-8601 TEXT column (§39).
      final postedAts = eligible
          .map((item) => item.grPostedAt)
          .whereType<DateTime>()
          .toList(growable: false);
      for (var i = 1; i < postedAts.length; i++) {
        expect(
          postedAts[i].isBefore(postedAts[i - 1]),
          isFalse,
          reason: 'Antrean tidak urut dari posting terlama.',
        );
      }
    });

    test('setelah retur dibuat, GR keluar dari antrean Perlu Dibuat', () async {
      await createGoodsReturnFor(context, fixture);

      final eligible = await context.goodsReturns.eligibleGoodReceiptsForBranch(
        branchId: fixture.branch.id,
      );
      final row = eligible.singleWhere(
        (item) => item.grId == fixture.goodReceiptId,
      );

      // The row is still *returned* by the query, carrying the document — §33 needs it
      // so the discrepancy page can show a status — but it is no longer creatable.
      expect(row.canCreateReturn, isFalse);
      expect(row.hasReturn, isTrue);
      expect(row.existingReturnStatus, GoodsReturnStatus.draft);
    });
  });

  group('pembuatan', () {
    test('Kepala Cabang membuat retur dari GR cabangnya', () async {
      final created = await createGoodsReturnFor(context, fixture);

      expect(created.status, GoodsReturnStatus.draft);
      expect(created.grId, fixture.goodReceiptId);
      expect(created.branchId, fixture.branch.id);
      expect(created.createdBy, fixture.branchHead.id);
      expect(created.shippedAt, isNull);
      expect(created.shippedBy, isNull);
      expect(created.receivedAt, isNull);
      expect(created.receivedBy, isNull);
      expect(created.warehouseNote, isNull);
      // Local numbering only: a server-shaped `RET-{cabang}-{date}-{seq}` would collide
      // across devices (G-Y4).
      expect(created.docNumber, startsWith('TMP-RET-'));
      expect(created.syncStatus, SyncStatus.pending);
    });

    test(
      'seluruh baris rejected disnapshot, tidak kurang tidak lebih',
      () async {
        final created = await createGoodsReturnFor(context, fixture);

        final rows = await context.goodsReturnLineRows(created.id);
        expect(rows.keys.toSet(), fixture.rejectedLineIds);
        expect(rows.length, 2);
      },
    );

    test('qty snapshot sama persis dengan shipped_qty baris GR', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final rows = await context.goodsReturnLineRows(created.id);

      expect(
        rows[fixture.rejectedSimpleLineId]!['qty'],
        fixture.rejectedSimpleQty.milliUnits,
      );
      expect(
        rows[fixture.rejectedBatchLineId]!['qty'],
        fixture.rejectedBatchQty.milliUnits,
      );
    });

    test('received_qty baris rejected memang nol', () async {
      // The premise the quantity rule rests on: a rejection accepted nothing, so
      // sending the whole shipped quantity back returns exactly what is at the branch
      // (§18).
      final rows = await context.goodReceiptLineRows(fixture.goodReceiptId);
      for (final lineId in fixture.rejectedLineIds) {
        expect(rows[lineId]!['received_qty'], 0);
      }
    });

    test('alasan penolakan disnapshot apa adanya', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final rows = await context.goodsReturnLineRows(created.id);

      expect(
        rows[fixture.rejectedSimpleLineId]!['reject_reason_snapshot'],
        'Kemasan rusak saat diterima',
      );
      expect(
        rows[fixture.rejectedBatchLineId]!['reject_reason_snapshot'],
        'Sisa umur simpan terlalu pendek',
      );
    });

    test(
      'item dan batch snapshot benar, batch null untuk non-expiry',
      () async {
        final created = await createGoodsReturnFor(context, fixture);
        final rows = await context.goodsReturnLineRows(created.id);

        final simple = rows[fixture.rejectedSimpleLineId]!;
        expect(simple['item_id'], fixture.simpleItem.id);
        expect(
          simple['batch_id'],
          isNull,
          reason: 'Barang tanpa expiry tidak boleh menyimpan batch (G-E2).',
        );

        final batched = rows[fixture.rejectedBatchLineId]!;
        expect(batched['item_id'], fixture.batchItem.id);
        expect(batched['batch_id'], fixture.nearBatch.id);
      },
    );

    test('batch near-expiry boleh diretur', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final detail = await context.goodsReturns.getDetail(created.id);

      final line = detail!.lines.singleWhere(
        (line) => line.grLineId == fixture.rejectedBatchLineId,
      );
      expect(line.isNearExpiry(nowUtc), isTrue);
      expect(line.isExpired(nowUtc), isFalse);
    });

    test('batch yang sudah kedaluwarsa tetap boleh diretur', () async {
      // Forty days on, `nearBatch` is past its date. G-E5 makes that a legitimate
      // reason to have rejected the delivery, so the goods must still be able to go
      // home (§36).
      final created = await createGoodsReturnFor(
        context,
        fixture,
        nowUtc: fixture.expiredInstant,
      );

      final detail = await context.goodsReturns.getDetail(created.id);
      final line = detail!.lines.singleWhere(
        (line) => line.grLineId == fixture.rejectedBatchLineId,
      );
      expect(line.isExpired(fixture.expiredInstant), isTrue);
      expect(await context.goodsReturnLineCount(created.id), 2);
    });

    test('catatan opsional tersimpan, spasi saja ditolak', () async {
      final created = await createGoodsReturnFor(
        context,
        fixture,
        note: '  Dikirim via kurir internal  ',
      );
      expect(created.note, 'Dikirim via kurir internal');

      await expectLater(
        createGoodsReturnFor(
          context,
          fixture,
          goodReceiptId: fixture.cleanGoodReceiptId,
          note: '   ',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('penolakan pembuatan', () {
    test('GR masih checking ditolak', () async {
      await expectLater(
        createGoodsReturnFor(
          context,
          fixture,
          goodReceiptId: fixture.checkingGoodReceiptId,
        ),
        throwsA(isA<GoodsReturnNotEligibleFailure>()),
      );
      expect(
        await context.goodsReturnCountFor(fixture.checkingGoodReceiptId),
        0,
      );
    });

    test('GR tanpa baris rejected ditolak', () async {
      await expectLater(
        createGoodsReturnFor(
          context,
          fixture,
          goodReceiptId: fixture.cleanGoodReceiptId,
        ),
        throwsA(isA<GoodsReturnNoRejectedLinesFailure>()),
      );
      expect(await context.goodsReturnCountFor(fixture.cleanGoodReceiptId), 0);
    });

    test('GR cabang lain ditolak', () async {
      await expectLater(
        createGoodsReturnFor(
          context,
          fixture,
          goodReceiptId: fixture.otherBranchGoodReceiptId,
        ),
        throwsA(isA<GoodsReturnNotEligibleFailure>()),
      );
      expect(
        await context.goodsReturnCountFor(fixture.otherBranchGoodReceiptId),
        0,
      );
    });

    test('GR tidak dikenal ditolak', () async {
      await expectLater(
        createGoodsReturnFor(
          context,
          fixture,
          goodReceiptId: 'gr-yang-tidak-ada',
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });

    test('satu GR hanya boleh punya satu retur', () async {
      await createGoodsReturnFor(context, fixture);

      await expectLater(
        createGoodsReturnFor(context, fixture),
        throwsA(isA<GoodsReturnAlreadyExistsFailure>()),
      );
      expect(await context.goodsReturnCountFor(fixture.goodReceiptId), 1);
    });

    test('kegagalan duplikat menyebut dokumen yang sudah ada', () async {
      final first = await createGoodsReturnFor(context, fixture);

      // The UI turns this into *"Lihat Retur"* rather than a dead end (§30).
      await expectLater(
        createGoodsReturnFor(context, fixture),
        throwsA(
          isA<GoodsReturnAlreadyExistsFailure>().having(
            (failure) => failure.existingGoodsReturnId,
            'existingGoodsReturnId',
            first.id,
          ),
        ),
      );
    });

    test('soft delete tidak membebaskan slot gr_id', () async {
      final first = await createGoodsReturnFor(context, fixture);
      // Nothing in the application can do this — there is no soft-delete writer (§24) —
      // so it is forced here to prove the *index* is unqualified rather than the use
      // case merely being careful.
      await context.database.customStatement(
        'UPDATE goods_returns SET deleted_at = ? WHERE id = ?;',
        [nowUtc.toIso8601String(), first.id],
      );

      await expectLater(
        createGoodsReturnFor(context, fixture),
        throwsA(anything),
      );
      expect(
        await context.goodsReturnCountFor(fixture.goodReceiptId),
        1,
        reason:
            'Index unik gr_id harus absolut: retur kedua akan menambah saldo '
            'Warehouse dua kali untuk satu pengiriman.',
      );
    });
  });

  group('pembuatan bersamaan', () {
    test('dua pembuatan serentak menghasilkan tepat satu dokumen', () async {
      final results = await Future.wait([
        createGoodsReturnFor(
          context,
          fixture,
        ).then<Object?>((value) => value, onError: (Object error) => error),
        createGoodsReturnFor(
          context,
          fixture,
        ).then<Object?>((value) => value, onError: (Object error) => error),
      ]);

      final succeeded = results.whereType<GoodsReturn>().length;
      expect(succeeded, 1, reason: 'Tepat satu pembuatan boleh berhasil.');
      expect(await context.goodsReturnCountFor(fixture.goodReceiptId), 1);

      // And nothing partial survived: the loser's header and lines share one
      // transaction (§17).
      final id = results.whereType<GoodsReturn>().single.id;
      expect(await context.goodsReturnLineCount(id), 2);
      final orphans = await context.database
          .customSelect(
            'SELECT COUNT(*) AS c FROM goods_return_lines '
            'WHERE goods_return_id NOT IN (SELECT id FROM goods_returns);',
          )
          .getSingle();
      expect(orphans.read<int>('c'), 0);
    });
  });

  group('efek samping pembuatan', () {
    test('tidak ada movement dan saldo yang berubah', () async {
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      final branchBefore = await context.balancesAt(fixture.branchStore.id);
      final movementsBefore = await context.totalMovementCount();

      final created = await createGoodsReturnFor(context, fixture);

      expect(await context.goodsReturnMovementCount(created.id), 0);
      expect(await context.totalMovementCount(), movementsBefore);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
      expect(await context.balancesAt(fixture.branchStore.id), branchBefore);
    });

    test('GR, DO dan PR tidak berubah', () async {
      final grBefore = await context.goodReceiptLineRows(fixture.goodReceiptId);
      final grStatus = await context.goodReceiptStatusOf(fixture.goodReceiptId);
      final doStatus = await context.deliveryOrderStatusOf(
        fixture.deliveryOrderId,
      );

      await createGoodsReturnFor(context, fixture);

      expect(
        await context.goodReceiptLineRows(fixture.goodReceiptId),
        grBefore,
      );
      expect(
        await context.goodReceiptStatusOf(fixture.goodReceiptId),
        grStatus,
      );
      expect(
        await context.deliveryOrderStatusOf(fixture.deliveryOrderId),
        doStatus,
      );
    });

    test(
      'total per unit dihitung dari posisi, bukan satu angka gabungan',
      () async {
        final created = await createGoodsReturnFor(context, fixture);
        final detail = await context.goodsReturns.getDetail(created.id);

        // `box` and `ampul` never add together — §29 asks for totals per unit.
        expect(detail!.totalQuantityByUnit.keys.toSet(), {
          fixture.simpleItem.unit,
          fixture.batchItem.unit,
        });
        expect(
          detail.totalQuantityByUnit[fixture.simpleItem.unit],
          fixture.rejectedSimpleQty,
        );
        expect(
          detail.totalQuantityByUnit[fixture.batchItem.unit],
          fixture.rejectedBatchQty,
        );
        expect(
          detail.progress.totalQty,
          Quantity.sum([fixture.rejectedSimpleQty, fixture.rejectedBatchQty]),
        );
      },
    );
  });
}
