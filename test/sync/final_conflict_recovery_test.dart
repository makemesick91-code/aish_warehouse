import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/final_conflict_recovery_service.dart';
import 'package:aish_warehouse/core/sync/pull_sync_contracts.dart';
import 'package:aish_warehouse/core/sync/remote_change_applier.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pull_test_fixtures.dart';

/// Acceptance 22, 23, 24 and 31: a final document that diverged is recovered to
/// the server's version, without deleting a ledger row, duplicating a movement,
/// or leaving a retry that would repost the transaction.
void main() {
  late AppDatabase database;
  late RemoteChangeApplier applier;
  late FinalConflictRecoveryService recovery;
  final now = DateTime.utc(2026, 8, 3);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    applier = RemoteChangeApplier(database, clock: () => now);
    recovery = FinalConflictRecoveryService(database, clock: () => now);
    await seedLocalMaster(database);
  });

  tearDown(() => database.close());

  /// A device that posted a consumption locally: a document, a line, a movement
  /// that debited the room, and a queued outbox entry that never reached the
  /// server.
  Future<void> seedLocalPosting() async {
    await database.customStatement(
      'INSERT INTO consumptions (id,created_at,updated_at,sync_status,'
      'doc_number,branch_id,room_id,created_by,status,posted_by,posted_at) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?);',
      [
        'cons-1',
        fixtureNow,
        fixtureNow,
        'pending',
        'TMP-CNS-lokal',
        'branch-1',
        'room-1',
        'user-1',
        'posted',
        'user-1',
        fixtureNow,
      ],
    );
    await database.customStatement(
      'INSERT INTO stock_balances (id,created_at,updated_at,sync_status,'
      'location_id,item_id,batch_id,qty_on_hand) VALUES (?,?,?,?,?,?,?,?);',
      [
        'bal-room',
        fixtureNow,
        fixtureNow,
        'synced',
        'loc-room',
        'item-1',
        null,
        4000,
      ],
    );
    await database.customStatement(
      'INSERT INTO stock_movements (id,created_at,updated_at,sync_status,'
      'item_id,batch_id,from_location_id,to_location_id,qty,movement_type,'
      'ref_doc_type,ref_doc_id,actor_user_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);',
      [
        'mov-lokal-1',
        fixtureNow,
        fixtureNow,
        'pending',
        'item-1',
        null,
        'loc-room',
        null,
        1000,
        'consumption',
        'CONS',
        'cons-1',
        'user-1',
      ],
    );
    await database.customStatement(
      'INSERT INTO sync_devices (id,created_at,last_seen_at,app_install_id) '
      'VALUES (?,?,?,?);',
      ['device-1', fixtureNow, fixtureNow, 'install-1'],
    );
    await database.customStatement(
      'INSERT INTO sync_outbox (id,request_id,device_id,operation_type,'
      'aggregate_type,aggregate_id,actor_user_id,occurred_at_utc,payload_hash,'
      'created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?);',
      [
        'outbox-1',
        'req-1',
        'device-1',
        'post_consumption',
        'consumption',
        'cons-1',
        'user-1',
        fixtureNow,
        'a' * 64,
        fixtureNow,
        fixtureNow,
      ],
    );
  }

  /// The server settled the same document differently: its own movement UUID.
  Future<void> applyServerVersion() => applier.applyAll([
    change(
      seq: 50,
      entityType: 'consumption',
      entityId: 'cons-1',
      payload: serverConsumption(docNumber: 'CNS-2026-0042'),
    ),
  ]);

  Future<int> balance() async {
    final row = await database
        .customSelect(
          'SELECT qty_on_hand FROM stock_balances WHERE id = ?;',
          variables: [Variable<String>('bal-room')],
        )
        .getSingle();
    return row.read<int>('qty_on_hand');
  }

  test(
    'acceptance 22: local state is restored to the server document',
    () async {
      await seedLocalPosting();
      await applyServerVersion();

      await recovery.recover(entityType: 'consumption', entityId: 'cons-1');

      final consumption =
          (await database.select(database.consumptions).get()).single;
      expect(
        consumption.docNumber,
        'CNS-2026-0042',
        reason:
            'the final server document number is kept, not the local TMP one',
      );
      expect(consumption.status.dbValue, 'posted');
    },
  );

  test('acceptance 23: recovery never duplicates a movement', () async {
    await seedLocalPosting();
    await applyServerVersion();

    await recovery.recover(entityType: 'consumption', entityId: 'cons-1');

    final movements = await database.select(database.stockMovements).get();
    final ids = movements.map((row) => row.id).toSet();
    expect(
      ids.length,
      movements.length,
      reason: 'a movement UUID appears at most once in the ledger',
    );
    expect(
      ids,
      containsAll(<String>['mov-lokal-1', 'mov-server-1']),
      reason: 'neither the local posting nor the server posting is discarded',
    );
  });

  test('the unaccepted local posting is reversed, never deleted', () async {
    await seedLocalPosting();
    await applyServerVersion();

    final outcome = await recovery.recover(
      entityType: 'consumption',
      entityId: 'cons-1',
    );

    expect(outcome.reversalsAppended, 1);
    final reversal = (await database.select(database.stockMovements).get())
        .firstWhere((row) => row.reversalOfMovementId == 'mov-lokal-1');
    expect(
      reversal.toLocationId,
      'loc-room',
      reason: 'what left the room comes back to it (G-A1)',
    );
    expect(reversal.fromLocationId, isNull);
    expect(reversal.qty, 1000);
    expect(
      await database.select(database.stockMovements).get(),
      hasLength(3),
      reason: 'the original local movement is still in the ledger',
    );
  });

  test(
    'acceptance 32: the recovered balance is correct and non-negative',
    () async {
      await seedLocalPosting();
      await applyServerVersion();

      await recovery.recover(entityType: 'consumption', entityId: 'cons-1');

      expect(
        await balance(),
        5000,
        reason: 'reversing the local debit restores the room position',
      );
      final balances = await database.select(database.stockBalances).get();
      expect(balances.every((row) => row.qtyOnHand >= 0), isTrue);
    },
  );

  test(
    'acceptance 31: rerunning recovery creates no new transaction',
    () async {
      await seedLocalPosting();
      await applyServerVersion();

      await recovery.recover(entityType: 'consumption', entityId: 'cons-1');
      final afterFirst = await database.select(database.stockMovements).get();
      final balanceAfterFirst = await balance();

      await recovery.recover(entityType: 'consumption', entityId: 'cons-1');
      await recovery.recover(entityType: 'consumption', entityId: 'cons-1');

      expect(
        await database.select(database.stockMovements).get(),
        hasLength(afterFirst.length),
        reason: 'the reversal id is derived from the movement it reverses',
      );
      expect(await balance(), balanceAfterFirst);
    },
  );

  test('the outbox is settled so retry cannot repost the document', () async {
    await seedLocalPosting();
    await applyServerVersion();

    final outcome = await recovery.recover(
      entityType: 'consumption',
      entityId: 'cons-1',
    );

    expect(outcome.outboxEntriesSettled, 1);
    expect(
      await database.select(database.syncOutbox).get(),
      isEmpty,
      reason:
          'an entry still queued would repost the moment the network came back',
    );
    final conflicts = await database.select(database.syncConflictLogs).get();
    expect(
      conflicts.any(
        (row) =>
            row.requestId == 'req-1' &&
            row.resolution == SyncConflictResolution.localChangeSuperseded,
      ),
      isTrue,
      reason: 'the conflict log is the durable record that the entry existed',
    );
  });

  test(
    'acceptance 24: every conflict ends with an explicit resolution',
    () async {
      await seedLocalPosting();
      await applyServerVersion();

      await recovery.recover(entityType: 'consumption', entityId: 'cons-1');

      final conflicts = await database.select(database.syncConflictLogs).get();
      expect(conflicts, isNotEmpty);
      expect(
        conflicts.every((row) => row.resolvedAt != null),
        isTrue,
        reason: 'a conflict with no resolution is a dead end in the UI',
      );
      expect(
        conflicts.every(
          (row) => SyncConflictResolution.all.contains(row.resolution),
        ),
        isTrue,
      );
    },
  );

  test('a document with no local divergence needs no reversal', () async {
    await applyServerVersion();

    final outcome = await recovery.recover(
      entityType: 'consumption',
      entityId: 'cons-1',
    );

    expect(outcome.reversalsAppended, 0);
    expect(outcome.recovered, isTrue);
  });

  test('a movement the server also has is left completely alone', () async {
    await seedLocalPosting();
    // This time the device's own movement is the one the server accepted.
    await applier.applyAll([
      change(
        seq: 51,
        entityType: 'consumption',
        entityId: 'cons-1',
        payload: serverConsumption(
          movements: [
            {
              'id': 'mov-lokal-1',
              'created_at': '2026-08-03T00:00:00+00:00',
              'updated_at': '2026-08-03T00:00:00+00:00',
              'deleted_at': null,
              'sync_status': 'synced',
              'item_id': 'item-1',
              'batch_id': null,
              'from_location_id': 'loc-room',
              'to_location_id': null,
              'qty': 1000,
              'movement_type': 'consumption',
              'ref_doc_type': 'CONS',
              'ref_doc_id': 'cons-1',
              'actor_user_id': 'user-1',
              'note': null,
              'reversal_of_movement_id': null,
            },
          ],
        ),
      ),
    ]);

    final outcome = await recovery.recover(
      entityType: 'consumption',
      entityId: 'cons-1',
    );

    expect(outcome.reversalsAppended, 0);
    expect(await database.select(database.stockMovements).get(), hasLength(1));
    expect(await balance(), 4000);
  });

  test('a non-document entity is not a recovery target', () async {
    final outcome = await recovery.recover(
      entityType: 'item',
      entityId: 'item-1',
    );

    expect(outcome.recovered, isFalse);
    expect(outcome.resolution, isNull);
  });

  test('recovery is refused rather than driving a balance negative', () async {
    await seedLocalPosting();
    // A movement that brought stock *in*. Reversing it would debit a position
    // that no longer holds enough, which G-A2 forbids outright.
    await database.customStatement(
      'INSERT INTO stock_movements (id,created_at,updated_at,sync_status,'
      'item_id,batch_id,from_location_id,to_location_id,qty,movement_type,'
      'ref_doc_type,ref_doc_id,actor_user_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);',
      [
        'mov-lokal-2',
        fixtureNow,
        fixtureNow,
        'pending',
        'item-1',
        null,
        null,
        'loc-store',
        99000,
        'consumption',
        'CONS',
        'cons-1',
        'user-1',
      ],
    );
    await applyServerVersion();

    final outcome = await recovery.recover(
      entityType: 'consumption',
      entityId: 'cons-1',
    );

    expect(outcome.recovered, isFalse);
    expect(outcome.resolution, SyncConflictResolution.manualReviewRequired);
    final balances = await database.select(database.stockBalances).get();
    expect(
      balances.every((row) => row.qtyOnHand >= 0),
      isTrue,
      reason: 'an aborted recovery leaves every position non-negative',
    );
  });
}
