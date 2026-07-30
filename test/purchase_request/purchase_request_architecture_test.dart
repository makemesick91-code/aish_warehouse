import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// Architecture rules for Purchase Request, enforced against the source itself.
///
/// These are the invariants no runtime test can catch, because breaking them still
/// compiles and still passes: a widget reaching past the repository into a DAO, a
/// quantity path that quietly grows a `double`, a `:id` route that ships without a
/// guard, a generic status writer that lets any caller move any document anywhere. Each
/// of them would be caught in code review once and then slowly reintroduced; here they
/// fail the build.
void main() {
  const featureRoot = 'lib/features/purchase_request';
  const domainRoot = '$featureRoot/domain';
  const presentationRoot = '$featureRoot/presentation';
  const dao = 'lib/core/db/daos/purchase_request_dao.dart';
  const tables = 'lib/core/db/tables/purchase_request_tables.dart';
  const repository =
      '$domainRoot/repositories/purchase_request_repository.dart';
  const driftRepository =
      '$featureRoot/data/repositories/drift_purchase_request_repository.dart';
  const providers =
      '$presentationRoot/providers/purchase_request_providers.dart';

  group('lapisan presentation', () {
    test('halaman dan widget PR tidak mengimpor DAO', () {
      for (final file in dartFilesUnder(presentationRoot)) {
        for (final import in importsOf(file)) {
          expect(
            import.contains('db/daos/'),
            isFalse,
            reason:
                '$file mengimpor DAO. UI harus lewat provider → use case → '
                'repository.',
          );
        }
      }
    });

    test('halaman dan widget PR tidak mengimpor kelas drift generated', () {
      for (final file in dartFilesUnder(presentationRoot)) {
        for (final import in importsOf(file)) {
          expect(
            import.endsWith('.g.dart') || import.endsWith('app_database.dart'),
            isFalse,
            reason: '$file mengimpor kelas drift generated.',
          );
        }
      }
    });

    test('halaman dan widget tidak mengimpor repository konkret', () {
      for (final file in dartFilesUnder(presentationRoot)) {
        if (!file.contains('/pages/') && !file.contains('/widgets/')) continue;
        for (final import in importsOf(file)) {
          expect(
            import.contains('data/repositories/'),
            isFalse,
            reason:
                '$file mengimpor repository konkret. Halaman harus lewat '
                'provider.',
          );
        }
      }
    });

    test('presentation memakai baca ter-scope, bukan getDetail generik', () {
      // `getDetail`/`watchDetail` are the unscoped reads and they exist for the use
      // cases, which apply their branch guard afterwards and can afford to load first.
      // A screen cannot: by the time it could check, another branch's document is
      // already in the widget tree.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final unscoped in ['.getDetail(', '.summaryById(']) {
          expect(
            code.contains(unscoped),
            isFalse,
            reason:
                '$file memakai baca tanpa scope ($unscoped). Gunakan '
                'watchDetailForBranch / watchDetailForWarehouse.',
          );
        }
      }
    });

    test('presentation tidak memakai API daftar tanpa scope', () {
      // `list`/`watchList` take a filter whose `branchId` defaults to `null`, which
      // means *every branch*. They are the repository's general shape and the two
      // scoped wrappers are built on them; a screen must reach for the wrapper that
      // states its scope, so "all branches" is never the accidental default.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final unscoped in ['.watchList(', '.list(']) {
          expect(
            code.contains(unscoped),
            isFalse,
            reason:
                '$file memakai $unscoped. Gunakan watchForBranch atau '
                'watchWarehouseQueue yang menyatakan scope-nya.',
          );
        }
      }
    });

    test('daftar opname eligible tidak menerima branch id dari pemanggil', () {
      final source = readCodeOnly(providers);

      // A provider that accepts a branch id is one careless call away from reading
      // another branch's counts, and `eligibleOpnamesProvider('branch-2')` does not
      // look suspicious at the call site. The branch comes from the acting user only.
      expect(
        RegExp(
          r'eligibleOpnamesProvider\s*=\s*FutureProvider\.autoDispose'
          r'<List<PurchaseRequestOpnameReference>>',
        ).hasMatch(source),
        isTrue,
        reason:
            'eligibleOpnamesProvider tidak boleh berupa family ber-branch id.',
      );
      expect(source, isNot(contains('branchIdOverride')));
    });

    test('provider detail cabang mengikat cabang dari sumber tunggal', () {
      final source = readCodeOnly(providers);

      // The branch must come from `actingBranchIdProvider` on every build — not from a
      // parameter a caller could pass at will, and not from a value captured once.
      expect(source, contains('watchDetailForBranch'));
      expect(source, contains('actingBranchIdProvider'));
      expect(
        RegExp(
          r'purchaseRequestDetailProvider\s*=\s*StreamProvider\.autoDispose',
        ).hasMatch(source),
        isTrue,
        reason:
            'purchaseRequestDetailProvider harus autoDispose agar dokumen yang '
            'pernah dibuka tidak tertinggal di cache setelah sesi berganti.',
      );
      expect(
        RegExp(
          r'warehousePurchaseRequestDetailProvider\s*=\s*'
          r'StreamProvider\.autoDispose',
        ).hasMatch(source),
        isTrue,
      );
    });

    test('provider warehouse memeriksa peran sebelum baca lintas cabang', () {
      final source = readCodeOnly(providers);
      final start = source.indexOf('warehousePurchaseRequestDetailProvider');
      expect(start, greaterThan(-1), reason: 'Pola tes usang.');

      final end = source.indexOf('// ---', start);
      final body = source.substring(start, end > start ? end : source.length);
      expect(
        body,
        contains('UserRole.warehouse'),
        reason:
            'Baca tanpa scope cabang harus menolak aktor yang bukan Warehouse, '
            'bukan hanya mengandalkan route guard.',
      );
    });

    test('setiap rute ber-:id dibungkus penjaga akses', () {
      final router = readCodeOnly('lib/app/router.dart');

      // Stated as an invariant over the routes that exist, not as a fixed count: a count
      // would keep passing the day somebody adds `/purchase-requests/:id/cetak` without
      // a guard. Reading `pathParameters['id']` is what makes a route
      // document-specific, so every such builder must be wrapped.
      final idRoutes = RegExp(
        r"pathParameters\['id'\]",
      ).allMatches(router).length;
      final guards = RegExp(r'\w*RouteGuard\(').allMatches(router).length;

      expect(idRoutes, greaterThan(0), reason: 'Pola tes usang.');
      expect(
        guards,
        idRoutes,
        reason:
            'Ditemukan $idRoutes rute ber-:id tetapi hanya $guards penjaga '
            'dokumen.',
      );
      expect(router, contains('PurchaseRequestRouteKind.branchDocument'));
      expect(router, contains('PurchaseRequestRouteKind.branchDraft'));
      expect(router, contains('PurchaseRequestRouteKind.warehouseDocument'));
    });

    test('rute bagian PR juga dibungkus penjaga bagian', () {
      final router = readCodeOnly('lib/app/router.dart');

      // The synchronous redirect decides sections from the session; the section guard
      // re-asks against the *stored* user, so a deep link that arrives before the
      // redirect still renders nothing.
      expect(router, contains('PurchaseRequestSectionGuard'));
      expect(router, contains('PurchaseRequestRouteKind.branchList'));
      expect(router, contains('PurchaseRequestRouteKind.branchCreate'));
      expect(router, contains('PurchaseRequestRouteKind.warehouseQueue'));
    });
  });

  group('lapisan domain', () {
    test('domain PR tidak bergantung pada drift', () {
      for (final file in dartFilesUnder(domainRoot)) {
        expect(
          readLibrarySource(file).contains('package:drift/drift.dart'),
          isFalse,
          reason: '$file mengimpor drift.',
        );
        for (final import in importsOf(file)) {
          expect(
            import.endsWith('.g.dart') ||
                import.endsWith('db/app_database.dart') ||
                import.contains('db/daos/'),
            isFalse,
            reason: '$file bergantung pada lapisan database.',
          );
        }
      }
    });

    test('domain PR tidak menyentuh BuildContext atau Flutter', () {
      for (final file in dartFilesUnder(domainRoot)) {
        final source = readLibrarySource(file);
        expect(
          RegExp(r'\bBuildContext\b').hasMatch(source),
          isFalse,
          reason: '$file menerima BuildContext.',
        );
        expect(
          source.contains('package:flutter/'),
          isFalse,
          reason: '$file mengimpor Flutter.',
        );
      }
    });

    test('domain PR memakai Quantity, bukan milli-unit mentah', () {
      for (final file in dartFilesUnder(domainRoot)) {
        expect(
          readLibrarySource(file).contains('milliUnits'),
          isFalse,
          reason:
              '$file menyentuh milli-unit. Konversi hanya boleh terjadi di '
              'repository (Q-4); perbandingan eksak ada di '
              'Quantity.exceedsRatioOf.',
        );
      }
    });

    test('tidak ada double pada jalur kuantitas PR', () {
      // A `double` anywhere on this path is the bug the fixed-point type exists to
      // prevent: `requested.toDouble() > suggested.toDouble() * 1.5` would decide the
      // 150 % threshold by whichever side binary rounding landed on.
      for (final file in [
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder('$featureRoot/data'),
        dao,
        tables,
      ]) {
        final code = readCodeOnly(file);
        expect(
          RegExp(r'\bdouble\b').hasMatch(code),
          isFalse,
          reason: '$file memakai double pada jalur kuantitas.',
        );
        expect(
          code.contains('toDouble()'),
          isFalse,
          reason: '$file mengonversi kuantitas ke double.',
        );
      }
    });

    test('kebijakan PR bebas dari Flutter dan database', () {
      // A rule that needs a widget tree or a query to be evaluated cannot be reused by
      // the router, the providers and the tests alike.
      for (final file in [
        '$domainRoot/services/purchase_request_state_policy.dart',
        '$domainRoot/services/purchase_request_quantity_policy.dart',
        '$domainRoot/services/purchase_request_access_policy.dart',
        '$domainRoot/services/purchase_request_opname_eligibility_policy.dart',
        '$domainRoot/services/suggested_purchase_request_calculator.dart',
      ]) {
        final source = readLibrarySource(file);
        expect(source, isNot(contains('package:flutter/')));
        expect(source, isNot(contains('package:drift/')));
        expect(source, isNot(contains('BuildContext')));
        expect(
          source,
          isNot(contains('Future<')),
          reason: '$file harus murni sinkron agar dapat dipakai di mana saja.',
        );
      }
    });

    test('kalkulator saran tidak membaca saldo atau selisih opname', () {
      final source = readCodeOnly(
        '$domainRoot/services/suggested_purchase_request_calculator.dart',
      );

      // The suggestion is `par − counted`, computed from the opname snapshot. Reading a
      // live balance would reintroduce the movements the count was meant to settle, and
      // reading `difference` would answer a question about bookkeeping accuracy instead.
      expect(source, isNot(contains('balance')));
      expect(source, isNot(contains('qtyOnHand')));
      expect(source, isNot(contains('.difference')));
    });

    test('use case tidak membaca jam sendiri di luar default', () {
      // Every clock is injected so a test can sit on a year boundary (T-7). The one
      // `DateTime.now()` each use case is allowed is its `_defaultClock`.
      for (final file in dartFilesUnder('$domainRoot/use_cases')) {
        final matches = RegExp(
          r'DateTime\.now\(\)',
        ).allMatches(readCodeOnly(file)).length;
        expect(
          matches,
          lessThanOrEqualTo(1),
          reason:
              '$file membaca jam lebih dari sekali; hanya _defaultClock yang '
              'boleh.',
        );
      }
    });
  });

  group('dokumen final dan penulisan terjaga', () {
    test('DAO tidak menawarkan penulis generik', () {
      final source = readCodeOnly(dao);

      // Every header write is guarded by a status predicate in the same statement; a
      // bare `update(...).write(...)` would not be.
      expect(
        RegExp(r'update\(purchaseRequests\)\)\s*\.write').hasMatch(source),
        isFalse,
      );
      expect(
        RegExp(r'update\(purchaseRequestLines\)\)\s*\.write').hasMatch(source),
        isFalse,
      );
      expect(
        RegExp(
          r'update\(purchaseRequestOpnames\)\)\s*\.write',
        ).hasMatch(source),
        isFalse,
      );
      // And nothing is ever hard deleted (G-A5).
      expect(source, isNot(contains('delete(purchaseRequests)')));
      expect(source, isNot(contains('delete(purchaseRequestLines)')));
      expect(source, isNot(contains('delete(purchaseRequestOpnames)')));
    });

    test('DAO tidak menawarkan setStatus generik', () {
      final source = readCodeOnly(dao);

      // Each transition names the status it expects to move *from*, so the predicate
      // travels into the same statement as the write.
      expect(source, isNot(contains('Future<int> setStatus')));
      expect(source, isNot(contains('Future<int> updateStatus')));
      expect(source, contains('Future<int> _transition('));
      for (final method in [
        'Future<int> submit(',
        'Future<int> markProcessing(',
        'Future<int> cancel(',
        'Future<int> reject(',
      ]) {
        expect(source, contains(method));
      }
    });

    test('tidak ada penulis shipped atau closed', () {
      // Those transitions belong to Delivery Order and Good Receipt. Offering one here
      // would be a button waiting to be wired up before the documents that justify it
      // exist.
      for (final file in [dao, driftRepository, repository, providers]) {
        final code = readCodeOnly(file);
        expect(
          code.contains('PurchaseRequestStatus.shipped'),
          isFalse,
          reason: '$file dapat menulis status shipped.',
        );
        expect(
          code.contains('PurchaseRequestStatus.closed'),
          isFalse,
          reason: '$file dapat menulis status closed.',
        );
      }
      // A use case may *mention* the two statuses — the guards render a sentence for
      // a document that is already in one. What none of them may do is ask for a
      // transition into one, which is what a `to:` argument expresses.
      for (final file in dartFilesUnder('$domainRoot/use_cases')) {
        final code = readCodeOnly(file);
        for (final status in ['shipped', 'closed']) {
          expect(
            RegExp('to:\\s*PurchaseRequestStatus\\.$status').hasMatch(code),
            isFalse,
            reason: '$file meminta transisi menuju $status.',
          );
        }
      }
    });

    test('setiap penulis baris dan tautan dijaga status draft', () {
      final source = readCodeOnly(dao);

      // The guard is `status = 'draft'` inside the statement, evaluated by SQLite in the
      // same breath as the write — not a Dart check above it with a gap in between.
      final guarded = "WHERE status = 'draft' AND deleted_at IS NULL";
      final writers = RegExp(
        r"UPDATE purchase_request_(lines|opnames) ",
      ).allMatches(source).length;
      expect(writers, greaterThan(0), reason: 'Pola tes usang.');
      expect(
        guarded.allMatches(source).length,
        writers,
        reason:
            'Ditemukan $writers penulis baris/tautan tetapi tidak semuanya '
            'dijaga status draft.',
      );
    });

    test('repository tidak menawarkan update dokumen bebas', () {
      final source = readCodeOnly(repository);

      expect(source, isNot(contains('Future<void> update(PurchaseRequest')));
      expect(source, isNot(contains('Future<bool> setStatus')));
      // Only the specific guarded operations exist.
      expect(source, contains('updateDraftHeader'));
      expect(source, contains('updateDraftLine'));
      expect(source, contains('markProcessing'));
      expect(source, contains('reject'));
    });

    test('penulis baris tidak menerima suggested_qty', () {
      final source = readCodeOnly(repository);
      final start = source.indexOf('Future<bool> updateDraftLine(');
      expect(start, greaterThan(-1), reason: 'Pola tes usang.');
      final end = source.indexOf('});', start);

      expect(
        source.substring(start, end),
        isNot(contains('suggestedQty')),
        reason:
            'Snapshot saran bukan milik editor; hanya '
            'replaceOpnameLinksAndSuggestions yang boleh memindahkannya.',
      );
    });

    test('Warehouse tidak memiliki mutasi isi PR', () {
      // The two warehouse use cases record who and when, and nothing else. No argument
      // for a quantity, an item or a note exists to pass (G-R3).
      for (final file in [
        '$domainRoot/use_cases/mark_purchase_request_processing_use_case.dart',
        '$domainRoot/use_cases/reject_purchase_request_use_case.dart',
      ]) {
        final code = readCodeOnly(file);
        for (final writer in [
          'updateDraftLine',
          'updateDraftHeader',
          'addDraftLine',
          'removeDraftLine',
          'replaceOpnameLinksAndSuggestions',
        ]) {
          expect(
            code.contains(writer),
            isFalse,
            reason:
                '$file memanggil $writer; Warehouse tidak boleh mengubah isi PR.',
          );
        }
      }
    });
  });

  group('ledger dan schema', () {
    test('PR tidak pernah memposting ke ledger', () {
      // Spec §2.5: a Purchase Request has no stock effect. The first posting happens
      // when a Delivery Order is shipped.
      for (final file in [...dartFilesUnder(featureRoot), dao, tables]) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'StockPostingService',
          'appendMovement',
          'setBalanceQty',
          'postOpnameAdjustment',
          'postTransfer',
          'postInboundWarehouse',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menyentuh ledger dari jalur Purchase Request.',
          );
        }
      }
    });

    test('tabel PR tidak memakai REAL untuk kuantitas', () {
      final source = readLibrarySource(tables);

      expect(source, contains('IntColumn get suggestedQty'));
      expect(source, contains('IntColumn get requestedQty'));
      expect(
        RegExp(r'RealColumn').hasMatch(source),
        isFalse,
        reason: 'Q-3: REAL dilarang pada kolom kuantitas.',
      );
    });

    test('tabel PR tidak memiliki batch_id', () {
      // A Purchase Request asks for an item; which batches satisfy it is the warehouse's
      // FEFO decision at Delivery Order time (G-E3).
      expect(readLibrarySource(tables).contains('get batchId'), isFalse);
    });

    test('index unik parsial G-P2 dan G-P4 dinyatakan pada tabel', () {
      final source = readLibrarySource(tables);

      expect(source, contains('idx_purchase_requests_active_branch'));
      expect(source, contains("status IN ('submitted', 'processing')"));
      expect(source, contains('idx_purchase_request_lines_item_unique'));
      // Uniqueness applies to live rows, so a line removed from a draft does not hold
      // its position hostage.
      expect(
        'deleted_at IS NULL'.allMatches(source).length,
        greaterThanOrEqualTo(4),
      );
    });

    test('migrasi v5 memakai SQL index yang dibekukan', () {
      // Comment-stripped, because the migration file *explains* at length why the list
      // is not derived from `allSchemaEntities`.
      final source = readCodeOnly('lib/core/db/app_database.dart');

      expect(source, contains('_v5PurchaseRequestIndexes'));
      expect(source, contains('if (from < 5)'));
      // Derived from `allSchemaEntities` the list would always describe the *current*
      // schema, so a v6 index would silently change what the v5 step creates.
      expect(
        source.contains('allSchemaEntities'),
        isFalse,
        reason:
            'Langkah migrasi harus tetap melakukan apa yang ia lakukan '
            'saat dirilis.',
      );
      // v5 must not touch `stock_opnames`: the `from < 4` block reads that table's
      // current Dart definition, so changing it would break a v3 → v5 upgrade.
      final v5Start = source.indexOf('if (from < 5)');
      final v5End = source.indexOf('    },', v5Start);
      final v5Block = source.substring(v5Start, v5End);
      expect(v5Block, isNot(contains('stockOpnames')));
      expect(v5Block, isNot(contains('stock_balances')));
      expect(v5Block, isNot(contains('stock_movements')));
    });

    test('generated manager tetap dinonaktifkan', () {
      // The manager API is a second, unguarded write path into every table: it would let
      // any caller overwrite a snapshot, edit the lines of a submitted document, or hard
      // delete business rows — the exact things the DAOs are written to make impossible.
      expect(
        readLibrarySource('build.yaml'),
        contains('generate_manager: false'),
      );
    });
  });

  test('tidak ada TODO pada aturan inti Purchase Request', () {
    for (final file in [...dartFilesUnder(featureRoot), tables, dao]) {
      expect(
        RegExp(r'\bTODO\b|\bFIXME\b').hasMatch(readLibrarySource(file)),
        isFalse,
        reason: '$file masih memuat TODO/FIXME pada jalur aturan inti.',
      );
    }
  });
}
