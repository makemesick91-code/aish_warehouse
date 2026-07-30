import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/inventory/domain/services/stock_posting_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_inventory_repository.dart';
import '../helpers/test_context.dart';

/// Atomicity of the receive transaction (§21/§46).
///
/// The receive is the only place in this milestone that writes to the ledger, and it
/// writes several rows: one movement and one balance increment per returned position,
/// then the status, the timestamp, the receiving actor and the Warehouse note. All of
/// it commits together or none of it does.
///
/// Every test here asserts the **same six facts** after a failure, through
/// [expectNothingHappened], because a partial receive is not one kind of bug — it is
/// six of them, and a test that checked only the movement count would pass while the
/// document sat in `received` with half a ledger behind it.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A posting service whose ledger writes fail on a chosen movement.
  ///
  /// The failure lands *inside* `postGoodsReturnLinesInTransaction`, after earlier
  /// positions have already written movements and increased balances — so if the
  /// receive were not one unit of work, those earlier writes would survive.
  StockPostingService failingPosting({
    String? failOnItemId,
    int? failAfterAppends,
  }) => context.postingWith(
    inventory: FailingInventoryRepository(
      context.inventory,
      failOnItemId: failOnItemId,
      failAfterAppends: failAfterAppends,
    ),
    clock: () => nowUtc,
  );

  Future<void> expectNothingHappened(String id) async {
    expect(await context.goodsReturnStatusOf(id), 'shipped');
    expect(await context.goodsReturnColumn(id, 'received_at'), isNull);
    expect(await context.goodsReturnColumn(id, 'received_by'), isNull);
    expect(await context.goodsReturnColumn(id, 'warehouse_note'), isNull);
    expect(await context.goodsReturnMovementCount(id), 0);
    expect(await context.goodsReturnLineCount(id), 2);
  }

  group('kegagalan ledger', () {
    test('gagal pada movement pertama tidak menulis apa pun', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      final movementsBefore = await context.totalMovementCount();

      await expectLater(
        context
            .receiveGoodsReturn(
              clock: () => nowUtc,
              posting: failingPosting(failAfterAppends: 0),
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
              warehouseNote: 'Tidak boleh tersimpan',
            ),
        throwsA(isA<ValidationFailure>()),
      );

      await expectNothingHappened(shipped.id);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
      expect(await context.totalMovementCount(), movementsBefore);
    });

    test('gagal pada movement terakhir membatalkan yang pertama', () async {
      // The assertion the whole transaction exists for: the first position's movement
      // and balance increase are already written when the second one throws.
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      final movementsBefore = await context.totalMovementCount();

      await expectLater(
        context
            .receiveGoodsReturn(
              clock: () => nowUtc,
              posting: failingPosting(failAfterAppends: 1),
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
            ),
        throwsA(isA<ValidationFailure>()),
      );

      await expectNothingHappened(shipped.id);
      expect(
        await context.balancesAt(fixture.warehouse.id),
        warehouseBefore,
        reason:
            'Saldo posisi pertama sudah dinaikkan sebelum baris kedua gagal; '
            'rollback harus mengembalikannya.',
      );
      expect(await context.totalMovementCount(), movementsBefore);
    });

    test('gagal pada satu item tertentu membatalkan seluruhnya', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);

      await expectLater(
        context
            .receiveGoodsReturn(
              clock: () => nowUtc,
              posting: failingPosting(failOnItemId: fixture.batchItem.id),
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
            ),
        throwsA(isA<ValidationFailure>()),
      );

      await expectNothingHappened(shipped.id);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
    });
  });

  group('kegagalan validasi sebelum ledger', () {
    Future<void> expectRefused(String id, Matcher matcher) async {
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      final movementsBefore = await context.totalMovementCount();

      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: id,
              warehouseNote: 'Tidak boleh tersimpan',
            ),
        throwsA(matcher),
      );

      await expectNothingHappened(id);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
      expect(await context.totalMovementCount(), movementsBefore);
    }

    test('batch yang hilang membatalkan penerimaan', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      await context.database.customStatement('PRAGMA foreign_keys = OFF;');
      await context.database.customStatement(
        'DELETE FROM item_batches WHERE id = ?;',
        [fixture.nearBatch.id],
      );

      await expectRefused(shipped.id, isA<AppFailure>());
      await context.database.customStatement('PRAGMA foreign_keys = ON;');
    });

    test('tanpa lokasi Warehouse aktif, penerimaan ditolak', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      // Archived, not deleted: the location still exists, so this is *"there is none
      // live"* rather than a broken foreign key. Inventing a destination would post the
      // ledger against a row nobody chose (§21).
      await context.database.customStatement(
        "UPDATE stock_locations SET deleted_at = ? WHERE type = 'warehouse';",
        [nowUtc.toIso8601String()],
      );

      await expectRefused(
        shipped.id,
        isA<GoodsReturnWarehouseLocationNotFoundFailure>(),
      );
    });

    test('lokasi Warehouse ganda menolak penerimaan', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);

      // Which warehouse the goods arrived at is a business fact. Picking the first
      // would credit a balance nobody chose, and the real shelf would still hold the
      // stock (§21).
      // Inserted raw, because `ensureLocation` is idempotent by type — it would hand
      // back the existing warehouse rather than create a second one. The ambiguity
      // this guards against is a data fault an administrator could cause, so the
      // fixture has to be able to produce it.
      await context.insertDuplicateLocation(
        id: 'warehouse-cadangan',
        type: StockLocationType.warehouse.dbValue,
        name: 'Warehouse Pusat Cadangan',
      );

      await expectRefused(
        shipped.id,
        isA<GoodsReturnWarehouseLocationAmbiguousFailure>(),
      );
    });

    test('timestamp mundur membatalkan penerimaan', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);

      await expectLater(
        context
            .receiveGoodsReturn(
              clock: () =>
                  shipped.shippedAt!.subtract(const Duration(seconds: 1)),
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
              warehouseNote: 'Tidak boleh tersimpan',
            ),
        throwsA(isA<InvalidGoodsReturnTimestampFailure>()),
      );

      await expectNothingHappened(shipped.id);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
    });

    test('pelanggaran pemisahan tugas membatalkan penerimaan', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      await context.database.customStatement(
        'UPDATE users SET role = ? WHERE id = ?;',
        [UserRole.warehouse.dbValue, fixture.branchHead.id],
      );

      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              goodsReturnId: shipped.id,
              warehouseNote: 'Tidak boleh tersimpan',
            ),
        throwsA(isA<GoodsReturnSegregationOfDutiesFailure>()),
      );

      await expectNothingHappened(shipped.id);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
    });

    test('snapshot tidak cocok membatalkan penerimaan', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final lineIds = await goodsReturnLineIdsByGrLine(context, shipped.id);
      await context.database.customStatement(
        'UPDATE goods_return_lines SET qty = qty * 2 WHERE id = ?;',
        [lineIds[fixture.rejectedSimpleLineId]!],
      );

      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);
      await expectLater(
        context
            .receiveGoodsReturn(clock: () => nowUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
              warehouseNote: 'Tidak boleh tersimpan',
            ),
        throwsA(isA<GoodsReturnQuantityMismatchFailure>()),
      );

      expect(await context.goodsReturnStatusOf(shipped.id), 'shipped');
      expect(
        await context.goodsReturnColumn(shipped.id, 'received_at'),
        isNull,
      );
      expect(
        await context.goodsReturnColumn(shipped.id, 'received_by'),
        isNull,
      );
      expect(
        await context.goodsReturnColumn(shipped.id, 'warehouse_note'),
        isNull,
      );
      expect(await context.goodsReturnMovementCount(shipped.id), 0);
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);
    });
  });

  group('setelah kegagalan, penerimaan yang sah tetap bisa', () {
    test('retur dapat diterima setelah kegagalan sementara diperbaiki', () async {
      final shipped = await shippedGoodsReturnFor(context, fixture);
      final warehouseBefore = await context.balancesAt(fixture.warehouse.id);

      await expectLater(
        context
            .receiveGoodsReturn(
              clock: () => nowUtc,
              posting: failingPosting(failAfterAppends: 1),
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              goodsReturnId: shipped.id,
            ),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await context.balancesAt(fixture.warehouse.id), warehouseBefore);

      // A rollback leaves the document exactly as it was, so the honest retry works.
      final received = await context
          .receiveGoodsReturn(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            goodsReturnId: shipped.id,
          );
      expect(received.status, GoodsReturnStatus.received);
      expect(await context.goodsReturnMovementCount(shipped.id), 2);
    });
  });
}
