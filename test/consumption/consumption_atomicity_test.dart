import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_inventory_repository.dart';
import '../helpers/test_context.dart';

/// Posting a Pemakaian is one unit of work (§42).
///
/// Every test in this file makes a posting fail at a chosen moment and then asserts the
/// same six things:
///
/// ```
/// 0 movement Pemakaian baru
/// saldo ruangan utuh
/// status tetap draft
/// posted_at null
/// posted_by null
/// baris utuh
/// ```
///
/// That matters as much here as on a Pemusnahan and for the same reason: a `consumption`
/// movement has no counter-entry (§19), so a partially committed document would be
/// quantities that simply vanished with nothing in the ledger to reconcile them against.
/// The transaction boundary is the only thing standing between that and the database, and
/// these tests are what prove it exists.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  /// The five positions of room 1, in the order the plan will sort them by item id.
  ///
  /// A five-line document is what makes "the first line", "a middle line" and "the last
  /// line" three distinguishable failures rather than one.
  Future<String> fiveLineDraft() async {
    final id = await createConsumptionDraft(
      context,
      fixture,
      roomId: fixture.roomOne.id,
      nowUtc: nowUtc,
      note: 'shift pagi',
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.expiryItem.id,
      batchId: fixture.validBatch.id,
      qty: '1.5',
      nowUtc: nowUtc,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.expiryItem.id,
      batchId: fixture.nearBatch.id,
      qty: '0.375',
      nowUtc: nowUtc,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.otherExpiryItem.id,
      batchId: fixture.otherItemBatch.id,
      qty: '2',
      nowUtc: nowUtc,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.plainItem.id,
      qty: '3.25',
      nowUtc: nowUtc,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.otherPlainItem.id,
      qty: '1',
      nowUtc: nowUtc,
    );
    return id;
  }

  /// Every room-1 balance this document could touch, before the posting.
  Future<Map<String, Quantity>> roomOneBalances() async {
    final positions = <({String itemId, String? batchId})>[
      (itemId: fixture.expiryItem.id, batchId: fixture.validBatch.id),
      (itemId: fixture.expiryItem.id, batchId: fixture.nearBatch.id),
      (itemId: fixture.expiryItem.id, batchId: fixture.todayBatch.id),
      (itemId: fixture.expiryItem.id, batchId: fixture.expiredBatch.id),
      (itemId: fixture.otherExpiryItem.id, batchId: fixture.otherItemBatch.id),
      (itemId: fixture.plainItem.id, batchId: null),
      (itemId: fixture.otherPlainItem.id, batchId: null),
    ];
    final balances = <String, Quantity>{};
    for (final position in positions) {
      balances['${position.itemId}|${position.batchId ?? ''}'] =
          await locationBalance(
            context,
            locationId: fixture.locationOne.id,
            itemId: position.itemId,
            batchId: position.batchId,
          );
    }
    return balances;
  }

  /// The six assertions every failure in this file shares.
  Future<void> expectFullRollback(
    String consumptionId, {
    required Map<String, Quantity> balancesBefore,
    required int lineCountBefore,
    required int totalMovementsBefore,
  }) async {
    expect(
      await context.consumptionMovementCount(consumptionId),
      0,
      reason: 'Posting gagal tidak boleh meninggalkan movement Pemakaian.',
    );
    expect(
      await context.movementCountOfType(StockMovementType.consumption),
      0,
      reason:
          'Tidak ada movement consumption di mana pun, bukan hanya di dokumen ini.',
    );
    expect(
      await context.totalMovementCount(),
      totalMovementsBefore,
      reason: 'Tidak ada movement jenis apa pun yang tertinggal.',
    );
    expect(await roomOneBalances(), balancesBefore);
    expect(await context.consumptionStatusOf(consumptionId), 'draft');
    expect(await context.consumptionColumn(consumptionId, 'posted_at'), isNull);
    expect(await context.consumptionColumn(consumptionId, 'posted_by'), isNull);
    expect(await context.consumptionLineCount(consumptionId), lineCountBefore);
  }

  group('kegagalan ledger pada posisi tertentu', () {
    test('gagal pada baris pertama membatalkan seluruh dokumen', () async {
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 0,
      );
      await expectLater(
        context
            .postConsumption(
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.nurse.id, consumptionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(failing.appendedBeforeFailure, 0);
      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });

    test('gagal pada baris tengah membatalkan baris yang sudah ditulis', () async {
      // The assertion the transaction boundary exists for: two movements and two balance
      // reductions have already happened inside the transaction when the third throws.
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      final failing = FailingInventoryRepository(
        context.inventory,
        failAfterAppends: 2,
      );
      await expectLater(
        context
            .postConsumption(
              posting: context.postingWith(
                inventory: failing,
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.nurse.id, consumptionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      expect(
        failing.appendedBeforeFailure,
        2,
        reason: 'Kegagalan harus mendarat setelah dua movement ditulis.',
      );
      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });

    test(
      'gagal pada baris terakhir membatalkan empat baris sebelumnya',
      () async {
        final id = await fiveLineDraft();
        final before = await roomOneBalances();
        final movementsBefore = await context.totalMovementCount();

        final failing = FailingInventoryRepository(
          context.inventory,
          failAfterAppends: 4,
        );
        await expectLater(
          context
              .postConsumption(
                posting: context.postingWith(
                  inventory: failing,
                  clock: () => nowUtc,
                ),
              )
              .call(actorUserId: fixture.nurse.id, consumptionId: id),
          throwsA(isA<ValidationFailure>()),
        );

        expect(failing.appendedBeforeFailure, 4);
        await expectFullRollback(
          id,
          balancesBefore: before,
          lineCountBefore: 5,
          totalMovementsBefore: movementsBefore,
        );
      },
    );

    test('gagal pada satu barang tertentu membatalkan yang lain', () async {
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      await expectLater(
        context
            .postConsumption(
              posting: context.postingWith(
                inventory: FailingInventoryRepository(
                  context.inventory,
                  failOnItemId: fixture.otherPlainItem.id,
                ),
                clock: () => nowUtc,
              ),
            )
            .call(actorUserId: fixture.nurse.id, consumptionId: id),
        throwsA(isA<ValidationFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });
  });

  group('referensi hilang', () {
    test('barang yang hilang secara fisik membatalkan posting', () async {
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      await context.corruptByDeleting('items', fixture.otherPlainItem.id);

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionLineIntegrityFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });

    test('batch yang hilang secara fisik membatalkan posting', () async {
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      await context.corruptByDeleting('item_batches', fixture.nearBatch.id);

      // A *left*-joined batch does not drop the line, so the set-integrity check passes
      // and the reference check is what refuses — naming the table and the id an
      // administrator has to repair (§33). That is the stronger failure of the two.
      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<HistoricalConsumptionReferenceMissingFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });

    test(
      'dokumen tidak menyusut: inner join tidak boleh menyembunyikan baris',
      () async {
        // The point of the set-integrity check. A joined read drops the line whose item is
        // gone, so every per-line check would still pass on a four-line document — and the
        // posting would consume less stock than the document says it did.
        final id = await fiveLineDraft();
        await context.corruptByDeleting('items', fixture.plainItem.id);

        final plainLines = await context.consumptions.lineReferences(id);
        expect(
          plainLines,
          hasLength(5),
          reason: 'Plain select tidak boleh terpengaruh join.',
        );

        final detail = await context.consumptions.getDetail(id);
        expect(
          detail!.lines,
          hasLength(4),
          reason:
              'Joined read memang kehilangan satu baris — itu sebabnya §22 ada.',
        );

        await expectLater(
          context.postConsumption().call(
            actorUserId: fixture.nurse.id,
            consumptionId: id,
          ),
          throwsA(isA<ConsumptionLineIntegrityFailure>()),
        );
        expect(await context.consumptionMovementCount(id), 0);
        expect(await context.consumptionStatusOf(id), 'draft');
      },
    );

    test('ruangan yang hilang membatalkan posting', () async {
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      await context.corruptByDeleting('rooms', fixture.roomOne.id);

      // The header's own inner join on `rooms` drops the document from the joined read.
      // The header was already loaded by then, so "not found" would be a lie — §33 asks
      // for a failure that names the broken reference instead.
      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<HistoricalConsumptionReferenceMissingFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });

    test('lokasi ruangan yang diarsipkan membatalkan posting', () async {
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      await context.archive('stock_locations', fixture.locationOne.id);

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionRoomLocationNotFoundFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });

    test('lokasi ruangan ganda membatalkan posting', () async {
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      await context.insertDuplicateLocation(
        id: 'dup-room-one',
        type: StockLocationType.room.dbValue,
        name: 'Ruang Dental 1 (duplikat)',
        branchId: fixture.branch.id,
        roomId: fixture.roomOne.id,
      );

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionRoomLocationAmbiguousFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });
  });

  group('kondisi operasional berubah', () {
    test('ruangan dinonaktifkan setelah draft dibuat memblokir posting', () async {
      // Where the Pemakaian rule is stricter than the Pemusnahan's (§15): taking expired
      // goods off a decommissioned shelf lowers risk, whereas recording usage in a room
      // the clinic has closed asserts activity in a place nobody is working.
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      await context.deactivate('rooms', fixture.roomOne.id);

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionRoomInactiveFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });

    test('draft tetap dapat dibaca meski ruangannya dinonaktifkan', () async {
      // The other half of the rule: posting is refused, reading is not, so the nurse can
      // see what was on the document and tidy it up.
      final id = await fiveLineDraft();
      await context.deactivate('rooms', fixture.roomOne.id);

      final detail = await context.consumptions.getOwn(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
      );
      expect(detail, isNotNull);
      expect(detail!.lines, hasLength(5));
      expect(detail.room.isHistorical, isTrue);
      expect(detail.summary.roomIsHistorical, isTrue);

      // And a line can still be removed, so the draft is not a trap.
      final lines = await consumptionLineIdsByPosition(context, id);
      await context.removeConsumptionLine.call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
        lineId: lines['${fixture.plainItem.id}|']!,
      );
      expect(await context.consumptionLineCount(id), 4);
    });

    test(
      'batch yang kedaluwarsa saat draft terbuka membatalkan posting',
      () async {
        final id = await fiveLineDraft();
        final before = await roomOneBalances();
        final movementsBefore = await context.totalMovementCount();

        // Ten days on, `nearBatch` is past its date.
        final later = nowUtc.add(const Duration(days: 11));
        await expectLater(
          context
              .postConsumption(clock: () => later)
              .call(actorUserId: fixture.nurse.id, consumptionId: id),
          throwsA(isA<ExpiredBatchForConsumptionFailure>()),
        );

        await expectFullRollback(
          id,
          balancesBefore: before,
          lineCountBefore: 5,
          totalMovementsBefore: movementsBefore,
        );
      },
    );

    test('saldo yang berubah di bawah draft membatalkan posting', () async {
      final id = await fiveLineDraft();

      // A second document drains one of the positions first.
      final rival = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: rival,
        itemId: fixture.otherPlainItem.id,
        qty: '6',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: rival,
      );

      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();
      final consumptionMovementsBefore = await context.movementCountOfType(
        StockMovementType.consumption,
      );

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<InsufficientRoomStockFailure>()),
      );

      // The rival's movement survives; this document wrote nothing.
      expect(await context.consumptionMovementCount(id), 0);
      expect(
        await context.movementCountOfType(StockMovementType.consumption),
        consumptionMovementsBefore,
      );
      expect(await context.totalMovementCount(), movementsBefore);
      expect(await roomOneBalances(), before);
      expect(await context.consumptionStatusOf(id), 'draft');
      expect(await context.consumptionColumn(id, 'posted_at'), isNull);
      expect(await context.consumptionColumn(id, 'posted_by'), isNull);
      expect(await context.consumptionLineCount(id), 5);
    });

    test('timestamp tidak valid membatalkan posting', () async {
      final id = await fiveLineDraft();
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      final behind = nowUtc.subtract(const Duration(days: 1));
      await expectLater(
        context
            .postConsumption(clock: () => behind)
            .call(actorUserId: fixture.nurse.id, consumptionId: id),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 5,
        totalMovementsBefore: movementsBefore,
      );
    });

    test(
      'aktor dinonaktifkan sebelum posting membatalkan seluruhnya',
      () async {
        final id = await fiveLineDraft();
        final before = await roomOneBalances();
        final movementsBefore = await context.totalMovementCount();

        await context.deactivate('users', fixture.nurse.id);

        await expectLater(
          context.postConsumption().call(
            actorUserId: fixture.nurse.id,
            consumptionId: id,
          ),
          throwsA(isA<InactiveEntityFailure>()),
        );

        await expectFullRollback(
          id,
          balancesBefore: before,
          lineCountBefore: 5,
          totalMovementsBefore: movementsBefore,
        );
      },
    );

    test('dokumen kosong tidak menulis apa pun', () async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
      );
      final before = await roomOneBalances();
      final movementsBefore = await context.totalMovementCount();

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        ),
        throwsA(isA<ConsumptionLineRequiredFailure>()),
      );

      await expectFullRollback(
        id,
        balancesBefore: before,
        lineCountBefore: 0,
        totalMovementsBefore: movementsBefore,
      );
    });

    test('baris terakhir dihapus di sela membuat guarded update gagal', () async {
      // What the `EXISTS` predicate in `markPosted` is for. Simulated by soft-deleting
      // every line through raw SQL *after* the use case would have read them — which is
      // the state a second device produces.
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      // The guarded statement, exercised directly: the document is a draft, the actor
      // owns it, and it has no live line.
      await context.database.customStatement(
        'UPDATE consumption_lines SET deleted_at = ? WHERE consumption_id = ?;',
        [nowUtc.toIso8601String(), id],
      );
      final posted = await context.consumptions.markPosted(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
        postedAtUtc: nowUtc,
        postedBy: fixture.nurse.id,
      );
      expect(posted, isFalse);
      expect(await context.consumptionStatusOf(id), 'draft');
    });

    test('guarded update menolak aktor yang bukan pembuat', () async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      final posted = await context.consumptions.markPosted(
        consumptionId: id,
        actorUserId: fixture.otherNurse.id,
        postedAtUtc: nowUtc,
        postedBy: fixture.otherNurse.id,
      );
      expect(
        posted,
        isFalse,
        reason: 'created_by ikut ke dalam statement, bukan hanya ke guard.',
      );
      expect(await context.consumptionStatusOf(id), 'draft');
    });

    test('guarded update menolak dokumen yang sudah posted', () async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      final again = await context.consumptions.markPosted(
        consumptionId: id,
        actorUserId: fixture.nurse.id,
        postedAtUtc: nowUtc.add(const Duration(hours: 1)),
        postedBy: fixture.nurse.id,
      );
      expect(again, isFalse);
      // And the stored stamps are the original ones.
      expect(
        await context.consumptionColumn(id, 'posted_at'),
        nowUtc.toIso8601String(),
      );
    });
  });

  group('satu transaksi', () {
    test(
      'posting berhasil menulis seluruh baris atau tidak sama sekali',
      () async {
        final id = await fiveLineDraft();
        final result = await context.postConsumption().call(
          actorUserId: fixture.nurse.id,
          consumptionId: id,
        );

        expect(result.movements, hasLength(5));
        expect(await context.consumptionMovementCount(id), 5);
        expect(await context.consumptionStatusOf(id), 'posted');

        // Every balance fell by exactly what its line asked for.
        expect(
          await locationBalance(
            context,
            locationId: fixture.locationOne.id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.validBatch.id,
          ),
          Quantity.parse('4'),
        );
        expect(
          await locationBalance(
            context,
            locationId: fixture.locationOne.id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.nearBatch.id,
          ),
          Quantity.parse('2'),
        );
        expect(
          await locationBalance(
            context,
            locationId: fixture.locationOne.id,
            itemId: fixture.otherExpiryItem.id,
            batchId: fixture.otherItemBatch.id,
          ),
          Quantity.parse('2'),
        );
        expect(
          await locationBalance(
            context,
            locationId: fixture.locationOne.id,
            itemId: fixture.plainItem.id,
          ),
          Quantity.parse('7.25'),
        );
        expect(
          await locationBalance(
            context,
            locationId: fixture.locationOne.id,
            itemId: fixture.otherPlainItem.id,
          ),
          Quantity.parse('5'),
        );
      },
    );

    test('posting tidak menyentuh posisi yang tidak ada di dokumen', () async {
      final id = await fiveLineDraft();
      final expiredBefore = await locationBalance(
        context,
        locationId: fixture.locationOne.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.expiredBatch.id,
      );
      final todayBefore = await locationBalance(
        context,
        locationId: fixture.locationOne.id,
        itemId: fixture.expiryItem.id,
        batchId: fixture.todayBatch.id,
      );

      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      expect(
        await locationBalance(
          context,
          locationId: fixture.locationOne.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.expiredBatch.id,
        ),
        expiredBefore,
      );
      expect(
        await locationBalance(
          context,
          locationId: fixture.locationOne.id,
          itemId: fixture.expiryItem.id,
          batchId: fixture.todayBatch.id,
        ),
        todayBefore,
      );
    });
  });
}
