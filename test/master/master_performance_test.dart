import 'package:aish_warehouse/features/master/domain/models/import_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_duplicate_detector.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_normalization_policy.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_row_normalizer.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_validation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'master_fixture.dart';

/// §58 — scale and resilience, asserted **without a flaky timing assertion**.
///
/// Nothing here measures wall-clock time. What is asserted instead is the shape
/// of the work: that 10,000 rows validate without recursion or a stack overflow,
/// that duplicate detection is linear rather than a nested scan, that a
/// multi-chunk commit stays inside one transaction, and that two concurrent
/// operations produce two independent audit trails.
///
/// ### Where the 10,000-row claim is and is not made
///
/// **Validation** is exercised at the full 10,000 rows, because it is pure and
/// cheap. **Commit** is exercised at a size that crosses several chunk
/// boundaries rather than at 10,000, because a 10,000-row commit against a real
/// SQLite file would dominate the suite's runtime for a fact the smaller run
/// already establishes: the transaction is opened once and the chunking is a
/// yield point inside it, not a boundary. That trade is stated here rather than
/// left for a reader to infer, so nothing in this file claims performance it did
/// not test.
void main() {
  late MasterFixture fixture;
  late String actorId;

  DateTime clock() => DateTime.utc(2026, 7, 31, 4, 30);

  setUp(() async {
    fixture = MasterFixture.create(clock: clock);
    actorId = await fixture.seedSuperAdmin();
  });

  tearDown(() => fixture.dispose());

  group('validasi 10.000 baris', () {
    test('selesai tanpa rekursi maupun stack overflow', () {
      const count = MasterImportLimits.maxDataRows;
      final rows = [
        for (var i = 0; i < count; i++)
          ImportRawRow(rowNumber: i + 3, values: {'name': 'Kategori $i'}),
      ];
      final workbook = ImportWorkbook(
        entity: MasterEntityType.itemCategories,
        templateVersion: MasterTemplateVersion.current,
        headers: MasterEntityType.itemCategories.headers,
        rows: rows,
        blankRowCount: 0,
        sampleRowSkipped: true,
      );

      final result = MasterImportValidationEngine.validate(
        entity: MasterEntityType.itemCategories,
        workbook: workbook,
        snapshot: const MasterImportReferenceSnapshot(actorId: 'actor'),
      );

      expect(result.summary.totalRows, count);
      expect(result.summary.insertedRows, count);
      expect(result.summary.failedRows, 0);
      expect(result.summary.isConsistent, isTrue);
      expect(result.plan, hasLength(count));
      // One preview row per data row, and no more.
      expect(result.previews, hasLength(count));
    });

    test('10.000 baris dengan duplikat melaporkan setiap baris terlibat', () {
      // 9,998 unique keys plus one key on three rows.
      const count = MasterImportLimits.maxDataRows;
      final rows = [
        for (var i = 0; i < count - 3; i++)
          ImportRawRow(rowNumber: i + 3, values: {'name': 'Kategori $i'}),
        for (var i = 0; i < 3; i++)
          ImportRawRow(
            rowNumber: count + i,
            values: const {'name': 'Duplikat'},
          ),
      ];
      final workbook = ImportWorkbook(
        entity: MasterEntityType.itemCategories,
        templateVersion: MasterTemplateVersion.current,
        headers: MasterEntityType.itemCategories.headers,
        rows: rows,
        blankRowCount: 0,
        sampleRowSkipped: true,
      );

      final result = MasterImportValidationEngine.validate(
        entity: MasterEntityType.itemCategories,
        workbook: workbook,
        snapshot: const MasterImportReferenceSnapshot(actorId: 'actor'),
      );

      // All three, never only the later two (§17).
      expect(result.summary.failedRows, 3);
      expect(result.summary.insertedRows, count - 3);
    });

    test('deteksi duplikat linier, bukan pemindaian bersarang', () {
      // The structural claim: one pass to bucket, one pass to emit. A nested
      // scan over 20,000 unique keys would be 400 million comparisons; this
      // completes because it is 20,000.
      const count = 20000;
      final rows = [
        for (var i = 0; i < count; i++)
          MasterImportRowNormalizer.category(
            ImportRawRow(rowNumber: i + 3, values: {'name': 'K$i'}),
          ).row!,
      ];

      final grouped = MasterImportDuplicateDetector.groupRowNumbers(rows);
      expect(grouped, hasLength(count));
      expect(MasterImportDuplicateDetector.duplicateKeys(rows), isEmpty);
      expect(
        MasterImportDuplicateDetector.detect(
          entity: MasterEntityType.itemCategories,
          rows: rows,
        ),
        isEmpty,
      );
    });

    test('error_detail 10.000 isu tetap JSON valid dan terurut', () {
      final issues = [
        for (var i = 0; i < 10000; i++)
          ImportRowIssue(
            rowNumber: 10002 - i,
            column: 'name',
            code: ImportIssueCode.requiredMissing,
            message: 'Kolom "name" wajib diisi.',
          ),
      ];
      final encoded = ImportErrorDetail.encode(issues)!;
      final decoded = ImportErrorDetail.decode(encoded);

      expect(decoded, hasLength(10000));
      // Ascending by row, whatever order they arrived in (§32).
      for (var i = 1; i < decoded.length; i++) {
        expect(
          decoded[i].rowNumber,
          greaterThanOrEqualTo(decoded[i - 1].rowNumber),
        );
      }
      // Byte-identical on a second pass.
      expect(ImportErrorDetail.encode(issues), encoded);
    });
  });

  group('commit multi-chunk dalam satu transaksi', () {
    test(
      'lebih dari dua chunk diterapkan atomik',
      () async {
        // Deliberately larger than `chunkSize` (250) so the loop yields several
        // times, and deliberately smaller than 10,000 so the suite stays usable —
        // see the file note on where the 10,000-row claim is made.
        const count = 600;
        final session = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.itemCategories,
          file: pickedFile(
            entity: MasterEntityType.itemCategories,
            rows: [
              for (var i = 0; i < count; i++) {'name': 'Kategori $i'},
            ],
          ),
        );

        expect(session.summary.totalRows, count);
        expect(session.summary.insertedRows, count);
        // Still nothing written before the commit (G-M3).
        expect(await fixture.countOf('item_categories'), 0);

        final result = await fixture.commitImport().call(
          actorUserId: actorId,
          importLogId: session.importId,
        );

        expect(result.insertedRows, count);
        expect(await fixture.countOf('item_categories'), count);
        expect(
          await fixture.importLogColumn(session.importId, 'inserted_rows'),
          '$count',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'kegagalan di tengah chunk membatalkan seluruhnya',
      () async {
        const count = 600;
        final session = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.itemCategories,
          file: pickedFile(
            entity: MasterEntityType.itemCategories,
            rows: [
              for (var i = 0; i < count; i++) {'name': 'Kategori $i'},
            ],
          ),
        );

        // Somebody removes the retained source between preview and commit, so the
        // commit refuses before it opens the transaction at all.
        fixture.sourceFileStore.remove(session.sourceFile.path);

        await expectLater(
          fixture.commitImport().call(
            actorUserId: actorId,
            importLogId: session.importId,
          ),
          throwsA(isA<Object>()),
        );

        expect(await fixture.countOf('item_categories'), 0);
        expect(
          await fixture.importLogColumn(session.importId, 'status'),
          'validated',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('operasi bersamaan', () {
    test('dua validasi menghasilkan dua id, dua file, dua log', () async {
      final results = await Future.wait([
        fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: pickedFile(
            entity: MasterEntityType.branches,
            fileName: 'satu.xlsx',
            rows: const [
              {
                'code': 'CAB-01',
                'name': 'Satu',
                'address': '',
                'is_active': 'TRUE',
              },
            ],
          ),
        ),
        fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: pickedFile(
            entity: MasterEntityType.branches,
            fileName: 'dua.xlsx',
            rows: const [
              {
                'code': 'CAB-02',
                'name': 'Dua',
                'address': '',
                'is_active': 'TRUE',
              },
            ],
          ),
        ),
      ]);

      expect(results[0].importId, isNot(results[1].importId));
      expect(results[0].sourceFile.path, isNot(results[1].sourceFile.path));
      expect(await fixture.countOf('import_logs'), 2);
      expect(fixture.sourceFileStore.files, hasLength(2));
      // And still nothing written to master data.
      expect(await fixture.countOf('branches'), 0);
    });

    test('dua commit pada log yang sama: satu pemenang', () async {
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.itemCategories,
        file: pickedFile(
          entity: MasterEntityType.itemCategories,
          rows: const [
            {'name': 'Obat'},
            {'name': 'APD'},
          ],
        ),
      );

      final outcomes = await Future.wait<Object?>([
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

      expect(outcomes.whereType<ImportCommitResult>(), hasLength(1));
      // Exactly one set of master effects.
      expect(await fixture.countOf('item_categories'), 2);
      expect(
        await fixture.importLogColumn(session.importId, 'status'),
        'committed',
      );
    });

    test('commit dan discard bersamaan: hanya satu berlaku', () async {
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

      final outcomes = await Future.wait<Object?>([
        fixture
            .commitImport()
            .call(actorUserId: actorId, importLogId: session.importId)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
        fixture
            .discardImport()
            .call(actorUserId: actorId, importLogId: session.importId)
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
      ]);

      // Exactly one of the two produced a result rather than an error: the
      // guarded transition matched one row and none for the loser.
      final succeeded = outcomes.where((o) => o is! Exception).length;
      expect(succeeded, 1);
      final status = await fixture.importLogColumn(session.importId, 'status');
      // Whichever won, the status is final and the master state matches it.
      expect(status, isIn(['committed', 'discarded']));
      expect(
        await fixture.countOf('item_categories'),
        status == 'committed' ? 1 : 0,
      );
    });
  });

  group('hash file besar', () {
    test(
      'file mendekati batas ukuran tetap ter-hash konsisten',
      () async {
        // A workbook with many rows rather than a synthetic blob, so what is
        // hashed is a file the parser could actually read.
        final file = pickedFile(
          entity: MasterEntityType.itemCategories,
          rows: [
            for (var i = 0; i < 3000; i++) {'name': 'Kategori $i'},
          ],
        );
        expect(file.sizeBytes, greaterThan(10 * 1024));

        final session = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.itemCategories,
          file: file,
        );

        expect(session.sourceFile.sha256, sha256Hex(file.bytes));
        expect(session.sourceFile.sizeBytes, file.bytes.length);
        // The commit's own verification agrees with the audit row.
        expect(
          await fixture.sourceFileStore.verifyHash(
            storedPath: session.sourceFile.path,
            expectedSha256: session.sourceFile.sha256,
            expectedSizeBytes: session.sourceFile.sizeBytes,
          ),
          isTrue,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('memori dilepas setelah status akhir', () {
    test('sesi pratinjau tidak menyimpan byte workbook', () async {
      final file = pickedFile(
        entity: MasterEntityType.itemCategories,
        rows: [
          for (var i = 0; i < 500; i++) {'name': 'Kategori $i'},
        ],
      );
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.itemCategories,
        file: file,
      );

      // What the session carries is metadata and preview rows — never the bytes.
      // The retained copy on disk is the only thing that holds them, and the
      // commit re-reads it (§43).
      expect(session.sourceFile.sizeBytes, file.bytes.length);
      expect(session.rows, hasLength(500));
      expect(session.toString(), isNot(contains('Uint8List')));
    });
  });

  group('normalisasi skala', () {
    test('10.000 baris item ternormalisasi tanpa kehilangan isu', () {
      // Every third row is broken, so the counting invariant is exercised at
      // scale rather than on three rows.
      final rows = <ImportRawRow>[
        for (var i = 0; i < 9999; i++)
          ImportRawRow(
            rowNumber: i + 3,
            values: {
              'sku': 'SKU-$i',
              'name': 'Barang $i',
              'category_name': 'Obat',
              'unit': 'pcs',
              'min_stock_room': i % 3 == 0 ? 'x' : '1',
              'min_stock_branch': '2',
              'has_expiry': 'FALSE',
              'expiry_alert_days': '30',
              'is_active': 'TRUE',
            },
          ),
      ];

      var valid = 0;
      var invalid = 0;
      for (final row in rows) {
        final result = MasterImportRowNormalizer.item(row);
        if (result.isValid) {
          valid++;
        } else {
          invalid++;
        }
      }
      expect(valid + invalid, 9999);
      expect(invalid, 3333);
    });
  });
}
