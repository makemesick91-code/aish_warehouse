import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture rules, enforced against the source itself.
///
/// These are the invariants that no runtime test can catch, because breaking
/// them still compiles and still passes: a widget reaching past the repository
/// into a DAO, a domain model growing a dependency on a generated drift row, or
/// the review loop quietly regaining a per-line transaction. Each of them would
/// be found in code review once and then slowly reintroduced; here they fail
/// the build.
void main() {
  List<File> dartFilesUnder(String path) => Directory(path)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  /// Import targets of one file, ignoring comments.
  List<String> importsOf(File file) {
    final pattern = RegExp(r"^\s*import\s+'([^']+)'", multiLine: true);
    return pattern
        .allMatches(file.readAsStringSync())
        .map((match) => match.group(1)!)
        .toList(growable: false);
  }

  group('lapisan presentation', () {
    test('widget dan halaman tidak mengimpor DAO', () {
      for (final file in dartFilesUnder('lib')) {
        if (!file.path.contains('/presentation/') &&
            !file.path.startsWith('lib/app/')) {
          continue;
        }
        for (final import in importsOf(file)) {
          expect(
            import.contains('db/daos/'),
            isFalse,
            reason:
                '${file.path} mengimpor DAO. UI harus lewat provider → use '
                'case → repository.',
          );
        }
      }
    });

    test('widget dan halaman tidak mengimpor kelas drift generated', () {
      for (final file in dartFilesUnder('lib')) {
        if (!file.path.contains('/presentation/')) continue;
        for (final import in importsOf(file)) {
          expect(
            import.endsWith('.g.dart') || import.endsWith('app_database.dart'),
            isFalse,
            reason: '${file.path} mengimpor kelas drift generated.',
          );
        }
      }
    });
  });

  group('lapisan domain', () {
    test('domain tidak bergantung pada drift', () {
      for (final file in dartFilesUnder('lib')) {
        if (!file.path.contains('/domain/')) continue;
        final source = file.readAsStringSync();

        expect(
          source.contains("package:drift/drift.dart"),
          isFalse,
          reason: '${file.path} mengimpor drift.',
        );
        for (final import in importsOf(file)) {
          expect(
            import.endsWith('.g.dart') ||
                import.endsWith('db/app_database.dart') ||
                import.contains('db/daos/'),
            isFalse,
            reason: '${file.path} bergantung pada lapisan database.',
          );
        }
      }
    });

    test('domain tidak menyentuh BuildContext', () {
      for (final file in dartFilesUnder('lib')) {
        if (!file.path.contains('/domain/')) continue;
        expect(
          RegExp(r'\bBuildContext\b').hasMatch(file.readAsStringSync()),
          isFalse,
          reason:
              '${file.path} menerima BuildContext. Use case tidak boleh tahu '
              'apa pun tentang UI.',
        );
      }
    });

    test('domain opname memakai Quantity, bukan milli-unit mentah', () {
      for (final file in dartFilesUnder('lib/features/opname/domain')) {
        expect(
          file.readAsStringSync().contains('milliUnits'),
          isFalse,
          reason:
              '${file.path} menyentuh milli-unit. Konversi hanya boleh terjadi '
              'di repository (Q-4).',
        );
      }
    });
  });

  group('atomisitas review', () {
    test('review dijalankan dalam satu transaksi', () {
      final source = File(
        'lib/features/opname/domain/use_cases/'
        'review_stock_opname_use_case.dart',
      ).readAsStringSync();

      // Exactly one transaction is opened, and it wraps everything.
      expect(
        'runInTransaction'.allMatches(source).length,
        1,
        reason:
            'Review harus membuka tepat satu transaksi yang mencakup seluruh '
            'posting dan perubahan status.',
      );
      // Posting goes through the transaction-aware batch method, never the
      // per-line one that opens its own transaction.
      expect(source, contains('postOpnameAdjustmentsInTransaction'));
      expect(
        RegExp(r'postOpnameAdjustment\s*\(').hasMatch(source),
        isFalse,
        reason:
            'Memanggil postOpnameAdjustment per baris akan membuka transaksi '
            'terpisah untuk setiap baris.',
      );
    });

    test('posting batch tidak membuka transaksinya sendiri', () {
      final source = File(
        'lib/features/inventory/domain/services/stock_posting_service.dart',
      ).readAsStringSync();

      final start = source.indexOf(
        'Future<List<OpnameAdjustmentResult>> '
        'postOpnameAdjustmentsInTransaction(',
      );
      expect(start, greaterThan(-1));

      final end = source.indexOf(
        'Future<InventoryMovement?> _postOpname',
        start,
      );
      expect(end, greaterThan(start));

      expect(
        source.substring(start, end),
        isNot(contains('runInTransaction')),
        reason:
            'Metode ini harus berjalan di dalam transaksi milik pemanggil, '
            'bukan membuka transaksi baru.',
      );
    });
  });

  group('dokumen final', () {
    test('tidak ada penulis generik untuk header atau baris opname', () {
      final dao = File('lib/core/db/daos/opname_dao.dart').readAsStringSync();

      // Every header write is guarded by a status predicate in the same
      // statement; a bare `update(...).write(...)` would not be.
      expect(
        RegExp(r'update\(stockOpnames\)\)\s*\.write').hasMatch(dao),
        isFalse,
      );
      expect(
        RegExp(r'update\(stockOpnameLines\)\)\s*\.write').hasMatch(dao),
        isFalse,
      );
      expect(dao, isNot(contains('delete(stockOpnames)')));
      expect(dao, isNot(contains('delete(stockOpnameLines)')));
    });

    test('repository tidak menawarkan update dokumen bebas', () {
      final source = File(
        'lib/features/opname/domain/repositories/opname_repository.dart',
      ).readAsStringSync();

      // Only the specific guarded operations exist.
      expect(source, isNot(contains('Future<void> update(StockOpname')));
      expect(source, isNot(contains('delete(')));
      expect(source, contains('updateDraftLine'));
      expect(source, contains('markReviewed'));
    });

    test('tidak ada penulis system_qty setelah pembuatan', () {
      final dao = File('lib/core/db/daos/opname_dao.dart').readAsStringSync();
      final repository = File(
        'lib/features/opname/data/repositories/drift_opname_repository.dart',
      ).readAsStringSync();

      expect(dao, isNot(contains('SET system_qty')));
      expect(
        RegExp(r'systemQty:\s*Value\(').hasMatch(dao),
        isFalse,
        reason: 'DAO tidak boleh menulis system_qty di luar insert awal.',
      );
      // The repository *writes* system_qty in exactly two places — the create
      // snapshot and an added draft line — and both are inserts. Reading it
      // back (`Quantity.fromMilliUnits`) is unlimited; only writes into a
      // companion are counted, which is what `: ….milliUnits` matches.
      final writes = RegExp(
        r'systemQty:[^,\n]*\.milliUnits',
      ).allMatches(repository).length;
      expect(
        writes,
        2,
        reason:
            'system_qty hanya boleh ditulis saat baris dibuat (G-O2); '
            'ditemukan $writes penulisan.',
      );
    });
  });

  test('tidak ada TODO pada aturan inti Stok Opname', () {
    for (final file in [
      ...dartFilesUnder('lib/features/opname'),
      File('lib/core/db/tables/opname_tables.dart'),
      File('lib/core/db/daos/opname_dao.dart'),
    ]) {
      expect(
        RegExp(r'\bTODO\b|\bFIXME\b').hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} masih memuat TODO/FIXME pada jalur aturan inti.',
      );
    }
  });
}
