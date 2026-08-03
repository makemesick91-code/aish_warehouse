import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/pull_sync_contracts.dart';
import 'package:aish_warehouse/core/sync/remote_change_applier.dart';
// `Variable` only; drift also exports `isNull`/`isNotNull` as SQL expression
// builders, which would shadow the matchers of the same name.
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pull_test_fixtures.dart';

void main() {
  late AppDatabase database;
  late RemoteChangeApplier applier;
  final now = DateTime.utc(2026, 8, 3);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    applier = RemoteChangeApplier(database, clock: () => now);
    await seedLocalMaster(database);
  });

  tearDown(() => database.close());

  Future<Map<String, Object?>?> row(String table, String id) async {
    final result = await database
        .customSelect(
          'SELECT * FROM $table WHERE id = ?;',
          variables: [Variable<String>(id)],
        )
        .getSingleOrNull();
    return result?.data;
  }

  Future<void> markBaseline({
    required String entityType,
    required String entityId,
    required Map<String, Object?> payload,
    required int serverVersion,
  }) => applier.applyAll([
    change(
      seq: 1,
      entityType: entityType,
      entityId: entityId,
      serverVersion: serverVersion,
      payload: payload,
    ),
  ]);

  group('acceptance 15: a duplicate change never duplicates a row', () {
    test('applying the same master change twice is one row', () async {
      final upsert = change(
        seq: 10,
        entityType: 'item',
        entityId: 'item-1',
        payload: serverItem(name: 'Masker Server'),
      );

      await applier.applyAll([upsert]);
      await applier.applyAll([upsert]);

      final items = await database.select(database.items).get();
      expect(items, hasLength(1));
      expect(items.single.name, 'Masker Server');
    });

    test('applying the same document twice posts one movement', () async {
      final upsert = change(
        seq: 11,
        entityType: 'consumption',
        entityId: 'cons-1',
        payload: serverConsumption(),
      );

      await applier.applyAll([upsert]);
      await applier.applyAll([upsert]);

      expect(await database.select(database.consumptions).get(), hasLength(1));
      expect(
        await database.select(database.consumptionLines).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.stockMovements).get(),
        hasLength(1),
        reason: 'the ledger is keyed by UUID and never re-inserted',
      );
    });

    test('a movement arriving twice on its own is inserted once', () async {
      final movement =
          (serverConsumption()['movements']! as List).first
              as Map<String, Object?>;
      final upsert = change(
        seq: 12,
        entityType: 'stock_movement',
        entityId: 'mov-server-1',
        payload: movement,
      );

      await applier.applyAll([upsert, upsert]);

      expect(
        await database.select(database.stockMovements).get(),
        hasLength(1),
      );
    });
  });

  group('acceptance 25: a tombstone prevents stale resurrection', () {
    test('a tombstone soft-deletes rather than removing the row', () async {
      await markBaseline(
        entityType: 'category',
        entityId: 'cat-1',
        payload: {
          'id': 'cat-1',
          'created_at': '2026-08-01T00:00:00+00:00',
          'updated_at': '2026-08-01T00:00:00+00:00',
          'deleted_at': null,
          'sync_status': 'synced',
          'server_version': 1,
          'name': 'Kategori',
        },
        serverVersion: 1,
      );

      await applier.applyAll([
        change(
          seq: 20,
          entityType: 'category',
          entityId: 'cat-1',
          operation: RemoteChangeOperation.tombstone,
          serverVersion: 4,
        ),
      ]);

      final category = await row('item_categories', 'cat-1');
      expect(
        category,
        isNotNull,
        reason: 'the row survives so history and foreign keys still resolve',
      );
      expect(category!['deleted_at'], isNotNull);
      final tombstones = await database.select(database.syncTombstones).get();
      expect(tombstones.single.serverVersion, 4);
      expect(tombstones.single.hadLocalRow, isTrue);
    });

    test('an older upsert cannot bring a deleted record back', () async {
      await applier.applyAll([
        change(
          seq: 21,
          entityType: 'category',
          entityId: 'cat-1',
          operation: RemoteChangeOperation.tombstone,
          serverVersion: 6,
        ),
      ]);

      // A device that was offline while this was deleted replays its stale view.
      await applier.applyAll([
        change(
          seq: 22,
          entityType: 'category',
          entityId: 'cat-1',
          serverVersion: 5,
          payload: {
            'id': 'cat-1',
            'created_at': '2026-08-01T00:00:00+00:00',
            'updated_at': '2026-08-01T00:00:00+00:00',
            'deleted_at': null,
            'sync_status': 'synced',
            'server_version': 5,
            'name': 'Kategori Hidup Lagi',
          },
        ),
      ]);

      final category = await row('item_categories', 'cat-1');
      expect(category!['deleted_at'], isNotNull);
      expect(category['name'], 'Kategori');
    });

    test('a strictly newer upsert is a genuine server restore', () async {
      await applier.applyAll([
        change(
          seq: 23,
          entityType: 'category',
          entityId: 'cat-1',
          operation: RemoteChangeOperation.tombstone,
          serverVersion: 6,
        ),
      ]);
      await applier.applyAll([
        change(
          seq: 24,
          entityType: 'category',
          entityId: 'cat-1',
          serverVersion: 7,
          payload: {
            'id': 'cat-1',
            'created_at': '2026-08-01T00:00:00+00:00',
            'updated_at': '2026-08-04T00:00:00+00:00',
            'deleted_at': null,
            'sync_status': 'synced',
            'server_version': 7,
            'name': 'Kategori Dipulihkan',
          },
        ),
      ]);

      final category = await row('item_categories', 'cat-1');
      expect(category!['deleted_at'], isNull);
      expect(category['name'], 'Kategori Dipulihkan');
      expect(await database.select(database.syncTombstones).get(), isEmpty);
    });

    test('a tombstone for an unheld record is still remembered', () async {
      await applier.applyAll([
        change(
          seq: 25,
          entityType: 'category',
          entityId: 'never-seen',
          operation: RemoteChangeOperation.tombstone,
          serverVersion: 2,
        ),
      ]);

      final tombstone =
          (await database.select(database.syncTombstones).get()).single;
      expect(tombstone.entityId, 'never-seen');
      expect(
        tombstone.hadLocalRow,
        isFalse,
        reason:
            'a deletion this device never held is a different fact from one it did',
      );
    });

    test('re-applying a tombstone changes nothing', () async {
      final tombstone = change(
        seq: 26,
        entityType: 'category',
        entityId: 'cat-1',
        operation: RemoteChangeOperation.tombstone,
        serverVersion: 3,
      );

      await applier.applyAll([tombstone]);
      final firstApplied =
          (await database.select(database.syncTombstones).get())
              .single
              .appliedAtUtc;
      await applier.applyAll([tombstone]);

      final rows = await database.select(database.syncTombstones).get();
      expect(rows, hasLength(1));
      expect(rows.single.appliedAtUtc, firstApplied);
    });

    test('an entity whose history is load-bearing is never tombstoned', () async {
      // A domain user names every document they ever posted. The server refuses
      // to delete one at all; replicating a deletion would strand that history.
      await applier.applyAll([
        change(
          seq: 27,
          entityType: 'user',
          entityId: 'user-1',
          operation: RemoteChangeOperation.tombstone,
          serverVersion: 9,
        ),
      ]);

      final user = await row('users', 'user-1');
      expect(user!['deleted_at'], isNull);
      expect(await database.select(database.syncTombstones).get(), isEmpty);
    });
  });

  group('acceptance 33: a document is applied whole or not at all', () {
    test('header, lines and movements land together', () async {
      await applier.applyAll([
        change(
          seq: 30,
          entityType: 'consumption',
          entityId: 'cons-1',
          payload: serverConsumption(),
        ),
      ]);

      expect(await database.select(database.consumptions).get(), hasLength(1));
      expect(
        await database.select(database.consumptionLines).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.stockMovements).get(),
        hasLength(1),
      );
    });

    test('the server document number is what survives locally', () async {
      await database.customStatement(
        'INSERT INTO consumptions (id,created_at,updated_at,sync_status,'
        'doc_number,branch_id,room_id,created_by,status) '
        'VALUES (?,?,?,?,?,?,?,?,?);',
        [
          'cons-1',
          fixtureNow,
          fixtureNow,
          'pending',
          'TMP-CNS-local',
          'branch-1',
          'room-1',
          'user-1',
          'draft',
        ],
      );

      await applier.applyAll([
        change(
          seq: 31,
          entityType: 'consumption',
          entityId: 'cons-1',
          payload: serverConsumption(docNumber: 'CNS-2026-0007'),
        ),
      ]);

      final consumption =
          (await database.select(database.consumptions).get()).single;
      expect(consumption.docNumber, 'CNS-2026-0007');
      expect(consumption.status.dbValue, 'posted');
    });

    test('a line the server dropped is soft-deleted, not removed', () async {
      await applier.applyAll([
        change(
          seq: 32,
          entityType: 'consumption',
          entityId: 'cons-1',
          payload: serverConsumption(),
        ),
      ]);
      final withoutLines = serverConsumption()..['lines'] = const [];
      await applier.applyAll([
        change(
          seq: 33,
          entityType: 'consumption',
          entityId: 'cons-1',
          payload: withoutLines,
        ),
      ]);

      final lines = await database.select(database.consumptionLines).get();
      expect(lines, hasLength(1), reason: 'the row is history, not garbage');
      expect(lines.single.deletedAt, isNotNull);
    });

    test('a final document divergence is recorded with a resolution', () async {
      await database.customStatement(
        'INSERT INTO consumptions (id,created_at,updated_at,sync_status,'
        'doc_number,branch_id,room_id,created_by,status) '
        'VALUES (?,?,?,?,?,?,?,?,?);',
        [
          'cons-1',
          fixtureNow,
          fixtureNow,
          'pending',
          'TMP-CNS-local',
          'branch-1',
          'room-1',
          'user-1',
          'draft',
        ],
      );

      final outcome = await applier.applyAll([
        change(
          seq: 34,
          entityType: 'consumption',
          entityId: 'cons-1',
          payload: serverConsumption(),
        ),
      ]);

      expect(outcome.finalRecoveries, hasLength(1));
      final conflict =
          (await database.select(database.syncConflictLogs).get()).single;
      expect(conflict.conflictCode, 'sync_final_state_conflict');
      expect(conflict.resolution, SyncConflictResolution.serverFinalApplied);
      expect(
        conflict.resolvedAt,
        isNotNull,
        reason: 'a conflict with no resolution is a dead end for the user',
      );
    });
  });

  group('acceptance 26: an untouched local draft is left alone', () {
    test('a draft no change names is not modified', () async {
      await database.customStatement(
        'INSERT INTO consumptions (id,created_at,updated_at,sync_status,'
        'doc_number,branch_id,room_id,created_by,status) '
        'VALUES (?,?,?,?,?,?,?,?,?);',
        [
          'cons-draft',
          fixtureNow,
          fixtureNow,
          'pending',
          'TMP-CNS-draft',
          'branch-1',
          'room-1',
          'user-1',
          'draft',
        ],
      );

      await applier.applyAll([
        change(
          seq: 35,
          entityType: 'consumption',
          entityId: 'cons-1',
          payload: serverConsumption(),
        ),
      ]);

      final draft = await row('consumptions', 'cons-draft');
      expect(draft!['status'], 'draft');
      expect(draft['doc_number'], 'TMP-CNS-draft');
      expect(draft['sync_status'], 'pending');
    });

    test('a pending master edit the server never saw is kept', () async {
      await markBaseline(
        entityType: 'item',
        entityId: 'item-1',
        payload: serverItem(serverVersion: 4),
        serverVersion: 4,
      );
      await database.customStatement(
        "UPDATE items SET unit = 'pack', sync_status = 'pending' WHERE id = ?;",
        ['item-1'],
      );

      await applier.applyAll([
        change(
          seq: 36,
          entityType: 'item',
          entityId: 'item-1',
          serverVersion: 5,
          payload: serverItem(name: 'Nama Server', serverVersion: 5),
          fieldVersions: {'name': 5, 'unit': 2},
        ),
      ]);

      final item = (await database.select(database.items).get()).single;
      expect(item.name, 'Nama Server');
      expect(item.unit, 'pack', reason: 'G-Y3 merges per column, not per row');
      expect(
        item.syncStatus.dbValue,
        'pending',
        reason: 'the column is still owed to the server',
      );
    });
  });

  group('reconciliation bookkeeping', () {
    test('a merge that keeps local work is reported to the caller', () async {
      await markBaseline(
        entityType: 'item',
        entityId: 'item-1',
        payload: serverItem(serverVersion: 4),
        serverVersion: 4,
      );
      await database.customStatement(
        "UPDATE items SET unit = 'pack' WHERE id = ?;",
        ['item-1'],
      );

      final outcome = await applier.applyAll([
        change(
          seq: 37,
          entityType: 'item',
          entityId: 'item-1',
          serverVersion: 5,
          payload: serverItem(name: 'Nama Server', serverVersion: 5),
          fieldVersions: {'name': 5, 'unit': 2},
        ),
      ]);

      expect(outcome.reconciledEntities, hasLength(1));
      expect(outcome.reconciledEntities.single.entityId, 'item-1');
    });

    test('a preserved column is put back on the outbox to be pushed', () async {
      // A merge that keeps a local column is only an opinion until the column
      // reaches the server. The queued entry that made the original edit still
      // carries the pre-merge payload hash, so without re-enqueueing it would be
      // rejected as a hash mismatch rather than sent.
      await database.customStatement(
        'INSERT INTO sync_devices (id,created_at,last_seen_at,app_install_id) '
        'VALUES (?,?,?,?);',
        ['device-1', fixtureNow, fixtureNow, 'install-1'],
      );
      await database.customStatement(
        'INSERT INTO sync_outbox (id,request_id,device_id,operation_type,'
        'aggregate_type,aggregate_id,actor_user_id,base_server_version,'
        'occurred_at_utc,payload_hash,created_at,updated_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?);',
        [
          'outbox-1',
          'req-1',
          'device-1',
          'upsert_master',
          'item',
          'item-1',
          'actor-original',
          4,
          fixtureNow,
          'a' * 64,
          fixtureNow,
          fixtureNow,
        ],
      );
      await markBaseline(
        entityType: 'item',
        entityId: 'item-1',
        payload: serverItem(serverVersion: 4),
        serverVersion: 4,
      );
      await database.customStatement(
        "UPDATE items SET unit = 'pack' WHERE id = ?;",
        ['item-1'],
      );

      await applier.applyAll([
        change(
          seq: 42,
          entityType: 'item',
          entityId: 'item-1',
          serverVersion: 5,
          payload: serverItem(name: 'Nama Server', serverVersion: 5),
          fieldVersions: {'name': 5, 'unit': 2},
        ),
      ]);

      final outbox = (await database.select(database.syncOutbox).get()).single;
      expect(outbox.status, 'queued');
      expect(
        outbox.baseServerVersion,
        5,
        reason: 'the push is rebased on what the server just reported',
      );
      expect(
        outbox.payloadHash,
        isNot('a' * 64),
        reason: 'the snapshot hash now describes the merged row',
      );
      expect(
        outbox.actorUserId,
        'actor-original',
        reason:
            'a shared device must not attribute one user edit to another; the '
            'actor comes from the entry that made it',
      );
    });

    test('a merge with no provable author enqueues nothing', () async {
      // No outbox entry means no proven author for the surviving column. The row
      // stays pending rather than borrowing whoever is signed in.
      await markBaseline(
        entityType: 'item',
        entityId: 'item-1',
        payload: serverItem(serverVersion: 4),
        serverVersion: 4,
      );
      await database.customStatement(
        "UPDATE items SET unit = 'pack' WHERE id = ?;",
        ['item-1'],
      );

      await applier.applyAll([
        change(
          seq: 43,
          entityType: 'item',
          entityId: 'item-1',
          serverVersion: 5,
          payload: serverItem(name: 'Nama Server', serverVersion: 5),
          fieldVersions: {'name': 5, 'unit': 2},
        ),
      ]);

      expect(await database.select(database.syncOutbox).get(), isEmpty);
      final item = (await database.select(database.items).get()).single;
      expect(item.unit, 'pack');
      expect(item.syncStatus.dbValue, 'pending');
    });

    test('server field versions are mirrored locally', () async {
      await applier.applyAll([
        change(
          seq: 38,
          entityType: 'item',
          entityId: 'item-1',
          payload: serverItem(),
          fieldVersions: {'name': 5, 'unit': 2},
        ),
      ]);

      final versions = await database.select(database.syncFieldVersions).get();
      expect(versions, hasLength(2));
      expect(
        versions.firstWhere((row) => row.fieldName == 'name').fieldVersion,
        5,
      );
    });

    test('an unknown entity type is skipped rather than failing', () async {
      final outcome = await applier.applyAll([
        change(
          seq: 39,
          entityType: 'something_a_newer_server_invented',
          entityId: 'x',
          payload: const {'id': 'x'},
        ),
      ]);

      expect(outcome.applied, 0);
    });
  });

  group('value decoding matches the local schema', () {
    test('a JSON boolean is stored as this schema stores booleans', () async {
      await applier.applyAll([
        change(
          seq: 40,
          entityType: 'item',
          entityId: 'item-1',
          payload: serverItem(isActive: false),
        ),
      ]);

      expect(
        (await database.select(database.items).get()).single.isActive,
        isFalse,
      );
    });

    test('a date-only value does not drift across a day boundary', () async {
      await applier.applyAll([
        change(
          seq: 41,
          entityType: 'batch',
          entityId: 'batch-1',
          payload: {
            'id': 'batch-1',
            'created_at': '2026-08-01T00:00:00+00:00',
            'updated_at': '2026-08-01T00:00:00+00:00',
            'deleted_at': null,
            'sync_status': 'synced',
            'server_version': 1,
            'item_id': 'item-1',
            'batch_no': 'B-1',
            'expiry_date': '2027-12-31',
          },
        ),
      ]);

      final batch = (await database.select(database.itemBatches).get()).single;
      expect(batch.expiryDate.toUtc(), DateTime.utc(2027, 12, 31));
    });
  });
}
