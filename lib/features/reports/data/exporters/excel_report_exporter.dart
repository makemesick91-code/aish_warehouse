import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/gateways/report_gateways.dart';
import '../../domain/models/reporting_models.dart';
import '../../domain/services/report_grouping_engine.dart';
import '../../domain/services/report_period_policy.dart';
import '../../domain/services/report_sync_snapshot_builder.dart';
import '../../domain/services/spreadsheet_cell_sanitizer.dart';

/// Turns a [ReportDocument] into a real `.xlsx` workbook (§39).
///
/// ### Two sheets, and the first one is the point
///
/// *Ringkasan* carries G-L3's header — print time, period, scope, location,
/// category, item, who exported it, the sync snapshot and the row count — and
/// *Data* carries the table with its category groups, subtotals and per-unit totals.
/// A single-sheet workbook would have to put the header above the data, where a
/// sort or a filter destroys it; a reader who opens the file a month later still
/// needs to know what it is a report *of*.
///
/// ### Every cell is text, on purpose
///
/// Quantities are written as the exact strings [Quantity.format] produced, never as
/// numeric cells. Writing `2.25` into a float cell is how an exact fixed-point value
/// becomes `2.2500000000000004` on somebody else's machine, and the whole reason
/// this application has a [Quantity] type is that it refuses to let that happen
/// (Q-3). The unit lives in its own column, so a reader can still sort and filter.
///
/// Every text cell goes through [SpreadsheetCellSanitizer] first — an item name
/// beginning with `=` is a formula waiting for an auditor to open it (§38).
///
/// ### What this exporter cannot do, and does not pretend to
///
/// `excel` 4.0.6 exposes **no freeze-pane and no auto-filter API** — there is no
/// method on `Sheet` for either. Rather than reach into the generated OOXML and
/// hand-write `<sheetView pane=…>`, which would be this application maintaining a
/// piece of another package's file format, the header row is made visually
/// unmistakable (bold, wrapped, sized columns) and the limitation is stated here.
/// The moment the package grows the API, this is the one place that changes.
///
/// The exporter runs **no query and no business logic**. Every figure it writes was
/// computed by a builder (§33).
class ExcelReportExporter implements ReportExcelExporter {
  const ExcelReportExporter();

  static const String summarySheetName = 'Ringkasan';
  static const String dataSheetName = 'Data';

  @override
  Future<Uint8List> export(ReportDocument document) async {
    try {
      final workbook = Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet();

      _writeSummarySheet(workbook[summarySheetName], document);
      _writeDataSheet(workbook[dataSheetName], document);

      // `createExcel` seeds a `Sheet1`; leaving it would ship every report with an
      // empty tab. Deleted after both real sheets exist, because a workbook with no
      // sheets is not a valid workbook.
      if (defaultSheet != null &&
          defaultSheet != summarySheetName &&
          defaultSheet != dataSheetName) {
        workbook.delete(defaultSheet);
      }
      workbook.setDefaultSheet(summarySheetName);

      final bytes = workbook.encode();
      if (bytes == null || bytes.isEmpty) {
        throw ReportExcelGenerationFailure(
          'File Excel gagal dibuat. Silakan coba lagi.',
          reportType: document.header.reportType,
        );
      }
      return Uint8List.fromList(bytes);
    } on ReportExcelGenerationFailure {
      rethrow;
    } catch (_) {
      // The underlying error is deliberately not surfaced: it names package
      // internals, and a nurse reading it learns nothing they can act on (§52).
      throw ReportExcelGenerationFailure(
        'File Excel gagal dibuat. Silakan coba lagi.',
        reportType: document.header.reportType,
      );
    }
  }

  // --- Ringkasan ------------------------------------------------------------

  void _writeSummarySheet(Sheet sheet, ReportDocument document) {
    final header = document.header;
    var row = 0;

    _put(sheet, row++, 0, ReportHeader.appTitle, style: _titleStyle);
    _put(sheet, row++, 0, header.title, style: _headingStyle);
    row++;

    for (final entry in <({String label, String value})>[
      (
        label: 'Waktu cetak',
        value: AppDateTimeFormatter.dateTimeWithZone(header.generatedAtUtc),
      ),
      (
        label: 'Periode',
        value: ReportPeriodPolicy.describe(
          header.period,
          isAsOf: header.reportType.isAsOfReport,
        ),
      ),
      (label: 'Cakupan', value: header.scopeLabel),
      (label: 'Lokasi', value: header.locationLabel),
      (label: 'Cabang', value: header.branchLabel),
      (label: 'Kategori', value: header.categoryLabel),
      (label: 'Barang', value: header.itemLabel),
      (label: 'Diekspor oleh', value: header.exportedByLabel),
      (label: 'Status sinkronisasi', value: header.syncSnapshot.label),
      (
        label: 'Pembaruan data terakhir',
        value: ReportSyncSnapshotBuilder.describeLastUpdate(
          header.syncSnapshot,
        ),
      ),
      (label: 'Jumlah baris', value: '${header.rowCount}'),
    ]) {
      _put(sheet, row, 0, entry.label, style: _labelStyle);
      _put(sheet, row, 1, entry.value);
      row++;
    }

    for (final section in document.sections) {
      row++;
      _put(sheet, row++, 0, section.title, style: _headingStyle);
      for (final metric in section.metrics) {
        _put(sheet, row, 0, metric.label, style: _labelStyle);
        _put(sheet, row, 1, metric.value);
        row++;
      }
    }

    if (document.warnings.isNotEmpty) {
      row++;
      _put(sheet, row++, 0, 'Peringatan', style: _headingStyle);
      for (final warning in document.warnings) {
        _put(sheet, row++, 0, warning, style: _wrapStyle);
      }
    }

    sheet.setColumnWidth(0, 32);
    sheet.setColumnWidth(1, 64);
  }

  // --- Data -----------------------------------------------------------------

  void _writeDataSheet(Sheet sheet, ReportDocument document) {
    var row = 0;

    for (var column = 0; column < document.columns.length; column++) {
      _put(
        sheet,
        row,
        column,
        document.columns[column].label,
        style: _headerRowStyle,
      );
    }
    row++;

    if (document.isEmpty) {
      _put(sheet, row, 0, ReportDocument.emptyMessage, style: _labelStyle);
      _applyColumnWidths(sheet, document);
      return;
    }

    for (final group in document.groups) {
      // A heading is drawn even for a single group: the surfaces stay consistent
      // with the model, which is always grouped (§32).
      _put(sheet, row++, 0, group.categoryName, style: _headingStyle);

      for (final dataRow in group.rows) {
        for (var column = 0; column < dataRow.cells.length; column++) {
          _put(
            sheet,
            row,
            column,
            dataRow.cells[column].text,
            style: _cellStyleFor(document.columns, column, dataRow),
          );
        }
        row++;
      }

      row = _writeTotals(
        sheet,
        row,
        ReportGroupingEngine.subtotalLabel(group),
        group.subtotals,
      );
      row++;
    }

    row = _writeTotals(
      sheet,
      row,
      ReportGroupingEngine.overallTotalLabel,
      document.overallTotals,
    );

    _applyColumnWidths(sheet, document);
  }

  /// One row per unit — never a single row summing them (§32).
  int _writeTotals(
    Sheet sheet,
    int startRow,
    String label,
    ReportUnitTotals totals,
  ) {
    var row = startRow;
    if (totals.isEmpty) {
      _put(sheet, row, 0, label, style: _totalStyle);
      _put(sheet, row, 1, ReportLabels.notApplicable, style: _totalStyle);
      return row + 1;
    }
    for (final unit in totals.units) {
      _put(sheet, row, 0, label, style: _totalStyle);
      _put(sheet, row, 1, unit, style: _totalStyle);
      _put(sheet, row, 2, totals[unit]!.format(), style: _totalStyle);
      row++;
    }
    return row;
  }

  void _applyColumnWidths(Sheet sheet, ReportDocument document) {
    for (var column = 0; column < document.columns.length; column++) {
      // `widthFlex` is the model's relative hint; 6 characters per unit lands
      // narrow columns around 6 and the widest text columns around 24.
      final width = (document.columns[column].widthFlex * 6).clamp(8, 48);
      sheet.setColumnWidth(column, width.toDouble());
    }
  }

  // --- cells ----------------------------------------------------------------

  void _put(Sheet sheet, int row, int column, String text, {CellStyle? style}) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    );
    // Sanitized on the way in, every time — see the class note on §38.
    cell.value = TextCellValue(SpreadsheetCellSanitizer.sanitize(text));
    if (style != null) cell.cellStyle = style;
  }

  CellStyle _cellStyleFor(
    List<ReportColumn> columns,
    int column,
    ReportDataRow row,
  ) {
    final align = column < columns.length
        ? columns[column].align
        : ReportColumnAlign.start;
    return CellStyle(
      horizontalAlign: switch (align) {
        ReportColumnAlign.start => HorizontalAlign.Left,
        ReportColumnAlign.center => HorizontalAlign.Center,
        ReportColumnAlign.end => HorizontalAlign.Right,
      },
      verticalAlign: VerticalAlign.Top,
      textWrapping: TextWrapping.WrapText,
      italic: row.isHistorical,
    );
  }

  static final CellStyle _titleStyle = CellStyle(bold: true, fontSize: 14);
  static final CellStyle _headingStyle = CellStyle(bold: true, fontSize: 12);
  static final CellStyle _labelStyle = CellStyle(bold: true);
  static final CellStyle _wrapStyle = CellStyle(
    textWrapping: TextWrapping.WrapText,
    verticalAlign: VerticalAlign.Top,
  );
  static final CellStyle _headerRowStyle = CellStyle(
    bold: true,
    textWrapping: TextWrapping.WrapText,
    verticalAlign: VerticalAlign.Center,
  );
  static final CellStyle _totalStyle = CellStyle(
    bold: true,
    horizontalAlign: HorizontalAlign.Right,
  );
}
