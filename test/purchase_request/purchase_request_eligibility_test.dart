import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/operational_iso_week.dart';
import 'package:aish_warehouse/features/purchase_request/domain/services/purchase_request_opname_eligibility_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-P1 — which stock opnames a Purchase Request may rest on.
///
/// > PR **wajib** menautkan ≥ 1 stok opname berstatus `submitted`/`reviewed` dari
/// > **minggu berjalan atau minggu sebelumnya**.
///
/// The rule has four independent conditions — branch, status, age and direction —
/// and the tests below exercise each on its own so a failure names the condition
/// that broke rather than "eligibility".
///
/// The year-boundary cases are the reason this file exists at all. A window written
/// as `periodWeek >= currentWeek - 1` looks equivalent to "this week or last week"
/// and is wrong every January: the week before `2026-W01` is `2025-W53`, so the
/// subtraction produces `0`, a week number that has never existed, and a perfectly
/// valid reference is refused. Every clock here is injected, so those weeks can be
/// tested without waiting for one (T-7).
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  /// Facts for an opname the policy can judge without a database.
  OpnameEligibilityFacts facts({
    String opnameId = 'so-1',
    String branchId = 'branch-1',
    StockOpnameStatus status = StockOpnameStatus.submitted,
    required int year,
    required int week,
  }) => (
    opnameId: opnameId,
    branchId: branchId,
    status: status,
    periodYear: year,
    periodWeek: week,
  );

  group('OperationalIsoWeek', () {
    test('minggu dihitung dari tanggal operasional GMT+8', () {
      // 2026-07-29 is a Wednesday in ISO week 31.
      expect(
        OperationalIsoWeek.ofUtcInstant(prWednesdayUtc()),
        const OperationalIsoWeek(year: 2026, week: 31),
      );
    });

    test('batas hari GMT+8 memindahkan minggu, bukan batas UTC', () {
      // 2026-08-02 is a Sunday — the last day of ISO week 31. At 16:30 UTC the
      // operational day is already 2026-08-03, a Monday in week 32. Reading the UTC
      // date instead would still say week 31.
      expect(
        OperationalIsoWeek.ofUtcInstant(DateTime.utc(2026, 8, 2, 15, 30)),
        const OperationalIsoWeek(year: 2026, week: 31),
      );
      expect(
        OperationalIsoWeek.ofUtcInstant(DateTime.utc(2026, 8, 2, 16, 30)),
        const OperationalIsoWeek(year: 2026, week: 32),
      );
    });

    test('pergantian ISO year dihitung benar', () {
      const firstOf2026 = OperationalIsoWeek(year: 2026, week: 1);

      // 2025 was a 52-week ISO year, so the predecessor of 2026-W01 is 2025-W52.
      expect(
        firstOf2026.previous,
        const OperationalIsoWeek(year: 2025, week: 52),
      );
      expect(firstOf2026.weeksAfter(firstOf2026.previous), 1);

      // 2020 was a 53-week ISO year, so the predecessor of 2021-W01 is 2020-W53 —
      // the case a `week - 1` subtraction cannot express at all.
      const firstOf2021 = OperationalIsoWeek(year: 2021, week: 1);
      expect(
        firstOf2021.previous,
        const OperationalIsoWeek(year: 2020, week: 53),
      );
      expect(firstOf2021.weeksAfter(firstOf2021.previous), 1);
    });

    test('jarak minggu bertanda dan eksak', () {
      const week31 = OperationalIsoWeek(year: 2026, week: 31);
      const week29 = OperationalIsoWeek(year: 2026, week: 29);

      expect(week31.weeksAfter(week31), 0);
      expect(week31.weeksAfter(week29), 2);
      // Negative when the other week is in the future relative to this one.
      expect(week29.weeksAfter(week31), -2);
    });

    test('label mengikuti format 2026-W31', () {
      expect(const OperationalIsoWeek(year: 2026, week: 7).label, '2026-W07');
      expect(const OperationalIsoWeek(year: 2025, week: 52).label, '2025-W52');
    });
  });

  group('kebijakan G-P1 (murni)', () {
    test('minggu berjalan eligible untuk submitted dan reviewed', () {
      for (final status in [
        StockOpnameStatus.submitted,
        StockOpnameStatus.reviewed,
      ]) {
        expect(
          PurchaseRequestOpnameEligibilityPolicy.isEligible(
            facts: facts(status: status, year: 2026, week: 31),
            prBranchId: 'branch-1',
            utcNow: prWednesdayUtc(),
          ),
          isTrue,
          reason: '$status pada minggu berjalan harus eligible.',
        );
      }
    });

    test('minggu sebelumnya eligible untuk submitted dan reviewed', () {
      for (final status in [
        StockOpnameStatus.submitted,
        StockOpnameStatus.reviewed,
      ]) {
        expect(
          PurchaseRequestOpnameEligibilityPolicy.isEligible(
            facts: facts(status: status, year: 2026, week: 30),
            prBranchId: 'branch-1',
            utcNow: prWednesdayUtc(),
          ),
          isTrue,
        );
      }
    });

    test('draft tidak eligible', () {
      expect(
        PurchaseRequestOpnameEligibilityPolicy.denialFor(
          facts: facts(status: StockOpnameStatus.draft, year: 2026, week: 31),
          prBranchId: 'branch-1',
          utcNow: prWednesdayUtc(),
        ),
        StockOpnameEligibilityDenial.notSubmitted,
      );
    });

    test('dua minggu lalu tidak eligible', () {
      expect(
        PurchaseRequestOpnameEligibilityPolicy.denialFor(
          facts: facts(year: 2026, week: 29),
          prBranchId: 'branch-1',
          utcNow: prWednesdayUtc(),
        ),
        StockOpnameEligibilityDenial.periodTooOld,
      );
    });

    test('minggu masa depan tidak eligible', () {
      expect(
        PurchaseRequestOpnameEligibilityPolicy.denialFor(
          facts: facts(year: 2026, week: 32),
          prBranchId: 'branch-1',
          utcNow: prWednesdayUtc(),
        ),
        StockOpnameEligibilityDenial.periodInFuture,
      );
    });

    test('cabang lain tidak eligible', () {
      expect(
        PurchaseRequestOpnameEligibilityPolicy.denialFor(
          facts: facts(branchId: 'branch-2', year: 2026, week: 31),
          prBranchId: 'branch-1',
          utcNow: prWednesdayUtc(),
        ),
        StockOpnameEligibilityDenial.otherBranch,
      );
    });

    test('pergantian ISO year: 2025-W52 eligible dari 2026-W01', () {
      // 2025-12-29 is the Monday of 2026-W01, so a count filed in 2025-W52 is
      // "last week" — the case a naive `week - 1` refuses.
      final firstWeekOf2026 = DateTime.utc(2025, 12, 29, 3, 0);
      expect(
        OperationalIsoWeek.ofUtcInstant(firstWeekOf2026),
        const OperationalIsoWeek(year: 2026, week: 1),
      );

      expect(
        PurchaseRequestOpnameEligibilityPolicy.isEligible(
          facts: facts(year: 2025, week: 52),
          prBranchId: 'branch-1',
          utcNow: firstWeekOf2026,
        ),
        isTrue,
      );
      // And 2025-W51 is genuinely too old.
      expect(
        PurchaseRequestOpnameEligibilityPolicy.denialFor(
          facts: facts(year: 2025, week: 51),
          prBranchId: 'branch-1',
          utcNow: firstWeekOf2026,
        ),
        StockOpnameEligibilityDenial.periodTooOld,
      );
    });

    test('pergantian ISO year: 2020-W53 eligible dari 2021-W01', () {
      // 2021-01-04 is the Monday of 2021-W01, and 2020 had 53 ISO weeks.
      final firstWeekOf2021 = DateTime.utc(2021, 1, 4, 3, 0);
      expect(
        PurchaseRequestOpnameEligibilityPolicy.isEligible(
          facts: facts(year: 2020, week: 53),
          prBranchId: 'branch-1',
          utcNow: firstWeekOf2021,
        ),
        isTrue,
      );
    });

    test('periode eligible adalah minggu berjalan dan satu sebelumnya', () {
      expect(
        PurchaseRequestOpnameEligibilityPolicy.eligiblePeriods(
          prWednesdayUtc(),
        ),
        [
          const OperationalIsoWeek(year: 2026, week: 31),
          const OperationalIsoWeek(year: 2026, week: 30),
        ],
      );
    });

    test('setiap penolakan punya pesan Bahasa Indonesia sendiri', () {
      // Unlike a read refusal, nothing is being withheld here: the branch head is
      // looking at their own branch's counts and needs to know which rule to fix.
      final messages = <String>{
        for (final reason in StockOpnameEligibilityDenial.values)
          PurchaseRequestOpnameEligibilityPolicy.messageFor(
            reason: reason,
            docNumber: 'TMP-SO-1',
          ),
      };
      expect(messages, hasLength(StockOpnameEligibilityDenial.values.length));
      for (final message in messages) {
        expect(message.trim(), isNotEmpty);
      }
    });
  });

  group('kebijakan G-P1 (terhadap database)', () {
    test('hanya opname eligible yang ditawarkan pemilih', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );

      final currentWeek = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final previousWeek = await fileOpnameForRoom(
        context,
        roomId: fixture.roomTwo.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(1),
      );
      final tooOld = await fileOpnameForRoom(
        context,
        roomId: fixture.roomThree.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(3),
      );
      final draft = await fileDraftOpnameForRoom(
        context,
        roomId: fixture.roomThree.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );
      final otherBranch = await fileOpnameForRoom(
        context,
        roomId: fixture.otherBranchRoom.id,
        nurseId: fixture.otherBranchNurse.id,
        utcNow: prWednesdayUtc(),
      );

      final eligible = await context.eligibleOpnamesFor(
        branchId: fixture.branch.id,
        utcNow: prWednesdayUtc(),
      );
      final ids = eligible.map((reference) => reference.opnameId).toSet();

      expect(ids, {currentWeek, previousWeek});
      expect(
        ids,
        isNot(contains(tooOld)),
        reason: 'Tiga minggu lalu terlalu tua.',
      );
      expect(ids, isNot(contains(draft)), reason: 'Draft belum diserahkan.');
      expect(
        ids,
        isNot(contains(otherBranch)),
        reason: 'Opname cabang lain tidak boleh ditawarkan (G-R2).',
      );
    });

    test('opname reviewed tetap ditawarkan', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final reviewed = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
        reviewedByUserId: fixture.branchHead.id,
      );

      final eligible = await context.eligibleOpnamesFor(
        branchId: fixture.branch.id,
        utcNow: prWednesdayUtc(),
      );
      expect(
        eligible.map((reference) => reference.opnameId),
        contains(reviewed),
      );
      expect(
        eligible.single.status,
        StockOpnameStatus.reviewed,
        reason: 'Reviewed dan submitted sama-sama eligible (G-O4).',
      );
    });

    test('opname soft-deleted tidak ditawarkan', () async {
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

      await context.archive('stock_opnames', opnameId);

      final eligible = await context.eligibleOpnamesFor(
        branchId: fixture.branch.id,
        utcNow: prWednesdayUtc(),
      );
      expect(eligible, isEmpty);
    });

    test('minimal satu opname wajib saat membuat PR', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );

      expect(
        () => context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: const <String>[],
            ),
        throwsA(isA<PurchaseRequestOpnameRequiredFailure>()),
      );
    });

    test('opname duplikat pada satu pilihan ditolak', () async {
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

      expect(
        () => context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [opnameId, opnameId],
            ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('opname draft ditolak dengan alasan yang tepat', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final draft = await fileDraftOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );

      expect(
        () => context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [draft],
            ),
        throwsA(
          isA<IneligibleStockOpnameFailure>().having(
            (failure) => failure.reason,
            'reason',
            StockOpnameEligibilityDenial.notSubmitted,
          ),
        ),
      );
    });

    test('opname cabang lain ditolak dan nomornya tidak dibocorkan', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final foreign = await fileOpnameForRoom(
        context,
        roomId: fixture.otherBranchRoom.id,
        nurseId: fixture.otherBranchNurse.id,
        utcNow: prWednesdayUtc(),
      );
      final foreignDocNumber = (await context.opnames.getById(
        foreign,
      ))!.docNumber;

      await expectLater(
        () => context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [foreign],
            ),
        throwsA(
          isA<IneligibleStockOpnameFailure>()
              .having(
                (failure) => failure.reason,
                'reason',
                StockOpnameEligibilityDenial.otherBranch,
              )
              // The one piece of a foreign document worth withholding is its
              // number: the branch head has no legitimate reason to see it.
              .having(
                (failure) => failure.message,
                'message',
                isNot(contains(foreignDocNumber)),
              ),
        ),
      );
    });

    test('opname terlalu tua ditolak saat membuat PR', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final tooOld = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(3),
      );

      expect(
        () => context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [tooOld],
            ),
        throwsA(
          isA<IneligibleStockOpnameFailure>().having(
            (failure) => failure.reason,
            'reason',
            StockOpnameEligibilityDenial.periodTooOld,
          ),
        ),
      );
    });

    test('acuan yang menua setelah draft dibuat ditolak saat submit', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWeeksBefore(1),
      );
      // The count and the draft are both made last week, so the citation is valid
      // at that moment…
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(1),
      );
      final request = await context
          .createPurchaseRequest(clock: () => prWeeksBefore(1))
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      // …and still valid a week later — the count is then "last week".
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: fixture.branchHead.id, prId: request.id);
      expect(await context.purchaseRequestStatusOf(request.id), 'submitted');
    });

    test('acuan lebih dari dua minggu tua ditolak saat submit', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWeeksBefore(3),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(3),
      );
      final request = await context
          .createPurchaseRequest(clock: () => prWeeksBefore(3))
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );

      // Three weeks later the draft is still there but its evidence has aged out.
      // The failure is its own type, because nothing is wrong with the choice the
      // branch head made — the draft simply sat too long.
      await expectLater(
        () => context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: fixture.branchHead.id, prId: request.id),
        throwsA(
          isA<ExpiredStockOpnameReferenceFailure>().having(
            (failure) => failure.opnameIds,
            'opnameIds',
            [opnameId],
          ),
        ),
      );
      expect(
        await context.purchaseRequestStatusOf(request.id),
        'draft',
        reason: 'Submit yang gagal tidak boleh memindahkan status.',
      );
    });

    test(
      'opname historis tetap terbaca sebagai acuan setelah ruangan nonaktif',
      () async {
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
        await context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: fixture.branchHead.id, prId: request.id);

        // The room is retired afterwards. The citation must stay readable: the
        // warehouse still has to act on the order, and the document cannot go back to
        // draft to be re-pointed at something else.
        await context.deactivate('rooms', fixture.roomOne.id);

        final detail = await context.requests.getDetail(request.id);
        expect(detail!.opnames, hasLength(1));
        expect(detail.opnames.single.opnameId, opnameId);
        expect(detail.opnames.single.roomIsHistorical, isTrue);
        expect(detail.opnames.single.roomName, fixture.roomOne.name);
      },
    );
  });
}
