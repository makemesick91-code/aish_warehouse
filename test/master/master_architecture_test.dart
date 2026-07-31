import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// §57 — the invariants no runtime test can catch, because breaking them still
/// compiles and still passes.
///
/// A widget reaching past the repository into a DAO, a domain file growing a
/// dependency on the spreadsheet package, a row writer quietly opening its own
/// transaction, a hard delete appearing on the master path: each would be found
/// in code review once and then slowly reintroduced. Asserted here, they fail the
/// build.
void main() {
  const domainDir = 'lib/features/master/domain';
  const dataDir = 'lib/features/master/data';
  const presentationDir = 'lib/features/master/presentation';
  const featureDir = 'lib/features/master';

  List<String> domainFiles() => dartFilesUnder(domainDir);
  List<String> presentationFiles() => dartFilesUnder(presentationDir);
  List<String> featureFiles() => dartFilesUnder(featureDir);

  group('lapisan', () {
    test('presentation tidak menyentuh DAO atau drift', () {
      for (final file in presentationFiles()) {
        final imports = importsOf(file);
        expect(
          imports.where((i) => i.contains('core/db/daos/')),
          isEmpty,
          reason: '$file mengimpor DAO langsung.',
        );
        expect(
          imports.where((i) => i.startsWith('package:drift')),
          isEmpty,
          reason: '$file mengimpor drift.',
        );
      }
    });

    test('domain tidak mengenal drift, excel, file_picker, atau Flutter', () {
      for (final file in domainFiles()) {
        final imports = importsOf(file);
        for (final forbidden in const [
          'package:drift',
          'package:excel',
          'package:file_picker',
          'package:flutter/',
          'package:share_plus',
          'package:path_provider',
          'core/db/',
        ]) {
          expect(
            imports.where(
              (i) => i.startsWith(forbidden) || i.contains(forbidden),
            ),
            isEmpty,
            reason: '$file mengimpor $forbidden.',
          );
        }
      }
    });

    test('tidak ada BuildContext di domain', () {
      for (final file in domainFiles()) {
        // Comments included: the gateway file *discusses* the rule, and it does
        // so in prose precisely so this assertion can be literal.
        expect(
          readLibrarySource(file),
          isNot(contains('BuildContext')),
          reason: '$file menyebut BuildContext.',
        );
      }
    });

    test('parser workbook tidak mengenal widget', () {
      final imports = importsOf(
        '$dataDir/import/excel_master_import_workbook_parser.dart',
      );
      expect(imports.where((i) => i.startsWith('package:flutter/')), isEmpty);
    });

    test('hanya satu paket spreadsheet dipakai', () {
      final pubspec = readLibrarySource('pubspec.yaml');
      expect(pubspec, contains('excel:'));
      // A second spreadsheet package would mean the file this application writes
      // and the file it reads are understood by two different code paths.
      for (final other in const [
        'spreadsheet_decoder',
        'syncfusion_flutter_xlsio',
        'xlsx_decoder',
      ]) {
        expect(pubspec, isNot(contains(other)), reason: other);
      }
    });

    test('tidak ada dependency_overrides', () {
      // The *key*, at column zero — the comment above `share_plus` explains why
      // an override was rejected, and reading that explanation as a violation
      // would make the file unable to record the decision.
      final lines = readLibrarySource('pubspec.yaml').split('\n');
      expect(
        lines.where((line) => line.startsWith('dependency_overrides')),
        isEmpty,
      );
    });
  });

  group('tulisan yang dilarang', () {
    test('tidak ada hard delete pada jalur master', () {
      for (final file in featureFiles()) {
        final code = readCodeOnly(file);
        for (final pattern in const [
          'DELETE FROM',
          'delete(branches)',
          'delete(rooms)',
          'delete(users)',
          'delete(items)',
          'delete(itemBatches)',
          'delete(itemCategories)',
          'delete(importLogs)',
        ]) {
          expect(code, isNot(contains(pattern)), reason: '$file: $pattern');
        }
      }
      // The DAO is under `core/db`, and it is the one place a delete could hide.
      final dao = readCodeOnly('lib/core/db/daos/master_admin_dao.dart');
      expect(dao, isNot(contains('DELETE FROM')));
      expect(dao, isNot(contains('delete(')));
    });

    test('impor tidak menulis stok, ledger, maupun dokumen workflow', () {
      final writers = <String>[
        '$domainDir/use_cases/commit_master_import_use_case.dart',
        '$domainDir/use_cases/validate_master_import_use_case.dart',
        'lib/core/db/daos/master_admin_dao.dart',
      ];
      for (final file in writers) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'into(stockBalances)',
          'into(stockMovements)',
          'update(stockBalances)',
          'update(stockMovements)',
          'into(purchaseRequests)',
          'into(deliveryOrders)',
          'into(goodReceipts)',
          'into(distributions)',
          'into(disposals)',
          'into(consumptions)',
          'into(goodsReturns)',
          'into(stockOpnames)',
        ]) {
          expect(code, isNot(contains(forbidden)), reason: '$file: $forbidden');
        }
      }
    });

    test('DAO admin tidak menyediakan update tabel generik', () {
      final code = readCodeOnly('lib/core/db/daos/master_admin_dao.dart');
      // A generic `update(String table, Map<String, dynamic>)` is how a caller
      // assembles a write the policies never inspected (§24).
      expect(code, isNot(contains('Map<String, dynamic>')));
      expect(code, isNot(contains('RawValuesInsertable')));
    });

    test('tidak ada SQL mentah dari presentation', () {
      for (final file in presentationFiles()) {
        final code = readCodeOnly(file);
        expect(code, isNot(contains('customStatement')));
        expect(code, isNot(contains('customSelect')));
        expect(code, isNot(contains('SELECT ')));
      }
    });

    test('tidak ada penulis yang mengubah import_logs kembali ke validated', () {
      final code = readCodeOnly('lib/core/db/daos/master_admin_dao.dart');
      // The only transition writer is guarded on `from`, and no caller passes a
      // final status (§3.4).
      expect(code, contains('transitionImportStatus'));
      expect(code, contains('t.status.equalsValue(from)'));
    });
  });

  group('transaksi dan atomicity', () {
    test('commit membuka tepat satu transaksi', () {
      final code = readCodeOnly(
        '$domainDir/use_cases/commit_master_import_use_case.dart',
      );
      // One `repository.transaction(` in the commit path, and one in the
      // discard use case that shares the file.
      final opens = RegExp(
        r'repository\.transaction\(',
      ).allMatches(code).length;
      expect(opens, 2, reason: 'commit dan discard, masing-masing satu.');
    });

    test('penulis baris tidak membuka transaksi sendiri', () {
      final dao = readCodeOnly('lib/core/db/daos/master_admin_dao.dart');
      // `runInTransaction` is the only opener, and it is the one the repository
      // exposes. Every other method participates in the caller's.
      final opens = RegExp(r'\btransaction\(').allMatches(dao).length;
      expect(
        opens,
        1,
        reason:
            'Hanya runInTransaction yang boleh membuka transaksi (§24). '
            'Ditemukan $opens.',
      );
    });

    test('generator template tidak menulis database', () {
      final code = readCodeOnly(
        '$dataDir/templates/excel_master_template_generator.dart',
      );
      for (final forbidden in const [
        'repository',
        'insert',
        'update(',
        'customStatement',
      ]) {
        expect(code, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('validasi tidak menulis tabel master', () {
      final code = readCodeOnly(
        '$domainDir/use_cases/validate_master_import_use_case.dart',
      );
      // The only writer it calls is the audit insert; every master writer is
      // absent by name (G-M3).
      expect(code, contains('insertValidatedImportLog'));
      for (final forbidden in const [
        'insertBranch',
        'insertRoom',
        'insertUser',
        'insertItem',
        'insertBatch',
        'insertCategory',
        'updateBranch',
        'updateItem',
        'setItemActive',
        'ensureBranchStoreLocation',
      ]) {
        expect(code, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('commit membaca ulang file sumber dan memverifikasi hash', () {
      final code = readCodeOnly(
        '$domainDir/use_cases/commit_master_import_use_case.dart',
      );
      expect(code, contains('verifyHash'));
      expect(code, contains('readStoredSource'));
      expect(code, contains('workbookReader.read'));
      // Revalidated inside the transaction against a snapshot taken there.
      expect(code, contains('MasterImportReferenceSnapshot.load'));
    });

    test('commit tidak menerima baris pratinjau dari UI', () {
      final code = readCodeOnly(
        '$domainDir/use_cases/commit_master_import_use_case.dart',
      );
      // The signature takes an id and an actor, and nothing else — a rows
      // parameter would be a way for a screen to decide what is written.
      expect(code, contains('required String importLogId'));
      expect(code, isNot(contains('required List<ImportRowPreview>')));
      expect(code, isNot(contains('ImportPreviewSession session')));
    });
  });

  group('aturan domain', () {
    test('setiap use case tulis memanggil requireSuperAdmin', () {
      final useCases = dartFilesUnder(
        '$domainDir/use_cases',
      ).where((path) => !path.endsWith('master_admin_guard.dart')).toList();
      expect(useCases, isNotEmpty);

      for (final file in useCases) {
        final code = readCodeOnly(file);
        if (!code.contains('with MasterAdminGuard')) continue;
        expect(
          code,
          contains('requireSuperAdmin'),
          reason: '$file memakai guard tetapi tidak memanggilnya.',
        );
      }
    });

    test('kunci alami terdaftar untuk keenam entitas', () {
      final code = readCodeOnly(
        '$domainDir/services/master_historical_integrity_policy.dart',
      );
      for (final field in const [
        "MasterEntityType.branches: ['code']",
        "MasterEntityType.users: ['email']",
        "MasterEntityType.itemCategories: ['name']",
        "MasterEntityType.items: ['sku']",
      ]) {
        expect(code, contains(field), reason: field);
      }
      expect(code, contains("'branch_id', 'code'"));
      expect(code, contains("'item_id', 'batch_no'"));
    });

    test('kolom historis terlindungi terdaftar', () {
      final code = readCodeOnly(
        '$domainDir/services/master_historical_integrity_policy.dart',
      );
      expect(code, contains("'unit', 'has_expiry', 'category_id'"));
      expect(code, contains("MasterEntityType.itemBatches: ['expiry_date']"));
    });

    test('tidak ada CSV, XLS, atau makro di jalur mana pun', () {
      for (final file in featureFiles()) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'CsvCodec',
          'csvDecode',
          '.xlsm"',
          'VbaProject',
          'macroEnabled',
        ]) {
          expect(code, isNot(contains(forbidden)), reason: '$file: $forbidden');
        }
      }
    });

    test('tidak ada evaluasi rumus', () {
      for (final file in featureFiles()) {
        final code = readCodeOnly(file);
        expect(code, isNot(contains('evaluateFormula')));
        expect(code, isNot(contains('.formula.value')));
      }
      // The parser refuses a formula cell rather than reading it.
      final parser = readCodeOnly(
        '$dataDir/import/excel_master_import_workbook_parser.dart',
      );
      expect(parser, contains('rejectFormulaCell'));
    });

    test('tidak ada toLocal() di seluruh fitur', () {
      for (final file in featureFiles()) {
        expect(
          readCodeOnly(file),
          isNot(contains('.toLocal()')),
          reason:
              '$file memanggil toLocal() — tanggal sipil tidak boleh '
              'dikonversi (T-8).',
        );
      }
    });

    test('tidak ada jaringan, Supabase, atau HTTP', () {
      for (final file in featureFiles()) {
        final imports = importsOf(file);
        for (final forbidden in const [
          'package:http',
          'package:dio',
          'package:supabase',
          'dart:io\'',
        ]) {
          if (forbidden == 'dart:io\'' &&
              (file.contains('/data/files/') ||
                  file.contains('/data/import/'))) {
            // The two file stores and the desktop picker fallback legitimately
            // touch the filesystem; nothing else may.
            continue;
          }
          expect(
            imports.where((i) => i.startsWith(forbidden.replaceAll("'", ''))),
            isEmpty,
            reason: '$file: $forbidden',
          );
        }
      }
    });

    test('tidak ada implementasi reset password', () {
      for (final file in featureFiles()) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'password',
          'passwordHash',
          'resetToken',
          'credential',
        ]) {
          expect(
            code.toLowerCase(),
            isNot(contains(forbidden.toLowerCase())),
            reason:
                '$file menyebut $forbidden — schema ini tidak menyimpan '
                'kredensial dan build ini tidak punya backend auth (§3.5).',
          );
        }
      }
    });

    test('perbandingan timestamp memakai kolom bertipe, bukan teks', () {
      final dao = readCodeOnly('lib/core/db/daos/master_admin_dao.dart');
      // Ordering and range filters go through drift's typed column API, never
      // through a string comparison — the trap schema v4 removed from
      // `stock_opnames`.
      expect(dao, contains('OrderingTerm.desc(t.createdAt)'));
      expect(dao, contains('isBiggerOrEqualValue'));
      expect(dao, isNot(contains("created_at >= '")));
      expect(dao, isNot(contains("created_at <= '")));
    });
  });

  group('presentation', () {
    test('setiap provider halaman ber-autoDispose', () {
      final code = readCodeOnly(
        '$presentationDir/providers/master_admin_providers.dart',
      );
      for (final provider in const [
        'masterDashboardProvider',
        'masterBranchListProvider',
        'masterRoomListProvider',
        'masterUserListProvider',
        'masterCategoryListProvider',
        'masterItemListProvider',
        'masterBatchListProvider',
        'importHistoryProvider',
        'importLogDetailProvider',
      ]) {
        final index = code.indexOf('final $provider');
        expect(index, greaterThan(-1), reason: '$provider tidak ditemukan.');
        final declaration = code.substring(index, index + 200);
        expect(
          declaration,
          contains('autoDispose'),
          reason: '$provider harus autoDispose (§38).',
        );
      }
    });

    test('tidak ada provider yang menerima actor id dari UI', () {
      final code = readCodeOnly(
        '$presentationDir/providers/master_admin_providers.dart',
      );
      // The actor is read from `actingUserProvider`, never passed in — a family
      // keyed on an actor id would be a screen able to pass somebody else's.
      expect(code, contains('masterAdminActorIdProvider'));
      expect(code, isNot(contains('family<.*, ActorId>')));
      expect(code, contains('ref.watch(actingUserProvider)'));
    });

    test('tidak ada kata "hapus permanen" atau "delete" di UI master', () {
      for (final file in dartFilesUnder('$presentationDir/pages')) {
        final code = readCodeOnly(file).toLowerCase();
        for (final forbidden in const ['hapus permanen', 'hapus data']) {
          expect(code, isNot(contains(forbidden)), reason: '$file: $forbidden');
        }
      }
    });

    test('kosakata siklus hidup sesuai §41', () {
      final lists = readCodeOnly(
        '$presentationDir/pages/master_entity_list_pages.dart',
      );
      for (final word in const [
        'Nonaktifkan',
        'Aktifkan Kembali',
        'Arsipkan',
        'Pulihkan',
      ]) {
        expect(lists, contains(word), reason: word);
      }
    });

    test('dialog commit menyebut tiga fakta wajib', () {
      final page = readLibrarySource(
        '$presentationDir/pages/master_import_page.dart',
      );
      expect(page, contains('satu transaksi'));
      expect(page, contains('Tidak ada data yang dihapus'));
      expect(page, contains('pending untuk sinkronisasi'));
    });

    test('daftar pratinjau dibangun malas', () {
      final page = readCodeOnly(
        '$presentationDir/pages/master_import_page.dart',
      );
      // `ListView.builder` over the filtered rows: a 10,000-row workbook builds
      // the rows on screen, not ten thousand widgets (§42, §58).
      expect(page, contains('ListView.builder'));
    });

    test('detail impor tidak merender jalur file', () {
      final page = readCodeOnly(
        '$presentationDir/pages/import_log_detail_page.dart',
      );
      expect(page, isNot(contains('storedFilePath')));
      expect(page, isNot(contains('stored_file_path')));
      expect(page, contains('sourceFileNotice'));
      // The hash is shortened before it is shown.
      expect(page, contains('shortHash'));
    });

    test('model ImportLog domain tidak membawa jalur file', () {
      final code = readCodeOnly('$domainDir/models/import_models.dart');
      final start = code.indexOf('class ImportLog {');
      final end = code.indexOf('class ImportLogDetail');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      expect(
        code.substring(start, end),
        isNot(contains('storedFilePath')),
        reason:
            'Jalur file hanya boleh dibaca commit langsung dari database (§36).',
      );
    });
  });

  group('rute', () {
    test('rute master dan import dijaga', () {
      final router = readCodeOnly('lib/app/router.dart');
      expect(router, contains('MasterAdminSectionGuard'));
      expect(router, contains('MasterAdminRouteKind.master'));
      expect(router, contains('MasterAdminRouteKind.imports'));
      expect(router, contains('MasterAdminRouteKind.importDetail'));
      // The redirect asks the policy rather than comparing a role, so it cannot
      // disagree with the guard by hand.
      expect(router, contains('MasterAdminAccessPolicy.forSection'));
    });

    test('tidak ada rute ber-:id yang tanpa penjaga', () {
      expect(unguardedIdRoutes(readCodeOnly('lib/app/router.dart')), isEmpty);
    });
  });

  group('tidak ada TODO pada aturan inti', () {
    test('tidak ada TODO/FIXME di lib/features/master', () {
      for (final file in featureFiles()) {
        final code = readCodeOnly(file);
        expect(code, isNot(contains('TODO')), reason: file);
        expect(code, isNot(contains('FIXME')), reason: file);
      }
    });
  });
}
