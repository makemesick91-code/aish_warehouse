import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/features/master/domain/models/import_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_normalization_policy.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_workbook_validator.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'master_fixture.dart';

/// G-M2 and §46: *"template Excel per entitas diunduh dari aplikasi"*.
///
/// Every assertion here reads a **real** workbook back. The generator writes
/// `.xlsx` bytes, the test decodes them with the same package the importer uses,
/// and asserts on cells — so what these tests prove is that the file this
/// application produces is the file it can read, not that a builder was called.
void main() {
  late MasterFixture fixture;
  late String actorId;

  DateTime clock() => DateTime.utc(2026, 7, 31, 4, 30);

  setUp(() async {
    fixture = MasterFixture.create(clock: clock);
    actorId = await fixture.seedSuperAdmin();
  });

  tearDown(() => fixture.dispose());

  Future<Excel> generate(MasterEntityType entity) async {
    final result = await fixture.downloadTemplate().call(
      actorUserId: actorId,
      entity: entity,
    );
    final bytes = await fixture.templateFileStore.readBytes(result.artifact);
    // The ZIP magic every `.xlsx` begins with.
    expect(bytes.sublist(0, 2), [0x50, 0x4B]);
    return Excel.decodeBytes(bytes);
  }

  String cellText(Sheet sheet, int row, int column) {
    final value = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .value;
    return switch (value) {
      null => '',
      TextCellValue() => value.value.toString(),
      _ => value.toString(),
    };
  }

  List<String> sheetText(Sheet sheet) => [
    for (final row in sheet.rows)
      for (final cell in row)
        if (cell?.value != null) cell!.value.toString(),
  ];

  for (final entity in MasterEntityType.values) {
    group('template ${entity.dbValue}', () {
      test('workbook valid dengan sheet Data dan Petunjuk', () async {
        final workbook = await generate(entity);
        expect(
          workbook.tables.keys,
          containsAll([
            MasterImportWorkbookValidator.dataSheetName,
            MasterImportWorkbookValidator.instructionsSheetName,
          ]),
        );
        // `createExcel` seeds a `Sheet1`; shipping it would put an empty tab in
        // every template.
        expect(workbook.tables.keys, hasLength(2));
      });

      test('baris 1 adalah header persis, dalam urutan yang benar', () async {
        final workbook = await generate(entity);
        final data =
            workbook.tables[MasterImportWorkbookValidator.dataSheetName]!;
        final headers = [
          for (var column = 0; column < entity.headers.length; column++)
            cellText(data, 0, column),
        ];
        expect(headers, entity.headers);
      });

      test('baris 2 adalah contoh yang terisi penuh dengan sentinel', () async {
        final workbook = await generate(entity);
        final data =
            workbook.tables[MasterImportWorkbookValidator.dataSheetName]!;

        for (var column = 0; column < entity.headers.length; column++) {
          expect(
            cellText(data, 1, column),
            isNotEmpty,
            reason:
                'Kolom ${entity.headers[column]} pada baris contoh kosong '
                '(G-M2 menuntut contoh terisi).',
          );
        }

        // Every natural-key column carries its sentinel (§3.7), so the importer
        // can skip exactly this row and no other.
        for (final entry in entity.sampleSentinels.entries) {
          final index = entity.headers.indexOf(entry.key);
          expect(cellText(data, 1, index), entry.value);
        }
      });

      test('sheet Petunjuk memuat versi, kunci, dan format', () async {
        final workbook = await generate(entity);
        final text = sheetText(
          workbook.tables[MasterImportWorkbookValidator.instructionsSheetName]!,
        );
        final joined = text.join('\n');

        expect(joined, contains(MasterImportWorkbookValidator.versionLabel));
        expect(joined, contains(MasterTemplateVersion.current));
        expect(joined, contains(entity.label));
        expect(joined, contains(entity.naturalKeyLabel));
        expect(
          joined,
          contains(MasterImportNormalizationPolicy.booleanFormatLabel),
        );
        expect(
          joined,
          contains(MasterImportNormalizationPolicy.dateFormatLabel),
        );
        // Required columns are named, so an operator can check their file
        // against the sheet rather than against a failed upload.
        for (final header in entity.requiredHeaders) {
          expect(joined, contains(header));
        }
      });

      test('sheet Petunjuk memuat peringatan wajib', () async {
        final workbook = await generate(entity);
        final joined = sheetText(
          workbook.tables[MasterImportWorkbookValidator.instructionsSheetName]!,
        ).join('\n');

        // The four §13 asks for by name.
        expect(joined, contains('rumus'));
        expect(joined, contains('makro'));
        expect(joined, contains('tidak pernah menghapus'));
        expect(joined, contains('0 baris'));
        expect(joined, contains('historis'));
        expect(joined, contains('Baris contoh'));
      });

      test('tidak ada rumus di seluruh workbook', () async {
        final workbook = await generate(entity);
        for (final sheet in workbook.tables.values) {
          for (final row in sheet.rows) {
            for (final cell in row) {
              expect(
                cell?.value,
                isNot(isA<FormulaCellValue>()),
                reason:
                    'Template tidak boleh berisi rumus — importer menolaknya.',
              );
            }
          }
        }
      });

      test('nama file baku sesuai §26', () async {
        final result = await fixture.downloadTemplate().call(
          actorUserId: actorId,
          entity: entity,
        );
        expect(
          result.artifact.fileName,
          '${entity.templateFileStem}_${MasterTemplateVersion.current}.xlsx',
        );
        expect(result.artifact.version, MasterTemplateVersion.current);
      });

      test('template yang dibuat dapat dibaca kembali oleh importer', () async {
        // The round trip §46 exists for: the generator's own output, parsed by
        // the production parser, yields zero data rows — the sample row is
        // skipped and nothing else is there.
        final result = await fixture.downloadTemplate().call(
          actorUserId: actorId,
          entity: entity,
        );
        final bytes = await fixture.templateFileStore.readBytes(
          result.artifact,
        );

        final session = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: entity,
          file: PickedImportFile(
            originalFileName: result.artifact.fileName,
            bytes: bytes,
          ),
        );

        expect(session.summary.totalRows, 0);
        expect(session.summary.failedRows, 0);
        // Nothing to apply, so the commit is refused — an empty template is not
        // an import.
        expect(session.canCommit, isFalse);
      });

      test('pembuatan template tidak menulis import_logs', () async {
        await fixture.downloadTemplate().call(
          actorUserId: actorId,
          entity: entity,
        );
        // Downloading a template is not an import (§25).
        expect(await fixture.countOf('import_logs'), 0);
      });
    });
  }

  group('daftar nilai dinamis', () {
    test('template ruangan memuat kode cabang yang ada', () async {
      await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Cabang Satu',
      );
      await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-02',
        name: 'Cabang Dua',
      );

      final workbook = await generate(MasterEntityType.rooms);
      final joined = sheetText(
        workbook.tables[MasterImportWorkbookValidator.instructionsSheetName]!,
      ).join('\n');
      expect(joined, contains('CAB-01'));
      expect(joined, contains('CAB-02'));
    });

    test('template barang memuat kategori yang ada', () async {
      await fixture.createCategory.call(
        actorUserId: actorId,
        name: 'Bahan Tambal',
      );

      final workbook = await generate(MasterEntityType.items);
      final joined = sheetText(
        workbook.tables[MasterImportWorkbookValidator.instructionsSheetName]!,
      ).join('\n');
      expect(joined, contains('Bahan Tambal'));
    });

    test('template batch hanya memuat SKU ber-kedaluwarsa', () async {
      final category = await fixture.createCategory.call(
        actorUserId: actorId,
        name: 'Obat',
      );
      await fixture.createItem.call(
        actorUserId: actorId,
        sku: 'EXP-0001',
        name: 'Dengan ED',
        categoryId: category.id,
        unit: 'botol',
        hasExpiry: true,
      );
      await fixture.createItem.call(
        actorUserId: actorId,
        sku: 'NOEXP-0001',
        name: 'Tanpa ED',
        categoryId: category.id,
        unit: 'pcs',
      );

      final workbook = await generate(MasterEntityType.itemBatches);
      final joined = sheetText(
        workbook.tables[MasterImportWorkbookValidator.instructionsSheetName]!,
      ).join('\n');
      expect(joined, contains('EXP-0001'));
      // Listing every SKU would invite exactly the row the validator then has to
      // refuse (§14.6).
      expect(joined, isNot(contains('NOEXP-0001')));
    });

    test('template pengguna memuat keempat peran', () async {
      final workbook = await generate(MasterEntityType.users);
      final joined = sheetText(
        workbook.tables[MasterImportWorkbookValidator.instructionsSheetName]!,
      ).join('\n');
      for (final role in MasterImportNormalizationPolicy.allowedRoles) {
        expect(joined, contains(role));
      }
    });
  });

  group('G-M1 dan offline', () {
    test('peran selain super_admin tidak dapat mengunduh template', () async {
      final other = await fixture.seedUser(
        id: 'warehouse-1',
        email: 'wh@aish.id',
        role: UserRole.warehouse,
      );

      await expectLater(
        fixture.downloadTemplate().call(
          actorUserId: other,
          entity: MasterEntityType.items,
        ),
        throwsA(isA<Object>()),
      );
      expect(fixture.templateFileStore.files, isEmpty);
    });

    test('template dibuat sepenuhnya lokal', () async {
      // No network client is wired anywhere in this path, and the share gateway
      // is a fake — so a successful generation is proof the whole flow is local
      // (G-L3's offline-first, applied to G-M2).
      final result = await fixture.downloadTemplate().call(
        actorUserId: actorId,
        entity: MasterEntityType.items,
      );
      expect(result.artifact.byteLength, greaterThan(0));
      expect(fixture.shareGateway.shared, hasLength(1));
    });

    test('share yang dibatalkan tetap menghasilkan file', () async {
      fixture.shareGateway.outcome = MasterTemplateShareOutcome.cancelled;
      final result = await fixture.downloadTemplate().call(
        actorUserId: actorId,
        entity: MasterEntityType.items,
      );
      expect(result.shareOutcome, MasterTemplateShareOutcome.cancelled);
      expect(await fixture.templateFileStore.exists(result.artifact), isTrue);
    });
  });
}
