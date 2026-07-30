import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/quantity_field.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/distribution_models.dart';
import '../providers/distribution_providers.dart';
import '../widgets/distribution_badges.dart';
import '../widgets/distribution_item_picker.dart';
import 'distribution_list_page.dart';

/// The multi-room Distribusi form (§29).
///
/// The flow spec §4.2 describes, top to bottom:
///
/// ```
/// pilih ruangan tujuan (chip, dinamis)
///   → CategoryFilterChips
///   → SearchableDropdown barang dari saldo Gudang Cabang
///   → alokasi FEFO otomatis
///   → qty
///   → Posting Distribusi
/// ```
///
/// One document, several rooms (G-T3): choosing a different chip does not start a new
/// document, it changes which room the next item is added to. The lines already stored
/// stay visible, grouped per room, so the branch head can see the whole distribution
/// while building it.
///
/// Everything is written through a use case as it is entered — there is no "save the
/// form" step. That is what lets each addition be validated against live stock (G-T2)
/// and FEFO (G-E3) at the moment it is made, and it is why the *Posting* button has
/// nothing left to validate except the document as a whole.
class DistributionFormPage extends ConsumerStatefulWidget {
  const DistributionFormPage({super.key, required this.distributionId});

  final String distributionId;

  static const Key listKey = ValueKey('distributionFormList');
  static const Key postKey = ValueKey('distributionPostButton');
  static const Key qtyKey = ValueKey('distributionQtyField');
  static const Key addKey = ValueKey('distributionAddButton');
  static const Key emptyKey = ValueKey('distributionFormEmpty');
  static const Key confirmKey = ValueKey('distributionPostConfirm');
  static const Key confirmAcceptKey = ValueKey('distributionPostConfirmAccept');
  static const Key readOnlyKey = ValueKey('distributionFormReadOnly');

  @override
  ConsumerState<DistributionFormPage> createState() =>
      _DistributionFormPageState();
}

class _DistributionFormPageState extends ConsumerState<DistributionFormPage> {
  /// The item chosen from the picker but not yet added — the row that shows a quantity
  /// field and an *Tambah* button.
  DistributionStockItem? _pending;

  /// The quantity typed for [_pending]. Held in a controller rather than read from the
  /// field on submit, so *Posting* can flush it: a branch head who types a number and
  /// taps the button without leaving the field would otherwise lose it (§29).
  final TextEditingController _qtyController = TextEditingController();

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _add(DistributionDetail detail) async {
    final item = _pending;
    final roomId = ref.read(distributionSelectedRoomProvider);
    if (item == null || roomId == null) return;

    final qty = Quantity.tryParse(_qtyController.text);
    if (qty == null || !qty.isPositive) {
      _notify('Masukkan jumlah lebih besar dari 0.');
      return;
    }

    final ok = await ref
        .read(distributionEditorControllerProvider.notifier)
        .addItem(
          distributionId: detail.id,
          roomId: roomId,
          itemId: item.itemId,
          qty: qty,
        );
    if (!mounted) return;
    if (!ok) {
      _notifyError();
      return;
    }
    setState(() {
      _pending = null;
      _qtyController.clear();
    });
  }

  void _notify(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _notifyError() {
    final error = ref.read(distributionEditorControllerProvider).error;
    _notify(describeFailure(error ?? 'Tindakan gagal. Coba lagi.'));
  }

  Future<void> _post(DistributionDetail initial) async {
    var detail = initial;

    // 1. Flush pending input first: a quantity typed but not yet added is work the
    // branch head believes is on the document, and posting without it would silently
    // distribute less than they intended.
    //
    // Attempted whenever an item is selected, not only when the field holds something:
    // an empty or invalid quantity then produces `_add`'s own message ("masukkan jumlah
    // lebih besar dari 0") rather than a button that appears to do nothing.
    if (_pending != null) {
      await _add(detail);
      if (!mounted) return;
      // Still pending means the flush was refused — `_add` has already said why.
      if (_pending != null) return;

      // Re-read the document after the flush. `initial` is the snapshot the build closed
      // over, and it does not know about the line that was just stored — confirming
      // against it would tell the branch head "belum memuat barang" about the very line
      // they just added, or quote a room and line count one short of the truth.
      //
      // `refresh` rather than `read`: the stored line reaches the widget through a drift
      // query stream, and that emission is asynchronous — this continuation runs before
      // it. Refreshing re-runs the branch-scoped query and awaits *its* first emission,
      // so the value is fresh by construction rather than by timing.
      final DistributionDetail? refreshed;
      try {
        refreshed = await ref.refresh(
          branchDistributionDetailProvider(widget.distributionId).future,
        );
      } on Object catch (error) {
        if (!mounted) return;
        _notify(describeFailure(error));
        return;
      }
      if (!mounted) return;
      if (refreshed == null) {
        _notify('Distribusi tidak dapat dimuat. Muat ulang halaman.');
        return;
      }
      detail = refreshed;
    }

    // 2. Nothing to post is not an error worth a dialog.
    if (detail.isEmpty) {
      _notify('Distribusi belum memuat barang.');
      return;
    }

    // 3–6. Confirm, and say exactly what will happen. Posting is final (G-S2) and moves
    // stock the moment it commits (spec §2.5), so the sentence names both sides.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: DistributionFormPage.confirmKey,
        title: const Text('Posting Distribusi?'),
        content: Text(
          'Stok Gudang Cabang akan berkurang dan stok '
          '${detail.roomCount} ruangan akan bertambah sesuai '
          '${detail.lineCount} baris pada dokumen ini.\n\n'
          'Setelah diposting, distribusi bersifat final dan tidak dapat '
          'diubah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: DistributionFormPage.confirmAcceptKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Posting'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 7–8. The controller's loading state disables the button, so a double tap cannot
    // post twice — and the guarded UPDATE would refuse the second one anyway.
    final ok = await ref
        .read(distributionEditorControllerProvider.notifier)
        .post(detail.id);
    if (!mounted) return;
    if (!ok) {
      _notifyError();
      return;
    }

    // 9–10. Say what happened, then open the read-only detail.
    final result = ref
        .read(distributionEditorControllerProvider.notifier)
        .lastPosting;
    _notify(
      'Distribusi diposting: ${result?.lineCount ?? detail.lineCount} baris '
      'ke ${result?.roomCount ?? detail.roomCount} ruangan.',
    );
    context.pushReplacementNamed(
      AppRoutes.distributionDetailName,
      pathParameters: {'id': detail.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(
      branchDistributionDetailProvider(widget.distributionId),
    );
    final action = ref.watch(distributionEditorControllerProvider);
    final nowUtc = ref.watch(distributionClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Distribusi')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(
            message: describeFailure(error),
            onRetry: () => ref.invalidate(
              branchDistributionDetailProvider(widget.distributionId),
            ),
          ),
        ),
        data: (document) {
          if (document == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Distribusi tidak ditemukan atau bukan milik cabang ini.',
                  ),
                ),
              ),
            );
          }

          // A posted document is read-only permanently (G-S2). The editor never renders
          // an action for it — the detail page is where it is read.
          if (!document.isEditable) {
            return _PostedNotice(distributionId: document.id);
          }

          final selectedRoom = ref.watch(distributionSelectedRoomProvider);
          final busy = action.isLoading;

          return ListView(
            key: DistributionFormPage.listKey,
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _Header(detail: document),
              const _SectionTitle('1 · Pilih ruangan tujuan'),
              DistributionRoomChips(enabled: !busy),
              const _SectionTitle('2 · Pilih kategori'),
              const DistributionCategoryFilterChips(),
              const _SectionTitle('3 · Cari barang dari saldo Gudang Cabang'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: selectedRoom == null
                    ? const Card(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Text('Pilih ruangan tujuan terlebih dahulu.'),
                        ),
                      )
                    : DistributionItemPicker(
                        enabled: !busy,
                        excludedItemIds: document
                            .linesForRoom(selectedRoom)
                            .map((line) => line.itemId)
                            .toSet(),
                        onSelected: (item) => setState(() {
                          _pending = item;
                          _qtyController.text = '';
                        }),
                      ),
              ),
              if (_pending != null && selectedRoom != null)
                _PendingItemCard(
                  item: _pending!,
                  controller: _qtyController,
                  nowUtc: nowUtc,
                  enabled: !busy,
                  onCancel: () => setState(() {
                    _pending = null;
                    _qtyController.clear();
                  }),
                  onAdd: () => _add(document),
                ),
              const _SectionTitle('4 · Alokasi per ruangan'),
              if (document.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Card(
                    key: DistributionFormPage.emptyKey,
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('Belum ada barang pada distribusi ini.'),
                    ),
                  ),
                )
              else
                for (final group in document.roomGroups)
                  _RoomGroupCard(
                    group: group,
                    distributionId: document.id,
                    nowUtc: nowUtc,
                    enabled: !busy,
                  ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: DistributionUnitTotals(totals: document.totalsByUnit),
              ),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: DistributionFormPage.postKey,
                    // The loading guard is the double-tap defence; `canPost` is the
                    // document's own precondition, and the use case remains the
                    // authority over both.
                    //
                    // `_pending != null` widens it deliberately: a branch head who picks
                    // their **first** item and presses *Posting* without tapping *Tambah*
                    // must have that input flushed (§29). Gating on `canPost` alone would
                    // leave the button dead on a document whose only line is still in the
                    // field — which reads as a broken screen, not as a rule.
                    onPressed: busy || (!document.canPost && _pending == null)
                        ? null
                        : () => _post(document),
                    icon: const Icon(Icons.outbound),
                    label: const Text('Posting Distribusi'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PostedNotice extends StatelessWidget {
  const _PostedNotice({required this.distributionId});

  final String distributionId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: DistributionFormPage.readOnlyKey,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Distribusi ini sudah diposting dan bersifat final, sehingga '
                'tidak dapat diubah.',
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => context.pushReplacementNamed(
                  AppRoutes.distributionDetailName,
                  pathParameters: {'id': distributionId},
                ),
                child: const Text('Lihat Detail'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final DistributionDetail detail;

  static const Key headerKey = ValueKey('distributionFormHeader');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distribution = detail.distribution;

    return Padding(
      key: headerKey,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      distribution.docNumber,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  DistributionStatusChip(status: distribution.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${detail.summary.branchCode} · ${detail.summary.branchName}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Didistribusikan ${detail.summary.distributedByName}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Dibuat ${AppDateTimeFormatter.dateTimeWithZone(distribution.createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if ((distribution.note ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    distribution.note!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${detail.roomCount} ruangan · ${detail.lineCount} baris',
                    style: theme.textTheme.bodySmall,
                  ),
                  SyncStatusTag(status: distribution.syncStatus),
                  if (detail.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail('Data master'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The item chosen from the picker, waiting for a quantity.
///
/// Shows what the store actually holds — the total, the batch count and the nearest
/// expiry — because a branch head typing a number needs to know the ceiling *before*
/// they hit it, not as a refusal afterwards.
class _PendingItemCard extends StatelessWidget {
  const _PendingItemCard({
    required this.item,
    required this.controller,
    required this.nowUtc,
    required this.enabled,
    required this.onCancel,
    required this.onAdd,
  });

  final DistributionStockItem item;
  final TextEditingController controller;
  final DateTime nowUtc;
  final bool enabled;
  final VoidCallback onCancel;
  final VoidCallback onAdd;

  static const Key cardKey = ValueKey('distributionPendingItem');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Card(
        key: cardKey,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.itemName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${item.sku} · tersedia '
                '${item.availableQty.formatWithUnit(item.unit)}',
                style: theme.textTheme.bodySmall,
              ),
              if (item.hasExpiry) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final candidate in item.candidates)
                      DistributionPill(
                        label:
                            '${candidate.batchNo} · '
                            '${candidate.availableQty.format()}',
                        color: theme.colorScheme.primary,
                      ),
                    if (item.nearestExpiryDate != null)
                      DistributionExpiryBadge(
                        expiryDate: item.nearestExpiryDate!,
                        expiryAlertDays: item.expiryAlertDays,
                        nowUtc: nowUtc,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Batch dipilih otomatis mengikuti FEFO (ED terdekat lebih '
                  'dahulu).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              QuantityField(
                key: DistributionFormPage.qtyKey,
                controller: controller,
                label: 'Jumlah',
                unit: item.unit,
                enabled: enabled,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: enabled ? onCancel : null,
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      key: DistributionFormPage.addKey,
                      onPressed: enabled ? onAdd : null,
                      child: const Text('Tambah'),
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

/// One room's lines, grouped (G-T3).
class _RoomGroupCard extends ConsumerWidget {
  const _RoomGroupCard({
    required this.group,
    required this.distributionId,
    required this.nowUtc,
    required this.enabled,
  });

  final DistributionRoomGroup group;
  final String distributionId;
  final DateTime nowUtc;
  final bool enabled;

  static Key cardKeyFor(String roomId) =>
      ValueKey('distributionRoomGroup-$roomId');

  static Key removeKeyFor(String lineId) =>
      ValueKey('distributionLineRemove-$lineId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: cardKeyFor(group.roomId),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${group.roomCode} · ${group.roomName}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (group.roomIsHistorical)
                    HistoricalMasterBadge.inactive(detail: 'Ruangan'),
                ],
              ),
              Text(
                '${group.itemCount} barang · ${group.lineCount} baris',
                style: theme.textTheme.bodySmall,
              ),
              const Divider(),
              for (final line in group.lines) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.itemName, style: theme.textTheme.bodySmall),
                          Text(
                            '${line.sku} · '
                            '${line.qty.formatWithUnit(line.unit)}'
                            '${line.batchNo == null ? '' : ' · ${line.batchNo}'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (line.expiryDate != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: DistributionExpiryBadge(
                                expiryDate: line.expiryDate!,
                                expiryAlertDays: line.expiryAlertDays,
                                nowUtc: nowUtc,
                              ),
                            ),
                          if (line.hasFefoOverride)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: DistributionFefoOverrideBadge(
                                reason: line.fefoOverrideReason!,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: removeKeyFor(line.id),
                      tooltip: 'Hapus baris',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: enabled
                          ? () async {
                              final ok = await ref
                                  .read(
                                    distributionEditorControllerProvider
                                        .notifier,
                                  )
                                  .removeLine(
                                    distributionId: distributionId,
                                    lineId: line.id,
                                  );
                              if (!context.mounted || ok) return;
                              final error = ref
                                  .read(distributionEditorControllerProvider)
                                  .error;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    describeFailure(
                                      error ?? 'Gagal menghapus baris.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                  ],
                ),
                const Divider(height: 1),
              ],
              const SizedBox(height: AppSpacing.sm),
              DistributionUnitTotals(totals: group.totalsByUnit),
            ],
          ),
        ),
      ),
    );
  }
}
