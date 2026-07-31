import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// Schema v10 as a **fresh** database gets it (§37).
///
/// Everything here is asserted against the objects SQLite actually holds rather than
/// against the Dart declarations that produced them, because the two can disagree in
/// exactly one direction that matters: a constraint written in a `@TableIndex.sql`
/// string, or a CHECK in `customConstraints`, is not type-checked by anything. If a
/// clause is missing, the Dart still compiles and the use cases still pass — and the
/// database stops being the last line of defence.
///
/// Four things get more attention than the rest, because each is easy to write in a
/// way that compiles and does nothing:
///
/// * the posted-status CHECK, which has to pair `posted_at` **and** `posted_by` with
///   the status in both directions;
/// * the note CHECK, which has to accept NULL *explicitly* — SQLite treats a CHECK
///   evaluating to NULL as **satisfied**, and this column is legitimately NULL on most
///   compliant rows, so `trim(note) <> ''` alone would refuse every one of them;
/// * `idx_consumptions_doc_number`, which is deliberately **unqualified** where most
///   document number indexes in this schema carry `WHERE deleted_at IS NULL`
///   (G-A3: *"nomor dokumen … tidak dipakai ulang"*);
/// * the batched/unbatched partial unique pair, which needs *two* indexes because
///   SQLite treats every NULL as distinct.
///
/// One absence is asserted rather than assumed: **no patient column anywhere.** A
/// consumption is an inventory document, and personal health information has a wholly
/// different retention and access story than a stock ledger (§9).
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  Future<List<String>> columnNames(String table) async {
    final rows = await context.database
        .customSelect('PRAGMA table_xinfo($table);')
        .get();
    return rows.map((row) => row.read<String>('name')).toList(growable: false);
  }

  Future<String> columnType(String table, String column) async {
    final rows = await context.database
        .customSelect('PRAGMA table_xinfo($table);')
        .get();
    final match = rows.where((row) => row.read<String>('name') == column);
    expect(match, isNotEmpty, reason: '$table.$column tidak ada.');
    return match.first.read<String>('type');
  }

  Future<int> columnNotNull(String table, String column) async {
    final rows = await context.database
        .customSelect('PRAGMA table_xinfo($table);')
        .get();
    final match = rows.where((row) => row.read<String>('name') == column);
    expect(match, isNotEmpty, reason: '$table.$column tidak ada.');
    return match.first.read<int>('notnull');
  }

  Future<String> tableSql(String table) async {
    final row = await context.database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?;",
          variables: [Variable<String>(table)],
        )
        .getSingle();
    return row.read<String>('sql');
  }

  Future<String> indexSql(String name) async {
    final row = await context.database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?;",
          variables: [Variable<String>(name)],
        )
        .getSingle();
    return row.read<String>('sql');
  }

  Future<Set<String>> indexNames(String needle) async {
    final rows = await context.database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE '%$needle%' AND name NOT LIKE 'sqlite_%';",
        )
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  Future<Map<String, String>> foreignKeys(String table) async {
    final rows = await context.database
        .customSelect('PRAGMA foreign_key_list($table);')
        .get();
    return {
      for (final row in rows)
        row.read<String>('from'): row.read<String>('table'),
    };
  }

  group('struktur tabel', () {
    test('schemaVersion adalah 12', () async {
      final row = await context.database
          .customSelect('PRAGMA user_version;')
          .getSingle();
      expect(row.read<int>('user_version'), 13);
      expect(context.database.schemaVersion, 13);
    });

    test('dua tabel Pemakaian tersedia', () async {
      final rows = await context.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'consumption%';",
          )
          .get();

      expect(rows.map((row) => row.read<String>('name')).toSet(), {
        'consumptions',
        'consumption_lines',
      });
    });

    test('kolom standar hadir di kedua tabel', () async {
      for (final table in ['consumptions', 'consumption_lines']) {
        expect(
          await columnNames(table),
          containsAll(<String>[
            'id',
            'created_at',
            'updated_at',
            'deleted_at',
            'sync_status',
          ]),
          reason: '$table kehilangan kolom standar §2.',
        );
      }
    });

    test('kolom bisnis header sesuai §8', () async {
      expect(
        await columnNames('consumptions'),
        containsAll(<String>[
          'doc_number',
          'branch_id',
          'room_id',
          'created_by',
          'status',
          'note',
          'posted_at',
          'posted_by',
        ]),
      );
    });

    test('kolom bisnis baris sesuai §9', () async {
      expect(
        await columnNames('consumption_lines'),
        containsAll(<String>[
          'consumption_id',
          'item_id',
          'batch_id',
          'qty',
          'note',
        ]),
      );
    });

    test('qty bertipe INTEGER, bukan REAL', () async {
      // Q-3: milli-units. A REAL column would accumulate binary rounding error and
      // drift away from the ledger it mirrors.
      expect(await columnType('consumption_lines', 'qty'), 'INTEGER');
    });

    test('batch_id baris nullable (§9)', () async {
      // The opposite of `disposal_lines`, and deliberately: a consumption is
      // ordinary usage, so an item without an expiry date is consumed without a
      // batch (G-E2). Making this NOT NULL would make gauze unconsumable.
      expect(await columnNotNull('consumption_lines', 'batch_id'), 0);
    });

    test('posted_at, posted_by dan note nullable; sisanya tidak', () async {
      expect(await columnNotNull('consumptions', 'branch_id'), 1);
      expect(await columnNotNull('consumptions', 'room_id'), 1);
      expect(await columnNotNull('consumptions', 'created_by'), 1);
      expect(await columnNotNull('consumptions', 'doc_number'), 1);
      expect(await columnNotNull('consumptions', 'posted_at'), 0);
      expect(await columnNotNull('consumptions', 'posted_by'), 0);
      expect(await columnNotNull('consumptions', 'note'), 0);
    });

    test('foreign key lengkap', () async {
      expect(await foreignKeys('consumptions'), {
        'branch_id': 'branches',
        'room_id': 'rooms',
        'created_by': 'users',
        'posted_by': 'users',
      });
      expect(await foreignKeys('consumption_lines'), {
        'consumption_id': 'consumptions',
        'item_id': 'items',
        'batch_id': 'item_batches',
      });
    });

    test('tidak ada kolom lokasi bebas pada baris', () async {
      // §9: the source is the header's room, for every line. A per-line location
      // column would let one document draw from two rooms — the invariant the
      // header exists to state.
      final columns = await columnNames('consumption_lines');
      for (final forbidden in const [
        'location_id',
        'from_location_id',
        'to_location_id',
        'room_id',
      ]) {
        expect(
          columns,
          isNot(contains(forbidden)),
          reason: 'consumption_lines.$forbidden akan membuka sumber bebas.',
        );
      }
    });

    test('tidak ada kolom tujuan pada header', () async {
      // §19: a consumption has one leg. Stock leaves the room and enters nothing.
      final columns = await columnNames('consumptions');
      for (final forbidden in const [
        'to_location_id',
        'destination_room_id',
        'destination_location_id',
      ]) {
        expect(columns, isNot(contains(forbidden)));
      }
    });

    test('tidak ada kolom data pasien di mana pun', () async {
      // §9/§14: this is an inventory document. A column that *could* hold personal
      // health information would put it inside a table every branch head reads.
      const forbidden = [
        'patient_id',
        'patient_name',
        'patient',
        'medical_record_no',
        'medical_record',
        'mrn',
        'diagnosis',
        'procedure',
        'procedure_code',
        'treatment',
      ];
      for (final table in ['consumptions', 'consumption_lines']) {
        final columns = await columnNames(table);
        for (final column in forbidden) {
          expect(
            columns,
            isNot(contains(column)),
            reason: '$table.$column adalah data pasien dan dilarang §9.',
          );
        }
      }
    });
  });

  group('CHECK', () {
    test('status dibatasi dua nilai', () async {
      final sql = await tableSql('consumptions');
      expect(sql, contains("status IN ('draft', 'posted')"));
    });

    test(
      'CHECK menuntut posted_at dan posted_by konsisten dengan status',
      () async {
        final sql = await tableSql('consumptions');
        expect(sql, contains('posted_at IS NULL'));
        expect(sql, contains('posted_by IS NULL'));
        expect(sql, contains('posted_at IS NOT NULL'));
        expect(sql, contains('posted_by IS NOT NULL'));
      },
    );

    test('CHECK tidak mewajibkan note pada dokumen posted', () async {
      // The difference from `disposals`, stated as an assertion so nobody
      // "harmonises" the two: G-E7 makes a disposal reason mandatory, and nothing in
      // the specification asks a nurse to justify ordinary consumption. A posted row
      // with no note is compliant.
      final sql = await tableSql('consumptions');
      expect(sql.contains('note IS NOT NULL'), isFalse);
    });

    test('CHECK note header menerima NULL dan menolak string kosong', () async {
      final sql = await tableSql('consumptions');
      expect(sql, contains('note IS NULL OR'));
      expect(sql, contains("trim(note) <> ''"));
    });

    test('tidak ada perbandingan timestamp leksikal', () async {
      // Timestamps are ISO-8601 TEXT, so `posted_at >= created_at` in SQL compares
      // characters rather than instants — the trap schema v4 removed from
      // `stock_opnames`. Ordering is `DocumentTimestampPolicy`'s, on UTC DateTimes.
      final sql = await tableSql('consumptions');
      expect(sql.contains('posted_at >= created_at'), isFalse);
      expect(sql.contains('posted_at > created_at'), isFalse);
      expect(sql.contains('created_at <='), isFalse);
    });

    test('CHECK qty > 0 pada baris', () async {
      expect(await tableSql('consumption_lines'), contains('qty > 0'));
    });

    test('CHECK note baris menerima NULL dan menolak string kosong', () async {
      final sql = await tableSql('consumption_lines');
      expect(sql, contains('note IS NULL OR'));
      expect(sql, contains("trim(note) <> ''"));
    });
  });

  group('CHECK ditegakkan oleh SQLite', () {
    Future<void> insertHeader({
      required String id,
      required String status,
      String? note,
      String? postedAt,
      String? postedBy,
      required ConsumptionSchemaFixture master,
    }) => context.database.customStatement(
      'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
      'doc_number, branch_id, room_id, created_by, status, note, posted_at, '
      'posted_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-30T00:00:00.000Z',
        '2026-07-30T00:00:00.000Z',
        'pending',
        'TMP-CNS-$id',
        master.branch,
        master.room,
        master.nurse,
        status,
        note,
        postedAt,
        postedBy,
      ],
    );

    test('draft dengan posted_at ditolak', () async {
      final master = await seedConsumptionSchemaFixture(context);
      await expectLater(
        insertHeader(
          id: 'c1',
          status: 'draft',
          postedAt: '2026-07-30T01:00:00.000Z',
          master: master,
        ),
        throwsA(anything),
      );
    });

    test('posted tanpa posted_by ditolak', () async {
      final master = await seedConsumptionSchemaFixture(context);
      await expectLater(
        insertHeader(
          id: 'c2',
          status: 'posted',
          postedAt: '2026-07-30T01:00:00.000Z',
          master: master,
        ),
        throwsA(anything),
      );
    });

    test('posted tanpa posted_at ditolak', () async {
      final master = await seedConsumptionSchemaFixture(context);
      await expectLater(
        insertHeader(
          id: 'c3',
          status: 'posted',
          postedBy: master.nurse,
          master: master,
        ),
        throwsA(anything),
      );
    });

    test('posted tanpa note diterima', () async {
      // The compliant row the disposal's stricter CHECK would have refused.
      final master = await seedConsumptionSchemaFixture(context);
      await insertHeader(
        id: 'c4',
        status: 'posted',
        postedAt: '2026-07-30T01:00:00.000Z',
        postedBy: master.nurse,
        master: master,
      );

      final row = await context.database
          .customSelect("SELECT note FROM consumptions WHERE id = 'c4';")
          .getSingle();
      expect(row.read<String?>('note'), isNull);
    });

    test('status di luar enum ditolak', () async {
      final master = await seedConsumptionSchemaFixture(context);
      for (final status in const ['submitted', 'approved', 'rejected']) {
        await expectLater(
          insertHeader(id: 'c-$status', status: status, master: master),
          throwsA(anything),
          reason: '$status bukan status Pemakaian.',
        );
      }
    });

    test('note spasi ditolak pada draft maupun posted', () async {
      final master = await seedConsumptionSchemaFixture(context);
      await expectLater(
        insertHeader(id: 'c5', status: 'draft', note: '   ', master: master),
        throwsA(anything),
      );
      await expectLater(
        insertHeader(
          id: 'c6',
          status: 'posted',
          note: ' ',
          postedAt: '2026-07-30T01:00:00.000Z',
          postedBy: master.nurse,
          master: master,
        ),
        throwsA(anything),
      );
    });

    test('qty nol dan negatif pada baris ditolak', () async {
      final master = await seedConsumptionSchemaFixture(context);
      await insertHeader(id: 'c7', status: 'draft', master: master);

      for (final qty in const [0, -1000]) {
        await expectLater(
          context.database.customStatement(
            'INSERT INTO consumption_lines (id, created_at, updated_at, '
            'sync_status, consumption_id, item_id, batch_id, qty) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
            [
              'l-$qty',
              '2026-07-30T00:00:00.000Z',
              '2026-07-30T00:00:00.000Z',
              'pending',
              'c7',
              master.expiryItem,
              master.batch,
              qty,
            ],
          ),
          throwsA(anything),
        );
      }
    });

    test('baris tanpa batch diterima untuk barang tanpa ED', () async {
      // §9's other half: the database accepts a null batch, and the *domain* is what
      // ties it to `items.has_expiry` — a column this table cannot read.
      final master = await seedConsumptionSchemaFixture(context);
      await insertHeader(id: 'c8', status: 'draft', master: master);

      await context.database.customStatement(
        'INSERT INTO consumption_lines (id, created_at, updated_at, '
        'sync_status, consumption_id, item_id, batch_id, qty) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'l-plain',
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          'pending',
          'c8',
          master.plainItem,
          null,
          Quantity.parse('1.5').milliUnits,
        ],
      );

      final row = await context.database
          .customSelect(
            "SELECT qty FROM consumption_lines WHERE id = 'l-plain';",
          )
          .getSingle();
      expect(row.read<int>('qty'), Quantity.parse('1.5').milliUnits);
    });

    test('ruangan cabang lain diterima database — aturan ada di domain', () async {
      // Stated so nobody mistakes the gap for coverage: `rooms.branch_id =
      // consumptions.branch_id` is a cross-table equality SQLite cannot express as a
      // foreign key. The use cases enforce it and the security tests prove it.
      final master = await seedConsumptionSchemaFixture(context);
      await context.database.customStatement(
        'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
        'doc_number, branch_id, room_id, created_by, status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          'c-mismatch',
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          'pending',
          'TMP-CNS-c-mismatch',
          master.branch,
          master.otherBranchRoom,
          master.nurse,
          'draft',
        ],
      );

      final row = await context.database
          .customSelect(
            "SELECT room_id FROM consumptions WHERE id = 'c-mismatch';",
          )
          .getSingle();
      expect(row.read<String>('room_id'), master.otherBranchRoom);
    });
  });

  group('index', () {
    test('seluruh index Pemakaian hadir', () async {
      expect(await indexNames('consumption'), {
        'idx_consumptions_branch_status',
        'idx_consumptions_room_status',
        'idx_consumptions_created_by_status',
        'idx_consumptions_posted_by_status',
        'idx_consumptions_created_at',
        'idx_consumptions_posted_at',
        'idx_consumptions_doc_number',
        'idx_consumption_lines_consumption',
        'idx_consumption_lines_item',
        'idx_consumption_lines_batch',
        'idx_consumption_lines_batched',
        'idx_consumption_lines_unbatched',
      });
    });

    test('doc_number unik tanpa klausa partial (G-A3)', () async {
      final sql = await indexSql('idx_consumptions_doc_number');
      expect(sql, contains('UNIQUE'));
      // Deliberately different from the opname / PR / DO / GR / Distribusi number
      // indexes: a consumption number must never be reissued, so a soft-deleted row
      // keeps holding it.
      expect(sql.toLowerCase().contains('where'), isFalse);
    });

    test('posisi batch unik hanya untuk baris hidup', () async {
      final sql = await indexSql('idx_consumption_lines_batched');
      expect(sql, contains('UNIQUE'));
      expect(sql, contains('consumption_id, item_id, batch_id'));
      expect(sql, contains('batch_id IS NOT NULL'));
      // What lets a line removed from a draft be added back afterwards.
      expect(sql, contains('deleted_at IS NULL'));
    });

    test('posisi tanpa batch punya index unik sendiri', () async {
      // The second shape exists because SQLite treats every NULL as distinct: one
      // index over `(…, batch_id)` would let an item without expiry be added any
      // number of times.
      final sql = await indexSql('idx_consumption_lines_unbatched');
      expect(sql, contains('UNIQUE'));
      expect(sql, contains('consumption_id, item_id'));
      expect(sql, contains('batch_id IS NULL'));
      expect(sql, contains('deleted_at IS NULL'));
    });

    test('index batch menolak batch ganda pada satu dokumen', () async {
      final master = await seedConsumptionSchemaFixture(context);
      await context.database.customStatement(
        'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
        'doc_number, branch_id, room_id, created_by, status) '
        "VALUES ('p1', ?, ?, 'pending', 'TMP-CNS-p1', ?, ?, ?, 'draft');",
        [
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          master.branch,
          master.room,
          master.nurse,
        ],
      );

      Future<void> insertLine(String id) => context.database.customStatement(
        'INSERT INTO consumption_lines (id, created_at, updated_at, '
        'sync_status, consumption_id, item_id, batch_id, qty) '
        "VALUES (?, ?, ?, 'pending', 'p1', ?, ?, ?);",
        [
          id,
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          master.expiryItem,
          master.batch,
          1000,
        ],
      );

      await insertLine('pl1');
      await expectLater(insertLine('pl2'), throwsA(anything));

      // Soft-deleting the first frees the position again.
      await context.database.customStatement(
        "UPDATE consumption_lines SET deleted_at = ? WHERE id = 'pl1';",
        ['2026-07-30T01:00:00.000Z'],
      );
      await insertLine('pl3');
    });

    test('index tanpa batch menolak barang ganda pada satu dokumen', () async {
      final master = await seedConsumptionSchemaFixture(context);
      await context.database.customStatement(
        'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
        'doc_number, branch_id, room_id, created_by, status) '
        "VALUES ('p2', ?, ?, 'pending', 'TMP-CNS-p2', ?, ?, ?, 'draft');",
        [
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          master.branch,
          master.room,
          master.nurse,
        ],
      );

      Future<void> insertLine(String id) => context.database.customStatement(
        'INSERT INTO consumption_lines (id, created_at, updated_at, '
        'sync_status, consumption_id, item_id, batch_id, qty) '
        "VALUES (?, ?, ?, 'pending', 'p2', ?, NULL, ?);",
        [
          id,
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          master.plainItem,
          1000,
        ],
      );

      await insertLine('ul1');
      await expectLater(insertLine('ul2'), throwsA(anything));
    });

    test('doc_number ganda ditolak', () async {
      final master = await seedConsumptionSchemaFixture(context);
      Future<void> insert(String id) => context.database.customStatement(
        'INSERT INTO consumptions (id, created_at, updated_at, sync_status, '
        "doc_number, branch_id, room_id, created_by, status) "
        "VALUES (?, ?, ?, 'pending', 'TMP-CNS-same', ?, ?, ?, 'draft');",
        [
          id,
          '2026-07-30T00:00:00.000Z',
          '2026-07-30T00:00:00.000Z',
          master.branch,
          master.room,
          master.nurse,
        ],
      );

      await insert('n1');
      await expectLater(insert('n2'), throwsA(anything));

      // And soft-deleting the first does **not** free the number (G-A3).
      await context.database.customStatement(
        "UPDATE consumptions SET deleted_at = ? WHERE id = 'n1';",
        ['2026-07-30T01:00:00.000Z'],
      );
      await expectLater(insert('n3'), throwsA(anything));
    });
  });

  group('integritas', () {
    test('foreign_key_check bersih pada database baru', () async {
      final rows = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(rows, isEmpty);
    });

    test('foreign_keys pragma aktif', () async {
      final row = await context.database
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });
  });
}

/// The master rows a raw-SQL schema test needs.
class ConsumptionSchemaFixture {
  const ConsumptionSchemaFixture({
    required this.branch,
    required this.room,
    required this.otherBranchRoom,
    required this.nurse,
    required this.expiryItem,
    required this.plainItem,
    required this.batch,
  });

  final String branch;
  final String room;
  final String otherBranchRoom;
  final String nurse;
  final String expiryItem;
  final String plainItem;
  final String batch;
}

Future<ConsumptionSchemaFixture> seedConsumptionSchemaFixture(
  TestContext context,
) async {
  final branch = await context.master.ensureBranch(
    code: 'CAB-01',
    name: 'Cabang Uji',
  );
  final otherBranch = await context.master.ensureBranch(
    code: 'CAB-02',
    name: 'Cabang Lain',
  );
  final room = await context.master.ensureRoom(
    branchId: branch.id,
    code: 'R1',
    name: 'Ruang Dental 1',
  );
  final otherBranchRoom = await context.master.ensureRoom(
    branchId: otherBranch.id,
    code: 'R1',
    name: 'Ruang Dental 1 Cabang Lain',
  );
  final nurse = await context.master.ensureUser(
    email: 'perawat@test.local',
    fullName: 'Perawat Uji',
    role: UserRole.perawat,
    branchId: branch.id,
  );
  final category = await context.master.ensureCategory('Obat');
  final expiryItem = await context.master.ensureItem(
    sku: 'CNS-0001',
    name: 'Anestesi',
    categoryId: category.id,
    unit: 'ampul',
    minStockRoom: 1,
    minStockBranch: 1,
    hasExpiry: true,
  );
  final plainItem = await context.master.ensureItem(
    sku: 'CNS-0002',
    name: 'Masker',
    categoryId: category.id,
    unit: 'box',
    minStockRoom: 1,
    minStockBranch: 1,
    hasExpiry: false,
  );
  final batch = await context.master.ensureBatch(
    itemId: expiryItem.id,
    batchNo: 'B-1',
    expiryDate: DateTime.utc(2026, 1, 1),
  );
  return ConsumptionSchemaFixture(
    branch: branch.id,
    room: room.id,
    otherBranchRoom: otherBranchRoom.id,
    nurse: nurse.id,
    expiryItem: expiryItem.id,
    plainItem: plainItem.id,
    batch: batch.id,
  );
}
