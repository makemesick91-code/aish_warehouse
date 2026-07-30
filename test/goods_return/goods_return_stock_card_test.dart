import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/goods_return/presentation/providers/goods_return_providers.dart';
import 'package:aish_warehouse/features/inventory/presentation/models/stock_card_entry.dart';
import 'package:aish_warehouse/features/inventory/presentation/stock_movement_presenter.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The Retur on a stock card (§34).
///
/// A return row has to read as what it is: goods coming *back into* the Warehouse, from
/// a named branch, against a named document, by a named person, on a date in operational
/// time. The two things worth testing hardest are the ones a bug would make invisible:
/// the row must never appear on a **branch** card — the goods were never branch stock —
/// and it must survive its master data being withdrawn, because a card that silently
/// drops rows is a card that does not add up.
void main() {
  late TestContext context;
  late GoodsReturnFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildGoodsReturnFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<ProviderContainer> containerFor(MasterUser user) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(context.database),
        currentSessionProvider.overrideWith(() => FixedSessionController(user)),
        goodsReturnClockProvider.overrideWithValue(() => nowUtc),
      ],
    );
    addTearDown(container.dispose);
    await container.read(currentSessionProvider.future);
    return container;
  }

  Future<List<StockCardEntry>> ledgerFor(
    ProviderContainer container,
    String goodsReturnId,
  ) async {
    // The provider inherits its scope from a *stream* provider, so the subscription has
    // to stay open long enough for that stream's first emission to arrive — the same
    // reason a screen holds it while it is on screen.
    final subscription = container.listen(
      goodsReturnMovementsProvider(goodsReturnId),
      (_, _) {},
    );
    try {
      var entries = await container.read(
        goodsReturnMovementsProvider(goodsReturnId).future,
      );
      if (entries.isEmpty) {
        // First read can land before the scoped detail stream has emitted.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        entries = await container.read(
          goodsReturnMovementsProvider(goodsReturnId).future,
        );
      }
      return entries;
    } finally {
      subscription.close();
    }
  }

  group('presenter', () {
    test('label movement dan dokumen menyebut Retur', () {
      expect(
        StockMovementPresenter.labelOf(StockMovementType.itemReturn),
        'Retur ke Warehouse',
      );
      expect(
        StockMovementPresenter.documentLabelOf(RefDocType.goodsReturn),
        'dokumen Retur',
      );
    });

    test('arah dibaca dari kolom lokasi, bukan dari jenis', () {
      // A return has one leg: nothing on the source side, the Warehouse on the other.
      expect(
        StockMovementPresenter.directionLabelOf(
          fromLocationId: null,
          toLocationId: 'warehouse-1',
        ),
        'Masuk',
      );
      expect(
        StockMovementPresenter.signFor(
          locationId: 'warehouse-1',
          fromLocationId: null,
          toLocationId: 'warehouse-1',
        ),
        '+',
      );
      // And no sign at all from a location the row does not touch.
      expect(
        StockMovementPresenter.signFor(
          locationId: 'branch-store-1',
          fromLocationId: null,
          toLocationId: 'warehouse-1',
        ),
        isNull,
      );
    });

    test('setiap jenis movement tetap punya label', () {
      for (final type in StockMovementType.values) {
        expect(StockMovementPresenter.labelOf(type).trim(), isNotEmpty);
      }
    });
  });

  group('baris kartu stok', () {
    test('memuat nomor RET, barang, batch, aktor dan kuantitas', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      final container = await containerFor(fixture.warehouseUser);

      final entries = await ledgerFor(container, received.id);
      expect(entries, hasLength(2));

      final batched = entries.singleWhere(
        (entry) => entry.movement.batchId == fixture.nearBatch.id,
      );
      expect(batched.documentNumber, received.goodsReturn.docNumber);
      expect(batched.itemName, fixture.batchItem.name);
      expect(batched.sku, fixture.batchItem.sku);
      expect(batched.unit, fixture.batchItem.unit);
      expect(batched.batchNo, fixture.nearBatch.batchNo);
      expect(batched.expiryDate, isNotNull);
      expect(batched.actorName, fixture.warehouseUser.fullName);
      expect(batched.movement.qty, fixture.rejectedBatchQty);
      expect(batched.movement.movementType, StockMovementType.itemReturn);
      expect(batched.movement.fromLocationId, isNull);
      expect(batched.movement.toLocationId, fixture.warehouse.id);
      expect(batched.toLocationName, fixture.warehouse.name);
      // The reject reason travels into the ledger note (§22).
      expect(
        batched.movement.note,
        contains('Sisa umur simpan terlalu pendek'),
      );
      // UTC on the wire; the widget converts to GMT+8 for display (T-1).
      expect(batched.movement.createdAt.isUtc, isTrue);
    });

    test('barang tanpa expiry tidak membawa batch', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      final container = await containerFor(fixture.warehouseUser);

      final entries = await ledgerFor(container, received.id);
      final plain = entries.singleWhere(
        (entry) => entry.movement.itemId == fixture.simpleItem.id,
      );
      expect(plain.movement.batchId, isNull);
      expect(plain.batchNo, isNull);
      expect(plain.expiryDate, isNull);
    });

    test('Kepala Cabang membaca kartu dokumennya sendiri', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      final container = await containerFor(fixture.branchHead);

      final entries = await ledgerFor(container, received.id);
      expect(entries, hasLength(2));
      expect(entries.first.documentNumber, received.goodsReturn.docNumber);
    });

    test('peran lain tidak mendapat baris apa pun', () async {
      final received = await receivedGoodsReturnFor(context, fixture);

      for (final user in [fixture.nurse, fixture.superAdmin]) {
        final container = await containerFor(user);
        expect(
          await ledgerFor(container, received.id),
          isEmpty,
          reason: '${user.role.label} tidak boleh membaca kartu retur.',
        );
      }
    });

    test('Kacab cabang lain tidak mendapat baris', () async {
      final received = await receivedGoodsReturnFor(context, fixture);
      final container = await containerFor(fixture.otherBranchHead);

      // The scope is inherited from the branch-scoped detail read, so a foreign
      // document yields an empty card rather than a leaked ledger (§47).
      expect(await ledgerFor(container, received.id), isEmpty);
    });
  });

  group('ketahanan historis', () {
    test(
      'baris tetap ada setelah barang, batch dan aktor dinonaktifkan',
      () async {
        final received = await receivedGoodsReturnFor(context, fixture);
        await context.deactivate('items', fixture.batchItem.id);
        await context.archive('item_batches', fixture.nearBatch.id);
        await context.deactivate('users', fixture.warehouseUser.id);
        await context.deactivate('branches', fixture.branch.id);

        final container = await containerFor(fixture.warehouseUser);
        final entries = await ledgerFor(container, received.id);

        expect(
          entries,
          hasLength(2),
          reason: 'Tidak ada baris yang boleh hilang.',
        );
        final batched = entries.singleWhere(
          (entry) => entry.movement.batchId == fixture.nearBatch.id,
        );
        expect(batched.itemName, fixture.batchItem.name);
        expect(batched.itemIsHistorical, isTrue);
        expect(batched.actorIsHistorical, isTrue);
        expect(batched.batchNo, fixture.nearBatch.batchNo);
      },
    );

    test('referensi dokumen yang tidak dikenal tidak membuat crash', () {
      // A `ref_doc_type` written by a later version, or by the sync backend.
      expect(
        StockMovementPresenter.documentLabelOf('XYZ'),
        StockMovementPresenter.unknownDocumentLabel('XYZ'),
      );
      expect(
        StockMovementPresenter.documentLabelOf(null),
        StockMovementPresenter.noDocumentLabel,
      );
    });
  });

  group('kartu Gudang Cabang', () {
    test('tidak pernah memuat movement retur', () async {
      await receivedGoodsReturnFor(context, fixture);

      for (final itemId in [fixture.simpleItem.id, fixture.batchItem.id]) {
        final card = await context.inventory.stockCard(
          itemId: itemId,
          locationId: fixture.branchStore.id,
        );
        expect(
          card.any(
            (movement) => movement.movementType == StockMovementType.itemReturn,
          ),
          isFalse,
          reason:
              'from_location_id NULL, dan barang rejected tidak pernah menjadi '
              'saldo cabang (§34).',
        );
      }
    });

    test('kartu Warehouse memuatnya sebagai penambahan', () async {
      final received = await receivedGoodsReturnFor(context, fixture);

      final card = await context.inventory.stockCard(
        itemId: fixture.simpleItem.id,
        locationId: fixture.warehouse.id,
      );
      final row = card.singleWhere(
        (movement) =>
            movement.movementType == StockMovementType.itemReturn &&
            movement.refDocId == received.id,
      );
      expect(
        StockMovementPresenter.signFor(
          locationId: fixture.warehouse.id,
          fromLocationId: row.fromLocationId,
          toLocationId: row.toLocationId,
        ),
        '+',
      );
    });
  });
}
