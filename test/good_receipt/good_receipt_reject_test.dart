import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_line_decision_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-G4 — *"Baris `rejected` wajib memiliki alasan (rusak / salah barang /
/// kedaluwarsa / tidak dipesan). 'Hapus yang tidak sesuai' = tandai `rejected` — bukan
/// menghapus record"* (§42).
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A single-position receipt. [qty] is small by default in the loops below, because
  /// G-D2 caps the cumulative shipped quantity of a requested position — four
  /// shipments of `2.5` against a request for `3` is an over-shipment, and would fail
  /// on the delivery side before this test got to its own subject.
  Future<({String grId, String lineId})> receipt({String qty = '2.5'}) async {
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
    return (grId: grId, lineId: detail!.lines.single.id);
  }

  Future<void> reject(String grId, String lineId, String? reason) =>
      context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: lineId,
        reason: reason,
      );

  Future<GoodReceiptLine> reload(String grId, String lineId) async {
    final detail = await context.receipts.getDetail(grId);
    return detail!.lines.firstWhere((line) => line.id == lineId);
  }

  group('alasan wajib', () {
    test('penolakan tanpa alasan ditolak', () async {
      final target = await receipt();

      await expectLater(
        reject(target.grId, target.lineId, null),
        throwsA(isA<GoodReceiptRejectReasonRequiredFailure>()),
      );

      final line = await reload(target.grId, target.lineId);
      expect(line.isPending, isTrue);
    });

    test('alasan berisi spasi saja ditolak', () async {
      final target = await receipt();

      await expectLater(
        reject(target.grId, target.lineId, '   \n\t '),
        throwsA(isA<GoodReceiptRejectReasonRequiredFailure>()),
      );

      final line = await reload(target.grId, target.lineId);
      expect(line.isPending, isTrue);
      expect(line.rejectReason, isNull);
    });

    test('alasan dinormalisasi dengan trim', () async {
      final target = await receipt();

      await reject(target.grId, target.lineId, '  Rusak  ');

      final line = await reload(target.grId, target.lineId);
      expect(line.rejectReason, 'Rusak');
    });

    test('constraint database menolak penolakan tanpa alasan', () async {
      final target = await receipt();

      // The use case is not the only guard. SQLite treats a CHECK whose result is NULL
      // as satisfied, which is why the constraint spells out `IS NOT NULL` — without
      // it, exactly this UPDATE would succeed.
      await expectLater(
        context.database.customStatement(
          "UPDATE good_receipt_lines SET line_status = 'rejected', "
          'received_qty = 0 WHERE id = ?;',
          [target.lineId],
        ),
        throwsA(anything),
      );
      await expectLater(
        context.database.customStatement(
          "UPDATE good_receipt_lines SET line_status = 'rejected', "
          "received_qty = 0, reject_reason = '  ' WHERE id = ?;",
          [target.lineId],
        ),
        throwsA(anything),
      );
    });
  });

  group('preset alasan', () {
    test('setiap preset menghasilkan alasan yang tersimpan', () async {
      for (final preset in [
        GoodReceiptRejectReasonPreset.damaged,
        GoodReceiptRejectReasonPreset.wrongItem,
        GoodReceiptRejectReasonPreset.expired,
        GoodReceiptRejectReasonPreset.notOrdered,
      ]) {
        final target = await receipt(qty: '0.5');
        final reason = GoodReceiptLineDecisionPolicy.composeReason(
          preset: preset,
        );

        await reject(target.grId, target.lineId, reason);

        final line = await reload(target.grId, target.lineId);
        expect(line.isRejected, isTrue);
        expect(line.rejectReason, preset.label);
      }
    });

    test('Lainnya wajib disertai detail', () {
      // The word on its own explains nothing, and storing it would produce an audit
      // trail that names no cause.
      expect(GoodReceiptRejectReasonPreset.other.requiresDetail, isTrue);
      expect(
        GoodReceiptLineDecisionPolicy.composeReason(
          preset: GoodReceiptRejectReasonPreset.other,
        ),
        isNull,
      );
      expect(
        GoodReceiptLineDecisionPolicy.composeReason(
          preset: GoodReceiptRejectReasonPreset.other,
          detail: '   ',
        ),
        isNull,
      );
      expect(
        GoodReceiptLineDecisionPolicy.composeReason(
          preset: GoodReceiptRejectReasonPreset.other,
          detail: 'Kemasan penyok',
        ),
        'Kemasan penyok',
      );
    });

    test('Lainnya tanpa detail ditolak oleh use case', () async {
      final target = await receipt();

      await expectLater(
        reject(
          target.grId,
          target.lineId,
          GoodReceiptLineDecisionPolicy.composeReason(
            preset: GoodReceiptRejectReasonPreset.other,
          ),
        ),
        throwsA(isA<GoodReceiptRejectReasonRequiredFailure>()),
      );
    });

    test('preset lain menyimpan label dan detail bersama', () {
      expect(
        GoodReceiptLineDecisionPolicy.composeReason(
          preset: GoodReceiptRejectReasonPreset.damaged,
          detail: 'Botol pecah',
        ),
        'Rusak — Botol pecah',
      );
      // Whitespace-only detail contributes nothing rather than a dangling dash.
      expect(
        GoodReceiptLineDecisionPolicy.composeReason(
          preset: GoodReceiptRejectReasonPreset.damaged,
          detail: '  ',
        ),
        'Rusak',
      );
    });

    test('preset kedaluwarsa tersedia untuk G-E5', () {
      // Spec §3.11 names the reason expired and near-expiry goods are refused with, so
      // the vocabulary has to contain it.
      expect(
        GoodReceiptRejectReasonPreset.expiryPreset,
        GoodReceiptRejectReasonPreset.expired,
      );
      expect(
        GoodReceiptRejectReasonPreset.expired.label,
        contains('Kedaluwarsa'),
      );
    });
  });

  group('penolakan bukan penghapusan', () {
    test('rejected memaksa received_qty menjadi nol', () async {
      final target = await receipt();
      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
        goodReceiptLineId: target.lineId,
        receivedQty: Quantity.parse('2'),
      );

      await reject(target.grId, target.lineId, 'Rusak');

      final line = await reload(target.grId, target.lineId);
      expect(line.receivedQty, Quantity.zero());
      expect(line.discrepancyQty, Quantity.parse('2.5'));
      expect(line.addsStock, isFalse);
    });

    test('baris rejected tetap ada di database', () async {
      final target = await receipt();

      await reject(target.grId, target.lineId, 'Salah barang');

      final rows = await context.goodReceiptLineRows(target.grId);
      expect(rows, hasLength(1));
      expect(rows[target.lineId]!['line_status'], 'rejected');
      expect(rows[target.lineId]!['reject_reason'], 'Salah barang');
      expect(await context.goodReceiptLineCount(target.grId), 1);
    });

    test('checked tidak boleh menyimpan alasan penolakan', () async {
      final target = await receipt();
      await reject(target.grId, target.lineId, 'Rusak');

      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
        goodReceiptLineId: target.lineId,
        receivedQty: Quantity.parse('2.5'),
      );

      final line = await reload(target.grId, target.lineId);
      expect(line.rejectReason, isNull);

      // And the database refuses the combination directly.
      await expectLater(
        context.database.customStatement(
          "UPDATE good_receipt_lines SET reject_reason = 'Rusak' WHERE id = ?;",
          [target.lineId],
        ),
        throwsA(anything),
      );
    });

    test('alasan tetap terbaca setelah GR diposting', () async {
      final target = await receipt();
      await reject(target.grId, target.lineId, 'Tidak dipesan');
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
      );

      final line = await reload(target.grId, target.lineId);
      expect(line.isRejected, isTrue);
      expect(line.rejectReason, 'Tidak dipesan');
      expect(await context.goodReceiptStatusOf(target.grId), 'posted');
    });

    test('alasan tampil pada antrean Warehouse', () async {
      final target = await receipt();
      await reject(target.grId, target.lineId, 'Rusak — Botol pecah');
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
      );

      final rows = await context.receipts.warehouseDiscrepancies(
        const GoodReceiptFilter(),
      );

      expect(rows, hasLength(1));
      expect(rows.single.rejectReason, 'Rusak — Botol pecah');
      expect(rows.single.lineStatus, GoodReceiptLineStatus.rejected);
      expect(rows.single.returnRequired, isTrue);
    });

    test('pencarian antrean menemukan baris lewat nomor GR', () async {
      final target = await receipt();
      await reject(target.grId, target.lineId, 'Rusak');
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: target.grId,
      );
      final receiptRow = await context.receipts.getById(target.grId);

      final found = await context.receipts.warehouseDiscrepancies(
        GoodReceiptFilter(searchQuery: receiptRow!.docNumber),
      );
      final missed = await context.receipts.warehouseDiscrepancies(
        const GoodReceiptFilter(searchQuery: 'tidak-ada-nomor-ini'),
      );

      expect(found, hasLength(1));
      expect(missed, isEmpty);
    });
  });

  group('kebijakan alasan', () {
    test('normalisasi mengubah kosong menjadi null', () {
      expect(GoodReceiptLineDecisionPolicy.normalizeReason(null), isNull);
      expect(GoodReceiptLineDecisionPolicy.normalizeReason(''), isNull);
      expect(GoodReceiptLineDecisionPolicy.normalizeReason('  \t'), isNull);
      expect(GoodReceiptLineDecisionPolicy.normalizeReason(' Rusak '), 'Rusak');
    });

    test('validitas alasan sejalan dengan normalisasi', () {
      expect(GoodReceiptLineDecisionPolicy.isValidRejectReason(null), isFalse);
      expect(GoodReceiptLineDecisionPolicy.isValidRejectReason(' '), isFalse);
      expect(
        GoodReceiptLineDecisionPolicy.isValidRejectReason('Kedaluwarsa'),
        isTrue,
      );
    });

    test('kuantitas baris rejected selalu nol menurut kebijakan', () {
      expect(
        GoodReceiptLineDecisionPolicy.rejectedReceivedQty,
        Quantity.zero(),
      );
    });
  });
}
