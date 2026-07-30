import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/inventory/data/repositories/drift_inventory_repository.dart';
import 'package:aish_warehouse/features/master/data/repositories/drift_master_data_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Migration v1 → v2: ledger quantities become fixed-point milli-units.
///
/// v1 and v2 share the same DDL — both quantity columns were already INTEGER
/// and only their *meaning* changed — so a v1 database is faithfully
/// reproduced by creating the schema, writing whole-unit values and stamping
/// `user_version = 1`. Drift then runs the real [MigrationStrategy] on reopen.
void main() {
  late Directory workDir;
  late File dbFile;

  setUp(() async {
    // Kept inside the project's build directory so the test never writes
    // outside the workspace.
    workDir = await Directory('.dart_tool/test_tmp').create(recursive: true);
    dbFile = File('${workDir.path}/migration_v1_to_v2.sqlite');
    if (dbFile.existsSync()) await dbFile.delete();
  });

  tearDown(() async {
    if (dbFile.existsSync()) await dbFile.delete();
  });

  AppDatabase openDatabase() => AppDatabase(NativeDatabase(dbFile));

  /// Builds a database that looks exactly like a v1 install: master rows, one
  /// balance of 10 whole units, one movement of 2 whole units, and a reversal
  /// pointing back at it.
  Future<void> createVersion1Database() async {
    final database = openDatabase();
    final master = DriftMasterDataRepository(database.masterDataDao);

    final branch = await master.ensureBranch(
      code: 'CAB-01',
      name: 'Cabang Uji',
    );
    final warehouse = await master.ensureLocation(
      type: StockLocationType.warehouse,
      name: 'Warehouse Pusat',
    );
    final branchStore = await master.ensureLocation(
      type: StockLocationType.branchStore,
      name: 'Gudang Cabang Uji',
      branchId: branch.id,
    );
    final actor = await master.ensureUser(
      email: 'warehouse@test.local',
      fullName: 'Petugas Uji',
      role: UserRole.warehouse,
    );
    final category = await master.ensureCategory('Alat Sekali Pakai');
    final item = await master.ensureItem(
      sku: 'TEST-0001',
      name: 'Masker Bedah',
      categoryId: category.id,
      unit: 'box',
      minStockRoom: 1,
      minStockBranch: 5,
      hasExpiry: false,
    );

    const stamp = "'2026-01-01T00:00:00.000Z'";

    // Balance of 10 whole units, written the v1 way.
    await database.customStatement(
      'INSERT INTO stock_balances (id, created_at, updated_at, sync_status, '
      'location_id, item_id, qty_on_hand) '
      "VALUES ('bal-1', $stamp, $stamp, 'synced', '${warehouse.id}', "
      "'${item.id}', 10);",
    );

    // Movement of 2 whole units...
    await database.customStatement(
      'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
      'item_id, from_location_id, to_location_id, qty, movement_type, '
      'ref_doc_type, ref_doc_id, actor_user_id) '
      "VALUES ('mov-1', $stamp, $stamp, 'synced', '${item.id}', "
      "'${warehouse.id}', '${branchStore.id}', 2, 'shipment', 'DO', 'DO-1', "
      "'${actor.id}');",
    );
    // ...and its reversal, so the self-reference can be checked afterwards.
    await database.customStatement(
      'INSERT INTO stock_movements (id, created_at, updated_at, sync_status, '
      'item_id, from_location_id, to_location_id, qty, movement_type, '
      'actor_user_id, reversal_of_movement_id) '
      "VALUES ('mov-2', $stamp, $stamp, 'pending', '${item.id}', "
      "'${branchStore.id}', '${warehouse.id}', 2, 'reversal', "
      "'${actor.id}', 'mov-1');",
    );

    // Roll the file back to a genuine v1. Creating the schema always produces
    // the *current* tables, so the ones introduced later have to go before the
    // version stamp — otherwise the upgrade would find v3 tables in a file
    // claiming to be v1.
    await database.customStatement('DROP TABLE stock_opname_lines;');
    await database.customStatement('DROP TABLE stock_opnames;');
    await database.customStatement('PRAGMA user_version = 1;');
    await database.close();
  }

  Future<int> readInt(AppDatabase database, String sql, String column) async {
    final row = await database.customSelect(sql).getSingle();
    return row.read<int>(column);
  }

  test('menaikkan skala kuantitas lama menjadi milli-unit', () async {
    await createVersion1Database();

    final database = openDatabase();
    // Opening is lazy; this query is what triggers the migration. A v1 file
    // now travels all the way to the current version in one open.
    expect(await readInt(database, 'PRAGMA user_version;', 'user_version'), 6);

    expect(
      await readInt(
        database,
        'SELECT qty_on_hand FROM stock_balances;',
        'qty_on_hand',
      ),
      10000,
    );
    expect(
      await readInt(
        database,
        "SELECT qty FROM stock_movements WHERE id = 'mov-1';",
        'qty',
      ),
      2000,
    );

    await database.close();
  });

  test('nilai domain tetap 10 dan 2 setelah migrasi', () async {
    await createVersion1Database();

    final database = openDatabase();
    final inventory = DriftInventoryRepository(database.inventoryDao);

    final balances = await inventory.balancesAtLocation(
      (await DriftMasterDataRepository(
        database.masterDataDao,
      ).warehouseLocation())!.id,
    );

    expect(balances, hasLength(1));
    expect(balances.single.qtyOnHand, Quantity.fromWhole(10));
    expect(balances.single.qtyOnHand.format(), '10');

    final movement = await inventory.movementById('mov-1');
    expect(movement!.qty, Quantity.fromWhole(2));
    expect(movement.qty.format(), '2');

    await database.close();
  });

  test('migrasi tidak dijalankan dua kali', () async {
    await createVersion1Database();

    final first = openDatabase();
    expect(
      await readInt(
        first,
        'SELECT qty_on_hand FROM stock_balances;',
        'qty_on_hand',
      ),
      10000,
    );
    await first.close();

    // Reopening an already migrated database must leave the data alone; a
    // second scaling pass would turn 10000 into 10000000.
    final second = openDatabase();
    expect(
      await readInt(
        second,
        'SELECT qty_on_hand FROM stock_balances;',
        'qty_on_hand',
      ),
      10000,
    );
    expect(
      await readInt(
        second,
        "SELECT qty FROM stock_movements WHERE id = 'mov-1';",
        'qty',
      ),
      2000,
    );
    await second.close();
  });

  test('integritas relasi tetap utuh setelah migrasi', () async {
    await createVersion1Database();
    final database = openDatabase();

    final violations = await database
        .customSelect('PRAGMA foreign_key_check;')
        .get();
    expect(violations, isEmpty);

    // Metadata that a careless table rebuild would have dropped.
    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'stock_balances';",
        )
        .get();
    final indexNames = indexes.map((r) => r.read<String>('name')).toSet();
    expect(indexNames, contains('idx_stock_balances_batched'));
    expect(indexNames, contains('idx_stock_balances_unbatched'));

    await database.close();
  });

  test(
    'id, timestamp, sync status dan referensi reversal dipertahankan',
    () async {
      await createVersion1Database();
      final database = openDatabase();

      final row = await database
          .customSelect(
            'SELECT id, created_at, updated_at, sync_status, '
            'reversal_of_movement_id, ref_doc_id FROM stock_movements '
            "WHERE id = 'mov-2';",
          )
          .getSingle();

      expect(row.read<String>('id'), 'mov-2');
      expect(row.read<String>('created_at'), startsWith('2026-01-01T00:00:00'));
      expect(row.read<String>('sync_status'), 'pending');
      expect(row.read<String>('reversal_of_movement_id'), 'mov-1');

      final original = await database
          .customSelect(
            "SELECT ref_doc_id FROM stock_movements WHERE id = 'mov-1';",
          )
          .getSingle();
      expect(original.read<String>('ref_doc_id'), 'DO-1');

      await database.close();
    },
  );

  test('database baru dibuat langsung pada schema terkini', () async {
    // No v1 file this time: onCreate must land on the current version without
    // running the upgrade path at all.
    final database = openDatabase();
    expect(await readInt(database, 'PRAGMA user_version;', 'user_version'), 6);
    await database.close();
  });
}
