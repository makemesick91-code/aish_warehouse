import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';

/// Document status chip with the palette fixed by the specification (§4.3):
/// Draft grey, Submitted blue, Processing purple, Shipped orange,
/// Closed green, Rejected/Cancelled red.
class PurchaseRequestStatusChip extends StatelessWidget {
  const PurchaseRequestStatusChip({
    super.key,
    required this.status,
    this.compact = true,
  });

  final PurchaseRequestStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      PurchaseRequestStatus.draft => (Colors.blueGrey, Icons.edit_note),
      PurchaseRequestStatus.submitted => (AppColors.primary, Icons.send),
      PurchaseRequestStatus.processing => (
        Colors.deepPurple,
        Icons.inventory_2_outlined,
      ),
      PurchaseRequestStatus.shipped => (
        AppColors.warning,
        Icons.local_shipping_outlined,
      ),
      PurchaseRequestStatus.closed => (
        AppColors.success,
        Icons.check_circle_outline,
      ),
      PurchaseRequestStatus.rejected => (AppColors.danger, Icons.block),
      PurchaseRequestStatus.cancelled => (AppColors.danger, Icons.cancel),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            status.label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// The one-line explanation of what a status means for the reader right now.
///
/// Separate from the chip because the chip is a label and this is guidance: a
/// branch head looking at `submitted` needs to know that the ball is in the
/// warehouse's court, and that they can still withdraw the order (§24.4).
class PurchaseRequestStatusNote extends StatelessWidget {
  const PurchaseRequestStatusNote({super.key, required this.status});

  final PurchaseRequestStatus status;

  static String messageFor(PurchaseRequestStatus status) => switch (status) {
    PurchaseRequestStatus.draft =>
      'Draft belum dikirim. Warehouse belum dapat melihat permintaan ini.',
    PurchaseRequestStatus.submitted => 'Menunggu diproses Warehouse.',
    PurchaseRequestStatus.processing =>
      'Sedang diproses Warehouse. Permintaan tidak dapat dibatalkan lagi.',
    PurchaseRequestStatus.shipped =>
      'Barang sudah dikirim Warehouse dan menunggu penerimaan di cabang.',
    PurchaseRequestStatus.closed =>
      'Permintaan selesai. Seluruh barang sudah diterima.',
    PurchaseRequestStatus.rejected => 'Permintaan ditolak Warehouse.',
    PurchaseRequestStatus.cancelled => 'Permintaan dibatalkan Kepala Cabang.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            messageFor(status),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
