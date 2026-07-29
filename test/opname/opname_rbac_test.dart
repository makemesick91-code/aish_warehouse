import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/opname/domain/repositories/opname_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// RBAC (G-R1, G-R2, G-R4) and the state machine (G-S1, G-S2).
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  DateTime now = fixedWednesdayUtc();
  DateTime clock() => now;

  setUp(() async {
    now = fixedWednesdayUtc();
    context = TestContext.create(clock: clock);
    fixture = await buildOpnameFixture(context, now: now);
  });

  tearDown(() => context.dispose());

  Future<String> draftOpname({String? roomId, String? nurseId}) async {
    final opname = await context.createOpname().call(
      actorUserId: nurseId ?? fixture.nurse.id,
      roomId: roomId ?? fixture.room.id,
    );
    return opname.id;
  }

  Future<String> submittedOpname({String? nurseId}) async {
    final id = await draftOpname(nurseId: nurseId);
    await context.submitOpname().call(
      actorUserId: nurseId ?? fixture.nurse.id,
      opnameId: id,
    );
    return id;
  }

  group('G-R1 — Perawat dan ruangannya', () {
    test('perawat dapat membuat opname untuk ruangan cabangnya', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      expect(opname.branchId, fixture.branch.id);
    });

    test('perawat ditolak untuk ruangan cabang lain', () async {
      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.otherBranchRoom.id,
        ),
        throwsA(isA<UnauthorizedRoomFailure>()),
      );
    });

    test('kepala cabang tidak dapat membuat opname', () async {
      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.branchHead.id,
          roomId: fixture.room.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('petugas warehouse tidak dapat membuat opname', () async {
      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.warehouseUser.id,
          roomId: fixture.room.id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('pengguna tidak aktif ditolak', () async {
      await context.database.customStatement(
        "UPDATE users SET is_active = 0 WHERE id = '${fixture.nurse.id}';",
      );

      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.room.id,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('pengguna tidak dikenal ditolak', () async {
      await expectLater(
        context.createOpname().call(
          actorUserId: 'pengguna-tidak-ada',
          roomId: fixture.room.id,
        ),
        throwsA(isA<EntityNotFoundFailure>()),
      );
    });

    test('ruangan tidak aktif ditolak untuk dokumen baru', () async {
      await context.database.customStatement(
        "UPDATE rooms SET is_active = 0 WHERE id = '${fixture.room.id}';",
      );

      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.room.id,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('ruangan tanpa lokasi stok ditolak', () async {
      await context.database.customStatement(
        'DELETE FROM stock_locations '
        "WHERE room_id = '${fixture.secondRoom.id}';",
      );

      await expectLater(
        context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.secondRoom.id,
        ),
        throwsA(isA<InvalidLocationFailure>()),
      );
    });

    test('perawat cabang lain tidak dapat mengedit baris dokumen ini', () async {
      final id = await draftOpname();
      final detail = await context.opnames.getDetail(id);

      // A nurse whose branch differs must be refused even with a valid line id.
      final otherNurse = await context.master.ensureUser(
        email: 'perawat-lain@test.local',
        fullName: 'Perawat Cabang Lain',
        role: UserRole.perawat,
        branchId: fixture.otherBranch.id,
      );

      await expectLater(
        context.updateOpnameLine(
          actorUserId: otherNurse.id,
          lineId: detail!.lines.first.id,
          countedQty: Quantity.parse('1'),
          note: 'Percobaan',
        ),
        throwsA(isA<UnauthorizedBranchFailure>()),
      );
    });
  });

  group('G-R2 / G-R4 — Kepala Cabang dan pemisahan tugas', () {
    test('kepala cabang mereview opname cabangnya', () async {
      final id = await submittedOpname();

      final result = await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: id,
      );
      expect(result.opname.status, StockOpnameStatus.reviewed);
    });

    test('kepala cabang lain ditolak mereview', () async {
      final id = await submittedOpname();

      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.otherBranchHead.id,
          opnameId: id,
        ),
        throwsA(isA<UnauthorizedBranchFailure>()),
      );
    });

    test('perawat tidak dapat mereview', () async {
      final id = await submittedOpname();

      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('penghitung tidak boleh mereview dokumennya sendiri', () async {
      // A branch head who somehow counted the stock may not approve it (G-R4).
      final id = await draftOpname();
      await context.database.customStatement(
        "UPDATE stock_opnames SET counted_by = '${fixture.branchHead.id}' "
        "WHERE id = '$id';",
      );
      await context.database.customStatement(
        "UPDATE stock_opnames SET status = 'submitted', "
        "submitted_at = '2026-07-29T04:00:00.000Z' WHERE id = '$id';",
      );

      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.branchHead.id,
          opnameId: id,
        ),
        throwsA(isA<SelfReviewNotAllowedFailure>()),
      );
    });

    test('database menolak reviewer yang sama dengan penghitung', () async {
      final id = await submittedOpname();

      await expectLater(
        context.database.customStatement(
          "UPDATE stock_opnames SET status = 'reviewed', "
          "reviewed_at = '2026-07-29T05:00:00.000Z', "
          "reviewed_by = '${fixture.nurse.id}' WHERE id = '$id';",
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('kepala cabang tidak aktif ditolak', () async {
      final id = await submittedOpname();
      await context.database.customStatement(
        "UPDATE users SET is_active = 0 WHERE id = '${fixture.branchHead.id}';",
      );

      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.branchHead.id,
          opnameId: id,
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('daftar review hanya memuat submitted dari cabang sendiri', () async {
      final mine = await submittedOpname();

      // A submitted document in the other branch must not appear.
      final otherNurse = await context.master.ensureUser(
        email: 'perawat-lain@test.local',
        fullName: 'Perawat Cabang Lain',
        role: UserRole.perawat,
        branchId: fixture.otherBranch.id,
      );
      final theirs = await context.createOpname().call(
        actorUserId: otherNurse.id,
        roomId: fixture.otherBranchRoom.id,
      );
      // That room holds no stock, so its snapshot is empty and an empty
      // document cannot be submitted — add the counted position first.
      await context.addOpnameLine(
        actorUserId: otherNurse.id,
        opnameId: theirs.id,
        itemId: fixture.simpleItem.id,
        countedQty: Quantity.parse('1'),
        note: 'Ditemukan di ruangan',
      );
      await context.submitOpname().call(
        actorUserId: otherNurse.id,
        opnameId: theirs.id,
      );

      final inbox = await context.opnames.list(
        submittedForBranch(fixture.branch.id),
      );
      expect(inbox.map((row) => row.id), [mine]);
    });
  });

  group('G-S1 / G-S2 — mesin status', () {
    test('draft tidak dapat langsung menjadi reviewed', () async {
      final id = await draftOpname();

      await expectLater(
        context.reviewOpname().call(
          actorUserId: fixture.branchHead.id,
          opnameId: id,
        ),
        throwsA(isA<InvalidStockOpnameStateFailure>()),
      );
    });

    test('submitted tidak dapat kembali menjadi draft', () async {
      final id = await submittedOpname();

      // There is no un-submit anywhere in the API; the guarded transition is
      // the only status writer and it only moves forward.
      final moved = await context.opnames.submit(
        opnameId: id,
        submittedAtUtc: now,
      );
      expect(moved, isFalse);

      final opname = await context.opnames.getById(id);
      expect(opname!.status, StockOpnameStatus.submitted);
    });

    test('submitted tidak dapat dikirim ulang', () async {
      final id = await submittedOpname();

      await expectLater(
        context.submitOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: id,
        ),
        throwsA(isA<InvalidStockOpnameStateFailure>()),
      );
    });

    test('reviewed tidak dapat kembali ke submitted', () async {
      final id = await submittedOpname();
      await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: id,
      );

      final moved = await context.opnames.markReviewed(
        opnameId: id,
        reviewedBy: fixture.branchHead.id,
        reviewedAtUtc: now,
      );
      expect(moved, isFalse);
    });

    test('baris dokumen submitted tidak dapat diedit', () async {
      final id = await submittedOpname();
      final detail = await context.opnames.getDetail(id);
      final line = detail!.lines.first;

      await expectLater(
        context.updateOpnameLine(
          actorUserId: fixture.nurse.id,
          lineId: line.id,
          countedQty: Quantity.parse('99'),
          note: 'Percobaan',
        ),
        throwsA(isA<InvalidStockOpnameStateFailure>()),
      );

      final unchanged = await context.opnames.lineById(line.id);
      expect(unchanged!.countedQty, line.countedQty);
    });

    test('baris tidak dapat ditambahkan ke dokumen submitted', () async {
      final id = await submittedOpname();

      await expectLater(
        context.addOpnameLine(
          actorUserId: fixture.nurse.id,
          opnameId: id,
          itemId: fixture.simpleItem.id,
          countedQty: Quantity.parse('1'),
        ),
        throwsA(isA<InvalidStockOpnameStateFailure>()),
      );
    });

    test('dokumen submitted tidak dapat dihapus lewat workflow', () async {
      final id = await submittedOpname();
      expect(await context.opnames.removeDraft(id), isFalse);
      expect(
        (await context.opnames.getById(id))!.status,
        StockOpnameStatus.submitted,
      );
    });

    test('draft dapat dihapus lewat workflow', () async {
      final id = await draftOpname();
      expect(await context.opnames.removeDraft(id), isTrue);
      expect(await context.opnames.getById(id), isNull);
    });

    test('enum hanya mengizinkan transisi maju', () {
      expect(
        StockOpnameStatus.draft.canTransitionTo(StockOpnameStatus.submitted),
        isTrue,
      );
      expect(
        StockOpnameStatus.draft.canTransitionTo(StockOpnameStatus.reviewed),
        isFalse,
      );
      expect(
        StockOpnameStatus.draft.canTransitionTo(StockOpnameStatus.draft),
        isFalse,
      );
      expect(
        StockOpnameStatus.submitted.canTransitionTo(StockOpnameStatus.reviewed),
        isTrue,
      );
      expect(
        StockOpnameStatus.submitted.canTransitionTo(StockOpnameStatus.draft),
        isFalse,
      );
      expect(
        StockOpnameStatus.submitted.canTransitionTo(
          StockOpnameStatus.submitted,
        ),
        isFalse,
      );
      for (final status in StockOpnameStatus.values) {
        expect(
          StockOpnameStatus.reviewed.canTransitionTo(status),
          isFalse,
          reason: 'reviewed harus final',
        );
      }
    });

    test('hanya reviewed yang bersifat final', () {
      expect(StockOpnameStatus.draft.isFinal, isFalse);
      expect(StockOpnameStatus.submitted.isFinal, isFalse);
      expect(StockOpnameStatus.reviewed.isFinal, isTrue);
    });
  });

  group('penambahan baris', () {
    test('barang yang ditemukan fisik dapat ditambahkan ke draft', () async {
      final id = await draftOpname();

      final extra = await context.master.ensureItem(
        sku: 'TEST-0003',
        name: 'Kapas Dental',
        categoryId: fixture.category.id,
        unit: 'pack',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );

      final line = await context.addOpnameLine(
        actorUserId: fixture.nurse.id,
        opnameId: id,
        itemId: extra.id,
        countedQty: Quantity.parse('0.5'),
        note: 'Ditemukan di laci',
      );

      expect(line.systemQty, Quantity.zero());
      expect(line.countedQty, Quantity.parse('0.5'));
      expect(line.difference, Quantity.parse('0.5'));
      expect(line.batchId, isNull);
    });

    test('barang duplikat ditolak', () async {
      final id = await draftOpname();

      await expectLater(
        context.addOpnameLine(
          actorUserId: fixture.nurse.id,
          opnameId: id,
          itemId: fixture.simpleItem.id,
          countedQty: Quantity.parse('1'),
        ),
        throwsA(isA<DuplicateStockOpnameLineFailure>()),
      );
    });

    test('barang ber-ED wajib memilih batch', () async {
      final id = await draftOpname();
      final newItem = await context.master.ensureItem(
        sku: 'TEST-0004',
        name: 'Obat Baru',
        categoryId: fixture.category.id,
        unit: 'botol',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: true,
      );

      await expectLater(
        context.addOpnameLine(
          actorUserId: fixture.nurse.id,
          opnameId: id,
          itemId: newItem.id,
          countedQty: Quantity.parse('1'),
        ),
        throwsA(isA<BatchRequiredFailure>()),
      );
    });

    test('barang tanpa ED tidak boleh memakai batch', () async {
      final id = await draftOpname();

      await expectLater(
        context.addOpnameLine(
          actorUserId: fixture.nurse.id,
          opnameId: id,
          itemId: fixture.simpleItem.id,
          batchId: fixture.validBatch.id,
          countedQty: Quantity.parse('1'),
        ),
        throwsA(isA<BatchNotAllowedFailure>()),
      );
    });

    test('batch milik barang lain ditolak', () async {
      final id = await draftOpname();
      final otherExpiryItem = await context.master.ensureItem(
        sku: 'TEST-0005',
        name: 'Obat Lain',
        categoryId: fixture.category.id,
        unit: 'botol',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: true,
      );

      await expectLater(
        context.addOpnameLine(
          actorUserId: fixture.nurse.id,
          opnameId: id,
          itemId: otherExpiryItem.id,
          batchId: fixture.validBatch.id,
          countedQty: Quantity.parse('1'),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('barang nonaktif tidak dapat ditambahkan', () async {
      final id = await draftOpname();
      final inactive = await context.master.ensureItem(
        sku: 'TEST-0006',
        name: 'Barang Nonaktif',
        categoryId: fixture.category.id,
        unit: 'pcs',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );
      await context.database.customStatement(
        "UPDATE items SET is_active = 0 WHERE id = '${inactive.id}';",
      );

      await expectLater(
        context.addOpnameLine(
          actorUserId: fixture.nurse.id,
          opnameId: id,
          itemId: inactive.id,
          countedQty: Quantity.parse('1'),
        ),
        throwsA(isA<InactiveEntityFailure>()),
      );
    });

    test('batch kedaluwarsa tetap dapat ditambahkan', () async {
      final id = await draftOpname();
      // Remove the snapshot line so the expired batch can be added back
      // manually — the scenario of finding expired stock that the system had
      // already written off.
      final detail = await context.opnames.getDetail(id);
      final expiredLine = detail!.lines.firstWhere(
        (line) => line.batchId == fixture.expiredBatch.id,
      );
      await context.opnames.removeDraftLine(expiredLine.id);

      final line = await context.addOpnameLine(
        actorUserId: fixture.nurse.id,
        opnameId: id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
        countedQty: Quantity.parse('0.5'),
        note: 'Batch kedaluwarsa ditemukan',
      );

      expect(line.batchId, fixture.expiredBatch.id);
      expect(line.isExpiredOn(now), isTrue);
    });

    test('baris tambahan dapat dihapus selama masih draft', () async {
      final id = await draftOpname();
      final extra = await context.master.ensureItem(
        sku: 'TEST-0007',
        name: 'Barang Tambahan',
        categoryId: fixture.category.id,
        unit: 'pcs',
        minStockRoom: 1,
        minStockBranch: 2,
        hasExpiry: false,
      );
      final line = await context.addOpnameLine(
        actorUserId: fixture.nurse.id,
        opnameId: id,
        itemId: extra.id,
        countedQty: Quantity.parse('2'),
        note: 'Ditemukan',
      );

      expect(await context.opnames.removeDraftLine(line.id), isTrue);

      final detail = await context.opnames.getDetail(id);
      expect(
        detail!.lines.map((line) => line.itemId),
        isNot(contains(extra.id)),
      );
    });
  });
}
