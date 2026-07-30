import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/widgets/status_card.dart';
import '../providers/consumption_providers.dart';
import '../widgets/consumption_badges.dart';
import '../widgets/consumption_filters.dart';
import 'consumption_list_page.dart';

/// The Kepala Cabang's read-only Pemakaian history (§31).
///
/// Everything here is a *read*. There is no create button, no edit control, no remove, no
/// post and no approval — §31 lists their absence, and it is not an oversight: spec §3.1
/// gives the branch head branch-level acts, and recording what was physically used in a
/// treatment room is not one of them. The person who opened the packet is the only one who
/// knows how much came out of it. What a branch head legitimately needs is oversight, and
/// that is what this screen is.
///
/// ### What it can never show
///
/// A **draft**. The list reads [branchConsumptionListProvider], whose scope carries
/// `status = 'posted'` inside the DAO's own predicate (§14) — not in a parameter this
/// screen passes, because a rule that depended on one call site would be one edit away
/// from leaking a nurse's unfinished work. Nor another branch's document: the branch id
/// comes from the *stored* actor.
///
/// ### Why the date filter is applied in Dart
///
/// `posted_at` is ISO-8601 TEXT, so a SQL `BETWEEN` on two serialised dates would compare
/// characters rather than instants — the trap schema v4 removed from `stock_opnames`. §31
/// asks for the filter to be a UTC instant range, and [consumptionPostedRangeProvider]
/// derives it from the picked operational day through `AppTimeZone`.
class BranchConsumptionListPage extends ConsumerStatefulWidget {
  const BranchConsumptionListPage({super.key});

  static const Key listKey = ValueKey('branchConsumptionList');
  static const Key emptyKey = ValueKey('branchConsumptionListEmpty');
  static const Key searchKey = ValueKey('branchConsumptionListSearch');
  static const Key dateKey = ValueKey('branchConsumptionDateFilter');
  static const Key dateClearKey = ValueKey('branchConsumptionDateClear');

  @override
  ConsumerState<BranchConsumptionListPage> createState() =>
      _BranchConsumptionListPageState();
}

class _BranchConsumptionListPageState
    extends ConsumerState<BranchConsumptionListPage> {
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

  Future<void> _pickDate() async {
    final nowUtc = ref.read(consumptionClockProvider)();
    final today = AppTimeZone.operationalDate(nowUtc);
    final current = ref.read(consumptionDateFilterProvider) ?? today;

    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      // A year back is more history than a branch head reads on a phone, and the future
      // has nothing posted in it.
      firstDate: DateTime.utc(today.year - 1, today.month, today.day),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    // Kept as a civil date: it is the *operational day* the branch head picked, and
    // `consumptionPostedRangeProvider` turns it into the two UTC instants it covers.
    ref
        .read(consumptionDateFilterProvider.notifier)
        .select(DateTime.utc(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(branchConsumptionListProvider);
    final dashboard = ref.watch(branchConsumptionDashboardProvider);
    final selectedDay = ref.watch(consumptionDateFilterProvider);
    final nowUtc = ref.watch(consumptionClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Pemakaian')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 170,
                  child: StatusCard(
                    label: 'Pemakaian hari ini',
                    value: '${dashboard.postedTodayCount}',
                    icon: Icons.today,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 190,
                  child: _BusiestRoomCard(
                    roomId: dashboard.busiestRoomId,
                    documentCount: dashboard.busiestRoomId == null
                        ? 0
                        : dashboard.documentsByRoom[dashboard.busiestRoomId] ??
                              0,
                  ),
                ),
              ],
            ),
          ),
          const ConsumptionRoomChips(forBranchHistory: true),
          const ConsumptionNurseChips(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: BranchConsumptionListPage.searchKey,
                    controller: _search,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      labelText: 'Cari nomor, ruangan, barang atau batch',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  key: BranchConsumptionListPage.dateKey,
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    selectedDay == null
                        ? 'Semua tanggal'
                        : AppDateTimeFormatter.civilDate(selectedDay),
                  ),
                ),
                if (selectedDay != null)
                  IconButton(
                    key: BranchConsumptionListPage.dateClearKey,
                    onPressed: () => ref
                        .read(consumptionDateFilterProvider.notifier)
                        .clear(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Hapus filter tanggal',
                  ),
              ],
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
                      key: BranchConsumptionListPage.emptyKey,
                      title: 'Belum ada pemakaian diposting',
                      message:
                          'Belum ada pemakaian yang diposting di cabang ini '
                          'sesuai filter yang dipilih. Draft perawat tidak '
                          'ditampilkan di sini.',
                      icon: Icons.history,
                    ),
                  );
                }
                return ListView.separated(
                  key: BranchConsumptionListPage.listKey,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => ConsumptionSummaryCard(
                    summary: rows[index],
                    nowUtc: nowUtc,
                    showNurse: true,
                    onTap: () => context.pushNamed(
                      AppRoutes.branchConsumptionDetailName,
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

/// "The room that used the most today", as a **document count** (§32).
///
/// Deliberately not a quantity: quantities of different units are not addable, so
/// *"ruangan dengan konsumsi tertinggi"* has no single answer in units. Counting documents
/// is a number that means something on its own — and a card that showed a summed figure
/// across `box` and `ampul` would be worse than one that showed none.
class _BusiestRoomCard extends ConsumerWidget {
  const _BusiestRoomCard({required this.roomId, required this.documentCount});

  final String? roomId;
  final int documentCount;

  static const Key cardKey = ValueKey('branchConsumptionBusiestRoom');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (roomId == null) {
      return const KeyedSubtree(
        key: cardKey,
        child: StatusCard(
          label: 'Ruangan tertinggi hari ini',
          value: '—',
          icon: Icons.meeting_room_outlined,
        ),
      );
    }

    final rooms = ref.watch(branchConsumptionRoomsProvider).value ?? const [];
    final match = rooms.where((room) => room.roomId == roomId);
    final label = match.isEmpty ? '—' : match.first.code;

    return KeyedSubtree(
      key: cardKey,
      child: StatusCard(
        label: 'Ruangan tertinggi · $documentCount dokumen',
        value: label,
        icon: Icons.meeting_room_outlined,
      ),
    );
  }
}
