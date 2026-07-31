import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// Source-level invariants for the Distribusi feature (§47).
///
/// Some rules no runtime test can catch, because breaking them still compiles and still
/// passes: a widget reaching past the repository into a DAO, a quantity path that quietly
/// grows a `double`, a `:id` route that ships without a guard, a search that reads the
/// central warehouse instead of the branch store. Those are found in code review once and
/// then slowly reintroduced; asserted here they fail the build instead.
void main() {
  const featureRoot = 'lib/features/distribution';
  const domainRoot = '$featureRoot/domain';
  const dataRoot = '$featureRoot/data';
  const presentationRoot = '$featureRoot/presentation';
  const dao = 'lib/core/db/daos/distribution_dao.dart';
  const tables = 'lib/core/db/tables/distribution_tables.dart';
  const repository = '$domainRoot/repositories/distribution_repository.dart';
  const driftRepository =
      '$dataRoot/repositories/drift_distribution_repository.dart';
  const database = 'lib/core/db/app_database.dart';
  const guard = 'lib/app/guards/distribution_route_guard.dart';
  const router = 'lib/app/router.dart';
  const routes = 'lib/app/routes.dart';
  const providers = '$presentationRoot/providers/distribution_providers.dart';
  const postUseCase = '$domainRoot/use_cases/post_distribution_use_case.dart';
  const fefoPolicy = '$domainRoot/services/distribution_fefo_policy.dart';

  group('lapisan', () {
    test('presentasi tidak mengimpor DAO atau Drift', () {
      for (final file in dartFilesUnder(presentationRoot)) {
        for (final import in importsOf(file)) {
          expect(
            import.contains('core/db/daos/'),
            isFalse,
            reason: '$file mencapai DAO langsung ($import).',
          );
          expect(
            import.startsWith('package:drift'),
            isFalse,
            reason: '$file mengimpor Drift ($import).',
          );
        }
      }
    });

    test('domain tidak mengimpor Drift, Flutter atau DAO', () {
      for (final file in dartFilesUnder(domainRoot)) {
        for (final import in importsOf(file)) {
          expect(
            import.startsWith('package:drift'),
            isFalse,
            reason: '$file mengimpor Drift ($import).',
          );
          expect(
            import.startsWith('package:flutter/'),
            isFalse,
            reason: '$file mengimpor Flutter ($import).',
          );
          expect(
            import.contains('core/db/'),
            isFalse,
            reason: '$file mencapai lapisan database ($import).',
          );
        }
      }
    });

    test('hanya repository Drift yang menyentuh milli-unit', () {
      // Q-4: the scale is a database-boundary fact, and a caller that reached for it
      // would be doing arithmetic the `Quantity` type exists to own.
      for (final file in [
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder(presentationRoot),
      ]) {
        expect(
          readCodeOnly(file).contains('milliUnits'),
          isFalse,
          reason: '$file menyentuh milliUnits.',
        );
      }
      expect(readCodeOnly(driftRepository), contains('milliUnits'));
    });

    test('presentasi tidak memakai repository yang tidak berbatas cabang', () {
      // `getDetail` is the unscoped read, for use cases only: by the time a widget could
      // apply an authorization check, the foreign document has already reached the UI.
      for (final file in dartFilesUnder(presentationRoot)) {
        expect(
          readCodeOnly(file).contains('.getDetail('),
          isFalse,
          reason: '$file memakai pembacaan tanpa batas cabang.',
        );
      }
    });

    test('layar cabang memakai provider berbatas cabang', () {
      for (final file in dartFilesUnder('$presentationRoot/pages')) {
        final code = readCodeOnly(file);
        if (!code.contains('branchDistributionDetailProvider') &&
            !code.contains('branchDistributionListProvider')) {
          continue;
        }
        // A screen must never build its own unscoped stream beside the scoped one.
        expect(code.contains('watchListForBranch'), isFalse, reason: file);
        expect(code.contains('watchForBranch'), isFalse, reason: file);
      }
    });
  });

  group('kuantitas', () {
    test('tidak ada double pada jalur kuantitas', () {
      for (final file in [
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder(dataRoot),
        dao,
        tables,
      ]) {
        final code = readCodeOnly(file);
        for (final forbidden in ['double ', 'toDouble()', '.toDouble']) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file memakai $forbidden pada jalur kuantitas.',
          );
        }
      }
    });

    test('kolom qty adalah INTEGER, bukan REAL', () {
      final code = readCodeOnly(tables);
      expect(code, contains('IntColumn get qty => integer()'));
      expect(code.contains('real()'), isFalse);
    });

    test('presentasi tidak membagi kuantitas menjadi pecahan', () {
      // A ratio computed as a `double` somewhere in the middle is how the rounding drift
      // `Quantity` exists to prevent gets back in.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        expect(code.contains('.milliUnits /'), isFalse, reason: file);
        expect(code.contains('toDouble'), isFalse, reason: file);
      }
    });
  });

  group('ledger', () {
    test('hanya StockPostingService menulis pergerakan', () {
      for (final file in [
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder(dataRoot),
        ...dartFilesUnder(presentationRoot),
        dao,
      ]) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'appendMovement',
          'setBalanceQty',
          'insertMovement',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menulis ledger atau saldo langsung.',
          );
        }
      }
    });

    test('posting memakai method tanpa transaksi sendiri', () {
      final code = readCodeOnly(postUseCase);
      // G-T4: one transaction for the whole document. `postTransfer` opens its own per
      // call, so a loop over it could commit one room and roll back the next.
      expect(code, contains('postDistributionInTransaction'));
      expect(code.contains('postTransfer'), isFalse);
      expect(code, contains('runInTransaction'));
    });

    test('ref doc type distribusi adalah DIST', () {
      expect(RefDocType.distribution, 'DIST');
      // Written through the constant rather than as a literal, so the ledger and the
      // reports cannot disagree about the string.
      final posting = readCodeOnly(
        'lib/features/inventory/domain/services/stock_posting_service.dart',
      );
      expect(posting, contains('RefDocType.distribution'));
    });

    test('jenis pergerakan distribusi memindahkan antar lokasi', () {
      expect(StockMovementType.distribution.dbValue, 'distribution');
      expect(StockMovementType.distribution.isLocationToLocation, isTrue);
    });
  });

  group('penulisan terjaga', () {
    test('tidak ada pembaruan status tanpa batas', () {
      final code = readCodeOnly(dao);
      expect(code.contains('setStatus'), isFalse);
      expect(code.contains('updateStatus'), isFalse);
      // Every guarded write names the status it expects to move *from*, inside the
      // statement.
      expect(code, contains("status = 'draft'"));
    });

    test('tidak ada un-post di mana pun pada fitur', () {
      for (final file in [...dartFilesUnder(featureRoot), dao, tables, guard]) {
        final code = readCodeOnly(file);
        for (final forbidden in ['unpost', 'unPost', 'reopen', 'markDraft']) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menyediakan $forbidden.',
          );
        }
      }
    });

    test('DAO tidak menyentuh room_id atau item_id pada UPDATE', () {
      // Moving a position to another room or another item is a *different* position, and
      // changing one in place would slip past the room/branch validation G-T1 depends on.
      final code = readCodeOnly(dao);
      final updates = RegExp(
        r'UPDATE distribution_lines[\s\S]*?;',
      ).allMatches(code).map((match) => match.group(0)!);
      expect(updates, isNotEmpty);
      for (final statement in updates) {
        expect(
          statement.contains('SET room_id'),
          isFalse,
          reason: 'UPDATE menyentuh room_id.',
        );
        expect(
          statement.contains('SET item_id'),
          isFalse,
          reason: 'UPDATE menyentuh item_id.',
        );
        expect(
          statement.contains('distribution_id ='),
          isTrue,
          reason: 'UPDATE tidak dipagari ke dokumennya.',
        );
      }
    });

    test('tidak ada hard delete pada baris atau header', () {
      final code = readCodeOnly(dao);
      expect(code.contains('DELETE FROM'), isFalse);
      expect(code.contains('delete(distributions)'), isFalse);
      expect(code.contains('delete(distributionLines)'), isFalse);
      // Removal is a soft delete (G-A5).
      expect(code, contains('SET deleted_at'));
    });
  });

  group('lokasi', () {
    test('tidak ada kolom lokasi pada tabel baris', () {
      final code = readCodeOnly(tables);
      for (final forbidden in [
        'fromLocationId',
        'toLocationId',
        'sourceLocationId',
        'destinationLocationId',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'distribution_lines menyimpan $forbidden.',
        );
      }
    });

    test('presentasi tidak menerima lokasi apa pun', () {
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'fromLocationId',
          'toLocationId',
          'sourceLocationId',
          'destinationLocationId',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menyebut $forbidden.',
          );
        }
      }
    });

    test('DAO tidak menerima lokasi arbitrer dari pemanggil', () {
      // The only location parameter the DAO takes is the branch store the *reads* are
      // scoped to, and the caller resolves it by type through `MasterDataRepository`.
      final code = readCodeOnly(dao);
      expect(code, contains('required String locationId'));
      expect(code.contains('required String toLocationId'), isFalse);
      expect(code.contains('required String fromLocationId'), isFalse);
    });
  });

  group('pencarian stok', () {
    test('pencarian membaca saldo positif saja', () {
      final code = readCodeOnly(dao);
      expect(code, contains('qtyOnHand.isBiggerThanValue(0)'));
    });

    test('sumber FEFO adalah gudang cabang, bukan warehouse', () {
      // The one thing that makes this feature's FEFO different from the shipment's: a
      // distribution moves goods that are already at the branch.
      for (final file in dartFilesUnder(domainRoot)) {
        final code = readCodeOnly(file);
        expect(
          code.contains('warehouseLocation'),
          isFalse,
          reason: '$file membaca lokasi warehouse pusat.',
        );
        expect(
          code.contains('activeWarehouseLocations'),
          isFalse,
          reason: '$file membaca lokasi warehouse pusat.',
        );
      }
      expect(
        readCodeOnly(
          '$domainRoot/services/distribution_branch_stock_reader.dart',
        ),
        contains('branchStoreLocationId'),
      );
    });

    test('kebijakan FEFO menilai per item lintas ruangan', () {
      // §16. The signature is the invariant: `violations` takes one item's whole
      // selection, so no caller can accidentally hand it one room's share.
      final code = readCodeOnly(fefoPolicy);
      expect(code, contains('required String itemId'));
      expect(code, contains('required List<DistributionAllocation> selection'));
      expect(code, contains('remainingCandidates'));
    });
  });

  group('waktu', () {
    test('tidak ada perbandingan timestamp leksikal di SQL', () {
      for (final file in [dao, tables]) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'postedAt.isBiggerOrEqualValue',
          'postedAt.isSmallerOrEqualValue',
          'postedAt.isBiggerThanValue',
          'postedAt.isSmallerThanValue',
          'createdAt.isBiggerOrEqualValue',
          'posted_at >=',
          'posted_at >',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file membandingkan timestamp secara leksikal.',
          );
        }
      }
    });

    test('tidak ada toLocal pada jalur Distribusi', () {
      // T-4/T-6: `toLocal()` follows the device timezone. Operational time is GMT+8 and
      // is applied through `AppTimeZone` alone.
      for (final file in [...dartFilesUnder(featureRoot), dao, guard]) {
        expect(
          readCodeOnly(file).contains('toLocal()'),
          isFalse,
          reason: '$file memakai toLocal().',
        );
      }
    });

    test('urutan timestamp diputuskan oleh policy bersama', () {
      expect(
        readCodeOnly(postUseCase),
        contains('DocumentTimestampPolicy.requireOrdered'),
      );
    });

    test('waktu operasional selalu melalui AppTimeZone', () {
      // Never by adding eight hours by hand, which is how the two would come to disagree.
      for (final file in [...dartFilesUnder(featureRoot)]) {
        final code = readCodeOnly(file);
        if (!code.contains('Duration(hours: 8')) continue;
        fail('$file menghitung offset GMT+8 secara manual.');
      }
    });
  });

  group('rute', () {
    test('setiap rute :id dibungkus guard', () {
      final code = readCodeOnly(router);
      expect(code, contains('AppRoutes.distributions,'));
      // The distribution section runs from its own top-level route to the end of the
      // route list, which is where the router closes.
      final section = code.substring(code.indexOf('AppRoutes.distributions,'));

      // Both parameterized routes exist, and both go through the guard.
      expect(section, contains('AppRoutes.distributionDetail'));
      expect(section, contains('AppRoutes.distributionEdit'));
      expect(section, contains('DistributionRouteGuard'));
      // The editor uses its own kind, so the draft-only precondition is a route fact.
      expect(section, contains('DistributionRouteKind.branchDraft'));
      expect(section, contains('DistributionRouteKind.branchDocument'));
    });

    test('rute literal new dideklarasikan sebelum pola :id', () {
      final code = readCodeOnly(routes);
      final literal = code.indexOf('distributionNew');
      final pattern = code.indexOf('distributionDetail =');
      expect(literal, greaterThan(-1));
      expect(pattern, greaterThan(-1));
      expect(
        literal,
        lessThan(pattern),
        reason: 'Segmen literal harus menang atas pola :id.',
      );
    });

    test('guard memakai actingUserProvider, bukan sesi mentah', () {
      final code = readCodeOnly(guard);
      // O-8: the stored row decides, not what the session claims about itself.
      expect(code, contains('actingUserProvider'));
      expect(code, contains('findAccessScope'));
      // And it must not load the document to decide whether it may be shown.
      expect(code.contains('getForBranch'), isFalse);
      expect(code.contains('watchForBranch'), isFalse);
    });

    test('guard yang gagal menutup, bukan membuka', () {
      final code = readCodeOnly(guard);
      expect(code, contains('AccessDeniedPage()'));
      // The `error` branch of every `when` must refuse.
      expect(code, contains('error: (_, _) => const AccessDeniedPage()'));
    });
  });

  group('provider', () {
    test('provider berlingkup layar memakai autoDispose', () {
      final code = readCodeOnly(providers);
      for (final name in [
        'branchDistributionListProvider',
        'branchDistributionDetailProvider',
        'distributionStockSearchProvider',
        'distributionStockItemProvider',
        'branchDistributionRoomsProvider',
        'branchStoreLocationProvider',
      ]) {
        final index = code.indexOf(name);
        expect(index, greaterThan(-1), reason: '$name tidak ada.');
        // A document opened under one session must not still be cached under the next.
        final declaration = code.substring(index, index + 200);
        expect(
          declaration.contains('autoDispose'),
          isTrue,
          reason: '$name bukan autoDispose.',
        );
      }
    });

    test('setiap provider daftar dan detail memeriksa peran dan cabang', () {
      final code = readCodeOnly(providers);
      // The route guard is never the only defence (§25).
      expect(
        code.split('DistributionAccessPolicy.canWrite').length - 1,
        greaterThanOrEqualTo(4),
      );
      expect(code, contains('actingBranchIdProvider'));
      expect(code, contains('actingRoleProvider'));
    });

    test('provider tidak menyimpan branchId pada kunci family', () {
      // Two entries for one document that look independent while both being resolvable is
      // how a stale cache entry survives a session change.
      final code = readCodeOnly(providers);
      expect(code.contains('family<DistributionDetail?, ({'), isFalse);
      expect(code, contains('family<DistributionDetail?, String>'));
    });
  });

  group('schema', () {
    test('migrasi v8 memakai SQL index yang dibekukan', () {
      // Comment-stripped, because the migration file *explains* at length why the list is
      // not derived from `allSchemaEntities`.
      final code = readCodeOnly(database);

      expect(code, contains('_v8DistributionIndexes'));
      expect(code, contains('if (from < 8)'));
      expect(code, contains('int get schemaVersion => 13;'));
      expect(
        code.contains('allSchemaEntities'),
        isFalse,
        reason:
            'Langkah migrasi harus tetap melakukan apa yang ia lakukan saat '
            'dirilis.',
      );
    });

    test('blok migrasi v8 tidak menyentuh milik versi sebelumnya', () {
      final code = readCodeOnly(database);
      final start = code.indexOf('if (from < 8)');
      final end = code.indexOf('    },', start);
      final block = code.substring(start, end);

      for (final untouched in [
        'stockOpnames',
        'stock_balances',
        'stock_movements',
        'purchaseRequests',
        'deliveryOrders',
        'goodReceipts',
        'alterTable',
        'UPDATE ',
      ]) {
        expect(
          block.contains(untouched),
          isFalse,
          reason: 'Blok migrasi v8 menyentuh $untouched.',
        );
      }
      expect(block, contains('createTable(distributions)'));
      expect(block, contains('createTable(distributionLines)'));
    });

    test('generated manager tetap dinonaktifkan', () {
      // The manager API is a second, unguarded write path into every table.
      final config = readLibrarySource('build.yaml');
      expect(config, contains('generate_manager: false'));
    });
  });

  group('kebersihan', () {
    test('tidak ada backend, HTTP atau ekspor pada jalur Distribusi', () {
      for (final file in [...dartFilesUnder(featureRoot), dao, guard]) {
        for (final import in importsOf(file)) {
          expect(
            import.startsWith('package:http') ||
                import.startsWith('package:supabase') ||
                import.startsWith('package:dio') ||
                import.startsWith('package:excel') ||
                import.startsWith('package:pdf') ||
                import.startsWith('package:printing'),
            isFalse,
            reason: '$file mengimpor jaringan atau ekspor ($import).',
          );
        }
      }
    });

    test('tidak ada TODO pada aturan inti Distribusi', () {
      for (final file in [
        ...dartFilesUnder('$domainRoot/services'),
        ...dartFilesUnder('$domainRoot/use_cases'),
        dao,
        tables,
      ]) {
        final source = readLibrarySource(file);
        expect(
          source.contains('TODO') || source.contains('FIXME'),
          isFalse,
          reason: '$file menyisakan TODO pada aturan inti.',
        );
      }
    });

    test('Distribusi tidak bergantung pada fitur setelahnya', () {
      // Disposal, returns and the reporting module are later milestones. A dependency on
      // one now would be a promise this milestone cannot keep.
      for (final file in dartFilesUnder(featureRoot)) {
        for (final import in importsOf(file)) {
          expect(
            import.contains('features/reports/'),
            isFalse,
            reason: '$file mengimpor modul laporan ($import).',
          );
        }
      }
    });

    test('tabel laporan tetap terpisah dari tabel Distribusi', () {
      // This guard was written for Milestone 6, when it read *"no reporting table
      // on this milestone"* — a scope-creep check, and the right one at the time.
      // Milestone 10 added `export_logs` deliberately (G-L2), so the assertion is
      // narrowed rather than deleted: what still must not happen is the audit table
      // growing into the Distribusi tables, or a distribution column appearing on
      // it. `distribution_tables.dart` names neither, and `reporting_tables.dart`
      // names no distribution.
      for (final file in dartFilesUnder('lib/core/db/tables')) {
        final source = readLibrarySource(file);
        expect(source.contains('class Reports'), isFalse, reason: file);
        if (file.endsWith('distribution_tables.dart')) {
          expect(source.contains('class ExportLogs'), isFalse, reason: file);
          expect(source.contains('export_logs'), isFalse, reason: file);
        }
        if (file.endsWith('reporting_tables.dart')) {
          expect(source.contains('class Distributions'), isFalse, reason: file);
          expect(source.contains('distribution_id'), isFalse, reason: file);
        }
      }
    });

    test('kontrak repository menyebut alasannya, bukan hanya aturannya', () {
      // Not a style check: the absences in this contract *are* the guardrails, and a
      // future change that adds a writer has to argue with the paragraph explaining why
      // there is none.
      final source = readLibrarySource(repository);
      expect(source, contains('G-S2'));
      expect(source, contains('G-T1'));
      expect(source, contains('G-T4'));
    });
  });
}
