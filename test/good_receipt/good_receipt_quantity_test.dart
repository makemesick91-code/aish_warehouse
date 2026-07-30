import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_line_decision_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-G3 — *"`0 ≤ received_qty ≤ shipped_qty`. Kekurangan otomatis tercatat sebagai
/// selisih pengiriman dan dilaporkan ke warehouse"* (§41).
///
/// Every comparison here is exact fixed-point arithmetic on milli-units (Q-2). That is
/// what the decimal cases are really testing: `2.375` received as `0.5 + 1.875` has to
/// leave exactly nothing, and a `double` path would leave a residue that made the
/// document either short by a hair or over-received by one.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A receipt whose only position ships [qty] of the non-batch item.
  Future<({String grId, GoodReceiptLine line})> receiptOf(String qty) async {
    final doId = await shipDeliveryOrderFor(
      context,
      fixture,
      nowUtc: nowUtc,
      allocations: [simpleAllocation(fixture, qty: qty)],
    );
    final grId = await startGoodReceiptFor(
      context,
      fixture,
      deliveryOrderId: doId,
      nowUtc: nowUtc,
    );
    final detail = await context.receipts.getDetail(grId);
    return (grId: grId, line: detail!.lines.single);
  }

  Future<void> check(String grId, String lineId, String qty) =>
      context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: lineId,
        receivedQty: Quantity.parse(qty),
      );

  Future<GoodReceiptLine> reload(String grId, String lineId) async {
    final detail = await context.receipts.getDetail(grId);
    return detail!.lines.firstWhere((line) => line.id == lineId);
  }

  group('batas kuantitas', () {
    test('diterima nol valid dan menghasilkan selisih penuh', () async {
      final target = await receiptOf('2.5');

      // A box that was on the manifest and not in the van. Refusing zero would push
      // the branch head towards `rejected`, which claims the goods are on their
      // counter waiting to go back.
      await check(target.grId, target.line.id, '0');

      final line = await reload(target.grId, target.line.id);
      expect(line.receivedQty, Quantity.zero());
      expect(line.discrepancyQty, Quantity.parse('2.5'));
      expect(line.isChecked, isTrue);
      expect(line.hasShortage, isTrue);
      expect(line.addsStock, isFalse);
    });

    test('diterima sama dengan dikirim valid tanpa selisih', () async {
      final target = await receiptOf('2.5');

      await check(target.grId, target.line.id, '2.5');

      final line = await reload(target.grId, target.line.id);
      expect(line.receivedQty, Quantity.parse('2.5'));
      expect(line.discrepancyQty, Quantity.zero());
      expect(line.hasShortage, isFalse);
      expect(line.addsStock, isTrue);
    });

    test('diterima kurang dari dikirim valid', () async {
      final target = await receiptOf('2.5');

      await check(target.grId, target.line.id, '1.5');

      final line = await reload(target.grId, target.line.id);
      expect(line.receivedQty, Quantity.parse('1.5'));
      expect(line.discrepancyQty, Quantity.parse('1'));
      expect(line.hasShortage, isTrue);
    });

    test('diterima lebih dari dikirim ditolak', () async {
      final target = await receiptOf('2.5');

      final failure = await check(
        target.grId,
        target.line.id,
        '2.501',
      ).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(failure, isA<ReceivedQuantityExceedsShippedFailure>());
      final typed = failure as ReceivedQuantityExceedsShippedFailure;
      expect(typed.shipped, Quantity.parse('2.5'));
      expect(typed.received, Quantity.parse('2.501'));
      // The excess is exact, down to the milli-unit.
      expect(typed.excess, Quantity.fromMilliUnits(1));

      // And nothing was written.
      final line = await reload(target.grId, target.line.id);
      expect(line.isPending, isTrue);
      expect(line.receivedQty, Quantity.parse('2.5'));
    });

    test('diterima negatif ditolak', () async {
      final target = await receiptOf('2.5');

      await expectLater(
        context.checkGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: target.grId,
          goodReceiptLineId: target.line.id,
          receivedQty: Quantity.fromMilliUnits(-1),
        ),
        throwsA(isA<InvalidReceivedQuantityFailure>()),
      );

      final line = await reload(target.grId, target.line.id);
      expect(line.isPending, isTrue);
    });

    test('constraint database menolak over-received', () async {
      final target = await receiptOf('2.5');

      // The use case is not the only guard: a hand-written UPDATE cannot receive more
      // than was sent either.
      await expectLater(
        context.database.customStatement(
          'UPDATE good_receipt_lines SET received_qty = ? WHERE id = ?;',
          [Quantity.parse('3').milliUnits, target.line.id],
        ),
        throwsA(anything),
      );
    });
  });

  group('aritmetika desimal eksak', () {
    test('kuantitas tiga desimal disimpan dan dibaca tepat', () async {
      final target = await receiptOf('2.375');

      await check(target.grId, target.line.id, '1.875');

      final line = await reload(target.grId, target.line.id);
      expect(line.receivedQty, Quantity.parse('1.875'));
      expect(line.discrepancyQty, Quantity.parse('0.5'));
      // And the stored integers are exactly the milli-units, with no rounding.
      final rows = await context.goodReceiptLineRows(target.grId);
      expect(rows[target.line.id]!['received_qty'], 1875);
      expect(rows[target.line.id]!['shipped_qty'], 2375);
    });

    test('selisih 0.1 + 0.2 tidak meninggalkan residu', () async {
      final target = await receiptOf('0.3');

      await check(target.grId, target.line.id, '0.1');
      var line = await reload(target.grId, target.line.id);
      expect(line.discrepancyQty, Quantity.parse('0.2'));

      await check(target.grId, target.line.id, '0.3');
      line = await reload(target.grId, target.line.id);
      expect(line.discrepancyQty, Quantity.zero());
      expect(line.discrepancyQty.isZero, isTrue);
    });

    test('tidak ada artefak floating point pada format', () async {
      final target = await receiptOf('1.005');
      await check(target.grId, target.line.id, '0.005');

      final line = await reload(target.grId, target.line.id);
      expect(line.receivedQty.format(), '0.005');
      expect(line.discrepancyQty.format(), '1');
    });
  });

  group('kebijakan kuantitas', () {
    test('rentang valid dinilai inklusif di kedua ujung', () {
      final shipped = Quantity.parse('2.5');

      expect(
        GoodReceiptLineDecisionPolicy.isValidReceivedQty(
          shippedQty: shipped,
          receivedQty: Quantity.zero(),
        ),
        isTrue,
      );
      expect(
        GoodReceiptLineDecisionPolicy.isValidReceivedQty(
          shippedQty: shipped,
          receivedQty: shipped,
        ),
        isTrue,
      );
      expect(
        GoodReceiptLineDecisionPolicy.isValidReceivedQty(
          shippedQty: shipped,
          receivedQty: Quantity.fromMilliUnits(2501),
        ),
        isFalse,
      );
      expect(
        GoodReceiptLineDecisionPolicy.isValidReceivedQty(
          shippedQty: shipped,
          receivedQty: Quantity.fromMilliUnits(-1),
        ),
        isFalse,
      );
    });

    test('selisih dihitung sebagai dikirim minus diterima', () {
      expect(
        GoodReceiptLineDecisionPolicy.discrepancyOf(
          shippedQty: Quantity.parse('2.375'),
          receivedQty: Quantity.parse('0.5'),
        ),
        Quantity.parse('1.875'),
      );
    });

    test('hanya checked positif yang menambah stok', () {
      expect(
        GoodReceiptLineDecisionPolicy.addsStock(
          lineStatus: GoodReceiptLineStatus.checked,
          receivedQty: Quantity.parse('1'),
        ),
        isTrue,
      );
      expect(
        GoodReceiptLineDecisionPolicy.addsStock(
          lineStatus: GoodReceiptLineStatus.checked,
          receivedQty: Quantity.zero(),
        ),
        isFalse,
      );
      expect(
        GoodReceiptLineDecisionPolicy.addsStock(
          lineStatus: GoodReceiptLineStatus.rejected,
          receivedQty: Quantity.parse('1'),
        ),
        isFalse,
      );
    });
  });

  group('pelaporan selisih ke Warehouse', () {
    /// A posted receipt with one shortage and one refusal.
    Future<String> postedWithBoth() async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          simpleAllocation(fixture, qty: '2.5'),
          safeBatchAllocation(fixture, qty: '4'),
        ],
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final byItem = await goodReceiptLinesByItem(context, grId);

      await check(grId, byItem[fixture.simpleItem.id]!.id, '1');
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: byItem[fixture.batchItem.id]!.id,
        reason: 'Rusak',
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );
      return grId;
    }

    test('checked shortage muncul di laporan Warehouse', () async {
      final grId = await postedWithBoth();

      final rows = await context.receipts.warehouseDiscrepancies(
        const GoodReceiptFilter(),
      );
      final shortage = rows.firstWhere(
        (row) => row.itemId == fixture.simpleItem.id,
      );

      expect(shortage.grId, grId);
      expect(shortage.kind, GoodReceiptDiscrepancyKind.shortage);
      expect(shortage.shippedQty, Quantity.parse('2.5'));
      expect(shortage.receivedQty, Quantity.parse('1'));
      expect(shortage.discrepancyQty, Quantity.parse('1.5'));
      // A shortage never arrived, so there is nothing at the branch to send back.
      expect(shortage.returnRequired, isFalse);
    });

    test(
      'rejected menghasilkan selisih sebesar seluruh kuantitas dikirim',
      () async {
        await postedWithBoth();

        final rows = await context.receipts.warehouseDiscrepancies(
          const GoodReceiptFilter(),
        );
        final rejected = rows.firstWhere(
          (row) => row.itemId == fixture.batchItem.id,
        );

        expect(rejected.kind, GoodReceiptDiscrepancyKind.rejectedReturn);
        expect(rejected.receivedQty, Quantity.zero());
        expect(rejected.discrepancyQty, Quantity.parse('4'));
        expect(rejected.returnRequired, isTrue);
        expect(rejected.rejectReason, 'Rusak');
      },
    );

    test('baris lengkap tidak muncul di laporan selisih', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );

      expect(
        await context.receipts.warehouseDiscrepancies(
          const GoodReceiptFilter(),
        ),
        isEmpty,
      );
    });

    test('GR yang masih checking tidak dilaporkan', () async {
      final doId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '2.5')],
      );
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      final line = (await context.receipts.getDetail(grId))!.lines.single;
      await check(grId, line.id, '1');

      // A branch head part way through a decision has not refused anything yet;
      // reporting the intermediate state would raise a return prematurely.
      expect(
        await context.receipts.warehouseDiscrepancies(
          const GoodReceiptFilter(),
        ),
        isEmpty,
      );
    });

    test('daftar retur hanya memuat baris rejected', () async {
      await postedWithBoth();

      final rows = await context.receipts.warehouseDiscrepancies(
        const GoodReceiptFilter(),
      );
      final candidates = GoodReceiptReturnCandidate.fromDiscrepancies(rows);

      expect(rows, hasLength(2));
      expect(candidates, hasLength(1));
      expect(candidates.single.sku, fixture.batchItem.sku);
      // The whole shipped quantity travels back, because a refusal accepted nothing.
      expect(candidates.single.returnQty, Quantity.parse('4'));
      expect(candidates.single.reason, 'Rusak');
    });

    test('filter jenis selisih memisahkan kekurangan dan retur', () async {
      await postedWithBoth();

      final shortages = await context.receipts.warehouseDiscrepancies(
        const GoodReceiptFilter(
          discrepancyKind: GoodReceiptDiscrepancyKind.shortage,
        ),
      );
      final returns = await context.receipts.warehouseDiscrepancies(
        const GoodReceiptFilter(
          discrepancyKind: GoodReceiptDiscrepancyKind.rejectedReturn,
        ),
      );

      expect(shortages.map((row) => row.itemId), [fixture.simpleItem.id]);
      expect(returns.map((row) => row.itemId), [fixture.batchItem.id]);
    });
  });
}
