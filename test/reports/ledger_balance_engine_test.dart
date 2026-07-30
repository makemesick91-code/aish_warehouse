import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/reports/domain/models/report_source_models.dart';
import 'package:aish_warehouse/features/reports/domain/services/ledger_balance_engine.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_period_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// G-L4 — report figures come from `stock_movements`.
///
/// A pure-function suite: the engine takes movements and returns balances, so the
/// arithmetic can be pinned exactly without a database in the way. The repository
/// test then checks that the real reports feed it the real ledger.
void main() {
  const warehouse = 'loc-wh';
  const branchStore = 'loc-store';
  const room = 'loc-room';
  const item = 'item-1';
  const otherItem = 'item-2';
  const batch = 'batch-1';

  ReportLedgerMovement movement({
    required String id,
    required DateTime at,
    String? from,
    String? to,
    required int qty,
    String itemId = item,
    String? batchId,
    StockMovementType type = StockMovementType.shipment,
    SyncStatus sync = SyncStatus.synced,
    String? refDocType,
    String? refDocId,
  }) => ReportLedgerMovement(
    id: id,
    createdAtUtc: at,
    updatedAtUtc: at,
    syncStatus: sync,
    itemId: itemId,
    batchId: batchId,
    fromLocationId: from,
    toLocationId: to,
    qty: Quantity.fromWhole(qty),
    movementType: type,
    refDocType: refDocType,
    refDocId: refDocId,
    actorUserId: 'actor',
    note: null,
    reversalOfMovementId: null,
  );

  group('tanda per lokasi', () {
    test('masuk menambah, keluar mengurangi, tidak menyentuh nol', () {
      final transfer = movement(
        id: 'm1',
        at: DateTime.utc(2026, 7, 20),
        from: warehouse,
        to: branchStore,
        qty: 10,
      );

      expect(transfer.signedDeltaFor(branchStore), Quantity.fromWhole(10));
      expect(transfer.signedDeltaFor(warehouse), Quantity.fromWhole(-10));
      expect(transfer.signedDeltaFor(room), Quantity.zero());
    });

    test('perpindahan dihitung dua kali, satu per sisi', () {
      // §21: a `branch_all` report that netted this would show the branch total
      // unchanged and lose the fact that the stock moved into a room.
      final movements = [
        movement(
          id: 'm1',
          at: DateTime.utc(2026, 7, 20),
          to: warehouse,
          qty: 100,
          type: StockMovementType.inboundWarehouse,
        ),
        movement(
          id: 'm2',
          at: DateTime.utc(2026, 7, 21),
          from: warehouse,
          to: branchStore,
          qty: 30,
        ),
        movement(
          id: 'm3',
          at: DateTime.utc(2026, 7, 22),
          from: branchStore,
          to: room,
          qty: 12,
          type: StockMovementType.distribution,
        ),
      ];

      final balances = LedgerBalanceEngine.balancesAsOf(
        movements: movements,
        locationIds: {warehouse, branchStore, room},
        cutoffExclusiveUtc: DateTime.utc(2026, 8, 1),
      );

      expect(
        balances[const LedgerPositionKey(
          locationId: warehouse,
          itemId: item,
          batchId: null,
        )],
        Quantity.fromWhole(70),
      );
      expect(
        balances[const LedgerPositionKey(
          locationId: branchStore,
          itemId: item,
          batchId: null,
        )],
        Quantity.fromWhole(18),
      );
      expect(
        balances[const LedgerPositionKey(
          locationId: room,
          itemId: item,
          batchId: null,
        )],
        Quantity.fromWhole(12),
      );
    });
  });

  group('cutoff', () {
    final movements = [
      movement(
        id: 'm1',
        at: DateTime.utc(2026, 7, 29, 15),
        to: warehouse,
        qty: 10,
        type: StockMovementType.inboundWarehouse,
      ),
      movement(
        id: 'm2',
        at: DateTime.utc(2026, 7, 30, 16),
        to: warehouse,
        qty: 5,
        type: StockMovementType.inboundWarehouse,
      ),
    ];

    test('pergerakan tepat pada cutoff eksklusif tidak dihitung', () {
      final period = ReportPeriodPolicy.asOf(DateOnly.of(2026, 7, 30));

      final balances = LedgerBalanceEngine.balancesAsOf(
        movements: movements,
        locationIds: {warehouse},
        cutoffExclusiveUtc: period.endExclusiveUtc,
      );

      expect(
        balances[const LedgerPositionKey(
          locationId: warehouse,
          itemId: item,
          batchId: null,
        )],
        Quantity.fromWhole(10),
      );
    });

    test('cutoff berikutnya memasukkan pergerakan itu', () {
      final period = ReportPeriodPolicy.asOf(DateOnly.of(2026, 7, 31));

      final balances = LedgerBalanceEngine.balancesAsOf(
        movements: movements,
        locationIds: {warehouse},
        cutoffExclusiveUtc: period.endExclusiveUtc,
      );

      expect(
        balances[const LedgerPositionKey(
          locationId: warehouse,
          itemId: item,
          batchId: null,
        )],
        Quantity.fromWhole(15),
      );
    });
  });

  group('posisi per batch', () {
    test('batch null dan batch terisi adalah posisi berbeda', () {
      // G-E2 splits balances per batch, and folding the unbatched case into the
      // batched one is how a report starts double-counting.
      final movements = [
        movement(
          id: 'm1',
          at: DateTime.utc(2026, 7, 20),
          to: warehouse,
          qty: 10,
          type: StockMovementType.inboundWarehouse,
        ),
        movement(
          id: 'm2',
          at: DateTime.utc(2026, 7, 20),
          to: warehouse,
          qty: 7,
          batchId: batch,
          type: StockMovementType.inboundWarehouse,
        ),
      ];

      final balances = LedgerBalanceEngine.balancesAsOf(
        movements: movements,
        locationIds: {warehouse},
        cutoffExclusiveUtc: DateTime.utc(2026, 8, 1),
      );

      expect(balances.length, 2);
      expect(
        balances[const LedgerPositionKey(
          locationId: warehouse,
          itemId: item,
          batchId: null,
        )],
        Quantity.fromWhole(10),
      );
      expect(
        balances[const LedgerPositionKey(
          locationId: warehouse,
          itemId: item,
          batchId: batch,
        )],
        Quantity.fromWhole(7),
      );
    });
  });

  group('saldo awal dan running balance', () {
    final movements = [
      movement(
        id: 'm-before',
        at: DateTime.utc(2026, 6, 30, 10),
        to: warehouse,
        qty: 100,
        type: StockMovementType.inboundWarehouse,
      ),
      movement(
        id: 'm-in',
        at: DateTime.utc(2026, 7, 5),
        to: warehouse,
        qty: 20,
        type: StockMovementType.inboundWarehouse,
      ),
      movement(
        id: 'm-out',
        at: DateTime.utc(2026, 7, 10),
        from: warehouse,
        to: branchStore,
        qty: 30,
      ),
      movement(
        id: 'm-other-item',
        at: DateTime.utc(2026, 7, 12),
        to: warehouse,
        qty: 99,
        itemId: otherItem,
        type: StockMovementType.inboundWarehouse,
      ),
    ];

    final period = ReportPeriodPolicy.range(
      periodStart: DateOnly.of(2026, 7, 1),
      periodEnd: DateOnly.of(2026, 7, 31),
    );

    test('saldo awal menjumlahkan seluruh ledger sebelum periode', () {
      expect(
        LedgerBalanceEngine.openingBalance(
          movements: movements,
          locationId: warehouse,
          itemId: item,
          startUtc: period.startUtc,
        ),
        Quantity.fromWhole(100),
      );
    });

    test('mutasi periode hanya barang dan lokasi yang diminta', () {
      final selected = LedgerBalanceEngine.movementsInPeriod(
        movements: movements,
        period: period,
        locationId: warehouse,
        itemId: item,
      );

      expect(selected.map((m) => m.id), ['m-in', 'm-out']);
    });

    test('running balance menjumlahkan opening dan setiap delta', () {
      final selected = LedgerBalanceEngine.movementsInPeriod(
        movements: movements,
        period: period,
        locationId: warehouse,
        itemId: item,
      );

      final running = LedgerBalanceEngine.runningBalance(
        movements: selected,
        locationId: warehouse,
        opening: Quantity.fromWhole(100),
      );

      expect(running, [Quantity.fromWhole(120), Quantity.fromWhole(90)]);
    });

    test('saldo akhir sama dengan saldo as-of', () {
      // The property that makes a stock card reconcile: opening + Σ deltas is the
      // same number the as-of fold produces.
      final selected = LedgerBalanceEngine.movementsInPeriod(
        movements: movements,
        period: period,
        locationId: warehouse,
        itemId: item,
      );
      final running = LedgerBalanceEngine.runningBalance(
        movements: selected,
        locationId: warehouse,
        opening: Quantity.fromWhole(100),
      );
      final asOf = LedgerBalanceEngine.balancesAsOf(
        movements: movements,
        locationIds: {warehouse},
        cutoffExclusiveUtc: period.endExclusiveUtc,
      );

      expect(
        running.last,
        asOf[const LedgerPositionKey(
          locationId: warehouse,
          itemId: item,
          batchId: null,
        )],
      );
    });
  });

  group('determinisme', () {
    test('urutan stabil walau input diacak', () {
      // Two movements sharing a timestamp to the microsecond — what a single
      // posting transaction produces. Without the id tie-break the running balance
      // column would differ between two runs of the same report.
      final at = DateTime.utc(2026, 7, 20, 8);
      final a = movement(
        id: 'aaa',
        at: at,
        to: warehouse,
        qty: 5,
        type: StockMovementType.inboundWarehouse,
      );
      final b = movement(
        id: 'bbb',
        at: at,
        from: warehouse,
        to: branchStore,
        qty: 2,
      );

      expect(LedgerBalanceEngine.sorted([b, a]).map((m) => m.id), [
        'aaa',
        'bbb',
      ]);
      expect(LedgerBalanceEngine.sorted([a, b]).map((m) => m.id), [
        'aaa',
        'bbb',
      ]);
    });

    test('running balance identik pada dua urutan input', () {
      final at = DateTime.utc(2026, 7, 20, 8);
      final movements = [
        movement(
          id: 'm1',
          at: at,
          to: warehouse,
          qty: 5,
          type: StockMovementType.inboundWarehouse,
        ),
        movement(id: 'm2', at: at, from: warehouse, to: branchStore, qty: 2),
      ];
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 1),
        periodEnd: DateOnly.of(2026, 7, 31),
      );

      List<Quantity> run(List<ReportLedgerMovement> input) =>
          LedgerBalanceEngine.runningBalance(
            movements: LedgerBalanceEngine.movementsInPeriod(
              movements: input,
              period: period,
              locationId: warehouse,
              itemId: item,
            ),
            locationId: warehouse,
            opening: Quantity.zero(),
          );

      expect(run(movements), run(movements.reversed.toList()));
    });
  });

  group('integritas', () {
    test('saldo historis negatif dilaporkan, bukan dijepit ke nol', () {
      // G-A2 makes this impossible on a healthy database, so finding one means the
      // ledger and the balance cache disagree — exactly what a report exposes (§18).
      final movements = [
        movement(
          id: 'm1',
          at: DateTime.utc(2026, 7, 20),
          from: warehouse,
          to: branchStore,
          qty: 5,
        ),
      ];

      final warnings = LedgerBalanceEngine.detectNegativeBalances(
        movements: movements,
        locationIds: {warehouse},
        cutoffExclusiveUtc: DateTime.utc(2026, 8, 1),
      );

      expect(warnings, hasLength(1));
      expect(warnings.single.balance, Quantity.fromWhole(-5));
      expect(warnings.single.message, contains('negatif'));
    });

    test('running balance negatif terkumpul sebagai peringatan', () {
      final movements = [
        movement(
          id: 'm1',
          at: DateTime.utc(2026, 7, 5),
          from: warehouse,
          to: branchStore,
          qty: 5,
        ),
      ];
      final warnings = <LedgerIntegrityWarning>[];

      LedgerBalanceEngine.runningBalance(
        movements: movements,
        locationId: warehouse,
        opening: Quantity.zero(),
        warnings: warnings,
      );

      expect(warnings.single.movementId, 'm1');
    });

    test('posisi nol dan negatif dibuang dari totals per posisi', () {
      final movements = [
        movement(
          id: 'm1',
          at: DateTime.utc(2026, 7, 5),
          to: warehouse,
          qty: 5,
          type: StockMovementType.inboundWarehouse,
        ),
        movement(
          id: 'm2',
          at: DateTime.utc(2026, 7, 6),
          from: warehouse,
          to: branchStore,
          qty: 5,
        ),
      ];

      final totals = LedgerBalanceEngine.totalsByLocationItemBatch(
        movements: movements,
        locationIds: {warehouse, branchStore},
        cutoffExclusiveUtc: DateTime.utc(2026, 8, 1),
      );

      expect(totals.keys.map((key) => key.locationId), [branchStore]);
    });
  });

  group('total per dokumen', () {
    test('menjumlahkan magnitudo per posisi dokumen', () {
      final movements = [
        movement(
          id: 'm1',
          at: DateTime.utc(2026, 7, 5),
          from: warehouse,
          to: branchStore,
          qty: 4,
          batchId: batch,
          refDocType: RefDocType.deliveryOrder,
          refDocId: 'do-1',
        ),
        movement(
          id: 'm2',
          at: DateTime.utc(2026, 7, 5),
          from: warehouse,
          to: branchStore,
          qty: 6,
          batchId: batch,
          refDocType: RefDocType.deliveryOrder,
          refDocId: 'do-1',
        ),
      ];

      final totals = LedgerBalanceEngine.totalsByDocumentPosition(
        movements: movements,
      );

      expect(
        totals[const LedgerDocumentPositionKey(
          refDocId: 'do-1',
          itemId: item,
          batchId: batch,
        )],
        Quantity.fromWhole(10),
      );
    });

    test('pergerakan tanpa referensi dokumen diabaikan', () {
      final movements = [
        movement(
          id: 'm1',
          at: DateTime.utc(2026, 7, 5),
          to: warehouse,
          qty: 4,
          type: StockMovementType.inboundWarehouse,
        ),
      ];

      expect(
        LedgerBalanceEngine.totalsByDocumentPosition(movements: movements),
        isEmpty,
      );
    });

    test('total per dokumen dan barang mengabaikan batch', () {
      final movements = [
        movement(
          id: 'm1',
          at: DateTime.utc(2026, 7, 5),
          from: warehouse,
          to: branchStore,
          qty: 4,
          batchId: 'batch-a',
          refDocType: RefDocType.deliveryOrder,
          refDocId: 'do-1',
        ),
        movement(
          id: 'm2',
          at: DateTime.utc(2026, 7, 5),
          from: warehouse,
          to: branchStore,
          qty: 6,
          batchId: 'batch-b',
          refDocType: RefDocType.deliveryOrder,
          refDocId: 'do-1',
        ),
      ];

      expect(
        LedgerBalanceEngine.totalsByDocumentItem(
          movements: movements,
        )[const LedgerDocumentItemKey(refDocId: 'do-1', itemId: item)],
        Quantity.fromWhole(10),
      );
    });
  });

  group('fixed-point', () {
    test('kuantitas desimal dijumlahkan persis', () {
      // The reason `Quantity` exists: 0.1 + 0.2 must be exactly 0.3.
      final movements = [
        for (var index = 0; index < 3; index++)
          ReportLedgerMovement(
            id: 'm$index',
            createdAtUtc: DateTime.utc(2026, 7, 5, index),
            updatedAtUtc: DateTime.utc(2026, 7, 5, index),
            syncStatus: SyncStatus.synced,
            itemId: item,
            batchId: null,
            fromLocationId: null,
            toLocationId: warehouse,
            qty: Quantity.parse('0.1'),
            movementType: StockMovementType.inboundWarehouse,
            refDocType: null,
            refDocId: null,
            actorUserId: 'actor',
            note: null,
            reversalOfMovementId: null,
          ),
      ];

      final balances = LedgerBalanceEngine.balancesAsOf(
        movements: movements,
        locationIds: {warehouse},
        cutoffExclusiveUtc: DateTime.utc(2026, 8, 1),
      );

      expect(
        balances[const LedgerPositionKey(
              locationId: warehouse,
              itemId: item,
              batchId: null,
            )]!
            .format(),
        '0.3',
      );
    });
  });
}
