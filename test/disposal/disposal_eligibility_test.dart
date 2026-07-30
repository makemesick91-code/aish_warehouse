import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/disposal/domain/services/disposal_expiry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-E7's eligibility rule, from every direction (§39).
///
/// *"Barang kedaluwarsa dikeluarkan dari stok hanya lewat movement `disposal`."*
/// The word doing the work is **kedaluwarsa**: a batch is usable for the whole of
/// its expiry day and becomes disposable from the next operational day onwards
/// (T-10), so the canonical rule is
///
/// ```
/// expired = operationalDate > expiryDate
/// ```
///
/// and equality — a batch expiring *today* — is the case that must be refused. That
/// boundary is the single most load-bearing line in this milestone, because it is
/// the only thing standing between "removing stock nobody can use" and "removing
/// stock somebody was about to use", and a `disposal` movement has no counter-entry
/// to find the mistake by.
void main() {
  // Mid-afternoon in GMT+8, comfortably away from the day boundary so the ordinary
  // cases are not accidentally testing the boundary too.
  final nowUtc = DateTime.utc(2026, 7, 30, 4);
  final today = AppTimeZone.operationalDate(nowUtc);

  late TestContext context;
  late DisposalFixture fixture;

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDisposalFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> warehouseDraft({String? reason}) => createDisposalDraft(
    context,
    fixture,
    sourceLocationId: fixture.warehouse.id,
    nowUtc: nowUtc,
    reason: reason ?? 'Kedaluwarsa',
  );

  group('kebijakan tanggal (§16)', () {
    test('batch yang lewat satu hari sudah kedaluwarsa', () {
      expect(
        DisposalExpiryPolicy.isExpired(
          expiryDate: DateOnly.addDays(today, -1),
          nowUtc: nowUtc,
        ),
        isTrue,
      );
    });

    test('batch yang kedaluwarsa hari ini belum boleh dimusnahkan', () {
      // The rule is `operationalDate > expiryDate`, so equality is *not* expired.
      // A batch is good until the end of its date (T-10).
      expect(
        DisposalExpiryPolicy.isExpired(expiryDate: today, nowUtc: nowUtc),
        isFalse,
      );
      expect(
        DisposalExpiryPolicy.isDisposable(expiryDate: today, nowUtc: nowUtc),
        isFalse,
      );
    });

    test('batch yang masih berlaku tidak pernah dapat dimusnahkan', () {
      expect(
        DisposalExpiryPolicy.isDisposable(
          expiryDate: DateOnly.addDays(today, 200),
          nowUtc: nowUtc,
        ),
        isFalse,
      );
    });

    test('batch segera kedaluwarsa bukan kandidat pemusnahan', () {
      // Inside the 30-day alert window, so G-E6 badges it orange — and §28 says a
      // badge is all it gets. `isNearExpiry` and `isDisposable` are deliberately
      // disjoint predicates.
      final near = DateOnly.addDays(today, 10);
      expect(
        DisposalExpiryPolicy.isNearExpiry(
          expiryDate: near,
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        isTrue,
      );
      expect(
        DisposalExpiryPolicy.isDisposable(expiryDate: near, nowUtc: nowUtc),
        isFalse,
      );
    });

    test('batch kedaluwarsa tidak dihitung sebagai segera kedaluwarsa', () {
      // The two badges must stay apart, or a screen would say "segera" about
      // something that has already gone.
      final past = DateOnly.addDays(today, -3);
      expect(
        DisposalExpiryPolicy.isNearExpiry(
          expiryDate: past,
          expiryAlertDays: 30,
          nowUtc: nowUtc,
        ),
        isFalse,
      );
    });

    test('daysExpired bernilai nol pada hari kedaluwarsa dan satu sehari '
        'setelahnya', () {
      expect(
        DisposalExpiryPolicy.daysExpired(expiryDate: today, nowUtc: nowUtc),
        0,
      );
      expect(
        DisposalExpiryPolicy.daysExpired(
          expiryDate: DateOnly.addDays(today, -1),
          nowUtc: nowUtc,
        ),
        1,
      );
      // An `int`, never a `double` (§12): a count of days has no fractional part.
      expect(
        DisposalExpiryPolicy.daysExpired(expiryDate: today, nowUtc: nowUtc),
        isA<int>(),
      );
    });
  });

  group('batas hari operasional GMT+8 (§39.14)', () {
    // A batch expiring on 2026-07-30 in operational time. 15:59:59Z on the 29th is
    // still 2026-07-29 in GMT+8; 16:00:00Z is already the 30th. So the batch is
    // valid across both of those instants, and becomes disposable only once the
    // operational date reaches the 31st — which happens at 16:00:00Z on the 30th.
    final expiry = DateTime.utc(2026, 7, 30);

    test('15:59 UTC masih hari sebelumnya, batch belum kedaluwarsa', () {
      final instant = DateTime.utc(2026, 7, 29, 15, 59, 59, 999);
      expect(AppTimeZone.operationalDate(instant), DateTime.utc(2026, 7, 29));
      expect(
        DisposalExpiryPolicy.isDisposable(expiryDate: expiry, nowUtc: instant),
        isFalse,
      );
    });

    test('16:00 UTC sudah hari berikutnya, batch masih belum kedaluwarsa', () {
      final instant = DateTime.utc(2026, 7, 29, 16);
      expect(AppTimeZone.operationalDate(instant), DateTime.utc(2026, 7, 30));
      // The operational day rolled over, but onto the expiry date itself — still
      // not expired.
      expect(
        DisposalExpiryPolicy.isDisposable(expiryDate: expiry, nowUtc: instant),
        isFalse,
      );
    });

    test('16:00 UTC keesokan harinya membuat batch dapat dimusnahkan', () {
      final instant = DateTime.utc(2026, 7, 30, 16);
      expect(AppTimeZone.operationalDate(instant), DateTime.utc(2026, 7, 31));
      expect(
        DisposalExpiryPolicy.isDisposable(expiryDate: expiry, nowUtc: instant),
        isTrue,
      );
    });

    test('15:59:59.999999 UTC keesokan harinya masih menolak', () {
      // One microsecond before the boundary. The whole operational day belongs to
      // the 30th, which is the expiry date.
      final instant = DateTime.utc(2026, 7, 30, 15, 59, 59, 999, 999);
      expect(AppTimeZone.operationalDate(instant), DateTime.utc(2026, 7, 30));
      expect(
        DisposalExpiryPolicy.isDisposable(expiryDate: expiry, nowUtc: instant),
        isFalse,
      );
    });
  });

  group('penambahan baris', () {
    test('batch kedaluwarsa H+1 dapat dipilih', () async {
      final id = await warehouseDraft();
      final line = await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      expect(line.batchId, fixture.expiredBatch.id);
      expect(line.qty, Quantity.parse('1'));
      // Adding a line is not a stock event; posting is.
      expect(await context.disposalMovementCount(id), 0);
    });

    test('batch yang kedaluwarsa hari ini ditolak', () async {
      final id = await warehouseDraft();

      await expectLater(
        addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.todayBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<BatchNotExpiredForDisposalFailure>()),
      );
      expect(await context.disposalLineCount(id), 0);
    });

    test('batch yang sama diterima sehari kemudian', () async {
      // The same position, the same document, one operational day later. Nothing
      // about the batch changed — only what day it is — which is what makes the
      // boundary a *rule* rather than a property of the row.
      final tomorrow = nowUtc.add(const Duration(days: 1));
      final id = await warehouseDraft();

      final line = await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.todayBatch.id,
        qty: '1',
        nowUtc: tomorrow,
      );
      expect(line.batchId, fixture.todayBatch.id);
    });

    test('batch segera kedaluwarsa ditolak', () async {
      final id = await warehouseDraft();

      await expectLater(
        addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.nearBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<BatchNotExpiredForDisposalFailure>()),
      );
    });

    test('batch yang masih berlaku ditolak', () async {
      final id = await warehouseDraft();

      await expectLater(
        addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.validBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<BatchNotExpiredForDisposalFailure>()),
      );
    });

    test(
      'alasan apa pun tidak dapat meloloskan batch yang masih berlaku',
      () async {
        // §16: *"Tidak ada alasan manual yang dapat meloloskan batch belum
        // expired."* The reason is a note, never a key.
        final id = await warehouseDraft(
          reason: 'Kemasan rusak setelah kedaluwarsa — sudah dicek supervisor',
        );

        await expectLater(
          addDisposalPosition(
            context,
            fixture,
            disposalId: id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.validBatch.id,
            qty: '1',
            nowUtc: nowUtc,
            note: 'Sudah dikonfirmasi rusak',
          ),
          throwsA(isA<BatchNotExpiredForDisposalFailure>()),
        );
      },
    );

    test('barang tanpa kedaluwarsa ditolak', () async {
      // §9: this milestone disposes of expired stock and nothing else. An item with
      // `has_expiry = false` has nothing that can be past a date, so a line naming
      // one would be a disposal for some *other* reason — damaged, recalled — with
      // none of that workflow's own rules applied.
      final id = await warehouseDraft();

      await expectLater(
        addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.plainItem.id,
          batchId: fixture.expiredBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DisposalItemMustHaveExpiryFailure>()),
      );
    });

    test('batch milik barang lain ditolak', () async {
      final id = await warehouseDraft();

      await expectLater(
        addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.otherExpiredBatch.id,
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<InvalidDisposalBatchFailure>()),
      );
    });

    test('batch yang tidak ada menghasilkan kegagalan eksplisit', () async {
      // Never a skipped line and never a substitution (§34): a reference that does
      // not resolve is an administrator's problem, stated as such.
      final id = await warehouseDraft();

      await expectLater(
        addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: 'batch-yang-tidak-ada',
          qty: '1',
          nowUtc: nowUtc,
        ),
        throwsA(isA<HistoricalDisposalReferenceMissingFailure>()),
      );
    });

    test('posisi tanpa saldo di lokasi sumber ditolak', () async {
      // `staleBatch` exists only at the warehouse, so from the branch store it is a
      // real, expired batch with nothing behind it.
      final id = await createDisposalDraft(
        context,
        fixture,
        sourceLocationId: fixture.branchStore.id,
        nowUtc: nowUtc,
        actorUserId: fixture.branchHead.id,
        reason: 'Kedaluwarsa',
      );

      await expectLater(
        addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.staleBatch.id,
          qty: '1',
          nowUtc: nowUtc,
          actorUserId: fixture.branchHead.id,
        ),
        throwsA(isA<InsufficientDisposalStockFailure>()),
      );
    });
  });

  group('daftar kandidat (§17)', () {
    test('hanya posisi kedaluwarsa dengan saldo positif yang muncul', () async {
      final positions = await context.disposals.expiredPositions(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
      );

      final batchIds = positions.map((p) => p.batchId).toSet();
      expect(batchIds, contains(fixture.expiredBatch.id));
      expect(batchIds, contains(fixture.staleBatch.id));
      expect(batchIds, contains(fixture.otherExpiredBatch.id));
      // The three that must never be offered, each for its own reason.
      expect(batchIds, isNot(contains(fixture.todayBatch.id)));
      expect(batchIds, isNot(contains(fixture.nearBatch.id)));
      expect(batchIds, isNot(contains(fixture.validBatch.id)));
      // And nothing about an item that has no expiry at all (§9).
      expect(
        positions.map((p) => p.itemId),
        isNot(contains(fixture.plainItem.id)),
      );
    });

    test('kandidat diurutkan dari tanggal kedaluwarsa terlama', () async {
      // Every row here is already expired, so "oldest first" is the risk order §17
      // asks for — the opposite emphasis to FEFO's "use this next", same arithmetic.
      final positions = await context.disposals.expiredPositions(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
      );

      expect(positions.first.batchId, fixture.staleBatch.id);
      for (var i = 1; i < positions.length; i++) {
        expect(
          DateOnly.compare(
            positions[i - 1].expiryDate,
            positions[i].expiryDate,
          ),
          lessThanOrEqualTo(0),
        );
      }
    });

    test('kandidat hanya berasal dari lokasi sumber yang diminta', () async {
      final roomPositions = await context.disposals.expiredPositions(
        sourceLocationId: fixture.locationOne.id,
        nowUtc: nowUtc,
      );

      expect(roomPositions, hasLength(1));
      expect(roomPositions.single.batchId, fixture.expiredBatch.id);
      expect(roomPositions.single.qtyOnHand, Quantity.parse('2.5'));
      expect(roomPositions.single.locationId, fixture.locationOne.id);
    });

    test('filter kategori mempersempit kandidat', () async {
      final obat = await context.disposals.expiredPositions(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
        categoryId: fixture.category.id,
      );

      expect(obat.map((p) => p.itemId).toSet(), {fixture.expiryItem.id});
    });

    test('pencarian menerima nama, SKU dan nomor batch', () async {
      for (final needle in ['anestesi', 'dsp-0001', 'a-stale']) {
        final found = await context.disposals.searchExpiredCandidates(
          sourceLocationId: fixture.warehouse.id,
          nowUtc: nowUtc,
          searchQuery: needle,
        );
        expect(found, isNotEmpty, reason: 'pencarian "$needle" kosong');
      }
    });

    test('pencarian tidak peka huruf besar-kecil', () async {
      final lower = await context.disposals.searchExpiredCandidates(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
        searchQuery: 'anestesi',
      );
      final upper = await context.disposals.searchExpiredCandidates(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
        searchQuery: 'ANESTESI',
      );
      expect(upper.map((p) => p.batchId), lower.map((p) => p.batchId));
    });

    test('picker dibatasi delapan hasil', () async {
      final capped = await context.disposals.searchExpiredCandidates(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
        limit: 2,
      );
      expect(capped, hasLength(2));
    });

    test('kandidat sehari kemudian memasukkan batch hari ini', () async {
      final tomorrow = nowUtc.add(const Duration(days: 1));
      final positions = await context.disposals.expiredPositions(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: tomorrow,
      );

      expect(positions.map((p) => p.batchId), contains(fixture.todayBatch.id));
      // And still not the ones that have not crossed their date.
      expect(
        positions.map((p) => p.batchId),
        isNot(contains(fixture.nearBatch.id)),
      );
    });

    test('barang nonaktif dengan stok kedaluwarsa tetap muncul', () async {
      // §17: a product withdrawn from the catalogue can still be rotting on a
      // shelf, and refusing to list it would leave stock nobody can ever remove.
      await context.deactivate('items', fixture.expiryItem.id);

      final positions = await context.disposals.expiredPositions(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
      );
      final historical = positions.where(
        (p) => p.itemId == fixture.expiryItem.id,
      );
      expect(historical, isNotEmpty);
      expect(historical.first.itemIsHistorical, isTrue);
    });

    test('batch yang diarsipkan tetap muncul dan ditandai historis', () async {
      await context.archive('item_batches', fixture.expiredBatch.id);

      final positions = await context.disposals.expiredPositions(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
      );
      final archived = positions.firstWhere(
        (p) => p.batchId == fixture.expiredBatch.id,
      );
      expect(archived.batchIsHistorical, isTrue);
    });

    test('posisi yang saldonya nol tidak muncul', () async {
      // Destroy the whole of one position, then look again: an empty shelf is not
      // stock anybody can act on.
      final id = await warehouseDraft();
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.staleBatch.id,
        qty: '1.25',
        nowUtc: nowUtc,
      );
      await context
          .postDisposal(clock: () => nowUtc)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      final positions = await context.disposals.expiredPositions(
        sourceLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
      );
      expect(
        positions.map((p) => p.batchId),
        isNot(contains(fixture.staleBatch.id)),
      );
    });

    test(
      'pemusnahan sebagian menyisakan kandidat dengan saldo berkurang',
      () async {
        final id = await warehouseDraft();
        await addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.staleBatch.id,
          // Fixed-point exactness: 1.25 − 0.375 is exactly 0.875, with no residue.
          qty: '0.375',
          nowUtc: nowUtc,
        );
        await context
            .postDisposal(clock: () => nowUtc)
            .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

        final positions = await context.disposals.expiredPositions(
          sourceLocationId: fixture.warehouse.id,
          nowUtc: nowUtc,
        );
        final remaining = positions.firstWhere(
          (p) => p.batchId == fixture.staleBatch.id,
        );
        expect(remaining.qtyOnHand, Quantity.parse('0.875'));
      },
    );
  });

  group('revalidasi saat posting', () {
    test(
      'batch yang belum kedaluwarsa pada saat posting membatalkan dokumen',
      () async {
        // The line was added on a day the batch *was* expired; the posting runs on a
        // clock that is earlier, so by then it was not. That is a device whose clock
        // went backwards, and the posting is the last chance to catch it.
        final tomorrow = nowUtc.add(const Duration(days: 1));
        final id = await warehouseDraft();
        await addDisposalPosition(
          context,
          fixture,
          disposalId: id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.todayBatch.id,
          qty: '1',
          nowUtc: tomorrow,
        );

        await expectLater(
          context
              .postDisposal(clock: () => nowUtc)
              .call(actorUserId: fixture.warehouseUser.id, disposalId: id),
          throwsA(isA<BatchNotExpiredForDisposalFailure>()),
        );

        expect(await context.disposalStatusOf(id), 'draft');
        expect(await context.disposalMovementCount(id), 0);
        expect(await context.disposalLineCount(id), 1);
      },
    );

    test('batch yang kedaluwarsa selama draft terbuka menjadi sah', () async {
      // The other direction, and it matters just as much: a draft is revalidated
      // rather than frozen, so stock that crossed its date while the form sat open
      // becomes disposable rather than stuck.
      final tomorrow = nowUtc.add(const Duration(days: 1));
      final id = await warehouseDraft();
      await addDisposalPosition(
        context,
        fixture,
        disposalId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.todayBatch.id,
        qty: '1',
        nowUtc: tomorrow,
      );

      final result = await context
          .postDisposal(clock: () => tomorrow)
          .call(actorUserId: fixture.warehouseUser.id, disposalId: id);

      expect(result.disposal.isPosted, isTrue);
      expect(result.movements, hasLength(1));
    });
  });
}
