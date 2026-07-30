import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/status_card.dart';
import '../../domain/models/goods_return_models.dart';
import '../providers/goods_return_providers.dart';
import '../widgets/goods_return_badges.dart';

/// The Kepala Cabang's Retur section (§29).
///
/// Four sections, and the order is the workflow: what still needs raising, what is
/// drafted, what is on a road, what has arrived.
///
/// ### What *Perlu Dibuat* can never contain
///
/// A shortage. §16.10 is the rule and it is worth restating on the screen that would
/// most easily blur it: a **rejection** is goods that arrived and were refused and are
/// physically at the branch, while a **shortage** is a quantity that never arrived. Only
/// the first has a box to send back — and the eligible query never returns the second,
/// so this screen has no way to offer a *Buat Retur* button for one.
///
/// Shortages remain visible where they belong: on the Warehouse's Good Receipt
/// discrepancy queue, labelled *Kekurangan* (§33).
class BranchGoodsReturnListPage extends ConsumerStatefulWidget {
  const BranchGoodsReturnListPage({super.key});

  static const Duration searchDebounce = Duration(milliseconds: 250);

  static const Key tabsKey = ValueKey('branchGoodsReturnTabs');
  static const Key searchKey = ValueKey('branchGoodsReturnSearch');
  static const Key pendingListKey = ValueKey('branchGoodsReturnPending');
  static const Key pendingEmptyKey = ValueKey('branchGoodsReturnPendingEmpty');
  static const Key draftListKey = ValueKey('branchGoodsReturnDrafts');
  static const Key draftEmptyKey = ValueKey('branchGoodsReturnDraftsEmpty');
  static const Key transitListKey = ValueKey('branchGoodsReturnTransit');
  static const Key transitEmptyKey = ValueKey('branchGoodsReturnTransitEmpty');
  static const Key historyListKey = ValueKey('branchGoodsReturnHistory');
  static const Key historyEmptyKey = ValueKey('branchGoodsReturnHistoryEmpty');

  static Key createButtonKey(String grId) =>
      ValueKey('branchGoodsReturnCreate-$grId');

  @override
  ConsumerState<BranchGoodsReturnListPage> createState() =>
      _BranchGoodsReturnListPageState();
}

class _BranchGoodsReturnListPageState
    extends ConsumerState<BranchGoodsReturnListPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(BranchGoodsReturnListPage.searchDebounce, () {
      if (!mounted) return;
      setState(() => _query = value);
      ref.read(branchGoodsReturnFilterProvider.notifier).setSearchQuery(value);
    });
  }

  Future<void> _createFor(GoodsReturnEligibility row) async {
    final result = await ref
        .read(goodsReturnActionsProvider.notifier)
        .create(goodReceiptId: row.grId);
    if (!mounted) return;

    if (result.isSuccess) {
      // Replace rather than push: the receipt this came from is no longer actionable,
      // so leaving it on the stack would let *Back* return to a dead button (§30).
      context.pushReplacementNamed(
        AppRoutes.returnDetailName,
        pathParameters: {'id': result.documentId!},
      );
      return;
    }

    final existingId = result.documentId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.errorMessage ?? 'Retur gagal dibuat.'),
        // A concurrent create loses to the unique index rather than to a bug, and the
        // branch head almost certainly wants the document that won (§30).
        action: existingId == null
            ? null
            : SnackBarAction(
                label: 'Lihat Retur',
                onPressed: () => context.pushNamed(
                  AppRoutes.returnDetailName,
                  pathParameters: {'id': existingId},
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eligible = ref.watch(branchRejectedGoodReceiptsProvider(_query));
    final documents = ref.watch(branchGoodsReturnListProvider);
    final nowUtc = ref.watch(goodsReturnClockProvider)();
    final busy = ref.watch(goodsReturnActionsProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Retur Barang'),
          bottom: const TabBar(
            key: BranchGoodsReturnListPage.tabsKey,
            isScrollable: true,
            tabs: [
              Tab(text: 'Perlu Dibuat'),
              Tab(text: 'Draft'),
              Tab(text: 'Dalam Perjalanan'),
              Tab(text: 'Riwayat Diterima'),
            ],
          ),
        ),
        body: Column(
          children: [
            _DashboardStrip(nowUtc: nowUtc),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: TextField(
                key: BranchGoodsReturnListPage.searchKey,
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  labelText: 'Cari nomor RET, GR, SJ, PR, barang atau batch',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _PendingTab(
                    eligible: eligible,
                    nowUtc: nowUtc,
                    busy: busy,
                    onCreate: _createFor,
                  ),
                  _DocumentTab(
                    documents: documents,
                    nowUtc: nowUtc,
                    status: GoodsReturnStatus.draft,
                    listKey: BranchGoodsReturnListPage.draftListKey,
                    emptyKey: BranchGoodsReturnListPage.draftEmptyKey,
                    emptyTitle: 'Belum ada draft retur',
                    emptyMessage:
                        'Draft yang sudah dibuat tetapi belum dikirim akan '
                        'muncul di sini.',
                  ),
                  _DocumentTab(
                    documents: documents,
                    nowUtc: nowUtc,
                    status: GoodsReturnStatus.shipped,
                    listKey: BranchGoodsReturnListPage.transitListKey,
                    emptyKey: BranchGoodsReturnListPage.transitEmptyKey,
                    emptyTitle: 'Tidak ada retur dalam perjalanan',
                    emptyMessage:
                        'Retur yang sudah dikirim akan menunggu konfirmasi '
                        'Warehouse di sini. Saldo Warehouse belum bertambah '
                        'sampai Warehouse mengonfirmasi penerimaan.',
                  ),
                  _DocumentTab(
                    documents: documents,
                    nowUtc: nowUtc,
                    status: GoodsReturnStatus.received,
                    listKey: BranchGoodsReturnListPage.historyListKey,
                    emptyKey: BranchGoodsReturnListPage.historyEmptyKey,
                    emptyTitle: 'Belum ada retur yang diterima',
                    emptyMessage:
                        'Retur yang sudah dikonfirmasi Warehouse akan tercatat '
                        'di sini.',
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

/// The four counters §35 asks the branch dashboard for.
class _DashboardStrip extends ConsumerWidget {
  const _DashboardStrip({required this.nowUtc});

  final DateTime nowUtc;

  static const Key pendingKey = ValueKey('branchGoodsReturnCardPending');
  static const Key draftKey = ValueKey('branchGoodsReturnCardDraft');
  static const Key transitKey = ValueKey('branchGoodsReturnCardTransit');
  static const Key receivedTodayKey = ValueKey(
    'branchGoodsReturnCardReceivedToday',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(branchGoodsReturnDashboardProvider(nowUtc));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: StatusCard(
              key: pendingKey,
              label: 'Belum dibuatkan retur',
              value: '${summary.pendingReceiptCount}',
              icon: Icons.assignment_late_outlined,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 150,
            child: StatusCard(
              key: draftKey,
              label: 'Draft retur',
              value: '${summary.draftCount}',
              icon: Icons.edit_note,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 170,
            child: StatusCard(
              key: transitKey,
              label: 'Sedang dikirim',
              value: '${summary.shippedCount}',
              icon: Icons.local_shipping_outlined,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 190,
            child: StatusCard(
              key: receivedTodayKey,
              label: 'Diterima hari ini',
              value: '${summary.receivedTodayCount}',
              icon: Icons.inventory_2_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingTab extends StatelessWidget {
  const _PendingTab({
    required this.eligible,
    required this.nowUtc,
    required this.busy,
    required this.onCreate,
  });

  final AsyncValue<List<GoodsReturnEligibility>> eligible;
  final DateTime nowUtc;
  final bool busy;
  final Future<void> Function(GoodsReturnEligibility) onCreate;

  @override
  Widget build(BuildContext context) {
    return eligible.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ErrorNotice(message: describeFailure(error)),
      ),
      data: (rows) {
        final actionable = rows
            .where((row) => row.canCreateReturn)
            .toList(growable: false);
        if (actionable.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: GoodsReturnNotice(
              key: BranchGoodsReturnListPage.pendingEmptyKey,
              title: 'Tidak ada barang yang perlu diretur',
              message:
                  'Setiap Penerimaan Barang yang memuat barang ditolak akan '
                  'muncul di sini. Selisih kirim (kekurangan) tidak diretur '
                  'karena barangnya memang tidak pernah sampai.',
              icon: Icons.inventory_outlined,
            ),
          );
        }
        return ListView.separated(
          key: BranchGoodsReturnListPage.pendingListKey,
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: actionable.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => _EligibleCard(
            row: actionable[index],
            nowUtc: nowUtc,
            busy: busy,
            onCreate: () => onCreate(actionable[index]),
          ),
        );
      },
    );
  }
}

/// One posted Good Receipt that still owes a return (§29).
class _EligibleCard extends StatelessWidget {
  const _EligibleCard({
    required this.row,
    required this.nowUtc,
    required this.busy,
    required this.onCreate,
  });

  final GoodsReturnEligibility row;
  final DateTime nowUtc;
  final bool busy;
  final VoidCallback onCreate;

  static Key keyFor(String grId) => ValueKey('goodsReturnEligible-$grId');

  @override
  Widget build(BuildContext context) {
    final expired = row.expiredCount(nowUtc);
    final near = row.nearExpiryCount(nowUtc);
    final postedAt = row.grPostedAt;

    return Card(
      key: keyFor(row.grId),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GR ${row.grDocNumber}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'SJ ${row.doDocNumber} · PR ${row.prDocNumber}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (postedAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Diposting ${AppDateTimeFormatter.dateTimeWithZone(postedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${row.rejectedLineCount} barang ditolak · '
              '${GoodsReturnQuantitySummary.format(row.totalQuantityByUnit)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (row.rejectReasons.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Alasan: ${row.rejectReasons.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (expired > 0 || near > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  if (expired > 0) '$expired batch kedaluwarsa',
                  if (near > 0) '$near batch segera kedaluwarsa',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: expired > 0 ? AppColors.danger : AppColors.warning,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: BranchGoodsReturnListPage.createButtonKey(row.grId),
                onPressed: busy ? null : onCreate,
                icon: const Icon(Icons.assignment_return_outlined, size: 18),
                label: const Text('Buat Retur'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTab extends StatelessWidget {
  const _DocumentTab({
    required this.documents,
    required this.nowUtc,
    required this.status,
    required this.listKey,
    required this.emptyKey,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final AsyncValue<List<GoodsReturnSummary>> documents;
  final DateTime nowUtc;
  final GoodsReturnStatus status;
  final Key listKey;
  final Key emptyKey;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return documents.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ErrorNotice(message: describeFailure(error)),
      ),
      data: (rows) {
        final matching = rows
            .where((row) => row.status == status)
            .toList(growable: false);
        if (matching.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: GoodsReturnNotice(
              key: emptyKey,
              title: emptyTitle,
              message: emptyMessage,
            ),
          );
        }
        return ListView.separated(
          key: listKey,
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: matching.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => GoodsReturnSummaryCard(
            summary: matching[index],
            nowUtc: nowUtc,
            onTap: () => context.pushNamed(
              AppRoutes.returnDetailName,
              pathParameters: {'id': matching[index].id},
            ),
          ),
        );
      },
    );
  }
}
