import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/goods_return_models.dart';
import '../providers/goods_return_providers.dart';
import '../widgets/goods_return_badges.dart';
import 'goods_return_detail_page.dart';

/// The Petugas Warehouse's Retur queue and history (§31).
///
/// Two sections, across **every** branch — this is the one document in the application
/// whose Warehouse side is deliberately not branch-scoped, because the goods all arrive
/// at one building. What keeps a Warehouse user out of a branch's private work is not a
/// branch predicate but a *status* one: `shipped` and `received` only, baked into the
/// DAO's scope rather than passed as a parameter, so a draft cannot appear here even if
/// a call site asked for one (§15).
class WarehouseGoodsReturnListPage extends ConsumerStatefulWidget {
  const WarehouseGoodsReturnListPage({super.key});

  static const Duration searchDebounce = Duration(milliseconds: 250);

  static const Key tabsKey = ValueKey('warehouseGoodsReturnTabs');
  static const Key searchKey = ValueKey('warehouseGoodsReturnSearch');
  static const Key branchChipsKey = ValueKey('warehouseGoodsReturnBranchChips');
  static const Key queueListKey = ValueKey('warehouseGoodsReturnQueue');
  static const Key queueEmptyKey = ValueKey('warehouseGoodsReturnQueueEmpty');
  static const Key historyListKey = ValueKey('warehouseGoodsReturnHistory');
  static const Key historyEmptyKey = ValueKey(
    'warehouseGoodsReturnHistoryEmpty',
  );
  static const Key awaitingCardKey = ValueKey('warehouseGoodsReturnAwaiting');
  static const Key expiredCardKey = ValueKey('warehouseGoodsReturnExpired');
  static const Key receivedTodayCardKey = ValueKey(
    'warehouseGoodsReturnReceivedToday',
  );
  static const Key outstandingCardKey = ValueKey(
    'warehouseGoodsReturnOutstanding',
  );

  static Key branchChipKey(String branchId) =>
      ValueKey('warehouseGoodsReturnBranchChip-$branchId');

  @override
  ConsumerState<WarehouseGoodsReturnListPage> createState() =>
      _WarehouseGoodsReturnListPageState();
}

class _WarehouseGoodsReturnListPageState
    extends ConsumerState<WarehouseGoodsReturnListPage> {
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
      WarehouseGoodsReturnListPage.searchDebounce,
      () => ref
          .read(warehouseGoodsReturnFilterProvider.notifier)
          .setSearchQuery(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(warehouseGoodsReturnQueueProvider);
    final history = ref.watch(warehouseGoodsReturnHistoryProvider);
    final nowUtc = ref.watch(goodsReturnClockProvider)();
    final dashboard = ref
        .watch(warehouseGoodsReturnDashboardProvider(nowUtc))
        .value;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Retur dari Cabang'),
          bottom: const TabBar(
            key: WarehouseGoodsReturnListPage.tabsKey,
            tabs: [
              Tab(text: 'Menunggu Penerimaan'),
              Tab(text: 'Riwayat Diterima'),
            ],
          ),
        ),
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
                    width: 180,
                    child: StatusCard(
                      key: WarehouseGoodsReturnListPage.awaitingCardKey,
                      label: 'Menunggu penerimaan',
                      value: '${dashboard?.awaitingCount ?? 0}',
                      icon: Icons.local_shipping_outlined,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 200,
                    child: StatusCard(
                      key: WarehouseGoodsReturnListPage.expiredCardKey,
                      label: 'Memuat batch kedaluwarsa',
                      value: '${dashboard?.expiredBatchCount ?? 0}',
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 180,
                    child: StatusCard(
                      key: WarehouseGoodsReturnListPage.receivedTodayCardKey,
                      label: 'Diterima hari ini',
                      value: '${dashboard?.receivedTodayCount ?? 0}',
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 210,
                    child: StatusCard(
                      key: WarehouseGoodsReturnListPage.outstandingCardKey,
                      label: 'Selisih GR belum diretur',
                      value: '${dashboard?.outstandingReceiptCount ?? 0}',
                      icon: Icons.assignment_late_outlined,
                    ),
                  ),
                ],
              ),
            ),
            const _BranchChips(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: TextField(
                key: WarehouseGoodsReturnListPage.searchKey,
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  labelText: 'Cari RET, GR, SJ, PR, cabang, barang atau batch',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _QueueTab(
                    rows: queue,
                    nowUtc: nowUtc,
                    listKey: WarehouseGoodsReturnListPage.queueListKey,
                    emptyKey: WarehouseGoodsReturnListPage.queueEmptyKey,
                    emptyTitle: 'Tidak ada retur yang menunggu',
                    emptyMessage:
                        'Retur yang sudah dikirim cabang akan muncul di sini '
                        'untuk diperiksa dan diterima. Draft cabang tidak '
                        'ditampilkan.',
                  ),
                  _QueueTab(
                    rows: history,
                    nowUtc: nowUtc,
                    listKey: WarehouseGoodsReturnListPage.historyListKey,
                    emptyKey: WarehouseGoodsReturnListPage.historyEmptyKey,
                    emptyTitle: 'Belum ada retur diterima',
                    emptyMessage:
                        'Retur yang sudah dikonfirmasi akan tercatat di sini.',
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

/// The branch **chip**, not a branch scope (§31).
///
/// It narrows a read that is already pinned to the two Warehouse-visible statuses, and
/// the two predicates are ANDed — so it can only ever restrict, never widen a Warehouse
/// user into a branch's drafts.
class _BranchChips extends ConsumerWidget {
  const _BranchChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(goodsReturnBranchesProvider).value ?? const [];
    if (branches.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(warehouseGoodsReturnFilterProvider).branchId;

    return SingleChildScrollView(
      key: WarehouseGoodsReturnListPage.branchChipsKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Semua cabang'),
            selected: selected == null,
            onSelected: (_) => ref
                .read(warehouseGoodsReturnFilterProvider.notifier)
                .setBranchId(null),
          ),
          for (final branch in branches) ...[
            const SizedBox(width: AppSpacing.sm),
            ChoiceChip(
              key: WarehouseGoodsReturnListPage.branchChipKey(branch.id),
              label: Text(branch.code),
              selected: selected == branch.id,
              onSelected: (_) => ref
                  .read(warehouseGoodsReturnFilterProvider.notifier)
                  .setBranchId(selected == branch.id ? null : branch.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.rows,
    required this.nowUtc,
    required this.listKey,
    required this.emptyKey,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final AsyncValue<List<GoodsReturnSummary>> rows;
  final DateTime nowUtc;
  final Key listKey;
  final Key emptyKey;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return rows.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ErrorNotice(message: describeFailure(error)),
      ),
      data: (values) {
        if (values.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: GoodsReturnNotice(
              key: emptyKey,
              title: emptyTitle,
              message: emptyMessage,
              icon: Icons.inbox_outlined,
            ),
          );
        }
        return ListView.separated(
          key: listKey,
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: values.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => GoodsReturnSummaryCard(
            summary: values[index],
            nowUtc: nowUtc,
            showBranch: true,
            onTap: () => context.pushNamed(
              AppRoutes.warehouseReturnDetailName,
              pathParameters: {'id': values[index].id},
            ),
          ),
        );
      },
    );
  }
}

/// One Retur, seen by the Warehouse that is about to count it in (§32).
///
/// Two affordances on a `shipped` document: an optional note and *Terima Retur*. There
/// is **no** partial checkbox and no quantity editor, and §16.16 is why — a Warehouse
/// user who opens the box and finds it does not match must not be able to quietly write
/// down what they actually found. That would replace the branch's account with the
/// Warehouse's, silently, with no record of the disagreement. A mismatch blocks the
/// confirmation and stays a residual operational issue for people to resolve.
class WarehouseGoodsReturnDetailPage extends ConsumerStatefulWidget {
  const WarehouseGoodsReturnDetailPage({
    super.key,
    required this.goodsReturnId,
  });

  final String goodsReturnId;

  static const Key linesKey = ValueKey('warehouseGoodsReturnLines');
  static const Key noteFieldKey = ValueKey('warehouseGoodsReturnNote');
  static const Key receiveButtonKey = ValueKey('warehouseGoodsReturnReceive');
  static const Key receiveConfirmKey = ValueKey(
    'warehouseGoodsReturnReceiveConfirm',
  );
  static const Key readOnlyKey = ValueKey('warehouseGoodsReturnReadOnly');
  static const Key missingKey = ValueKey('warehouseGoodsReturnMissing');

  @override
  ConsumerState<WarehouseGoodsReturnDetailPage> createState() =>
      _WarehouseGoodsReturnDetailPageState();
}

class _WarehouseGoodsReturnDetailPageState
    extends ConsumerState<WarehouseGoodsReturnDetailPage> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _receive(GoodsReturnDetail detail, DateTime nowUtc) async {
    final expired = detail.lines.where((line) => line.isExpired(nowUtc)).length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terima Retur?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tujuan: Warehouse Pusat',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${detail.lineCount} posisi · '
              '${GoodsReturnQuantitySummary.format(detail.totalQuantityByUnit)}',
            ),
            if (expired > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$expired posisi memuat batch kedaluwarsa. Barang tetap masuk '
                'saldo Warehouse dan hanya dapat dikeluarkan lewat Pemusnahan.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Seluruh barang retur akan dikembalikan ke saldo Warehouse '
              'Pusat.\n\n'
              'Movement return akan dibuat untuk setiap baris.\n\n'
              'Tindakan ini final dan tidak dapat dibatalkan dari dokumen ini.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: WarehouseGoodsReturnDetailPage.receiveConfirmKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Terima Retur'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final text = _note.text.trim();
    final result = await ref
        .read(goodsReturnActionsProvider.notifier)
        .receive(
          goodsReturnId: widget.goodsReturnId,
          warehouseNote: text.isEmpty ? null : text,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? 'Retur diterima. Saldo Warehouse sudah bertambah.'
              : result.errorMessage ?? 'Retur gagal diterima.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(
      warehouseGoodsReturnDetailProvider(widget.goodsReturnId),
    );
    final nowUtc = ref.watch(goodsReturnClockProvider)();
    final busy = ref.watch(goodsReturnActionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Periksa Retur')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
        data: (value) {
          if (value == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: GoodsReturnNotice(
                key: WarehouseGoodsReturnDetailPage.missingKey,
                title: 'Dokumen tidak tersedia',
                message:
                    'Dokumen retur ini tidak ditemukan atau belum dikirim '
                    'cabang.',
                icon: Icons.lock_outline,
              ),
            );
          }
          return _WarehouseBody(
            detail: value,
            nowUtc: nowUtc,
            busy: busy,
            noteController: _note,
            onReceive: () => _receive(value, nowUtc),
          );
        },
      ),
    );
  }
}

class _WarehouseBody extends StatelessWidget {
  const _WarehouseBody({
    required this.detail,
    required this.nowUtc,
    required this.busy,
    required this.noteController,
    required this.onReceive,
  });

  final GoodsReturnDetail detail;
  final DateTime nowUtc;
  final bool busy;
  final TextEditingController noteController;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final document = detail.goodsReturn;
    final summary = detail.summary;
    final transit = summary.transitAge(nowUtc);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                document.docNumber,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            GoodsReturnStatusChip(status: document.status),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(summary.branchLabel),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WarehouseFact(
                  label: 'Penerimaan Barang',
                  value: summary.grDocNumber,
                ),
                _WarehouseFact(
                  label: 'Surat Jalan',
                  value: summary.doDocNumber,
                ),
                _WarehouseFact(
                  label: 'Purchase Request',
                  value: summary.prDocNumber,
                ),
                _WarehouseFact(
                  label: 'Dibuat oleh',
                  value: summary.createdByName,
                ),
                if (document.shippedAt != null)
                  _WarehouseFact(
                    label: 'Dikirim',
                    value:
                        '${AppDateTimeFormatter.dateTimeWithZone(document.shippedAt!)}'
                        '${summary.shippedByName == null ? '' : ' · ${summary.shippedByName}'}'
                        '${transit == null ? '' : ' · ${_ageLabel(transit)} di jalan'}',
                  ),
                if (document.receivedAt != null)
                  _WarehouseFact(
                    label: 'Diterima',
                    value:
                        '${AppDateTimeFormatter.dateTimeWithZone(document.receivedAt!)}'
                        '${summary.receivedByName == null ? '' : ' · ${summary.receivedByName}'}',
                  ),
                if (document.hasNote)
                  _WarehouseFact(
                    label: 'Catatan cabang',
                    value: document.note!,
                  ),
                if (document.hasWarehouseNote)
                  _WarehouseFact(
                    label: 'Catatan Warehouse',
                    value: document.warehouseNote!,
                  ),
                if (document.isPendingSync)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: SyncStatusTag(status: document.syncStatus),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        StatusCard(
          label: 'Total retur',
          value: GoodsReturnQuantitySummary.format(detail.totalQuantityByUnit),
          icon: Icons.assignment_return_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Barang yang diretur',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Column(
          key: WarehouseGoodsReturnDetailPage.linesKey,
          children: [
            for (final line in detail.lines)
              GoodsReturnLineTile(line: line, nowUtc: nowUtc),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (detail.canReceive) ...[
          TextField(
            key: WarehouseGoodsReturnDetailPage.noteFieldKey,
            controller: noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan Warehouse (opsional)',
              helperText:
                  'Misalnya kondisi kemasan saat diterima. Disimpan bersama '
                  'konfirmasi penerimaan.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            key: WarehouseGoodsReturnDetailPage.receiveButtonKey,
            onPressed: busy ? null : onReceive,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Terima Retur'),
          ),
        ] else
          const GoodsReturnNotice(
            key: WarehouseGoodsReturnDetailPage.readOnlyKey,
            title: 'Retur sudah diterima',
            message:
                'Dokumen ini final. Saldo Warehouse sudah bertambah dan '
                'koreksi dilakukan lewat dokumen baru, bukan dengan mengubah '
                'dokumen ini.',
            icon: Icons.verified_outlined,
          ),
      ],
    );
  }

  static String _ageLabel(Duration age) {
    if (age.inDays >= 1) return '${age.inDays} hari';
    if (age.inHours >= 1) return '${age.inHours} jam';
    return '${age.inMinutes} menit';
  }
}

class _WarehouseFact extends StatelessWidget {
  const _WarehouseFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
