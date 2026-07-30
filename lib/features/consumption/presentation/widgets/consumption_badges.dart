import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/services/consumption_expiry_policy.dart';

/// The small labelled pill every badge on these screens is made of.
///
/// One widget rather than five near-identical `Container`s, because the padding, radius
/// and alpha values were being retyped per badge on the earlier screens and had already
/// drifted apart.
class ConsumptionPill extends StatelessWidget {
  const ConsumptionPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.pillKey,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Lets a test address the badge without matching on prose.
  final Key? pillKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: pillKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
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
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Document status chip: `draft` orange (work in progress), `posted` green (final).
///
/// The labels come from [ConsumptionStatus.label], which deliberately says *Sudah
/// Diposting* rather than *Disetujui*: there is no approval stage in this workflow (§7),
/// and wording that implied one would describe a document that does not exist.
class ConsumptionStatusChip extends StatelessWidget {
  const ConsumptionStatusChip({super.key, required this.status});

  final ConsumptionStatus status;

  static Key keyFor(ConsumptionStatus status) =>
      ValueKey('consumptionStatusChip-${status.dbValue}');

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      ConsumptionStatus.draft => (AppColors.warning, Icons.edit_note),
      ConsumptionStatus.posted => (
        AppColors.success,
        Icons.check_circle_outline,
      ),
    };

    return ConsumptionPill(
      pillKey: keyFor(status),
      label: status.label,
      color: color,
      icon: icon,
    );
  }
}

/// Expiry indicator for one position on a Pemakaian screen (G-E6).
///
/// Four states, and the difference between the first two is what this milestone turns
/// on:
///
/// * **red — kedaluwarsa**: past its date, and therefore *not* consumable. It appears
///   only where the screen is *reporting* stock (the room-stock summary and the
///   dashboard), never in the picker: the candidate query cannot return an expired
///   position at all, so a red badge there would be unreachable. It says how many days
///   ago, because that is the number that decides how urgently somebody needs to file a
///   Pemusnahan.
/// * **orange — segera kedaluwarsa**: inside the item's alert window and **fully
///   selectable**. This is the opposite of the Pemusnahan screen's orange badge, and
///   deliberately: §17 says near-expiry stock is exactly what should be used next, so the
///   badge is an encouragement rather than a barrier — and no FEFO override reason is
///   asked for anywhere.
/// * **grey with a date**: comfortably in date.
/// * **nothing at all**: an item without an expiry date has no badge, because it has no
///   date to describe. Rendering a grey "ED —" pill would invent a fact.
///
/// The verdict comes from [ConsumptionExpiryPolicy] rather than being decided here, so
/// the badge and the refusal a use case produces can never disagree. In particular a
/// batch expiring *today* renders orange-or-grey and not red — which is exactly the
/// answer the use case gives (T-10).
class ConsumptionExpiryBadge extends StatelessWidget {
  const ConsumptionExpiryBadge({
    super.key,
    required this.expiryDate,
    required this.expiryAlertDays,
    required this.nowUtc,
  });

  /// Civil date — never timezone converted (T-9). `null` for an item without expiry.
  final DateTime? expiryDate;
  final int expiryAlertDays;

  /// UTC instant used as the reference "now" (T-7).
  final DateTime nowUtc;

  static const Key badgeKey = ValueKey('consumptionExpiryBadge');
  static const Key expiredKey = ValueKey('consumptionExpiredBadge');
  static const Key nearExpiryKey = ValueKey('consumptionNearExpiryBadge');

  @override
  Widget build(BuildContext context) {
    final expiry = expiryDate;
    // No date, no badge. An item without expiry is a legitimate consumption position
    // (G-E2), and inventing a pill for it would make the picker look inconsistent.
    if (expiry == null) return const SizedBox.shrink();

    final expired = ConsumptionExpiryPolicy.isExpired(
      expiryDate: expiry,
      nowUtc: nowUtc,
    );
    final nearExpiry = ConsumptionExpiryPolicy.isNearExpiry(
      expiryDate: expiry,
      expiryAlertDays: expiryAlertDays,
      nowUtc: nowUtc,
    );

    final (Color color, String label, Key key) = switch ((
      expired,
      nearExpiry,
    )) {
      (true, _) => (
        AppColors.danger,
        'Kedaluwarsa · lewat '
            '${ConsumptionExpiryPolicy.daysExpired(expiryDate: expiry, nowUtc: nowUtc)} '
            'hari',
        expiredKey,
      ),
      (false, true) => (
        AppColors.warning,
        'Segera kedaluwarsa · '
            '${ConsumptionExpiryPolicy.remainingDays(expiryDate: expiry, nowUtc: nowUtc)} '
            'hari',
        nearExpiryKey,
      ),
      _ => (
        Colors.blueGrey,
        'ED ${AppDateTimeFormatter.civilDate(expiry)}',
        badgeKey,
      ),
    };

    return ConsumptionPill(pillKey: key, label: label, color: color);
  }
}

/// The banner that explains the orange badges on the picker.
///
/// It exists to answer the question a row of orange pills provokes — *"should I be
/// avoiding these?"* — the opposite way round from the Pemusnahan screen's equivalent.
/// There the notice explains why near-expiry stock cannot be selected; here it explains
/// that it should be selected **first**.
class ConsumptionNearExpiryNotice extends StatelessWidget {
  const ConsumptionNearExpiryNotice({super.key});

  static const Key noticeKey = ValueKey('consumptionNearExpiryNotice');

  /// The exact sentence the picker and the form both show. A constant so the two cannot
  /// word it differently.
  static const String message =
      'Batch bertanda oranye segera kedaluwarsa. Gunakan lebih dahulu agar '
      'tidak terbuang.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: noticeKey,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// The notice a room's expired positions get on the stock summary.
///
/// A Pemakaian cannot remove them (G-E7), and a nurse looking at a red badge needs to
/// know what *does* — otherwise the screen reads as broken rather than as correct.
class ConsumptionExpiredNotice extends StatelessWidget {
  const ConsumptionExpiredNotice({super.key, required this.positionCount});

  final int positionCount;

  static const Key noticeKey = ValueKey('consumptionExpiredNotice');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: noticeKey,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block, size: 16, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$positionCount posisi di ruangan ini sudah kedaluwarsa dan tidak '
              'dapat dipakai. Laporkan ke Kepala Cabang untuk pemusnahan.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled message card, for the states a screen has to explain rather than list.
///
/// `StatusCard` is a *metric* — a big number over a label — and reaching for it here
/// produced cards whose headline was a sentence, which is neither. This is the other
/// shape, kept beside the badges so the Pemakaian screens and the picker word their empty
/// and refused states identically.
class ConsumptionNotice extends StatelessWidget {
  const ConsumptionNotice({
    super.key,
    required this.title,
    required this.message,
    this.icon,
  });

  final String title;
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(message, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The warning the posting dialog and the draft header carry.
///
/// The exact wording §29 asks for. Kept as a constant rather than as a literal so the
/// dialog, the header and the tests all quote the same words — and worded around what
/// actually happens, because *"tidak dapat dibatalkan"* on its own reads like every other
/// confirmation dialog while this one removes stock with nothing on the other side.
class ConsumptionFinalityNotice extends StatelessWidget {
  const ConsumptionFinalityNotice({super.key});

  static const Key noticeKey = ValueKey('consumptionFinalityNotice');

  /// §29's first sentence.
  static const String stockMessage =
      'Stok ruangan akan berkurang sesuai jumlah pemakaian.';

  /// §29's second sentence.
  static const String finalityMessage =
      'Tindakan ini tidak dapat diedit setelah diposting.';

  /// The sentence shown when the balance moved underneath the form (§29).
  static const String stockChangedMessage =
      'Stok ruangan berubah. Periksa kembali jumlah barang yang digunakan.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: noticeKey,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.local_fire_department_outlined,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(stockMessage, style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Text(finalityMessage, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
