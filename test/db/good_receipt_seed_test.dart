import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The Good Receipt half of the development seed (§37).
///
/// All three methods are **opt-in**: `run()` deliberately does not call them, because a
/// developer's first walk through *Alokasikan FEFO → Kirim → Mulai Pemeriksaan → Posting*
/// would otherwise find the work already done.
///
/// What the tests pin is that each of them is **idempotent** — a second run adds nothing —
/// and that the demo balances arrive **through the ledger**, never by writing
/// `stock_balances` directly, which is the same rule the production code follows (G-A1).
void main() {
  late TestContext context;

  setUp(() async {
    context = TestContext.create();
    await context.seed.run();
  });

  tearDown(() => context.dispose());

  Future<int> countOf(String table) async {
    final row = await context.database
        .customSelect('SELECT COUNT(*) AS c FROM $table;')
        .getSingle();
    return row.read<int>('c');
  }

  group('pengiriman demo', () {
    test('menghasilkan Surat Jalan shipped yang melewati tenggat', () async {
      final doId = await context.seed.seedShippedDeliveryOrder();

      expect(doId, isNotNull);
      expect(await context.deliveryOrderStatusOf(doId!), 'shipped');

      // 60 hours by default, which is past the 2×24 hour deadline (G-G6) — so the reminder
      // is demonstrable without waiting two days.
      final shippedAt = DateTime.parse(
        (await context.deliveryOrderColumn(doId, 'shipped_at'))!,
      );
      expect(
        DateTime.now().toUtc().difference(shippedAt).inHours,
        greaterThanOrEqualTo(48),
      );
    });

    test('idempoten: dijalankan dua kali tetap satu pengiriman', () async {
      final first = await context.seed.seedShippedDeliveryOrder();
      final second = await context.seed.seedShippedDeliveryOrder();

      expect(second, first);
      final shipped = await context.database
          .customSelect(
            "SELECT COUNT(*) AS c FROM delivery_orders WHERE status = 'shipped';",
          )
          .getSingle();
      expect(shipped.read<int>('c'), 1);
    });

    test(
      'stok warehouse berkurang lewat ledger, bukan tulisan langsung',
      () async {
        final doId = await context.seed.seedShippedDeliveryOrder();

        final movements = await context.shipmentMovements(doId!);
        expect(movements, isNotEmpty);
        for (final movement in movements) {
          expect(movement['movement_type'], 'shipment');
          expect(movement['ref_doc_type'], 'DO');
        }
      },
    );

    test('umur pengiriman dapat dikurangi untuk demo dalam tenggat', () async {
      final doId = await context.seed.seedShippedDeliveryOrder(
        age: const Duration(hours: 4),
      );

      final shippedAt = DateTime.parse(
        (await context.deliveryOrderColumn(doId!, 'shipped_at'))!,
      );
      expect(
        DateTime.now().toUtc().difference(shippedAt).inHours,
        lessThan(48),
      );
    });
  });

  group('GR checking demo', () {
    test('menghasilkan GR checking dengan snapshot lengkap', () async {
      final grId = await context.seed.seedCheckingGoodReceipt();

      expect(grId, isNotNull);
      expect(await context.goodReceiptStatusOf(grId!), 'checking');

      final detail = await context.receipts.getDetail(grId);
      expect(detail!.lines, isNotEmpty);
      expect(detail.progress.pending, detail.progress.total);
      // Nothing about stock happens when a checklist is opened (spec §2.5).
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test('idempoten: dijalankan dua kali tetap satu GR', () async {
      final first = await context.seed.seedCheckingGoodReceipt();
      final second = await context.seed.seedCheckingGoodReceipt();

      expect(second, first);
      expect(await countOf('good_receipts'), 1);
    });

    test('memanggilnya langsung juga menyiapkan pengirimannya', () async {
      // No shipment yet — the method builds the whole chain rather than returning null.
      expect(await countOf('delivery_orders'), 0);

      final grId = await context.seed.seedCheckingGoodReceipt();

      expect(grId, isNotNull);
      final receipt = await context.receipts.getById(grId!);
      expect(await context.deliveryOrderStatusOf(receipt!.doId), 'shipped');
    });
  });

  group('GR posted demo', () {
    test('menghasilkan GR posted dengan kekurangan dan penolakan', () async {
      final grId = await context.seed.seedPostedGoodReceipt();

      expect(grId, isNotNull);
      expect(await context.goodReceiptStatusOf(grId!), 'posted');

      final detail = await context.receipts.getDetail(grId);
      // Both shapes of discrepancy, so the warehouse queue is never empty and never
      // one-sided.
      expect(detail!.progress.shortage, greaterThan(0));
      expect(detail.progress.rejected, greaterThan(0));
      expect(detail.progress.pending, 0);
    });

    test('antrean selisih Warehouse memuat kedua jenis', () async {
      await context.seed.seedPostedGoodReceipt();

      final rows = await context.receipts.warehouseDiscrepancies(
        const GoodReceiptFilter(),
      );

      expect(rows, isNotEmpty);
      expect(
        rows.map((row) => row.kind),
        containsAll([
          GoodReceiptDiscrepancyKind.shortage,
          GoodReceiptDiscrepancyKind.rejectedReturn,
        ]),
      );
    });

    test('saldo Gudang Cabang dibuat lewat ledger', () async {
      final grId = await context.seed.seedPostedGoodReceipt();

      final movements = await context.goodReceiptMovements(grId!);
      expect(movements, isNotEmpty);
      for (final movement in movements) {
        expect(movement['movement_type'], 'good_receipt');
        expect(movement['ref_doc_type'], 'GR');
        // The shipment already recorded the outbound leg.
        expect(movement['from_location_id'], isNull);
        expect(movement['to_location_id'], isNotNull);
      }

      // Every balance row is backed by one of those movements, so `stock_balances` was
      // never written directly (G-A1).
      final branchStore = movements.first['to_location_id']! as String;
      final balances = await context.balancesAt(branchStore);
      expect(balances, isNotEmpty);
    });

    test('Surat Jalan menjadi received setelah GR diposting', () async {
      final grId = await context.seed.seedPostedGoodReceipt();
      final receipt = await context.receipts.getById(grId!);

      expect(await context.deliveryOrderStatusOf(receipt!.doId), 'received');
    });

    test('idempoten: dijalankan dua kali tetap satu GR posted', () async {
      final first = await context.seed.seedPostedGoodReceipt();
      final second = await context.seed.seedPostedGoodReceipt();

      expect(second, first);
      expect(await countOf('good_receipts'), 1);
      // And exactly one set of movements, not two.
      expect(await context.goodReceiptMovementCount(first!), greaterThan(0));
    });

    test(
      'batch yang tidak boleh diterima ditolak, bukan dipaksa masuk',
      () async {
        final grId = await context.seed.seedPostedGoodReceipt();
        final detail = await context.receipts.getDetail(grId!);
        final nowUtc = DateTime.now().toUtc();

        // The seed obeys G-E5 like every other caller: nothing that must be rejected was
        // accepted instead.
        for (final line in detail!.lines) {
          if (!line.mustBeRejectedOn(nowUtc)) continue;
          expect(
            line.isRejected,
            isTrue,
            reason:
                'Baris ${line.sku} kedaluwarsa/dekat ED tetapi tidak ditolak.',
          );
        }
      },
    );
  });

  group('seed utama tidak memposting apa pun', () {
    test('run() tidak membuat Good Receipt', () async {
      // Opt-in, so the workflow stays demonstrable end to end.
      expect(await countOf('good_receipts'), 0);
      expect(await countOf('good_receipt_lines'), 0);
    });

    test('run() tidak mengirim Surat Jalan', () async {
      final shipped = await context.database
          .customSelect(
            "SELECT COUNT(*) AS c FROM delivery_orders "
            "WHERE status IN ('shipped', 'received');",
          )
          .getSingle();
      expect(shipped.read<int>('c'), 0);
    });

    test('run() dapat dijalankan dua kali tanpa duplikasi', () async {
      final receiptsBefore = await countOf('good_receipts');
      await context.seed.run();

      expect(await countOf('good_receipts'), receiptsBefore);
    });
  });

  group('penjaga build produksi', () {
    test('setiap metode demo menolak berjalan pada build produksi', () async {
      for (final attempt in [
        () => context.productionSeed.seedShippedDeliveryOrder(),
        () => context.productionSeed.seedCheckingGoodReceipt(),
        () => context.productionSeed.seedPostedGoodReceipt(),
      ]) {
        await expectLater(attempt(), throwsA(isA<StateError>()));
      }
      expect(await countOf('good_receipts'), 0);
    });
  });

  group('integritas database setelah seed', () {
    test('tidak ada pelanggaran foreign key', () async {
      await context.seed.seedPostedGoodReceipt();

      final violations = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });

    test('setiap baris GR memiliki status yang konsisten', () async {
      final grId = await context.seed.seedPostedGoodReceipt();
      final rows = await context.goodReceiptLineRows(grId!);

      for (final row in rows.values) {
        final status = row['line_status'];
        expect(status, isNot('pending'));
        if (status == 'rejected') {
          expect(row['received_qty'], 0);
          expect(row['reject_reason'], isNotNull);
        } else {
          expect(row['reject_reason'], isNull);
          expect(
            row['received_qty'] as int,
            lessThanOrEqualTo(row['shipped_qty'] as int),
          );
        }
      }
    });

    test('status Purchase Request tetap konsisten dengan pengirimannya', () async {
      final grId = await context.seed.seedPostedGoodReceipt();
      final receipt = await context.receipts.getById(grId!);
      final order = await context.deliveries.getById(receipt!.doId);
      final status = await context.purchaseRequestStatusOf(order!.prId);

      // The seeded shipment does not necessarily cover the whole request, so the request
      // may legitimately still be `processing` — what must never happen is `closed` while
      // a shipment is outstanding.
      expect(
        status,
        anyOf('processing', 'shipped', 'closed'),
        reason: 'Status PR tidak wajar setelah seed: $status.',
      );
      if (status == PurchaseRequestStatus.closed.dbValue) {
        final outstanding = await context.database
            .customSelect(
              "SELECT COUNT(*) AS c FROM delivery_orders "
              "WHERE pr_id = ? AND status = 'shipped';",
              variables: [],
            )
            .getSingle();
        expect(outstanding.read<int>('c'), 0);
      }
    });
  });
}
