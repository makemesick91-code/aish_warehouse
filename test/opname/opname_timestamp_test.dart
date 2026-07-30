import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_date_time_formatter.dart';
import 'package:aish_warehouse/core/time/document_timestamp_policy.dart';
import 'package:aish_warehouse/features/opname/presentation/pages/opname_review_detail_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Milestone 2.1, risk 3 — timestamp ordering is a domain rule decided on UTC
/// instants, never a text comparison performed by SQLite.
///
/// Until schema v4 the database carried
/// `CHECK (reviewed_at IS NULL OR submitted_at IS NULL OR reviewed_at >= submitted_at)`.
/// Timestamps are ISO-8601 TEXT, so that `>=` compared characters. Whether it
/// fired depended on how the value happened to be serialised rather than on
/// which moment came first — it could accept an out-of-order pair and reject a
/// correct one. The rule now lives in `DocumentTimestampPolicy` and compares
/// `DateTime`s.
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildOpnameFixture(context);
  });

  tearDown(() => context.dispose());

  final submittedAt = DateTime.utc(2026, 7, 29, 6, 0);

  /// A submitted document, stamped at [submittedAt] by an injected clock so no
  /// assertion here depends on the wall clock (T-7).
  Future<String> submitted() =>
      submitOpnameFor(context, fixture, clock: () => submittedAt);

  Future<void> reviewAt(String id, DateTime reviewedAt) => context
      .reviewOpname(clock: () => reviewedAt)
      .call(actorUserId: fixture.branchHead.id, opnameId: id);

  Future<Quantity> roomBalance() => roomBalanceOf(context, fixture);

  group('urutan waktu dokumen', () {
    test('review setelah submit berhasil', () async {
      final id = await submitted();

      await reviewAt(id, submittedAt.add(const Duration(hours: 2)));

      final opname = await context.opnames.getById(id);
      expect(opname!.isReviewed, isTrue);
      expect(opname.reviewedAt!.isAfter(opname.submittedAt!), isTrue);
    });

    test('review pada instant yang sama persis berhasil', () async {
      final id = await submitted();

      // A fast device really can land both on the same microsecond, and there
      // is nothing wrong with that document.
      await reviewAt(id, submittedAt);

      final opname = await context.opnames.getById(id);
      expect(opname!.isReviewed, isTrue);
      expect(opname.reviewedAt, opname.submittedAt);
    });

    test('review satu mikrodetik lebih awal ditolak', () async {
      final id = await submitted();

      await expectLater(
        reviewAt(id, submittedAt.subtract(const Duration(microseconds: 1))),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );
    });

    test('review satu milidetik lebih awal ditolak', () async {
      final id = await submitted();

      await expectLater(
        reviewAt(id, submittedAt.subtract(const Duration(milliseconds: 1))),
        throwsA(
          isA<InvalidDocumentTimestampFailure>()
              .having((f) => f.documentId, 'documentId', id)
              .having((f) => f.earlierLabel, 'earlierLabel', 'submitted_at')
              .having((f) => f.laterLabel, 'laterLabel', 'reviewed_at')
              .having((f) => f.skew, 'skew', const Duration(milliseconds: 1)),
        ),
      );
    });

    test('pesan kegagalan mengarahkan ke pengaturan waktu perangkat', () async {
      final id = await submitted();

      await expectLater(
        reviewAt(id, submittedAt.subtract(const Duration(hours: 3))),
        throwsA(
          isA<InvalidDocumentTimestampFailure>().having(
            (f) => f.message,
            'message',
            'Waktu perangkat lebih awal dari waktu pengiriman dokumen. '
                'Periksa pengaturan waktu perangkat.',
          ),
        ),
      );
    });
  });

  group('clock skew membatalkan seluruh review', () {
    test('status tetap submitted', () async {
      final id = await submitted();

      await expectLater(
        reviewAt(id, submittedAt.subtract(const Duration(hours: 1))),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );

      expect(await context.statusOf(id), 'submitted');
      final opname = await context.opnames.getById(id);
      expect(opname!.reviewedAt, isNull);
      expect(opname.reviewedBy, isNull);
      expect(opname.submittedAt, submittedAt);
    });

    test('tidak ada movement yang tersisa', () async {
      final id = await submitted();
      final before = await context.movementCountFor(id);

      await expectLater(
        reviewAt(id, submittedAt.subtract(const Duration(hours: 1))),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );

      expect(await context.movementCountFor(id), before);
      expect(before, 0);
    });

    test('saldo tidak berubah', () async {
      final id = await submitted();
      final before = await roomBalance();

      await expectLater(
        reviewAt(id, submittedAt.subtract(const Duration(hours: 1))),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );

      expect(await roomBalance(), before);
      // The count said 8; the balance must still be the pre-review 10.5.
      expect(before, Quantity.parse('10.5'));
    });

    test('dokumen dapat direview lagi setelah jam diperbaiki', () async {
      final id = await submitted();
      await expectLater(
        reviewAt(id, submittedAt.subtract(const Duration(hours: 1))),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );

      await reviewAt(id, submittedAt.add(const Duration(minutes: 5)));

      expect(await context.statusOf(id), 'reviewed');
      expect(await roomBalance(), Quantity.parse('8'));
    });
  });

  group('kebijakan dibandingkan sebagai instant', () {
    test('representasi ISO berbeda tidak memengaruhi hasil', () {
      // Two spellings of the same instant. `.` is 0x2E and `Z` is 0x5A, so
      // lexically `…00.000Z` sorts *before* `…00Z` — a CHECK of
      // `reviewed_at >= submitted_at` on TEXT would reject this pair even
      // though the two moments are equal. Compared as instants they simply
      // are equal, which is the whole reason the rule moved out of SQL.
      const submittedText = '2026-07-29T06:00:00Z';
      const reviewedText = '2026-07-29T06:00:00.000Z';
      expect(reviewedText.compareTo(submittedText), lessThan(0));

      final submitted = DateTime.parse(submittedText);
      final reviewed = DateTime.parse(reviewedText);
      expect(reviewed.isAtSameMomentAs(submitted), isTrue);

      expect(
        () => DocumentTimestampPolicy.requireReviewNotBeforeSubmit(
          documentId: 'so-1',
          submittedAtUtc: submitted,
          reviewedAtUtc: reviewed,
        ),
        returnsNormally,
      );
    });

    test('offset dan Z untuk instant yang sama tidak ditolak', () {
      // Lexically `2026-07-29T14:00:00.000+08:00` sorts *after*
      // `2026-07-29T06:00:00.000Z`, yet they denote the same moment.
      final asZulu = DateTime.parse('2026-07-29T06:00:00.000Z');
      final asOffset = DateTime.parse('2026-07-29T14:00:00.000+08:00').toUtc();

      expect(asZulu.isAtSameMomentAs(asOffset), isTrue);
      expect(
        () => DocumentTimestampPolicy.requireReviewNotBeforeSubmit(
          documentId: 'so-1',
          submittedAtUtc: asOffset,
          reviewedAtUtc: asZulu,
        ),
        returnsNormally,
      );
    });

    test('submitted_at kosong tidak memicu kegagalan kedua', () {
      // A document that is not `submitted` is already refused by the status
      // guard; this must not add a second, confusing error about the same
      // problem.
      expect(
        () => DocumentTimestampPolicy.requireReviewNotBeforeSubmit(
          documentId: 'so-1',
          submittedAtUtc: null,
          reviewedAtUtc: DateTime.utc(2020),
        ),
        returnsNormally,
      );
    });
  });

  group('timestamp tetap UTC, tampilan tetap GMT+8', () {
    test('submitted_at dan reviewed_at tersimpan sebagai UTC', () async {
      final id = await submitted();
      final reviewedAt = submittedAt.add(const Duration(hours: 2));
      await reviewAt(id, reviewedAt);

      final opname = await context.opnames.getById(id);
      expect(opname!.submittedAt!.isUtc, isTrue);
      expect(opname.reviewedAt!.isUtc, isTrue);
      expect(opname.submittedAt, submittedAt);
      expect(opname.reviewedAt, reviewedAt);

      // And on disk, as `…Z` rather than an offset form.
      final row = await context.database
          .customSelect(
            "SELECT submitted_at, reviewed_at FROM stock_opnames "
            "WHERE id = '$id';",
          )
          .getSingle();
      expect(row.read<String>('submitted_at'), endsWith('Z'));
      expect(row.read<String>('reviewed_at'), endsWith('Z'));
    });

    testWidgets('UI menampilkan waktu dalam GMT+8', (tester) async {
      final id = await submitted();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      // 06:00 UTC is 14:00 in operational time (T-2).
      expect(
        AppDateTimeFormatter.dateTimeWithZone(submittedAt),
        contains('14:00'),
      );
      expect(find.textContaining('14:00'), findsWidgets);
      expect(find.textContaining('GMT+8'), findsWidgets);

      await disposeWidget(tester);
    });
  });
}
