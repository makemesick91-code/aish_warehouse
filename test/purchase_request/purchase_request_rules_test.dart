import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/purchase_request/domain/models/purchase_request_models.dart';
import 'package:aish_warehouse/features/purchase_request/domain/services/purchase_request_quantity_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-P2 and G-P3 — quantity validity, one line per item, and when a request needs a
/// written reason.
///
/// The 150 % threshold is compared in **exact fixed point**, never on `double`. Half
/// of this file is about the boundary: exactly 150 % is allowed, because the rule
/// says `> 150%`, and a `requested.toDouble() > suggested.toDouble() * 1.5`
/// comparison would land on whichever side binary floating point happened to round
/// it to.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  Quantity qty(String value) => Quantity.parse(value);

  /// A branch with one cited count and a draft built from it.
  Future<
    ({
      PurchaseRequestFixture fixture,
      String prId,
      String opnameId,
      int lineCount,
    })
  >
  draftFor(TestContext context) async {
    final fixture = await buildPurchaseRequestFixture(
      context,
      now: prWednesdayUtc(),
    );
    final opnameId = await fileOpnameForRoom(
      context,
      roomId: fixture.roomOne.id,
      nurseId: fixture.nurse.id,
      utcNow: prWednesdayUtc(),
    );
    final request = await context
        .createPurchaseRequest(clock: prWednesdayUtc)
        .call(
          actorUserId: fixture.branchHead.id,
          selectedOpnameIds: [opnameId],
        );
    return (
      fixture: fixture,
      prId: request.id,
      opnameId: opnameId,
      // Ruang Dental 1 is short of `simpleItem` and `spareItem`, so a fresh draft
      // starts with two lines. Asserting against this rather than against a literal
      // keeps the tests about the rule under test instead of about the fixture's par
      // levels.
      lineCount: await context.purchaseRequestLineCount(request.id),
    );
  }

  Future<PurchaseRequestLine> lineOf(String prId, String itemId) async {
    final detail = await context.requests.getDetail(prId);
    return detail!.lines.firstWhere((line) => line.itemId == itemId);
  }

  group('kebijakan 150% (aritmetika eksak)', () {
    test('di bawah 150% bukan pelampauan', () {
      expect(
        PurchaseRequestQuantityPolicy.isAboveSuggestionThreshold(
          suggested: qty('2'),
          requested: qty('2.999'),
        ),
        isFalse,
      );
    });

    test('tepat 150% bukan pelampauan', () {
      // The rule is worded `> 150%`, so exactly one and a half times the suggestion
      // has not exceeded anything.
      expect(
        PurchaseRequestQuantityPolicy.isAboveSuggestionThreshold(
          suggested: qty('2'),
          requested: qty('3'),
        ),
        isFalse,
      );
      expect(
        PurchaseRequestQuantityPolicy.requiresJustification(
          suggested: qty('2'),
          requested: qty('3'),
        ),
        isFalse,
      );
    });

    test('satu milli-unit di atas 150% adalah pelampauan', () {
      expect(
        PurchaseRequestQuantityPolicy.isAboveSuggestionThreshold(
          suggested: qty('2'),
          requested: qty('3.001'),
        ),
        isTrue,
      );
    });

    test('tepat 150% dari saran desimal tetap eksak', () {
      // 0.7 × 1.5 = 1.05. On `double` this is 1.0499999999999998, so a floating
      // point comparison would call an exactly-at-threshold request an exceedance.
      expect(
        PurchaseRequestQuantityPolicy.isAboveSuggestionThreshold(
          suggested: qty('0.7'),
          requested: qty('1.05'),
        ),
        isFalse,
      );
      expect(
        PurchaseRequestQuantityPolicy.isAboveSuggestionThreshold(
          suggested: qty('0.7'),
          requested: qty('1.051'),
        ),
        isTrue,
      );
    });

    test(
      'perbandingan rasio Quantity adalah perkalian silang bilangan bulat',
      () {
        // 6.5 × 1.5 = 9.75 exactly.
        expect(
          qty('9.75').exceedsRatioOf(qty('6.5'), numerator: 3, denominator: 2),
          isFalse,
        );
        expect(
          qty('9.751').exceedsRatioOf(qty('6.5'), numerator: 3, denominator: 2),
          isTrue,
        );
      },
    );

    test('batas bebas catatan dihitung dari saran', () {
      expect(
        PurchaseRequestQuantityPolicy.justificationFreeCeiling(qty('6.5')),
        qty('9.75'),
      );
      expect(
        PurchaseRequestQuantityPolicy.justificationFreeCeiling(Quantity.zero()),
        isNull,
      );
    });
  });

  group('kebijakan permintaan manual', () {
    test('saran nol menjadikan permintaan positif sebagai manual', () {
      expect(
        PurchaseRequestQuantityPolicy.isManualRequest(Quantity.zero()),
        isTrue,
      );
      expect(
        PurchaseRequestQuantityPolicy.requiresJustification(
          suggested: Quantity.zero(),
          requested: qty('1'),
        ),
        isTrue,
        reason:
            '150% dari nol adalah nol, jadi tidak ada rasio yang bermakna — '
            'aturan yang berlaku adalah "permintaan manual".',
      );
    });

    test('pelampauan threshold false ketika tidak ada saran', () {
      // Otherwise the two rules would report the same line twice.
      expect(
        PurchaseRequestQuantityPolicy.isAboveSuggestionThreshold(
          suggested: Quantity.zero(),
          requested: qty('5'),
        ),
        isFalse,
      );
    });

    test('pesan peringatan berbeda untuk manual dan pelampauan', () {
      expect(
        PurchaseRequestQuantityPolicy.warningFor(
          suggested: Quantity.zero(),
          requested: qty('1'),
        ),
        PurchaseRequestQuantityPolicy.manualRequestWarning,
      );
      expect(
        PurchaseRequestQuantityPolicy.warningFor(
          suggested: qty('2'),
          requested: qty('4'),
        ),
        PurchaseRequestQuantityPolicy.aboveThresholdWarning,
      );
      expect(
        PurchaseRequestQuantityPolicy.warningFor(
          suggested: qty('2'),
          requested: qty('2'),
        ),
        isNull,
      );
    });

    test('catatan hanya spasi bukan justifikasi', () {
      expect(PurchaseRequestQuantityPolicy.hasJustification(null), isFalse);
      expect(PurchaseRequestQuantityPolicy.hasJustification(''), isFalse);
      expect(PurchaseRequestQuantityPolicy.hasJustification('   '), isFalse);
      expect(PurchaseRequestQuantityPolicy.hasJustification('\t\n'), isFalse);
      expect(PurchaseRequestQuantityPolicy.hasJustification('Rusak'), isTrue);
    });
  });

  group('G-P2 — jumlah dan keunikan item', () {
    test('jumlah nol ditolak saat mengubah baris', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      expect(
        () => context.updatePurchaseRequest.line(
          actorUserId: setup.fixture.branchHead.id,
          lineId: line.id,
          requestedQty: Quantity.zero(),
        ),
        throwsA(isA<InvalidRequestedQuantityFailure>()),
      );
    });

    test('jumlah negatif ditolak', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      expect(
        () => context.updatePurchaseRequest.line(
          actorUserId: setup.fixture.branchHead.id,
          lineId: line.id,
          requestedQty: const Quantity.fromMilliUnits(-1000),
        ),
        throwsA(isA<InvalidRequestedQuantityFailure>()),
      );
    });

    test('jumlah desimal positif diterima', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      final updated = await context.updatePurchaseRequest.line(
        actorUserId: setup.fixture.branchHead.id,
        lineId: line.id,
        requestedQty: qty('0.5'),
      );
      expect(updated.requestedQty, qty('0.5'));
    });

    test('item duplikat ditolak domain dengan pesan yang menuntun', () async {
      final setup = await draftFor(context);

      await expectLater(
        () => context.addPurchaseRequestLine.call(
          actorUserId: setup.fixture.branchHead.id,
          prId: setup.prId,
          itemId: setup.fixture.simpleItem.id,
          requestedQty: qty('1'),
          note: 'Tambahan',
        ),
        throwsA(
          isA<DuplicatePurchaseRequestItemFailure>().having(
            (failure) => failure.itemId,
            'itemId',
            setup.fixture.simpleItem.id,
          ),
        ),
      );
      expect(
        await context.purchaseRequestLineCount(setup.prId),
        setup.lineCount,
        reason: 'Penolakan duplikat tidak boleh menambah baris.',
      );
    });

    test('baris yang dihapus dapat ditambahkan kembali', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      await context.removePurchaseRequestLine.call(
        actorUserId: setup.fixture.branchHead.id,
        lineId: line.id,
      );
      expect(
        await context.purchaseRequestLineCount(setup.prId),
        setup.lineCount - 1,
      );

      // The partial unique index covers live rows only, so the position is free.
      final added = await context.addPurchaseRequestLine.call(
        actorUserId: setup.fixture.branchHead.id,
        prId: setup.prId,
        itemId: setup.fixture.simpleItem.id,
        requestedQty: qty('2'),
        note: 'Ditambahkan kembali',
      );
      expect(added.itemId, setup.fixture.simpleItem.id);
      expect(
        await context.purchaseRequestLineCount(setup.prId),
        setup.lineCount,
      );
      expect(
        added.id,
        isNot(line.id),
        reason: 'Baris baru, bukan baris lama yang dibangkitkan ulang.',
      );
    });

    test('PR tanpa baris tidak dapat dikirim', () async {
      final setup = await draftFor(context);
      final detail = await context.requests.getDetail(setup.prId);
      for (final line in detail!.lines) {
        await context.removePurchaseRequestLine.call(
          actorUserId: setup.fixture.branchHead.id,
          lineId: line.id,
        );
      }
      expect(await context.purchaseRequestLineCount(setup.prId), 0);

      await expectLater(
        () => context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'draft');
    });
  });

  group('G-P3 — catatan wajib', () {
    test('di bawah 150% tanpa catatan valid dan dapat dikirim', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      // Suggested 2.5 → requested 3 is 120 %.
      await context.updatePurchaseRequest.line(
        actorUserId: setup.fixture.branchHead.id,
        lineId: line.id,
        requestedQty: qty('3'),
      );
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      expect(await context.purchaseRequestStatusOf(setup.prId), 'submitted');
    });

    test('tepat 150% tanpa catatan valid', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      // Suggested 2.5 × 1.5 = 3.75, exactly at the threshold.
      await context.updatePurchaseRequest.line(
        actorUserId: setup.fixture.branchHead.id,
        lineId: line.id,
        requestedQty: qty('3.75'),
      );
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      expect(await context.purchaseRequestStatusOf(setup.prId), 'submitted');
    });

    test('di atas 150% tanpa catatan ditolak saat mengubah baris', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      expect(
        () => context.updatePurchaseRequest.line(
          actorUserId: setup.fixture.branchHead.id,
          lineId: line.id,
          requestedQty: qty('3.751'),
        ),
        throwsA(isA<PurchaseRequestJustificationRequiredFailure>()),
      );
    });

    test('catatan hanya spasi ditolak', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      expect(
        () => context.updatePurchaseRequest.line(
          actorUserId: setup.fixture.branchHead.id,
          lineId: line.id,
          requestedQty: qty('10'),
          note: '    ',
        ),
        throwsA(isA<PurchaseRequestJustificationRequiredFailure>()),
      );
    });

    test('catatan valid diterima dan tersimpan ter-trim', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      final updated = await context.updatePurchaseRequest.line(
        actorUserId: setup.fixture.branchHead.id,
        lineId: line.id,
        requestedQty: qty('10'),
        note: '  Kegiatan bakti sosial  ',
      );
      expect(updated.note, 'Kegiatan bakti sosial');
      expect(updated.requiresJustification, isTrue);
      expect(updated.isSubmittable, isTrue);
    });

    test('permintaan manual wajib catatan sejak ditambahkan', () async {
      final setup = await draftFor(context);

      expect(
        () => context.addPurchaseRequestLine.call(
          actorUserId: setup.fixture.branchHead.id,
          prId: setup.prId,
          itemId: setup.fixture.unstockedItem.id,
          requestedQty: qty('2'),
        ),
        throwsA(isA<PurchaseRequestJustificationRequiredFailure>()),
      );

      final added = await context.addPurchaseRequestLine.call(
        actorUserId: setup.fixture.branchHead.id,
        prId: setup.prId,
        itemId: setup.fixture.unstockedItem.id,
        requestedQty: qty('2'),
        note: 'Persediaan baru',
      );
      expect(added.suggestedQty, Quantity.zero());
      expect(added.isManualRequest, isTrue);
    });

    test('barang nonaktif tidak dapat ditambahkan manual', () async {
      final setup = await draftFor(context);
      await context.deactivate('items', setup.fixture.unstockedItem.id);

      expect(
        () => context.addPurchaseRequestLine.call(
          actorUserId: setup.fixture.branchHead.id,
          prId: setup.prId,
          itemId: setup.fixture.unstockedItem.id,
          requestedQty: qty('2'),
          note: 'Persediaan baru',
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('submit menolak baris tanpa catatan meski UI dilewati', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      // Write straight through SQL, so the use case's own validation is the only
      // thing standing between this and a sent document.
      await context.database.customStatement(
        'UPDATE purchase_request_lines SET requested_qty = ?, note = NULL '
        'WHERE id = ?;',
        [qty('99').milliUnits, line.id],
      );

      await expectLater(
        () => context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId),
        throwsA(
          isA<PurchaseRequestJustificationRequiredFailure>().having(
            (failure) => failure.lineIds,
            'lineIds',
            [line.id],
          ),
        ),
      );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'draft');
    });

    test('seluruh baris bermasalah dilaporkan sekaligus', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);
      final manual = await context.addPurchaseRequestLine.call(
        actorUserId: setup.fixture.branchHead.id,
        prId: setup.prId,
        itemId: setup.fixture.unstockedItem.id,
        requestedQty: qty('2'),
        note: 'Persediaan baru',
      );

      // Strip both justifications behind the use case's back.
      await context.database.customStatement(
        'UPDATE purchase_request_lines SET requested_qty = ?, note = NULL '
        'WHERE id IN (?, ?);',
        [qty('99').milliUnits, line.id, manual.id],
      );

      await expectLater(
        () => context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId),
        throwsA(
          isA<PurchaseRequestJustificationRequiredFailure>().having(
            (failure) => failure.lineIds.toSet(),
            'lineIds',
            {line.id, manual.id},
          ),
        ),
      );
    });

    test('model baris menyediakan predikat G-P3 untuk UI', () async {
      final setup = await draftFor(context);
      final line = await lineOf(setup.prId, setup.fixture.simpleItem.id);

      expect(line.suggestedQty, qty('2.5'));
      expect(line.requiresJustification, isFalse);
      expect(line.isAboveSuggestionThreshold, isFalse);
      expect(line.isManualRequest, isFalse);
      expect(line.difference, Quantity.zero());

      final raised = await context.updatePurchaseRequest.line(
        actorUserId: setup.fixture.branchHead.id,
        lineId: line.id,
        requestedQty: qty('5'),
        note: 'Kegiatan tambahan',
      );
      expect(raised.isAboveSuggestionThreshold, isTrue);
      expect(raised.requiresJustification, isTrue);
      expect(raised.hasNote, isTrue);
      expect(raised.difference, qty('2.5'));
    });
  });
}
