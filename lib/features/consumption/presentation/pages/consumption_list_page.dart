import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/consumption_models.dart';
import '../providers/consumption_providers.dart';
import '../widgets/consumption_badges.dart';
import '../widgets/consumption_filters.dart';

/// The Perawat's *Pemakaian* section (§27).
///
/// The list **is** the create surface: `Catat Pemakaian` creates the draft and pushes
/// straight into the editor, because a document has to exist before positions can be
/// validated against it. The `new` route exists so a deep link has somewhere to go, and
/// so the section guard has a `nurseCreate` kind to refuse.
///
/// ### What it can never show
///
/// Another nurse's document, of either status. The list reads
/// [ownConsumptionListProvider], whose scope is `created_by = <acting user>` resolved in
/// SQL (§14) — so a colleague's draft is not fetched and then hidden, it is not fetched.
/// That is the first *ownership*-scoped list in this application, and the security tests
/// exercise the two-nurses-one-branch case no earlier screen could produce.
class ConsumptionListPage extends ConsumerStatefulWidget {
  const ConsumptionListPage({super.key});

  static const Key listKey = ValueKey('consumptionList');
  static const Key emptyKey = ValueKey('consumptionListEmpty');
  static const Key searchKey = ValueKey('consumptionListSearch');
  static const Key createKey = ValueKey('consumptionCreateButton');
  static const Key noRoomKey = ValueKey('consumptionListNoRoom');

  static Key rowKeyFor(String consumptionId) =>
      ValueKey('consumptionRow-$consumptionId');

  /// Debounce window for the search field, matching the picker's.
  static const Duration searchDebounce = Duration(milliseconds: 200);

  @override
  ConsumerState<ConsumptionListPage> createState() =>
      _ConsumptionListPageState();
}

class _ConsumptionListPageState extends ConsumerState<ConsumptionListPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      ConsumptionListPage.searchDebounce,
      () => ref.read(consumptionSearchProvider.notifier).update(value),
    );
  }

  Future<void> _create() async {
    final room = await ref.read(effectiveConsumptionRoomProvider.future);
    if (!mounted) return;
    if (room == null) {
      _report(
        'Belum ada ruangan aktif di cabang Anda, sehingga pemakaian tidak '
        'dapat dicatat.',
      );
      return;
    }

    final id = await ref
        .read(createConsumptionControllerProvider.notifier)
        .create(roomId: room.roomId);
    if (!mounted) return;
    if (id == null) {
      final error = ref.read(createConsumptionControllerProvider).error;
      _report(describeFailure(error ?? 'Gagal membuat dokumen pemakaian.'));
      return;
    }
    context.pushNamed(
      AppRoutes.consumptionEditName,
      pathParameters: {'id': id},
    );
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(ownConsumptionListProvider);
    final rooms = ref.watch(consumptionRoomsProvider);
    final creating = ref.watch(createConsumptionControllerProvider).isLoading;
    final nowUtc = ref.watch(consumptionClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Pemakaian')),
      floatingActionButton: FloatingActionButton.extended(
        key: ConsumptionListPage.createKey,
        // Disabled while a create is in flight, so two taps cannot produce two
        // documents.
        onPressed: creating ? null : _create,
        icon: const Icon(Icons.add),
        label: const Text('Catat Pemakaian'),
      ),
      body: Column(
        children: [
          const _NurseDashboardStrip(),
          const ConsumptionRoomChips(),
          const ConsumptionStatusChips(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: TextField(
              key: ConsumptionListPage.searchKey,
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                labelText: 'Cari nomor, ruangan, barang atau batch',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (rooms.value?.isEmpty ?? false)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: ConsumptionNotice(
                key: ConsumptionListPage.noRoomKey,
                title: 'Belum ada ruangan aktif',
                message:
                    'Cabang Anda belum memiliki ruangan aktif dengan lokasi '
                    'stok, sehingga pemakaian belum dapat dicatat. Hubungi '
                    'administrator.',
                icon: Icons.meeting_room_outlined,
              ),
            ),
          Expanded(
            child: documents.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(message: describeFailure(error)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: ConsumptionNotice(
                      key: ConsumptionListPage.emptyKey,
                      title: 'Belum ada pemakaian',
                      message:
                          'Tekan Catat Pemakaian untuk mencatat barang yang '
                          'dipakai di ruangan Anda.',
                      icon: Icons.medical_services_outlined,
                    ),
                  );
                }
                return ListView.separated(
                  key: ConsumptionListPage.listKey,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => ConsumptionSummaryCard(
                    summary: rows[index],
                    nowUtc: nowUtc,
                    onTap: () => context.pushNamed(
                      rows[index].consumption.isDraft
                          ? AppRoutes.consumptionEditName
                          : AppRoutes.consumptionDetailName,
                      pathParameters: {'id': rows[index].id},
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One list row: the number, the room, the counters and the audit facts (§27).
///
/// Shared with the branch head's history, because a summary row shows the same facts
/// whoever is reading it — and writing it twice is how the two come to disagree about
/// which timezone a timestamp is in.
class ConsumptionSummaryCard extends StatelessWidget {
  const ConsumptionSummaryCard({
    super.key,
    required this.summary,
    required this.nowUtc,
    this.onTap,
    this.showNurse = false,
  });

  final ConsumptionSummary summary;
  final DateTime nowUtc;
  final VoidCallback? onTap;

  /// `true` on the branch head's history, where *whose* usage it was is the point.
  final bool showNurse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consumption = summary.consumption;
    final postedAt = consumption.postedAt;

    return Card(
      key: ConsumptionListPage.rowKeyFor(summary.id),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.docNumber,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ConsumptionStatusChip(status: summary.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(summary.roomLabel, style: theme.textTheme.bodyMedium),
              if (showNurse) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Perawat: ${summary.createdByName}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Dibuat ${AppDateTimeFormatter.dateTimeWithZone(consumption.createdAt)}',
                style: theme.textTheme.bodySmall,
              ),
              if (postedAt != null)
                Text(
                  'Diposting ${AppDateTimeFormatter.dateTimeWithZone(postedAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConsumptionPill(
                    label: summary.label,
                    color: theme.colorScheme.primary,
                  ),
                  SyncStatusTag(status: consumption.syncStatus),
                  if (summary.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (summary.roomIsHistorical) 'Ruangan',
                        if (summary.branchIsHistorical) 'Cabang',
                        if (summary.createdByIsHistorical) 'Perawat',
                        if (summary.postedByIsHistorical) 'Pemosting',
                      ].join(', '),
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

/// The nurse's dashboard strip above the list (§32).
///
/// Four numbers, and the last two are G-E6's badges: near-expiry in orange because it is
/// what should be used next, expired in red because it cannot be used at all and somebody
/// has to be told.
class _NurseDashboardStrip extends ConsumerWidget {
  const _NurseDashboardStrip();

  static const Key stripKey = ValueKey('consumptionDashboardStrip');
  static const Key draftKey = ValueKey('consumptionDashboardDrafts');
  static const Key todayKey = ValueKey('consumptionDashboardToday');
  static const Key lowStockKey = ValueKey('consumptionDashboardLowStock');
  static const Key nearExpiryKey = ValueKey('consumptionDashboardNearExpiry');
  static const Key expiredKey = ValueKey('consumptionDashboardExpired');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(nurseConsumptionDashboardProvider).value;
    if (summary == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      key: stripKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: KeyedSubtree(
              key: draftKey,
              child: StatusCard(
                label: 'Draft belum diposting',
                value: '${summary.draftCount}',
                icon: Icons.edit_note,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 160,
            child: KeyedSubtree(
              key: todayKey,
              child: StatusCard(
                label: 'Pemakaian hari ini',
                value: '${summary.postedTodayCount}',
                icon: Icons.today,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 160,
            child: KeyedSubtree(
              key: lowStockKey,
              child: StatusCard(
                label: 'Stok ruangan menipis',
                value: '${summary.lowStockPositions}',
                icon: Icons.trending_down,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 170,
            child: KeyedSubtree(
              key: nearExpiryKey,
              child: StatusCard(
                label: 'Segera kedaluwarsa',
                value: '${summary.nearExpiryPositions}',
                icon: Icons.schedule,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 160,
            child: KeyedSubtree(
              key: expiredKey,
              child: StatusCard(
                label: 'Kedaluwarsa',
                value: '${summary.expiredPositions}',
                icon: Icons.block,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `2 box · 3 ampul` — per-unit totals, never one summed number.
///
/// Quantities of different units are not addable: `2 box` and `3 ampul` are not `5` of
/// anything, and a single headline figure would mislead. Shared by the detail screens and
/// the branch history.
String formatTotalsByUnit(Map<String, Quantity> totals) {
  if (totals.isEmpty) return '—';
  final units = totals.keys.toList()..sort();
  return units.map((unit) => totals[unit]!.formatWithUnit(unit)).join(' · ');
}
