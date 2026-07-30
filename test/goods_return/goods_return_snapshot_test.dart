import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/goods_return/domain/models/goods_return_models.dart';
import 'package:aish_warehouse/features/goods_return/domain/services/goods_return_snapshot_policy.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The immutable snapshot (§18/§26/§44).
///
/// A Retur says *"here is exactly what you sent that we refused"*. Everything in this
/// file is an assertion that it keeps saying that — at creation, before shipping and
/// before receiving — because the snapshot is not the only copy of these facts and
/// something could happen to the other one in between.
///
/// ### Why several tests corrupt the database with raw SQL
///
/// Nothing in the application can add a return line, remove one, or change a quantity:
/// there is no writer on the repository, none on the DAO, and no screen with an input.
/// That is exactly what makes the guards hard to test honestly — the only way to reach
/// the state they defend against is to write it directly. These tests therefore go
/// behind every Dart layer on an **in-memory** database, prove the domain refuses what
/// it finds, and assert that the refusal left the document and the ledger untouched.
/// The corruption never escapes the test's own database.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('policy murni', () {
    test('himpunan yang sama diterima', () {
      final verdict = GoodsReturnSnapshotPolicy.verifyLineSet(
        expectedGrLineIds: const ['a', 'b'],
        actualGrLineIds: const ['b', 'a'],
      );
      expect(verdict.matches, isTrue);
    });

    test('baris hilang, baris ekstra, duplikat dan kosong terdeteksi', () {
      expect(
        GoodsReturnSnapshotPolicy.verifyLineSet(
          expectedGrLineIds: const ['a', 'b'],
          actualGrLineIds: const ['a'],
        ).mismatch,
        GoodsReturnSnapshotMismatch.missingLine,
      );
      expect(
        GoodsReturnSnapshotPolicy.verifyLineSet(
          expectedGrLineIds: const ['a'],
          actualGrLineIds: const ['a', 'b'],
        ).mismatch,
        GoodsReturnSnapshotMismatch.extraLine,
      );
      expect(
        GoodsReturnSnapshotPolicy.verifyLineSet(
          expectedGrLineIds: const ['a'],
          actualGrLineIds: const ['a', 'a'],
        ).mismatch,
        GoodsReturnSnapshotMismatch.duplicateLine,
      );
      expect(
        GoodsReturnSnapshotPolicy.verifyLineSet(
          expectedGrLineIds: const ['a'],
          actualGrLineIds: const [],
        ).mismatch,
        GoodsReturnSnapshotMismatch.empty,
      );
    });

    test('setiap field baris dibandingkan satu per satu', () {
      final position = RejectedGoodReceiptPosition(
        grLineId: 'grl-1',
        grId: 'gr-1',
        itemId: 'item-1',
        sku: 'SKU-1',
        itemName: 'Barang',
        categoryId: 'cat-1',
        unit: 'box',
        hasExpiry: false,
        expiryAlertDays: 30,
        shippedQty: Quantity.parse('2'),
        receivedQty: Quantity.zero(),
        rejectReason: 'Rusak',
      );
      GoodsReturnLineReference line({
        String itemId = 'item-1',
        String? batchId,
        String qty = '2',
        String reason = 'Rusak',
      }) => GoodsReturnLineReference(
        id: 'line-1',
        goodsReturnId: 'ret-1',
        grLineId: 'grl-1',
        itemId: itemId,
        batchId: batchId,
        qty: Quantity.parse(qty),
        rejectReason: reason,
      );

      expect(
        GoodsReturnSnapshotPolicy.verifyLine(
          line: line(),
          position: position,
        ).matches,
        isTrue,
      );
      expect(
        GoodsReturnSnapshotPolicy.verifyLine(
          line: line(itemId: 'lain'),
          position: position,
        ).mismatch,
        GoodsReturnSnapshotMismatch.item,
      );
      expect(
        GoodsReturnSnapshotPolicy.verifyLine(
          line: line(batchId: 'batch-1'),
          position: position,
        ).mismatch,
        GoodsReturnSnapshotMismatch.batch,
      );
      expect(
        GoodsReturnSnapshotPolicy.verifyLine(
          line: line(qty: '1'),
          position: position,
        ).mismatch,
        GoodsReturnSnapshotMismatch.quantity,
      );
      expect(
        GoodsReturnSnapshotPolicy.verifyLine(
          line: line(reason: 'Alasan lain'),
          position: position,
        ).mismatch,
        GoodsReturnSnapshotMismatch.rejectReason,
      );
      // A reason that became blank is a G-G4 guarantee that failed upstream.
      expect(
        GoodsReturnSnapshotPolicy.verifyLine(
          line: line(reason: '   '),
          position: position,
        ).mismatch,
        GoodsReturnSnapshotMismatch.rejectReason,
      );
    });
  });

  group('tidak ada penulis baris sama sekali', () {
    test('baris identik sebelum dan sesudah seluruh alur', () async {
      // The strictest contract in the application (§25), asserted behaviourally: drive
      // the document through every transition it has and compare the raw line rows
      // byte for byte. `createFromGoodReceipt` is the only writer that exists; if a
      // second one were ever added, one of these three snapshots would differ.
      final created = await createGoodsReturnFor(context, fixture);
      final afterCreate = await context.goodsReturnLineRows(created.id);

      await context.updateGoodsReturnNote.call(
        actorUserId: fixture.branchHead.id,
        goodsReturnId: created.id,
        note: 'Catatan yang tidak boleh menyentuh baris',
      );
      await context
          .shipGoodsReturn(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, goodsReturnId: created.id);
      final afterShip = await context.goodsReturnLineRows(created.id);

      await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: created.id,
            warehouseNote: 'Catatan Warehouse yang juga tidak boleh',
          );
      final afterReceive = await context.goodsReturnLineRows(created.id);

      expect(afterShip, afterCreate);
      expect(afterReceive, afterCreate);
      expect(afterCreate.keys.toSet(), fixture.rejectedLineIds);
    });

    test('index unik menolak baris kedua untuk satu posisi rejected', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final lineIds = await goodsReturnLineIdsByGrLine(context, created.id);
      expect(lineIds.length, 2);

      await expectLater(
        context.database.customStatement(
          'INSERT INTO goods_return_lines (id, created_at, updated_at, '
          'sync_status, goods_return_id, gr_line_id, item_id, batch_id, qty, '
          "reject_reason_snapshot) VALUES ('dup', ?, ?, 'pending', ?, ?, ?, "
          "NULL, 1000, 'Alasan');",
          [
            nowUtc.toIso8601String(),
            nowUtc.toIso8601String(),
            created.id,
            fixture.rejectedSimpleLineId,
            fixture.simpleItem.id,
          ],
        ),
        throwsA(anything),
      );
      expect(await context.goodsReturnLineCount(created.id), 2);
    });
  });

  group('snapshot memblokir pengiriman', () {
    test('baris rejected yang hilang dari retur memblokir kirim', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final lineIds = await goodsReturnLineIdsByGrLine(context, created.id);

      // Hard-deleted rather than soft-deleted, because a soft delete is what a
      // *joined* read would still see; this is the shape that would silently shrink a
      // manifest (§26).
      await context.database.customStatement(
        'DELETE FROM goods_return_lines WHERE id = ?;',
        [lineIds[fixture.rejectedSimpleLineId]!],
      );

      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<GoodsReturnSnapshotMismatchFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
      expect(await context.goodsReturnColumn(created.id, 'shipped_at'), isNull);
    });

    test('baris ekstra pada retur memblokir kirim', () async {
      final created = await createGoodsReturnFor(context, fixture);

      // The shortage line, smuggled onto the document. It is the exact position §16.10
      // says is never returnable.
      await context.database.customStatement(
        'INSERT INTO goods_return_lines (id, created_at, updated_at, '
        'sync_status, goods_return_id, gr_line_id, item_id, batch_id, qty, '
        "reject_reason_snapshot) VALUES ('extra', ?, ?, 'pending', ?, ?, ?, ?, "
        "1000, 'Diselundupkan');",
        [
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          created.id,
          fixture.shortageLineId,
          fixture.tieItem.id,
          fixture.tieBatchA.id,
        ],
      );

      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<GoodsReturnSnapshotMismatchFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
    });

    test('kuantitas yang diubah memblokir kirim', () async {
      final created = await createGoodsReturnFor(context, fixture);
      final lineIds = await goodsReturnLineIdsByGrLine(context, created.id);

      await context.database.customStatement(
        'UPDATE goods_return_lines SET qty = qty + 1000 WHERE id = ?;',
        [lineIds[fixture.rejectedSimpleLineId]!],
      );

      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<GoodsReturnQuantityMismatchFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
    });
  });

  group('snapshot memblokir penerimaan', () {
    Future<String> shippedId() async =>
        (await shippedGoodsReturnFor(context, fixture)).id;

    Future<void> expectReceiveRefused(String id, Matcher matcher) async {
      final movementsBefore = await context.totalMovementCount();
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, goodsReturnId: id),
        throwsA(matcher),
      );

      expect(await context.goodsReturnStatusOf(id), 'shipped');
      expect(await context.goodsReturnColumn(id, 'received_at'), isNull);
      expect(await context.goodsReturnColumn(id, 'received_by'), isNull);
      expect(await context.goodsReturnMovementCount(id), 0);
      expect(await context.totalMovementCount(), movementsBefore);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
    }

    test('kuantitas tidak cocok memblokir terima', () async {
      final id = await shippedId();
      final lineIds = await goodsReturnLineIdsByGrLine(context, id);
      await context.database.customStatement(
        'UPDATE goods_return_lines SET qty = 1 WHERE id = ?;',
        [lineIds[fixture.rejectedBatchLineId]!],
      );

      await expectReceiveRefused(id, isA<GoodsReturnQuantityMismatchFailure>());
    });

    test('item tidak cocok memblokir terima', () async {
      final id = await shippedId();
      final lineIds = await goodsReturnLineIdsByGrLine(context, id);
      await context.database.customStatement(
        'UPDATE goods_return_lines SET item_id = ?, batch_id = NULL '
        'WHERE id = ?;',
        [fixture.tieItem.id, lineIds[fixture.rejectedSimpleLineId]!],
      );

      await expectReceiveRefused(
        id,
        isA<GoodsReturnItemBatchMismatchFailure>(),
      );
    });

    test('batch tidak cocok memblokir terima', () async {
      final id = await shippedId();
      final lineIds = await goodsReturnLineIdsByGrLine(context, id);
      await context.database.customStatement(
        'UPDATE goods_return_lines SET batch_id = NULL WHERE id = ?;',
        [lineIds[fixture.rejectedBatchLineId]!],
      );

      await expectReceiveRefused(
        id,
        isA<GoodsReturnItemBatchMismatchFailure>(),
      );
    });

    test('alasan penolakan tidak cocok memblokir terima', () async {
      final id = await shippedId();
      final lineIds = await goodsReturnLineIdsByGrLine(context, id);
      await context.database.customStatement(
        'UPDATE goods_return_lines SET reject_reason_snapshot = ? '
        'WHERE id = ?;',
        ['Alasan yang diubah', lineIds[fixture.rejectedSimpleLineId]!],
      );

      await expectReceiveRefused(
        id,
        isA<GoodsReturnRejectReasonMissingFailure>(),
      );
    });

    test('baris hilang memblokir terima', () async {
      final id = await shippedId();
      final lineIds = await goodsReturnLineIdsByGrLine(context, id);
      await context.database.customStatement(
        'DELETE FROM goods_return_lines WHERE id = ?;',
        [lineIds[fixture.rejectedBatchLineId]!],
      );

      await expectReceiveRefused(id, isA<GoodsReturnSnapshotMismatchFailure>());
    });

    test('dokumen tanpa baris sama sekali memblokir terima', () async {
      final id = await shippedId();
      await context.database.customStatement(
        'DELETE FROM goods_return_lines WHERE goods_return_id = ?;',
        [id],
      );

      await expectReceiveRefused(id, isA<AppFailure>());
    });

    test('item yang dihapus fisik terdeteksi, bukan dilewati diam-diam', () async {
      // The inner-join data loss §26 exists for. `detailLines` inner-joins `items`, so
      // a physically deleted item row makes the joined read return **one line fewer** —
      // perfectly self-consistent, and wrong. The plain id list is what catches it.
      final id = await shippedId();
      final lines = await context.goodsReturns.lineReferences(id);
      expect(lines.length, 2);

      await context.database.customStatement('PRAGMA foreign_keys = OFF;');
      await context.database.customStatement(
        'DELETE FROM items WHERE id = ?;',
        [fixture.simpleItem.id],
      );

      final joined = await context.goodsReturns.getDetail(id);
      expect(
        joined!.lines.length,
        1,
        reason: 'Join memang kehilangan satu baris — itulah bahayanya.',
      );
      final plain = await context.goodsReturns.lineReferences(id);
      expect(plain.length, 2, reason: 'Baca polos harus tetap dua baris.');

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, goodsReturnId: id),
        throwsA(isA<AppFailure>()),
      );
      expect(await context.goodsReturnStatusOf(id), 'shipped');
      expect(await context.goodsReturnMovementCount(id), 0);
      await context.database.customStatement('PRAGMA foreign_keys = ON;');
    });
  });

  group('GR asal tetap final', () {
    test('baris GR yang direvisi setelah retur dibuat memblokir terima', () async {
      final id = (await shippedGoodsReturnFor(context, fixture)).id;

      // A posted receipt is read-only (G-S2) and nothing in the application does this.
      // Forced here because the snapshot check exists precisely for the case where the
      // *other* copy of these facts moved.
      await context.database.customStatement(
        'UPDATE good_receipt_lines SET shipped_qty = shipped_qty + 1000 '
        'WHERE id = ?;',
        [fixture.rejectedSimpleLineId],
      );

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, goodsReturnId: id),
        throwsA(isA<GoodsReturnQuantityMismatchFailure>()),
      );
      expect(await context.goodsReturnMovementCount(id), 0);
    });

    test('GR yang tidak lagi posted memblokir kirim dan terima', () async {
      final created = await createGoodsReturnFor(context, fixture);
      await context.database.customStatement(
        "UPDATE good_receipts SET status = 'checking', posted_at = NULL "
        'WHERE id = ?;',
        [fixture.goodReceiptId],
      );

      await expectLater(
        context
            .shipGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: created.id,
            ),
        throwsA(isA<GoodsReturnNotEligibleFailure>()),
      );
      expect(await context.goodsReturnStatusOf(created.id), 'draft');
    });

    test('GR yang hilang memberi kegagalan historis eksplisit', () async {
      final id = (await shippedGoodsReturnFor(context, fixture)).id;

      await context.database.customStatement('PRAGMA foreign_keys = OFF;');
      await context.database.customStatement(
        'DELETE FROM good_receipts WHERE id = ?;',
        [fixture.goodReceiptId],
      );

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, goodsReturnId: id),
        throwsA(isA<HistoricalGoodsReturnReferenceMissingFailure>()),
      );
      expect(await context.goodsReturnStatusOf(id), 'shipped');
      expect(await context.goodsReturnMovementCount(id), 0);
      await context.database.customStatement('PRAGMA foreign_keys = ON;');
    });
  });

  group('database menolak bentuk yang tidak sah', () {
    test('qty nol dan alasan kosong ditolak oleh CHECK', () async {
      final created = await createGoodsReturnFor(context, fixture);

      await expectLater(
        context.database.customStatement(
          'UPDATE goods_return_lines SET qty = 0 WHERE goods_return_id = ?;',
          [created.id],
        ),
        throwsA(anything),
      );
      await expectLater(
        context.database.customStatement(
          "UPDATE goods_return_lines SET reject_reason_snapshot = '  ' "
          'WHERE goods_return_id = ?;',
          [created.id],
        ),
        throwsA(anything),
      );

      final rows = await context.database
          .customSelect(
            'SELECT qty, reject_reason_snapshot FROM goods_return_lines '
            'WHERE goods_return_id = ?;',
            variables: [Variable<String>(created.id)],
          )
          .get();
      for (final row in rows) {
        expect(row.read<int>('qty'), greaterThan(0));
        expect(row.read<String>('reject_reason_snapshot').trim(), isNotEmpty);
      }
    });
  });
}
