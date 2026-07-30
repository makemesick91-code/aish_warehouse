import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Creating a draft and filling it in (§21.1/§21.2).
///
/// The two halves of the form: a header that exists before anything is chosen, and a
/// FEFO allocation per (room, item) position. Everything here asserts what the
/// *database* holds afterwards rather than what the use case returned, because the
/// return value cannot tell a stored allocation from a discarded one.
void main() {
  late TestContext context;
  late DistributionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDistributionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('membuat draft', () {
    test('Kepala Cabang membuat draft kosong untuk cabangnya', () async {
      final distribution = await context
          .createDistribution(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id);

      expect(distribution.isDraft, isTrue);
      expect(distribution.branchId, fixture.branch.id);
      expect(distribution.distributedBy, fixture.branchHead.id);
      expect(distribution.postedAt, isNull);
      expect(distribution.isPendingSync, isTrue);
      expect(distribution.createdAt, nowUtc);
      expect(distribution.createdAt.isUtc, isTrue);

      expect(await context.distributionStatusOf(distribution.id), 'draft');
      expect(await context.distributionLineCount(distribution.id), 0);
      // Creating a document is not a stock event (spec §2.5).
      expect(await context.distributionMovementCount(distribution.id), 0);
    });

    test('nomor sementara berbentuk TMP-DIST-{uuid}', () async {
      final distribution = await context
          .createDistribution(clock: () => nowUtc, idGenerator: () => 'abc-123')
          .call(actorUserId: fixture.branchHead.id);

      expect(distribution.docNumber, 'TMP-DIST-abc-123');
    });

    test('dua draft untuk cabang yang sama diperbolehkan', () async {
      // Unlike a Purchase Request (G-P4) there is no "one active document per branch"
      // rule for distributions: a branch head may prepare several and post whichever
      // is ready. Which of them can commit is decided at posting against live
      // balances (§18), not by a unique index here.
      final first = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      final second = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      expect(first, isNot(second));
      final list = await context.distributions.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(list.map((summary) => summary.id), containsAll([first, second]));
    });

    test(
      'catatan dipangkas dan catatan kosong disimpan sebagai null',
      () async {
        final withNote = await context
            .createDistribution(clock: () => nowUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              note: '  Rutin mingguan  ',
            );
        expect(withNote.note, 'Rutin mingguan');

        final blank = await context
            .createDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, note: '   ');
        expect(blank.note, isNull);
      },
    );

    test('gudang cabang yang belum ada menolak pembuatan', () async {
      // Refused when the document is created rather than when it is posted: a branch
      // that cannot supply goods cannot start a distribution, and saying so before the
      // branch head fills in three rooms is the honest answer.
      await context.archive('stock_locations', fixture.branchStore.id);

      expect(
        () => context
            .createDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id),
        throwsA(isA<DistributionBranchStoreNotFoundFailure>()),
      );
    });

    test('dua gudang cabang menolak pembuatan sebagai ambigu', () async {
      // Raw SQL because `ensureLocation` is idempotent and cannot produce this state.
      // A bad import or sync payload can, and §14 says the answer is to refuse rather
      // than guess which store the goods left.
      await context.insertDuplicateLocation(
        id: 'branch-store-duplicate',
        type: 'branch_store',
        name: 'Gudang Cabang Uji Kedua',
        branchId: fixture.branch.id,
      );

      expect(
        () => context
            .createDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id),
        throwsA(isA<DistributionBranchStoreAmbiguousFailure>()),
      );
    });

    test('cabang yang dinonaktifkan menolak pembuatan', () async {
      await context.deactivate('branches', fixture.branch.id);

      expect(
        () => context
            .createDistribution(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });
  });

  group('menambah barang tanpa ED', () {
    test('satu baris tanpa batch dibuat', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      final result = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2.5',
        nowUtc: nowUtc,
      );

      expect(result.lineCount, 1);
      expect(result.isSplit, isFalse);
      expect(result.totalQty, Quantity.parse('2.5'));
      expect(result.allocations.single.batchId, isNull);

      final rows = await context.distributionLineRows(id);
      expect(rows, hasLength(1));
      final row = rows.values.single;
      expect(row['room_id'], fixture.roomOne.id);
      expect(row['item_id'], fixture.simpleItem.id);
      expect(row['batch_id'], isNull);
      // Stored as milli-units (Q-3), never as a REAL.
      expect(row['qty'], 2500);
      expect(row['fefo_override_reason'], isNull);
    });

    test('qty nol dan negatif ditolak', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      for (final qty in ['0', '0.000']) {
        expect(
          () => addDistributionItem(
            context,
            fixture,
            distributionId: id,
            roomId: fixture.roomOne.id,
            itemId: fixture.simpleItem.id,
            qty: qty,
            nowUtc: nowUtc,
          ),
          throwsA(isA<InvalidDistributionQuantityFailure>()),
        );
      }
      expect(await context.distributionLineCount(id), 0);
    });

    test('desimal tiga angka disimpan persis', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '2.375',
        nowUtc: nowUtc,
      );

      final detail = await context.distributions.getDetail(id);
      expect(detail!.lines.single.qty.format(), '2.375');
    });

    test('barang tanpa saldo gudang cabang ditolak', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.emptyItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DistributionItemHasNoStockFailure>()),
      );
    });

    test(
      'barang nonaktif tidak dapat ditambahkan sebagai baris baru',
      () async {
        final id = await createDistributionDraft(
          context,
          fixture,
          nowUtc: nowUtc,
        );
        await context.deactivate('items', fixture.simpleItem.id);

        expect(
          () => addDistributionItem(
            context,
            fixture,
            distributionId: id,
            roomId: fixture.roomOne.id,
            itemId: fixture.simpleItem.id,
            qty: '1',
            nowUtc: nowUtc,
          ),
          throwsA(isA<InactiveEntityFailure>()),
        );
      },
    );

    test('barang yang sama pada ruangan yang sama ditolak dua kali', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DuplicateDistributionLineFailure>()),
      );
      expect(await context.distributionLineCount(id), 1);
    });
  });

  group('menambah barang ber-ED dengan FEFO', () {
    test('batch dengan ED terdekat dipakai lebih dulu', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      final result = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '2',
        nowUtc: nowUtc,
      );

      // `B-OLD` expires in 10 days and holds exactly 2, so the whole request comes
      // from it — even though `A-NEW` sorts first alphabetically.
      expect(result.lineCount, 1);
      expect(result.allocations.single.batchId, fixture.oldBatch.id);
      expect(result.allocations.single.qty, Quantity.parse('2'));
      expect(result.allocations.single.fefoOverrideReason, isNull);
    });

    test('alokasi terpecah ke beberapa batch bila perlu', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      final result = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '3',
        nowUtc: nowUtc,
      );

      expect(result.isSplit, isTrue);
      expect(result.lineCount, 2);
      expect(result.totalQty, Quantity.parse('3'));

      final byBatch = {
        for (final allocation in result.allocations)
          allocation.batchId: allocation.qty,
      };
      expect(byBatch[fixture.oldBatch.id], Quantity.parse('2'));
      expect(byBatch[fixture.newBatch.id], Quantity.parse('1'));

      // Two rows, one decision: both landed or neither would have.
      expect(await context.distributionLineCount(id), 2);
    });

    test('stok valid kurang menolak seluruh alokasi', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      // The store holds 2 + 4 valid and 3 expired. Asking for 7 must fail rather than
      // return a partial 6 — and the expired 3 must not count.
      expect(
        () => addDistributionItem(
          context,
          fixture,
          distributionId: id,
          roomId: fixture.roomOne.id,
          itemId: fixture.batchItem.id,
          qty: '7',
          nowUtc: nowUtc,
        ),
        throwsA(isA<InsufficientBranchStockFailure>()),
      );
      expect(await context.distributionLineCount(id), 0);
    });

    test('batch kedaluwarsa tidak pernah dialokasikan', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.batchItem.id,
        qty: '6',
        nowUtc: nowUtc,
      );

      final rows = await context.distributionLineRows(id);
      expect(
        rows.values.map((row) => row['batch_id']),
        isNot(contains(fixture.expiredBatch.id)),
      );
      expect(rows, hasLength(2));
    });

    test('ED yang sama tidak memerlukan alasan override', () async {
      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      // `T-A` and `T-B` share an expiry date, so taking either first violates nothing.
      final result = await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.tieItem.id,
        qty: '3',
        nowUtc: nowUtc,
      );

      expect(result.lineCount, 2);
      for (final allocation in result.allocations) {
        expect(allocation.fefoOverrideReason, isNull);
      }
    });
  });

  group('draft bukan reservasi', () {
    test('menambah baris tidak mengubah saldo gudang cabang', () async {
      final before = await branchStoreBalance(
        context,
        fixture,
        itemId: fixture.simpleItem.id,
      );

      final id = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      await addDistributionItem(
        context,
        fixture,
        distributionId: id,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '4',
        nowUtc: nowUtc,
      );

      expect(
        await branchStoreBalance(
          context,
          fixture,
          itemId: fixture.simpleItem.id,
        ),
        before,
      );
      expect(
        await roomBalance(
          context,
          fixture,
          roomId: fixture.roomOne.id,
          itemId: fixture.simpleItem.id,
        ),
        Quantity.zero(),
      );
      expect(await context.distributionMovementCount(id), 0);
    });

    test('dua draft boleh meminta lebih dari saldo bersama-sama', () async {
      // §18: a draft reserves nothing. Both documents may hold 6 of a balance of 10.5;
      // which of them can post is decided at posting, and the second one to try is the
      // one that finds out.
      final first = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );
      final second = await createDistributionDraft(
        context,
        fixture,
        nowUtc: nowUtc,
      );

      await addDistributionItem(
        context,
        fixture,
        distributionId: first,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '6',
        nowUtc: nowUtc,
      );
      await addDistributionItem(
        context,
        fixture,
        distributionId: second,
        roomId: fixture.roomOne.id,
        itemId: fixture.simpleItem.id,
        qty: '6',
        nowUtc: nowUtc,
      );

      expect(await context.distributionLineCount(first), 1);
      expect(await context.distributionLineCount(second), 1);
    });
  });
}
