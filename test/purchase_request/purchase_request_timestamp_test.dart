import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/app_date_time_formatter.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/document_timestamp_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';

/// Document timestamps: stored in UTC, ordered as instants, displayed in GMT+8.
///
/// The rule this file protects is why `purchase_requests` carries four event
/// timestamps and not one CHECK comparing them. Timestamps are stored as ISO-8601
/// **TEXT**, so `processing_at >= submitted_at` in SQL compares characters rather than
/// moments: two equally valid serialisations of the same instant — `…000Z` against
/// `…000000Z`, or a `+08:00` suffix against a `Z` one — would order by their text.
/// Ordering therefore lives in `DocumentTimestampPolicy`, on UTC `DateTime` values,
/// and the database restricts itself to which timestamps each status must carry.
///
/// Every clock here is injected (T-7). A test that read the wall clock could not
/// express "the device is three hours behind" at all.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  Future<({PurchaseRequestFixture fixture, String prId})> draft() async {
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
    return (fixture: fixture, prId: request.id);
  }

  /// `2026-07-29T03:00Z` plus [hours].
  DateTime at(int hours) => prWednesdayUtc().add(Duration(hours: hours));

  group('kebijakan urutan (murni)', () {
    test('instan yang sama diterima', () {
      // A submit and a transition really can land on the same microsecond on a fast
      // device, and there is nothing wrong with that document.
      expect(
        () => DocumentTimestampPolicy.requireProcessingNotBeforeSubmit(
          documentId: 'pr-1',
          submittedAtUtc: at(0),
          processingAtUtc: at(0),
        ),
        returnsNormally,
      );
    });

    test('satu mikrosekon lebih awal ditolak', () {
      expect(
        () => DocumentTimestampPolicy.requireProcessingNotBeforeSubmit(
          documentId: 'pr-1',
          submittedAtUtc: at(0),
          processingAtUtc: at(0).subtract(const Duration(microseconds: 1)),
        ),
        throwsA(
          isA<InvalidDocumentTimestampFailure>()
              .having((failure) => failure.documentId, 'documentId', 'pr-1')
              .having(
                (failure) => failure.earlierLabel,
                'earlierLabel',
                'submitted_at',
              )
              .having(
                (failure) => failure.laterLabel,
                'laterLabel',
                'processing_at',
              ),
        ),
      );
    });

    test('event sebelumnya yang null adalah no-op', () {
      // Only reachable for a status the guard has already rejected, or for a draft
      // that has no `submitted_at` at all. Either way there is nothing to compare.
      expect(
        () => DocumentTimestampPolicy.requireCancellationNotBeforeSubmit(
          documentId: 'pr-1',
          submittedAtUtc: null,
          cancelledAtUtc: at(0),
        ),
        returnsNormally,
      );
    });

    test('skew dilaporkan sebagai durasi positif', () {
      try {
        DocumentTimestampPolicy.requireRejectionNotBeforeProcessing(
          documentId: 'pr-1',
          processingAtUtc: at(5),
          rejectedAtUtc: at(2),
        );
        fail('Harus melempar InvalidDocumentTimestampFailure.');
      } on InvalidDocumentTimestampFailure catch (failure) {
        expect(failure.skew, const Duration(hours: 3));
        expect(failure.skew.isNegative, isFalse);
      }
    });

    test('kebijakan tidak membaca jam mana pun', () {
      // Callers pass the instants they are about to persist, which is what keeps the
      // injected clock the single source of "now".
      final source = readLibrarySource(
        'lib/core/time/document_timestamp_policy.dart',
      );
      expect(source, isNot(contains('DateTime.now()')));
    });
  });

  group('timestamp transisi tersimpan UTC', () {
    test('submit menulis submitted_at UTC', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: () => at(1))
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      final request = (await context.requests.getById(setup.prId))!;
      expect(request.submittedAt!.isUtc, isTrue);
      expect(request.submittedAt, at(1));

      // And the stored text carries the `Z` suffix rather than an offset, so a value
      // written in operational time could not be mistaken for this instant.
      final stored = await context.purchaseRequestColumn(
        setup.prId,
        'submitted_at',
      );
      expect(stored, endsWith('Z'));
      expect(stored, isNot(contains('+08:00')));
    });

    test('processing menulis processing_at dan processed_by', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: () => at(1))
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      await context
          .markPurchaseRequestProcessing(clock: () => at(4))
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);

      final request = (await context.requests.getById(setup.prId))!;
      expect(request.processingAt, at(4));
      expect(request.processingAt!.isUtc, isTrue);
      expect(request.processedBy, setup.fixture.warehouseUser.id);
    });

    test('cancel menulis cancelled_at, actor dan alasan', () async {
      final setup = await draft();
      await context
          .cancelPurchaseRequest(clock: () => at(2))
          .call(
            actorUserId: setup.fixture.branchHead.id,
            prId: setup.prId,
            reason: 'Sudah tersedia di cabang',
          );

      final request = (await context.requests.getById(setup.prId))!;
      expect(request.cancelledAt, at(2));
      expect(request.cancelledAt!.isUtc, isTrue);
      expect(request.cancelledBy, setup.fixture.branchHead.id);
      expect(request.cancelReason, 'Sudah tersedia di cabang');
    });

    test('reject menulis rejected_at, actor dan alasan', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: () => at(1))
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      await context
          .markPurchaseRequestProcessing(clock: () => at(2))
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);
      await context
          .rejectPurchaseRequest(clock: () => at(6))
          .call(
            actorUserId: setup.fixture.warehouseUser.id,
            prId: setup.prId,
            reason: 'Stok warehouse habis',
          );

      final request = (await context.requests.getById(setup.prId))!;
      expect(request.rejectedAt, at(6));
      expect(request.rejectedAt!.isUtc, isTrue);
      expect(request.rejectedBy, setup.fixture.warehouseUser.id);
      expect(request.rejectReason, 'Stok warehouse habis');
    });

    test('instan yang sama untuk dua event berurutan diterima', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: () => at(1))
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      await context
          .markPurchaseRequestProcessing(clock: () => at(1))
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);

      expect(await context.purchaseRequestStatusOf(setup.prId), 'processing');
    });
  });

  group('jam perangkat yang terbelakang', () {
    test(
      'processing lebih awal dari submit ditolak dan tidak menulis apa pun',
      () async {
        final setup = await draft();
        await context
            .submitPurchaseRequest(clock: () => at(5))
            .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

        await expectLater(
          () => context
              .markPurchaseRequestProcessing(clock: () => at(2))
              .call(
                actorUserId: setup.fixture.warehouseUser.id,
                prId: setup.prId,
              ),
          throwsA(
            isA<InvalidDocumentTimestampFailure>().having(
              (failure) => failure.message,
              'message',
              DocumentTimestampPolicy.deviceClockBehindMessage,
            ),
          ),
        );

        // The whole transition rolls back: no status, no timestamp, no actor.
        expect(await context.purchaseRequestStatusOf(setup.prId), 'submitted');
        expect(
          await context.purchaseRequestColumn(setup.prId, 'processing_at'),
          isNull,
        );
        expect(
          await context.purchaseRequestColumn(setup.prId, 'processed_by'),
          isNull,
        );
      },
    );

    test('reject lebih awal dari processing ditolak', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: () => at(1))
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      await context
          .markPurchaseRequestProcessing(clock: () => at(5))
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);

      await expectLater(
        () => context
            .rejectPurchaseRequest(clock: () => at(3))
            .call(
              actorUserId: setup.fixture.warehouseUser.id,
              prId: setup.prId,
              reason: 'Stok habis',
            ),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'processing');
      expect(
        await context.purchaseRequestColumn(setup.prId, 'reject_reason'),
        isNull,
      );
    });

    test('cancel lebih awal dari submit ditolak', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: () => at(5))
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      await expectLater(
        () => context
            .cancelPurchaseRequest(clock: () => at(1))
            .call(
              actorUserId: setup.fixture.branchHead.id,
              prId: setup.prId,
              reason: 'Berubah pikiran',
            ),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'submitted');
      expect(
        await context.purchaseRequestColumn(setup.prId, 'cancelled_at'),
        isNull,
      );
    });

    test('membatalkan draft tidak dibatasi urutan event apa pun', () async {
      final setup = await draft();

      // A draft has no earlier workflow event, so there is nothing for the ordering
      // rule to compare a cancellation to — and it must not invent one.
      await context
          .cancelPurchaseRequest(clock: () => at(-48))
          .call(
            actorUserId: setup.fixture.branchHead.id,
            prId: setup.prId,
            reason: 'Salah pilih',
          );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'cancelled');
    });
  });

  group('tampilan GMT+8', () {
    test('instan UTC ditampilkan dalam operasional GMT+8', () {
      // 2026-07-29T03:00Z is 11:00 on the same operational day.
      expect(
        AppDateTimeFormatter.dateTimeWithZone(prWednesdayUtc()),
        '29 Jul 2026, 11:00 GMT+8',
      );
      // And 2026-07-29T17:00Z has already rolled over to the 30th operationally.
      expect(
        AppDateTimeFormatter.date(DateTime.utc(2026, 7, 29, 17)),
        '30 Jul 2026',
      );
    });

    test('needed_date adalah civil date dan tidak bergeser', () async {
      final setup = await draft();
      final needed = DateTime.utc(2026, 8, 5);

      await context.updatePurchaseRequest.header(
        actorUserId: setup.fixture.branchHead.id,
        prId: setup.prId,
        neededDate: needed,
      );

      final request = (await context.requests.getById(setup.prId))!;
      expect(request.neededDate, needed);
      // T-9: no timezone conversion on the way in or out, so `2026-08-05` prints as
      // `2026-08-05` and not as the 4th or the 6th.
      expect(
        AppDateTimeFormatter.civilDate(request.neededDate!),
        '05 Agu 2026',
      );
      final stored = await context.purchaseRequestColumn(
        setup.prId,
        'needed_date',
      );
      expect(stored, startsWith('2026-08-05'));
    });

    test('tidak ada toLocal() pada jalur Purchase Request', () {
      // T-4: `toLocal()` follows the device timezone, which is exactly what the
      // operational timezone replaces.
      for (final path in [
        'lib/features/purchase_request',
        'lib/core/time/operational_iso_week.dart',
      ]) {
        for (final file in dartFilesUnder(path)) {
          // Comment-stripped, so a file may *explain* that `toLocal()` is banned
          // without the test reading the explanation as a violation.
          expect(
            readCodeOnly(file).contains('toLocal()'),
            isFalse,
            reason: '$file memanggil toLocal(), yang dilarang oleh T-4.',
          );
        }
      }
    });

    test('minggu operasional dihitung lewat AppTimeZone', () {
      // The week boundary is GMT+8's, never the device's.
      expect(
        AppTimeZone.operationalDate(prWednesdayUtc()),
        DateTime.utc(2026, 7, 29),
      );
      expect(AppTimeZone.isoWeekNumber(DateTime.utc(2026, 7, 29)), 31);
      expect(AppTimeZone.isoWeekYear(DateTime.utc(2026, 7, 29)), 2026);
    });
  });
}
