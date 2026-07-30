import 'dart:io';

import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

void main() {
  late TestContext context;

  setUp(() {
    context = TestContext.create();
  });

  tearDown(() => context.dispose());

  test('schema version adalah 8', () {
    // v2 introduced fixed-point milli-unit quantities; v3 adds Stok Opname
    // as its own version rather than extending v2 (spec §6.3); v4 hardens
    // `stock_opnames` by dropping the lexical timestamp-order CHECK; v5 adds
    // Purchase Request; v6 adds Delivery Order; v7 adds Good Receipt; v8 adds
    // Distribusi.
    expect(context.database.schemaVersion, 8);
  });

  test('kolom kuantitas ledger bertipe INTEGER, bukan REAL', () async {
    Future<String> columnType(String table, String column) async {
      final rows = await context.database
          .customSelect('PRAGMA table_info($table);')
          .get();
      final row = rows.firstWhere((r) => r.read<String>('name') == column);
      return row.read<String>('type').toUpperCase();
    }

    expect(await columnType('stock_balances', 'qty_on_hand'), 'INTEGER');
    expect(await columnType('stock_movements', 'qty'), 'INTEGER');
  });

  test('kuantitas desimal tersimpan sebagai milli-unit INTEGER', () async {
    final fixture = await buildFixture(context);
    await context.posting.postInboundWarehouse(
      itemId: fixture.simpleItem.id,
      toLocationId: fixture.warehouse.id,
      qty: Quantity.parse('0.5'),
      actorUserId: fixture.actor.id,
    );

    final row = await context.database
        .customSelect('SELECT qty_on_hand FROM stock_balances;')
        .getSingle();

    expect(row.read<int>('qty_on_hand'), 500);
  });

  test('foreign key aktif', () async {
    final row = await context.database
        .customSelect('PRAGMA foreign_keys;')
        .getSingle();
    expect(row.read<int>('foreign_keys'), 1);
  });

  test('foreign key benar-benar ditegakkan', () async {
    await expectLater(
      context.database.customStatement(
        "INSERT INTO rooms (id, created_at, updated_at, sync_status, "
        "branch_id, code, name, is_active) "
        "VALUES ('r1', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
        "'pending', 'cabang-tidak-ada', 'R9', 'Ruang', 1);",
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('saldo tidak dapat berada di bawah nol pada level database', () async {
    final fixture = await buildFixture(context);
    await context.posting.postInboundWarehouse(
      itemId: fixture.simpleItem.id,
      toLocationId: fixture.warehouse.id,
      qty: Quantity.fromWhole(5),
      actorUserId: fixture.actor.id,
    );

    await expectLater(
      context.database.customStatement(
        'UPDATE stock_balances SET qty_on_hand = -1;',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('qty movement harus lebih besar dari nol pada level database', () async {
    final fixture = await buildFixture(context);

    await expectLater(
      context.database.customStatement(
        "INSERT INTO stock_movements (id, created_at, updated_at, sync_status, "
        "item_id, to_location_id, qty, movement_type, actor_user_id) "
        "VALUES ('m1', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
        "'pending', '${fixture.simpleItem.id}', '${fixture.warehouse.id}', 0, "
        "'inbound_warehouse', '${fixture.actor.id}');",
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('movement wajib memiliki minimal satu lokasi', () async {
    final fixture = await buildFixture(context);

    await expectLater(
      context.database.customStatement(
        "INSERT INTO stock_movements (id, created_at, updated_at, sync_status, "
        "item_id, qty, movement_type, actor_user_id) "
        "VALUES ('m2', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
        "'pending', '${fixture.simpleItem.id}', 1, "
        "'inbound_warehouse', '${fixture.actor.id}');",
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('lokasi warehouse tidak boleh memiliki cabang', () async {
    final fixture = await buildFixture(context);
    final branchId = fixture.branchStore.branchId!;

    await expectLater(
      context.database.customStatement(
        "INSERT INTO stock_locations (id, created_at, updated_at, sync_status, "
        "type, branch_id, name) "
        "VALUES ('l1', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
        "'pending', 'warehouse', '$branchId', 'Warehouse Salah');",
      ),
      throwsA(isA<Exception>()),
    );
  });

  group('saldo tanpa batch bersifat unik per lokasi dan barang', () {
    test('index parsial mencegah baris saldo ganda', () async {
      final fixture = await buildFixture(context);
      await context.posting.postInboundWarehouse(
        itemId: fixture.simpleItem.id,
        toLocationId: fixture.warehouse.id,
        qty: Quantity.fromWhole(5),
        actorUserId: fixture.actor.id,
      );

      // SQLite treats NULLs as distinct in a plain UNIQUE constraint, so this
      // second NULL-batch row is what the partial unique index has to reject.
      await expectLater(
        context.database.customStatement(
          "INSERT INTO stock_balances (id, created_at, updated_at, "
          "sync_status, location_id, item_id, qty_on_hand) "
          "VALUES ('b-dup', '2026-01-01T00:00:00.000Z', "
          "'2026-01-01T00:00:00.000Z', 'pending', '${fixture.warehouse.id}', "
          "'${fixture.simpleItem.id}', 3);",
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  test('DAO dan repository ledger tidak memiliki update/delete movement', () {
    // G-A1 is enforced structurally: no mutating API may exist for
    // stock_movements. Guard the source so it cannot be reintroduced.
    final sources = {
      'inventory_dao.dart': File(
        'lib/core/db/daos/inventory_dao.dart',
      ).readAsStringSync(),
      'inventory_repository.dart': File(
        'lib/features/inventory/domain/repositories/inventory_repository.dart',
      ).readAsStringSync(),
      'drift_inventory_repository.dart': File(
        'lib/features/inventory/data/repositories/'
        'drift_inventory_repository.dart',
      ).readAsStringSync(),
    };

    for (final entry in sources.entries) {
      expect(
        entry.value,
        isNot(contains('updateStockMovement')),
        reason: '${entry.key} must not expose movement updates',
      );
      expect(
        entry.value,
        isNot(contains('deleteStockMovement')),
        reason: '${entry.key} must not expose movement deletes',
      );
    }

    expect(
      sources['inventory_dao.dart'],
      isNot(contains('update(stockMovements)')),
    );
    expect(
      sources['inventory_dao.dart'],
      isNot(contains('delete(stockMovements)')),
    );
    expect(sources['inventory_dao.dart'], contains('insertMovement'));
  });

  test('tidak ada double atau REAL pada jalur perhitungan ledger', () {
    // Q-3: the ledger is integer-only. Guard the sources so a `double` or a
    // `CAST(... AS REAL)` cannot creep back into balance arithmetic.
    //
    // Comments are stripped first: the guard is about executable code, and the
    // files legitimately *describe* why floating point is not used.
    String codeOnly(String source) => source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    final sources = {
      'inventory_dao.dart': File(
        'lib/core/db/daos/inventory_dao.dart',
      ).readAsStringSync(),
      'stock_posting_service.dart': File(
        'lib/features/inventory/domain/services/stock_posting_service.dart',
      ).readAsStringSync(),
      'drift_inventory_repository.dart': File(
        'lib/features/inventory/data/repositories/'
        'drift_inventory_repository.dart',
      ).readAsStringSync(),
      'inventory_tables.dart': File(
        'lib/core/db/tables/inventory_tables.dart',
      ).readAsStringSync(),
      'quantity.dart': File(
        'lib/core/quantity/quantity.dart',
      ).readAsStringSync(),
    };

    for (final entry in sources.entries) {
      final code = codeOnly(entry.value);
      expect(
        code,
        isNot(matches(RegExp(r'\bdouble\b'))),
        reason: '${entry.key} must not use double for ledger quantities',
      );
      expect(
        code,
        isNot(contains('AS REAL')),
        reason: '${entry.key} must not cast ledger quantities to REAL',
      );
      expect(
        code,
        isNot(contains('real()')),
        reason: '${entry.key} must not declare a REAL quantity column',
      );
    }
  });

  test('sync_status default untuk data lokal baru adalah pending', () async {
    final fixture = await buildFixture(context);
    final row = await context.database
        .customSelect(
          'SELECT sync_status FROM items WHERE id = ?;',
          variables: [Variable<String>(fixture.simpleItem.id)],
        )
        .getSingle();

    expect(row.read<String>('sync_status'), 'pending');
  });
}
