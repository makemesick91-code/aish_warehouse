import 'dart:typed_data';

import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/master/data/import/excel_master_import_workbook_parser.dart';
import 'package:aish_warehouse/features/master/domain/models/import_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_duplicate_detector.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_normalization_policy.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_row_normalizer.dart';
import 'package:aish_warehouse/features/master/domain/services/master_import_workbook_validator.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'master_fixture.dart';

/// §55 (cell types and parser behaviour) and §16 (normalization).
///
/// Split in two: the **parser** turns cells into trimmed strings and refuses
/// structural problems, and the **normalizer** turns those strings into typed
/// rows and collects per-cell issues. Neither knows about the other's job, which
/// is why each can be tested against inputs the other never produces.
void main() {
  const parser = ExcelMasterImportWorkbookParser();

  ImportWorkbook parse({
    required MasterEntityType entity,
    required Uint8List bytes,
    String fileName = 'master.xlsx',
  }) => parser.parse(entity: entity, bytes: bytes, fileName: fileName);

  group('§55 tipe sel', () {
    test('teks dibaca apa adanya, dengan whitespace dipangkas', () {
      final workbook = parse(
        entity: MasterEntityType.branches,
        bytes: buildWorkbookBytes(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': '  CAB-01  ',
              'name': '  Cabang Satu ',
              'address': '   ',
              'is_active': ' TRUE ',
            },
          ],
        ),
      );
      final row = workbook.rows.single;
      expect(row['code'], 'CAB-01');
      expect(row['name'], 'Cabang Satu');
      // Whitespace-only is empty, so `address` reads as absent rather than as a
      // three-space address.
      expect(row['address'], '');
    });

    test('sel kosong dibaca sebagai string kosong', () {
      final workbook = parse(
        entity: MasterEntityType.branches,
        bytes: buildWorkbookBytes(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Satu',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );
      expect(workbook.rows.single['address'], '');
    });

    test('sel integer dibaca tanpa notasi desimal', () {
      final workbook = parse(
        entity: MasterEntityType.items,
        bytes: buildWorkbookBytes(
          entity: MasterEntityType.items,
          rows: [
            {
              'sku': 'DEN-1',
              'name': 'Barang',
              'category_name': 'Obat',
              'unit': 'pcs',
              'min_stock_room': '',
              'min_stock_branch': '',
              'has_expiry': 'FALSE',
              'expiry_alert_days': '',
              'is_active': 'TRUE',
            },
          ],
          intCells: const {
            '3:min_stock_room': 5,
            '3:min_stock_branch': 20,
            '3:expiry_alert_days': 30,
          },
        ),
      );
      final row = workbook.rows.single;
      expect(row['min_stock_room'], '5');
      expect(row['min_stock_branch'], '20');
      expect(row['expiry_alert_days'], '30');
    });

    test('sel berisi rumus ditolak, tidak dievaluasi', () {
      expect(
        () => parse(
          entity: MasterEntityType.branches,
          bytes: buildWorkbookBytes(
            entity: MasterEntityType.branches,
            rows: [
              {
                'code': 'CAB-01',
                'name': '',
                'address': '',
                'is_active': 'TRUE',
              },
            ],
            formulaCells: const {'3:name': 'CONCAT(A1,"x")'},
          ),
        ),
        throwsA(isA<ImportFormulaCellFailure>()),
      );
    });

    test('teks yang mirip rumus tetap diperlakukan literal', () {
      // A category *named* `=SUM(A1)` is a string cell, not a formula cell — the
      // cell's type decides, not its first character.
      final workbook = parse(
        entity: MasterEntityType.itemCategories,
        bytes: buildWorkbookBytes(
          entity: MasterEntityType.itemCategories,
          rows: const [
            {'name': '=SUM(A1)'},
          ],
        ),
      );
      expect(workbook.rows.single['name'], '=SUM(A1)');
    });

    test('kode dengan angka nol di depan bertahan sebagai teks', () {
      final workbook = parse(
        entity: MasterEntityType.branches,
        bytes: buildWorkbookBytes(
          entity: MasterEntityType.branches,
          rows: const [
            {
              'code': '007',
              'name': 'Nol Depan',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );
      expect(workbook.rows.single['code'], '007');
    });

    test('nama unicode bertahan', () {
      final workbook = parse(
        entity: MasterEntityType.itemCategories,
        bytes: buildWorkbookBytes(
          entity: MasterEntityType.itemCategories,
          rows: const [
            {'name': 'Perlengkapan Bedah — Ünïcödé 中文'},
          ],
        ),
      );
      expect(workbook.rows.single['name'], 'Perlengkapan Bedah — Ünïcödé 中文');
    });

    test('baris kosong dilewati dan dihitung', () {
      final workbook = parse(
        entity: MasterEntityType.branches,
        bytes: buildWorkbookBytes(
          entity: MasterEntityType.branches,
          rows: const [
            {
              'code': 'CAB-01',
              'name': 'Satu',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
          blankRowsAfter: 4,
        ),
      );
      expect(workbook.rows, hasLength(1));
      expect(workbook.blankRowCount, greaterThanOrEqualTo(1));
    });

    test('baris contoh dilewati tepat satu kali', () {
      final workbook = parse(
        entity: MasterEntityType.branches,
        bytes: buildWorkbookBytes(
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
      expect(workbook.sampleRowSkipped, isTrue);
      expect(workbook.rows, hasLength(1));
      expect(workbook.rows.single.rowNumber, 3);
    });

    test('sentinel di baris selain baris 2 tidak dilewati', () {
      // A row further down carrying the sentinel was typed by a person. Skipping
      // it would silently drop data the operator believes they imported; it goes
      // through validation and fails there instead (§3.7).
      final workbook = parse(
        entity: MasterEntityType.branches,
        bytes: buildWorkbookBytes(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': MasterEntityType.branches.sampleSentinel,
              'name': 'Disalin',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );
      expect(workbook.rows, hasLength(1));
      expect(
        workbook.rows.single['code'],
        MasterEntityType.branches.sampleSentinel,
      );
    });

    test('teks sangat panjang ditolak di atas batas sel', () {
      expect(
        () => parse(
          entity: MasterEntityType.branches,
          bytes: buildWorkbookBytes(
            entity: MasterEntityType.branches,
            rows: [
              {
                'code': 'CAB-01',
                'name': 'x' * (MasterImportLimits.maxCellCharacters + 1),
                'address': '',
                'is_active': 'TRUE',
              },
            ],
          ),
        ),
        throwsA(isA<ImportRowLimitFailure>()),
      );
    });

    test(
      'jumlah baris di atas batas ditolak',
      () {
        expect(
          () => parse(
            entity: MasterEntityType.itemCategories,
            bytes: buildWorkbookBytes(
              entity: MasterEntityType.itemCategories,
              rows: [
                for (var i = 0; i <= MasterImportLimits.maxDataRows; i++)
                  {'name': 'Kategori $i'},
              ],
            ),
          ),
          throwsA(isA<ImportRowLimitFailure>()),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'tepat pada batas 10.000 baris diterima',
      () {
        final workbook = parse(
          entity: MasterEntityType.itemCategories,
          bytes: buildWorkbookBytes(
            entity: MasterEntityType.itemCategories,
            rows: [
              for (var i = 0; i < MasterImportLimits.maxDataRows; i++)
                {'name': 'Kategori $i'},
            ],
          ),
        );
        expect(workbook.rows, hasLength(MasterImportLimits.maxDataRows));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('§16 normalisasi', () {
    ImportRawRow raw(Map<String, String> values, {int rowNumber = 3}) =>
        ImportRawRow(rowNumber: rowNumber, values: values);

    test('boolean menerima empat ejaan dan menolak sisanya', () {
      for (final value in const ['TRUE', 'true', 'True', 'tRuE']) {
        expect(
          MasterImportNormalizationPolicy.boolean(value),
          isTrue,
          reason: value,
        );
      }
      for (final value in const ['FALSE', 'false', 'False']) {
        expect(
          MasterImportNormalizationPolicy.boolean(value),
          isFalse,
          reason: value,
        );
      }
      // Every one of these is a spelling somebody will try, and every one is
      // refused with a message naming the two that work (§16).
      for (final value in const [
        '1',
        '0',
        'ya',
        'tidak',
        'Y',
        'N',
        'yes',
        'no',
        'on',
        'off',
        '',
        '  ',
      ]) {
        expect(
          MasterImportNormalizationPolicy.boolean(value),
          isNull,
          reason: value,
        );
      }
    });

    test('integer diparse persis, pecahan dan notasi ilmiah ditolak', () {
      expect(MasterImportNormalizationPolicy.nonNegativeInteger('12'), 12);
      expect(MasterImportNormalizationPolicy.nonNegativeInteger(' 0 '), 0);
      // Excel writes whole numbers back as `12.0` often enough that refusing it
      // would fail files that are unambiguously correct.
      expect(MasterImportNormalizationPolicy.nonNegativeInteger('12.0'), 12);
      for (final value in const ['12.5', '-1', '1e3', '1,000', 'x', '']) {
        expect(
          MasterImportNormalizationPolicy.nonNegativeInteger(value),
          isNull,
          reason: value,
        );
      }
    });

    test('tanggal hanya ISO, dan tidak pernah dikonversi zona waktu', () {
      final parsed = MasterImportNormalizationPolicy.isoDate('2026-12-31');
      expect(parsed, DateOnly.of(2026, 12, 31));
      expect(parsed!.isUtc, isTrue);
      expect(parsed.hour, 0);
      for (final value in const [
        '31/12/2026',
        '2026-13-01',
        '2026-12-32',
        '31 Des 2026',
        '',
      ]) {
        expect(
          MasterImportNormalizationPolicy.isoDate(value),
          isNull,
          reason: value,
        );
      }
    });

    test('email dijadikan huruf kecil, nama tetap apa adanya', () {
      final result = MasterImportRowNormalizer.user(
        raw(const {
          'full_name': '  Budi Santoso ',
          'email': '  Budi@Klinik.ID ',
          'role': ' Warehouse ',
          'branch_code': '',
          'is_active': 'TRUE',
        }),
      );
      expect(result.isValid, isTrue);
      expect(result.row!.email, 'budi@klinik.id');
      // Preserved verbatim: nothing here title-cases or upper-cases a name.
      expect(result.row!.fullName, 'Budi Santoso');
      expect(result.row!.role, UserRole.warehouse);
      expect(result.row!.branchCode, isNull);
    });

    test('nama kategori tetap ejaannya, hanya kuncinya yang dilipat', () {
      final result = MasterImportRowNormalizer.category(
        raw(const {'name': 'Bahan Tambal'}),
      );
      expect(result.row!.name, 'Bahan Tambal');
      expect(result.row!.naturalKey, 'bahan tambal');
    });

    test('kunci ruangan adalah cabang + kode', () {
      final result = MasterImportRowNormalizer.room(
        raw(const {
          'branch_code': 'CAB-01',
          'code': 'R1',
          'name': 'Ruang',
          'is_active': 'TRUE',
        }),
      );
      expect(
        result.row!.naturalKey,
        'cab-01${MasterImportNormalizationPolicy.keySeparator}r1',
      );
      expect(result.row!.naturalKeyDisplay, 'CAB-01 / R1');
    });

    test('kunci komposit tidak dapat bertabrakan lewat separator', () {
      // `('A B', 'C')` and `('A', 'B C')` must be two different keys.
      expect(
        MasterImportNormalizationPolicy.compositeKey(['A B', 'C']),
        isNot(MasterImportNormalizationPolicy.compositeKey(['A', 'B C'])),
      );
    });

    test('satu baris melaporkan seluruh masalahnya sekaligus', () {
      final result = MasterImportRowNormalizer.item(
        raw(const {
          'sku': '',
          'name': '',
          'category_name': '',
          'unit': '',
          'min_stock_room': 'x',
          'min_stock_branch': '-1',
          'has_expiry': 'ya',
          'expiry_alert_days': '1.5',
          'is_active': '1',
        }),
      );
      expect(result.isValid, isFalse);
      // Nine columns, nine problems — never the first one only (§29).
      expect(result.issues, hasLength(9));
      expect(
        result.issues.map((issue) => issue.column).toSet(),
        MasterEntityType.items.headers.toSet(),
      );
    });

    test('identifier berbentuk notasi ilmiah ditolak', () {
      final result = MasterImportRowNormalizer.item(
        raw(const {
          'sku': '1.0E+12',
          'name': 'Barang',
          'category_name': 'Obat',
          'unit': 'pcs',
          'min_stock_room': '0',
          'min_stock_branch': '0',
          'has_expiry': 'FALSE',
          'expiry_alert_days': '30',
          'is_active': 'TRUE',
        }),
      );
      expect(result.isValid, isFalse);
      expect(result.issues.single.message, contains('angka ilmiah'));
    });

    test('email yang bukan email ditolak', () {
      final result = MasterImportRowNormalizer.user(
        raw(const {
          'full_name': 'Budi',
          'email': '12345',
          'role': 'warehouse',
          'branch_code': '',
          'is_active': 'TRUE',
        }),
      );
      expect(result.isValid, isFalse);
      expect(result.issues.single.code, ImportIssueCode.invalidEmail);
    });

    test('peran yang tidak dikenal ditolak dengan daftar yang valid', () {
      final result = MasterImportRowNormalizer.user(
        raw(const {
          'full_name': 'Budi',
          'email': 'budi@aish.id',
          'role': 'manajer',
          'branch_code': '',
          'is_active': 'TRUE',
        }),
      );
      expect(result.isValid, isFalse);
      final issue = result.issues.single;
      expect(issue.code, ImportIssueCode.invalidRole);
      for (final role in MasterImportNormalizationPolicy.allowedRoles) {
        expect(issue.message, contains(role));
      }
    });
  });

  group('§17 deteksi duplikat', () {
    test('semua baris yang berbagi kunci dilaporkan', () {
      final rows = [
        for (final entry in const [
          (3, 'CAB-01'),
          (4, 'CAB-02'),
          (5, 'cab-01'),
          (6, 'CAB-01'),
        ])
          MasterImportRowNormalizer.branch(
            ImportRawRow(
              rowNumber: entry.$1,
              values: {
                'code': entry.$2,
                'name': 'X',
                'address': '',
                'is_active': 'TRUE',
              },
            ),
          ).row!,
      ];

      final issues = MasterImportDuplicateDetector.detect(
        entity: MasterEntityType.branches,
        rows: rows,
      );
      expect(issues.map((issue) => issue.rowNumber).toSet(), {3, 5, 6});
      expect(MasterImportDuplicateDetector.duplicateKeys(rows), {'cab-01'});
      // Sorted deterministically, so `error_detail` is byte-identical across
      // runs (§32).
      expect(issues.map((issue) => issue.rowNumber).toList(), [3, 5, 6]);
    });

    test('kunci unik tidak menghasilkan isu', () {
      final rows = [
        for (var i = 0; i < 200; i++)
          MasterImportRowNormalizer.branch(
            ImportRawRow(
              rowNumber: i + 3,
              values: {
                'code': 'CAB-$i',
                'name': 'X',
                'address': '',
                'is_active': 'TRUE',
              },
            ),
          ).row!,
      ];
      expect(
        MasterImportDuplicateDetector.detect(
          entity: MasterEntityType.branches,
          rows: rows,
        ),
        isEmpty,
      );
    });
  });

  group('§32 error_detail JSON', () {
    test('urutan deterministik dan hanya berisi error', () {
      final issues = [
        const ImportRowIssue(
          rowNumber: 5,
          column: 'name',
          code: 'b',
          message: 'B',
        ),
        const ImportRowIssue(
          rowNumber: 3,
          column: 'code',
          code: 'a',
          message: 'A',
        ),
        const ImportRowIssue.warning(
          rowNumber: 4,
          column: 'is_active',
          code: 'w',
          message: 'W',
        ),
      ];

      final encoded = ImportErrorDetail.encode(issues)!;
      final decoded = ImportErrorDetail.decode(encoded);
      expect(decoded.map((issue) => issue.rowNumber), [3, 5]);
      // Warnings are not failures, so a column whose purpose is explaining
      // `failed_rows` must not describe rows that succeeded.
      expect(encoded, isNot(contains('"w"')));
      // Same input, same bytes.
      expect(ImportErrorDetail.encode(issues), encoded);
    });

    test('tanpa error menghasilkan null', () {
      expect(ImportErrorDetail.encode(const []), isNull);
      expect(
        ImportErrorDetail.encode(const [
          ImportRowIssue.warning(
            rowNumber: 3,
            column: '',
            code: 'w',
            message: 'W',
          ),
        ]),
        isNull,
      );
    });

    test('JSON rusak dibaca sebagai kosong, bukan melempar', () {
      expect(ImportErrorDetail.decode('bukan json'), isEmpty);
      expect(ImportErrorDetail.decode(null), isEmpty);
      expect(ImportErrorDetail.decode('   '), isEmpty);
    });
  });

  group('§15 tanda tangan file', () {
    test('bytes yang bukan ZIP ditolak sebelum parser dibuka', () {
      expect(
        MasterImportWorkbookValidator.looksLikeXlsx([1, 2, 3, 4]),
        isFalse,
      );
      expect(
        MasterImportWorkbookValidator.looksLikeXlsx([0x50, 0x4B, 0x03, 0x04]),
        isTrue,
      );
    });

    test('workbook tanpa header sama sekali ditolak', () {
      final workbook = Excel.createExcel();
      workbook[MasterImportWorkbookValidator.dataSheetName];
      workbook[MasterImportWorkbookValidator.instructionsSheetName]
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = TextCellValue(
        MasterImportWorkbookValidator.versionLabel,
      );
      workbook[MasterImportWorkbookValidator.instructionsSheetName]
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
          .value = TextCellValue(
        MasterTemplateVersion.current,
      );

      expect(
        () => parse(
          entity: MasterEntityType.branches,
          bytes: Uint8List.fromList(workbook.encode()!),
        ),
        throwsA(isA<ImportHeaderMismatchFailure>()),
      );
    });
  });
}
