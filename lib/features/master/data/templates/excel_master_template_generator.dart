import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../../core/errors/failures.dart';
import '../../../reports/domain/services/spreadsheet_cell_sanitizer.dart';
import '../../domain/gateways/master_import_gateways.dart';
import '../../domain/models/import_models.dart';
import '../../domain/services/master_import_workbook_validator.dart';
import '../../domain/services/master_template_catalog.dart';

/// Writes one entity's template as a real `.xlsx` (G-M2, §25).
///
/// ### Two sheets, and both are required by the rule
///
/// *Data* carries row 1 (headers), row 2 (the filled sample) and nothing else.
/// *Petunjuk* carries the version, the column guide, the valid-value lists and
/// the warnings. G-M2 asks for exactly this shape, and the parser refuses a
/// workbook missing either — which is what makes the round trip closed: this
/// class writes the only file shape [MasterImportWorkbookValidator] accepts.
///
/// ### Every cell is text, and identifier columns especially
///
/// `007` is a branch code, not the number seven, and a numeric cell is how it
/// becomes one. Every value written here is a `TextCellValue`, so a code with
/// leading zeros survives the round trip through Excel and back into the parser.
/// The same applies to `expiry_date`: an ISO string is unambiguous, while a date
/// cell is interpreted against whatever locale opened the file last.
///
/// Every string goes through [SpreadsheetCellSanitizer] first — reused from the
/// reporting module rather than reimplemented, because a category name beginning
/// with `=` is a formula waiting for an auditor to open it, and that reasoning is
/// already written down there.
///
/// ### What this class must not do
///
/// * **No query.** It receives a finished [MasterTemplateDefinition]; the
///   dynamic value lists were read from Drift by the use case.
/// * **No database write, and no `import_logs` row.** Downloading a template is
///   not an import (§25).
/// * **No formula, no macro, no external link.** Nothing here writes a
///   `FormulaCellValue`, and the file is a plain `.xlsx` rather than an `.xlsm` —
///   which is also what makes the *"tidak ada rumus"* template test assertable.
class ExcelMasterTemplateGenerator implements MasterTemplateGenerator {
  const ExcelMasterTemplateGenerator();

  @override
  Future<Uint8List> generate(MasterTemplateDefinition definition) async {
    try {
      final workbook = Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet();

      _writeDataSheet(
        workbook[MasterImportWorkbookValidator.dataSheetName],
        definition,
      );
      _writeInstructionsSheet(
        workbook[MasterImportWorkbookValidator.instructionsSheetName],
        definition,
      );

      // `createExcel` seeds a `Sheet1`; leaving it would ship every template with
      // an empty tab, and a parser that scanned sheets by position rather than by
      // name would find it first. Deleted after both real sheets exist, because a
      // workbook with no sheets is not a valid workbook.
      if (defaultSheet != null &&
          defaultSheet != MasterImportWorkbookValidator.dataSheetName &&
          defaultSheet != MasterImportWorkbookValidator.instructionsSheetName) {
        workbook.delete(defaultSheet);
      }
      workbook.setDefaultSheet(MasterImportWorkbookValidator.dataSheetName);

      final bytes = workbook.encode();
      if (bytes == null || bytes.isEmpty) {
        throw ImportSourceFileWriteFailure(
          'Template gagal dibuat. Silakan coba lagi.',
          fileName: definition.fileName,
        );
      }
      return Uint8List.fromList(bytes);
    } on ImportSourceFileWriteFailure {
      rethrow;
    } catch (_) {
      // The underlying error names package internals, and §45 keeps those out of
      // anything a user reads.
      throw ImportSourceFileWriteFailure(
        'Template gagal dibuat. Silakan coba lagi.',
        fileName: definition.fileName,
      );
    }
  }

  // --- Data -------------------------------------------------------------------

  void _writeDataSheet(Sheet sheet, MasterTemplateDefinition definition) {
    final headers = definition.headers;

    for (var column = 0; column < headers.length; column++) {
      _put(
        sheet,
        MasterImportWorkbookValidator.headerRowNumber - 1,
        column,
        headers[column],
        style: _headerStyle,
      );
    }

    for (var column = 0; column < headers.length; column++) {
      _put(
        sheet,
        MasterImportWorkbookValidator.sampleRowNumber - 1,
        column,
        definition.sampleRow[headers[column]] ?? '',
        style: _sampleStyle,
      );
    }

    for (var column = 0; column < headers.length; column++) {
      sheet.setColumnWidth(column, _widthFor(headers[column]));
    }
  }

  /// Wide enough that a header is readable without resizing, and no wider.
  ///
  /// A guess per column name rather than a measurement, because `excel` has no
  /// auto-fit API — the same limitation the reporting exporter documents.
  double _widthFor(String header) => switch (header) {
    'address' || 'name' || 'full_name' => 32,
    'email' => 28,
    'category_name' || 'branch_code' || 'item_sku' => 20,
    'sku' || 'batch_no' || 'expiry_date' || 'role' => 18,
    _ => 16,
  };

  // --- Petunjuk ----------------------------------------------------------------

  void _writeInstructionsSheet(
    Sheet sheet,
    MasterTemplateDefinition definition,
  ) {
    var row = 0;

    _put(sheet, row++, 0, 'Petunjuk Pengisian Template', style: _titleStyle);
    _put(sheet, row++, 0, 'Aish Warehouse', style: _labelStyle);
    row++;

    for (final entry in MasterTemplateCatalog.metadataRows(definition)) {
      _put(sheet, row, 0, entry.label, style: _labelStyle);
      _put(sheet, row, 1, entry.value);
      row++;
    }
    row++;

    _put(sheet, row++, 0, 'Arti Kolom', style: _headingStyle);
    for (final (index, label) in const [
      'Kolom',
      'Wajib',
      'Keterangan',
      'Format',
    ].indexed) {
      _put(sheet, row, index, label, style: _headerStyle);
    }
    row++;

    for (final column in definition.columns) {
      _put(sheet, row, 0, column.column);
      _put(sheet, row, 1, column.isRequired ? 'Wajib' : 'Opsional');
      _put(sheet, row, 2, column.meaning, style: _wrapStyle);
      _put(sheet, row, 3, column.format ?? 'teks', style: _wrapStyle);
      row++;
    }
    row++;

    // The dynamic lists. Each is written only when the entity has one, and each
    // is written as a *list* rather than a sentence so an operator can copy a
    // value out of the cell verbatim.
    for (final column in definition.columns) {
      if (column.allowedValues.isEmpty) continue;
      _put(
        sheet,
        row++,
        0,
        'Nilai valid untuk "${column.column}"',
        style: _headingStyle,
      );
      if (column.allowedValues.isEmpty) {
        _put(sheet, row++, 0, '(belum ada data)');
      }
      for (final value in column.allowedValues) {
        _put(sheet, row++, 0, value);
      }
      row++;
    }

    _put(sheet, row++, 0, 'Hal Penting', style: _headingStyle);
    for (final note in definition.notes) {
      _put(sheet, row++, 0, note, style: _wrapStyle);
    }

    sheet.setColumnWidth(0, 34);
    sheet.setColumnWidth(1, 14);
    sheet.setColumnWidth(2, 62);
    sheet.setColumnWidth(3, 34);
  }

  // --- cells --------------------------------------------------------------------

  void _put(Sheet sheet, int row, int column, String text, {CellStyle? style}) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    );
    // `TextCellValue` on every cell, always — see the class note on `007`.
    cell.value = TextCellValue(SpreadsheetCellSanitizer.sanitize(text));
    if (style != null) cell.cellStyle = style;
  }

  static final CellStyle _titleStyle = CellStyle(bold: true, fontSize: 14);
  static final CellStyle _headingStyle = CellStyle(bold: true, fontSize: 12);
  static final CellStyle _labelStyle = CellStyle(bold: true);
  static final CellStyle _headerStyle = CellStyle(
    bold: true,
    textWrapping: TextWrapping.WrapText,
    verticalAlign: VerticalAlign.Center,
  );
  static final CellStyle _sampleStyle = CellStyle(
    italic: true,
    textWrapping: TextWrapping.WrapText,
    verticalAlign: VerticalAlign.Top,
  );
  static final CellStyle _wrapStyle = CellStyle(
    textWrapping: TextWrapping.WrapText,
    verticalAlign: VerticalAlign.Top,
  );
}
