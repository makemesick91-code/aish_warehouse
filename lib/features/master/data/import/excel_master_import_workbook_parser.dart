import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/time/date_only.dart';
import '../../domain/models/import_models.dart';
import '../../domain/models/master_admin_models.dart';
import '../../domain/services/master_import_normalization_policy.dart';
import '../../domain/services/master_import_workbook_validator.dart';
import '../../domain/use_cases/validate_master_import_use_case.dart';

/// Reads an uploaded `.xlsx` into [ImportRawRow]s (§15).
///
/// ### The only class in this module that knows what OOXML is
///
/// Every business rule lives in the domain; this turns cells into trimmed
/// strings and applies the structural checks
/// [MasterImportWorkbookValidator] states. The split is what lets §15's twenty
/// refusals be tested against lists of strings rather than against files.
///
/// ### Formulas are refused, never evaluated
///
/// `excel` exposes a formula cell as [FormulaCellValue], and this class throws on
/// one rather than reading whatever cached result the writing application left
/// behind. Two reasons, and the second is the important one: a cached result is a
/// fact about the machine that last opened the file, and an import must mean what
/// the file *says*; and evaluating a formula would make importing a spreadsheet a
/// code-execution path.
///
/// Text that merely *looks* like a formula — a category literally named `=A1` —
/// is a string cell and is imported verbatim. It is the cell's *type* that
/// decides, not its first character.
///
/// ### Dates
///
/// ISO text is the contract, because the template writes ISO text. A
/// [DateCellValue] is also accepted, because a user who retyped the column and
/// let Excel format it as a date produced something this library converts to
/// calendar fields **deterministically** — year, month and day, with no timezone
/// in the path. It is rendered straight back to `YYYY-MM-DD` and handed to the
/// normalizer as if it had been text, so exactly one code path parses a date.
/// [DateTimeCellValue] is treated the same way, with its time discarded: a civil
/// date has no time (T-8).
///
/// Anything else — a bare serial number in a numeric cell — is **refused**. There
/// is no unambiguous conversion: Excel's epoch depends on the workbook's 1904 flag
/// and its leap-year bug, and guessing wrong shifts an expiry date by four years
/// or one day.
class ExcelMasterImportWorkbookParser {
  const ExcelMasterImportWorkbookParser();

  /// Parses [bytes] for [entity], applying every structural check of §15.
  ///
  /// Throws exactly one failure and stops: a workbook whose headers are wrong has
  /// no rows worth reporting on. Per-*row* problems are the validator's, and those
  /// are collected rather than thrown (§29).
  ImportWorkbook parse({
    required MasterEntityType entity,
    required Uint8List bytes,
    required String fileName,
  }) {
    MasterImportWorkbookValidator.ensureLooksLikeXlsx(
      bytes: bytes,
      fileName: fileName,
    );

    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      // Truncated, not really a ZIP, or password-protected — all four of §15's
      // "cannot open it" cases arrive here, and all four have the same fix.
      throw ImportWorkbookCorruptFailure(
        'File tidak dapat dibaca. Pastikan file tidak rusak atau terkunci '
        'kata sandi, lalu simpan ulang sebagai .xlsx.',
        fileName: fileName,
      );
    }

    MasterImportWorkbookValidator.ensureSheetsPresent(workbook.tables.keys);

    final instructions =
        workbook.tables[MasterImportWorkbookValidator.instructionsSheetName]!;
    MasterImportWorkbookValidator.ensureSupportedTemplateVersion(
      _readTemplateVersion(instructions),
    );

    final data = workbook.tables[MasterImportWorkbookValidator.dataSheetName]!;
    final headerRow = data.rows.isEmpty
        ? const <Data?>[]
        : data.rows[MasterImportWorkbookValidator.headerRowNumber - 1];
    final headers = headerRow
        .map((cell) => _cellText(cell, rowNumber: 1, column: '').trim())
        .toList(growable: false);
    MasterImportWorkbookValidator.ensureHeadersMatch(
      entity: entity,
      found: headers,
    );

    final expectedHeaders = entity.headers;
    final rows = <ImportRawRow>[];
    var blankRowCount = 0;
    var sampleRowSkipped = false;

    for (
      var index = MasterImportWorkbookValidator.sampleRowNumber - 1;
      index < data.rows.length;
      index++
    ) {
      final rowNumber = index + 1;
      final cells = data.rows[index];

      final values = <String, String>{};
      for (var column = 0; column < expectedHeaders.length; column++) {
        final header = expectedHeaders[column];
        final cell = column < cells.length ? cells[column] : null;
        final text = _cellText(cell, rowNumber: rowNumber, column: header);
        MasterImportWorkbookValidator.ensureCellWithinLength(
          rowNumber: rowNumber,
          column: header,
          value: text,
        );
        values[header] = text;
      }

      final raw = ImportRawRow(rowNumber: rowNumber, values: values);

      // A row of nothing is not a row (§15). Hidden rows are **not** skipped:
      // `excel` does not surface row visibility, and a row an operator hid is
      // still a row they filled — silently dropping it would import less than the
      // file contains and say nothing about it.
      if (raw.isBlank) {
        blankRowCount++;
        continue;
      }

      // Exactly one sample row is ever skipped, and only at row 2 — the position
      // the generator writes it to. A row further down carrying the sentinels was
      // typed by a person, and it fails validation loudly rather than vanishing.
      if (rowNumber == MasterImportWorkbookValidator.sampleRowNumber &&
          !sampleRowSkipped &&
          MasterImportWorkbookValidator.isSampleRow(entity: entity, row: raw)) {
        sampleRowSkipped = true;
        continue;
      }

      rows.add(raw);
      // Checked inside the loop rather than after it, so a hostile 200,000-row
      // workbook is refused at row 10,001 instead of being fully materialized
      // first (§58).
      MasterImportWorkbookValidator.ensureWithinRowLimit(rows.length);
    }

    return ImportWorkbook(
      entity: entity,
      templateVersion: MasterTemplateVersion.current,
      headers: expectedHeaders,
      rows: rows,
      blankRowCount: blankRowCount,
      sampleRowSkipped: sampleRowSkipped,
    );
  }

  /// Finds the template version on the *Petunjuk* sheet.
  ///
  /// By **label** in column A rather than by cell address, so adding a metadata
  /// row above it in some later template does not silently make every older file
  /// unreadable. `null` when the label is absent, which the validator turns into
  /// *"unsupported template"* rather than a crash.
  String? _readTemplateVersion(Sheet sheet) {
    for (final row in sheet.rows) {
      if (row.isEmpty) continue;
      final label = _plainText(row.first);
      if (label.trim() != MasterImportWorkbookValidator.versionLabel) continue;
      if (row.length < 2) return null;
      final value = _plainText(row[1]).trim();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  /// A cell's text without any of the refusals — used only for reading the
  /// *Petunjuk* metadata, where a formula is somebody's own annotation and not
  /// data this module imports.
  String _plainText(Data? cell) {
    final value = cell?.value;
    return switch (value) {
      null => '',
      TextCellValue() => value.value.toString(),
      IntCellValue() => value.value.toString(),
      DoubleCellValue() => value.value.toString(),
      BoolCellValue() => value.value ? 'TRUE' : 'FALSE',
      DateCellValue() => DateOnly.formatIso(
        DateTime.utc(value.year, value.month, value.day),
      ),
      DateTimeCellValue() => DateOnly.formatIso(
        DateTime.utc(value.year, value.month, value.day),
      ),
      TimeCellValue() => '',
      FormulaCellValue() => '',
    };
  }

  /// One data cell as the trimmed string the normalizer will read.
  ///
  /// Every branch here is a decision §15 states, and the two that matter most are
  /// the formula refusal and the numeric-date refusal — see the class note.
  String _cellText(
    Data? cell, {
    required int rowNumber,
    required String column,
  }) {
    final value = cell?.value;
    return switch (value) {
      null => '',
      TextCellValue() => value.value.toString().trim(),
      // An integer cell in an identifier column has already lost its leading
      // zeros by the time it reaches here — nothing can recover them. What this
      // *can* do is not make it worse: the digits are read exactly, never through
      // a double. A code that was mangled shows up in the preview as the wrong
      // code, which is visible; silently reformatting it would not be.
      IntCellValue() => value.value.toString(),
      DoubleCellValue() => _doubleText(value.value),
      BoolCellValue() =>
        value.value
            ? MasterImportNormalizationPolicy.canonicalBooleans.first
            : MasterImportNormalizationPolicy.canonicalBooleans.last,
      // Deterministic: the library hands back calendar fields, and they are
      // rendered straight to ISO so exactly one code path parses a date.
      DateCellValue() => DateOnly.formatIso(
        DateTime.utc(value.year, value.month, value.day),
      ),
      // A civil date has no time (T-8), so the time is discarded rather than
      // converted.
      DateTimeCellValue() => DateOnly.formatIso(
        DateTime.utc(value.year, value.month, value.day),
      ),
      TimeCellValue() => value.toString().trim(),
      FormulaCellValue() => MasterImportWorkbookValidator.rejectFormulaCell(
        rowNumber: rowNumber,
        column: column,
      ),
    };
  }

  /// Renders a numeric cell without scientific notation and without a spurious
  /// `.0` on a whole number.
  ///
  /// `12.0` becomes `12`, which is what the operator typed; `12.5` stays `12.5`
  /// so the integer parser can refuse it with the value visible in the message.
  String _doubleText(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}

/// Adapts [ExcelMasterImportWorkbookParser] to the domain's reader interface.
///
/// The adapter exists so the domain never names the spreadsheet package: the use
/// cases depend on [MasterImportWorkbookReader], the architecture tests assert
/// that no `domain/` file imports `package:excel`, and a test can hand in rows
/// without producing a real workbook.
class ExcelMasterImportWorkbookReader implements MasterImportWorkbookReader {
  const ExcelMasterImportWorkbookReader([
    this.parser = const ExcelMasterImportWorkbookParser(),
  ]);

  final ExcelMasterImportWorkbookParser parser;

  @override
  ImportWorkbook read({
    required MasterEntityType entity,
    required Uint8List bytes,
    required String fileName,
  }) => parser.parse(entity: entity, bytes: bytes, fileName: fileName);
}
