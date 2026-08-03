import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/pull_sync_contracts.dart';
import 'package:aish_warehouse/core/sync/pull_sync_worker.dart';
import 'package:aish_warehouse/core/sync/sync_cursor_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pull_test_fixtures.dart';

void main() {
  late AppDatabase database;
  late SyncCursorRepository cursors;
  final now = DateTime.utc(2026, 8, 3);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    cursors = SyncCursorRepository(database);
    await seedLocalMaster(database);
  });

  tearDown(() => database.close());

  PullSyncWorker worker(PullSyncGateway gateway, {int batchSize = 200}) =>
      PullSyncWorker(
        database: database,
        gateway: gateway,
        cursors: cursors,
        clock: () => now,
        batchSize: batchSize,
      );

  Future<int> storedCursor({String scope = 'scope-a'}) =>
      cursors.cursorFor(actorUserId: 'actor-1', scopeFingerprint: scope);

  RemoteChange itemChange(int seq, {String name = 'Nama Server'}) => change(
    seq: seq,
    entityType: 'item',
    entityId: 'item-1',
    payload: serverItem(name: name),
  );

  group('acceptance 12: the batch and the cursor move together', () {
    test('a successful batch advances the cursor exactly once', () async {
      final gateway = FakePullGateway([
        batch([itemChange(5)], nextCursor: 7),
      ]);

      final result = await worker(
        gateway,
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      expect(result.succeeded, isTrue);
      expect(result.reachedEnd, isTrue);
      expect(result.applied, 1);
      expect(
        await storedCursor(),
        7,
        reason:
            'the cursor consumes filtered positions too, not just applied ones',
      );
      expect(
        (await database.select(database.items).get()).single.name,
        'Nama Server',
      );
    });

    test('nothing to do leaves the cursor where it was', () async {
      final gateway = FakePullGateway([batch(const [], nextCursor: 0)]);

      final result = await worker(
        gateway,
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      expect(result.applied, 0);
      expect(await storedCursor(), 0);
    });
  });

  group('acceptance 13: a failure part-way rolls the whole batch back', () {
    test('an unapplicable change discards its entire page', () async {
      // The second change points at a category that does not exist, so the
      // foreign key rejects it. The first change must not survive on its own.
      final gateway = FakePullGateway([
        batch([
          itemChange(5, name: 'Diterapkan Lebih Dulu'),
          change(
            seq: 6,
            entityType: 'item',
            entityId: 'item-2',
            payload: serverItem(id: 'item-2', sku: 'SKU-2')
              ..['category_id'] = 'category-yang-tidak-ada',
          ),
        ], nextCursor: 6),
      ]);

      await expectLater(
        worker(gateway).run(actorUserId: 'actor-1', deviceId: 'device-1'),
        throwsA(anything),
      );

      expect(
        (await database.select(database.items).get()).single.name,
        'Masker Bedah',
        reason: 'the first change of the batch was rolled back with the second',
      );
      expect(
        await storedCursor(),
        0,
        reason: 'a cursor that moved past an unapplied change loses it forever',
      );
    });
  });

  group('acceptance 14 and 15: retry converges on the same state', () {
    test('replaying the identical batch changes nothing further', () async {
      final page = batch([
        itemChange(5),
        change(
          seq: 6,
          entityType: 'consumption',
          entityId: 'cons-1',
          payload: serverConsumption(),
        ),
      ], nextCursor: 6);

      await worker(
        FakePullGateway([page]),
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');
      final afterFirst = {
        'items': (await database.select(database.items).get()).length,
        'consumptions':
            (await database.select(database.consumptions).get()).length,
        'movements':
            (await database.select(database.stockMovements).get()).length,
        'lines':
            (await database.select(database.consumptionLines).get()).length,
      };

      // Re-run from cursor 0, as a device would after losing its cursor write.
      await cursors.reset(actorUserId: 'actor-1', scopeFingerprint: 'scope-a');
      await worker(
        FakePullGateway([page]),
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      expect({
        'items': (await database.select(database.items).get()).length,
        'consumptions':
            (await database.select(database.consumptions).get()).length,
        'movements':
            (await database.select(database.stockMovements).get()).length,
        'lines':
            (await database.select(database.consumptionLines).get()).length,
      }, afterFirst);
      expect(await storedCursor(), 6);
    });
  });

  group('acceptance 28: a device behind by several pages catches up', () {
    test('pages are drained until the server reports no more', () async {
      final gateway = FakePullGateway([
        batch([itemChange(1)], nextCursor: 1, hasMore: true),
        batch(
          [
            change(
              seq: 2,
              entityType: 'consumption',
              entityId: 'cons-1',
              payload: serverConsumption(),
            ),
          ],
          nextCursor: 2,
          hasMore: true,
        ),
        batch([
          change(
            seq: 3,
            entityType: 'category',
            entityId: 'cat-1',
            operation: RemoteChangeOperation.tombstone,
            serverVersion: 4,
          ),
        ], nextCursor: 3),
      ]);

      final result = await worker(
        gateway,
        batchSize: 1,
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      expect(result.batches, 3);
      expect(result.reachedEnd, isTrue);
      expect(result.tombstones, 1);
      expect(await storedCursor(), 3);
      expect(
        gateway.requestedCursors,
        [0, 1, 2],
        reason: 'each page resumes from the position the previous one reported',
      );
    });

    test('the cursor is durable between cycles', () async {
      await worker(
        FakePullGateway([
          batch([itemChange(1)], nextCursor: 4),
        ]),
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      final second = FakePullGateway([batch(const [], nextCursor: 4)]);
      await worker(second).run(actorUserId: 'actor-1', deviceId: 'device-1');

      expect(second.requestedCursors, [4]);
    });

    test('one cycle is bounded even when the server keeps saying more', () async {
      // A page that always reports `has_more` would otherwise hold the app in a
      // single unbounded cycle.
      final gateway = _EndlessGateway();
      final bounded = PullSyncWorker(
        database: database,
        gateway: gateway,
        cursors: cursors,
        clock: () => now,
        maxBatchesPerCycle: 4,
      );

      final result = await bounded.run(
        actorUserId: 'actor-1',
        deviceId: 'device-1',
      );

      expect(result.batches, 4);
      expect(result.reachedEnd, isFalse);
      expect(gateway.calls, 4);
    });
  });

  group('acceptance 16 and 17: session boundaries are respected', () {
    test('signing out mid-drain stops before the next page', () async {
      final gateway = FakePullGateway([
        batch([itemChange(1)], nextCursor: 1, hasMore: true),
        batch(
          [
            change(
              seq: 2,
              entityType: 'consumption',
              entityId: 'cons-1',
              payload: serverConsumption(),
            ),
          ],
          nextCursor: 2,
          hasMore: true,
        ),
      ]);
      final syncWorker = worker(gateway, batchSize: 1);
      // Logout lands while the first page is in flight.
      gateway.onPull = syncWorker.cancel;

      final result = await syncWorker.run(
        actorUserId: 'actor-1',
        deviceId: 'device-1',
      );

      expect(result.reachedEnd, isFalse);
      expect(
        gateway.calls,
        1,
        reason: 'a cancelled worker does not fetch the next page',
      );
      expect(
        await storedCursor(),
        0,
        reason: 'a page discarded unapplied must not move the cursor',
      );
      expect(
        await database.select(database.consumptions).get(),
        isEmpty,
        reason: 'no page after the cancellation was applied',
      );
      final log = (await database.select(database.syncPullLogs).get()).single;
      expect(log.outcome, 'cancelled');
    });

    test('a second actor never inherits the first actor cursor', () async {
      await worker(
        FakePullGateway([
          batch([itemChange(1)], nextCursor: 9),
        ]),
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      final second = FakePullGateway([
        batch(const [], nextCursor: 0, fingerprint: 'scope-b'),
      ]);
      await worker(second).run(actorUserId: 'actor-2', deviceId: 'device-1');

      expect(
        second.requestedCursors.first,
        0,
        reason: 'a fresh actor starts from zero rather than another actor row',
      );
      expect(await storedCursor(), 9);
      expect(
        await cursors.cursorFor(
          actorUserId: 'actor-2',
          scopeFingerprint: 'scope-b',
        ),
        0,
      );
    });

    test('signing out forgets the actor position entirely', () async {
      await worker(
        FakePullGateway([
          batch([itemChange(1)], nextCursor: 9),
        ]),
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      await cursors.resetActor('actor-1');

      expect(await storedCursor(), 0);
      expect(
        await database.select(database.items).get(),
        hasLength(1),
        reason: 'forgetting a position must not discard applied data',
      );
    });
  });

  group('scope changes invalidate a cursor rather than corrupting it', () {
    test('a different fingerprint starts its own position', () async {
      await worker(
        FakePullGateway([
          batch([itemChange(1)], nextCursor: 9),
        ]),
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      // The same actor, promoted: the server names a new scope.
      final promoted = FakePullGateway([
        batch([itemChange(2)], nextCursor: 3, fingerprint: 'scope-promoted'),
      ]);
      await worker(promoted).run(actorUserId: 'actor-1', deviceId: 'device-1');

      expect(
        await cursors.cursorFor(
          actorUserId: 'actor-1',
          scopeFingerprint: 'scope-promoted',
        ),
        3,
      );
      expect(
        await storedCursor(),
        9,
        reason: 'the old scope position is kept, not overwritten',
      );
    });

    test('a rejected cursor triggers a full resync from zero', () async {
      await worker(
        FakePullGateway([
          batch([itemChange(1)], nextCursor: 40),
        ]),
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      final resetting = _CursorResetGateway(
        batch([itemChange(1)], nextCursor: 2),
      );
      final result = await worker(
        resetting,
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      expect(result.scopeReset, isTrue);
      expect(resetting.cursors, [40, 0]);
      expect(await storedCursor(), 2);
    });
  });

  group('failures are safe and logged without detail', () {
    test(
      'a retryable failure leaves the cursor and schedules a retry',
      () async {
        final gateway =
            FakePullGateway([
                batch([itemChange(1)], nextCursor: 5),
              ])
              ..failWith = const PullSyncRetryableFailure(
                PullSyncErrorCodes.retryLater,
                'Server belum dapat dihubungi. Akan dicoba lagi.',
              )
              ..failAfterCalls = 0;

        final result = await worker(
          gateway,
        ).run(actorUserId: 'actor-1', deviceId: 'device-1');

        expect(result.succeeded, isFalse);
        expect(result.failureCode, PullSyncErrorCodes.retryLater);
        expect(result.retryAfter, isNotNull);
        expect(await storedCursor(), 0);
      },
    );

    test('a permanent failure is not scheduled for retry', () async {
      final gateway = FakePullGateway([batch(const [])])
        ..failWith = const PullSyncPermanentFailure(
          PullSyncErrorCodes.accessDenied,
          'Anda tidak berwenang membaca data ini.',
        )
        ..failAfterCalls = 0;

      final result = await worker(
        gateway,
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      expect(result.failureCode, PullSyncErrorCodes.accessDenied);
      expect(result.retryAfter, isNull);
    });

    test('every cycle is logged with counts and no payload', () async {
      await worker(
        FakePullGateway([
          batch([itemChange(1)], nextCursor: 5),
        ]),
      ).run(actorUserId: 'actor-1', deviceId: 'device-1');

      final log = (await database.select(database.syncPullLogs).get()).single;
      expect(log.outcome, 'applied');
      expect(log.fromCursor, 0);
      expect(log.toCursor, 5);
      expect(log.changeCount, 1);
      expect(log.safeErrorMessage, isNull);
    });

    test('a failed cycle logs a safe code and message only', () async {
      final gateway = FakePullGateway([batch(const [])])
        ..failWith = const PullSyncPermanentFailure(
          PullSyncErrorCodes.accessDenied,
          'Anda tidak berwenang membaca data ini.',
        )
        ..failAfterCalls = 0;

      await worker(gateway).run(actorUserId: 'actor-1', deviceId: 'device-1');

      final log = (await database.select(database.syncPullLogs).get()).single;
      expect(log.outcome, 'failed');
      expect(log.safeErrorCode, PullSyncErrorCodes.accessDenied);
      expect(
        log.safeErrorMessage,
        isNot(contains('PostgrestException')),
        reason: 'a log a user can open is a log an attacker can read',
      );
    });
  });

  group('the worker is single-flight', () {
    test(
      'a concurrent run returns immediately without a second drain',
      () async {
        final gateway = FakePullGateway([
          batch([itemChange(1)], nextCursor: 1, hasMore: true),
          batch([itemChange(2)], nextCursor: 2),
        ]);
        final syncWorker = worker(gateway, batchSize: 1);

        final first = syncWorker.run(
          actorUserId: 'actor-1',
          deviceId: 'device-1',
        );
        final second = await syncWorker.run(
          actorUserId: 'actor-1',
          deviceId: 'device-1',
        );
        await first;

        expect(second.batches, 0);
        expect(second.reachedEnd, isFalse);
      },
    );
  });
}

/// Always reports another page, to prove the per-cycle bound holds.
final class _EndlessGateway implements PullSyncGateway {
  int calls = 0;

  @override
  Future<RemoteChangeBatch> pull({
    required int cursor,
    required int limit,
    required String deviceId,
    List<String>? entityTypes,
  }) async {
    calls += 1;
    return batch(const [], nextCursor: cursor + 1, hasMore: true);
  }
}

/// Refuses the first cursor it is given, then serves normally — the shape of a
/// scope change or a pruned journal.
final class _CursorResetGateway implements PullSyncGateway {
  _CursorResetGateway(this.page);
  final RemoteChangeBatch page;
  final List<int> cursors = [];
  bool _refused = false;

  @override
  Future<RemoteChangeBatch> pull({
    required int cursor,
    required int limit,
    required String deviceId,
    List<String>? entityTypes,
  }) async {
    cursors.add(cursor);
    if (!_refused) {
      _refused = true;
      throw const PullSyncCursorResetRequired();
    }
    return page;
  }
}
