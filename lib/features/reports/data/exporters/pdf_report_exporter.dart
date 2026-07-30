import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/errors/failures.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/gateways/report_gateways.dart';
import '../../domain/models/reporting_models.dart';
import '../../domain/services/report_grouping_engine.dart';
import '../../domain/services/report_period_policy.dart';
import '../../domain/services/report_sync_snapshot_builder.dart';

/// Turns a [ReportDocument] into a real PDF (§40).
///
/// ### Nothing is fetched, at build time or at run time
///
/// The document uses the `pdf` package's **built-in** Helvetica metrics. No font
/// file is bundled, no font is downloaded, and no logo is loaded from a URL — G-L3
/// makes reports an offline capability, and a PDF exporter that reached for a Google
/// Font would make the report fail on exactly the device that needs it most.
///
/// The price is a real constraint: the built-in metrics cover **Latin-1 only**, and
/// the `pdf` package draws an unsupported rune as an empty placeholder without
/// failing. Indonesian needs nothing outside Latin-1, but this application's own
/// labels do — the en dash between two period dates, the em dash that means *"not
/// applicable"* — and losing either silently would turn `12 Jan 2026 – 18 Jan 2026`
/// into two dates with a gap where the range used to be. So every string this
/// exporter draws goes through [_drawable] first, which is a *rendering* decision
/// and the only kind of transformation an exporter is allowed to make.
///
/// ### Orientation follows the table, not a preference
///
/// A stock card has fourteen columns and a stock report eleven; portrait A4 would
/// squeeze either into unreadable slivers. So the page is landscape whenever the
/// column count crosses [_landscapeColumnThreshold] and portrait otherwise — decided
/// from the document rather than passed in, so no caller can get it wrong.
///
/// ### Page breaks are the table's problem, and `pdf` solves it
///
/// `pw.TableHelper` inside a `pw.MultiPage` repeats the header row on every page and
/// breaks between rows rather than through them. The alternative — laying out rows by
/// hand and tracking the remaining height — is how a report ends up with a row sliced
/// across a page boundary.
///
/// The exporter runs **no query and no business logic**: every figure comes from the
/// builder (§33).
class PdfReportExporter implements ReportPdfExporter {
  const PdfReportExporter();

  /// Above this many columns the page turns landscape.
  static const int _landscapeColumnThreshold = 8;

  /// Typographic characters this application uses, mapped to the closest thing
  /// Latin-1 can draw.
  ///
  /// Everything else outside Latin-1 becomes `?`, which is visible: a reader who
  /// sees one knows something was lost, where a silent placeholder tells them
  /// nothing. Nothing here is a business decision — the *numbers* are already
  /// rendered by the builder, and none of them contain a character in this table.
  static const Map<int, String> _latin1Substitutes = {
    0x2010: '-', // hyphen
    0x2011: '-', // non-breaking hyphen
    0x2012: '-', // figure dash
    0x2013: '-', // en dash — the period separator
    0x2014: '-', // em dash — ReportLabels.notApplicable
    0x2018: "'", // left single quote
    0x2019: "'", // right single quote
    0x201C: '"', // left double quote
    0x201D: '"', // right double quote
    0x2022: '-', // bullet
    0x2026: '...', // ellipsis
    0x00A0: ' ', // non-breaking space, drawn but never desirable in a cell
  };

  /// [value] with every rune the built-in font cannot draw replaced.
  ///
  /// The built-in Type 1 metrics support `U+0000`–`U+00FF` and nothing else; the
  /// `pdf` package substitutes an empty placeholder for anything above that and
  /// carries on, so an unsanitised label loses characters without any failure to
  /// notice.
  static String _drawable(String value) {
    var needsWork = false;
    for (final rune in value.runes) {
      if (rune > 0xFF) {
        needsWork = true;
        break;
      }
    }
    if (!needsWork) return value;

    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune <= 0xFF) {
        buffer.writeCharCode(rune);
        continue;
      }
      buffer.write(_latin1Substitutes[rune] ?? '?');
    }
    return buffer.toString();
  }

  @override
  Future<Uint8List> export(ReportDocument document) async {
    try {
      final theme = pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
      );
      final pdf = pw.Document(theme: theme);
      final landscape = document.columns.length > _landscapeColumnThreshold;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => _pageHeader(document, context),
          footer: _footer,
          build: (context) => _body(document),
        ),
      );

      final bytes = await pdf.save();
      if (bytes.isEmpty) {
        throw ReportPdfGenerationFailure(
          'File PDF gagal dibuat. Silakan coba lagi.',
          reportType: document.header.reportType,
        );
      }
      return bytes;
    } on ReportPdfGenerationFailure {
      rethrow;
    } catch (_) {
      // Package internals are deliberately not surfaced (§52).
      throw ReportPdfGenerationFailure(
        'File PDF gagal dibuat. Silakan coba lagi.',
        reportType: document.header.reportType,
      );
    }
  }

  /// The strip repeated at the top of every page.
  ///
  /// Deliberately short: the full header block is the first thing in the body, and
  /// repeating eleven lines on page nine would push the data off the page. What
  /// repeats is what a reader needs to know about a page they are looking at in
  /// isolation — which report, which period, printed when.
  pw.Widget _pageHeader(ReportDocument document, pw.Context context) {
    final header = document.header;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _drawable(ReportHeader.appTitle),
                style: pw.TextStyle(fontSize: 8, letterSpacing: 1),
              ),
              pw.Text(
                _drawable(header.title),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                _drawable(
                  ReportPeriodPolicy.describe(
                    header.period,
                    isAsOf: header.reportType.isAsOfReport,
                  ),
                ),
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                _drawable(
                  'Dicetak '
                  '${AppDateTimeFormatter.dateTimeWithZone(header.generatedAtUtc)}',
                ),
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context context) => pw.Container(
    alignment: pw.Alignment.centerRight,
    margin: const pw.EdgeInsets.only(top: 6),
    child: pw.Text(
      _drawable('Halaman ${context.pageNumber} dari ${context.pagesCount}'),
      style: const pw.TextStyle(fontSize: 8),
    ),
  );

  List<pw.Widget> _body(ReportDocument document) {
    final widgets = <pw.Widget>[
      _headerBlock(document),
      pw.SizedBox(height: 10),
    ];

    if (document.warnings.isNotEmpty) {
      widgets
        ..add(_warningsBlock(document.warnings))
        ..add(pw.SizedBox(height: 10));
    }

    for (final section in document.sections) {
      widgets
        ..add(_sectionBlock(section))
        ..add(pw.SizedBox(height: 10));
    }

    if (document.isEmpty) {
      widgets.add(
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          child: pw.Text(
            _drawable(ReportDocument.emptyMessage),
            style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
          ),
        ),
      );
      return widgets;
    }

    for (final group in document.groups) {
      widgets
        ..add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 6, bottom: 3),
            child: pw.Text(
              _drawable(group.categoryName),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
        )
        ..add(_table(document.columns, group.rows))
        ..add(
          _totalsBlock(
            ReportGroupingEngine.subtotalLabel(group),
            group.subtotals,
          ),
        );
    }

    widgets
      ..add(pw.SizedBox(height: 8))
      ..add(
        _totalsBlock(
          ReportGroupingEngine.overallTotalLabel,
          document.overallTotals,
          emphasise: true,
        ),
      );
    return widgets;
  }

  pw.Widget _headerBlock(ReportDocument document) {
    final header = document.header;
    final entries = <({String label, String value})>[
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
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 120,
                    child: pw.Text(
                      _drawable(entry.label),
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      _drawable(entry.value),
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _warningsBlock(List<String> warnings) => pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.5, color: PdfColors.orange700),
      borderRadius: pw.BorderRadius.circular(2),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _drawable('Peringatan'),
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        for (final warning in warnings)
          pw.Text(
            _drawable('\u2022 $warning'),
            style: const pw.TextStyle(fontSize: 8),
          ),
      ],
    ),
  );

  pw.Widget _sectionBlock(ReportSection section) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        _drawable(section.title),
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 3),
      pw.Wrap(
        spacing: 16,
        runSpacing: 3,
        children: [
          for (final metric in section.metrics)
            pw.Text(
              _drawable('${metric.label}: ${metric.value}'),
              style: const pw.TextStyle(fontSize: 8),
            ),
        ],
      ),
    ],
  );

  pw.Widget _table(List<ReportColumn> columns, List<ReportDataRow> rows) {
    return pw.TableHelper.fromTextArray(
      headers: [for (final column in columns) _drawable(column.label)],
      data: [
        for (final row in rows)
          [for (final cell in row.cells) _drawable(cell.text)],
      ],
      border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey500),
      headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellHeight: 14,
      // `MultiPage` repeats this on every page it spills onto.
      headerCount: 1,
      cellAlignments: {
        for (var index = 0; index < columns.length; index++)
          index: switch (columns[index].align) {
            ReportColumnAlign.start => pw.Alignment.centerLeft,
            ReportColumnAlign.center => pw.Alignment.center,
            ReportColumnAlign.end => pw.Alignment.centerRight,
          },
      },
      columnWidths: {
        for (var index = 0; index < columns.length; index++)
          index: pw.FlexColumnWidth(columns[index].widthFlex.toDouble()),
      },
    );
  }

  /// One line per unit — never one line summing them (§32).
  pw.Widget _totalsBlock(
    String label,
    ReportUnitTotals totals, {
    bool emphasise = false,
  }) => pw.Container(
    alignment: pw.Alignment.centerRight,
    margin: const pw.EdgeInsets.only(top: 3, bottom: 3),
    child: pw.Text(
      _drawable('$label \u2014 ${totals.label}'),
      style: pw.TextStyle(
        fontSize: emphasise ? 9 : 8,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}
