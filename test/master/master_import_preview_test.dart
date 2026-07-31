import 'dart:typed_data';

import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/master/domain/models/import_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_normalization_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'master_fixture.dart';

/// Stage 1 of G-M3: *"semua baris dicek … tanpa menyentuh database"*, and §47's
/// twenty-three assertions about what a preview may and may not do.
///
/// The load-bearing test in this file is the first one: a full fingerprint of
/// every master table before and after a preview, byte-identical. Counts alone
/// would not catch an UPDATE, and "no master mutation" is exactly the claim
/// G-M3 makes.
void main() {
  late MasterFixture fixture;
  late String actorId;

  DateTime clock() => DateTime.utc(2026, 7, 31, 4, 30);

  setUp(() async {
    fixture = MasterFixture.create(clock: clock);
    actorId = await fixture.seedSuperAdmin();
  });

  tearDown(() => fixture.dispose());

  group('G-M3 pratinjau tidak mengubah master data', () {
    test('pratinjau valid tidak menulis satu baris master pun', () async {
      final before = await fixture.masterCounts();
      final fingerprint = await fixture.masterFingerprint();

      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Cabang Satu',
              'address': 'Jl. Satu',
              'is_active': 'TRUE',
            },
            {
              'code': 'CAB-02',
              'name': 'Cabang Dua',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );

      expect(session.summary.totalRows, 2);
      expect(session.summary.insertedRows, 2);
      expect(session.summary.updatedRows, 0);
      expect(session.summary.failedRows, 0);
      expect(session.canCommit, isTrue);

      // The whole point: nothing moved.
      expect(await fixture.masterCounts(), before);
      expect(await fixture.masterFingerprint(), fingerprint);
    });

    test('pratinjau dengan error juga tidak mengubah master data', () async {
      final fingerprint = await fixture.masterFingerprint();

      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          rows: [
            {'code': '', 'name': '', 'address': '', 'is_active': 'mungkin'},
          ],
        ),
      );

      expect(session.summary.failedRows, 1);
      expect(session.canCommit, isFalse);
      expect(await fixture.masterFingerprint(), fingerprint);
    });

    test(
      'pratinjau tidak menulis baris stok maupun dokumen workflow',
      () async {
        await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: pickedFile(
            entity: MasterEntityType.branches,
            rows: [
              {
                'code': 'CAB-01',
                'name': 'Cabang Satu',
                'address': '',
                'is_active': 'TRUE',
              },
            ],
          ),
        );

        for (final table in const [
          'stock_locations',
          'stock_balances',
          'stock_movements',
          'stock_opnames',
          'purchase_requests',
          'delivery_orders',
          'good_receipts',
          'distributions',
          'disposals',
          'consumptions',
          'goods_returns',
        ]) {
          expect(await fixture.countOf(table), 0, reason: table);
        }
      },
    );
  });

  group('G-M6 baris audit dan file sumber', () {
    test(
      'satu import_logs berstatus validated dibuat setelah validasi',
      () async {
        final session = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: pickedFile(
            entity: MasterEntityType.branches,
            fileName: 'cabang-juli.xlsx',
            rows: [
              {
                'code': 'CAB-01',
                'name': 'Cabang Satu',
                'address': '',
                'is_active': 'TRUE',
              },
            ],
          ),
        );

        final rows = await fixture.importLogRows();
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row['id'], session.importId);
        expect(row['entity'], 'branches');
        expect(row['status'], 'validated');
        // The name the operator saw in the picker, not the sanitized one.
        expect(row['file_name'], 'cabang-juli.xlsx');
        expect(row['total_rows'], 1);
        expect(row['inserted_rows'], 1);
        expect(row['updated_rows'], 0);
        expect(row['failed_rows'], 0);
        expect(row['error_detail'], isNull);
        expect(row['imported_by'], actorId);
        expect(row['template_version'], MasterTemplateVersion.current);
        expect(row['sync_status'], SyncStatus.pending.dbValue);
        expect(row['deleted_at'], isNull);
      },
    );

    test('file sumber disimpan dengan hash dan ukuran yang tepat', () async {
      final file = pickedFile(
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

      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: file,
      );

      expect(
        fixture.sourceFileStore.files.containsKey(session.sourceFile.path),
        isTrue,
      );
      expect(session.sourceFile.sha256, sha256Hex(file.bytes));
      expect(session.sourceFile.sizeBytes, file.bytes.length);
      expect(
        await fixture.importLogColumn(session.importId, 'file_sha256'),
        sha256Hex(file.bytes),
      );
      expect(session.sourceFile.sha256, hasLength(64));
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(session.sourceFile.sha256),
        isTrue,
      );
    });

    test(
      'kegagalan menyimpan file sumber tidak meninggalkan baris audit',
      () async {
        fixture.sourceFileStore.failOnStore = true;

        await expectLater(
          fixture.validateImport().call(
            actorUserId: actorId,
            entity: MasterEntityType.branches,
            file: pickedFile(
              entity: MasterEntityType.branches,
              rows: [
                {
                  'code': 'CAB-01',
                  'name': 'Cabang Satu',
                  'address': '',
                  'is_active': 'TRUE',
                },
              ],
            ),
          ),
          throwsA(isA<ImportSourceFileWriteFailureForTest>()),
        );

        expect(await fixture.countOf('import_logs'), 0);
        expect(await fixture.countOf('branches'), 0);
      },
    );

    test(
      'file yang sama diimpor dua kali menghasilkan dua baris audit',
      () async {
        final file = pickedFile(
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

        final first = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: file,
        );
        final second = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: file,
        );

        // Two events, two rows, two retained copies — §11 refuses a unique index
        // on the hash for exactly this reason.
        expect(first.importId, isNot(second.importId));
        expect(await fixture.countOf('import_logs'), 2);
        expect(fixture.sourceFileStore.files, hasLength(2));
        expect(first.sourceFile.sha256, second.sourceFile.sha256);
      },
    );
  });

  group('§29 setiap baris diperiksa, tidak berhenti di error pertama', () {
    test('baris setelah error pertama tetap divalidasi', () async {
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': '',
              'name': 'Tanpa Kode',
              'address': '',
              'is_active': 'TRUE',
            },
            {
              'code': 'CAB-02',
              'name': 'Valid',
              'address': '',
              'is_active': 'TRUE',
            },
            {'code': 'CAB-03', 'name': '', 'address': '', 'is_active': 'TRUE'},
          ],
        ),
      );

      expect(session.summary.totalRows, 3);
      expect(session.summary.failedRows, 2);
      expect(session.summary.insertedRows, 1);
      // Row 5 is the third data row (1 header + 1 sample + 3 data).
      expect(session.issues.where((issue) => issue.rowNumber == 5), isNotEmpty);
    });

    test('satu baris dengan banyak masalah menampilkan semuanya', () async {
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.items,
        file: pickedFile(
          entity: MasterEntityType.items,
          rows: [
            {
              'sku': '',
              'name': '',
              'category_name': '',
              'unit': '',
              'min_stock_room': 'x',
              'min_stock_branch': '-1',
              'has_expiry': 'ya',
              'expiry_alert_days': '1.5',
              'is_active': '1',
            },
          ],
        ),
      );

      final row = session.rows.single;
      expect(row.isValid, isFalse);
      expect(row.errors.length, greaterThanOrEqualTo(8));
      // Still exactly one failure — §31 counts rows, not issues.
      expect(session.summary.failedRows, 1);
    });
  });

  group('§15 struktur workbook', () {
    Future<void> expectRejected(
      PickedImportFile file,
      Matcher matcher, {
      MasterEntityType entity = MasterEntityType.branches,
    }) async {
      await expectLater(
        fixture.validateImport().call(
          actorUserId: actorId,
          entity: entity,
          file: file,
        ),
        throwsA(matcher),
      );
      // Every structural refusal happens before the file is stored (§29).
      expect(await fixture.countOf('import_logs'), 0);
      expect(fixture.sourceFileStore.files, isEmpty);
    }

    test('ekstensi selain .xlsx ditolak', () async {
      for (final name in const [
        'master.xls',
        'master.xlsm',
        'master.csv',
        'master',
      ]) {
        final file = pickedFile(
          entity: MasterEntityType.branches,
          fileName: name,
        );
        await expectRejected(file, isA<ImportUnsupportedFileFailure>());
      }
    });

    test('file kosong ditolak', () async {
      await expectRejected(
        PickedImportFile(originalFileName: 'kosong.xlsx', bytes: Uint8List(0)),
        isA<ImportFileEmptyFailure>(),
      );
    });

    test('workbook rusak ditolak', () async {
      await expectRejected(
        PickedImportFile(
          originalFileName: 'rusak.xlsx',
          bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        ),
        isA<ImportWorkbookCorruptFailure>(),
      );
    });

    test('sheet Data yang hilang ditolak', () async {
      await expectRejected(
        pickedFile(entity: MasterEntityType.branches, includeDataSheet: false),
        isA<ImportSheetMissingFailure>(),
      );
    });

    test('sheet Petunjuk yang hilang ditolak', () async {
      await expectRejected(
        pickedFile(
          entity: MasterEntityType.branches,
          includeInstructionsSheet: false,
        ),
        isA<ImportSheetMissingFailure>(),
      );
    });

    test('versi template yang tidak didukung ditolak', () async {
      await expectRejected(
        pickedFile(
          entity: MasterEntityType.branches,
          templateVersion: 'aish-master-v0',
        ),
        isA<ImportTemplateVersionFailure>(),
      );
    });

    test('versi template yang hilang ditolak', () async {
      await expectRejected(
        pickedFile(entity: MasterEntityType.branches, templateVersion: null),
        isA<ImportTemplateVersionFailure>(),
      );
    });

    test('kolom wajib yang hilang ditolak', () async {
      await expectRejected(
        pickedFile(
          entity: MasterEntityType.branches,
          headers: const ['code', 'name', 'address'],
        ),
        isA<ImportHeaderMismatchFailure>(),
      );
    });

    test('kolom tidak dikenal ditolak', () async {
      await expectRejected(
        pickedFile(
          entity: MasterEntityType.branches,
          headers: const ['code', 'name', 'address', 'is_active', 'catatan'],
        ),
        isA<ImportHeaderMismatchFailure>(),
      );
    });

    test('kolom ganda ditolak', () async {
      await expectRejected(
        pickedFile(
          entity: MasterEntityType.branches,
          headers: const ['code', 'code', 'name', 'address', 'is_active'],
        ),
        isA<ImportHeaderMismatchFailure>(),
      );
    });

    test('urutan kolom yang tertukar ditolak', () async {
      await expectRejected(
        pickedFile(
          entity: MasterEntityType.branches,
          headers: const ['name', 'code', 'address', 'is_active'],
        ),
        isA<ImportHeaderMismatchFailure>(),
      );
    });

    test('sel berisi rumus ditolak', () async {
      await expectRejected(
        pickedFile(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Cabang',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
          formulaCells: const {'3:name': 'A1&"x"'},
        ),
        isA<ImportFormulaCellFailure>(),
      );
    });

    test('template entitas lain ditolak lewat header', () async {
      // A room template uploaded to the branch importer: the headers do not
      // match, and that is the check that catches it.
      await expectRejected(
        pickedFile(
          entity: MasterEntityType.branches,
          headers: MasterEntityType.rooms.headers,
        ),
        isA<ImportHeaderMismatchFailure>(),
      );
    });

    test('file melebihi batas ukuran ditolak', () async {
      await expectRejected(
        PickedImportFile(
          originalFileName: 'besar.xlsx',
          bytes: Uint8List.fromList(
            List<int>.filled(MasterImportLimits.maxFileBytes + 1, 0x50),
          ),
        ),
        isA<ImportFileTooLargeFailure>(),
      );
    });

    test('baris kosong dilewati, baris contoh dilewati', () async {
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Cabang Satu',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
          blankRowsAfter: 3,
        ),
      );

      // One data row: the sample row and the three blank rows are not rows.
      expect(session.summary.totalRows, 1);
      expect(session.rows.single.naturalKeyDisplay, 'CAB-01');
    });

    test(
      'baris contoh yang sudah diganti pengguna diperlakukan sebagai data',
      () async {
        final session = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          // The sample row's sentinel has been typed over, so it is data.
          file: pickedFile(
            entity: MasterEntityType.branches,
            sampleRow: const {
              'code': 'CAB-99',
              'name': 'Cabang Sembilan',
              'address': 'Jl. Sembilan',
              'is_active': 'TRUE',
            },
          ),
        );

        expect(session.summary.totalRows, 1);
        expect(session.summary.insertedRows, 1);
        expect(session.rows.single.naturalKeyDisplay, 'CAB-99');
      },
    );
  });

  group('G-M1 hanya Super Admin', () {
    test('peran selain super_admin ditolak', () async {
      for (final role in const [
        UserRole.perawat,
        UserRole.kepalaCabang,
        UserRole.warehouse,
      ]) {
        final branch = await fixture.createBranch.call(
          actorUserId: actorId,
          code: 'CAB-${role.index}',
          name: 'Cabang ${role.label}',
        );
        final otherId = await fixture.seedUser(
          id: 'user-${role.dbValue}',
          email: '${role.dbValue}@aish.id',
          role: role,
          branchId: role.requiresBranch ? branch.id : null,
        );

        await expectLater(
          fixture.validateImport().call(
            actorUserId: otherId,
            entity: MasterEntityType.branches,
            file: pickedFile(entity: MasterEntityType.branches),
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
        );
      }
      expect(await fixture.countOf('import_logs'), 0);
    });

    test('Super Admin yang dinonaktifkan ditolak', () async {
      await fixture.deactivateRaw('users', actorId);

      await expectLater(
        fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: pickedFile(entity: MasterEntityType.branches),
        ),
        throwsA(isA<MasterAdminAccessDeniedFailure>()),
      );
      expect(await fixture.countOf('import_logs'), 0);
    });
  });
}
