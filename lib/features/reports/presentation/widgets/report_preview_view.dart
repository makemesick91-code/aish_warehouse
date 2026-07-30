import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/reporting_models.dart';
import '../../domain/services/report_grouping_engine.dart';
import '../../domain/services/report_period_policy.dart';
import '../../domain/services/report_sync_snapshot_builder.dart';

/// Renders a [ReportPreview] (§46).
///
/// ### It renders; it does not compute
///
/// Every number on screen was produced by a builder and is already a string. The
/// widget adds no arithmetic of its own, which is what makes *"the preview, the
/// workbook and the PDF agree"* structurally true rather than something three
/// implementations have to remember (§33).
///
/// ### Why the row cap is here and the export is not capped
///
/// A five-thousand-row stock report is a legitimate thing to ask for, and building
/// five thousand `DataRow`s on a clinic tablet is not. So the preview draws the
/// first [ReportPreview.displayedRowCount] and says so, in as many words. The export
/// path rebuilds from the same request and writes all of them — the cap is a
/// property of this widget, not of the report (§46).
///
/// ### Narrow screens
///
/// The table lives inside a horizontal `SingleChildScrollView`, so a fourteen-column
/// stock card scrolls sideways instead of overflowing. The header block and summary
/// cards `Wrap` instead.
class ReportPreviewView extends StatelessWidget {
  const ReportPreviewView({super.key, required this.preview});

  final ReportPreview preview;

  static const Key emptyKey = ValueKey('reportPreviewEmpty');
  static const Key tableKey = ValueKey('reportPreviewTable');
  static const Key truncationKey = ValueKey('reportPreviewTruncation');

  @override
  Widget build(BuildContext context) {
    final document = preview.document;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderCard(header: document.header),
        if (document.warnings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _WarningsCard(warnings: document.warnings),
        ],
        for (final section in document.sections) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionCard(section: section),
        ],
        const SizedBox(height: AppSpacing.md),
        if (document.isEmpty)
          const _EmptyState()
        else ...[
          if (preview.isTruncated) ...[
            Padding(
              key: truncationKey,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                preview.truncationNotice,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          _DataTable(preview: preview),
          const SizedBox(height: AppSpacing.md),
          _TotalsRow(
            label: ReportGroupingEngine.overallTotalLabel,
            totals: document.overallTotals,
            emphasise: true,
          ),
        ],
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.header});

  final ReportHeader header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = ReportSyncSnapshotBuilder.describeWarning(
      header.syncSnapshot,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ReportHeader.appTitle,
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2),
            ),
            Text(
              header.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                _Field(
                  label: 'Waktu cetak',
                  value: AppDateTimeFormatter.dateTimeWithZone(
                    header.generatedAtUtc,
                  ),
                ),
                _Field(
                  label: 'Periode',
                  value: ReportPeriodPolicy.describe(
                    header.period,
                    isAsOf: header.reportType.isAsOfReport,
                  ),
                ),
                _Field(label: 'Cakupan', value: header.scopeLabel),
                _Field(label: 'Lokasi', value: header.locationLabel),
                _Field(label: 'Cabang', value: header.branchLabel),
                _Field(label: 'Kategori', value: header.categoryLabel),
                _Field(label: 'Barang', value: header.itemLabel),
                _Field(label: 'Dibuat oleh', value: header.exportedByLabel),
                _Field(label: 'Jumlah baris', value: '${header.rowCount}'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(header.syncSnapshot.label, style: theme.textTheme.bodySmall),
            Text(
              ReportSyncSnapshotBuilder.describeLastUpdate(header.syncSnapshot),
              style: theme.textTheme.bodySmall,
            ),
            if (warning != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sync_problem_outlined,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      warning,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Peringatan',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: AppColors.warning),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final warning in warnings) Text('• $warning'),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final ReportSection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                for (final metric in section.metrics)
                  _Field(label: metric.label, value: metric.value),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ReportPreviewView.emptyKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            const Icon(Icons.inbox_outlined),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(ReportDocument.emptyMessage)),
          ],
        ),
      ),
    );
  }
}

/// The grouped table, capped at the preview limit.
///
/// The cap is applied **across groups** rather than per group, so the first
/// categories are shown whole rather than every category being shown truncated —
/// a reader checking a subtotal needs the rows above it to be all of them.
class _DataTable extends StatelessWidget {
  const _DataTable({required this.preview});

  final ReportPreview preview;

  @override
  Widget build(BuildContext context) {
    final document = preview.document;
    var remaining = preview.displayedRowCount;
    final children = <Widget>[];

    for (final group in document.groups) {
      if (remaining <= 0) break;
      final rows = group.rows.take(remaining).toList(growable: false);
      remaining -= rows.length;
      children
        ..add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              group.categoryName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        )
        ..add(_GroupTable(columns: document.columns, rows: rows))
        ..add(
          _TotalsRow(
            label: ReportGroupingEngine.subtotalLabel(group),
            totals: group.subtotals,
          ),
        );
    }

    return Column(
      key: ReportPreviewView.tableKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _GroupTable extends StatelessWidget {
  const _GroupTable({required this.columns, required this.rows});

  final List<ReportColumn> columns;
  final List<ReportDataRow> rows;

  @override
  Widget build(BuildContext context) {
    // Horizontal scroll rather than shrinking: a fourteen-column stock card cannot
    // be made to fit a phone, and squeezing it produces a table nobody can read.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 64,
        columnSpacing: AppSpacing.lg,
        columns: [
          for (final column in columns)
            DataColumn(
              label: Text(column.label),
              numeric: column.align == ReportColumnAlign.end,
            ),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (var index = 0; index < columns.length; index++)
                  DataCell(
                    Text(
                      index < row.cells.length ? row.cells[index].text : '',
                      style: TextStyle(
                        color: _colorFor(
                          index < row.cells.length
                              ? row.cells[index].emphasis
                              : ReportCellEmphasis.none,
                        ),
                        fontStyle: row.isHistorical
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static Color? _colorFor(ReportCellEmphasis emphasis) => switch (emphasis) {
    ReportCellEmphasis.none => null,
    ReportCellEmphasis.positive => AppColors.success,
    ReportCellEmphasis.warning => AppColors.warning,
    ReportCellEmphasis.danger => AppColors.danger,
    ReportCellEmphasis.muted => Colors.black54,
  };
}

/// Per-unit totals, one line each. Never a single summed figure (§32).
class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.totals,
    this.emphasise = false,
  });

  final String label;
  final ReportUnitTotals totals;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final style = emphasise
        ? Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text('$label — ${totals.label}', style: style),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A `Wrap` gives its children unbounded width, so a long location or category
    // name would render past the card edge on a phone. Capping it lets the text
    // wrap inside the field instead of overflowing the row (§46).
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
