import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/use_cases/export_history_use_cases.dart';
import '../providers/reporting_providers.dart';

/// The dashboard's *Laporan* entry, worded per role (§49).
///
/// ### One route, four labels
///
/// Every role reaches `/reports`, so this is one button — but *"Laporan Ruangan"*
/// and *"Laporan Lintas Cabang"* describe genuinely different screens, and a single
/// generic label would leave a nurse guessing whether the module is for them. The
/// label comes from the role; the reach comes from [ReportAccessPolicy].
///
/// ### Why this is a card rather than a bottom-nav tab
///
/// This application's shell is still the development home page: there is no final
/// bottom navigation to add a tab to. Adding one now would mean rebuilding the shell
/// for every role as a side effect of shipping reports, so the entry point is a
/// role-visible card on the surface that already exists. **That is the actual
/// surface this milestone ships**, and it is stated here rather than left to be
/// discovered.
class ReportingDashboardCard extends ConsumerWidget {
  const ReportingDashboardCard({super.key});

  static const Key buttonKey = ValueKey('homeReports');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(actingRoleProvider);
    if (role == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: buttonKey,
        onPressed: () => context.pushNamed(AppRoutes.reportsName),
        icon: const Icon(Icons.summarize_outlined),
        label: Text(labelFor(role)),
      ),
    );
  }

  /// The wording each role sees. Public so the widget tests can assert it without
  /// duplicating the strings.
  static String labelFor(UserRole role) => switch (role) {
    UserRole.perawat => 'Laporan Ruangan',
    UserRole.kepalaCabang => 'Laporan Cabang',
    UserRole.warehouse => 'Laporan Warehouse & Lintas Cabang',
    UserRole.superAdmin => 'Semua Laporan',
  };
}

/// The Super Admin's audit summary: today's exports, unsynced rows, and the way in
/// to the trail itself (§49).
///
/// Shown to nobody else. The counts are as revealing as the list — *"14 ekspor hari
/// ini"* tells a branch head how busy the group was — so the card is gated on the
/// same role check as the route, and the underlying stream is empty for every other
/// role regardless.
class ExportAuditSummaryCard extends ConsumerWidget {
  const ExportAuditSummaryCard({super.key});

  static const Key cardKey = ValueKey('homeExportAuditSummary');
  static const Key historyButtonKey = ValueKey('homeExportHistory');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(actingRoleProvider);
    if (!canOpenExportHistory(role)) return const SizedBox.shrink();

    final today = ref.watch(exportsTodayCountProvider);
    final pending = ref.watch(pendingExportCountProvider);

    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jejak Ekspor', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                _Metric(
                  label: 'Ekspor hari ini',
                  value: today.maybeWhen(
                    data: (value) => '$value',
                    orElse: () => '…',
                  ),
                ),
                _Metric(
                  label: 'Belum tersinkron',
                  value: pending.maybeWhen(
                    data: (value) => '$value',
                    orElse: () => '…',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: historyButtonKey,
                onPressed: () => context.pushNamed(AppRoutes.exportHistoryName),
                icon: const Icon(Icons.history),
                label: const Text('Riwayat Ekspor'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The acting user's own recent exports (§49).
///
/// Scoped to *"what I exported"*, not *"what my branch exported"* — so a Kepala
/// Cabang sees their own trail without being handed a colleague's, which is a
/// distinction only the Super Admin's audit screen is meant to erase.
class RecentOwnExportsCard extends ConsumerWidget {
  const RecentOwnExportsCard({super.key});

  static const Key cardKey = ValueKey('homeRecentOwnExports');
  static const String emptyMessage = 'Belum ada ekspor dari akun ini.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(recentOwnExportsProvider);

    return Card(
      key: cardKey,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ekspor Terbaru Saya',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            logs.when(
              // A muted line rather than a progress indicator: this card sits on the
              // home page, which every refused route lands on, and an indeterminate
              // animation there is a frame scheduled forever.
              loading: () =>
                  Text('Memuat…', style: Theme.of(context).textTheme.bodySmall),
              error: (_, _) => const Text('Gagal memuat riwayat ekspor.'),
              data: (rows) => rows.isEmpty
                  ? const Text(emptyMessage)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final log in rows)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: Text(
                              '${log.fileName} · '
                              '${AppDateTimeFormatter.dateTimeWithZone(log.exportedAtUtc)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
