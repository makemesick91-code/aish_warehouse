import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late File file;
  setUp(() async {
    final directory = await Directory(
      '.dart_tool/test_tmp',
    ).create(recursive: true);
    file = File('${directory.path}/migration_v14_to_v15.sqlite');
    if (file.existsSync()) await file.delete();
  });
  tearDown(() async {
    if (file.existsSync()) await file.delete();
  });

  /// Rewinds a freshly created database to look like a v14 one: the five pull
  /// tables removed, `user_version` set back.
  Future<void> rewindToV14(AppDatabase database) async {
    for (final table in const [
      'sync_pull_logs',
      'sync_tombstones',
      'sync_field_versions',
      'sync_entity_snapshots',
      'sync_pull_cursors',
    ]) {
      await database.customStatement('DROP TABLE $table;');
    }
    await database.customStatement('PRAGMA user_version = 14;');
  }

  test('v14 to v15 is additive and creates exactly five pull tables', () async {
    var database = AppDatabase(NativeDatabase(file));
    await database.customStatement(
      'INSERT INTO branches (id,created_at,updated_at,sync_status,code,name,'
      'is_active) VALUES (?,?,?,?,?,?,?);',
      [
        'kept',
        '2026-01-01T00:00:00.000Z',
        '2026-01-01T00:00:00.000Z',
        'pending',
        'KEEP',
        'Tetap',
        1,
      ],
    );
    await rewindToV14(database);
    await database.close();

    database = AppDatabase(NativeDatabase(file));
    expect(
      (await database.customSelect('PRAGMA user_version;').getSingle())
          .read<int>('user_version'),
      15,
    );
    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name LIKE 'sync_%' ORDER BY name;",
        )
        .get();
    expect(tables.map((row) => row.read<String>('name')).toSet(), {
      // The six Milestone 12B tables survive untouched...
      'sync_devices',
      'sync_outbox',
      'sync_entity_states',
      'sync_attempt_logs',
      'sync_conflict_logs',
      'sync_file_uploads',
      // ...and only these five are added.
      'sync_pull_cursors',
      'sync_entity_snapshots',
      'sync_field_versions',
      'sync_tombstones',
      'sync_pull_logs',
    });
    expect(
      (await database
              .customSelect("SELECT name FROM branches WHERE id='kept';")
              .getSingle())
          .read<String>('name'),
      'Tetap',
    );
    expect(
      await database.customSelect('PRAGMA foreign_key_check;').get(),
      isEmpty,
    );
    await database.close();
  });

  test('the upgrade preserves every business row and its sync state', () async {
    var database = AppDatabase(NativeDatabase(file));
    const now = '2026-01-01T00:00:00.000Z';
    await database.customStatement(
      'INSERT INTO branches (id,created_at,updated_at,sync_status,code,name,'
      'is_active) VALUES (?,?,?,?,?,?,?);',
      ['b1', now, now, 'pending', 'B1', 'Cabang Satu', 1],
    );
    await database.customStatement(
      'INSERT INTO item_categories (id,created_at,updated_at,sync_status,name) '
      'VALUES (?,?,?,?,?);',
      ['c1', now, now, 'synced', 'Kategori'],
    );
    await database.customStatement(
      'INSERT INTO sync_devices (id,created_at,last_seen_at,app_install_id) '
      'VALUES (?,?,?,?);',
      ['d1', now, now, 'install-1'],
    );
    await database.customStatement(
      'INSERT INTO sync_outbox (id,request_id,device_id,operation_type,'
      'aggregate_type,aggregate_id,actor_user_id,occurred_at_utc,payload_hash,'
      'created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?);',
      [
        'o1',
        'r1',
        'd1',
        'upsert_master',
        'category',
        'c1',
        'actor-1',
        now,
        'a' * 64,
        now,
        now,
      ],
    );
    await database.customStatement(
      'INSERT INTO sync_entity_states (id,aggregate_type,aggregate_id,'
      'server_version) VALUES (?,?,?,?);',
      ['s1', 'category', 'c1', 7],
    );
    await rewindToV14(database);
    await database.close();

    database = AppDatabase(NativeDatabase(file));
    expect(
      (await database.select(database.branches).get()).single.name,
      'Cabang Satu',
    );
    expect(
      (await database.select(database.syncOutbox).get()).single.requestId,
      'r1',
    );
    // The pre-existing acknowledged version is exactly what the first merge
    // reads as its base, so losing it here would make the first pull treat every
    // server column as newer than it is.
    expect(
      (await database.select(database.syncEntityStates).get())
          .single
          .serverVersion,
      7,
    );
    expect(
      (await database.select(database.syncDevices).get()).single.appInstallId,
      'install-1',
    );
    await database.close();
  });

  test('the new pull tables start empty on an upgraded device', () async {
    var database = AppDatabase(NativeDatabase(file));
    const now = '2026-01-01T00:00:00.000Z';
    await database.customStatement(
      'INSERT INTO item_categories (id,created_at,updated_at,sync_status,name) '
      'VALUES (?,?,?,?,?);',
      ['c1', now, now, 'pending', 'Kategori'],
    );
    // A row soft-deleted by this device before v15 must not be mistaken for a
    // server tombstone, or the legitimate upsert a later pull brings would be
    // refused as a resurrection.
    await database.customStatement(
      'INSERT INTO item_categories (id,created_at,updated_at,deleted_at,'
      'sync_status,name) VALUES (?,?,?,?,?,?);',
      ['c2', now, now, now, 'pending', 'Dihapus lokal'],
    );
    await rewindToV14(database);
    await database.close();

    database = AppDatabase(NativeDatabase(file));
    // A cursor invented here would make the first pull skip everything below it,
    // silently and permanently.
    expect(await database.select(database.syncPullCursors).get(), isEmpty);
    // A baseline invented from a local row would be read as "the server said
    // this", so a pending local edit would be discarded on the first merge.
    expect(await database.select(database.syncEntitySnapshots).get(), isEmpty);
    expect(await database.select(database.syncFieldVersions).get(), isEmpty);
    expect(await database.select(database.syncTombstones).get(), isEmpty);
    expect(await database.select(database.syncPullLogs).get(), isEmpty);
    await database.close();
  });

  test('the v14 and v15 steps are safe to run again', () async {
    var database = AppDatabase(NativeDatabase(file));
    await rewindToV14(database);
    await database.close();

    database = AppDatabase(NativeDatabase(file));
    await database.close();
    // Re-opening runs no migration at all; the second open must be a no-op
    // rather than a second CREATE TABLE.
    database = AppDatabase(NativeDatabase(file));
    expect(
      (await database.customSelect('PRAGMA user_version;').getSingle())
          .read<int>('user_version'),
      15,
    );
    expect(await database.select(database.syncPullCursors).get(), isEmpty);
    await database.close();
  });

  test('a v13 database migrates all the way through v15', () async {
    var database = AppDatabase(NativeDatabase(file));
    const now = '2026-01-01T00:00:00.000Z';
    await database.customStatement(
      'INSERT INTO branches (id,created_at,updated_at,sync_status,code,name,'
      'is_active) VALUES (?,?,?,?,?,?,?);',
      ['b1', now, now, 'pending', 'B1', 'Cabang Satu', 1],
    );
    for (final table in const [
      'sync_pull_logs',
      'sync_tombstones',
      'sync_field_versions',
      'sync_entity_snapshots',
      'sync_pull_cursors',
      'sync_file_uploads',
      'sync_conflict_logs',
      'sync_attempt_logs',
      'sync_entity_states',
      'sync_outbox',
      'sync_devices',
    ]) {
      await database.customStatement('DROP TABLE $table;');
    }
    await database.customStatement('PRAGMA user_version = 13;');
    await database.close();

    database = AppDatabase(NativeDatabase(file));
    expect(
      (await database.customSelect('PRAGMA user_version;').getSingle())
          .read<int>('user_version'),
      15,
    );
    expect(
      (await database.select(database.branches).get()).single.name,
      'Cabang Satu',
    );
    expect(
      await database.customSelect('PRAGMA foreign_key_check;').get(),
      isEmpty,
    );
    await database.close();
  });
}
