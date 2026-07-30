import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/inventory/data/repositories/drift_inventory_repository.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v2 → v3: Stok Opname arrives as two new tables.
///
/// The upgrade is purely additive, so the interesting assertions are as much
/// about what must *not* change — ledger quantities, balances, master data,
/// existing indexes — as about the tables that appear.
///
/// A v2 database is reproduced faithfully: the schema is created, milli-unit
/// data is written the way v2 stores it, the two opname tables are dropped
/// again, and `user_version` is stamped back to 2. Drift then runs the real
/// [MigrationStrategy] on reopen.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v2_to_v3.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  /// Ids of the rows written into the simulated v2 database, so the assertions
  /// can find them again after the upgrade.
  late String itemId;
  late String batchId;
  late String warehouseId;
  late String roomId;
  late String actorId;

  Future<void> createVersion2Database() async {
    final database = openDatabase();
    final master = DriftMasterDataRepository(database.masterDataDao);

    final branch = await master.ensureBranch(
      code: 'CAB-01',
      name: 'Cabang Uji',
    );
    final room = await master.ensureRoom(
      branchId: branch.id,
      code: 'R1',
      name: 'Ruang Dental 1',
    );
    roomId = room.id;

    final warehouse = await master.ensureLocation(
      type: StockLocationType.warehouse,
      name: 'Warehouse Pusat',
    );
    warehouseId = warehouse.id;

    final actor = await master.ensureUser(
      email: 'warehouse@test.local',
      fullName: 'Petugas Uji',
      role: UserRole.warehouse,
    );
    actorId = actor.id;

    final category = await master.ensureCategory('Alat Sekali Pakai');
    final item = await master.ensureItem(
      sku: 'TEST-0001',
      name: 'Masker Bedah',
      categoryId: category.id,
      unit: 'box',
      minStockRoom: 1,
      minStockBranch: 5,
      hasExpiry: true,
    );
    itemId = item.id;

    final batch = await master.ensureBatch(
      itemId: item.id,
      batchNo: 'B-01',
      expiryDate: DateTime.utc(2027, 1, 31),
    );
    batchId = batch.id;

    const stamp = "'2026-01-01T00:00:00.000Z'";

    // 10.5 units and 2.375 units, already scaled — this is what v2 stores.
    await database.customStatement(
      'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
      'location_id, item_id, batch_id, qty_on_hand) '
      "VALUES ('bal-1', $stamp, $stamp, 'synced', '$warehouseId', "
      "'$itemId', '$batchId', 10500);",
    );
    await database.customStatement(
      'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
      'item_id, batch_id, to_location_id, qty, movement_type, '
      'ref_doc_type, ref_doc_id, actor_user_id) '
      "VALUES ('mov-1', $stamp, $stamp, 'synced', '$itemId', '$batchId', "
      "'$warehouseId', 2375, 'inbound_warehouse', 'SEED', 'seed-1', "
      "'$actorId');",
    );

    // Roll the file back to a genuine v2: the opname tables and their indexes
    // did not exist yet.
    await database.customStatement('DROP TABLE stock_opname_lines;');
    await database.customStatement('DROP TABLE stock_opnames;');
    await database.customStatement('PRAGMA user_version = 2;');
    await database.close();
  }

  Future<Set<String>> tableNames(AppDatabase database) async {
    final rows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table';")
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  Future<Set<String>> indexNames(AppDatabase database) async {
    final rows = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index';")
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  test('menaikkan versi schema ke versi terkini', () async {
    await createVersion2Database();

    final database = openDatabase();
    final row = await database.customSelect('PRAGMA user_version;').getSingle();
    // A v2 file reaches the head in one open: `from < 3` adds the opname
    // tables and `from < 4` rebuilds `stock_opnames` without the lexical
    // timestamp CHECK.
    expect(row.read<int>('user_version'), 6);

    await database.close();
  });

  test('membuat tabel stock_opnames dan stock_opname_lines', () async {
    await createVersion2Database();
    final database = openDatabase();

    final tables = await tableNames(database);
    expect(tables, contains('stock_opnames'));
    expect(tables, contains('stock_opname_lines'));

    await database.close();
  });

  test('membuat index kueri dan partial unique index', () async {
    await createVersion2Database();
    final database = openDatabase();

    final indexes = await indexNames(database);
    expect(indexes, contains('idx_stock_opnames_branch_status'));
    expect(indexes, contains('idx_stock_opnames_room_period'));
    expect(indexes, contains('idx_stock_opnames_counted_by_status'));
    expect(indexes, contains('idx_stock_opname_lines_opname'));
    expect(indexes, contains('idx_stock_opname_lines_item'));
    expect(indexes, contains('idx_stock_opname_lines_batched'));
    expect(indexes, contains('idx_stock_opname_lines_unbatched'));

    await database.close();
  });

  test('kuantitas lama tidak diskalakan ulang oleh migrasi v3', () async {
    await createVersion2Database();
    final database = openDatabase();

    // The v1 → v2 scaling must not run again on a v2 file: 10500 becoming
    // 10500000 is precisely the bug the `from < 2` guard prevents.
    final balance = await database
        .customSelect(
          "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
        )
        .getSingle();
    expect(balance.read<int>('qty_on_hand'), 10500);

    final movement = await database
        .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-1';")
        .getSingle();
    expect(movement.read<int>('qty'), 2375);

    // And the domain still reads them as the quantities they were.
    final inventory = DriftInventoryRepository(database.inventoryDao);
    final balances = await inventory.balancesAtLocation(warehouseId);
    expect(balances.single.qtyOnHand, Quantity.parse('10.5'));
    expect(balances.single.qtyOnHand.format(), '10.5');

    await database.close();
  });

  test('data master dan ledger lama tetap utuh', () async {
    await createVersion2Database();
    final database = openDatabase();

    final master = DriftMasterDataRepository(database.masterDataDao);
    expect((await master.activeBranches()).single.code, 'CAB-01');
    expect((await master.activeRooms()).single.code, 'R1');
    expect((await master.itemById(itemId))!.sku, 'TEST-0001');
    expect((await master.batchById(batchId))!.batchNo, 'B-01');

    final movement = await database
        .customSelect(
          'SELECT ref_doc_id, sync_status, created_at FROM stock_movements '
          "WHERE id = 'mov-1';",
        )
        .getSingle();
    expect(movement.read<String>('ref_doc_id'), 'seed-1');
    expect(movement.read<String>('sync_status'), 'synced');
    expect(
      movement.read<String>('created_at'),
      startsWith('2026-01-01T00:00:00'),
    );

    await database.close();
  });

  test('index inventory lama tidak hilang', () async {
    await createVersion2Database();
    final database = openDatabase();

    final indexes = await indexNames(database);
    expect(indexes, contains('idx_stock_balances_batched'));
    expect(indexes, contains('idx_stock_balances_unbatched'));
    expect(indexes, contains('idx_stock_movements_item'));
    expect(indexes, contains('idx_stock_movements_ref'));

    await database.close();
  });

  test('foreign key aktif dan tidak ada pelanggaran setelah migrasi', () async {
    await createVersion2Database();
    final database = openDatabase();

    final pragma = await database
        .customSelect('PRAGMA foreign_keys;')
        .getSingle();
    expect(pragma.read<int>('foreign_keys'), 1);

    final violations = await database
        .customSelect('PRAGMA foreign_key_check;')
        .get();
    expect(violations, isEmpty);

    await database.close();
  });

  test('kolom generated difference bekerja setelah migrasi', () async {
    await createVersion2Database();
    final database = openDatabase();

    const stamp = "'2026-07-29T00:00:00.000Z'";
    final nurse = await DriftMasterDataRepository(database.masterDataDao)
        .ensureUser(
          email: 'perawat@test.local',
          fullName: 'Perawat Uji',
          role: UserRole.perawat,
          branchId: (await database.masterDataDao.activeBranches()).single.id,
        );
    final branchId = nurse.branchId!;

    await database.customStatement(
      'INSERT INTO stock_opnames (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, room_id, period_year, period_week, counted_by, '
      'status) '
      "VALUES ('so-1', $stamp, $stamp, 'pending', 'TMP-SO-1', '$branchId', "
      "'$roomId', 2026, 31, '${nurse.id}', 'draft');",
    );
    await database.customStatement(
      'INSERT INTO stock_opname_lines (id, created_at, updated_at, '
      'sync_status, opname_id, item_id, batch_id, system_qty, counted_qty) '
      "VALUES ('sol-1', $stamp, $stamp, 'pending', 'so-1', '$itemId', "
      "'$batchId', 10500, 500);",
    );

    final row = await database
        .customSelect(
          "SELECT difference FROM stock_opname_lines WHERE id = 'sol-1';",
        )
        .getSingle();
    // 0.5 counted against a 10.5 snapshot is exactly -10 units.
    expect(row.read<int>('difference'), -10000);
    expect(
      Quantity.fromMilliUnits(row.read<int>('difference')).format(),
      '-10',
    );

    final violations = await database
        .customSelect('PRAGMA foreign_key_check;')
        .get();
    expect(violations, isEmpty);

    await database.close();
  });

  test('database v1 dapat bermigrasi hingga versi terkini melalui v2', () async {
    // Same file, but declared as v1 with whole-unit quantities: the reopen has
    // to scale once *and* add the opname tables, in that order.
    await createVersion2Database();

    final prepare = openDatabase();
    await prepare.customStatement('DROP TABLE stock_opname_lines;');
    await prepare.customStatement('DROP TABLE stock_opnames;');
    await prepare.customStatement(
      "UPDATE stock_balances SET qty_on_hand = 10 WHERE id = 'bal-1';",
    );
    await prepare.customStatement(
      "UPDATE stock_movements SET qty = 2 WHERE id = 'mov-1';",
    );
    await prepare.customStatement('PRAGMA user_version = 1;');
    await prepare.close();

    final database = openDatabase();

    final version = await database
        .customSelect('PRAGMA user_version;')
        .getSingle();
    expect(version.read<int>('user_version'), 6);

    // v1 → v2 scaling ran exactly once...
    final balance = await database
        .customSelect(
          "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
        )
        .getSingle();
    expect(balance.read<int>('qty_on_hand'), 10000);
    final movement = await database
        .customSelect("SELECT qty FROM stock_movements WHERE id = 'mov-1';")
        .getSingle();
    expect(movement.read<int>('qty'), 2000);

    // ...and v2 → v3 added the opname tables on top.
    final tables = await tableNames(database);
    expect(tables, contains('stock_opnames'));
    expect(tables, contains('stock_opname_lines'));

    final violations = await database
        .customSelect('PRAGMA foreign_key_check;')
        .get();
    expect(violations, isEmpty);

    await database.close();
  });

  test('membuka ulang database v3 tidak menjalankan migrasi lagi', () async {
    await createVersion2Database();

    final first = openDatabase();
    expect(await tableNames(first), contains('stock_opnames'));
    await first.close();

    // Already at v3, so `onUpgrade` is not invoked at all.
    final second = openDatabase();
    expect(await tableNames(second), contains('stock_opnames'));
    final balance = await second
        .customSelect(
          "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
        )
        .getSingle();
    expect(balance.read<int>('qty_on_hand'), 10500);
    await second.close();
  });

  test('langkah migrasi v3 dan v4 aman dijalankan ulang', () async {
    // The test above only proves the upgrade is *skipped* on a current file.
    // This one forces the `from < 3` and `from < 4` blocks to run against a
    // database that already has the opname tables, their indexes and the
    // rebuilt header table — the situation a partially applied or re-attempted
    // migration produces. Without `IF NOT EXISTS` on both the tables and the
    // indexes, the second pass throws `index … already exists` and the
    // database cannot be opened at all; and the v4 rebuild has to survive
    // being applied to a table it already rebuilt once.
    await createVersion2Database();

    final migrated = openDatabase();
    expect(await tableNames(migrated), contains('stock_opnames'));
    await migrated.close();

    final rewind = openDatabase();
    await rewind.customStatement('PRAGMA user_version = 2;');
    await rewind.close();

    final again = openDatabase();
    expect(await tableNames(again), contains('stock_opnames'));
    expect(await indexNames(again), contains('idx_stock_opname_lines_batched'));
    // The v4 rebuild replaces `stock_opnames`; its own indexes have to come
    // back with it, replay or not.
    expect(await indexNames(again), contains('idx_stock_opnames_room_period'));
    expect(await indexNames(again), contains('idx_stock_opnames_doc_number'));

    final version = await again
        .customSelect('PRAGMA user_version;')
        .getSingle();
    expect(version.read<int>('user_version'), 6);

    // And the quantities were still not rescaled by the replay.
    final balance = await again
        .customSelect(
          "SELECT qty_on_hand FROM stock_balances WHERE id = 'bal-1';",
        )
        .getSingle();
    expect(balance.read<int>('qty_on_hand'), 10500);

    await again.close();
  });
}
