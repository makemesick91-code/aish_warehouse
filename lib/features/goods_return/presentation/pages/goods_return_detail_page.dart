import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../domain/models/goods_return_models.dart';
import '../providers/goods_return_providers.dart';
import '../widgets/goods_return_badges.dart';

/// One Retur, seen by the branch that raised it (§30).
///
/// The whole screen is a **read**, with exactly two affordances on a draft: the note
/// field and *Kirim Retur*. There is no quantity input, no item picker, no batch
/// picker, no *Tambah Baris* and no *Hapus Baris* — and their absence is the document's
/// definition rather than a simplification (§18/§30). A return says *"here is exactly
/// what you sent that we refused"*; a screen that could edit it would be a screen that
/// makes a different claim.
///
/// ### Why the ship dialog spells out that nothing moves
///
/// Because the intuition is the other way round. Pressing a button labelled *Kirim*
/// looks like it should change a balance, and it does not: the goods were never in the
/// branch's stock (G-G5 credits `checked` lines only) and the Warehouse must not be
/// credited until somebody has counted the box in (§20). A branch head who believes the
/// Warehouse balance has already gone up is a branch head who will be surprised later,
/// so the confirmation says so in words.
class GoodsReturnDetailPage extends ConsumerStatefulWidget {
  const GoodsReturnDetailPage({super.key, required this.goodsReturnId});

  final String goodsReturnId;

  static const Key linesKey = ValueKey('goodsReturnDetailLines');
  static const Key noteFieldKey = ValueKey('goodsReturnDetailNote');
  static const Key shipButtonKey = ValueKey('goodsReturnDetailShip');
  static const Key shipConfirmKey = ValueKey('goodsReturnDetailShipConfirm');
  static const Key readOnlyKey = ValueKey('goodsReturnDetailReadOnly');
  static const Key missingKey = ValueKey('goodsReturnDetailMissing');

  static Key lineKey(String lineId) => ValueKey('goodsReturnLine-$lineId');

  @override
  ConsumerState<GoodsReturnDetailPage> createState() =>
      _GoodsReturnDetailPageState();
}

class _GoodsReturnDetailPageState extends ConsumerState<GoodsReturnDetailPage> {
  final TextEditingController _note = TextEditingController();
  bool _noteSeeded = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final text = _note.text.trim();
    final result = await ref
        .read(goodsReturnActionsProvider.notifier)
        .updateNote(
          goodsReturnId: widget.goodsReturnId,
          note: text.isEmpty ? null : text,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? 'Catatan tersimpan.'
              : result.errorMessage ?? 'Catatan gagal disimpan.',
        ),
      ),
    );
  }

  Future<void> _ship(GoodsReturnDetail detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kirim Retur?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${detail.lineCount} posisi · '
              '${GoodsReturnQuantitySummary.format(detail.totalQuantityByUnit)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Barang fisik akan ditandai telah dikirim ke Warehouse Pusat.\n\n'
              'Saldo Gudang Cabang tidak berubah karena barang rejected belum '
              'pernah masuk ke stok cabang.\n\n'
              'Saldo Warehouse baru bertambah setelah Warehouse mengonfirmasi '
              'penerimaan.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: GoodsReturnDetailPage.shipConfirmKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kirim Retur'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(goodsReturnActionsProvider.notifier)
        .ship(widget.goodsReturnId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isSuccess
              ? 'Retur ditandai dikirim ke Warehouse.'
              : result.errorMessage ?? 'Retur gagal dikirim.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(
      branchGoodsReturnDetailProvider(widget.goodsReturnId),
    );
    final nowUtc = ref.watch(goodsReturnClockProvider)();
    final busy = ref.watch(goodsReturnActionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Retur')),
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
                key: GoodsReturnDetailPage.missingKey,
                title: 'Dokumen tidak tersedia',
                message:
                    'Dokumen retur ini tidak ditemukan atau berada di cabang '
                    'lain.',
                icon: Icons.lock_outline,
              ),
            );
          }
          if (!_noteSeeded) {
            _note.text = value.goodsReturn.note ?? '';
            _noteSeeded = true;
          }
          return _Body(
            detail: value,
            nowUtc: nowUtc,
            busy: busy,
            noteController: _note,
            onSaveNote: _saveNote,
            onShip: () => _ship(value),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.detail,
    required this.nowUtc,
    required this.busy,
    required this.noteController,
    required this.onSaveNote,
    required this.onShip,
  });

  final GoodsReturnDetail detail;
  final DateTime nowUtc;
  final bool busy;
  final TextEditingController noteController;
  final Future<void> Function() onSaveNote;
  final VoidCallback onShip;

  @override
  Widget build(BuildContext context) {
    final document = detail.goodsReturn;
    final summary = detail.summary;

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
        Text(summary.progressLabel),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Fact(label: 'Cabang', value: summary.branchLabel),
                _Fact(label: 'Penerimaan Barang', value: summary.grDocNumber),
                _Fact(label: 'Surat Jalan', value: summary.doDocNumber),
                _Fact(label: 'Purchase Request', value: summary.prDocNumber),
                _Fact(label: 'Dibuat oleh', value: summary.createdByName),
                _Fact(
                  label: 'Dibuat',
                  value: AppDateTimeFormatter.dateTimeWithZone(
                    document.createdAt,
                  ),
                ),
                if (document.shippedAt != null)
                  _Fact(
                    label: 'Dikirim',
                    value:
                        '${AppDateTimeFormatter.dateTimeWithZone(document.shippedAt!)}'
                        '${summary.shippedByName == null ? '' : ' · ${summary.shippedByName}'}',
                  ),
                if (document.receivedAt != null)
                  _Fact(
                    label: 'Diterima Warehouse',
                    value:
                        '${AppDateTimeFormatter.dateTimeWithZone(document.receivedAt!)}'
                        '${summary.receivedByName == null ? '' : ' · ${summary.receivedByName}'}',
                  ),
                if (document.hasWarehouseNote)
                  _Fact(
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
        if (document.isDraft) ...[
          TextField(
            key: GoodsReturnDetailPage.noteFieldKey,
            controller: noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan cabang (opsional)',
              helperText: 'Misalnya cara pengiriman atau nama kurir.',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: busy ? null : onSaveNote,
              child: const Text('Simpan catatan'),
            ),
          ),
        ] else if (document.hasNote)
          Card(
            child: ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Catatan cabang'),
              subtitle: Text(document.note!),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Barang yang diretur',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        // The read-only notice sits above the lines rather than below them, so it is
        // read before the quantities it explains.
        const _ImmutabilityNotice(),
        const SizedBox(height: AppSpacing.sm),
        Column(
          key: GoodsReturnDetailPage.linesKey,
          children: [
            for (final line in detail.lines)
              GoodsReturnLineTile(line: line, nowUtc: nowUtc),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (detail.canShip)
          FilledButton.icon(
            key: GoodsReturnDetailPage.shipButtonKey,
            onPressed: busy ? null : onShip,
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Kirim Retur'),
          )
        else
          GoodsReturnNotice(
            key: GoodsReturnDetailPage.readOnlyKey,
            title: document.isReceived
                ? 'Retur sudah diterima Warehouse'
                : 'Retur sedang dalam perjalanan',
            message: document.isReceived
                ? 'Dokumen ini final. Koreksi dilakukan lewat dokumen baru, '
                      'bukan dengan mengubah dokumen ini.'
                : 'Menunggu Warehouse mengonfirmasi penerimaan. Saldo '
                      'Warehouse belum bertambah sampai konfirmasi itu '
                      'dilakukan.',
            icon: document.isReceived
                ? Icons.verified_outlined
                : Icons.schedule,
          ),
      ],
    );
  }
}

/// Why nothing on this screen can be edited (§18/§30).
class _ImmutabilityNotice extends StatelessWidget {
  const _ImmutabilityNotice();

  static const Key noticeKey = ValueKey('goodsReturnImmutabilityNotice');

  @override
  Widget build(BuildContext context) => const GoodsReturnNotice(
    key: noticeKey,
    title: 'Isi retur mengikuti Penerimaan Barang',
    message:
        'Seluruh barang yang ditolak pada Penerimaan Barang ikut diretur, '
        'dengan kuantitas dan alasan yang sama persis. Kuantitas, barang, '
        'batch dan alasan tidak dapat diubah, dan baris tidak dapat ditambah '
        'atau dihapus.',
    icon: Icons.lock_outline,
  );
}

/// One immutable returned position, shared by both detail screens.
class GoodsReturnLineTile extends StatelessWidget {
  const GoodsReturnLineTile({
    super.key,
    required this.line,
    required this.nowUtc,
  });

  final GoodsReturnLine line;
  final DateTime nowUtc;

  static Key qtyKeyFor(String lineId) => ValueKey('goodsReturnLineQty-$lineId');
  static Key reasonKeyFor(String lineId) =>
      ValueKey('goodsReturnLineReason-$lineId');

  @override
  Widget build(BuildContext context) {
    return Card(
      key: GoodsReturnDetailPage.lineKey(line.id),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.itemName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        line.sku,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${line.qty.format()} ${line.unit}',
                  key: qtyKeyFor(line.id),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            if (line.isBatched) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Batch ${line.batchNo ?? '—'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            GoodsReturnExpiryBadge(line: line, nowUtc: nowUtc),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Alasan ditolak: ${line.rejectReason}',
              key: reasonKeyFor(line.id),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (line.usesHistoricalMaster) ...[
              const SizedBox(height: AppSpacing.xs),
              const HistoricalMasterBadge.historical(
                detail: 'Barang atau batch sudah tidak aktif.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

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

/// `/returns/new/{goodReceiptId}` — the deep-link landing for raising a return (§30).
///
/// The list's *Buat Retur* button creates in one tap and replaces straight into the
/// detail; this page exists so a link, a bookmark or a back-navigation has somewhere to
/// land, and so the section guard has a `branchCreate` kind to refuse. It shows what
/// would be snapshotted and offers the same single action.
class GoodsReturnCreatePage extends ConsumerWidget {
  const GoodsReturnCreatePage({super.key, required this.goodReceiptId});

  final String goodReceiptId;

  static const Key createButtonKey = ValueKey('goodsReturnCreatePageButton');
  static const Key previewKey = ValueKey('goodsReturnCreatePreview');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibility = ref.watch(
      goodsReturnEligibilityByReceiptProvider(goodReceiptId),
    );
    final nowUtc = ref.watch(goodsReturnClockProvider)();
    final busy = ref.watch(goodsReturnActionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Buat Retur')),
      body: eligibility.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
        data: (row) {
          if (row == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: GoodsReturnNotice(
                title: 'Dokumen tidak tersedia',
                message:
                    'Penerimaan Barang ini tidak ditemukan atau berada di '
                    'cabang lain.',
                icon: Icons.lock_outline,
              ),
            );
          }
          if (!row.canCreateReturn) {
            final existing = row.existingReturnId;
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GoodsReturnNotice(
                    title: row.hasReturn
                        ? 'Retur sudah dibuat'
                        : 'Tidak ada barang yang perlu diretur',
                    message: row.hasReturn
                        ? 'Penerimaan Barang ini sudah memiliki dokumen '
                              '${row.existingReturnDocNumber ?? 'retur'}.'
                        : 'Penerimaan Barang ini tidak memuat barang yang '
                              'ditolak.',
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => context.pushReplacementNamed(
                        AppRoutes.returnDetailName,
                        pathParameters: {'id': existing},
                      ),
                      child: const Text('Lihat Retur'),
                    ),
                  ],
                ],
              ),
            );
          }
          return ListView(
            key: previewKey,
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'GR ${row.grDocNumber}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('SJ ${row.doDocNumber} · PR ${row.prDocNumber}'),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${row.rejectedLineCount} barang ditolak · '
                '${GoodsReturnQuantitySummary.format(row.totalQuantityByUnit)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final position in row.positions)
                Card(
                  child: ListTile(
                    title: Text('${position.itemName} (${position.sku})'),
                    subtitle: Text(
                      [
                        '${position.returnQty.format()} ${position.unit}',
                        if (position.isBatched)
                          'Batch ${position.batchNo ?? '—'}',
                        position.rejectReason,
                      ].join(' · '),
                    ),
                    trailing: position.isExpired(nowUtc)
                        ? const Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.danger,
                          )
                        : position.isNearExpiry(nowUtc)
                        ? const Icon(Icons.schedule, color: AppColors.warning)
                        : null,
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                key: createButtonKey,
                onPressed: busy
                    ? null
                    : () async {
                        final result = await ref
                            .read(goodsReturnActionsProvider.notifier)
                            .create(goodReceiptId: goodReceiptId);
                        if (!context.mounted) return;
                        if (result.isSuccess) {
                          context.pushReplacementNamed(
                            AppRoutes.returnDetailName,
                            pathParameters: {'id': result.documentId!},
                          );
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result.errorMessage ?? 'Retur gagal dibuat.',
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.assignment_return_outlined),
                label: const Text('Buat Retur'),
              ),
            ],
          );
        },
      ),
    );
  }
}
