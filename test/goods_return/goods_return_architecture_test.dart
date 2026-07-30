import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// Invariants no runtime test can catch (§50).
///
/// Every rule here stays true while the code still compiles and every other test still
/// passes — which is exactly why they are asserted against the *source*. A quantity path
/// that grows a `double`, a widget reaching past the repository into a DAO, a line
/// writer added "just for the editor", a `receive` that starts its own transaction: each
/// is a one-line change that would survive code review once and then never be noticed
/// again.
void main() {
  const featureRoot = 'lib/features/goods_return';
  const domainRoot = '$featureRoot/domain';
  const dataRoot = '$featureRoot/data';
  const presentationRoot = '$featureRoot/presentation';
  const dao = 'lib/core/db/daos/goods_return_dao.dart';
  const tables = 'lib/core/db/tables/goods_return_tables.dart';
  const database = 'lib/core/db/app_database.dart';
  const posting =
      'lib/features/inventory/domain/services/stock_posting_service.dart';
  const presenter =
      'lib/features/inventory/presentation/stock_movement_presenter.dart';
  const routes = 'lib/app/routes.dart';
  const router = 'lib/app/router.dart';
  const guard = 'lib/app/guards/goods_return_route_guard.dart';

  /// The body of `postGoodsReturnLinesInTransaction`, **comments stripped**.
  ///
  /// Stripping matters: the method's own comments discuss the very identifiers these
  /// tests forbid — *"Note what is absent: no `_rejectExpiredBatch`"* — so reading the
  /// raw source would make the explanation of a rule read as a violation of it. The
  /// closing marker is the next method's signature rather than its doc comment, for the
  /// same reason.
  String goodsReturnPostingBody() {
    final code = readCodeOnly(posting);
    final start = code.indexOf(
      'Future<List<InventoryMovement>> postGoodsReturnLinesInTransaction(',
    );
    expect(start, greaterThan(-1), reason: 'Metode posting retur tidak ada.');
    final end = code.indexOf('Future<InventoryMovement> postReversal(', start);
    expect(end, greaterThan(start), reason: 'Batas metode tidak ditemukan.');
    return code.substring(start, end);
  }

  group('lapisan', () {
    test('presentation tidak pernah menyentuh DAO atau drift', () {
      for (final file in dartFilesUnder(presentationRoot)) {
        final imports = importsOf(file);
        expect(
          imports.any((path) => path.contains('core/db/daos')),
          isFalse,
          reason: '$file mengimpor DAO langsung.',
        );
        expect(
          imports.any((path) => path.startsWith('package:drift')),
          isFalse,
          reason: '$file mengimpor drift.',
        );
        expect(
          imports.any((path) => path.contains('core/db/app_database')),
          isFalse,
          reason: '$file mengimpor kelas database.',
        );
      }
    });

    test('domain tidak mengimpor drift, Flutter atau Riverpod', () {
      for (final file in dartFilesUnder(domainRoot)) {
        final imports = importsOf(file);
        for (final forbidden in const [
          'package:drift',
          'package:flutter/',
          'package:flutter_riverpod',
        ]) {
          expect(
            imports.any((path) => path.startsWith(forbidden)),
            isFalse,
            reason: '$file mengimpor $forbidden.',
          );
        }
      }
    });

    test('hanya repository drift yang menyentuh milli-unit', () {
      // Q-4: the conversion lives in exactly one file, so nothing above it can get the
      // scale wrong.
      for (final file in [
        ...dartFilesUnder(domainRoot),
        ...dartFilesUnder(presentationRoot),
      ]) {
        expect(
          readCodeOnly(file).contains('milliUnits'),
          isFalse,
          reason: '$file bekerja pada milli-unit, bukan Quantity.',
        );
      }
      expect(
        readCodeOnly(
          '$dataRoot/repositories/drift_goods_return_repository.dart',
        ).contains('milliUnits'),
        isTrue,
      );
    });

    test('tidak ada double di jalur kuantitas', () {
      for (final file in [...dartFilesUnder(featureRoot), dao, tables]) {
        final code = readCodeOnly(file);
        for (final pattern in const [
          'double qty',
          'double get qty',
          'qty.toDouble',
          'RealColumn',
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason: '$file memakai "$pattern" pada jalur kuantitas.',
          );
        }
      }
    });

    test('kuantitas disimpan sebagai INTEGER', () {
      final source = readLibrarySource(tables);
      expect(source, contains('IntColumn get qty => integer()'));
      expect(source, isNot(contains('RealColumn')));
    });
  });

  group('baris tidak dapat ditulis setelah dibuat', () {
    test('DAO hanya punya satu penulis baris', () {
      final code = readCodeOnly(dao);
      // The single writer, and the name is deliberate: it is the create path's.
      expect(code, contains('Future<void> insertLines('));
      expect(code, contains('batch.insertAll(goodsReturnLines'));

      for (final forbidden in const [
        'update(goodsReturnLines)',
        'delete(goodsReturnLines)',
        'UPDATE goods_return_lines',
        'DELETE FROM goods_return_lines',
        'updateLine',
        'softDeleteLine',
        'removeLine',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'DAO Retur menyediakan penulis baris "$forbidden" (§18).',
        );
      }
    });

    test('repository tidak menawarkan add, update atau remove baris', () {
      final code = readCodeOnly(
        '$domainRoot/repositories/goods_return_repository.dart',
      );
      for (final forbidden in const [
        'addDraftLine',
        'addLine',
        'updateDraftLine',
        'updateLine',
        'removeDraftLine',
        'removeLine',
        'deleteLine',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: 'Kontrak Retur menyediakan "$forbidden" (§25).',
        );
      }
      expect(code, contains('createFromGoodReceipt'));
    });

    test('tidak ada use case yang mengubah baris', () {
      final files = dartFilesUnder('$domainRoot/use_cases');
      expect(files, hasLength(5));
      final names = files.map((file) => file.split('/').last).toSet();
      expect(names, {
        'goods_return_guards.dart',
        'create_goods_return_use_case.dart',
        'update_goods_return_note_use_case.dart',
        'ship_goods_return_use_case.dart',
        'receive_goods_return_use_case.dart',
      });
    });
  });

  group('state machine', () {
    test('hanya ship use case yang menulis shipped', () {
      const writer = '$domainRoot/use_cases/ship_goods_return_use_case.dart';
      // The contract and its drift implementation legitimately *declare* the guarded
      // write — that is what makes it callable at all. The rule is about who calls it:
      // exactly one use case, and no screen, provider or route.
      for (final file in [
        ...dartFilesUnder('$domainRoot/use_cases'),
        ...dartFilesUnder(presentationRoot),
        ...dartFilesUnder('lib/app'),
      ]) {
        if (file.replaceAll(r'\', '/') == writer) continue;
        expect(
          readCodeOnly(file).contains('markShipped('),
          isFalse,
          reason: '$file dapat menandai retur dikirim.',
        );
      }
      expect(readCodeOnly(writer), contains('markShipped('));
    });

    test('hanya receive use case yang menulis received', () {
      const writer = '$domainRoot/use_cases/receive_goods_return_use_case.dart';
      for (final file in [
        ...dartFilesUnder('$domainRoot/use_cases'),
        ...dartFilesUnder(presentationRoot),
        ...dartFilesUnder('lib/app'),
      ]) {
        if (file.replaceAll(r'\', '/') == writer) continue;
        expect(
          readCodeOnly(file).contains('markReceived('),
          isFalse,
          reason: '$file dapat menandai retur diterima.',
        );
      }
      expect(readCodeOnly(writer), contains('markReceived('));
    });

    test('tidak ada updateStatus generik, cancel, unship atau unreceive', () {
      for (final file in [...dartFilesUnder(featureRoot), dao]) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'setStatus(',
          'updateStatus(',
          'cancelGoodsReturn',
          'unship',
          'unShip',
          'unreceive',
          'unReceive',
          'reopenGoodsReturn',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menyediakan "$forbidden" (§14/§24).',
          );
        }
      }
    });

    test('tidak ada retur parsial atau penerimaan parsial', () {
      // `receivedQty` is deliberately **not** forbidden outright: the repository maps a
      // *Good Receipt* line's accepted quantity into `RejectedGoodReceiptPosition`, and
      // the eligibility rule needs it precisely to verify that a rejection accepted
      // nothing (§16). What must not exist is a *return* line carrying one — and the
      // table has no such column, which the schema test asserts.
      for (final file in dartFilesUnder(featureRoot)) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'partialReturn',
          'partialReceive',
          'selectedLineIds',
          'lineSelection',
          'receivedQtyController',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file membuka retur/penerimaan parsial (§16.16).',
          );
        }
      }
    });
  });

  group('ledger', () {
    test('hanya receive use case yang memanggil posting', () {
      const writer = '$domainRoot/use_cases/receive_goods_return_use_case.dart';
      for (final file in dartFilesUnder(featureRoot)) {
        if (file.replaceAll(r'\', '/') == writer) continue;
        expect(
          readCodeOnly(file).contains('postGoodsReturnLinesInTransaction'),
          isFalse,
          reason: '$file memposting ledger retur.',
        );
      }
      expect(
        readCodeOnly(writer),
        contains('postGoodsReturnLinesInTransaction'),
      );
    });

    test('ship use case tidak menyentuh StockPostingService sama sekali', () {
      final code = readCodeOnly(
        '$domainRoot/use_cases/ship_goods_return_use_case.dart',
      );
      expect(code, isNot(contains('StockPostingService')));
      expect(code, isNot(contains('posting')));
      expect(
        importsOf(
          '$domainRoot/use_cases/ship_goods_return_use_case.dart',
        ).any((path) => path.contains('stock_posting_service')),
        isFalse,
        reason: 'Pengiriman tidak menulis ledger (§20).',
      );
    });

    test('posting retur tidak membuka transaksi sendiri', () {
      final body = goodsReturnPostingBody();

      expect(
        body.contains('_inventory.runInTransaction'),
        isFalse,
        reason:
            'Transaksi dimiliki ReceiveGoodsReturnUseCase; membuka satu lagi '
            'akan memutus atomisitas (§23).',
      );
    });

    test('movement retur selalu NULL → Warehouse', () {
      final body = goodsReturnPostingBody();

      expect(body, contains('fromLocationId: null'));
      expect(body, contains('toLocationId: warehouseLocationId'));
      expect(body, contains('StockMovementType.itemReturn'));
      expect(body, contains('RefDocType.goodsReturn'));
      expect(body, contains('StockLocationType.warehouse'));
      // Only a credit — a return never debits anything.
      expect(body, contains('_increase('));
      expect(
        body.contains('_decrease('),
        isFalse,
        reason:
            'Barang rejected tidak pernah menjadi saldo cabang, jadi tidak ada '
            'yang bisa dikurangi (§22).',
      );
    });

    test('jalur retur tidak memakai penghalang expiry outbound', () {
      final body = goodsReturnPostingBody();

      // G-E5 makes an expired batch a legitimate rejection, and §36 lets it come home.
      expect(
        body.contains('_rejectExpiredBatch'),
        isFalse,
        reason: 'Retur harus menerima batch kedaluwarsa (§36).',
      );
      for (final file in dartFilesUnder(featureRoot)) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'ExpiredBatchFailure',
          'rejectExpiredBatch',
          'allocateFefo',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file memblokir batch kedaluwarsa pada jalur Retur.',
          );
        }
      }
    });

    test('tidak ada mutasi saldo langsung di fitur Retur', () {
      for (final file in [...dartFilesUnder(featureRoot), dao]) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'setBalanceQty',
          'stockBalances)',
          'UPDATE stock_balances',
          'INSERT INTO stock_balances',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menulis saldo langsung.',
          );
        }
      }
    });

    test('movement_type return dan ref_doc_type RET terdaftar', () {
      final enums = readLibrarySource('lib/core/enums/app_enums.dart');
      expect(enums, contains("itemReturn('return')"));
      expect(enums, contains("static const goodsReturn = 'RET'"));

      final presenterSource = readLibrarySource(presenter);
      expect(
        presenterSource,
        contains("StockMovementType.itemReturn => 'Retur ke Warehouse'"),
      );
      expect(
        presenterSource,
        contains("RefDocType.goodsReturn => 'dokumen Retur'"),
      );
    });

    test('return bukan perpindahan antar lokasi', () {
      // `postTransfer` demands two locations; a return has one leg.
      final enums = readCodeOnly('lib/core/enums/app_enums.dart');
      final start = enums.indexOf('bool get isLocationToLocation');
      final end = enums.indexOf(';', start);
      final body = enums.substring(start, end);
      expect(body.contains('itemReturn'), isFalse);
    });
  });

  group('kelayakan', () {
    test('shortage tidak pernah menjadi retur', () {
      final policy = readLibrarySource(
        '$domainRoot/services/goods_return_eligibility_policy.dart',
      );
      expect(policy, contains('static bool isShortageReturnable() => false;'));
      expect(policy, contains('GoodReceiptLineStatus.rejected'));

      // No query anywhere in the feature admits a `checked` line.
      for (final file in [...dartFilesUnder(featureRoot), dao]) {
        final code = readCodeOnly(file);
        expect(
          code.contains('GoodReceiptLineStatus.checked'),
          isFalse,
          reason: '$file memperlakukan baris checked sebagai kandidat retur.',
        );
      }
    });

    test('hanya GR posted yang memenuhi syarat', () {
      final code = readCodeOnly(dao);
      expect(code, contains('GoodReceiptStatus.posted'));
      expect(
        readLibrarySource(
          '$domainRoot/services/goods_return_eligibility_policy.dart',
        ),
        contains('requiredReceiptStatus =\n      GoodReceiptStatus.posted'),
      );
    });

    test('satu GR satu retur ditegakkan index tak berklausa', () {
      final source = readLibrarySource(tables);
      expect(source, contains('CREATE UNIQUE INDEX idx_goods_returns_gr'));
      expect(
        source,
        contains('CREATE UNIQUE INDEX idx_goods_return_lines_gr_line_unique'),
      );

      // No `WHERE deleted_at IS NULL` on either — a soft delete must not free the slot.
      for (final name in const [
        'idx_goods_returns_gr',
        'idx_goods_returns_doc_number',
        'idx_goods_return_lines_gr_line_unique',
        'idx_goods_return_lines_unique',
      ]) {
        final start = source.indexOf('CREATE UNIQUE INDEX $name');
        expect(start, greaterThan(-1), reason: '$name tidak dideklarasikan.');
        final end = source.indexOf(';', start);
        expect(
          source.substring(start, end).toLowerCase().contains('where'),
          isFalse,
          reason: '$name partial: soft delete akan membebaskan slot.',
        );
      }
    });
  });

  group('waktu', () {
    test('tidak ada perbandingan timestamp leksikal di SQL', () {
      for (final file in [dao, tables]) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'shipped_at >=',
          'received_at >=',
          'created_at >=',
          'shipped_at <=',
          'received_at <=',
          'posted_at >=',
          'posted_at <=',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file membandingkan timestamp TEXT (§39).',
          );
        }
      }
    });

    test('tidak ada toLocal di jalur Retur', () {
      for (final file in [...dartFilesUnder(featureRoot), dao, guard]) {
        expect(
          readCodeOnly(file).contains('.toLocal()'),
          isFalse,
          reason: '$file mengubah instant ke zona perangkat (T-1/T-4).',
        );
      }
    });

    test('urutan transisi memakai DocumentTimestampPolicy', () {
      final guards = readLibrarySource(
        '$domainRoot/use_cases/goods_return_guards.dart',
      );
      expect(
        guards,
        contains('DocumentTimestampPolicy.requireShipNotBeforeCreate'),
      );
      expect(
        guards,
        contains('DocumentTimestampPolicy.requireReceiveNotBeforeShip'),
      );
    });
  });

  group('keamanan', () {
    test('setiap route bertanda :id dibungkus guard', () {
      final source = readLibrarySource(router);
      for (final name in const [
        'AppRoutes.returnDetailName',
        'AppRoutes.returnEditName',
        'AppRoutes.warehouseReturnDetailName',
      ]) {
        final start = source.indexOf('name: $name');
        expect(start, greaterThan(-1), reason: '$name tidak terdaftar.');
        final end = source.indexOf('),\n          ),', start);
        final body = source.substring(start, end == -1 ? source.length : end);
        expect(
          body,
          contains('GoodsReturnRouteGuard'),
          reason: '$name tidak dibungkus guard.',
        );
      }
      // And the create route, which names a Good Receipt rather than a return.
      final createStart = source.indexOf('name: AppRoutes.returnNewName');
      expect(createStart, greaterThan(-1));
      final createBody = source.substring(createStart, createStart + 900);
      expect(createBody, contains('GoodsReturnSectionGuard'));
      expect(createBody, contains('GoodsReturnCreateGuard'));
    });

    test('kedua bagian berada pada path terpisah', () {
      final source = readLibrarySource(routes);
      expect(source, contains("static const String returns = '/returns';"));
      expect(
        source,
        contains(
          "static const String warehouseReturns = '/warehouse/returns';",
        ),
      );
    });

    test('provider cabang tidak menerima branch id sebagai parameter', () {
      final code = readCodeOnly(
        '$presentationRoot/providers/goods_return_providers.dart',
      );
      expect(code, contains('actingBranchIdProvider'));

      // Every branch-scoped read must take its branch from the session. The Warehouse
      // queue's `setBranchId` is deliberately *not* in scope here: it is a display
      // chip on a read already pinned to the two Warehouse-visible statuses, and it
      // can only ever narrow (§31).
      for (final name in const [
        'branchRejectedGoodReceiptsProvider',
        'branchGoodsReturnListProvider',
        'branchGoodsReturnDetailProvider',
        'goodsReturnEligibilityByReceiptProvider',
      ]) {
        final start = code.indexOf('final $name');
        expect(start, greaterThan(-1), reason: '$name tidak ditemukan.');
        final end = code.indexOf('\n    });', start);
        final body = code.substring(start, end == -1 ? code.length : end);
        expect(
          body,
          contains('actingBranchIdProvider'),
          reason: '$name tidak memakai branch sesi (§28).',
        );
        expect(
          body.contains('required String branchId'),
          isFalse,
          reason: '$name menerima branch id bebas (§28).',
        );
      }
    });

    test('provider Warehouse tidak dapat meminta draft', () {
      final code = readCodeOnly(
        '$presentationRoot/providers/goods_return_providers.dart',
      );
      final start = code.indexOf('final warehouseGoodsReturnListProvider');
      final end = code.indexOf('/// The queue', start);
      final body = code.substring(start, end == -1 ? code.length : end);
      expect(body.contains('GoodsReturnStatus.draft'), isFalse);
    });

    test('provider layar memakai autoDispose', () {
      final code = readCodeOnly(
        '$presentationRoot/providers/goods_return_providers.dart',
      );
      for (final name in const [
        'branchRejectedGoodReceiptsProvider',
        'goodsReturnEligibilityByReceiptProvider',
        'branchGoodsReturnListProvider',
        'branchGoodsReturnDetailProvider',
        'warehouseGoodsReturnListProvider',
        'warehouseGoodsReturnDetailProvider',
        'goodsReturnMovementsProvider',
        'goodsReturnActionsProvider',
      ]) {
        final start = code.indexOf('final $name');
        expect(start, greaterThan(-1), reason: '$name tidak ditemukan.');
        final end = code.indexOf('(', start + name.length + 6);
        expect(
          code.substring(start, end),
          contains('autoDispose'),
          reason: '$name bukan autoDispose (§28).',
        );
      }
    });

    test('use case memuat ulang aktor dari database', () {
      for (final name in const [
        'create_goods_return_use_case.dart',
        'update_goods_return_note_use_case.dart',
        'ship_goods_return_use_case.dart',
        'receive_goods_return_use_case.dart',
      ]) {
        final code = readCodeOnly('$domainRoot/use_cases/$name');
        expect(
          RegExp(r'require(Branch|Warehouse)Actor\(').hasMatch(code),
          isTrue,
          reason: '$name tidak memuat ulang aktor (O-8).',
        );
      }
    });

    test('getDetail tanpa scope hanya dipakai use case', () {
      for (final file in dartFilesUnder(presentationRoot)) {
        expect(
          readCodeOnly(file).contains('.getDetail('),
          isFalse,
          reason: '$file memakai baca tanpa scope (§25).',
        );
      }
    });

    test('pemisahan tugas ditegakkan di SQL, bukan hanya di guard', () {
      final code = readCodeOnly(dao);
      final start = code.indexOf('Future<int> markReceived(');
      expect(start, greaterThan(-1));
      // The next method's signature, because `markReceived` nests braces and a naive
      // `'\n  }'` closes it at the first inner block.
      final end = code.indexOf('Future<GoodsReturnRow?> headerById(', start);
      expect(end, greaterThan(start));
      final body = code.substring(start, end);
      expect(body, contains('created_by <> ?'));
      expect(body, contains('shipped_by IS NULL OR shipped_by <> ?'));
    });
  });

  group('schema', () {
    test('schemaVersion 11 dan index migrasi dibekukan', () {
      final source = readLibrarySource(database);
      expect(source, contains('int get schemaVersion => 11;'));
      expect(source, contains('_v11GoodsReturnIndexes'));
      expect(source, contains('if (from < 11)'));
      expect(source, contains('await m.createTable(goodsReturns);'));
      expect(source, contains('await m.createTable(goodsReturnLines);'));
    });

    test('migrasi v11 tidak menyentuh tabel milestone sebelumnya', () {
      // Comments stripped: the step's own note explains at length which tables it
      // leaves alone, and reading it raw would make that explanation trip every
      // assertion below.
      final code = readCodeOnly(database);
      final start = code.indexOf('if (from < 11)');
      expect(start, greaterThan(-1));
      final end = code.indexOf('beforeOpen:', start);
      expect(end, greaterThan(start));
      final body = code.substring(start, end);

      for (final forbidden in const [
        'UPDATE ',
        'DELETE ',
        'INSERT ',
        'alterTable',
        'good_receipt',
        'consumptions',
        'stock_balances',
        'stock_movements',
      ]) {
        expect(
          body.contains(forbidden),
          isFalse,
          reason: 'Langkah v11 menyentuh "$forbidden" — tidak aditif (§12).',
        );
      }
    });

    test('CHECK pemisahan tugas ada di tabel', () {
      final source = readLibrarySource(tables);
      expect(
        source,
        contains('CHECK (received_by IS NULL OR received_by <> created_by)'),
      );
      expect(source, contains('received_by <> shipped_by'));
    });
  });

  group('dokumen lain tidak berubah', () {
    test('Good Receipt tetap final', () {
      // Raising a return changes nothing about the receipt it came from (G-S2).
      for (final file in [...dartFilesUnder(featureRoot), dao]) {
        final code = readCodeOnly(file);
        for (final forbidden in const [
          'UPDATE good_receipts',
          'UPDATE good_receipt_lines',
          'update(goodReceipts)',
          'update(goodReceiptLines)',
          'markPosted(',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$file menulis dokumen Penerimaan Barang.',
          );
        }
      }
    });

    test('Pemusnahan tetap satu-satunya jalan keluar stok kedaluwarsa', () {
      // A return brings expired stock *in*; taking it back out is still G-E7's.
      for (final file in dartFilesUnder(featureRoot)) {
        expect(
          readCodeOnly(file).contains('StockMovementType.disposal'),
          isFalse,
          reason: '$file menulis movement pemusnahan.',
        );
      }
    });
  });
}
