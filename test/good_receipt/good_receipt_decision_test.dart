import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_line_decision_policy.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_state_policy.dart';
import 'package:aish_warehouse/features/good_receipt/domain/use_cases/post_good_receipt_use_case.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';

/// G-G2 — *"Setiap baris wajib diputuskan: `checked` atau `rejected`. GR tidak bisa
/// `posted` selama masih ada baris `pending`"* (§40).
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// A three-position shipment, so "one pending among many" is reachable.
  Future<String> shippedOrder() => shipDeliveryOrderFor(
    context,
    fixture,
    nowUtc: nowUtc,
    allocations: [
      simpleAllocation(fixture, qty: '2.5'),
      safeBatchAllocation(fixture, qty: '4'),
      tieAllocation(fixture, qty: '2'),
    ],
  );

  Future<String> checkingReceipt() async => startGoodReceiptFor(
    context,
    fixture,
    deliveryOrderId: await shippedOrder(),
    nowUtc: nowUtc,
  );

  Future<GoodReceiptDetail> detailOf(String grId) async {
    final detail = await context.receipts.getDetail(grId);
    expect(detail, isNotNull);
    return detail!;
  }

  Future<GoodReceiptPostingResult> post(String grId) => context
      .postGoodReceipt()
      .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId);

  group('posting menuntut setiap baris diputuskan', () {
    test('semua baris pending menolak posting', () async {
      final grId = await checkingReceipt();

      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptLinesPendingFailure>()),
      );
      expect(await context.goodReceiptStatusOf(grId), 'checking');
      expect(await context.goodReceiptColumn(grId, 'posted_at'), isNull);
    });

    test('satu baris pending saja tetap menolak posting', () async {
      final grId = await checkingReceipt();
      final detail = await detailOf(grId);
      final check = context.checkGoodReceiptLine();

      for (final line in detail.lines.take(detail.lines.length - 1)) {
        await check.call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: line.shippedQty,
        );
      }

      final failure = await post(
        grId,
      ).then<Object?>((_) => null, onError: (Object error, _) => error);
      expect(failure, isA<GoodReceiptLinesPendingFailure>());
      expect(
        (failure as GoodReceiptLinesPendingFailure).pendingCount,
        1,
        reason: 'Kegagalan harus menyebut baris yang belum diputuskan.',
      );
      expect(await context.goodReceiptStatusOf(grId), 'checking');
    });

    test('semua baris checked berhasil diposting', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      final result = await post(grId);

      expect(result.receipt.status, GoodReceiptStatus.posted);
      expect(await context.goodReceiptStatusOf(grId), 'posted');
      expect(await context.goodReceiptColumn(grId, 'posted_at'), isNotNull);
    });

    test('campuran checked dan rejected berhasil diposting', () async {
      final grId = await checkingReceipt();
      final detail = await detailOf(grId);

      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: detail.lines.first.id,
        reason: 'Rusak',
      );
      final check = context.checkGoodReceiptLine();
      for (final line in detail.lines.skip(1)) {
        await check.call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: line.shippedQty,
        );
      }

      final result = await post(grId);

      expect(result.receipt.status, GoodReceiptStatus.posted);
      expect(result.progress.rejected, 1);
      expect(result.progress.checked, detail.lines.length - 1);
    });

    test('semua baris rejected tetap dapat diposting tanpa movement', () async {
      // A delivery where nothing was acceptable is a real outcome: the decisions are
      // the record, and the discrepancy queue is what the warehouse acts on.
      final grId = await checkingReceipt();
      final detail = await detailOf(grId);
      final reject = context.rejectGoodReceiptLine();
      for (final line in detail.lines) {
        await reject.call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          reason: 'Salah barang',
        );
      }

      final result = await post(grId);

      expect(result.receipt.status, GoodReceiptStatus.posted);
      expect(result.movements, isEmpty);
      expect(await context.goodReceiptMovementCount(grId), 0);
      expect(await context.balancesAt(fixture.branchStore.id), isEmpty);
    });
  });

  group('progres keputusan', () {
    test('hitungan progres benar di setiap langkah', () async {
      final grId = await checkingReceipt();
      final detail = await detailOf(grId);

      expect(detail.progress.total, 3);
      expect(detail.progress.pending, 3);
      expect(detail.progress.decided, 0);
      expect(detail.progress.allDecided, isFalse);
      expect(detail.progress.label, '0/3');
      expect(detail.canPost, isFalse);

      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: detail.lines.first.id,
        receivedQty: detail.lines.first.shippedQty,
      );

      final afterOne = await detailOf(grId);
      expect(afterOne.progress.label, '1/3');
      expect(afterOne.progress.checked, 1);
      expect(afterOne.progress.pending, 2);
      expect(afterOne.canPost, isFalse);

      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      final afterAll = await detailOf(grId);
      expect(afterAll.progress.label, '3/3');
      expect(afterAll.progress.allDecided, isTrue);
      expect(afterAll.canPost, isTrue);
    });

    test('progres kosong tidak dianggap selesai', () async {
      // A receipt with no lines has nothing to have decided, and treating that as
      // "all decided" would let a corrupt document post.
      const empty = GoodReceiptProgress(
        total: 0,
        pending: 0,
        checked: 0,
        rejected: 0,
        shortage: 0,
      );
      expect(empty.allDecided, isFalse);
      expect(GoodReceiptLineDecisionPolicy.allDecided(const []), isFalse);
    });

    test('shortage dihitung terpisah dari rejected', () async {
      final grId = await checkingReceipt();
      final detail = await detailOf(grId);
      final simple = detail.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );

      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: simple.id,
        receivedQty: Quantity.parse('1'),
      );

      final after = await detailOf(grId);
      expect(after.progress.checked, 1);
      expect(after.progress.rejected, 0);
      expect(after.progress.shortage, 1);
    });
  });

  group('revisi keputusan selama checking', () {
    test('checked dapat diubah menjadi rejected', () async {
      final grId = await checkingReceipt();
      final line = (await detailOf(grId)).lines.first;

      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        receivedQty: line.shippedQty,
      );
      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        reason: 'Rusak',
      );

      final revised = (await detailOf(
        grId,
      )).lines.firstWhere((row) => row.id == line.id);
      expect(revised.lineStatus, GoodReceiptLineStatus.rejected);
      expect(revised.receivedQty, Quantity.zero());
      expect(revised.rejectReason, 'Rusak');
    });

    test('rejected dapat diubah kembali menjadi checked', () async {
      final grId = await checkingReceipt();
      final line = (await detailOf(grId)).lines.first;

      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        reason: 'Rusak',
      );
      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        receivedQty: line.shippedQty,
      );

      final revised = (await detailOf(
        grId,
      )).lines.firstWhere((row) => row.id == line.id);
      expect(revised.lineStatus, GoodReceiptLineStatus.checked);
      expect(revised.receivedQty, line.shippedQty);
      // An accepted line carrying the reason it was once refused would be an audit
      // trail for a decision that was reversed.
      expect(revised.rejectReason, isNull);
    });

    test('keputusan dapat direset menjadi pending', () async {
      final grId = await checkingReceipt();
      final line = (await detailOf(grId)).lines.first;

      await context.checkGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
        receivedQty: Quantity.parse('1'),
      );
      await context.resetGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
      );

      final reset = (await detailOf(
        grId,
      )).lines.firstWhere((row) => row.id == line.id);
      expect(reset.lineStatus, GoodReceiptLineStatus.pending);
      // Back to what the snapshot left, so the reader is confirming the shipment
      // again rather than holding a quantity nobody entered.
      expect(reset.receivedQty, line.shippedQty);
      expect(reset.rejectReason, isNull);
    });

    test('reset membuat posting kembali tertolak', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      final line = (await detailOf(grId)).lines.first;

      await context.resetGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: line.id,
      );

      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptLinesPendingFailure>()),
      );
    });
  });

  group('dokumen posted bersifat final', () {
    Future<String> postedReceipt() async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await post(grId);
      return grId;
    }

    test('baris GR posted tidak dapat di-check ulang', () async {
      final grId = await postedReceipt();
      final line = (await detailOf(grId)).lines.first;

      await expectLater(
        context.checkGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: Quantity.parse('1'),
        ),
        throwsA(isA<GoodReceiptAlreadyPostedFailure>()),
      );
    });

    test('baris GR posted tidak dapat ditolak', () async {
      final grId = await postedReceipt();
      final line = (await detailOf(grId)).lines.first;

      await expectLater(
        context.rejectGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          reason: 'Rusak',
        ),
        throwsA(isA<GoodReceiptAlreadyPostedFailure>()),
      );
    });

    test('baris GR posted tidak dapat direset', () async {
      final grId = await postedReceipt();
      final line = (await detailOf(grId)).lines.first;

      await expectLater(
        context.resetGoodReceiptLine().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
        ),
        throwsA(isA<GoodReceiptAlreadyPostedFailure>()),
      );
    });

    test('keputusan tersimpan tidak berubah setelah percobaan itu', () async {
      final grId = await postedReceipt();
      final before = await context.goodReceiptLineRows(grId);
      final line = before.keys.first;

      await context
          .rejectGoodReceiptLine()
          .call(
            actorUserId: fixture.branchHead.id,
            goodReceiptId: grId,
            goodReceiptLineId: line,
            reason: 'Rusak',
          )
          .then<void>((_) {}, onError: (_, _) {});

      expect(await context.goodReceiptLineRows(grId), before);
    });

    test('posting kedua ditolak', () async {
      final grId = await postedReceipt();

      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptAlreadyPostedFailure>()),
      );
      // And exactly one set of movements — three positions, three rows, not six.
      expect(await context.goodReceiptMovementCount(grId), 3);
    });

    test('dua posting bersamaan menulis stok tepat sekali', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      final outcomes = await Future.wait<bool>(
        [context.postGoodReceipt(), context.postGoodReceipt()].map(
          (useCase) => useCase
              .call(actorUserId: fixture.branchHead.id, goodReceiptId: grId)
              .then((_) => true)
              .onError<AppFailure>((_, _) => false),
        ),
      );

      expect(outcomes.where((ok) => ok), hasLength(1));
      expect(await context.goodReceiptStatusOf(grId), 'posted');
      // Three positions, three movements — not six.
      expect(await context.goodReceiptMovementCount(grId), 3);
    });
  });

  group('integritas himpunan baris', () {
    test('baris GR yang hilang terdeteksi saat posting', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      final lineId = (await context.goodReceiptLineRows(grId)).keys.first;

      // A receipt that has quietly lost a line would check in less than was sent,
      // with nobody told: every per-line check still passes.
      await context.corruptByDeleting('good_receipt_lines', lineId);

      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptLineIntegrityFailure>()),
      );
      expect(await context.goodReceiptStatusOf(grId), 'checking');
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test('baris GR tambahan terdeteksi saat posting', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      // A second shipment's allocation, smuggled onto this receipt: posting it would
      // credit stock that never left the warehouse under this document.
      final otherDoId = await shipDeliveryOrderFor(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [
          tieAllocation(fixture, qty: '1', batchId: fixture.tieBatchB.id),
        ],
      );
      final foreign = (await context.deliveries.lineReferences(
        otherDoId,
      )).single;
      await context.database.customStatement(
        'INSERT INTO good_receipt_lines (id, created_at, updated_at, sync_status, '
        'gr_id, do_line_id, item_id, shipped_qty, received_qty, line_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'gr-line-extra',
          nowUtc.toIso8601String(),
          nowUtc.toIso8601String(),
          'pending',
          grId,
          foreign.id,
          foreign.itemId,
          foreign.shippedQty.milliUnits,
          foreign.shippedQty.milliUnits,
          'checked',
        ],
      );

      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptLineIntegrityFailure>()),
      );
      expect(await context.goodReceiptStatusOf(grId), 'checking');
      expect(await context.goodReceiptMovementCount(grId), 0);
    });

    test('inner join tidak menghilangkan baris ketika barang hilang', () async {
      final grId = await checkingReceipt();
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      // The joined detail read inner-joins `items`, so a physically missing item row
      // makes the receipt one line shorter — silently. The plain select behind the
      // integrity check is what notices.
      await context.database.customStatement('PRAGMA foreign_keys = OFF;');
      await context.database.customStatement(
        'DELETE FROM items WHERE id = ?;',
        [fixture.simpleItem.id],
      );
      await context.database.customStatement('PRAGMA foreign_keys = ON;');

      final loaded = await context.receipts.getDetail(grId);
      final stored = await context.receipts.lineReferences(grId);
      expect(
        loaded!.lines.length,
        lessThan(stored.length),
        reason: 'Pola tes usang: join seharusnya menelan baris ini.',
      );

      await expectLater(
        post(grId),
        throwsA(isA<GoodReceiptHistoricalReferenceMissingFailure>()),
      );
      expect(await context.goodReceiptMovementCount(grId), 0);
    });
  });

  group('tidak ada penghapusan baris', () {
    test('repository tidak menawarkan penghapusan baris', () {
      // *"Hapus yang tidak sesuai"* means `rejected` (G-G4), and the audit trail is
      // the point. Asserted against the source because a method that exists will
      // eventually be called.
      final code = readCodeOnly(
        'lib/features/good_receipt/domain/repositories/good_receipt_repository.dart',
      );
      for (final forbidden in [
        'removeLine',
        'deleteLine',
        'softDeleteLine',
        'removeGoodReceipt',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'Repository menawarkan $forbidden.',
        );
      }
    });

    test('DAO tidak menawarkan penghapusan baris', () {
      final code = readCodeOnly('lib/core/db/daos/good_receipt_dao.dart');
      for (final forbidden in [
        'DELETE FROM good_receipt',
        'softDeleteLine',
        'deleteLine',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'DAO menawarkan $forbidden.',
        );
      }
    });

    test('baris rejected tetap ada dan terbaca setelah posting', () async {
      final grId = await checkingReceipt();
      final detail = await detailOf(grId);
      final rejectedId = detail.lines.first.id;

      await context.rejectGoodReceiptLine().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
        goodReceiptLineId: rejectedId,
        reason: 'Tidak dipesan',
      );
      final check = context.checkGoodReceiptLine();
      for (final line in detail.lines.skip(1)) {
        await check.call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
          goodReceiptLineId: line.id,
          receivedQty: line.shippedQty,
        );
      }
      await post(grId);

      final rows = await context.goodReceiptLineRows(grId);
      expect(rows, hasLength(detail.lines.length));
      expect(rows[rejectedId]!['line_status'], 'rejected');
      expect(rows[rejectedId]!['reject_reason'], 'Tidak dipesan');
      expect(rows[rejectedId]!['deleted_at'], isNull);

      final live = await context.database
          .customSelect(
            'SELECT deleted_at FROM good_receipt_lines WHERE id = ?;',
            variables: [Variable<String>(rejectedId)],
          )
          .getSingle();
      expect(live.read<String?>('deleted_at'), isNull);
    });
  });

  group('state machine', () {
    test('checking → posted adalah satu-satunya transisi', () {
      expect(GoodReceiptStatePolicy.nextStatesOf(GoodReceiptStatus.checking), {
        GoodReceiptStatus.posted,
      });
      expect(
        GoodReceiptStatePolicy.nextStatesOf(GoodReceiptStatus.posted),
        isEmpty,
      );
    });

    test('posted tidak dapat dibuka kembali', () {
      expect(
        GoodReceiptStatePolicy.isAllowed(
          GoodReceiptStatus.posted,
          GoodReceiptStatus.checking,
        ),
        isFalse,
      );
      expect(
        GoodReceiptStatePolicy.isAllowed(
          GoodReceiptStatus.posted,
          GoodReceiptStatus.posted,
        ),
        isFalse,
      );
      expect(
        GoodReceiptStatePolicy.isAllowed(
          GoodReceiptStatus.checking,
          GoodReceiptStatus.checking,
        ),
        isFalse,
      );
    });

    test('hanya Kepala Cabang yang boleh memposting', () {
      for (final role in UserRole.values) {
        expect(
          GoodReceiptStatePolicy.isAllowedFor(
            role: role,
            from: GoodReceiptStatus.checking,
            to: GoodReceiptStatus.posted,
          ),
          role == UserRole.kepalaCabang,
          reason: '${role.dbValue} salah dinilai.',
        );
      }
    });
  });
}
