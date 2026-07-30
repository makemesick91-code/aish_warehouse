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

  group('otorisasi baca', () {
    /// Source with `//` comments removed, so a rule can be *explained* in prose
    /// without the test that enforces it reading the explanation as a
    /// violation.
    String codeOnly(File file) => file
        .readAsStringSync()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    test('halaman opname tidak memanggil DAO atau repository langsung', () {
      for (final file in dartFilesUnder('lib/features/opname/presentation')) {
        final imports = importsOf(file);
        expect(
          imports.any((import) => import.contains('db/daos/')),
          isFalse,
          reason: '${file.path} memanggil DAO langsung dari UI.',
        );
        // Pages go through providers; only the providers file wires the
        // repository, and even it never constructs a DAO itself.
        if (file.path.contains('/pages/') || file.path.contains('/widgets/')) {
          expect(
            imports.any((import) => import.contains('data/repositories/')),
            isFalse,
            reason:
                '${file.path} mengimpor repository konkret. Halaman harus '
                'lewat provider.',
          );
        }
      }
    });

    test('presentation memakai read yang ter-scope cabang', () {
      // `getDetail`/`watchDetail` are the unscoped reads, and they exist for
      // the use cases — which apply `requireSameBranch` afterwards and can
      // therefore afford to load first. A screen cannot: by the time it could
      // check, another branch's document is already in the widget tree. This
      // is the rule that keeps the two apart.
      for (final file in dartFilesUnder('lib/features/opname/presentation')) {
        final code = codeOnly(file);
        for (final unscoped in [
          '.watchDetail(',
          '.getDetail(',
          '.summaryById(',
        ]) {
          expect(
            code.contains(unscoped),
            isFalse,
            reason:
                '${file.path} memakai baca tanpa scope cabang ($unscoped). '
                'Gunakan watchDetailForBranch/getDetailForBranch.',
          );
        }
      }
    });

    test('provider detail mengikat cabang dari sesi', () {
      final source = codeOnly(
        File(
          'lib/features/opname/presentation/providers/opname_providers.dart',
        ),
      );

      // The branch must come from the session on every build, not from a
      // parameter a caller could pass at will and not from a value captured
      // once — otherwise switching user would keep serving the old branch.
      expect(source, contains('watchDetailForBranch'));
      expect(source, contains('currentSessionValueProvider'));
      expect(
        RegExp(
          r'opnameDetailProvider\s*=\s*StreamProvider\.autoDispose',
        ).hasMatch(source),
        isTrue,
        reason:
            'opnameDetailProvider harus autoDispose agar dokumen yang pernah '
            'dibuka tidak tertinggal di cache setelah sesi berganti.',
      );
    });

    test('setiap rute ber-:id dibungkus penjaga akses', () {
      final router = codeOnly(File('lib/app/router.dart'));

      // Stated as an invariant over the routes that exist, not as a fixed
      // count of guards. A count would keep passing the day somebody adds
      // `/opname/:id/cetak` without a guard — precisely the "new call site
      // misses it" failure the guard exists to prevent. Reading
      // `pathParameters['id']` is what makes a route document-specific, so
      // every such builder must be wrapped.
      // `id` and `deliveryOrderId` both name a *document*, so both make a route
      // document-specific and both must be wrapped. `purchaseRequestId` does not:
      // `/warehouse/delivery-orders/new/{pr}` creates a document rather than
      // opening one, and its section guard is the right shape for it.
      final idRoutes = RegExp(
        r"pathParameters\['(?:id|deliveryOrderId)'\]",
      ).allMatches(router).length;
      expect(idRoutes, greaterThan(0), reason: 'Pola tes usang.');
      // Matched by shape rather than by name, so a third module's guard counts
      // automatically instead of quietly lowering the total. `OpnameRouteGuard(`
      // and `PurchaseRequestRouteGuard(` both match; an import of the file does
      // not.
      final guards = RegExp(r'\w*RouteGuard\(').allMatches(router).length;
      expect(
        guards,
        idRoutes,
        reason:
            'Ditemukan $idRoutes rute ber-:id tetapi hanya $guards penjaga '
            'dokumen. Setiap rute dokumen harus dibungkus penjaga.',
      );
      expect(router, contains('OpnameRouteKind.document'));
      expect(router, contains('OpnameRouteKind.reviewDocument'));
      expect(router, contains('PurchaseRequestRouteKind.branchDocument'));
      expect(router, contains('PurchaseRequestRouteKind.branchDraft'));
      expect(router, contains('PurchaseRequestRouteKind.warehouseDocument'));
    });

    test('kebijakan akses bebas dari Flutter dan database', () {
      final file = File(
        'lib/features/opname/domain/services/opname_access_policy.dart',
      );
      final source = file.readAsStringSync();

      // A rule that needs a widget tree or a query to be evaluated cannot be
      // reused by the router, the providers and the tests alike.
      expect(source, isNot(contains("package:flutter/")));
      expect(source, isNot(contains("package:drift/")));
      expect(source, isNot(contains('BuildContext')));
      expect(source, isNot(contains('Future<')));
    });
  });

  group('pemisahan lookup aktif dan historis', () {
    test('review memakai lookup historis, bukan lookup aktif', () {
      final source = File(
        'lib/features/opname/domain/use_cases/'
        'review_stock_opname_use_case.dart',
      ).readAsStringSync();

      expect(source, contains('requireHistoricalRoom('));
      expect(source, contains('requireHistoricalRoomLocation('));
      expect(source, contains('requireHistoricalLineBatch('));
      expect(source, contains('requireEveryLineLoaded('));

      // Every guard that demands *active* master data, named explicitly.
      // Reaching for any of them here is what would strand a submitted
      // document whose room, location or item was retired after the count.
      for (final creationGuard in [
        'requireRoomInActorBranch',
        'requireRoomLocation',
        'requireActiveItem',
        'requireValidItemBatch',
        // `requireItem` is not an active-only guard, but it reports a missing
        // row as `EntityNotFoundFailure` — which reads as "wrong id" rather
        // than "this document is stuck and needs an administrator".
        'requireItem',
      ]) {
        expect(
          RegExp('$creationGuard\\s*\\(').hasMatch(source),
          isFalse,
          reason:
              'Review dokumen submitted tidak boleh memakai $creationGuard: '
              'penjaga itu untuk pekerjaan baru, bukan untuk menyelesaikan '
              'dokumen historis.',
        );
      }
    });

    test('pembuatan draft tetap menuntut master aktif', () {
      final guards = File(
        'lib/features/opname/domain/use_cases/opname_guards.dart',
      ).readAsStringSync();

      // The creation path still reads through the `active…` repository methods
      // and still rejects a deactivated room.
      expect(guards, contains('activeRoomById'));
      expect(guards, contains('activeRoomLocation'));
      expect(guards, contains('InactiveEntityFailure'));
    });

    test('tidak ada parameter boolean ambigu pada lookup master', () {
      final repository = File(
        'lib/features/master/domain/repositories/master_data_repository.dart',
      ).readAsStringSync();

      // §7.4: the two lookup modes are separate named methods, so a call site
      // states which one it means instead of hiding it in a flag.
      for (final ambiguous in [
        'includeEverything',
        'includeDeleted',
        'includeInactive',
        'bool includeAll',
      ]) {
        expect(repository, isNot(contains(ambiguous)));
      }
      expect(repository, contains('historicalRoomById'));
      expect(repository, contains('historicalRoomLocation'));
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
