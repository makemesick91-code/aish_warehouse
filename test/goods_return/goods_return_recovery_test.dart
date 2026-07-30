import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Historical references, and the line between *inactive* and *gone* (§37).
///
/// The rule this file keeps testing is the one that is easy to get backwards. A
/// reference that has been **deactivated** — a branch closed, an item withdrawn, a
/// batch archived, a user retired — must not stop a document being read, and in one
/// specific case must not stop it being *received* either: the goods are physically at
/// the Warehouse door, and refusing them because the sender has since closed would leave
/// a box with no document. A reference that is **physically gone** is the opposite: the
/// snapshot is verified against it, so without it there is nothing to verify against,
/// and the honest answer is an explicit failure.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('dokumen received tetap terbaca', () {
    test(
      'setelah cabang, barang, batch dan ketiga aktor dinonaktifkan',
      () async {
        final received = await receivedGoodsReturnFor(context, fixture);

        await context.deactivate('branches', fixture.branch.id);
        await context.deactivate('items', fixture.simpleItem.id);
        await context.deactivate('items', fixture.batchItem.id);
        await context.archive('item_batches', fixture.nearBatch.id);
        await context.deactivate('users', fixture.branchHead.id);
        await context.deactivate('users', fixture.warehouseUser.id);

        final detail = await context.goodsReturns.getDetail(received.id);
        expect(detail, isNotNull);
        expect(detail!.lines, hasLength(2));
        expect(detail.status, GoodsReturnStatus.received);
        // Badged rather than hidden — a row that disappeared would be a stock card that
        // does not add up (§37).
        expect(detail.usesHistoricalMaster, isTrue);
        expect(detail.summary.branchIsHistorical, isTrue);
        expect(detail.lines.every((line) => line.itemIsHistorical), isTrue);
        expect(
          detail.lines.singleWhere((line) => line.isBatched).batchIsHistorical,
          isTrue,
        );
        // The names still resolve: the joins filter neither flag.
        expect(detail.summary.createdByName, fixture.branchHead.fullName);
        expect(detail.summary.receivedByName, fixture.warehouseUser.fullName);
      },
    );

    test('tetap muncul di daftar cabang dan riwayat Warehouse', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      await context.deactivate('branches', fixture.branch.id);
      await context.deactivate('items', fixture.simpleItem.id);

      expect(
        (await context.goodsReturns.listForBranch(
          branchId: fixture.branch.id,
        )).map((row) => row.id),
        contains(received.id),
      );
      expect(
        (await context.goodsReturns.listForWarehouse()).map((row) => row.id),
        contains(received.id),
      );
    });

    test('movement retur tetap tampil di kartu stok', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      await context.deactivate('items', fixture.batchItem.id);
      await context.archive('item_batches', fixture.nearBatch.id);
      await context.deactivate('users', fixture.warehouseUser.id);

      final card = await context.inventory.stockCard(
        itemId: fixture.batchItem.id,
        locationId: fixture.warehouse.id,
      );
      expect(
        card.where(
          (movement) =>
              movement.movementType == StockMovementType.itemReturn &&
              movement.refDocId == received.id,
        ),
        hasLength(1),
      );
    });
  });

  group('draft: aktor dan cabang harus aktif untuk mengirim', () {
    test('cabang nonaktif memblokir pengiriman', () async {
      final created = await createGoodsReturnFor(context, fixture);
      await context.deactivate('branches', fixture.branch.id);

      // Shipping is *new* work, and a closed branch is not sending anything (§37).
      // The document itself stays readable.
      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(anything),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
      expect(await context.goodsReturns.getDetail(created.id), isNotNull);
    });

    test('barang nonaktif tidak memblokir pengiriman', () async {
      // The distinction §37 draws: an *inactive* item is master data an administrator
      // withdrew, and the goods are still in the box. Only a *missing* row blocks.
      final created = await createGoodsReturnFor(context, fixture);
      await context.deactivate('items', fixture.simpleItem.id);
      await context.archive('item_batches', fixture.nearBatch.id);

      final shipped = await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: created.id);
      expect(shipped.status, GoodsReturnStatus.shipped);
    });

    test('baris GR yang hilang memberi kegagalan historis eksplisit', () async {
      final created = await createGoodsReturnFor(context, fixture);

      await context.database.customStatement('PRAGMA foreign_keys = OFF;');
      await context.database.customStatement(
        'DELETE FROM good_receipt_lines WHERE id = ?;',
        [fixture.rejectedSimpleLineId],
      );

      // Not an inner-join data loss that quietly shrinks the manifest: the plain id
      // list disagrees with the document, and that is reported (§26).
      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<AppFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
      await context.database.customStatement('PRAGMA foreign_keys = ON;');
    });
  });

  group('shipped: Warehouse tetap dapat menerima', () {
    test('walau cabang pengirim sudah dinonaktifkan', () async {
      // The case §37 is most specific about. The box is at the Warehouse door; refusing
      // it because the branch closed would leave goods with no document at all.
      final shipped = await shippedGoodsReturnFor(context, fixture);
      await context.deactivate('branches', fixture.branch.id);
      await context.deactivate('users', fixture.branchHead.id);

      final received = await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: shipped.id,
          );
      expect(received.status, GoodsReturnStatus.received);
      expect(await context.goodsReturnMovementCount(shipped.id), 2);
    });

    test('walau barang dan batch sudah dinonaktifkan', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      await context.deactivate('items', fixture.simpleItem.id);
      await context.deactivate('items', fixture.batchItem.id);
      await context.archive('item_batches', fixture.nearBatch.id);

      final received = await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: shipped.id,
          );
      expect(received.status, GoodsReturnStatus.received);

      // And the balance really moved: an inactive item still has a shelf.
      final balances = await context.balancesAt(fixture.warehouse.id);
      expect(
        Quantity.fromMilliUnits(
          balances['${fixture.simpleItem.id}|'] ?? 0,
        ).isPositive,
        isTrue,
      );
    });

    test('lokasi Warehouse harus aktif dan tepat satu', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      await context.archive('stock_locations', fixture.warehouse.id);

      // Reading a received document falls back to archived locations; *receiving* is
      // new ledger work and needs a live one (§21/§37).
      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
            ),
        throwsA(isA<GoodsReturnWarehouseLocationNotFoundFailure>()),
      );
      expect(await context.goodsReturnStatusOf(shipped.id), 'shipped');
      expect(await context.goodsReturnMovementCount(shipped.id), 0);
    });
  });

  group('pesan kegagalan', () {
    test('setiap kegagalan Retur punya kalimat Bahasa Indonesia', () {
      // `describeFailure` returns `AppFailure.message` for every sealed subtype, so the
      // presenter mapping is structural rather than a switch that could miss one. What
      // is worth asserting is that the messages are actually written — an empty or
      // English one would pass the type check and fail the user.
      final failures = <AppFailure>[
        const GoodsReturnNotFoundFailure(
          'Dokumen Retur tidak ditemukan.',
          goodsReturnId: 'x',
        ),
        const GoodsReturnAlreadyExistsFailure(
          'Penerimaan Barang ini sudah memiliki dokumen Retur.',
          grId: 'x',
        ),
        const GoodsReturnNotEligibleFailure(
          'Retur hanya dapat dibuat dari Penerimaan Barang yang sudah '
          'diposting.',
          grId: 'x',
        ),
        const GoodsReturnNoRejectedLinesFailure(
          'Tidak ada barang yang ditolak pada Penerimaan Barang ini.',
          grId: 'x',
        ),
        const InvalidGoodsReturnStateFailure(
          'Retur berstatus Draft, sehingga tindakan ini tidak dapat dilakukan.',
          goodsReturnId: 'x',
          currentStatus: GoodsReturnStatus.draft,
        ),
        const GoodsReturnBranchMismatchFailure(
          'Retur ini milik cabang lain.',
          actorUserId: 'x',
          documentBranchId: 'y',
        ),
        const GoodsReturnAccessDeniedFailure(
          'Hanya Kepala Cabang yang dapat membuat dan mengirim Retur.',
          actorUserId: 'x',
        ),
        const GoodsReturnLineIntegrityFailure(
          'Data baris Retur tidak lengkap.',
          goodsReturnId: 'x',
        ),
        const GoodsReturnSnapshotMismatchFailure(
          'Retur ini tidak lagi mencakup seluruh barang yang ditolak.',
          goodsReturnId: 'x',
          grId: 'y',
        ),
        GoodsReturnQuantityMismatchFailure(
          'Kuantitas retur tidak lagi sama dengan kuantitas kirim.',
          goodsReturnId: 'x',
          grLineId: 'y',
          expected: Quantity.parse('1'),
          actual: Quantity.parse('2'),
        ),
        const GoodsReturnRejectReasonMissingFailure(
          'Baris penolakan tanpa alasan tidak dapat diretur.',
          grLineId: 'x',
        ),
        const GoodsReturnItemBatchMismatchFailure(
          'Barang atau batch pada Retur ini tidak lagi sama.',
          itemId: 'x',
        ),
        const GoodsReturnWarehouseLocationNotFoundFailure(
          'Lokasi Warehouse Pusat tidak ditemukan.',
        ),
        const GoodsReturnWarehouseLocationAmbiguousFailure(
          'Terdapat lebih dari satu lokasi Warehouse Pusat.',
          locationIds: ['a', 'b'],
        ),
        const GoodsReturnSegregationOfDutiesFailure(
          'Retur ini dibuat oleh akun ini.',
          goodsReturnId: 'x',
          actorUserId: 'y',
          createdBy: 'y',
        ),
        const GoodsReturnAlreadyShippedFailure(
          'Retur sudah dikirim ke Warehouse.',
          goodsReturnId: 'x',
        ),
        const GoodsReturnAlreadyReceivedFailure(
          'Retur sudah diterima Warehouse.',
          goodsReturnId: 'x',
        ),
        const ConcurrentGoodsReturnUpdateFailure(
          'Retur sudah berubah di perangkat lain.',
          goodsReturnId: 'x',
        ),
        const HistoricalGoodsReturnReferenceMissingFailure(
          'Dokumen Penerimaan Barang asalnya tidak ditemukan.',
          entity: 'good_receipts',
          id: 'x',
        ),
        InvalidGoodsReturnTimestampFailure(
          'Waktu perangkat lebih awal dari waktu pengiriman dokumen.',
          goodsReturnId: 'x',
          earlierLabel: 'shipped_at',
          earlierUtc: nowUtc,
          laterLabel: 'received_at',
          laterUtc: nowUtc,
        ),
      ];

      for (final failure in failures) {
        final message = describeFailure(failure);
        expect(message, failure.message);
        expect(message.trim(), isNotEmpty);
        expect(
          message.endsWith('.'),
          isTrue,
          reason: '${failure.runtimeType} tidak diakhiri titik: "$message"',
        );
        // No raw exception text, no stack trace, no English fallback.
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('#0')));
        expect(
          message,
          isNot('Terjadi kesalahan tak terduga. Silakan coba lagi.'),
        );
      }
    });

    test('kegagalan nyata dari use case juga terbaca', () async {
      await createGoodsReturnFor(context, fixture);
      try {
        await createGoodsReturnFor(context, fixture);
        fail('Pembuatan kedua seharusnya ditolak.');
      } catch (error) {
        final message = describeFailure(error);
        expect(message, contains('sudah memiliki dokumen Retur'));
        expect(
          error,
          isA<GoodsReturnAlreadyExistsFailure>().having(
            (failure) => failure.existingGoodsReturnId,
            'existingGoodsReturnId',
            isNotNull,
          ),
        );
      }
    });
  });
}
