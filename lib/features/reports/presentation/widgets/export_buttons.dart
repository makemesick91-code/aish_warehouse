import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../domain/models/reporting_models.dart';
import '../providers/reporting_providers.dart';

/// The `⬇ Excel` / `⬇ PDF` pair §4.3 asks to be *"konsisten di semua layar
/// laporan"*.
///
/// ### What the wording is careful about
///
/// > *"Laporan Excel berhasil dibuat. File siap disimpan atau dibagikan."*
///
/// Not *"tersimpan ke Downloads"*. The file is in the app's private directory
/// (§41), and telling a user to look in Downloads would send them looking for
/// something that is not there. What they can do is share it — and the share sheet
/// opens by itself — so that is what the message says (§47).
///
/// A dismissed share sheet still reports success, because it *is* one: the file
/// exists and the export is recorded by the time the sheet opens (§3.16).
///
/// ### Both buttons disable together
///
/// While one export runs the other is disabled too. They are the same operation on
/// the same data, and a second tap during the first would produce a second file and
/// a second audit row for a single intention (§47). The buttons are also disabled
/// until the filter form can express a question at all.
class ExportButtons extends ConsumerWidget {
  const ExportButtons({super.key, this.enabled = true});

  /// The caller's own precondition — typically [isReportDraftReady].
  final bool enabled;

  static const Key excelButtonKey = ValueKey('exportExcelButton');
  static const Key pdfButtonKey = ValueKey('exportPdfButton');
  static const Key progressKey = ValueKey('exportProgress');

  static const String excelLabel = 'Unduh Excel';
  static const String pdfLabel = 'Unduh PDF';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportExportControllerProvider);
    final canExport = enabled && !state.isExporting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              key: excelButtonKey,
              onPressed: canExport
                  ? () => ref
                        .read(reportExportControllerProvider.notifier)
                        .export(ReportFormat.xlsx)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.success),
              icon: const Icon(Icons.download),
              label: const Text(excelLabel),
            ),
            FilledButton.icon(
              key: pdfButtonKey,
              onPressed: canExport
                  ? () => ref
                        .read(reportExportControllerProvider.notifier)
                        .export(ReportFormat.pdf)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text(pdfLabel),
            ),
          ],
        ),
        if (state.isExporting) ...[
          const SizedBox(height: AppSpacing.sm),
          const Row(
            key: progressKey,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppSpacing.sm),
              Text('Menyiapkan file laporan…'),
            ],
          ),
        ],
        if (state.hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          _Banner(
            icon: Icons.error_outline,
            color: AppColors.danger,
            text: state.errorMessage!,
          ),
        ],
        if (state.artifact != null && !state.hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          _Banner(
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            text: _successText(state.artifact!),
          ),
        ],
      ],
    );
  }

  /// The success sentence, plus the canonical file name and — when the sheet did
  /// not open — a note that the file was still created.
  static String _successText(GeneratedReportArtifact artifact) {
    final buffer = StringBuffer(artifact.successMessage)
      ..write('\n')
      ..write(artifact.fileName);
    if (artifact.shareOutcome != ReportShareOutcome.shared) {
      buffer.write(
        '\nBerbagi dibatalkan atau tidak tersedia — file tetap dibuat.',
      );
    }
    return buffer.toString();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
