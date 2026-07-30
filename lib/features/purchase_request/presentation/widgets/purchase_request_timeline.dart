import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/purchase_request_models.dart';

/// Who did what, and when (spec §4.3 DocTimeline, G-A3).
///
/// Every timestamp is a UTC instant converted to GMT+8 for display, with the zone
/// spelled out so nobody reads it as device time (T-2). `toLocal()` is never
/// called anywhere on this path.
///
/// The shape of the timeline follows the *outcome* rather than the state machine,
/// because a document that was withdrawn or refused did not simply stop partway —
/// it ended somewhere else. So a cancelled request shows Created → Sent →
/// Cancelled and never a greyed-out "waiting for warehouse" step it will never
/// reach, and a rejected one shows the rejection instead of the shipment.
class PurchaseRequestTimeline extends StatelessWidget {
  const PurchaseRequestTimeline({super.key, required this.summary});

  final PurchaseRequestSummary summary;

  @override
  Widget build(BuildContext context) {
    final request = summary.request;
    final steps = <Widget>[
      _Step(
        icon: Icons.edit_note,
        title: 'Dibuat',
        actor: summary.requestedByName,
        timestamp: request.createdAt,
        done: true,
      ),
      _Step(
        icon: Icons.send,
        title: 'Dikirim ke Warehouse',
        actor: summary.requestedByName,
        timestamp: request.submittedAt,
        done: request.submittedAt != null,
        pendingLabel: 'Belum dikirim',
        isLast: request.isDraft,
      ),
    ];

    if (request.isCancelled) {
      steps.add(
        _Step(
          icon: Icons.cancel,
          title: 'Dibatalkan',
          actor: summary.cancelledByName,
          timestamp: request.cancelledAt,
          done: true,
          detail: request.cancelReason,
          isLast: true,
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps,
      );
    }

    if (!request.isDraft) {
      steps.add(
        _Step(
          icon: Icons.inventory_2_outlined,
          title: 'Diproses Warehouse',
          actor: summary.processedByName,
          timestamp: request.processingAt,
          done: request.processingAt != null,
          pendingLabel: 'Menunggu diproses Warehouse',
          isLast: request.isSubmitted,
        ),
      );
    }

    if (request.isRejected) {
      steps.add(
        _Step(
          icon: Icons.block,
          title: 'Ditolak Warehouse',
          actor: summary.rejectedByName,
          timestamp: request.rejectedAt,
          done: true,
          detail: request.rejectReason,
          isLast: true,
        ),
      );
    } else if (request.isProcessing || request.isShipped || request.isClosed) {
      // The two steps Delivery Order and Good Receipt will fill in. They are shown
      // as pending rather than hidden, so a branch head can see what still has to
      // happen — but nothing in this milestone can complete them.
      steps.addAll([
        _Step(
          icon: Icons.local_shipping_outlined,
          title: 'Barang dikirim',
          actor: null,
          timestamp: null,
          done: request.isShipped || request.isClosed,
          pendingLabel: 'Menunggu Surat Jalan dari Warehouse',
        ),
        _Step(
          icon: Icons.check_circle_outline,
          title: 'Selesai',
          actor: null,
          timestamp: null,
          done: request.isClosed,
          pendingLabel: 'Menunggu penerimaan barang di cabang',
          isLast: true,
        ),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: steps,
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.actor,
    required this.timestamp,
    required this.done,
    this.pendingLabel,
    this.detail,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String? actor;

  /// UTC instant, or `null` while this step has not happened.
  final DateTime? timestamp;
  final bool done;
  final String? pendingLabel;

  /// Free text belonging to the step, e.g. a rejection or cancellation reason.
  final String? detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = done ? AppColors.primary : theme.colorScheme.outline;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(icon, size: 18, color: color),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: color.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                      color: done ? null : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (done && timestamp != null)
                    Text(
                      '${actor ?? '—'} · '
                      '${AppDateTimeFormatter.dateTimeWithZone(timestamp!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Text(
                      pendingLabel ?? '—',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (detail != null && detail!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        detail!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pending-sync marker (G-Y1), kept beside the timeline so every detail screen
/// shows the same pair.
class PurchaseRequestSyncNote extends StatelessWidget {
  const PurchaseRequestSyncNote({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (status == SyncStatus.synced) return const SizedBox.shrink();

    return Text(
      status == SyncStatus.pending
          ? 'Perubahan tersimpan di perangkat dan menunggu sinkronisasi. '
                'Nomor dokumen final diberikan server saat tersinkron.'
          : 'Terjadi konflik sinkronisasi pada dokumen ini.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
