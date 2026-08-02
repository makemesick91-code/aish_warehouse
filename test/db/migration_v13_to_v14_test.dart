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
    file = File('${directory.path}/migration_v13_to_v14.sqlite');
    if (file.existsSync()) await file.delete();
  });
  tearDown(() async {
    if (file.existsSync()) await file.delete();
  });

  test('v13 to v14 is additive and creates exactly six sync tables', () async {
    var database = AppDatabase(NativeDatabase(file));
    await database.customStatement(
      "INSERT INTO branches (id,created_at,updated_at,sync_status,code,name,is_active) "
      "VALUES ('kept',?,?, 'pending','KEEP','Tetap',1);",
      ['2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'],
    );
    for (final table in const [
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
    final version = await database
        .customSelect('PRAGMA user_version;')
        .getSingle();
    expect(version.read<int>('user_version'), 14);
    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'sync_%' ORDER BY name;",
        )
        .get();
    expect(tables.map((row) => row.read<String>('name')).toSet(), {
      'sync_devices',
      'sync_outbox',
      'sync_entity_states',
      'sync_attempt_logs',
      'sync_conflict_logs',
      'sync_file_uploads',
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
}
