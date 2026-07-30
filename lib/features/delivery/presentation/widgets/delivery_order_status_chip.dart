import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';

/// Document status chip with the palette fixed by the specification (§4.3):
/// Preparing grey-blue (a working draft), Shipped orange (in transit), Received
/// green (final).
class DeliveryOrderStatusChip extends StatelessWidget {
  const DeliveryOrderStatusChip({
    super.key,
    required this.status,
    this.compact = true,
  });

  final DeliveryOrderStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      DeliveryOrderStatus.preparing => (
        Colors.blueGrey,
        Icons.inventory_2_outlined,
      ),
      DeliveryOrderStatus.shipped => (
        AppColors.warning,
        Icons.local_shipping_outlined,
      ),
      DeliveryOrderStatus.received => (
        AppColors.success,
        Icons.check_circle_outline,
      ),
    };

    return Container(
      key: ValueKey('deliveryStatusChip-${status.dbValue}'),
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
/// branch head looking at `shipped` needs to be told that the next step is theirs
/// — and that it is not available yet.
class DeliveryOrderStatusNote extends StatelessWidget {
  const DeliveryOrderStatusNote({super.key, required this.status});

  final DeliveryOrderStatus status;

  /// The sentence a branch head reads for a shipment awaiting their check.
  ///
  /// A constant so the widget test can assert it without matching prose it
  /// re-typed, and so Good Receipt can reuse the wording when it lands.
  static const String awaitingGoodReceipt = 'Menunggu pemeriksaan Good Receipt';

  static String messageFor(DeliveryOrderStatus status) => switch (status) {
    DeliveryOrderStatus.preparing =>
      'Surat Jalan masih disiapkan Warehouse. Cabang belum dapat melihat '
          'pengiriman ini.',
    DeliveryOrderStatus.shipped => awaitingGoodReceipt,
    DeliveryOrderStatus.received =>
      'Barang sudah diterima cabang melalui Good Receipt.',
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
