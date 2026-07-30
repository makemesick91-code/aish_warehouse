import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// Source-level invariants for the Pemusnahan feature (§47).
///
/// Some rules no runtime test can catch, because breaking them still compiles and
/// still passes: a widget reaching past the repository into a DAO, a quantity path
/// that quietly grows a `double`, a `:id` route that ships without a guard, a
/// candidate query that stops filtering by expiry. Those are found in code review
/// once and then slowly reintroduced; asserted here they fail the build instead.
///
/// Several of them are specific to *this* document and have no counterpart in the
/// earlier milestones: there must be no destination anywhere, no un-post, no approval
/// vocabulary, and no path that disposes of anything but an expired batch.
void main() {
  const featureRoot = 'lib/features/disposal';
  const domainRoot = '$featureRoot/domain';
  const dataRoot = '$featureRoot/data';
  const presentationRoot = '$featureRoot/presentation';
  const dao = 'lib/core/db/daos/disposal_dao.dart';
  const tables = 'lib/core/db/tables/disposal_tables.dart';
  const repository = '$domainRoot/repositories/disposal_repository.dart';
  const driftRepository =
      '$dataRoot/repositories/drift_disposal_repository.dart';
  const database = 'lib/core/db/app_database.dart';
  const guard = 'lib/app/guards/disposal_route_guard.dart';
  const router = 'lib/app/router.dart';
  const routes = 'lib/app/routes.dart';
  const providers = '$presentationRoot/providers/disposal_providers.dart';
  const postUseCase = '$domainRoot/use_cases/post_disposal_use_case.dart';
  const expiryPolicy = '$domainRoot/services/disposal_expiry_policy.dart';
  const postingService =
      'lib/features/inventory/domain/services/stock_posting_service.dart';

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

    test('domain tidak mengimpor Drift, Flutter atau lapisan database', () {
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
          reason: '$file menyentuh milli-unit di luar batas repository.',
        );
      }
      expect(readCodeOnly(driftRepository), contains('milliUnits'));
    });

    test('tidak ada double pada jalur kuantitas', () {
      for (final file in [
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder(dataRoot),
        ...dartFilesUnder(presentationRoot),
        dao,
        tables,
      ]) {
        final code = readCodeOnly(file);
        for (final needle in const [
          'double ',
          '.toDouble()',
          'as double',
          'double.parse',
        ]) {
          expect(
            code.contains(needle),
            isFalse,
            reason: '$file memakai `$needle` pada jalur kuantitas.',
          );
        }
      }
    });

    test('kolom qty bertipe INTEGER, tidak pernah REAL', () {
      final code = readCodeOnly(tables);
      expect(code, contains('IntColumn get qty'));
      expect(code.contains('RealColumn'), isFalse);
    });

    test('presentasi hanya membaca dokumen lewat pembacaan yang di-scope', () {
      // `getDetail` is the single unscoped read and belongs to the use cases: by the
      // time a widget could apply an access check, the foreign document has already
      // been handed to the UI layer.
      for (final file in dartFilesUnder(presentationRoot)) {
        expect(
          readCodeOnly(file).contains('.getDetail('),
          isFalse,
          reason: '$file memakai pembacaan tanpa scope.',
        );
      }
    });
  });

  group('ledger', () {
    test('stok hanya berubah lewat StockPostingService', () {
      for (final file in [
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder(dataRoot),
        ...dartFilesUnder(presentationRoot),
      ]) {
        final code = readCodeOnly(file);
        expect(
          code.contains('setBalanceQty'),
          isFalse,
          reason: '$file menulis saldo langsung.',
        );
        expect(
          code.contains('appendMovement'),
          isFalse,
          reason: '$file menulis ledger langsung.',
        );
      }
    });

    test('DAO tidak menyentuh saldo maupun movement', () {
      final code = readCodeOnly(dao);
      for (final needle in const [
        'stock_balances SET',
        'INSERT INTO stock_balances',
        'INSERT INTO stock_movements',
        'stock_movements SET',
      ]) {
        expect(
          code.contains(needle),
          isFalse,
          reason: 'DisposalDao menulis $needle.',
        );
      }
    });

    test('posting memakai metode transaction-aware, bukan postDisposal', () {
      // `postDisposal` opens its own transaction; a loop over it would commit per
      // line, and a failure on the last position would leave the earlier ones' stock
      // already gone (§21).
      final code = readCodeOnly(postUseCase);
      expect(code, contains('postDisposalLinesInTransaction'));
      expect(
        RegExp(r'\.postDisposal\(').hasMatch(code),
        isFalse,
        reason:
            'Post use case memanggil metode yang membuka transaksi sendiri.',
      );
    });

    test('metode transaction-aware tidak membuka transaksi', () {
      final code = readCodeOnly(postingService);
      final start = code.indexOf('postDisposalLinesInTransaction');
      expect(start, greaterThan(-1));
      final body = code.substring(
        start,
        code.indexOf('_postDisposalLine', start),
      );
      expect(
        body.contains('runInTransaction'),
        isFalse,
        reason:
            'postDisposalLinesInTransaction membuka transaksi sendiri, sehingga '
            'rollback dokumen tidak lagi atomik.',
      );
    });

    test('movement memakai ref_doc_type DSP dan tipe disposal', () {
      expect(RefDocType.disposal, 'DSP');
      final code = readCodeOnly(postingService);
      expect(code, contains('RefDocType.disposal'));
      expect(code, contains('StockMovementType.disposal'));
    });

    test('ref DSP tidak menabrak DIST', () {
      expect(RefDocType.disposal, isNot(RefDocType.distribution));
      expect(RefDocType.disposal, isNot(RefDocType.goodReceipt));
      expect(RefDocType.disposal, isNot(RefDocType.deliveryOrder));
      expect(RefDocType.disposal, isNot(RefDocType.purchaseRequest));
      expect(RefDocType.disposal, isNot(RefDocType.stockOpname));
    });

    test('movement disposal selalu tanpa lokasi tujuan', () {
      // §20: a disposal has one leg. The posting core states `toLocationId: null`
      // literally rather than leaving it to a default, so the absence is visible.
      final code = readCodeOnly(postingService);
      final start = code.indexOf('_postDisposalLine');
      final body = code.substring(start);
      expect(body, contains('toLocationId: null'));
    });
  });

  group('tidak ada tujuan di mana pun', () {
    test('tabel tidak memiliki kolom lokasi tujuan', () {
      final code = readCodeOnly(tables);
      expect(code.contains('toLocationId'), isFalse);
      expect(code.contains('destinationLocation'), isFalse);
    });

    test('kontrak, DAO dan model tidak menyebut tujuan', () {
      for (final file in [
        repository,
        dao,
        '$domainRoot/models/disposal_models.dart',
      ]) {
        final code = readCodeOnly(file);
        for (final needle in const [
          'toLocationId',
          'destinationLocationId',
          'destinationLocationsBy',
        ]) {
          expect(
            code.contains(needle),
            isFalse,
            reason: '$file menyebut lokasi tujuan ($needle).',
          );
        }
      }
    });

    test('UI tidak memiliki pemilih tujuan', () {
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        expect(code.contains('destinationLocation'), isFalse);
        expect(code.contains('toLocationId'), isFalse);
      }
    });
  });

  group('tidak ada penulis yang tidak dibatasi', () {
    test('DAO tidak menyediakan pembaruan status generik', () {
      final code = readCodeOnly(dao);
      expect(
        code.contains('setStatus'),
        isFalse,
        reason: 'Pembaruan status generik akan melewati mesin status.',
      );
      // The one transition names the status it moves *from*, inside the statement.
      expect(code, contains("status = 'draft'"));
    });

    test('tidak ada un-post, reopen atau cancel di mana pun', () {
      for (final file in [
        dao,
        repository,
        driftRepository,
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder(presentationRoot),
      ]) {
        final code = readCodeOnly(file);
        for (final needle in const [
          'unpost',
          'unPost',
          'reopen',
          'markDraft',
          'cancelDisposal',
        ]) {
          expect(
            code.contains(needle),
            isFalse,
            reason:
                '$file menyediakan jalan keluar dari status posted ($needle).',
          );
        }
      }
    });

    test('tidak ada hard delete', () {
      for (final file in [dao, driftRepository]) {
        final code = readCodeOnly(file);
        expect(
          code.contains('DELETE FROM'),
          isFalse,
          reason: '$file menghapus baris secara permanen (G-A5).',
        );
        expect(code.contains('.delete('), isFalse);
      }
    });

    test('tidak ada penulis untuk source_location_id', () {
      // The source decides who may post the document, so a writer here would move a
      // document into — or out of — somebody else's scope.
      for (final file in [dao, driftRepository, repository]) {
        final code = readCodeOnly(file);
        expect(
          code.contains('SET source_location_id'),
          isFalse,
          reason: '$file mengubah lokasi sumber.',
        );
        expect(
          code.contains('updateSourceLocation'),
          isFalse,
          reason: '$file menyediakan pengubah lokasi sumber.',
        );
      }
    });

    test('penulis baris tidak menjangkau item atau batch', () {
      // A different batch is a *different* position, with its own expiry date and its
      // own balance. Changing one in place would slip past both checks.
      final code = readCodeOnly(dao);
      final start = code.indexOf('updateDraftLine');
      final body = code.substring(start, code.indexOf('softDeleteDraftLine'));
      expect(body.contains('SET qty'), isTrue);
      expect(body.contains('item_id ='), isFalse);
      expect(body.contains('batch_id ='), isFalse);
    });

    test('setiap penulis terjaga mengembalikan jumlah baris terpengaruh', () {
      final code = readCodeOnly(driftRepository);
      for (final method in const [
        'updateDraftReason',
        'updateDraftLine',
        'removeDraftLine',
        'markPosted',
      ]) {
        expect(
          code.contains(method),
          isTrue,
          reason: '$method hilang dari repository.',
        );
      }
      // `… > 0` is how "the guard fired" becomes a boolean the caller must handle.
      expect(code, contains('> 0'));
    });
  });

  group('kelayakan hanya barang kedaluwarsa', () {
    test('tidak ada jalur untuk barang tanpa kedaluwarsa', () {
      // §9: damaged, recalled and rejected goods are different workflows with their
      // own eligibility rules, and letting one in here would give it none of them.
      final code = readCodeOnly('$domainRoot/use_cases/disposal_guards.dart');
      expect(code, contains('DisposalItemMustHaveExpiryFailure'));
      expect(code, contains('!item.hasExpiry'));
    });

    test('batch_id baris tidak nullable', () {
      final code = readCodeOnly(tables);
      final start = code.indexOf('class DisposalLines');
      final body = code.substring(start);
      expect(body, contains('TextColumn get batchId => text().references('));
      expect(
        body.contains('batchId => text().nullable()'),
        isFalse,
        reason: 'batch_id yang nullable membuat pemusnahan non-batch mungkin.',
      );
    });

    test('kueri kandidat menuntut batch dan has_expiry', () {
      final code = readCodeOnly(dao);
      expect(code, contains('stockBalances.batchId.isNotNull()'));
      expect(code, contains('items.hasExpiry.equals(true)'));
    });

    test('kebijakan kedaluwarsa tidak menerima override', () {
      // Nothing here takes a `force`, a `confirmed` or an override reason. A batch
      // that has not expired cannot be put on a disposal by any path.
      final code = readCodeOnly(expiryPolicy);
      for (final needle in const ['force', 'override', 'confirmed', 'bypass']) {
        expect(
          code.toLowerCase().contains(needle),
          isFalse,
          reason: 'DisposalExpiryPolicy menerima jalan pintas ($needle).',
        );
      }
    });

    test('aturan kedaluwarsa dinyatakan sekali dan dipakai ulang', () {
      // One definition, so the badge and the refusal can never disagree about which
      // batch is past its date.
      final code = readCodeOnly(expiryPolicy);
      expect(code, contains('DateOnly.isBeforeDate'));
      expect(code, contains('AppTimeZone.operationalDate'));

      // Nothing else in the feature converts an instant into an operational date.
      // That conversion *is* the expiry rule — `operationalDate > expiryDate` — so a
      // second caller of it would be a second definition, and the two would
      // eventually disagree by a day at the GMT+8 boundary.
      //
      // Comparing two civil dates against each other is a different thing and stays
      // allowed: `DisposalProgress` finds the oldest expiry on a document that way,
      // and no clock is involved.
      for (final file in [
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder(dataRoot),
        ...dartFilesUnder(presentationRoot),
      ]) {
        if (file.endsWith('disposal_expiry_policy.dart')) continue;
        expect(
          readCodeOnly(file).contains('AppTimeZone.operationalDate'),
          isFalse,
          reason: '$file mendefinisikan ulang aturan kedaluwarsa.',
        );
      }
    });

    test('kandidat dan model tidak memakai double untuk hari kedaluwarsa', () {
      // §12: a count of days has no fractional part.
      final code = readCodeOnly('$domainRoot/models/disposal_models.dart');
      expect(code, contains('int daysExpiredOn('));
      expect(code.contains('double daysExpired'), isFalse);
    });
  });

  group('rute dan penjagaan', () {
    test('setiap rute :id dibungkus penjaga', () {
      final code = readCodeOnly(router);
      final section = code.substring(
        code.indexOf('AppRoutes.warehouseDisposals'),
      );
      for (final name in const [
        'warehouseDisposalDetailName',
        'warehouseDisposalEditName',
        'disposalDetailName',
        'disposalEditName',
      ]) {
        final index = section.indexOf(name);
        expect(index, greaterThan(-1), reason: '$name tidak dirutekan.');
        // The guard is the next thing the builder does.
        final window = section.substring(index, index + 600);
        expect(
          window.contains('DisposalRouteGuard'),
          isTrue,
          reason: 'Rute $name tidak dijaga.',
        );
      }
    });

    test('rute bagian memakai section guard', () {
      final code = readCodeOnly(router);
      expect(code, contains('DisposalSectionGuard'));
      expect(code, contains('DisposalRouteKind.warehouseList'));
      expect(code, contains('DisposalRouteKind.branchList'));
    });

    test('editor memakai kind yang berbeda dari detail', () {
      final code = readCodeOnly(router);
      expect(code, contains('DisposalRouteKind.warehouseDraft'));
      expect(code, contains('DisposalRouteKind.branchDraft'));
      expect(code, contains('DisposalRouteKind.warehouseDocument'));
      expect(code, contains('DisposalRouteKind.branchDocument'));
    });

    test('penjaga membaca ulang aktor dari database', () {
      final code = readCodeOnly(guard);
      expect(code, contains('actingUserProvider'));
      // O-8: the decision rests on the stored role, never on the session's claim.
      expect(code, contains('findAccessScope'));
    });

    test('penjaga gagal tertutup', () {
      final code = readCodeOnly(guard);
      expect(code, contains('AccessDeniedPage'));
      expect(code, contains('error: (_, _) => const AccessDeniedPage()'));
    });

    test('kedua jalur rute terdaftar', () {
      final code = readCodeOnly(routes);
      expect(code, contains("'/warehouse/disposals'"));
      expect(code, contains("'/disposals'"));
    });
  });

  group('provider', () {
    test('provider layar bersifat autoDispose', () {
      final code = readCodeOnly(providers);
      for (final name in const [
        'warehouseDisposalListProvider',
        'branchDisposalListProvider',
        'warehouseDisposalDetailProvider',
        'branchDisposalDetailProvider',
        'disposalExpiredPositionsProvider',
        'disposalSourceLocationsProvider',
      ]) {
        final index = code.indexOf(name);
        expect(index, greaterThan(-1), reason: '$name hilang.');
        final window = code.substring(index, index + 240);
        expect(
          window.contains('autoDispose'),
          isTrue,
          reason:
              '$name bukan autoDispose, sehingga dokumen dapat bertahan di cache '
              'melewati pergantian sesi.',
        );
      }
    });

    test('provider sumber tidak menerima argumen lokasi bebas', () {
      // A `family<…, String branchId>` would be a parameter a screen could fill in
      // with somebody else's branch (§27).
      final code = readCodeOnly(providers);
      final index = code.indexOf('disposalSourceLocationsProvider');
      final window = code.substring(index, index + 200);
      expect(window.contains('family'), isFalse);
    });

    test('cakupan cabang berasal dari aktor, bukan dari pemanggil', () {
      final code = readCodeOnly(providers);
      expect(code, contains('actingBranchIdProvider'));
      expect(code, contains('actingRoleProvider'));
    });

    test('setiap provider daftar memeriksa peran sebelum membuka stream', () {
      final code = readCodeOnly(providers);
      for (final name in const [
        'warehouseDisposalListProvider',
        'branchDisposalListProvider',
      ]) {
        final index = code.indexOf(name);
        final window = code.substring(index, index + 700);
        expect(
          window.contains('actingRoleProvider'),
          isTrue,
          reason: '$name membuka stream tanpa memeriksa peran.',
        );
      }
    });
  });

  group('waktu', () {
    test('tidak ada perbandingan timestamp leksikal di SQL', () {
      for (final file in [dao, tables, database]) {
        final code = readCodeOnly(file);
        for (final needle in const [
          'posted_at >= created_at',
          'posted_at > created_at',
          "posted_at >= '",
        ]) {
          expect(
            code.contains(needle),
            isFalse,
            reason: '$file membandingkan timestamp sebagai teks.',
          );
        }
      }
    });

    test('tidak ada toLocal di mana pun pada fitur ini', () {
      for (final file in [...dartFilesUnder(featureRoot), dao, tables, guard]) {
        expect(
          readCodeOnly(file).contains('.toLocal()'),
          isFalse,
          reason: '$file memakai zona waktu perangkat (T-4/T-6).',
        );
      }
    });

    test('urutan timestamp diputuskan oleh kebijakan bersama', () {
      final code = readCodeOnly(postUseCase);
      expect(code, contains('DocumentTimestampPolicy.requireOrdered'));
    });

    test('migrasi v9 memakai SQL index yang dibekukan', () {
      // Comment-stripped, because the migration file *explains* at length why the
      // list is not derived from `allSchemaEntities`.
      final code = readCodeOnly(database);

      expect(code, contains('_v9DisposalIndexes'));
      expect(code, contains('if (from < 9)'));
      expect(code, contains('int get schemaVersion => 9;'));
      expect(
        code.contains('allSchemaEntities'),
        isFalse,
        reason:
            'Langkah migrasi harus tetap melakukan apa yang ia lakukan saat '
            'dirilis.',
      );
    });
  });

  group('kosakata', () {
    test('tidak ada kata persetujuan di UI Pemusnahan', () {
      // §7/§13: posting is not approving, and there is no approval stage to describe.
      // Wording that implied one would describe a document that does not exist.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final needle in const [
          'Setujui',
          'Approve',
          'Disetujui',
          'Menunggu Persetujuan',
        ]) {
          expect(
            code.contains(needle),
            isFalse,
            reason: '$file memakai kosakata persetujuan ($needle).',
          );
        }
      }
    });

    test('status memakai label yang benar', () {
      expect(DisposalStatus.draft.label, 'Draft');
      expect(DisposalStatus.posted.label, 'Sudah Diposting');
    });

    test('tombol posting memakai kata Posting Pemusnahan', () {
      final code = readCodeOnly(
        '$presentationRoot/pages/disposal_form_page.dart',
      );
      expect(code, contains('Posting Pemusnahan'));
    });

    test('tidak ada status submitted, approved atau rejected', () {
      expect(DisposalStatus.values, hasLength(2));
      expect(DisposalStatus.values.map((status) => status.dbValue).toSet(), {
        'draft',
        'posted',
      });
    });
  });

  group('dokumen lain tetap menolak stok kedaluwarsa', () {
    test('Distribusi masih memblokir batch kedaluwarsa (G-E4)', () {
      // The two halves of the same line: a batch blocked from a distribution on the
      // day this milestone starts allowing it onto a disposal. If they ever
      // disagreed there would be a day on which a batch could go nowhere at all.
      final code = readCodeOnly(
        'lib/features/distribution/domain/use_cases/distribution_guards.dart',
      );
      expect(code, contains('requireNotExpired'));
      expect(code, contains('ExpiredBatchForDistributionFailure'));
    });

    test('Delivery Order masih memblokir batch kedaluwarsa (G-E4)', () {
      final code = readCodeOnly(
        'lib/features/inventory/domain/services/stock_posting_service.dart',
      );
      final start = code.indexOf('postShipmentInTransaction');
      final body = code.substring(
        start,
        code.indexOf('postGoodReceiptInTransaction'),
      );
      expect(body, contains('_rejectExpiredBatch'));
    });

    test('hanya jalur disposal yang melewati pemeriksaan kedaluwarsa', () {
      final code = readCodeOnly(postingService);
      final start = code.indexOf('postDisposalLinesInTransaction');
      final body = code.substring(
        start,
        code.indexOf('_postDisposalLine', start),
      );
      expect(
        body.contains('_rejectExpiredBatch'),
        isFalse,
        reason:
            'Pemusnahan justru harus menerima batch kedaluwarsa — itulah G-E7.',
      );
    });
  });
}
