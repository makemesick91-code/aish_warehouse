import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/consumption/domain/models/consumption_models.dart';
import 'package:aish_warehouse/features/consumption/domain/services/consumption_note_policy.dart';
import 'package:aish_warehouse/features/consumption/domain/services/consumption_room_policy.dart';
import 'package:aish_warehouse/features/consumption/domain/services/consumption_state_policy.dart';
import 'package:aish_warehouse/features/consumption/domain/services/consumption_stock_plan_builder.dart';
import 'package:aish_warehouse/features/consumption/presentation/providers/consumption_providers.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The pure pieces: the state machine, the room policy, the note policy, the plan builder,
/// the filter and the models' own derived values (§7/§12/§13/§15/§19/§31).
///
/// Every one of these is a function of its inputs with no database in sight, which is what
/// lets the same rule answer the router, the buttons on a form and the use case that
/// performs the write. A rule duplicated across those three places eventually differs
/// between them, and the disagreement always shows up as a button that exists for a
/// transition the use case refuses.
void main() {
  group('ConsumptionStatePolicy', () {
    test('hanya draft → posted diizinkan', () {
      expect(
        ConsumptionStatePolicy.isAllowed(
          ConsumptionStatus.draft,
          ConsumptionStatus.posted,
        ),
        isTrue,
      );
      // Everything else is refused: no un-post, no double post, no re-entering draft.
      expect(
        ConsumptionStatePolicy.isAllowed(
          ConsumptionStatus.posted,
          ConsumptionStatus.draft,
        ),
        isFalse,
      );
      expect(
        ConsumptionStatePolicy.isAllowed(
          ConsumptionStatus.posted,
          ConsumptionStatus.posted,
        ),
        isFalse,
      );
      expect(
        ConsumptionStatePolicy.isAllowed(
          ConsumptionStatus.draft,
          ConsumptionStatus.draft,
        ),
        isFalse,
      );
    });

    test('posted tidak memiliki transisi keluar', () {
      expect(
        ConsumptionStatePolicy.nextStatesOf(ConsumptionStatus.posted),
        isEmpty,
      );
      expect(ConsumptionStatePolicy.nextStatesOf(ConsumptionStatus.draft), {
        ConsumptionStatus.posted,
      });
    });

    test('hanya perawat yang dapat mendorong transisi', () {
      expect(
        ConsumptionStatePolicy.isAllowedFor(
          role: UserRole.perawat,
          from: ConsumptionStatus.draft,
          to: ConsumptionStatus.posted,
        ),
        isTrue,
      );
      for (final role in [
        UserRole.kepalaCabang,
        UserRole.warehouse,
        UserRole.superAdmin,
      ]) {
        expect(
          ConsumptionStatePolicy.isAllowedFor(
            role: role,
            from: ConsumptionStatus.draft,
            to: ConsumptionStatus.posted,
          ),
          isFalse,
          reason: '${role.dbValue} tidak boleh memposting pemakaian.',
        );
        expect(ConsumptionStatePolicy.actorOf(role), isNull);
      }
    });

    test('writeRole adalah perawat, satu-satunya', () {
      expect(ConsumptionStatePolicy.writeRole, UserRole.perawat);
      expect(ConsumptionStatePolicy.writeRoles, {UserRole.perawat});
      expect(ConsumptionTransitionActor.values, hasLength(1));
    });

    test('enum status: helper sesuai §7', () {
      expect(ConsumptionStatus.draft.isEditable, isTrue);
      expect(ConsumptionStatus.draft.isFinal, isFalse);
      expect(ConsumptionStatus.draft.canPost, isTrue);
      expect(ConsumptionStatus.posted.isEditable, isFalse);
      expect(ConsumptionStatus.posted.isFinal, isTrue);
      expect(ConsumptionStatus.posted.canPost, isFalse);
      expect(
        ConsumptionStatus.draft.canTransitionTo(ConsumptionStatus.posted),
        isTrue,
      );
      expect(
        ConsumptionStatus.posted.canTransitionTo(ConsumptionStatus.draft),
        isFalse,
      );
    });

    test('label status tidak memakai kosakata persetujuan', () {
      expect(ConsumptionStatus.draft.label, 'Draft');
      expect(ConsumptionStatus.posted.label, 'Sudah Diposting');
      for (final status in ConsumptionStatus.values) {
        expect(status.label, isNot(contains('Setuju')));
        expect(status.label, isNot(contains('Persetujuan')));
        expect(status.label, isNot(contains('Menunggu')));
      }
    });

    test('nilai database round-trip', () {
      for (final status in ConsumptionStatus.values) {
        expect(ConsumptionStatus.fromDbValue(status.dbValue), status);
      }
      expect(
        () => ConsumptionStatus.fromDbValue('approved'),
        throwsArgumentError,
      );
    });
  });

  group('ConsumptionRoomPolicy', () {
    const branchId = 'b1';
    const room = MasterRoom(
      id: 'r1',
      branchId: branchId,
      code: 'R1',
      name: 'Ruang Dental 1',
      isActive: true,
    );

    test('hanya perawat yang dapat mengonsumsi', () {
      expect(ConsumptionRoomPolicy.canConsume(UserRole.perawat), isTrue);
      for (final role in [
        UserRole.kepalaCabang,
        UserRole.warehouse,
        UserRole.superAdmin,
      ]) {
        expect(ConsumptionRoomPolicy.canConsume(role), isFalse);
      }
    });

    test('hanya lokasi bertipe room yang diizinkan', () {
      expect(ConsumptionRoomPolicy.allowedSourceTypes, {
        StockLocationType.room,
      });
      expect(
        ConsumptionRoomPolicy.allowedSourceTypes,
        isNot(contains(StockLocationType.warehouse)),
      );
      expect(
        ConsumptionRoomPolicy.allowedSourceTypes,
        isNot(contains(StockLocationType.branchStore)),
      );
    });

    test('ruangan aktif cabang sendiri diterima', () {
      expect(
        ConsumptionRoomPolicy.verifyRoom(
          room: room,
          branchId: branchId,
        ).isAccepted,
        isTrue,
      );
    });

    test('cabang diperiksa sebelum keaktifan', () {
      // The order matters: a message about another branch's room must not confirm whether
      // it is switched on.
      const foreignInactive = MasterRoom(
        id: 'r2',
        branchId: 'b2',
        code: 'R1',
        name: 'Ruang Cabang Lain',
        isActive: false,
      );
      expect(
        ConsumptionRoomPolicy.verifyRoom(
          room: foreignInactive,
          branchId: branchId,
        ).rejection,
        ConsumptionRoomRejection.branchMismatch,
      );
    });

    test('ruangan nonaktif dan diarsipkan ditolak', () {
      expect(
        ConsumptionRoomPolicy.verifyRoom(
          room: const MasterRoom(
            id: 'r1',
            branchId: branchId,
            code: 'R1',
            name: 'x',
            isActive: false,
          ),
          branchId: branchId,
        ).rejection,
        ConsumptionRoomRejection.inactive,
      );
      expect(
        ConsumptionRoomPolicy.verifyRoom(
          room: const MasterRoom(
            id: 'r1',
            branchId: branchId,
            code: 'R1',
            name: 'x',
            isActive: true,
            isArchived: true,
          ),
          branchId: branchId,
        ).rejection,
        ConsumptionRoomRejection.inactive,
      );
    });

    test('ruangan null ditolak sebagai missing', () {
      expect(
        ConsumptionRoomPolicy.verifyRoom(
          room: null,
          branchId: branchId,
        ).rejection,
        ConsumptionRoomRejection.missing,
      );
    });

    test('historis: nonaktif diterima, cabang lain tetap ditolak', () {
      const retired = MasterRoom(
        id: 'r1',
        branchId: branchId,
        code: 'R1',
        name: 'x',
        isActive: false,
      );
      expect(
        ConsumptionRoomPolicy.verifyHistoricalRoom(
          room: retired,
          branchId: branchId,
        ).isAccepted,
        isTrue,
        reason: 'Dokumen posted harus tetap terbaca (§33).',
      );
      expect(
        ConsumptionRoomPolicy.verifyHistoricalRoom(
          room: retired,
          branchId: 'b2',
        ).rejection,
        ConsumptionRoomRejection.branchMismatch,
      );
    });

    test('lokasi: nol dan lebih dari satu dibedakan', () {
      expect(
        ConsumptionRoomPolicy.verifyRoomLocation(
          room: room,
          branchId: branchId,
          locations: const [],
        ).rejection,
        ConsumptionRoomRejection.locationMissing,
      );
      expect(
        ConsumptionRoomPolicy.verifyRoomLocation(
          room: room,
          branchId: branchId,
          locations: const [
            MasterLocation(
              id: 'l1',
              type: StockLocationType.room,
              branchId: branchId,
              roomId: 'r1',
              name: 'a',
            ),
            MasterLocation(
              id: 'l2',
              type: StockLocationType.room,
              branchId: branchId,
              roomId: 'r1',
              name: 'b',
            ),
          ],
        ).rejection,
        ConsumptionRoomRejection.locationAmbiguous,
        reason: 'Sistem tidak boleh menebak lokasi mana (§15).',
      );
    });

    test('lokasi salah tipe, salah ruangan atau salah cabang ditolak', () {
      for (final location in const [
        MasterLocation(
          id: 'l1',
          type: StockLocationType.branchStore,
          branchId: branchId,
          roomId: 'r1',
          name: 'salah tipe',
        ),
        MasterLocation(
          id: 'l1',
          type: StockLocationType.room,
          branchId: branchId,
          roomId: 'r9',
          name: 'salah ruangan',
        ),
        MasterLocation(
          id: 'l1',
          type: StockLocationType.room,
          branchId: 'b2',
          roomId: 'r1',
          name: 'salah cabang',
        ),
      ]) {
        expect(
          ConsumptionRoomPolicy.verifyRoomLocation(
            room: room,
            branchId: branchId,
            locations: [location],
          ).rejection,
          ConsumptionRoomRejection.locationMismatch,
          reason: '${location.name} harus ditolak.',
        );
      }
    });

    test('allowedRooms menyaring memakai verifyRoom', () {
      final rooms = ConsumptionRoomPolicy.allowedRooms(
        branchId: branchId,
        rooms: const [
          room,
          MasterRoom(
            id: 'r2',
            branchId: 'b2',
            code: 'R1',
            name: 'lain',
            isActive: true,
          ),
          MasterRoom(
            id: 'r3',
            branchId: branchId,
            code: 'R3',
            name: 'nonaktif',
            isActive: false,
          ),
        ],
      );
      expect(rooms.map((room) => room.id), ['r1']);
    });
  });

  group('ConsumptionNotePolicy', () {
    test('kosong dan spasi menjadi null', () {
      expect(ConsumptionNotePolicy.normalize(null), isNull);
      expect(ConsumptionNotePolicy.normalize(''), isNull);
      expect(ConsumptionNotePolicy.normalize('   '), isNull);
      // Dart's `trim()` strips tabs and newlines where SQLite's strips spaces only, which is
      // why this is the authority and the CHECK is the floor.
      expect(ConsumptionNotePolicy.normalize('\n\t '), isNull);
    });

    test('teks dipangkas, tidak diubah', () {
      expect(ConsumptionNotePolicy.normalize('  shift pagi  '), 'shift pagi');
      expect(ConsumptionNotePolicy.hasText(' x '), isTrue);
      expect(ConsumptionNotePolicy.hasText('  '), isFalse);
    });

    test('movementNote menggabungkan deterministik', () {
      expect(
        ConsumptionNotePolicy.movementNote(
          headerNote: 'shift pagi',
          lineNote: 'kemasan rusak',
        ),
        'shift pagi · kemasan rusak',
      );
      expect(
        ConsumptionNotePolicy.movementNote(headerNote: 'shift pagi'),
        'shift pagi',
      );
      expect(
        ConsumptionNotePolicy.movementNote(lineNote: 'kemasan rusak'),
        'kemasan rusak',
      );
      // Neither: a null movement note is legitimate (§19).
      expect(ConsumptionNotePolicy.movementNote(), isNull);
      expect(
        ConsumptionNotePolicy.movementNote(headerNote: '  ', lineNote: '\n'),
        isNull,
      );
    });
  });

  group('ConsumptionStockPlanBuilder', () {
    ConsumptionLineReference line(
      String id,
      String itemId,
      String? batchId,
      String qty, {
      String? note,
    }) => ConsumptionLineReference(
      id: id,
      consumptionId: 'c1',
      itemId: itemId,
      batchId: batchId,
      qty: Quantity.parse(qty),
      note: note,
    );

    test('dokumen tanpa baris ditolak', () {
      expect(
        () => ConsumptionStockPlanBuilder.build(
          consumptionId: 'c1',
          roomId: 'r1',
          roomLocationId: 'l1',
          note: null,
          lines: const [],
        ),
        throwsA(
          isA<ConsumptionPlanException>().having(
            (error) => error.rejection,
            'rejection',
            ConsumptionPlanRejection.noLines,
          ),
        ),
      );
    });

    test('qty nol ditolak dan menamai barisnya', () {
      expect(
        () => ConsumptionStockPlanBuilder.build(
          consumptionId: 'c1',
          roomId: 'r1',
          roomLocationId: 'l1',
          note: null,
          lines: [line('l-1', 'i1', 'b1', '0')],
        ),
        throwsA(
          isA<ConsumptionPlanException>()
              .having(
                (error) => error.rejection,
                'rejection',
                ConsumptionPlanRejection.invalidQty,
              )
              .having((error) => error.lineId, 'lineId', 'l-1'),
        ),
      );
    });

    test('catatan kosong bukan alasan penolakan (§8)', () {
      // The difference from `DisposalStockPlanBuilder`, asserted so nobody "harmonises"
      // the two.
      final plan = ConsumptionStockPlanBuilder.build(
        consumptionId: 'c1',
        roomId: 'r1',
        roomLocationId: 'l1',
        note: null,
        lines: [line('l-1', 'i1', 'b1', '1')],
      );
      expect(plan.note, isNull);
      expect(plan.entries.single.note, isNull);
    });

    test('agregasi per posisi menjumlahkan sebelum membandingkan', () {
      final plan = ConsumptionStockPlanBuilder.build(
        consumptionId: 'c1',
        roomId: 'r1',
        roomLocationId: 'l1',
        note: 'shift pagi',
        lines: [
          line('l-1', 'i1', 'b1', '1.5'),
          line('l-2', 'i1', null, '2'),
          line('l-3', 'i2', 'b2', '0.375'),
        ],
      );

      expect(plan.sourceRequirements, {
        'i1|b1': Quantity.parse('1.5'),
        'i1|': Quantity.parse('2'),
        'i2|b2': Quantity.parse('0.375'),
      });
      expect(plan.sourcePositions, hasLength(3));
      expect(plan.itemCount, 2);
      expect(plan.lineCount, 3);
      expect(plan.totalQty, Quantity.parse('3.875'));
    });

    test('urutan deterministik: item, batch, baris', () {
      final plan = ConsumptionStockPlanBuilder.build(
        consumptionId: 'c1',
        roomId: 'r1',
        roomLocationId: 'l1',
        note: null,
        lines: [
          line('l-3', 'i2', 'b1', '1'),
          line('l-1', 'i1', 'b2', '1'),
          line('l-2', 'i1', null, '1'),
        ],
      );
      // `i1` before `i2`; within `i1`, the unbatched position first because `''` precedes
      // every batch id.
      expect(plan.entries.map((entry) => entry.sourceKey), [
        'i1|',
        'i1|b2',
        'i2|b1',
      ]);
    });

    test('catatan pergerakan disusun sekali per baris', () {
      final plan = ConsumptionStockPlanBuilder.build(
        consumptionId: 'c1',
        roomId: 'r1',
        roomLocationId: 'l1',
        note: 'shift pagi',
        lines: [
          line('l-1', 'i1', 'b1', '1', note: 'kemasan rusak'),
          line('l-2', 'i2', null, '1'),
        ],
      );
      final byLine = {
        for (final entry in plan.entries) entry.lineId: entry.note,
      };
      expect(byLine['l-1'], 'shift pagi · kemasan rusak');
      expect(byLine['l-2'], 'shift pagi');
    });

    test('rencana tidak memiliki tujuan', () {
      final plan = ConsumptionStockPlanBuilder.build(
        consumptionId: 'c1',
        roomId: 'r1',
        roomLocationId: 'l1',
        note: null,
        lines: [line('l-1', 'i1', 'b1', '1')],
      );
      // The room is named twice — as a room and as a location — and there is no third
      // field a destination could occupy (§19).
      expect(plan.roomId, 'r1');
      expect(plan.roomLocationId, 'l1');
      expect(plan.isEmpty, isFalse);
    });
  });

  group('ConsumptionFilter', () {
    final from = DateTime.utc(2026, 7, 29, 16);
    final to = DateTime.utc(2026, 7, 30, 15, 59, 59, 999, 999);

    test('tanpa rentang, semuanya masuk', () {
      const filter = ConsumptionFilter();
      expect(filter.hasPostedRange, isFalse);
      expect(filter.includesPostedAt(DateTime.utc(2020)), isTrue);
      expect(filter.includesPostedAt(null), isTrue);
    });

    test('rentang membandingkan instant, bukan teks', () {
      final filter = ConsumptionFilter(postedFromUtc: from, postedToUtc: to);
      expect(filter.hasPostedRange, isTrue);

      // Inside, at both edges.
      expect(filter.includesPostedAt(from), isTrue);
      expect(filter.includesPostedAt(to), isTrue);
      expect(filter.includesPostedAt(DateTime.utc(2026, 7, 30, 8)), isTrue);
      // Just outside, by one microsecond either way.
      expect(
        filter.includesPostedAt(from.subtract(const Duration(microseconds: 1))),
        isFalse,
      );
      expect(
        filter.includesPostedAt(to.add(const Duration(microseconds: 1))),
        isFalse,
      );
    });

    test('draft berada di luar setiap rentang', () {
      final filter = ConsumptionFilter(postedFromUtc: from, postedToUtc: to);
      expect(
        filter.includesPostedAt(null),
        isFalse,
        reason: 'Belum diposting berarti tidak ada instant untuk dibandingkan.',
      );
    });

    test('rentang berasal dari hari operasional GMT+8', () {
      // `2026-07-30` GMT+8 runs from `2026-07-29T16:00Z` to `2026-07-30T15:59:59.999999Z`.
      final day = DateOnly.of(2026, 7, 30);
      expect(AppTimeZone.startOfOperationalDayUtc(day), from);
      expect(AppTimeZone.endOfOperationalDayUtc(day), to);
    });

    test('copyWith dapat mengosongkan nilai', () {
      final filter = ConsumptionFilter(
        roomId: 'r1',
        createdBy: 'u1',
        postedFromUtc: from,
      );
      final cleared = filter.copyWith(
        roomId: null,
        createdBy: null,
        postedFromUtc: null,
      );
      expect(cleared.roomId, isNull);
      expect(cleared.createdBy, isNull);
      expect(cleared.postedFromUtc, isNull);
      // …and an omitted argument keeps the current value.
      expect(filter.copyWith().roomId, 'r1');
    });

    test('kesetaraan mengabaikan urutan status', () {
      const a = ConsumptionFilter(
        statuses: {ConsumptionStatus.draft, ConsumptionStatus.posted},
      );
      const b = ConsumptionFilter(
        statuses: {ConsumptionStatus.posted, ConsumptionStatus.draft},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ConsumptionProgress', () {
    ConsumptionLine line({
      required String id,
      String itemId = 'i1',
      String? batchId,
      DateTime? expiryDate,
      int expiryAlertDays = 30,
      String qty = '1',
      String unit = 'ampul',
    }) => ConsumptionLine(
      id: id,
      consumptionId: 'c1',
      itemId: itemId,
      sku: 'SKU',
      itemName: 'Barang',
      categoryId: 'cat',
      unit: unit,
      hasExpiry: batchId != null,
      expiryAlertDays: expiryAlertDays,
      batchId: batchId,
      batchNo: batchId == null ? null : 'B',
      expiryDate: expiryDate,
      qty: Quantity.parse(qty),
    );

    final reference = DateTime.utc(2026, 7, 30, 8);
    final today = AppTimeZone.operationalDate(reference);

    test('menghitung baris, barang dan batch', () {
      final progress = ConsumptionProgress.of([
        line(id: 'l1', batchId: 'b1', expiryDate: DateOnly.addDays(today, 100)),
        line(id: 'l2', batchId: 'b2', expiryDate: DateOnly.addDays(today, 90)),
        line(id: 'l3', itemId: 'i2'),
      ], referenceUtc: reference);

      expect(progress.lineCount, 3);
      expect(progress.itemCount, 2);
      expect(
        progress.batchCount,
        2,
        reason: 'Baris tanpa batch tidak menyumbang (G-E2).',
      );
      expect(progress.label, '3 posisi · 2 barang');
    });

    test('allUsable salah begitu satu baris kedaluwarsa', () {
      final ok = ConsumptionProgress.of([
        line(id: 'l1', batchId: 'b1', expiryDate: today),
      ], referenceUtc: reference);
      expect(ok.allUsable, isTrue);
      expect(ok.expiredCount, 0);

      final drifted = ConsumptionProgress.of([
        line(id: 'l1', batchId: 'b1', expiryDate: DateOnly.addDays(today, -1)),
      ], referenceUtc: reference);
      expect(drifted.allUsable, isFalse);
      expect(drifted.expiredCount, 1);
    });

    test('near-expiry dihitung tanpa memblokir', () {
      final progress = ConsumptionProgress.of([
        line(id: 'l1', batchId: 'b1', expiryDate: DateOnly.addDays(today, 10)),
        line(id: 'l2', batchId: 'b2', expiryDate: DateOnly.addDays(today, 200)),
      ], referenceUtc: reference);

      expect(progress.nearExpiryCount, 1);
      expect(progress.hasNearExpiry, isTrue);
      expect(
        progress.allUsable,
        isTrue,
        reason: 'Near-expiry adalah peringatan, bukan blokir (§17).',
      );
    });

    test('nearestExpiryDate mengabaikan baris tanpa ED', () {
      final progress = ConsumptionProgress.of([
        line(id: 'l1'),
        line(id: 'l2', batchId: 'b1', expiryDate: DateOnly.addDays(today, 50)),
        line(id: 'l3', batchId: 'b2', expiryDate: DateOnly.addDays(today, 20)),
      ], referenceUtc: reference);

      expect(progress.nearestExpiryDate, DateOnly.addDays(today, 20));
    });

    test('dokumen kosong', () {
      final progress = ConsumptionProgress.of(
        const [],
        referenceUtc: reference,
      );
      expect(progress.isEmpty, isTrue);
      expect(progress.allUsable, isTrue);
      expect(progress.nearestExpiryDate, isNull);
    });
  });

  group('ConsumptionDraft', () {
    ConsumptionCandidate candidate(String available) => ConsumptionCandidate(
      itemId: 'i1',
      sku: 'SKU',
      itemName: 'Barang',
      categoryId: 'cat',
      unit: 'ampul',
      hasExpiry: false,
      expiryAlertDays: 30,
      availableQty: Quantity.parse(available),
      roomId: 'r1',
      locationId: 'l1',
    );

    test('sisa dihitung eksak dan tidak pernah negatif', () {
      final draft = ConsumptionDraft(
        candidate: candidate('5.5'),
        qty: Quantity.parse('2.375'),
      );
      expect(draft.remainingAfterConsumption, Quantity.parse('3.125'));
      expect(draft.isValid, isTrue);
      expect(draft.isPartial, isTrue);
      expect(draft.isFullPosition, isFalse);

      final over = ConsumptionDraft(
        candidate: candidate('1'),
        qty: Quantity.parse('2'),
      );
      expect(over.exceedsAvailable, isTrue);
      expect(over.isValid, isFalse);
      expect(
        over.remainingAfterConsumption,
        Quantity.zero(),
        reason: 'Ditolak, bukan dijepit — angka layar dan ledger harus sama.',
      );
    });

    test('memakai seluruh posisi sah', () {
      final draft = ConsumptionDraft(
        candidate: candidate('2'),
        qty: Quantity.parse('2'),
      );
      expect(draft.isFullPosition, isTrue);
      expect(draft.isValid, isTrue);
      expect(draft.remainingAfterConsumption, Quantity.zero());
    });

    test('qty nol belum valid', () {
      final draft = ConsumptionDraft(
        candidate: candidate('2'),
        qty: Quantity.zero(),
      );
      expect(draft.isValid, isFalse);
    });

    test('copyWith dapat mengosongkan catatan', () {
      final draft = ConsumptionDraft(
        candidate: candidate('2'),
        qty: Quantity.parse('1'),
        note: 'x',
      );
      expect(draft.copyWith(note: null).note, isNull);
      expect(draft.copyWith().note, 'x');
    });

    test('minus menjepit di nol', () {
      final reduced = candidate('1').minus(Quantity.parse('2'));
      expect(reduced.availableQty, Quantity.zero());
    });
  });

  group('kunci posisi', () {
    test('grain item|batch konsisten di seluruh model', () {
      const reference = ConsumptionLineReference(
        id: 'l1',
        consumptionId: 'c1',
        itemId: 'i1',
        batchId: 'b1',
        qty: Quantity.fromMilliUnits(1000),
      );
      expect(reference.positionKey, 'i1|b1');
      expect(reference.isBatched, isTrue);

      const unbatched = ConsumptionLineReference(
        id: 'l2',
        consumptionId: 'c1',
        itemId: 'i1',
        qty: Quantity.fromMilliUnits(1000),
      );
      expect(unbatched.positionKey, 'i1|');
      expect(unbatched.isBatched, isFalse);
    });
  });

  group('filter tanggal riwayat cabang, dari ujung ke ujung', () {
    late TestContext context;
    late ConsumptionFixture fixture;

    final nowUtc = DateTime.utc(2026, 7, 30, 8);

    setUp(() async {
      context = TestContext.create(clock: () => nowUtc);
      fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
    });

    tearDown(() => context.dispose());

    Future<String> postedAt(DateTime instant) async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: instant.isBefore(nowUtc) ? instant : nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '0.5',
        nowUtc: nowUtc,
      );
      await context
          .postConsumption(clock: () => instant)
          .call(actorUserId: fixture.nurse.id, consumptionId: id);
      return id;
    }

    test('hanya dokumen pada hari operasional terpilih', () async {
      // Yesterday in GMT+8, and today.
      final yesterday = await postedAt(DateTime.utc(2026, 7, 29, 8));
      final todayDoc = await postedAt(nowUtc);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(context.database),
          currentSessionProvider.overrideWith(
            () => FixedSessionController(fixture.branchHead),
          ),
          consumptionClockProvider.overrideWithValue(() => nowUtc),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentSessionProvider.future);

      Future<List<String>> read() async {
        final subscription = container.listen(
          branchConsumptionListProvider,
          (_, _) {},
        );
        try {
          final rows = await container.read(
            branchConsumptionListProvider.future,
          );
          return rows.map((row) => row.id).toList();
        } finally {
          subscription.close();
        }
      }

      // No filter: both.
      expect(await read(), containsAll([yesterday, todayDoc]));

      // Today only.
      container
          .read(consumptionDateFilterProvider.notifier)
          .select(DateOnly.of(2026, 7, 30));
      expect(await read(), [todayDoc]);

      // Yesterday only.
      container
          .read(consumptionDateFilterProvider.notifier)
          .select(DateOnly.of(2026, 7, 29));
      expect(await read(), [yesterday]);

      // Cleared: both again.
      container.read(consumptionDateFilterProvider.notifier).clear();
      expect(await read(), containsAll([yesterday, todayDoc]));
    });

    test('rentang diturunkan dari hari operasional, bukan UTC', () {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(context.database),
          consumptionClockProvider.overrideWithValue(() => nowUtc),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(consumptionDateFilterProvider.notifier)
          .select(DateOnly.of(2026, 7, 30));
      final range = container.read(consumptionPostedRangeProvider);

      // `2026-07-30` GMT+8 begins at 16:00Z the day before — the boundary a UTC-day filter
      // would get wrong by eight hours (§31).
      expect(range.fromUtc, DateTime.utc(2026, 7, 29, 16));
      expect(range.toUtc, DateTime.utc(2026, 7, 30, 15, 59, 59, 999, 999));
    });
  });
}
