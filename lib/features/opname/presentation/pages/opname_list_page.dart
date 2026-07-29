import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/opname_models.dart';
import '../providers/opname_providers.dart';
import '../widgets/historical_master_badge.dart';
import '../widgets/opname_status_chip.dart';

/// Stok Opname — Perawat's list of counts for their rooms (spec §4.2).
class OpnameListPage extends ConsumerStatefulWidget {
  const OpnameListPage({super.key});

  @override
  ConsumerState<OpnameListPage> createState() => _OpnameListPageState();
}

class _OpnameListPageState extends ConsumerState<OpnameListPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A ward tablet is left open for days. Coming back to the foreground is
    // exactly when the cached operational week may have gone stale, which
    // would otherwise leave "+ Opname Minggu Ini" disabled for the new week.
    if (state == AppLifecycleState.resumed) _refreshPeriod();
  }

  void _refreshPeriod() {
    ref.invalidate(currentOperationalPeriodProvider);
    ref.invalidate(roomOpnameForCurrentWeekProvider);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionValueProvider);
    final period = ref.watch(currentOperationalPeriodProvider);
    final opnames = ref.watch(nurseOpnameListProvider);

    ref.listen(createOpnameControllerProvider, (previous, next) {
      final error = next.error;
      if (error != null) _showError(context, error);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Opname'),
        actions: [
          if (session != null && session.canReviewOpname)
            IconButton(
              tooltip: 'Review Stok Opname',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () => context.pushNamed(AppRoutes.opnameReviewName),
            ),
        ],
      ),
      body: session == null || !session.canViewOpname
          ? const _NoAccessNotice()
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(nurseOpnameListProvider);
                ref.invalidate(sessionRoomsProvider);
                _refreshPeriod();
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                children: [
                  _PeriodHeader(period: period, session: session),
                  const _RoomFilter(),
                  if (session.canFillOpname) const _CreateSection(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      'Riwayat Opname',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  opnames.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => _ErrorNotice(
                      message: describeFailure(error),
                      onRetry: () => ref.invalidate(nurseOpnameListProvider),
                    ),
                    data: (rows) => rows.isEmpty
                        ? const _EmptyHistory()
                        : Column(
                            children: [
                              for (final summary in rows)
                                _OpnameTile(summary: summary),
                            ],
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(describeFailure(error))));
}

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.period, required this.session});

  final OperationalPeriod period;
  final CurrentUserSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Periode ${period.label}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tanggal operasional '
                '${AppDateTimeFormatter.civilDate(period.date)} '
                '${AppDateTimeFormatter.timeZoneLabel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '${session.displayName} · ${session.roleLabel}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Room chips, shown only when the nurse covers more than one room.
class _RoomFilter extends ConsumerWidget {
  const _RoomFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(sessionRoomsProvider);
    final selected = ref.watch(selectedRoomIdProvider);

    return rooms.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.length < 2) return const SizedBox.shrink();

        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            children: [
              Center(
                child: FilterChip(
                  label: const Text('Semua ruangan'),
                  selected: selected == null,
                  showCheckmark: false,
                  onSelected: (_) =>
                      ref.read(selectedRoomIdProvider.notifier).select(null),
                ),
              ),
              for (final room in rows) ...[
                const SizedBox(width: AppSpacing.sm),
                Center(
                  child: FilterChip(
                    label: Text(room.name),
                    selected: selected == room.id,
                    showCheckmark: false,
                    onSelected: (_) => ref
                        .read(selectedRoomIdProvider.notifier)
                        .select(selected == room.id ? null : room.id),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One "+ Opname Minggu Ini" button per room, disabled with a reason once that
/// room already has a document for the current ISO week (G-O1).
class _CreateSection extends ConsumerWidget {
  const _CreateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(sessionRoomsProvider);

    return rooms.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => _ErrorNotice(
        message: describeFailure(error),
        onRetry: () => ref.invalidate(sessionRoomsProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const _Notice(
            icon: Icons.meeting_room_outlined,
            message:
                'Belum ada ruangan aktif di cabang Anda. Hubungi Super Admin '
                'untuk menambahkan ruangan.',
          );
        }

        final selected = ref.watch(selectedRoomIdProvider);
        final visible = selected == null
            ? rows
            : rows.where((room) => room.id == selected).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [for (final room in visible) _CreateButton(room: room)],
          ),
        );
      },
    );
  }
}

class _CreateButton extends ConsumerWidget {
  const _CreateButton({required this.room});

  final MasterRoom room;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final existing = ref.watch(roomOpnameForCurrentWeekProvider(room.id));
    final creating = ref.watch(createOpnameControllerProvider).isLoading;

    return existing.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => _ErrorNotice(
        message: describeFailure(error),
        onRetry: () =>
            ref.invalidate(roomOpnameForCurrentWeekProvider(room.id)),
      ),
      data: (opname) {
        final alreadyCounted = opname != null;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                // Disabled while a create is in flight, so a double tap cannot
                // produce two documents.
                onPressed: alreadyCounted || creating
                    ? null
                    : () async {
                        final id = await ref
                            .read(createOpnameControllerProvider.notifier)
                            .create(room.id);
                        if (id == null || !context.mounted) return;
                        ref.invalidate(
                          roomOpnameForCurrentWeekProvider(room.id),
                        );
                        context.pushNamed(
                          AppRoutes.opnameDetailName,
                          pathParameters: {'id': id},
                        );
                      },
                icon: creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text('+ Opname Minggu Ini · ${room.name}'),
              ),
              if (alreadyCounted)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '${room.name} sudah memiliki opname minggu ini '
                    '(${opname.docNumber}). Satu ruangan hanya boleh dihitung '
                    'sekali per minggu.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OpnameTile extends StatelessWidget {
  const _OpnameTile({required this.summary});

  final StockOpnameSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opname = summary.opname;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.pushNamed(
            AppRoutes.opnameDetailName,
            pathParameters: {'id': opname.id},
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        opname.docNumber,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    OpnameStatusChip(status: opname.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${summary.roomName} · Periode ${opname.periodLabel}',
                  style: theme.textTheme.bodySmall,
                ),
                // The list query filters neither `is_active` nor `deleted_at`,
                // so a count of a retired room is still here — labelled rather
                // than missing (§7.6).
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: HistoricalMasterBadge.forSummary(summary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${summary.lineCount} baris · '
                  '${summary.differenceLineCount} berselisih',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (opname.submittedAt != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Dikirim '
                    '${AppDateTimeFormatter.dateTimeWithZone(opname.submittedAt!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (opname.reviewedAt != null)
                  Text(
                    'Direview '
                    '${AppDateTimeFormatter.dateTimeWithZone(opname.reviewedAt!)}'
                    '${summary.reviewedByName == null ? '' : ' · ${summary.reviewedByName}'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                SyncStatusTag(status: opname.syncStatus),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const _Notice(
      icon: Icons.inventory_2_outlined,
      message:
          'Belum ada stok opname. Mulai hitung fisik minggu ini dengan tombol '
          'di atas.',
    );
  }
}

class _NoAccessNotice extends StatelessWidget {
  const _NoAccessNotice();

  @override
  Widget build(BuildContext context) {
    return const _Notice(
      icon: Icons.lock_outline,
      message:
          'Peran Anda tidak memiliki akses ke Stok Opname. Modul ini untuk '
          'Perawat dan Kepala Cabang.',
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(message)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('Coba lagi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
