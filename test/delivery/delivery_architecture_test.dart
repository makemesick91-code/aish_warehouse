import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// Architecture rules for Delivery Order, enforced against the source itself.
///
/// These are the invariants no runtime test can catch, because breaking them still
/// compiles and still passes: a widget reaching past the repository into a DAO, a
/// quantity path that quietly grows a `double`, a `:id` route that ships without a
/// guard, a generic status writer that lets any caller move any document anywhere.
/// Each of them would be caught in code review once and then slowly reintroduced;
/// here they fail the build.
void main() {
  const featureRoot = 'lib/features/delivery';
  const domainRoot = '$featureRoot/domain';
  const presentationRoot = '$featureRoot/presentation';
  const dao = 'lib/core/db/daos/delivery_order_dao.dart';
  const tables = 'lib/core/db/tables/delivery_tables.dart';
  const repository = '$domainRoot/repositories/delivery_order_repository.dart';
  const driftRepository =
      '$featureRoot/data/repositories/drift_delivery_order_repository.dart';
  const providers = '$presentationRoot/providers/delivery_providers.dart';

  group('lapisan presentation', () {
    test('halaman dan widget Delivery tidak mengimpor DAO', () {
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
      // `getDetail` is the unscoped read and it exists for the use cases, which
      // apply their guards afterwards and can afford to load first. A screen
      // cannot: by the time it could check, another branch's document is already in
      // the widget tree.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final unscoped in [
          '.getDetail(',
          '.summaryById(',
          '.listOrders(',
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

      expect(source, contains('watchListForWarehouse'));
      expect(source, contains('watchListForBranch'));
      expect(source, contains('watchForWarehouse'));
      expect(source, contains('watchForBranch'));
      expect(source, contains('actingBranchIdProvider'));
      expect(source, contains('actingRoleProvider'));
    });

    test('provider ber-scope layar memakai autoDispose', () {
      final source = readCodeOnly(providers);

      // A stream left subscribed after its screen closed is a cache entry that
      // outlives the session it was scoped for — the one way a branch scope can be
      // correct everywhere and still leak.
      for (final name in [
        'warehouseDeliveryListProvider',
        'branchDeliveryListProvider',
        'warehouseDeliveryDetailProvider',
        'branchDeliveryDetailProvider',
        'deliveriesOfPurchaseRequestProvider',
      ]) {
        expect(
          RegExp('$name\\s*=\\s*StreamProvider\\.autoDispose').hasMatch(source),
          isTrue,
          reason: '$name harus StreamProvider.autoDispose.',
        );
      }
      for (final name in [
        'deliveryAllocationDraftsProvider',
        'deliveryWaybillProvider',
        'purchaseRequestShipmentProgressProvider',
      ]) {
        expect(
          RegExp('$name\\s*=\\s*FutureProvider\\.autoDispose').hasMatch(source),
          isTrue,
          reason: '$name harus FutureProvider.autoDispose.',
        );
      }
    });

    test('provider Purchase Request ber-scope layar juga autoDispose', () {
      // The Milestone 3 residual risk this milestone closes: both list streams
      // stayed alive after their screens closed.
      final source = readCodeOnly(
        'lib/features/purchase_request/presentation/providers/'
        'purchase_request_providers.dart',
      );
      for (final name in [
        'branchPurchaseRequestListProvider',
        'warehousePurchaseRequestQueueProvider',
        'purchaseRequestDetailProvider',
        'warehousePurchaseRequestDetailProvider',
      ]) {
        expect(
          RegExp(
            '$name\\s*=\\s*\\n?\\s*StreamProvider\\.autoDispose',
          ).hasMatch(source),
          isTrue,
          reason: '$name harus StreamProvider.autoDispose.',
        );
      }
    });

    test('provider warehouse memeriksa peran sebelum baca lintas cabang', () {
      final source = readCodeOnly(providers);
      for (final name in [
        'warehouseDeliveryListProvider',
        'warehouseDeliveryDetailProvider',
      ]) {
        final start = source.indexOf(name);
        expect(start, greaterThan(-1), reason: 'Pola tes usang: $name.');
        final end = source.indexOf('final ', start + name.length);
        final body = source.substring(start, end > start ? end : source.length);
        expect(
          body,
          contains('UserRole.warehouse'),
          reason:
              'Baca tanpa scope cabang harus menolak aktor yang bukan '
              'Warehouse, bukan hanya mengandalkan route guard.',
        );
      }
    });

    test('layar cabang memakai provider ber-scope cabang', () {
      final code = readCodeOnly(
        '$presentationRoot/pages/branch_delivery_list_page.dart',
      );
      expect(code, contains('branchDeliveryListProvider'));
      expect(code, isNot(contains('warehouseDeliveryListProvider')));
    });

    test('layar warehouse tidak memakai sesi cabang sebagai pembatas', () {
      // The central warehouse serves every branch (spec §4.2); scoping its own list
      // to the acting branch would lock it out of its own queue.
      for (final file in [
        '$presentationRoot/pages/warehouse_delivery_order_list_page.dart',
        '$presentationRoot/pages/delivery_order_form_page.dart',
      ]) {
        final code = readCodeOnly(file);
        expect(
          code.contains('actingBranchIdProvider'),
          isFalse,
          reason: '$file membatasi layar warehouse dengan cabang sesi.',
        );
        expect(code.contains('branchDeliveryDetailProvider'), isFalse);
      }
    });

    test('tidak ada item picker bebas pada layar Delivery Order', () {
      // G-D4 by design: every card descends from a Purchase Request line, so there
      // is no control that could express an item outside the request.
      for (final file in dartFilesUnder(presentationRoot)) {
        final code = readCodeOnly(file);
        for (final forbidden in [
          'SearchableItemDropdown',
          'PurchaseRequestItemPicker',
          'searchAddableItems',
          'activeItems()',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menyediakan pemilih barang bebas ($forbidden).',
          );
        }
      }
    });

    test('setiap rute ber-:id dibungkus penjaga akses', () {
      final router = readCodeOnly('lib/app/router.dart');

      // Stated as an invariant over the routes that exist, not as a fixed count: a
      // count would keep passing the day somebody adds
      // `/warehouse/delivery-orders/:id/cetak` without a guard. Reading
      // `pathParameters['id']` is what makes a route document-specific, so every
      // such builder must be wrapped.
      // `id` and `deliveryOrderId` both name a *document*, so both make a route
      // document-specific and both must be wrapped. `purchaseRequestId` does not:
      // `/warehouse/delivery-orders/new/{pr}` creates a document rather than
      // opening one, and its section guard is the right shape for it.
      final idRoutes = RegExp(
        r"pathParameters\['(?:id|deliveryOrderId)'\]",
      ).allMatches(router).length;

      expect(idRoutes, greaterThan(0), reason: 'Pola tes usang.');
      // Checked per occurrence rather than by comparing two counts — see
      // [unguardedIdRoutes] for why the count stopped being able to express
      // this once a section guard began covering an `:id` route.
      expect(
        unguardedIdRoutes(router),
        isEmpty,
        reason: 'Ada rute ber-:id yang tidak dibungkus penjaga akses.',
      );
      for (final kind in [
        'DeliveryRouteKind.warehouseDocument',
        'DeliveryRouteKind.warehouseDraft',
        'DeliveryRouteKind.warehouseWaybill',
        'DeliveryRouteKind.branchDocument',
        'DeliveryRouteKind.branchWaybill',
      ]) {
        expect(router, contains(kind));
      }
    });

    test('rute bagian Delivery juga dibungkus penjaga bagian', () {
      final router = readCodeOnly('lib/app/router.dart');

      expect(router, contains('DeliverySectionGuard'));
      expect(router, contains('DeliveryRouteKind.warehouseList'));
      expect(router, contains('DeliveryRouteKind.warehouseCreate'));
      expect(router, contains('DeliveryRouteKind.branchList'));
    });

    test('rute create memakai parameter PR, bukan id dokumen', () {
      // `/warehouse/delivery-orders/new/:purchaseRequestId` names a request, not a
      // shipment — and it is declared before the `:id` pattern so the literal `new`
      // segment wins.
      final router = readCodeOnly('lib/app/router.dart');
      expect(router, contains("pathParameters['purchaseRequestId']"));

      final routes = readCodeOnly('lib/app/routes.dart');
      expect(
        routes,
        contains("warehouseDeliveryOrderNew = 'new/:purchaseRequestId'"),
      );
    });
  });

  group('lapisan domain', () {
    test('domain Delivery tidak bergantung pada drift', () {
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

    test('domain Delivery tidak menyentuh BuildContext atau Flutter', () {
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

    test('domain Delivery memakai Quantity, bukan milli-unit mentah', () {
      for (final file in dartFilesUnder(domainRoot)) {
        expect(
          readLibrarySource(file).contains('milliUnits'),
          isFalse,
          reason:
              '$file menyentuh milli-unit. Konversi hanya boleh terjadi di '
              'repository (Q-4).',
        );
      }
    });

    test('tidak ada double pada jalur kuantitas Delivery', () {
      // A `double` anywhere on this path is the bug the fixed-point type exists to
      // prevent: a cumulative total compared in floating point would eventually
      // disagree with the sum of its own parts.
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

    test('kebijakan Delivery bebas dari Flutter, database dan async', () {
      // A rule that needs a widget tree or a query to be evaluated cannot be reused
      // by the router, the providers, the use cases and the tests alike.
      for (final file in [
        '$domainRoot/services/delivery_order_state_policy.dart',
        '$domainRoot/services/delivery_quantity_policy.dart',
        '$domainRoot/services/delivery_fefo_policy.dart',
        '$domainRoot/services/delivery_expiry_policy.dart',
        '$domainRoot/services/delivery_order_access_policy.dart',
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

    test('FEFO tidak dinilai dengan membandingkan hasil alokasi kanonik', () {
      // Two batches with the same expiry date are equally correct FEFO choices; the
      // canonical answer has to pick one, and diffing against it would demand a
      // written reason from an officer who picked the other. The rule is stated
      // directly instead.
      final source = readCodeOnly(
        '$domainRoot/services/delivery_fefo_policy.dart',
      );
      final start = source.indexOf('static List<FefoViolation> violations(');
      expect(start, greaterThan(-1), reason: 'Pola tes usang.');
      final body = source.substring(start);

      expect(
        body.contains('allocate('),
        isFalse,
        reason:
            'Deteksi pelanggaran tidak boleh memanggil alokasi kanonik; '
            'expiry yang sama akan salah dianggap pelanggaran.',
      );
      expect(body, contains('isBeforeDate'));
    });

    test('kebijakan expiry memakai tanggal operasional, bukan UTC mentah', () {
      final source = readCodeOnly(
        '$domainRoot/services/delivery_expiry_policy.dart',
      );
      expect(source, contains('AppTimeZone.operationalDate'));
      expect(source, contains('DateOnly'));
      // `<` and not `<=`: the specification says "sisa umur < expiry_alert_days".
      expect(source, contains('< expiryAlertDays'));
    });
  });

  group('dokumen final dan penulisan terjaga', () {
    test('DAO tidak menawarkan penulis generik', () {
      final source = readCodeOnly(dao);

      // Every header write is guarded by a status predicate in the same statement; a
      // bare `update(...).write(...)` would not be.
      expect(
        RegExp(r'update\(deliveryOrders\)\)\s*\.write').hasMatch(source),
        isFalse,
      );
      expect(
        RegExp(r'update\(deliveryOrderLines\)\)\s*\.write').hasMatch(source),
        isFalse,
      );
      expect(source, isNot(contains('Future<int> setStatus')));
      expect(source, isNot(contains('Future<int> updateStatus')));
      // And nothing is ever hard deleted (G-A5).
      expect(source, isNot(contains('delete(deliveryOrders)')));
      expect(source, isNot(contains('delete(deliveryOrderLines)')));
      expect(source, isNot(contains('delete(purchaseRequests)')));
    });

    test('setiap penulis baris dijaga status preparing', () {
      final source = readCodeOnly(dao);

      // The guard is `status = 'preparing'` inside the statement, evaluated by
      // SQLite in the same breath as the write — not a Dart check above it with a
      // gap in between.
      final guarded = "WHERE status = 'preparing' AND deleted_at IS NULL";
      final writers = RegExp(
        r'UPDATE delivery_order_lines ',
      ).allMatches(source).length;
      expect(writers, greaterThan(0), reason: 'Pola tes usang.');
      expect(
        guarded.allMatches(source).length,
        writers,
        reason:
            'Ditemukan $writers penulis baris tetapi tidak semuanya dijaga '
            'status preparing.',
      );
    });

    test('setiap transisi status menyebut status asalnya', () {
      final source = readCodeOnly(dao);

      // `markShipped` moves from `preparing`; the two Purchase Request writers move
      // from `submitted` and `processing`. Each predicate travels into the same
      // statement as the write, so a racing device produces one transition and one
      // zero.
      expect(
        source,
        contains('t.status.equalsValue(DeliveryOrderStatus.preparing)'),
      );
      expect(
        source,
        contains('t.status.equalsValue(PurchaseRequestStatus.submitted)'),
      );
      expect(
        source,
        contains('t.status.equalsValue(PurchaseRequestStatus.processing)'),
      );
    });

    test('repository tidak menawarkan update dokumen bebas', () {
      final source = readCodeOnly(repository);

      expect(source, isNot(contains('Future<void> update(DeliveryOrder')));
      expect(source, isNot(contains('Future<bool> setStatus')));
      // Only the specific guarded operations exist.
      expect(source, contains('updatePreparingLine'));
      expect(source, contains('replacePreparingLines'));
      expect(source, contains('markShipped'));
    });

    test('penulis baris tidak menerima pr_line_id atau item_id', () {
      // G-D4: which requested position a line satisfies, and which item it moves, is
      // decided when the line is created. Repointing it is expressed as removing it
      // and allocating another.
      final source = readCodeOnly(repository);
      final start = source.indexOf('Future<bool> updatePreparingLine(');
      expect(start, greaterThan(-1), reason: 'Pola tes usang.');
      final end = source.indexOf('});', start);
      final body = source.substring(start, end);

      expect(body, isNot(contains('prLineId')));
      expect(body, isNot(contains('itemId')));
    });

    test('baris dokumen shipped tidak dapat diedit', () {
      final source = readCodeOnly(dao);

      // Every line writer is scoped to a `preparing` parent, so there is no
      // statement that could reach a posted allocation.
      for (final writer in ['UPDATE delivery_order_lines']) {
        for (final match in RegExp(
          '$writer.*?;',
          dotAll: true,
        ).allMatches(source)) {
          expect(
            match.group(0),
            contains("status = 'preparing'"),
            reason: 'Penulis baris tanpa penjaga preparing: ${match.group(0)}',
          );
        }
      }
    });

    test('tidak ada penulis status received', () {
      for (final file in [
        dao,
        repository,
        driftRepository,
        providers,
        ...dartFilesUnder('$domainRoot/use_cases'),
      ]) {
        final code = readCodeOnly(file);
        expect(
          RegExp(
            r'(status:\s*(const\s+)?Value\(DeliveryOrderStatus\.received|'
            r'to:\s*DeliveryOrderStatus\.received|markReceived)',
          ).hasMatch(code),
          isFalse,
          reason: '$file dapat menulis status received.',
        );
      }
    });

    test('tidak ada use case publik untuk received', () {
      // Naming it would be a button waiting to be wired up before the document that
      // justifies it exists.
      for (final file in dartFilesUnder(featureRoot)) {
        expect(
          readLibrarySource(file).contains('MarkDeliveryOrderReceivedUseCase'),
          isFalse,
          reason: '$file mendeklarasikan use case received.',
        );
      }
    });
  });

  group('ledger dan schema', () {
    test('ledger hanya ditulis lewat Inventory service', () {
      // The Delivery Order path may *ask* the posting service to write; it may not
      // write itself. `appendMovement` and `setBalanceQty` belong to the inventory
      // repository alone (G-A1).
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

    test('pengiriman memposting lewat metode transaction-aware', () {
      final code = readCodeOnly(
        '$domainRoot/use_cases/ship_delivery_order_use_case.dart',
      );

      expect(code, contains('postShipmentInTransaction'));
      // Not the per-line transfer method, which opens a transaction of its own and
      // would make one commit per line.
      expect(code, isNot(contains('postTransfer')));
      expect(code, isNot(contains('postInboundWarehouse')));
      // And exactly one transaction wraps the whole thing.
      expect(
        'runInTransaction'.allMatches(code).length,
        1,
        reason: 'Pengiriman harus memiliki tepat satu transaksi luar.',
      );
    });

    test('movement shipment memakai referensi DO dan tanpa lokasi tujuan', () {
      final code = readCodeOnly(
        'lib/features/inventory/domain/services/stock_posting_service.dart',
      );
      final start = code.indexOf('postShipmentInTransaction');
      expect(start, greaterThan(-1), reason: 'Pola tes usang.');
      final body = code.substring(start);

      expect(body, contains('StockMovementType.shipment'));
      expect(body, contains('RefDocType.deliveryOrder'));
      expect(body, contains('refDocId: deliveryOrderId'));
      // Spec §2.5: the branch gains nothing until Good Receipt posts.
      expect(body, contains('toLocationId: null'));
    });

    test('tabel Delivery tidak memakai REAL untuk kuantitas', () {
      final source = readLibrarySource(tables);

      expect(source, contains('IntColumn get shippedQty'));
      expect(
        RegExp(r'RealColumn').hasMatch(source),
        isFalse,
        reason: 'Q-3: REAL dilarang pada kolom kuantitas.',
      );
    });

    test('index unik parsial alokasi dinyatakan pada tabel', () {
      final source = readLibrarySource(tables);

      expect(source, contains('idx_delivery_order_lines_batched'));
      expect(source, contains('idx_delivery_order_lines_unbatched'));
      expect(source, contains('idx_delivery_orders_doc_number'));
      // Uniqueness applies to live rows, so a removed allocation does not hold its
      // position hostage.
      expect(
        'deleted_at IS NULL'.allMatches(source).length,
        greaterThanOrEqualTo(3),
      );
    });

    test('tidak ada index unik yang membatasi satu DO per PR', () {
      // Spec §2.3 allows one Purchase Request to have several Delivery Orders, and
      // partial shipment depends on it.
      final source = readLibrarySource(tables);
      expect(
        RegExp(r'UNIQUE INDEX[^;]*delivery_orders \(pr_id\)').hasMatch(source),
        isFalse,
      );
      expect(
        source,
        isNot(
          contains('prId => text().references(PurchaseRequests, #id).unique()'),
        ),
      );
    });

    test('migrasi v6 memakai SQL index yang dibekukan', () {
      // Comment-stripped, because the migration file *explains* at length why the
      // list is not derived from `allSchemaEntities`.
      final source = readCodeOnly('lib/core/db/app_database.dart');

      expect(source, contains('_v6DeliveryOrderIndexes'));
      expect(source, contains('if (from < 6)'));
      // Bumped by every later milestone; what this test is really pinning is
      // that the v6 *step* is still there, still frozen, and still additive.
      expect(source, contains('int get schemaVersion => 14;'));
      expect(
        source.contains('allSchemaEntities'),
        isFalse,
        reason:
            'Langkah migrasi harus tetap melakukan apa yang ia lakukan saat '
            'dirilis.',
      );

      // v6 must touch nothing an earlier version owns.
      final v6Start = source.indexOf('if (from < 6)');
      final v6End = source.indexOf('    },', v6Start);
      final v6Block = source.substring(v6Start, v6End);
      for (final untouched in [
        'stockOpnames',
        'stock_balances',
        'stock_movements',
        'purchaseRequests',
        'alterTable',
      ]) {
        expect(
          v6Block.contains(untouched),
          isFalse,
          reason: 'Blok migrasi v6 menyentuh $untouched.',
        );
      }
    });

    test('generated manager tetap dinonaktifkan', () {
      // The manager API is a second, unguarded write path into every table: it would
      // let any caller mark a shipment `received`, edit the lines of a posted
      // document, or hard delete business rows — the exact things the DAO is written
      // to make impossible.
      expect(
        readLibrarySource('build.yaml'),
        contains('generate_manager: false'),
      );
    });
  });

  test('tidak ada TODO pada aturan inti Delivery Order', () {
    for (final file in [...dartFilesUnder(featureRoot), tables, dao]) {
      expect(
        RegExp(r'\bTODO\b|\bFIXME\b').hasMatch(readLibrarySource(file)),
        isFalse,
        reason: '$file masih memuat TODO/FIXME pada jalur aturan inti.',
      );
    }
  });
}
