import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/master/domain/models/import_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'master_fixture.dart';

/// Stage 2 of G-M3 — *"dieksekusi atomik dalam 1 transaksi"* — plus G-M4's upsert
/// semantics and §51's atomicity table.
void main() {
  late MasterFixture fixture;
  late String actorId;

  DateTime clock() => DateTime.utc(2026, 7, 31, 4, 30);

  setUp(() async {
    fixture = MasterFixture.create(clock: clock);
    actorId = await fixture.seedSuperAdmin();
  });

  tearDown(() => fixture.dispose());

  Future<ImportPreviewSession> preview({
    required MasterEntityType entity,
    required List<Map<String, String>> rows,
    String fileName = 'master.xlsx',
  }) => fixture.validateImport().call(
    actorUserId: actorId,
    entity: entity,
    file: pickedFile(entity: entity, rows: rows, fileName: fileName),
  );

  group('G-M4 upsert cabang', () {
    test(
      'kode baru menambah, kode sama memperbarui, tidak ada duplikat',
      () async {
        final first = await preview(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Cabang Satu',
              'address': 'Jl. A',
              'is_active': 'TRUE',
            },
          ],
        );
        await fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: first.importId,
        );

        expect(await fixture.countOf('branches'), 1);
        // §22: exactly one branch store, created along with the branch.
        expect(await fixture.countOf('stock_locations'), 1);

        final second = await preview(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Cabang Satu Baru',
              'address': 'Jl. B',
              'is_active': 'TRUE',
            },
          ],
        );
        expect(second.summary.updatedRows, 1);
        expect(second.summary.insertedRows, 0);

        final result = await fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: second.importId,
        );

        expect(result.updatedRows, 1);
        expect(await fixture.countOf('branches'), 1);
        // No second store — `ensureBranchStoreLocation` is idempotent (§22).
        expect(await fixture.countOf('stock_locations'), 1);

        final branches = await fixture.repository.branchesByCode('CAB-01');
        expect(branches.single.name, 'Cabang Satu Baru');
        expect(branches.single.address, 'Jl. B');
      },
    );

    test(
      'kode yang berbeda huruf besar/kecil dianggap kunci yang sama',
      () async {
        final first = await preview(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Cabang Satu',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        );
        await fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: first.importId,
        );

        final second = await preview(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'cab-01',
              'name': 'Huruf Kecil',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        );
        expect(second.summary.updatedRows, 1);
        await fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: second.importId,
        );

        expect(await fixture.countOf('branches'), 1);
        // The stored code is the one that was created, never rewritten by a later
        // spelling — only the comparison key is case-folded (§16).
        expect(
          await fixture.columnOf(
            'branches',
            (await fixture.repository.branchesByCode('CAB-01')).single.id,
            'code',
          ),
          'CAB-01',
        );
      },
    );
  });

  group('G-M4 upsert ruangan: kunci adalah cabang + kode', () {
    Future<String> seedBranch(String code) async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: code,
        name: 'Cabang $code',
      );
      return branch.id;
    }

    test('kode ruangan sama di cabang berbeda adalah dua ruangan', () async {
      await seedBranch('CAB-01');
      await seedBranch('CAB-02');

      final session = await preview(
        entity: MasterEntityType.rooms,
        rows: [
          {
            'branch_code': 'CAB-01',
            'code': 'R1',
            'name': 'Ruang 1 A',
            'is_active': 'TRUE',
          },
          {
            'branch_code': 'CAB-02',
            'code': 'R1',
            'name': 'Ruang 1 B',
            'is_active': 'TRUE',
          },
        ],
      );

      // Two inserts, not one insert and one duplicate: the key is composite.
      expect(session.summary.insertedRows, 2);
      expect(session.summary.failedRows, 0);

      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );
      expect(await fixture.countOf('rooms'), 2);
      // Two branch stores plus two room locations.
      expect(await fixture.countOf('stock_locations'), 4);
    });

    test('cabang + kode yang sama memperbarui ruangan yang ada', () async {
      await seedBranch('CAB-01');
      final first = await preview(
        entity: MasterEntityType.rooms,
        rows: [
          {
            'branch_code': 'CAB-01',
            'code': 'R1',
            'name': 'Ruang Lama',
            'is_active': 'TRUE',
          },
        ],
      );
      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: first.importId,
      );

      final second = await preview(
        entity: MasterEntityType.rooms,
        rows: [
          {
            'branch_code': 'CAB-01',
            'code': 'R1',
            'name': 'Ruang Baru',
            'is_active': 'TRUE',
          },
        ],
      );
      expect(second.summary.updatedRows, 1);
      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: second.importId,
      );

      expect(await fixture.countOf('rooms'), 1);
      expect(await fixture.countOf('stock_locations'), 2);
    });

    test('cabang yang tidak ada ditolak', () async {
      final session = await preview(
        entity: MasterEntityType.rooms,
        rows: [
          {
            'branch_code': 'CAB-99',
            'code': 'R1',
            'name': 'Ruang',
            'is_active': 'TRUE',
          },
        ],
      );
      expect(session.summary.failedRows, 1);
      expect(session.issues.single.code, ImportIssueCode.foreignKeyNotFound);
    });
  });

  group('§17 kunci ganda dalam satu file', () {
    test('semua baris yang terlibat gagal — tidak ada last-row-wins', () async {
      final session = await preview(
        entity: MasterEntityType.branches,
        rows: [
          {
            'code': 'CAB-01',
            'name': 'Pertama',
            'address': '',
            'is_active': 'TRUE',
          },
          {
            'code': 'CAB-02',
            'name': 'Lain',
            'address': '',
            'is_active': 'TRUE',
          },
          {
            'code': 'cab-01',
            'name': 'Kedua',
            'address': '',
            'is_active': 'TRUE',
          },
        ],
      );

      expect(session.summary.failedRows, 2);
      expect(session.summary.insertedRows, 1);
      final duplicateRows = session.issues
          .where((issue) => issue.code == ImportIssueCode.duplicateNaturalKey)
          .map((issue) => issue.rowNumber)
          .toSet();
      // Rows 3 and 5 — both, never only the later one.
      expect(duplicateRows, {3, 5});
      expect(session.canCommit, isFalse);
    });
  });

  group('G-M3 commit hanya dengan 0 error', () {
    test('commit ditolak ketika ada baris gagal', () async {
      final session = await preview(
        entity: MasterEntityType.branches,
        rows: [
          {'code': '', 'name': '', 'address': '', 'is_active': 'TRUE'},
        ],
      );

      await expectLater(
        fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<ImportHasErrorsFailure>()),
      );

      expect(await fixture.countOf('branches'), 0);
      expect(
        await fixture.importLogColumn(session.importId, 'status'),
        ImportStatus.validated.dbValue,
      );
    });
  });

  group('§3.4 mesin status impor', () {
    Future<ImportPreviewSession> validPreview() => preview(
      entity: MasterEntityType.branches,
      rows: [
        {
          'code': 'CAB-01',
          'name': 'Cabang Satu',
          'address': '',
          'is_active': 'TRUE',
        },
      ],
    );

    test('validated → committed', () async {
      final session = await validPreview();
      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );
      expect(
        await fixture.importLogColumn(session.importId, 'status'),
        'committed',
      );
      expect(
        await fixture.importLogColumn(session.importId, 'sync_status'),
        SyncStatus.pending.dbValue,
      );
    });

    test('validated → discarded, master tidak berubah, file tetap ada', () async {
      final session = await validPreview();
      final fingerprint = await fixture.masterFingerprint();

      final log = await fixture.discardImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );

      expect(log.status, ImportStatus.discarded);
      expect(await fixture.masterFingerprint(), fingerprint);
      // The source file is retained: a discarded import is still an import that
      // happened (§35).
      expect(
        fixture.sourceFileStore.files.containsKey(session.sourceFile.path),
        isTrue,
      );
      expect(log.totalRows, 1);
      expect(log.insertedRows, 1);
    });

    test('committed tidak dapat di-commit lagi', () async {
      final session = await validPreview();
      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );

      await expectLater(
        fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<ImportAlreadyCommittedFailure>()),
      );
      expect(await fixture.countOf('branches'), 1);
    });

    test('committed tidak dapat dibatalkan', () async {
      final session = await validPreview();
      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );

      await expectLater(
        fixture.discardImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<ImportAlreadyCommittedFailure>()),
      );
    });

    test('discarded tidak dapat di-commit maupun dibatalkan lagi', () async {
      final session = await validPreview();
      await fixture.discardImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );

      await expectLater(
        fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<ImportAlreadyDiscardedFailure>()),
      );
      await expectLater(
        fixture.discardImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<ImportAlreadyDiscardedFailure>()),
      );
      expect(await fixture.countOf('branches'), 0);
    });
  });

  group('§33 commit tidak mempercayai pratinjau', () {
    test('file sumber yang hilang menolak commit', () async {
      final session = await preview(
        entity: MasterEntityType.branches,
        rows: [
          {
            'code': 'CAB-01',
            'name': 'Cabang Satu',
            'address': '',
            'is_active': 'TRUE',
          },
        ],
      );
      fixture.sourceFileStore.remove(session.sourceFile.path);

      await expectLater(
        fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<ImportSourceFileMissingFailure>()),
      );

      expect(await fixture.countOf('branches'), 0);
      expect(
        await fixture.importLogColumn(session.importId, 'status'),
        'validated',
      );
    });

    test('file sumber yang berubah menolak commit', () async {
      final session = await preview(
        entity: MasterEntityType.branches,
        rows: [
          {
            'code': 'CAB-01',
            'name': 'Cabang Satu',
            'address': '',
            'is_active': 'TRUE',
          },
        ],
      );
      fixture.sourceFileStore.corrupt(session.sourceFile.path);

      await expectLater(
        fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<ImportSourceFileHashMismatchFailure>()),
      );

      expect(await fixture.countOf('branches'), 0);
      expect(
        await fixture.importLogColumn(session.importId, 'status'),
        'validated',
      );
    });

    test(
      'kunci alami yang dibuat pihak lain setelah pratinjau menolak commit',
      () async {
        final session = await preview(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Dari File',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        );
        expect(session.summary.insertedRows, 1);

        // Somebody else created it in the meantime. The commit re-parses and
        // revalidates, so the row becomes an *update* rather than a duplicate
        // insert — and the row it updates is the one that now exists.
        await fixture.createBranch.call(
          actorUserId: actorId,
          code: 'CAB-01',
          name: 'Dibuat Manual',
        );

        final result = await fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        );

        expect(result.insertedRows, 0);
        expect(result.updatedRows, 1);
        expect(await fixture.countOf('branches'), 1);
        // The audit records what actually happened, not what was predicted.
        expect(
          await fixture.importLogColumn(session.importId, 'inserted_rows'),
          '0',
        );
        expect(
          await fixture.importLogColumn(session.importId, 'updated_rows'),
          '1',
        );
      },
    );

    test('aktor yang dinonaktifkan setelah pratinjau menolak commit', () async {
      final session = await preview(
        entity: MasterEntityType.branches,
        rows: [
          {
            'code': 'CAB-01',
            'name': 'Cabang Satu',
            'address': '',
            'is_active': 'TRUE',
          },
        ],
      );
      await fixture.deactivateRaw('users', actorId);

      await expectLater(
        fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<MasterAdminAccessDeniedFailure>()),
      );

      expect(await fixture.countOf('branches'), 0);
      expect(
        await fixture.importLogColumn(session.importId, 'status'),
        'validated',
      );
    });

    test('peran aktor yang berubah setelah pratinjau menolak commit', () async {
      final session = await preview(
        entity: MasterEntityType.branches,
        rows: [
          {
            'code': 'CAB-01',
            'name': 'Cabang Satu',
            'address': '',
            'is_active': 'TRUE',
          },
        ],
      );
      await fixture.database.customStatement(
        "UPDATE users SET role = 'warehouse' WHERE id = ?;",
        [actorId],
      );

      await expectLater(
        fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        ),
        throwsA(isA<MasterAdminAccessDeniedFailure>()),
      );
      expect(await fixture.countOf('branches'), 0);
    });
  });

  group('§51 atomicity: satu kegagalan membatalkan seluruh impor', () {
    test(
      'kegagalan revalidasi di baris terakhir tidak menyisakan insert parsial',
      () async {
        // Three branches, all new. Then somebody archives a category… no — for
        // branches the reachable mid-flight failure is a row whose revalidation
        // now fails. A room whose branch is deactivated between preview and
        // commit is exactly that, and it is the last of three.
        await fixture.createBranch.call(
          actorUserId: actorId,
          code: 'CAB-01',
          name: 'Cabang Satu',
        );
        final second = await fixture.createBranch.call(
          actorUserId: actorId,
          code: 'CAB-02',
          name: 'Cabang Dua',
        );

        final session = await preview(
          entity: MasterEntityType.rooms,
          rows: [
            {
              'branch_code': 'CAB-01',
              'code': 'R1',
              'name': 'Ruang 1',
              'is_active': 'TRUE',
            },
            {
              'branch_code': 'CAB-01',
              'code': 'R2',
              'name': 'Ruang 2',
              'is_active': 'TRUE',
            },
            {
              'branch_code': 'CAB-02',
              'code': 'R3',
              'name': 'Ruang 3',
              'is_active': 'TRUE',
            },
          ],
        );
        expect(session.summary.insertedRows, 3);

        final roomsBefore = await fixture.countOf('rooms');
        final locationsBefore = await fixture.countOf('stock_locations');

        // The third row's branch is deactivated after the preview.
        await fixture.setBranchActive.call(
          actorUserId: actorId,
          branchId: second.id,
          isActive: false,
        );

        await expectLater(
          fixture.commitImport().call(
            actorUserId: actorId,
            importLogId: session.importId,
          ),
          throwsA(isA<ImportHasErrorsFailure>()),
        );

        // Zero partial inserts, zero orphan locations, status unchanged, source
        // retained — every line of §51.
        expect(await fixture.countOf('rooms'), roomsBefore);
        expect(await fixture.countOf('stock_locations'), locationsBefore);
        expect(await fixture.countOf('stock_balances'), 0);
        expect(await fixture.countOf('stock_movements'), 0);
        expect(
          await fixture.importLogColumn(session.importId, 'status'),
          'validated',
        );
        expect(
          fixture.sourceFileStore.files.containsKey(session.sourceFile.path),
          isTrue,
        );
      },
    );

    test('dua commit bersamaan: tepat satu menang', () async {
      final session = await preview(
        entity: MasterEntityType.branches,
        rows: [
          {
            'code': 'CAB-01',
            'name': 'Cabang Satu',
            'address': '',
            'is_active': 'TRUE',
          },
        ],
      );

      final results = await Future.wait<Object?>([
        fixture
            .commitImport()
            .call(actorUserId: actorId, importLogId: session.importId)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
        fixture
            .commitImport()
            .call(actorUserId: actorId, importLogId: session.importId)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
      ]);

      final successes = results.whereType<ImportCommitResult>().length;
      expect(successes, 1);
      // Exactly one set of master effects, and no duplicate location.
      expect(await fixture.countOf('branches'), 1);
      expect(await fixture.countOf('stock_locations'), 1);
      expect(
        await fixture.importLogColumn(session.importId, 'status'),
        'committed',
      );
    });
  });

  group('G-M7 sinkronisasi', () {
    test('setiap baris master yang ditulis impor berstatus pending', () async {
      final session = await preview(
        entity: MasterEntityType.branches,
        rows: [
          {
            'code': 'CAB-01',
            'name': 'Cabang Satu',
            'address': '',
            'is_active': 'TRUE',
          },
        ],
      );
      await fixture.commitImport().call(
        actorUserId: actorId,
        importLogId: session.importId,
      );

      final branchId = (await fixture.repository.branchesByCode(
        'CAB-01',
      )).single.id;
      expect(
        await fixture.columnOf('branches', branchId, 'sync_status'),
        SyncStatus.pending.dbValue,
      );
      final rows = await fixture.database
          .customSelect('SELECT sync_status FROM stock_locations;')
          .get();
      expect(
        rows.map((row) => row.read<String>('sync_status')),
        everyElement(SyncStatus.pending.dbValue),
      );
      // Never `synced` — nothing in this build simulates a server (§44).
      expect(
        await fixture.importLogColumn(session.importId, 'sync_status'),
        SyncStatus.pending.dbValue,
      );
    });
  });
}
