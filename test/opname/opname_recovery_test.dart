import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/opname/domain/repositories/opname_repository.dart';
import 'package:aish_warehouse/features/opname/domain/use_cases/review_stock_opname_use_case.dart';
import 'package:aish_warehouse/features/opname/presentation/pages/opname_review_detail_page.dart';
import 'package:aish_warehouse/features/opname/presentation/pages/opname_review_list_page.dart';
import 'package:aish_warehouse/features/opname/presentation/widgets/historical_master_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Milestone 2.1, risk 2 — a `submitted` document must not become unfinishable
/// because master data was deactivated or archived after it was submitted.
///
/// The asymmetry under test is the whole point:
///
/// * **New** work still demands active master data. A count may not be started
///   against a retired room, and a deactivated item may not be added to a
///   draft.
/// * **Existing** work is completed against whatever it already references.
///   `submitted` has no transition back to `draft`, so a document that could
///   not be reviewed could never be resolved at all — it would sit in the
///   inbox forever.
///
/// The one thing that genuinely stops a review is a reference that resolves to
/// nothing. Nothing is invented, substituted or guessed; the whole transaction
/// rolls back and the document stays exactly where it was.
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildOpnameFixture(context);
  });

  tearDown(() => context.dispose());

  /// A submitted document with a 2.5 box shortage on the plain item.
  Future<String> submitted() =>
      submitOpnameFor(context, fixture, note: 'Dua setengah box terpakai');

  Future<StockOpnameReviewResult> review(String id) => context
      .reviewOpname()
      .call(actorUserId: fixture.branchHead.id, opnameId: id);

  Future<Quantity> roomBalance() => roomBalanceOf(context, fixture);

  group('dokumen baru tetap menuntut master aktif', () {
    test('membuat opname ditolak bila ruangan sudah nonaktif', () async {
      await context.deactivate('rooms', fixture.secondRoom.id);

      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.secondRoom.id,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('membuat opname ditolak bila ruangan sudah diarsipkan', () async {
      await context.archive('rooms', fixture.secondRoom.id);

      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.secondRoom.id,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });

    test('membuat opname ditolak bila lokasi stok sudah diarsipkan', () async {
      final location = await context.master.activeRoomLocation(
        fixture.secondRoom.id,
      );
      await context.archive('stock_locations', location!.id);

      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.secondRoom.id,
        ),
        throwsA(isA<InvalidLocationFailure>()),
      );
    });

    test('menambah baris ditolak bila barang sudah nonaktif', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.secondRoom.id,
      );
      await context.deactivate('items', fixture.simpleItem.id);

      await expectLater(
        context.addOpnameLine.call(
          actorUserId: fixture.nurse.id,
          opnameId: opname.id,
          itemId: fixture.simpleItem.id,
          countedQty: Quantity.parse('1'),
          note: 'Ditemukan di rak',
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });
  });

  group('lookup master yang recovery bergantung padanya', () {
    // `requireHistoricalItem` and the batch guard rely on `itemById` /
    // `batchById` returning soft-deleted rows. Unlike rooms and locations,
    // those two have no explicit `active…`/`historical…` pair — the behaviour
    // is implicit in the absence of a `deleted_at` filter, and `userById` two
    // lines away in the same DAO *does* filter it. Someone tidying the DAO for
    // consistency would reintroduce the stranding bug with nothing to stop
    // them. These tests are that something.

    test('itemById mengembalikan barang yang sudah diarsipkan', () async {
      await context.archive('items', fixture.simpleItem.id);

      final item = await context.master.itemById(fixture.simpleItem.id);

      expect(
        item,
        isNotNull,
        reason:
            'itemById tidak boleh memfilter deleted_at: review dokumen '
            'historis bergantung padanya.',
      );
      expect(item!.sku, fixture.simpleItem.sku);
    });

    test('batchById mengembalikan batch yang sudah diarsipkan', () async {
      await context.archive('item_batches', fixture.validBatch.id);

      final batch = await context.master.batchById(fixture.validBatch.id);

      expect(batch, isNotNull);
      expect(batch!.batchNo, fixture.validBatch.batchNo);
    });

    test('historicalRoomById mengembalikan ruangan yang diarsipkan', () async {
      await context.archive('rooms', fixture.room.id);

      expect(await context.master.activeRoomById(fixture.room.id), isNull);
      expect(
        await context.master.historicalRoomById(fixture.room.id),
        isNotNull,
      );
    });

    test(
      'historicalRoomLocation mengembalikan lokasi yang diarsipkan',
      () async {
        await context.archive('stock_locations', fixture.roomLocation.id);

        expect(
          await context.master.activeRoomLocation(fixture.room.id),
          isNull,
        );
        final location = await context.master.historicalRoomLocation(
          fixture.room.id,
        );
        expect(location, isNotNull);
        expect(location!.id, fixture.roomLocation.id);
        expect(location.isArchived, isTrue);
      },
    );
  });

  group('dokumen submitted tetap terbaca', () {
    test('detail tetap terbaca setelah ruangan nonaktif', () async {
      final id = await submitted();
      await context.deactivate('rooms', fixture.room.id);

      final detail = await context.opnames.getDetailForBranch(
        opnameId: id,
        branchId: fixture.branch.id,
      );

      expect(detail, isNotNull);
      expect(detail!.summary.roomName, fixture.room.name);
      expect(detail.summary.roomIsHistorical, isTrue);
      expect(detail.summary.usesHistoricalMaster, isTrue);
    });

    test('detail tetap terbaca setelah ruangan diarsipkan', () async {
      final id = await submitted();
      await context.archive('rooms', fixture.room.id);

      final detail = await context.opnames.getDetail(id);

      expect(detail, isNotNull);
      expect(detail!.summary.roomIsHistorical, isTrue);
    });

    test('tetap muncul pada daftar review setelah ruangan nonaktif', () async {
      final id = await submitted();
      await context.deactivate('rooms', fixture.room.id);

      final inbox = await context.opnames.list(
        submittedForBranch(fixture.branch.id),
      );

      expect(inbox.map((row) => row.id), contains(id));
      expect(inbox.single.roomIsHistorical, isTrue);
    });

    test('tetap muncul pada daftar setelah cabang nonaktif', () async {
      final id = await submitted();
      await context.deactivate('branches', fixture.branch.id);

      final inbox = await context.opnames.list(
        submittedForBranch(fixture.branch.id),
      );

      expect(inbox.map((row) => row.id), contains(id));
      expect(inbox.single.branchIsHistorical, isTrue);
    });

    test('tetap muncul setelah perawat penghitung nonaktif', () async {
      final id = await submitted();
      await context.deactivate('users', fixture.nurse.id);

      final inbox = await context.opnames.list(
        submittedForBranch(fixture.branch.id),
      );

      expect(inbox.map((row) => row.id), contains(id));
      expect(inbox.single.countedByIsHistorical, isTrue);
      // The name is still shown: the document says who counted it, and that
      // fact does not change when the account is closed.
      expect(inbox.single.countedByName, fixture.nurse.fullName);
    });

    test('baris barang nonaktif ditandai tanpa dihilangkan', () async {
      final id = await submitted();
      await context.deactivate('items', fixture.simpleItem.id);

      final detail = await context.opnames.getDetail(id);
      final line = detail!.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );

      expect(line.itemIsHistorical, isTrue);
      expect(detail.lines, hasLength(3));
    });

    test('dokumen reviewed historis tetap terbaca', () async {
      final id = await submitted();
      await review(id);
      await context.deactivate('rooms', fixture.room.id);
      await context.deactivate('items', fixture.simpleItem.id);

      final detail = await context.opnames.getDetail(id);

      expect(detail, isNotNull);
      expect(detail!.opname.isReviewed, isTrue);
      expect(detail.summary.roomIsHistorical, isTrue);
      expect(detail.lines, isNotEmpty);
    });
  });

  group('review tetap dapat diselesaikan', () {
    test('berhasil setelah ruangan nonaktif', () async {
      final id = await submitted();
      await context.deactivate('rooms', fixture.room.id);

      final result = await review(id);

      expect(result.opname.isReviewed, isTrue);
      expect(await roomBalance(), Quantity.parse('8'));
    });

    test('berhasil setelah ruangan diarsipkan', () async {
      final id = await submitted();
      await context.archive('rooms', fixture.room.id);

      final result = await review(id);

      expect(result.opname.isReviewed, isTrue);
      expect(await roomBalance(), Quantity.parse('8'));
    });

    test('berhasil setelah lokasi stok diarsipkan', () async {
      final id = await submitted();
      await context.archive('stock_locations', fixture.roomLocation.id);

      final result = await review(id);

      expect(result.opname.isReviewed, isTrue);
      // Posted against the very location that was archived — no substitute was
      // chosen, and the balances that live there are the ones adjusted.
      expect(await roomBalance(), Quantity.parse('8'));
      expect(
        result.adjustments.map((a) => a.movement?.fromLocationId),
        contains(fixture.roomLocation.id),
      );
    });

    test('berhasil setelah barang nonaktif', () async {
      final id = await submitted();
      await context.deactivate('items', fixture.simpleItem.id);

      final result = await review(id);

      expect(result.opname.isReviewed, isTrue);
      expect(await roomBalance(), Quantity.parse('8'));
    });

    test('berhasil setelah batch diarsipkan', () async {
      final id = await submitted();
      await context.archive('item_batches', fixture.validBatch.id);

      final result = await review(id);

      expect(result.opname.isReviewed, isTrue);
    });

    test('berhasil setelah perawat penghitung nonaktif', () async {
      final id = await submitted();
      await context.deactivate('users', fixture.nurse.id);

      final result = await review(id);

      expect(result.opname.isReviewed, isTrue);
      expect(result.opname.countedBy, fixture.nurse.id);
    });

    test(
      'berhasil setelah cabang nonaktif bila reviewer masih aktif',
      () async {
        final id = await submitted();
        await context.deactivate('branches', fixture.branch.id);

        final result = await review(id);

        expect(result.opname.isReviewed, isTrue);
        expect(result.opname.branchId, fixture.branch.id);
      },
    );

    test(
      'berhasil setelah kategori barang nonaktif dihapus dari pilihan',
      () async {
        final id = await submitted();
        // Categories carry no `is_active`; archiving is the only way they leave
        // the picker, and it must not take the document with them.
        await context.archive('item_categories', fixture.category.id);

        final result = await review(id);

        expect(result.opname.isReviewed, isTrue);
      },
    );

    test(
      'berhasil setelah seluruh master terkait nonaktif sekaligus',
      () async {
        final id = await submitted();
        await context.deactivate('branches', fixture.branch.id);
        await context.deactivate('rooms', fixture.room.id);
        await context.deactivate('items', fixture.simpleItem.id);
        await context.deactivate('items', fixture.expiryItem.id);
        await context.deactivate('users', fixture.nurse.id);
        await context.archive('stock_locations', fixture.roomLocation.id);

        final result = await review(id);

        expect(result.opname.isReviewed, isTrue);
        expect(await roomBalance(), Quantity.parse('8'));
      },
    );
  });

  group('syarat reviewer tetap ketat', () {
    test('reviewer nonaktif tetap ditolak', () async {
      final id = await submitted();
      await context.deactivate('users', fixture.branchHead.id);

      await expectLater(review(id), throwsA(isA<InactiveEntityFailure>()));
      expect(await context.statusOf(id), 'submitted');
    });

    test('reviewer cabang lain tetap ditolak', () async {
      final id = await submitted();

      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.otherBranchHead.id,
          opnameId: id,
        ),
        throwsA(isA<UnauthorizedBranchFailure>()),
      );
      expect(await context.statusOf(id), 'submitted');
    });

    test('reviewer yang menghitung sendiri tetap ditolak', () async {
      final id = await submitted();
      // A second branch head who is also the counter is not constructible, so
      // the check runs against the nurse's own attempt, which fails on role
      // first — and the branch head who did not count still succeeds.
      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(await context.statusOf(id), 'submitted');
    });
  });

  group('referensi yang benar-benar hilang', () {
    test('lokasi stok hilang menghasilkan kegagalan eksplisit', () async {
      final id = await submitted();
      await context.corruptByDeleting(
        'stock_locations',
        fixture.roomLocation.id,
      );

      await expectLater(
        review(id),
        throwsA(
          isA<HistoricalReferenceMissingFailure>()
              .having((f) => f.entity, 'entity', 'stock_locations')
              .having((f) => f.opnameId, 'opnameId', id)
              .having(
                (f) => f.message,
                'message',
                contains('lokasi stok historis tidak ditemukan'),
              ),
        ),
      );
    });

    test('ruangan hilang menghasilkan kegagalan eksplisit', () async {
      final id = await submitted();
      await context.corruptByDeleting('rooms', fixture.room.id);

      // The header join drops the whole document when its room row is gone, so
      // the failure is reported against the header rather than against
      // `rooms` — but it is still a broken-reference failure naming the stuck
      // document, not a misleading "not found".
      await expectLater(
        review(id),
        throwsA(
          isA<HistoricalReferenceMissingFailure>()
              .having((f) => f.entity, 'entity', 'stock_opnames')
              .having((f) => f.opnameId, 'opnameId', id)
              .having(
                (f) => f.message,
                'message',
                contains('Hubungi administrator'),
              ),
        ),
      );
      expect(await context.statusOf(id), 'submitted');
    });

    test(
      'id yang benar-benar tidak ada tetap dilaporkan sebagai tidak ada',
      () async {
        await expectLater(
          review('opname-tidak-ada'),
          throwsA(isA<StockOpnameNotFoundFailure>()),
        );
      },
    );

    test('barang hilang menghasilkan kegagalan eksplisit', () async {
      final id = await submitted();
      await context.corruptByDeleting('items', fixture.simpleItem.id);

      await expectLater(
        review(id),
        throwsA(
          isA<HistoricalReferenceMissingFailure>().having(
            (f) => f.entity,
            'entity',
            'items',
          ),
        ),
      );
    });

    test('batch hilang menghasilkan kegagalan eksplisit', () async {
      final id = await submitted();
      await context.corruptByDeleting('item_batches', fixture.validBatch.id);

      await expectLater(
        review(id),
        throwsA(
          isA<HistoricalReferenceMissingFailure>().having(
            (f) => f.entity,
            'entity',
            'item_batches',
          ),
        ),
      );
    });

    test('kegagalan membatalkan seluruh movement dan saldo', () async {
      final id = await submitted();
      final balanceBefore = await roomBalance();
      final movementsBefore = await context.movementCountFor(id);

      // The room's location is fine; the *item* is what is broken, so the
      // failure lands after the location has been resolved and the posting
      // loop is already in reach. Nothing may survive it.
      await context.corruptByDeleting('items', fixture.simpleItem.id);

      await expectLater(
        review(id),
        throwsA(isA<HistoricalReferenceMissingFailure>()),
      );

      expect(await context.statusOf(id), 'submitted');
      expect(await context.movementCountFor(id), movementsBefore);
      expect(await roomBalance(), balanceBefore);
    });

    test('submit menolak barang yang hilang selagi masih draft', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      await context.corruptByDeleting('items', fixture.simpleItem.id);

      // Caught while the document can still be repaired, rather than at review
      // when `submitted` has no way back to `draft`.
      await expectLater(
        context.submitOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: opname.id,
        ),
        throwsA(
          isA<HistoricalReferenceMissingFailure>().having(
            (f) => f.entity,
            'entity',
            'items',
          ),
        ),
      );
      expect(await context.statusOf(opname.id), 'draft');
    });

    test('dokumen tetap dapat direview setelah referensi dipulihkan', () async {
      final id = await submitted();
      await context.corruptByDeleting(
        'stock_locations',
        fixture.roomLocation.id,
      );
      await expectLater(
        review(id),
        throwsA(isA<HistoricalReferenceMissingFailure>()),
      );

      // An administrator restores the row with its original id — the document
      // was never mutated, so it simply works again.
      await context.database.customStatement(
        'INSERT INTO stock_locations (id, created_at, updated_at, sync_status, '
        'type, branch_id, room_id, name) '
        "VALUES (?, ?, ?, 'pending', 'room', ?, ?, ?);",
        [
          fixture.roomLocation.id,
          DateTime.utc(2026).toIso8601String(),
          DateTime.utc(2026).toIso8601String(),
          fixture.branch.id,
          fixture.room.id,
          fixture.room.name,
        ],
      );

      final result = await review(id);
      expect(result.opname.isReviewed, isTrue);
    });
  });

  group('UI menandai master historis', () {
    testWidgets('detail review menampilkan badge data historis', (
      tester,
    ) async {
      final id = await submitted();
      await context.deactivate('rooms', fixture.room.id);

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      expect(find.byKey(HistoricalMasterBadge.badgeKey), findsWidgets);
      expect(find.textContaining('Data historis'), findsWidgets);
      // The document itself is fully readable, badge or not — the room's name
      // is still shown and the review action is still offered.
      expect(find.textContaining(fixture.room.name), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Review & Kunci'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('daftar review tidak menyembunyikan dokumen historis', (
      tester,
    ) async {
      final id = await submitted();
      await context.deactivate('rooms', fixture.room.id);
      await context.deactivate('users', fixture.nurse.id);

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: const OpnameReviewListPage(),
      );

      final docNumber = (await context.opnames.getById(id))!.docNumber;
      expect(find.text(docNumber), findsOneWidget);
      expect(find.byKey(HistoricalMasterBadge.badgeKey), findsWidgets);
      expect(find.textContaining('Ruangan, Perawat'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('dokumen tanpa master historis tidak menampilkan badge', (
      tester,
    ) async {
      final id = await submitted();

      await pumpOpnameWidget(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        child: OpnameReviewDetailPage(opnameId: id),
      );

      expect(find.byKey(HistoricalMasterBadge.badgeKey), findsNothing);

      await disposeWidget(tester);
    });
  });

  group('alur aktif yang sudah ada tidak berubah', () {
    test('review normal tetap menyesuaikan saldo', () async {
      final id = await submitted();

      final result = await review(id);

      expect(result.opname.isReviewed, isTrue);
      expect(result.postedMovementCount, 1);
      expect(await roomBalance(), Quantity.parse('8'));
    });
  });
}
