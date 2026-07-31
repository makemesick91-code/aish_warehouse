import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/sync/sync_gateway.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import 'master_fixture.dart';

/// G-M7 and §54: *"dibuat offline → `pending` → server memvalidasi ulang saat
/// sinkronisasi"*.
///
/// Two halves, and the second is the one that has to be stated honestly:
///
/// * **Everything this milestone writes is `pending`**, and nothing in it ever
///   writes `synced`. That is asserted directly, for every entity and for the
///   audit row's own life.
/// * **Server revalidation is not implemented.** There is no server in this
///   build. What exists is the boundary a Milestone 12 sync client would sit
///   behind, and the tests below prove the boundary is clean — no network client,
///   no sync gateway required for a commit — rather than proving a server checked
///   anything.
void main() {
  late MasterFixture fixture;
  late String actorId;

  DateTime clock() => DateTime.utc(2026, 7, 31, 4, 30);

  setUp(() async {
    fixture = MasterFixture.create(clock: clock);
    actorId = await fixture.seedSuperAdmin();
  });

  tearDown(() => fixture.dispose());

  /// Marks every row of [table] synced, so a later assertion about `pending`
  /// cannot pass by accident on a row that was pending all along.
  Future<void> markSynced(String table) => fixture.database.customStatement(
    "UPDATE $table SET sync_status = 'synced';",
  );

  Future<List<String>> syncStatuses(String table) async {
    final rows = await fixture.database
        .customSelect('SELECT sync_status FROM $table;')
        .get();
    return rows.map((row) => row.read<String>('sync_status')).toList();
  }

  group('setiap tulisan master berstatus pending', () {
    test('insert, update, nonaktifkan, dan aktifkan kembali', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      expect(await syncStatuses('branches'), ['pending']);
      expect(await syncStatuses('stock_locations'), ['pending']);

      for (final step in <Future<void> Function()>[
        () => fixture.updateBranch.call(
          actorUserId: actorId,
          branchId: branch.id,
          name: 'Satu Baru',
          isActive: true,
        ),
        () => fixture.setBranchActive.call(
          actorUserId: actorId,
          branchId: branch.id,
          isActive: false,
        ),
        () => fixture.setBranchActive.call(
          actorUserId: actorId,
          branchId: branch.id,
          isActive: true,
        ),
      ]) {
        await markSynced('branches');
        await step();
        expect(
          await syncStatuses('branches'),
          ['pending'],
          reason: 'setiap perubahan harus kembali ke pending',
        );
      }
    });

    test('arsip dan pulih kategori berstatus pending', () async {
      final category = await fixture.createCategory.call(
        actorUserId: actorId,
        name: 'Obat',
      );
      await markSynced('item_categories');

      await fixture.archiveCategory.call(
        actorUserId: actorId,
        categoryId: category.id,
      );
      expect(await syncStatuses('item_categories'), ['pending']);

      await markSynced('item_categories');
      await fixture.restoreCategory.call(
        actorUserId: actorId,
        categoryId: category.id,
      );
      expect(await syncStatuses('item_categories'), ['pending']);
    });

    test('arsip dan pulih batch berstatus pending', () async {
      final category = await fixture.createCategory.call(
        actorUserId: actorId,
        name: 'Obat',
      );
      final item = await fixture.createItem.call(
        actorUserId: actorId,
        sku: 'DEN-1',
        name: 'Anestesi',
        categoryId: category.id,
        unit: 'ampul',
        hasExpiry: true,
      );
      final batch = await fixture.createBatch.call(
        actorUserId: actorId,
        itemId: item.id,
        batchNo: 'LOT-1',
        expiryDate: DateOnly.of(2026, 12, 31),
      );
      await markSynced('item_batches');

      await fixture.archiveBatch.call(actorUserId: actorId, batchId: batch.id);
      expect(await syncStatuses('item_batches'), ['pending']);

      await markSynced('item_batches');
      await fixture.restoreBatch.call(actorUserId: actorId, batchId: batch.id);
      expect(await syncStatuses('item_batches'), ['pending']);
    });
  });

  group('setiap baris audit dan transisinya berstatus pending', () {
    test('validated, committed, dan discarded semuanya pending', () async {
      final first = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.itemCategories,
        file: pickedFile(
          entity: MasterEntityType.itemCategories,
          rows: const [
            {'name': 'Obat'},
          ],
        ),
      );
      expect(
        await fixture.importLogColumn(first.importId, 'sync_status'),
        SyncStatus.pending.dbValue,
      );

      await markSynced('import_logs');
      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: first.importId,
      );
      // A status transition is itself a change the server has not seen.
      expect(
        await fixture.importLogColumn(first.importId, 'sync_status'),
        SyncStatus.pending.dbValue,
      );

      final second = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.itemCategories,
        file: pickedFile(
          entity: MasterEntityType.itemCategories,
          rows: const [
            {'name': 'APD'},
          ],
        ),
      );
      await markSynced('import_logs');
      await fixture.discardImport().call(
        actorUserId: actorId,
        importLogId: second.importId,
      );
      expect(
        await fixture.importLogColumn(second.importId, 'sync_status'),
        SyncStatus.pending.dbValue,
      );
    });

    test('impor tidak pernah menulis synced sendiri', () async {
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          rows: const [
            {
              'code': 'CAB-01',
              'name': 'Satu',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );
      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );

      for (final table in const [
        'branches',
        'stock_locations',
        'import_logs',
      ]) {
        expect(
          await syncStatuses(table),
          everyElement(SyncStatus.pending.dbValue),
          reason: table,
        );
      }
    });
  });

  group('offline', () {
    test('seluruh alur berjalan tanpa gateway sinkronisasi', () async {
      // No sync gateway is constructed anywhere in this test, and the whole flow
      // still runs: template → validate → preview → commit → history.
      final download = await fixture.downloadTemplate().call(
        actorUserId: actorId,
        entity: MasterEntityType.itemCategories,
      );
      expect(download.artifact.byteLength, greaterThan(0));

      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.itemCategories,
        file: pickedFile(
          entity: MasterEntityType.itemCategories,
          rows: const [
            {'name': 'Obat'},
          ],
        ),
      );
      expect(session.canCommit, isTrue);

      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );
      final history = await fixture.watchImportHistory
          .call(actorUserId: actorId)
          .first;
      expect(history, hasLength(1));
      expect(history.single.status.isCommitted, isTrue);
    });

    test('NoopSyncGateway tidak menghalangi impor', () async {
      // The gateway this build ships is a no-op, and it is not on the import
      // path at all — constructing one changes nothing about the flow.
      const gateway = NoopSyncGateway();
      expect(gateway, isNotNull);

      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.itemCategories,
        file: pickedFile(
          entity: MasterEntityType.itemCategories,
          rows: const [
            {'name': 'Obat'},
          ],
        ),
      );
      final result = await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );
      expect(result.insertedRows, 1);
    });
  });

  group('batas server didokumentasikan, bukan disimulasikan', () {
    test('tidak ada klien jaringan pada jalur master/import', () {
      for (final file in dartFilesUnder('lib/features/master')) {
        final imports = importsOf(file);
        for (final forbidden in const [
          'package:http',
          'package:dio',
          'package:supabase',
          'package:web_socket',
        ]) {
          expect(
            imports.where((i) => i.startsWith(forbidden)),
            isEmpty,
            reason: '$file: $forbidden',
          );
        }
      }
    });

    test('tidak ada kode yang menulis synced', () {
      // *Writes*, not reads: the Super Admin dashboard legitimately counts logs
      // whose status is not `synced`, and forbidding the identifier outright
      // would forbid asking the question as well as answering it wrongly.
      const writes = [
        'Value(SyncStatus.synced)',
        'syncStatus: SyncStatus.synced',
        "sync_status = 'synced'",
      ];
      for (final file in [
        ...dartFilesUnder('lib/features/master'),
        'lib/core/db/daos/master_admin_dao.dart',
      ]) {
        final code = readCodeOnly(file);
        for (final write in writes) {
          expect(
            code,
            isNot(contains(write)),
            reason:
                '$file menulis synced — hanya server yang boleh, dan belum ada '
                'server (§44).',
          );
        }
      }
    });

    test('batas revalidasi server dinyatakan dalam dokumentasi', () {
      // Stated in prose where the next milestone will look for it, and asserted
      // here so it cannot quietly disappear.
      // Read with line breaks and comment markers collapsed, so the assertion
      // is about the *statement* rather than about where the doc comment wraps.
      final policy = readLibrarySource(
        'lib/features/master/domain/services/master_admin_access_policy.dart',
      ).replaceAll(RegExp(r'\s*///\s*'), ' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(policy, contains('Milestone 12'));
      expect(policy, contains('There is no server in this build'));
      expect(
        policy,
        contains(
          'should be read as a claim that a server has checked anything',
        ),
      );
    });
  });
}
