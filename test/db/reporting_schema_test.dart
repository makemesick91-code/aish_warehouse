import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';
import '../reports/reporting_fixture.dart';

/// Schema v12 as a fresh database has it: `export_logs`, its constraints and its
/// indexes (§12, §54).
void main() {
  late TestContext context;
  late ReportingFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildReportingFixture(
      context,
      postedAtUtc: DateTime.utc(2026, 7, 20, 2),
    );
  });

  tearDown(() => context.dispose());

  /// Inserts one audit row directly, so a CHECK can be exercised without going
  /// through the use case that would refuse it earlier.
  Future<void> insertLog({
    String id = 'log-1',
    String reportType = 'stok_lokasi',
    String format = 'xlsx',
    String scopeType = 'warehouse',
    String? locationId = 'USE_WAREHOUSE',
    String? categoryId,
    String? branchId,
    String? itemId,
    String periodStart = '2026-07-30T00:00:00.000Z',
    String periodEnd = '2026-07-30T00:00:00.000Z',
    String? exportedBy,
    String fileName = 'stok_lokasi_WH_20260730.xlsx',
    String syncSummary = 'Status sync: 1 tersinkron · 0 pending · 0 konflik',
    int rowCount = 3,
  }) {
    return context.database.customStatement(
      'INSERT INTO export_logs (id, created_at, updated_at, sync_status, '
      'report_type, format, scope_type, location_id, category_id, branch_id, '
      'item_id, period_start, period_end, exported_by, file_name, '
      'data_cutoff_at, sync_summary, row_count) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        id,
        '2026-07-30T14:00:00.000Z',
        '2026-07-30T14:00:00.000Z',
        'pending',
        reportType,
        format,
        scopeType,
        locationId == 'USE_WAREHOUSE' ? fixture.warehouse.id : locationId,
        categoryId,
        branchId,
        itemId,
        periodStart,
        periodEnd,
        exportedBy ?? fixture.warehouseUser.id,
        fileName,
        '2026-07-30T14:00:00.000Z',
        syncSummary,
        rowCount,
      ],
    );
  }

  Future<Set<String>> objectNames(String type) async {
    final rows = await context.database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = '$type' "
          "AND name NOT LIKE 'sqlite_%';",
        )
        .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  group('bentuk tabel', () {
    test('schema version adalah 12', () {
      expect(context.database.schemaVersion, 15);
    });

    test('export_logs ada', () async {
      expect(await objectNames('table'), contains('export_logs'));
    });

    test('kolom umum §2 hadir', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_info(export_logs);')
          .get();
      final columns = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        columns,
        containsAll(<String>[
          'id',
          'created_at',
          'updated_at',
          'deleted_at',
          'sync_status',
        ]),
      );
    });

    test('kolom spesifikasi dan ekstensi hadir', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_info(export_logs);')
          .get();
      final columns = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        columns,
        containsAll(<String>[
          'report_type',
          'format',
          'scope_type',
          'location_id',
          'category_id',
          'branch_id',
          'period_start',
          'period_end',
          'exported_by',
          'file_name',
          // §12's four extension columns.
          'item_id',
          'data_cutoff_at',
          'sync_summary',
          'row_count',
        ]),
      );
    });

    test('row_count bertipe INTEGER', () async {
      final rows = await context.database
          .customSelect('PRAGMA table_info(export_logs);')
          .get();
      final row = rows.firstWhere(
        (entry) => entry.read<String>('name') == 'row_count',
      );
      expect(row.read<String>('type').toUpperCase(), 'INTEGER');
    });

    test('seluruh index v12 dibuat', () async {
      expect(
        await objectNames('index'),
        containsAll(<String>[
          'idx_export_logs_actor',
          'idx_export_logs_type',
          'idx_export_logs_format',
          'idx_export_logs_scope',
          'idx_export_logs_branch',
          'idx_export_logs_location',
          'idx_export_logs_category',
          'idx_export_logs_item',
          'idx_export_logs_created_at',
        ]),
      );
    });

    test('tidak ada index unik pada export_logs', () async {
      // An export log is an *event*: the same person exporting the same report
      // twice produced two files and must produce two rows. A unique index on any
      // combination of these columns would collapse the second out of the audit.
      final rows = await context.database
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'export_logs' AND sql IS NOT NULL;",
          )
          .get();

      for (final row in rows) {
        expect(
          row.read<String>('sql').toUpperCase(),
          isNot(contains('UNIQUE')),
        );
      }
    });

    test('foreign key ditegakkan', () async {
      await expectLater(
        insertLog(exportedBy: 'pengguna-tidak-ada'),
        throwsA(isA<Exception>()),
      );
    });

    test('PRAGMA foreign_key_check kosong', () async {
      await insertLog();
      final violations = await context.database
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });
  });

  group('CHECK enum', () {
    test('report_type asing ditolak', () async {
      await expectLater(
        insertLog(reportType: 'laporan_ajaib'),
        throwsA(isA<Exception>()),
      );
    });

    test('format asing ditolak', () async {
      // No CSV — §10.
      await expectLater(insertLog(format: 'csv'), throwsA(isA<Exception>()));
    });

    test('scope_type asing ditolak', () async {
      await expectLater(
        insertLog(scopeType: 'semua_ruangan'),
        throwsA(isA<Exception>()),
      );
    });

    test('setiap nilai enum yang dikenal diterima', () async {
      for (final type in const [
        'stok_lokasi',
        'kartu_stok',
        'rekap_opname',
        'rekap_pr',
        'rekap_do',
        'rekap_gr',
        'rekap_distribusi',
        'rekap_pemakaian',
        'rekap_pemusnahan',
        'rekap_retur',
        'kadaluarsa',
      ]) {
        await insertLog(id: 'log-$type', reportType: type);
      }
      expect(await context.exportLogCount(), 11);
    });
  });

  group('CHECK cakupan (§12)', () {
    test('warehouse: lokasi wajib, cabang wajib kosong', () async {
      await expectLater(
        insertLog(scopeType: 'warehouse', locationId: null),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insertLog(scopeType: 'warehouse', branchId: fixture.branch.id),
        throwsA(isA<Exception>()),
      );
    });

    test('branch_store dan room: lokasi dan cabang wajib', () async {
      for (final scope in const ['branch_store', 'room']) {
        await expectLater(
          insertLog(scopeType: scope, locationId: null, branchId: 'x'),
          throwsA(isA<Exception>()),
          reason: scope,
        );
        await expectLater(
          insertLog(scopeType: scope),
          throwsA(isA<Exception>()),
          reason: scope,
        );
      }
    });

    test('branch_all: cabang wajib, lokasi wajib kosong', () async {
      // The shape §11 exists to make impossible: `branch_all` with a NULL branch
      // would leave an audit row unable to say whether one branch or every branch
      // was exported.
      await expectLater(
        insertLog(scopeType: 'branch_all', locationId: null, branchId: null),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        insertLog(scopeType: 'branch_all', branchId: fixture.branch.id),
        throwsA(isA<Exception>()),
      );
      await insertLog(
        scopeType: 'branch_all',
        locationId: null,
        branchId: fixture.branch.id,
      );
      expect(await context.exportLogCount(), 1);
    });

    test('cross_branch dan all_locations: keduanya wajib kosong', () async {
      for (final scope in const ['cross_branch', 'all_locations']) {
        await expectLater(
          insertLog(scopeType: scope),
          throwsA(isA<Exception>()),
          reason: scope,
        );
        await expectLater(
          insertLog(
            scopeType: scope,
            locationId: null,
            branchId: fixture.branch.id,
          ),
          throwsA(isA<Exception>()),
          reason: scope,
        );
      }
      await insertLog(scopeType: 'cross_branch', locationId: null);
      expect(await context.exportLogCount(), 1);
    });
  });

  group('CHECK teks dan angka', () {
    test('file_name kosong atau spasi ditolak', () async {
      await expectLater(insertLog(fileName: ''), throwsA(isA<Exception>()));
      await expectLater(insertLog(fileName: '   '), throwsA(isA<Exception>()));
    });

    test('sync_summary kosong atau spasi ditolak', () async {
      await expectLater(insertLog(syncSummary: ''), throwsA(isA<Exception>()));
      await expectLater(
        insertLog(syncSummary: '  '),
        throwsA(isA<Exception>()),
      );
    });

    test('row_count negatif ditolak', () async {
      await expectLater(insertLog(rowCount: -1), throwsA(isA<Exception>()));
    });

    test('row_count nol diterima', () async {
      // §52: an export that found nothing is still an export.
      await insertLog(rowCount: 0);
      expect(await context.exportLogCount(), 1);
    });
  });

  group('append-only (§42)', () {
    test('DAO dan repository tidak menyediakan update atau delete', () {
      // Enforced structurally, the way G-A1 is for the ledger: no mutating API may
      // exist, so it cannot be reintroduced by a screen that "just needs to tidy
      // up".
      // Comments are stripped first: these files *explain* why the forbidden
      // writers do not exist, and a guard that read the explanation as a violation
      // would forbid documenting the rule.
      final sources = {
        'reporting_dao.dart': readCodeOnly(
          'lib/core/db/daos/reporting_dao.dart',
        ),
        'reporting_repository.dart': readCodeOnly(
          'lib/features/reports/domain/repositories/reporting_repository.dart',
        ),
        'drift_reporting_repository.dart': readCodeOnly(
          'lib/features/reports/data/repositories/'
          'drift_reporting_repository.dart',
        ),
      };

      for (final entry in sources.entries) {
        expect(
          entry.value,
          isNot(contains('update(exportLogs)')),
          reason: '${entry.key} must not update export logs',
        );
        expect(
          entry.value,
          isNot(contains('delete(exportLogs)')),
          reason: '${entry.key} must not delete export logs',
        );
        expect(
          entry.value,
          isNot(contains('updateExportLog')),
          reason: entry.key,
        );
        expect(
          entry.value,
          isNot(contains('deleteExportLog')),
          reason: entry.key,
        );
      }
      expect(sources['reporting_dao.dart'], contains('insertExportLog'));
    });

    test('sync_status baris baru adalah pending', () async {
      await insertLog();
      final row = await context.database
          .customSelect(
            'SELECT sync_status FROM export_logs WHERE id = ?;',
            variables: [Variable<String>('log-1')],
          )
          .getSingle();
      expect(row.read<String>('sync_status'), 'pending');
    });
  });

  group('timestamp tidak dibandingkan secara leksikal', () {
    test('DAO tidak mengurutkan created_at di SQL', () {
      // §34 rule 2: `created_at` is ISO-8601 TEXT, so SQLite would compare it
      // character by character — the trap schema v4 removed from `stock_opnames`.
      final code = readCodeOnly('lib/core/db/daos/reporting_dao.dart');

      expect(code, isNot(contains('ORDER BY created_at')));
      expect(
        code,
        isNot(contains('orderBy([(t) => OrderingTerm.desc(t.createdAt')),
      );
      expect(code, isNot(contains("created_at >=")));
      expect(code, isNot(contains("created_at <")));
      expect(code, isNot(contains("created_at BETWEEN")));
    });

    test('tabel export_logs tidak memiliki CHECK urutan tanggal', () async {
      final row = await context.database
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'table' "
            "AND name = 'export_logs';",
          )
          .getSingle();
      final sql = row.read<String>('sql');

      expect(sql.contains('period_start <='), isFalse);
      expect(sql.contains('period_end >='), isFalse);
      expect(sql.contains('data_cutoff_at >='), isFalse);
    });
  });

  group('tidak membaca stock_balances (G-L4)', () {
    test('sumber reporting tidak menyebut tabel saldo', () {
      // The rule the whole module is built around, asserted at the source so it
      // survives the next person who "just needs a quick total".
      final files = <String>[
        'lib/core/db/daos/reporting_dao.dart',
        'lib/features/reports/data/repositories/drift_reporting_repository.dart',
        'lib/features/reports/domain/services/ledger_balance_engine.dart',
      ];

      for (final path in files) {
        final code = readCodeOnly(path);
        expect(code, isNot(contains('stock_balances')), reason: path);
        expect(code, isNot(contains('qty_on_hand')), reason: path);
        expect(code, isNot(contains('StockBalances')), reason: path);
      }
    });
  });
}
