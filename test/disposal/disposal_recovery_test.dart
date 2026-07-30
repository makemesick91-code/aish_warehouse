import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Documents survive the master data they were written against (§34).
///
/// Two independent rules, and this milestone is the first where they point in
/// *opposite* directions from the earlier ones:
///
/// * **A posted document stays readable** whatever is retired afterwards. That is the
///   same rule every document in this application follows: the joins filter neither
///   `is_active` nor `deleted_at`, and the screens label the row rather than dropping
///   it.
/// * **An existing draft may still be posted against an archived source.** This one
///   is the *opposite* of the Distribusi's, and deliberately: a distribution into an
///   archived room would put goods somewhere nobody is working, so it is refused; a
///   disposal *out of* an archived shelf removes goods that are already unusable from
///   a shelf that still physically holds them. Refusing would leave stock nobody can
///   ever remove — which is precisely the state this milestone exists to end.
///
/// What is never relaxed is that the row must still be *there*. A reference that
/// cannot be resolved at all is an explicit failure naming the table and the id an
/// administrator has to repair — never a skipped line, never a substitution.
void main() {
  final nowUtc = DateTime.utc(2026, 7, 30, 4);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> branchDraft({String? sourceLocationId}) async {
    final id = await createDisposalDraft(
      context,
      fixture,
      sourceLocationId: sourceLocationId ?? fixture.branchStore.id,
      nowUtc: nowUtc,
      actorUserId: fixture.branchHead.id,
      reason: 'Kedaluwarsa',
    );
    await addDisposalPosition(
      context,
      fixture,
      disposalId: id,
      itemId: fixture.expiryItem.id,
      batchId: fixture.expiredBatch.id,
      qty: '1',
      nowUtc: nowUtc,
      actorUserId: fixture.branchHead.id,
    );
    return id;
  }

  Future<String> postedBranchDisposal() async {
    final id = await branchDraft();
    await context
        .postDisposal(clock: () => nowUtc)
        .call(actorUserId: fixture.branchHead.id, disposalId: id);
    return id;
  }

  group('dokumen yang diposting tetap terbaca', () {
    test('setelah lokasi sumber diarsipkan', () async {
      final id = await postedBranchDisposal();
      await context.archive('stock_locations', fixture.branchStore.id);

      final detail = await context.disposals.getForBranch(
        disposalId: id,
        branchId: fixture.branch.id,
      );
      expect(detail, isNotNull);
      expect(detail!.summary.sourceIsHistorical, isTrue);
      expect(detail.summary.source.name, fixture.branchStore.name);
      expect(detail.lines, hasLength(1));
    });

    test('setelah cabang dinonaktifkan', () async {
      final id = await postedBranchDisposal();
      await context.deactivate('branches', fixture.branch.id);

      final detail = await context.disposals.getForBranch(
        disposalId: id,
        branchId: fixture.branch.id,
      );
      expect(detail, isNotNull);
      expect(detail!.summary.branchIsHistorical, isTrue);
      expect(detail.summary.branchName, fixture.branch.name);
    });

    test('setelah ruangan dinonaktifkan', () async {
      final id = await branchDraft(sourceLocationId: fixture.locationOne.id);
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);
      await context.deactivate('rooms', fixture.roomOne.id);

      final detail = await context.disposals.getForBranch(
        disposalId: id,
        branchId: fixture.branch.id,
      );
      expect(detail, isNotNull);
      expect(detail!.summary.roomIsHistorical, isTrue);
      expect(detail.summary.roomName, fixture.roomOne.name);
    });

    test('setelah barang dinonaktifkan', () async {
      final id = await postedBranchDisposal();
      await context.deactivate('items', fixture.expiryItem.id);

      final detail = await context.disposals.getForBranch(
        disposalId: id,
        branchId: fixture.branch.id,
      );
      expect(detail!.lines.single.itemIsHistorical, isTrue);
      expect(detail.lines.single.itemName, fixture.expiryItem.name);
      expect(detail.usesHistoricalMaster, isTrue);
    });

    test('setelah batch diarsipkan', () async {
      final id = await postedBranchDisposal();
      await context.archive('item_batches', fixture.expiredBatch.id);

      final detail = await context.disposals.getForBranch(
        disposalId: id,
        branchId: fixture.branch.id,
      );
      expect(detail!.lines.single.batchIsHistorical, isTrue);
      expect(detail.lines.single.batchNo, fixture.expiredBatch.batchNo);
    });

    test('setelah pembuat maupun pemosting dinonaktifkan', () async {
      final id = await postedBranchDisposal();
      await context.deactivate('users', fixture.branchHead.id);

      final detail = await context.disposals.getForBranch(
        disposalId: id,
        branchId: fixture.branch.id,
      );
      expect(detail!.summary.createdByIsHistorical, isTrue);
      expect(detail.summary.postedByIsHistorical, isTrue);
      // The names survive: an audit trail whose actor becomes anonymous is not one.
      expect(detail.summary.createdByName, fixture.branchHead.fullName);
      expect(detail.summary.postedByName, fixture.branchHead.fullName);
    });

    test('daftar riwayat tetap memuat dokumen historis', () async {
      final id = await postedBranchDisposal();
      await context.archive('stock_locations', fixture.branchStore.id);
      await context.deactivate('items', fixture.expiryItem.id);

      final rows = await context.disposals.listForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows.map((row) => row.id), contains(id));
      expect(rows.single.usesHistoricalMaster, isTrue);
    });
  });

  group('draft yang ada tetap dapat diposting', () {
    test('meski lokasi sumber diarsipkan setelah draft dibuat', () async {
      // The rule that is the opposite of the Distribusi's. The goods are already
      // unusable and still physically on that shelf; taking them off lowers risk.
      final id = await branchDraft();
      await context.archive('stock_locations', fixture.branchStore.id);

      final result = await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);

      expect(result.disposal.isPosted, isTrue);
      expect(result.movements, hasLength(1));
      expect(
        await locationBalance(
          context,
          locationId: fixture.branchStore.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('3'),
      );
    });

    test('meski ruangan sumber dinonaktifkan setelah draft dibuat', () async {
      final id = await branchDraft(sourceLocationId: fixture.locationOne.id);
      await context.deactivate('rooms', fixture.roomOne.id);

      final result = await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);
      expect(result.disposal.isPosted, isTrue);
    });

    test('meski barang dinonaktifkan setelah baris ditambahkan', () async {
      final id = await branchDraft();
      await context.deactivate('items', fixture.expiryItem.id);

      final result = await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);
      expect(result.disposal.isPosted, isTrue);
    });

    test('meski batch diarsipkan setelah baris ditambahkan', () async {
      final id = await branchDraft();
      await context.archive('item_batches', fixture.expiredBatch.id);

      final result = await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.branchHead.id, disposalId: id);
      expect(result.disposal.isPosted, isTrue);
    });

    test('baris baru masih dapat ditambahkan ke stok historis', () async {
      // §17: a product withdrawn from the catalogue can still be rotting on a shelf,
      // and refusing to list it would leave stock nobody can ever remove.
      await context.deactivate('items', fixture.expiryItem.id);
      final id = await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.branchStore.id,
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
        reason: 'Kedaluwarsa',
      );

      final line = await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
      );
      expect(line.itemId, fixture.expiryItem.id);
    });

    test('dokumen baru tetap ditolak untuk lokasi yang diarsipkan', () async {
      // The asymmetry stated in the other direction: completing existing work is
      // allowed, *starting* it on a decommissioned shelf is not (§15).
      await context.archive('stock_locations', fixture.locationTwo.id);

      await expectLater(
        createDisposalDraft(
          context,
          fixture,
          sourceLocationId: fixture.locationTwo.id,
          nowUtc: nowUtc,
          actorUserId: fixture.branchHead.id,
          reason: 'Kedaluwarsa',
        ),
        throwsA(isA<DisposalSourceLocationInactiveFailure>()),
      );
    });
  });

  group('referensi yang benar-benar hilang', () {
    test('barang yang hilang menghasilkan kegagalan eksplisit, bukan baris '
        'yang dilewati', () async {
      final id = await branchDraft();
      await context.corruptByDeleting('items', fixture.expiryItem.id);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, disposalId: id),
        throwsA(isA<AppFailure>()),
      );
      // Not a shrunken document: the line is still there, and nothing moved.
      expect(await context.disposalLineCount(id), 1);
      expect(await context.disposalMovementCount(id), 0);
      expect(await context.disposalStatusOf(id), 'draft');
    });

    test('batch yang hilang menghasilkan kegagalan eksplisit', () async {
      final id = await branchDraft();
      await context.corruptByDeleting('item_batches', fixture.expiredBatch.id);

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, disposalId: id),
        throwsA(isA<AppFailure>()),
      );
      expect(await context.disposalLineCount(id), 1);
      expect(await context.disposalMovementCount(id), 0);
    });

    test('tidak ada lokasi pengganti yang dipilih diam-diam', () async {
      // There are two branch-store-shaped locations in the fixture; a path that
      // "resolved" a source by type would happily pick the other branch's.
      final id = await branchDraft();
      await context.corruptByDeleting(
        'stock_locations',
        fixture.branchStore.id,
      );

      await expectLater(
        context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.branchHead.id, disposalId: id),
        throwsA(isA<AppFailure>()),
      );

      // The other branch's shelf is untouched — nothing was substituted.
      expect(
        await locationBalance(
          context,
          locationId: fixture.otherBranchStore.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        Quantity.parse('4'),
      );
      expect(await context.disposalMovementCount(id), 0);
    });
  });
}
