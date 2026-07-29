import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// G-O1 … G-O4 — the rules that govern a Stok Opname while it is being filled.
///
/// Every test injects a fixed UTC clock, so nothing here depends on when the
/// suite happens to run (T-7).
void main() {
  late TestContext context;
  late OpnameFixture fixture;

  /// Wednesday 2026-07-29, 03:00 UTC → 11:00 GMT+8, ISO week 31 of 2026.
  DateTime now = fixedWednesdayUtc();
  DateTime clock() => now;

  setUp(() async {
    now = fixedWednesdayUtc();
    context = TestContext.create(clock: clock);
    fixture = await buildOpnameFixture(context, now: now);
  });

  tearDown(() => context.dispose());

  int weekOf(DateTime utc) =>
      AppTimeZone.isoWeekNumber(AppTimeZone.operationalDate(utc));

  int weekYearOf(DateTime utc) =>
      AppTimeZone.isoWeekYear(AppTimeZone.operationalDate(utc));

  group('G-O1 — satu opname per ruangan per minggu ISO', () {
    test('opname pertama minggu ini berhasil dibuat', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      expect(opname.status, StockOpnameStatus.draft);
      expect(opname.roomId, fixture.room.id);
      expect(opname.branchId, fixture.branch.id);
      expect(opname.countedBy, fixture.nurse.id);
      expect(opname.periodYear, weekYearOf(now));
      expect(opname.periodWeek, weekOf(now));
      expect(opname.docNumber, startsWith('TMP-SO-'));
      expect(opname.syncStatus, SyncStatus.pending);
    });

    test('opname kedua untuk ruangan dan minggu yang sama ditolak', () async {
      final create = context.createOpname();
      await create(actorUserId: fixture.nurse.id, roomId: fixture.room.id);

      await expectLater(
        create(actorUserId: fixture.nurse.id, roomId: fixture.room.id),
        throwsA(isA<StockOpnameAlreadyExistsFailure>()),
      );
    });

    test('kegagalan duplikat menunjuk dokumen yang sudah ada', () async {
      final create = context.createOpname();
      final first = await create(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      try {
        await create(actorUserId: fixture.nurse.id, roomId: fixture.room.id);
        fail('duplikat seharusnya ditolak');
      } on StockOpnameAlreadyExistsFailure catch (failure) {
        expect(failure.existingOpnameId, first.id);
        expect(failure.roomId, fixture.room.id);
        expect(failure.periodWeek, weekOf(now));
      }
    });

    test(
      'database menolak duplikat walau pemeriksaan aplikasi dilewati',
      () async {
        final opname = await context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.room.id,
        );

        // Bypass every Dart guard: this is the UNIQUE index doing the work.
        await expectLater(
          context.database.customStatement(
            'INSERT INTO stock_opnames (id, created_at, updated_at, sync_status, '
            'doc_number, branch_id, room_id, period_year, period_week, '
            'counted_by, status) '
            "VALUES ('so-dup', '2026-07-29T00:00:00.000Z', "
            "'2026-07-29T00:00:00.000Z', 'pending', 'TMP-SO-DUP', "
            "'${fixture.branch.id}', '${fixture.room.id}', "
            "${opname.periodYear}, ${opname.periodWeek}, "
            "'${fixture.nurse.id}', 'draft');",
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('ruangan lain pada minggu yang sama berhasil', () async {
      final create = context.createOpname();
      await create(actorUserId: fixture.nurse.id, roomId: fixture.room.id);
      final second = await create(
        actorUserId: fixture.nurse.id,
        roomId: fixture.secondRoom.id,
      );

      expect(second.roomId, fixture.secondRoom.id);
      expect(second.periodWeek, weekOf(now));
    });

    test('ruangan yang sama pada minggu berikutnya berhasil', () async {
      await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      now = now.add(const Duration(days: 7));
      final next = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      expect(next.periodWeek, weekOf(now));
      expect(next.periodWeek, isNot(weekOf(fixedWednesdayUtc())));
    });

    test('periode dihitung memakai kalender operasional GMT+8', () async {
      // 2026-08-02 is a Sunday in GMT+8 — the last day of ISO week 31 — but
      // 17:00 UTC on that day is already Monday 2026-08-03 in Manila, i.e.
      // week 32. Using the UTC date here would file the count under the wrong
      // week (T-3).
      now = DateTime.utc(2026, 8, 2, 17, 0);
      final operational = AppTimeZone.operationalDate(now);
      expect(operational.day, 3);
      expect(operational.month, 8);

      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      expect(opname.periodWeek, AppTimeZone.isoWeekNumber(operational));
      expect(opname.periodWeek, 32);
    });

    test('pergantian tahun ISO memakai week-numbering year', () async {
      // 2027-01-01 (GMT+8) is a Friday belonging to ISO week 53 of 2026.
      now = DateTime.utc(2026, 12, 31, 20, 0);
      final operational = AppTimeZone.operationalDate(now);
      expect(operational.year, 2027);
      expect(operational.month, 1);
      expect(operational.day, 1);

      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      expect(opname.periodYear, 2026);
      expect(opname.periodWeek, 53);
      expect(opname.periodLabel, '2026-W53');
    });

    test('dua permintaan bersamaan hanya menghasilkan satu opname', () async {
      final create = context.createOpname();

      final results =
          await Future.wait([
                create(actorUserId: fixture.nurse.id, roomId: fixture.room.id),
                create(actorUserId: fixture.nurse.id, roomId: fixture.room.id),
              ], eagerError: false)
              .then<List<Object?>>(
                (values) => values,
                onError: (_) => <Object?>[],
              )
              .catchError((_) => <Object?>[]);

      // Whether the loser fails on the application check or on the UNIQUE
      // index, the database must end up with exactly one document.
      expect(results, anything);
      final rows = await context.database
          .customSelect('SELECT id FROM stock_opnames;')
          .get();
      expect(rows, hasLength(1));
    });

    test('opname minggu berjalan terdeteksi untuk tombol buat', () async {
      final create = context.createOpname();
      expect(await create.existingForCurrentWeek(fixture.room.id), isNull);

      final opname = await create(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      final existing = await create.existingForCurrentWeek(fixture.room.id);
      expect(existing?.id, opname.id);
    });
  });

  group('G-O2 — system_qty adalah snapshot', () {
    test('snapshot sama dengan saldo ruangan saat dibuat', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      final detail = await context.opnames.getDetail(opname.id);
      expect(detail!.lines, hasLength(3));

      final simple = detail.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );
      expect(simple.systemQty, Quantity.parse('10.5'));
      expect(simple.batchId, isNull);

      final valid = detail.lines.firstWhere(
        (line) => line.batchId == fixture.validBatch.id,
      );
      expect(valid.systemQty, Quantity.parse('2.375'));

      final expired = detail.lines.firstWhere(
        (line) => line.batchId == fixture.expiredBatch.id,
      );
      expect(expired.systemQty, Quantity.parse('0.5'));
    });

    test(
      'barang ber-ED di-snapshot per batch, non-ED dengan batch null',
      () async {
        final opname = await context.createOpname().call(
          actorUserId: fixture.nurse.id,
          roomId: fixture.room.id,
        );
        final detail = await context.opnames.getDetail(opname.id);

        final expiryLines = detail!.lines
            .where((line) => line.itemId == fixture.expiryItem.id)
            .toList();
        expect(expiryLines, hasLength(2));
        expect(expiryLines.every((line) => line.batchId != null), isTrue);

        final simpleLines = detail.lines
            .where((line) => line.itemId == fixture.simpleItem.id)
            .toList();
        expect(simpleLines, hasLength(1));
        expect(simpleLines.single.batchId, isNull);
      },
    );

    test('counted_qty awal sama dengan system_qty', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      final detail = await context.opnames.getDetail(opname.id);

      for (final line in detail!.lines) {
        expect(line.countedQty, line.systemQty);
        expect(line.difference, Quantity.zero());
        expect(line.hasDifference, isFalse);
        expect(line.requiresNote, isFalse);
      }
    });

    test('mutasi stok setelah create tidak mengubah snapshot', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      // Stock leaves the room after the count started.
      await context.posting.postDisposal(
        locationId: fixture.roomLocation.id,
        itemId: fixture.simpleItem.id,
        qty: Quantity.parse('4'),
        actorUserId: fixture.warehouseUser.id,
        note: 'Pemusnahan uji',
      );

      final balance = await context.inventory.balanceQty(
        locationId: fixture.roomLocation.id,
        itemId: fixture.simpleItem.id,
      );
      expect(balance, Quantity.parse('6.5'));

      final detail = await context.opnames.getDetail(opname.id);
      final line = detail!.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );
      // The sheet still says what the system believed when counting began.
      expect(line.systemQty, Quantity.parse('10.5'));
    });

    test('memuat ulang dokumen mempertahankan snapshot', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      final before = await context.opnames.getDetail(opname.id);
      final after = await context.opnames.getDetail(opname.id);

      expect(
        after!.lines.map((line) => line.systemQty.milliUnits),
        before!.lines.map((line) => line.systemQty.milliUnits),
      );
    });

    test('mengedit hasil hitung tidak mengubah system_qty', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      final detail = await context.opnames.getDetail(opname.id);
      final line = detail!.lines.firstWhere(
        (line) => line.itemId == fixture.simpleItem.id,
      );

      final updated = await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: line.id,
        countedQty: Quantity.parse('0.5'),
        note: 'Sebagian terpakai',
      );

      expect(updated.systemQty, Quantity.parse('10.5'));
      expect(updated.countedQty, Quantity.parse('0.5'));
    });
  });

  group('G-O3 — hasil hitung dan catatan selisih', () {
    late String opnameId;
    late String simpleLineId;

    setUp(() async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      opnameId = opname.id;
      final detail = await context.opnames.getDetail(opnameId);
      simpleLineId = detail!.lines
          .firstWhere((line) => line.itemId == fixture.simpleItem.id)
          .id;
    });

    test('hasil hitung nol valid', () async {
      final line = await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: simpleLineId,
        countedQty: Quantity.zero(),
        note: 'Habis dipakai',
      );

      expect(line.countedQty, Quantity.zero());
      expect(line.difference, Quantity.parse('10.5').let((q) => -q));
    });

    test('hasil hitung 0.5 valid dan tersimpan persis', () async {
      final line = await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: simpleLineId,
        countedQty: Quantity.parse('0.5'),
        note: 'Tersisa setengah box',
      );

      expect(line.countedQty, Quantity.parse('0.5'));
      expect(line.countedQty.format(), '0.5');
      // 0.5 − 10.5 is exactly −10, with no floating point tail.
      expect(line.difference.format(), '-10');
      expect(line.difference.milliUnits, -10000);
    });

    test('hasil hitung negatif ditolak', () async {
      await expectLater(
        context.updateOpnameLine(
          actorUserId: fixture.nurse.id,
          lineId: simpleLineId,
          countedQty: const Quantity.fromMilliUnits(-1),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('selisih nol tidak memerlukan catatan', () async {
      final line = await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: simpleLineId,
        countedQty: Quantity.parse('10.5'),
      );

      expect(line.hasDifference, isFalse);
      expect(line.requiresNote, isFalse);
      expect(line.isSubmittable, isTrue);

      final opname = await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: opnameId,
      );
      expect(opname.status, StockOpnameStatus.submitted);
    });

    test('selisih negatif tanpa catatan menahan submit', () async {
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: simpleLineId,
        countedQty: Quantity.parse('8'),
      );

      await expectLater(
        context.submitOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: opnameId,
        ),
        throwsA(isA<DifferenceNoteRequiredFailure>()),
      );
    });

    test('selisih positif tanpa catatan menahan submit', () async {
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: simpleLineId,
        countedQty: Quantity.parse('12'),
      );

      await expectLater(
        context.submitOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: opnameId,
        ),
        throwsA(isA<DifferenceNoteRequiredFailure>()),
      );
    });

    test('catatan berisi spasi saja dianggap kosong', () async {
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: simpleLineId,
        countedQty: Quantity.parse('8'),
        note: '   ',
      );

      final line = await context.opnames.lineById(simpleLineId);
      expect(line!.note, isNull);
      expect(line.hasNote, isFalse);

      await expectLater(
        context.submitOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: opnameId,
        ),
        throwsA(isA<DifferenceNoteRequiredFailure>()),
      );
    });

    test('kegagalan catatan menyebut setiap baris yang bermasalah', () async {
      final detail = await context.opnames.getDetail(opnameId);
      for (final line in detail!.lines) {
        await context.updateOpnameLine(
          actorUserId: fixture.nurse.id,
          lineId: line.id,
          countedQty: line.systemQty + Quantity.parse('1'),
        );
      }

      try {
        await context.submitOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: opnameId,
        );
        fail('submit seharusnya ditolak');
      } on DifferenceNoteRequiredFailure catch (failure) {
        expect(failure.lineIds, hasLength(3));
      }
    });

    test('catatan valid mengizinkan submit', () async {
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: simpleLineId,
        countedQty: Quantity.parse('8'),
        note: 'Dua box terpakai tanpa tercatat',
      );

      final opname = await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: opnameId,
      );

      expect(opname.status, StockOpnameStatus.submitted);
      expect(opname.submittedAt, isNotNull);
      expect(opname.submittedAt!.isUtc, isTrue);
      expect(opname.submittedAt, now);
      expect(opname.syncStatus, SyncStatus.pending);
    });

    test('selisih desimal tetap eksak', () async {
      await context.updateOpnameLine(
        actorUserId: fixture.nurse.id,
        lineId: simpleLineId,
        countedQty: Quantity.parse('10.375'),
        note: 'Sisa 10.375',
      );

      final line = await context.opnames.lineById(simpleLineId);
      // 10.375 − 10.5 = −0.125 exactly.
      expect(line!.difference.milliUnits, -125);
      expect(line.difference.format(), '-0.125');
    });

    test('dokumen kosong tidak dapat dikirim', () async {
      final detail = await context.opnames.getDetail(opnameId);
      for (final line in detail!.lines) {
        await context.opnames.removeDraftLine(line.id);
      }

      await expectLater(
        context.submitOpname().call(
          actorUserId: fixture.nurse.id,
          opnameId: opnameId,
        ),
        throwsA(isA<EmptyStockOpnameFailure>()),
      );
    });
  });

  group('G-O4 — acuan Purchase Request', () {
    test('draft belum dapat dijadikan acuan PR', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );

      expect(opname.status.isPurchaseRequestReference, isFalse);
      expect(opname.isPurchaseRequestReference, isFalse);
    });

    test('submitted dapat dijadikan acuan PR', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      final submitted = await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: opname.id,
      );

      expect(submitted.isPurchaseRequestReference, isTrue);
    });

    test('reviewed dapat dijadikan acuan PR', () async {
      final opname = await context.createOpname().call(
        actorUserId: fixture.nurse.id,
        roomId: fixture.room.id,
      );
      await context.submitOpname().call(
        actorUserId: fixture.nurse.id,
        opnameId: opname.id,
      );
      final result = await context.reviewOpname().call(
        actorUserId: fixture.branchHead.id,
        opnameId: opname.id,
      );

      expect(result.opname.isPurchaseRequestReference, isTrue);
    });

    test('hanya submitted dan reviewed yang memenuhi syarat', () {
      expect(StockOpnameStatus.draft.isPurchaseRequestReference, isFalse);
      expect(StockOpnameStatus.submitted.isPurchaseRequestReference, isTrue);
      expect(StockOpnameStatus.reviewed.isPurchaseRequestReference, isTrue);
    });
  });
}

/// Small helper so a negative expectation reads as prose.
extension on Quantity {
  T let<T>(T Function(Quantity) transform) => transform(this);
}
