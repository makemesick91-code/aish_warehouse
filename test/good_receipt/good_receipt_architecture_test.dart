import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// Architecture rules for Good Receipt, enforced against the source itself (§50).
///
/// These are the invariants no runtime test can catch, because breaking them still
/// compiles and still passes: a widget reaching past the repository into a DAO, a quantity
/// path that quietly grows a `double`, a `:id` route that ships without a guard, a generic
/// status writer that lets any caller move any document anywhere. Each of them would be
/// caught in code review once and then slowly reintroduced; here they fail the build.
void main() {
  const featureRoot = 'lib/features/good_receipt';
  const domainRoot = '$featureRoot/domain';
  const presentationRoot = '$featureRoot/presentation';
  const dao = 'lib/core/db/daos/good_receipt_dao.dart';
  const tables = 'lib/core/db/tables/good_receipt_tables.dart';
  const repository = '$domainRoot/repositories/good_receipt_repository.dart';
  const driftRepository =
      '$featureRoot/data/repositories/drift_good_receipt_repository.dart';
  const providers = '$presentationRoot/providers/good_receipt_providers.dart';

  group('lapisan presentation', () {
    test('halaman dan widget tidak mengimpor DAO', () {
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

    test('halaman dan widget tidak mengimpor kelas drift generated', () {
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
      // `getDetail` is the unscoped read and it exists for the use cases, which apply
      // their guards afterwards and can afford to load first. A screen cannot: by the time
      // it could check, another branch's document is already in the widget tree.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final unscoped in [
          '.getDetail(',
          '.summaryById(',
          '.listReceipts(',
          '.lineReferences(',
          '.awaitingReceipts(',
          '.discrepancies(',
        ]) {
          expect(
            code.contains(unscoped),
            isFalse,
            reason:
                '$file memakai baca tanpa scope ($unscoped). Gunakan '
                'watchForBranch / watchForWarehouse.',
          );
        }
      }
    });

    test('provider daftar dan detail menyatakan scope-nya', () {
      final source = readCodeOnly(providers);

      expect(source, contains('watchListForBranch'));
      expect(source, contains('watchListForWarehouse'));
      expect(source, contains('watchForBranch'));
      expect(source, contains('watchForWarehouse'));
      expect(source, contains('watchWarehouseDiscrepancies'));
      expect(source, contains('actingBranchIdProvider'));
      expect(source, contains('actingRoleProvider'));
    });

    test('provider ber-scope layar memakai autoDispose', () {
      final source = readCodeOnly(providers);

      // A stream left subscribed after its screen closed is a cache entry that outlives
      // the session it was scoped for — the one way a branch scope can be correct
      // everywhere and still leak.
      for (final name in [
        'branchAwaitingDeliveriesProvider',
        'branchGoodReceiptListProvider',
        'warehouseGoodReceiptListProvider',
        'warehouseDiscrepancyQueueProvider',
        'branchGoodReceiptDetailProvider',
        'warehouseGoodReceiptDetailProvider',
        'warehouseGoodReceiptRemindersProvider',
      ]) {
        expect(
          RegExp('$name\\s*=\\s*StreamProvider\\.autoDispose').hasMatch(source),
          isTrue,
          reason: '$name harus StreamProvider.autoDispose.',
        );
      }
      for (final name in [
        'branchGoodReceiptRemindersProvider',
        'branchGoodReceiptUrgentRemindersProvider',
        'warehouseOverdueRemindersProvider',
        'branchGoodReceiptProgressProvider',
        'branchReceiptForDeliveryProvider',
        'warehouseReturnCandidatesProvider',
      ]) {
        expect(
          RegExp('$name\\s*=\\s*Provider\\.autoDispose').hasMatch(source),
          isTrue,
          reason: '$name harus Provider.autoDispose.',
        );
      }
    });

    test('provider warehouse memeriksa peran sebelum baca lintas cabang', () {
      final source = readCodeOnly(providers);

      // The role check is what stands in for the branch predicate on an unscoped read, so
      // the route guard is not the only thing between a branch session and every branch's
      // receipts.
      for (final name in [
        'warehouseGoodReceiptListProvider',
        'warehouseDiscrepancyQueueProvider',
        'warehouseGoodReceiptDetailProvider',
        'warehouseGoodReceiptRemindersProvider',
      ]) {
        final start = source.indexOf(name);
        expect(start, greaterThan(-1), reason: 'Pola tes usang: $name.');
        final body = source.substring(start, source.indexOf('});', start));
        expect(
          body,
          contains('UserRole.warehouse'),
          reason: '$name membaca lintas cabang tanpa memeriksa peran.',
        );
      }
    });

    test('layar cabang memakai provider ber-scope cabang', () {
      final source = readCodeOnly(providers);

      for (final name in [
        'branchAwaitingDeliveriesProvider',
        'branchGoodReceiptListProvider',
        'branchGoodReceiptDetailProvider',
      ]) {
        final start = source.indexOf(name);
        final body = source.substring(start, source.indexOf('});', start));
        expect(body, contains('actingBranchIdProvider'));
        expect(body, contains('UserRole.kepalaCabang'));
      }
    });

    test('setiap rute ber-:id dibungkus penjaga akses', () {
      final router = readCodeOnly('lib/app/router.dart');

      // Stated as an invariant over the routes that exist rather than as a fixed count: a
      // count would keep passing the day somebody adds an unguarded document route.
      final idRoutes = RegExp(
        r"pathParameters\['(?:id|deliveryOrderId)'\]",
      ).allMatches(router).length;
      final guards = RegExp(r'\w*RouteGuard\(').allMatches(router).length;

      expect(idRoutes, greaterThan(0), reason: 'Pola tes usang.');
      expect(guards, idRoutes);
      for (final kind in [
        'GoodReceiptRouteKind.branchDocument',
        'GoodReceiptRouteKind.warehouseDocument',
      ]) {
        expect(router, contains(kind));
      }
      expect(router, contains('GoodReceiptCreateRouteGuard'));
    });

    test('rute bagian Good Receipt dibungkus penjaga bagian', () {
      final router = readCodeOnly('lib/app/router.dart');

      expect(router, contains('GoodReceiptSectionGuard'));
      expect(router, contains('GoodReceiptRouteKind.branchList'));
      expect(router, contains('GoodReceiptRouteKind.warehouseList'));
      expect(router, contains('GoodReceiptRouteKind.warehouseDiscrepancies'));
    });

    test('rute create memakai parameter Surat Jalan, bukan id GR', () {
      // `/receipts/new/{do}` names a shipment: the receipt does not exist yet, so there is
      // no id to name.
      expect(
        readCodeOnly('lib/app/routes.dart'),
        contains("receiptNew = 'new/:deliveryOrderId'"),
      );
    });

    test('layar warehouse selisih bersifat read-only', () {
      final code = readCodeOnly(
        '$presentationRoot/pages/warehouse_good_receipt_discrepancy_page.dart',
      );

      // No controller, no use case, no write of any kind: the physical return is a later
      // milestone's document, and a button here would invent stock nobody has counted.
      for (final forbidden in [
        'Controller.notifier',
        'checkGoodReceiptLineUseCase',
        'rejectGoodReceiptLineUseCase',
        'postGoodReceiptUseCase',
        'createGoodReceiptUseCase',
        'FilledButton(',
        'setBalanceQty',
        'appendMovement',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: '$forbidden muncul pada layar read-only.',
        );
      }
    });

    test('tidak ada picker barang bebas pada layar Good Receipt', () {
      // A receipt checks a shipment in; it never adds an item the warehouse did not send.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'SearchableItemDropdown',
          'PurchaseRequestItemPicker',
          'activeItems()',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menawarkan pemilihan barang bebas ($forbidden).',
          );
        }
      }
    });
  });

  group('lapisan domain', () {
    test('domain tidak bergantung pada drift', () {
      for (final file in dartFilesUnder(domainRoot)) {
        for (final import in importsOf(file)) {
          expect(
            import.startsWith('package:drift') ||
                import.contains('db/daos/') ||
                import.endsWith('app_database.dart'),
            isFalse,
            reason: '$file bergantung pada drift.',
          );
        }
      }
    });

    test('domain tidak menyentuh BuildContext atau Flutter', () {
      for (final file in dartFilesUnder(domainRoot)) {
        for (final import in importsOf(file)) {
          expect(
            import.startsWith('package:flutter/'),
            isFalse,
            reason: '$file mengimpor Flutter.',
          );
        }
        expect(
          readCodeOnly(file).contains('BuildContext'),
          isFalse,
          reason: '$file menyentuh BuildContext.',
        );
      }
    });

    test('domain memakai Quantity, bukan milli-unit mentah', () {
      // Q-4: only the repository implementation may touch `milliUnits`.
      for (final file in dartFilesUnder(domainRoot)) {
        expect(
          readCodeOnly(file).contains('milliUnits'),
          isFalse,
          reason: '$file membaca milli-unit langsung.',
        );
      }
    });

    test('tidak ada double pada jalur kuantitas', () {
      for (final file in [
        ...dartFilesUnder(domainRoot),
        driftRepository,
        dao,
        tables,
      ]) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'double ',
          '.toDouble()',
          'RealColumn',
          'as double',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file memakai $forbidden pada jalur kuantitas (Q-3).',
          );
        }
      }
    });

    test('kebijakan bebas dari Flutter, database dan async', () {
      for (final file in dartFilesUnder('$domainRoot/services')) {
        final code = readCodeOnly(file);
        expect(
          code.contains('Future<'),
          isFalse,
          reason: '$file bukan kebijakan murni: memakai Future.',
        );
        expect(
          code.contains('await '),
          isFalse,
          reason: '$file bukan kebijakan murni: memakai await.',
        );
        for (final import in importsOf(file)) {
          expect(
            import.startsWith('package:flutter') ||
                import.startsWith('package:drift'),
            isFalse,
            reason: '$file bukan kebijakan murni: $import.',
          );
        }
      }
    });

    test('kebijakan expiry memakai tanggal operasional, bukan UTC mentah', () {
      final code = readCodeOnly(
        '$domainRoot/services/good_receipt_expiry_policy.dart',
      );

      expect(code, contains('AppTimeZone.operationalDate'));
      expect(
        code.contains('toLocal'),
        isFalse,
        reason: 'T-4: toLocal mengikuti zona perangkat.',
      );
      expect(
        code.contains('DateTime.now'),
        isFalse,
        reason: 'T-7: jam harus diinjeksi.',
      );
    });

    test('kebijakan pengingat tidak membaca jam sendiri', () {
      for (final file in [
        '$domainRoot/services/good_receipt_reminder_policy.dart',
        '$domainRoot/services/good_receipt_reminder_builder.dart',
        '$domainRoot/services/good_receipt_closure_policy.dart',
      ]) {
        final code = readCodeOnly(file);
        expect(code.contains('DateTime.now'), isFalse, reason: file);
        expect(code.contains('toLocal'), isFalse, reason: file);
      }
    });

    test('setiap use case menerima clock yang dapat diinjeksi', () {
      for (final file in dartFilesUnder('$domainRoot/use_cases')) {
        if (file.endsWith('good_receipt_guards.dart')) continue;
        expect(
          readCodeOnly(file).contains('DateTime Function()? clock'),
          isTrue,
          reason: '$file tidak menerima clock yang dapat diinjeksi (T-7).',
        );
      }
    });
  });

  group('dokumen final dan penulisan terjaga', () {
    test('DAO tidak menawarkan penulis generik', () {
      final code = readCodeOnly(dao);

      for (final forbidden in [
        'setStatus',
        'updateLine(',
        'updateHeader(',
        'Future<int> update(',
        'DELETE FROM',
        'softDelete',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'DAO menawarkan penulis generik ($forbidden).',
        );
      }
    });

    test('setiap penulis baris dijaga status checking', () {
      final code = readCodeOnly(dao);

      // Not "the caller checks first": the predicate travels into the statement, so a
      // receipt posted between the read and the write yields zero rows.
      for (final match in RegExp(
        r'UPDATE good_receipt_lines[\s\S]*?;',
      ).allMatches(code)) {
        expect(
          match.group(0),
          contains("status = 'checking'"),
          reason: 'Penulis baris tanpa penjaga checking: ${match.group(0)}',
        );
      }
    });

    test('penulis posting menjaga status dan baris pending', () {
      final code = readCodeOnly(dao);
      final start = code.indexOf('Future<int> markPosted');
      final end = code.indexOf('markDeliveryOrderReceived', start);
      expect(start, greaterThan(-1), reason: 'Pola tes usang.');
      expect(end, greaterThan(start), reason: 'Pola tes usang.');
      final body = code.substring(start, end);

      expect(body, contains("status = 'checking'"));
      // G-G2 re-checked inside the UPDATE, which is what a second device deciding a line
      // between the read and the write would otherwise defeat.
      expect(body, contains('NOT EXISTS'));
      expect(body, contains("line_status = 'pending'"));
    });

    test('transisi asing menyebut status asalnya', () {
      final code = readCodeOnly(dao);

      final received = code.substring(
        code.indexOf('markDeliveryOrderReceived'),
      );
      expect(received, contains('DeliveryOrderStatus.shipped'));

      final closed = code.substring(code.indexOf('markPurchaseRequestClosed'));
      expect(closed, contains('PurchaseRequestStatus.shipped'));
    });

    test('repository tidak menawarkan update dokumen bebas', () {
      final code = readCodeOnly(repository);

      for (final forbidden in [
        'update(GoodReceipt',
        'save(GoodReceipt',
        'delete(',
        'removeLine',
        'setStatus',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'Repository menawarkan $forbidden.',
        );
      }
    });

    test('tidak ada penulis yang menjangkau snapshot pengiriman', () {
      // `item_id`, `batch_id` and `shipped_qty` are what the shipment left. A receipt
      // decides *about* a delivery; it does not rewrite what was sent.
      final code = readCodeOnly(dao);
      for (final forbidden in [
        'SET item_id',
        'SET batch_id',
        'SET shipped_qty',
        'item_id = ?',
        'shipped_qty = ?',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'DAO dapat menulis kolom snapshot ($forbidden).',
        );
      }
    });

    test('tidak ada alur penghapusan baris', () {
      for (final file in [...dartFilesUnder(featureRoot), dao, repository]) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'RemoveGoodReceiptLineUseCase',
          'DeleteGoodReceiptLineUseCase',
          'removeGoodReceiptLine',
          'deleteGoodReceiptLine',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menawarkan penghapusan baris ($forbidden).',
          );
        }
      }
    });

    test('tidak ada use case reopen atau un-post', () {
      for (final file in dartFilesUnder(featureRoot)) {
        final source = readLibrarySource(file);
        for (final forbidden in [
          'ReopenGoodReceiptUseCase',
          'UnpostGoodReceiptUseCase',
          'CancelGoodReceiptUseCase',
          'DeleteGoodReceiptUseCase',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '$file mendeklarasikan $forbidden.',
          );
        }
      }
    });

    test('tidak ada penulis status generik pada use case', () {
      for (final file in dartFilesUnder('$domainRoot/use_cases')) {
        final code = readCodeOnly(file);
        expect(
          RegExp(r'status:\s*(const\s+)?Value\(').hasMatch(code),
          isFalse,
          reason: '$file menulis status langsung, bukan lewat penulis terjaga.',
        );
      }
    });
  });

  group('ledger dan schema', () {
    test('ledger hanya ditulis lewat Inventory service', () {
      // The Good Receipt path may *ask* the posting service to write; it may not write
      // itself. `appendMovement` and `setBalanceQty` belong to the inventory repository
      // alone (G-A1).
      for (final file in [...dartFilesUnder(featureRoot), dao, tables]) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'appendMovement',
          'setBalanceQty',
          'insertMovement',
          'INSERT INTO stock_movements',
          'UPDATE stock_balances',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menulis ledger langsung ($forbidden).',
          );
        }
      }
    });

    test('posting memakai metode transaction-aware', () {
      final code = readCodeOnly(
        '$domainRoot/use_cases/post_good_receipt_use_case.dart',
      );

      expect(code, contains('postGoodReceiptInTransaction'));
      // Not the per-line transfer method, which opens a transaction of its own and would
      // make one commit per line.
      expect(code, isNot(contains('postTransfer')));
      expect(code, isNot(contains('postInboundWarehouse')));
      // And exactly one transaction wraps the whole thing.
      expect(
        'runInTransaction'.allMatches(code).length,
        1,
        reason: 'Posting harus memiliki tepat satu transaksi luar.',
      );
    });

    test('movement good_receipt masuk Gudang Cabang tanpa lokasi asal', () {
      final code = readCodeOnly(
        'lib/features/inventory/domain/services/stock_posting_service.dart',
      );
      final start = code.indexOf('postGoodReceiptInTransaction');
      expect(start, greaterThan(-1), reason: 'Pola tes usang.');
      final body = code.substring(start);

      expect(body, contains('StockMovementType.goodReceipt'));
      expect(body, contains('RefDocType.goodReceipt'));
      expect(body, contains('refDocId: goodReceiptId'));
      // The shipment already recorded the outbound leg (spec §2.5).
      expect(body, contains('fromLocationId: null'));
      expect(body, contains('StockLocationType.branchStore'));
    });

    test('baris rejected tidak memanggil stock posting', () {
      final code = readCodeOnly(
        '$domainRoot/use_cases/post_good_receipt_use_case.dart',
      );

      // Only `addsStock` lines reach the posting service, and that predicate is both
      // halves of G-G5: `checked`, and a positive quantity.
      expect(code, contains('line.addsStock'));
      expect(
        code.contains('StockMovementType.itemReturn'),
        isFalse,
        reason: 'Penolakan tidak boleh menulis movement return.',
      );
    });

    test('tidak ada movement return di seluruh fitur', () {
      // The physical return is a later milestone's document. A `return` movement here
      // would credit the warehouse with stock nobody has counted back in.
      for (final file in [...dartFilesUnder(featureRoot), dao]) {
        final code = readCodeOnly(file);
        expect(
          code.contains('StockMovementType.itemReturn'),
          isFalse,
          reason: '$file menulis movement return.',
        );
      }
    });

    test('tabel Good Receipt tidak memakai REAL untuk kuantitas', () {
      final source = readLibrarySource(tables);

      expect(source, contains('IntColumn get shippedQty'));
      expect(source, contains('IntColumn get receivedQty'));
      expect(
        RegExp(r'RealColumn').hasMatch(source),
        isFalse,
        reason: 'Q-3: REAL dilarang pada kolom kuantitas.',
      );
    });

    test('index unik satu DO satu GR dinyatakan pada tabel tanpa WHERE', () {
      final source = readLibrarySource(tables);

      expect(source, contains('idx_good_receipts_do'));
      expect(source, contains('idx_good_receipt_lines_unique'));
      // Neither is partial: a soft delete must not free a shipment for a second receipt.
      final doIndex = source.substring(
        source.indexOf('CREATE UNIQUE INDEX idx_good_receipts_do'),
      );
      expect(
        doIndex.substring(0, doIndex.indexOf(';')),
        isNot(contains('WHERE')),
      );
    });

    test('migrasi v7 memakai SQL index yang dibekukan', () {
      // Comment-stripped, because the migration file *explains* at length why the list is
      // not derived from `allSchemaEntities`.
      final source = readCodeOnly('lib/core/db/app_database.dart');

      expect(source, contains('_v7GoodReceiptIndexes'));
      expect(source, contains('if (from < 7)'));
      expect(source, contains('int get schemaVersion => 9;'));
      expect(
        source.contains('allSchemaEntities'),
        isFalse,
        reason:
            'Langkah migrasi harus tetap melakukan apa yang ia lakukan saat '
            'dirilis.',
      );

      // v7 must touch nothing an earlier version owns — `delivery_orders` above all: a
      // migration that marked existing shipments `received` would assert a business event
      // that never happened.
      final v7Start = source.indexOf('if (from < 7)');
      final v7End = source.indexOf('    },', v7Start);
      final v7Block = source.substring(v7Start, v7End);
      for (final untouched in [
        'stockOpnames',
        'stock_balances',
        'stock_movements',
        'purchaseRequests',
        'deliveryOrders',
        'alterTable',
      ]) {
        expect(
          v7Block.contains(untouched),
          isFalse,
          reason: 'Blok migrasi v7 menyentuh $untouched.',
        );
      }
    });

    test('tidak ada perbandingan timestamp di SQL', () {
      // Timestamps are ISO-8601 TEXT (`build.yaml`), so `posted_at >= ?` in SQLite
      // compares characters rather than instants — the trap schema v4 removed from
      // `stock_opnames`. The posted-date window is applied in Dart, on UTC instants.
      final code = readCodeOnly(dao);

      for (final forbidden in [
        'postedAt.isBiggerOrEqualValue',
        'postedAt.isSmallerOrEqualValue',
        'postedAt.isBiggerThanValue',
        'shippedAt.isBiggerOrEqualValue',
        'posted_at >=',
        'posted_at <=',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'DAO membandingkan timestamp sebagai TEXT ($forbidden).',
        );
      }
      // And the Dart-side window is where it belongs.
      expect(readCodeOnly(driftRepository), contains('_withinPostedWindow'));
    });

    test('generated manager tetap dinonaktifkan', () {
      // The manager API is a second, unguarded write path into every table: it would let
      // any caller post a receipt, edit the lines of a final document, or hard delete
      // business rows — the exact things the DAO is written to make impossible.
      expect(
        readLibrarySource('build.yaml'),
        contains('generate_manager: false'),
      );
    });
  });

  group('kebersihan', () {
    test('tidak ada TODO pada aturan inti Good Receipt', () {
      for (final file in [...dartFilesUnder(featureRoot), tables, dao]) {
        expect(
          RegExp(r'\bTODO\b|\bFIXME\b').hasMatch(readLibrarySource(file)),
          isFalse,
          reason: '$file masih memuat TODO/FIXME pada jalur aturan inti.',
        );
      }
    });

    test('tidak ada paket notifikasi atau background task', () {
      // G-G6 asks for a reminder, and an in-app badge is one.
      final pubspec = readLibrarySource('pubspec.yaml');
      for (final forbidden in [
        'flutter_local_notifications',
        'awesome_notifications',
        'workmanager',
        'firebase_messaging',
      ]) {
        expect(pubspec.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('Good Receipt tidak bergantung pada fitur Distribusi', () {
      // Until Milestone 6 this asserted that the distribution tables did not exist at
      // all. They do now (schema v8), so the invariant worth keeping is the one that was
      // really behind it: the Good Receipt path must not reach *forward* into a feature
      // that comes after it. A receipt credits the branch store and stops there — what
      // the branch then does with that stock is the distribution's business, and a
      // dependency in this direction would make the two impossible to reason about
      // separately.
      for (final file in [...dartFilesUnder(featureRoot), dao]) {
        for (final import in importsOf(file)) {
          expect(
            import.contains('features/distribution/'),
            isFalse,
            reason: '\$file mengimpor fitur Distribusi (\$import).',
          );
        }
      }
    });

    test('tidak ada backend atau HTTP pada jalur Good Receipt', () {
      for (final file in [...dartFilesUnder(featureRoot), dao]) {
        for (final import in importsOf(file)) {
          expect(
            import.startsWith('package:http') ||
                import.startsWith('package:supabase') ||
                import.startsWith('package:dio'),
            isFalse,
            reason: '$file mengimpor jaringan ($import).',
          );
        }
      }
    });
  });
}
