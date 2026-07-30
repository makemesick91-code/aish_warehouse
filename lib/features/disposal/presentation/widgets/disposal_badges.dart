import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/services/disposal_expiry_policy.dart';

/// The small labelled pill every badge on these screens is made of.
///
/// One widget rather than five near-identical `Container`s, because the padding,
/// radius and alpha values were being retyped per badge on the earlier screens and
/// had already drifted apart.
class DisposalPill extends StatelessWidget {
  const DisposalPill({
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
/// The labels come from [DisposalStatus.label], which deliberately says *Sudah
/// Diposting* rather than *Disetujui*: there is no approval stage in this workflow,
/// and wording that implied one would describe a document that does not exist.
class DisposalStatusChip extends StatelessWidget {
  const DisposalStatusChip({super.key, required this.status});

  final DisposalStatus status;

  static Key keyFor(DisposalStatus status) =>
      ValueKey('disposalStatusChip-${status.dbValue}');

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      DisposalStatus.draft => (AppColors.warning, Icons.edit_note),
      DisposalStatus.posted => (AppColors.success, Icons.check_circle_outline),
    };

    return DisposalPill(
      pillKey: keyFor(status),
      label: status.label,
      color: color,
      icon: icon,
    );
  }
}

/// Expiry indicator for one batch on a Pemusnahan screen (G-E6).
///
/// Three states, and the difference between the first two is what the whole
/// milestone turns on:
///
/// * **red — kedaluwarsa**: past its date, and therefore destroyable. It says how
///   many days ago, because *"lewat 40 hari"* is the number that decides which of
///   twelve expired batches to deal with first.
/// * **orange — segera kedaluwarsa**: inside the item's alert window and **not**
///   selectable. §28 is explicit that near-expiry stock may be shown as information
///   and never offered as a candidate, so this badge appears only in the
///   informational section.
/// * **grey**: comfortably in date.
///
/// The verdict comes from [DisposalExpiryPolicy] rather than being decided here, so
/// the badge and the refusal a use case produces can never disagree about which
/// batch is past its date. In particular, a batch expiring *today* renders grey and
/// not red — which is exactly the answer the use case gives (T-10).
class DisposalExpiryBadge extends StatelessWidget {
  const DisposalExpiryBadge({
    super.key,
    required this.expiryDate,
    required this.expiryAlertDays,
    required this.nowUtc,
  });

  /// Civil date — never timezone converted (T-9).
  final DateTime expiryDate;
  final int expiryAlertDays;

  /// UTC instant used as the reference "now" (T-7).
  final DateTime nowUtc;

  static const Key badgeKey = ValueKey('disposalExpiryBadge');
  static const Key expiredKey = ValueKey('disposalExpiredBadge');
  static const Key nearExpiryKey = ValueKey('disposalNearExpiryBadge');

  @override
  Widget build(BuildContext context) {
    final expired = DisposalExpiryPolicy.isExpired(
      expiryDate: expiryDate,
      nowUtc: nowUtc,
    );
    final nearExpiry = DisposalExpiryPolicy.isNearExpiry(
      expiryDate: expiryDate,
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
            '${DisposalExpiryPolicy.daysExpired(expiryDate: expiryDate, nowUtc: nowUtc)} '
            'hari',
        expiredKey,
      ),
      (false, true) => (
        AppColors.warning,
        'Segera kedaluwarsa · '
            '${DisposalExpiryPolicy.remainingDays(expiryDate: expiryDate, nowUtc: nowUtc)} '
            'hari',
        nearExpiryKey,
      ),
      _ => (
        Colors.blueGrey,
        'ED ${AppDateTimeFormatter.civilDate(expiryDate)}',
        badgeKey,
      ),
    };

    return DisposalPill(pillKey: key, label: label, color: color);
  }
}

/// The banner the informational near-expiry section carries.
///
/// It exists to answer the question the section provokes — *"why can I not select
/// these?"* — in the place the question is asked, rather than leaving the user to
/// discover it by tapping.
class DisposalNearExpiryNotice extends StatelessWidget {
  const DisposalNearExpiryNotice({super.key});

  static const Key noticeKey = ValueKey('disposalNearExpiryNotice');

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
          Expanded(
            child: Text(
              'Barang berikut belum kedaluwarsa dan tidak dapat dimusnahkan. '
              'Gunakan lebih dahulu sebelum tanggal kedaluwarsanya.',
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
/// shape, kept beside the badges so the two Pemusnahan screens and the picker word
/// their empty and refused states identically.
class DisposalNotice extends StatelessWidget {
  const DisposalNotice({
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
/// Worded around what actually happens — the stock leaves and nothing receives it —
/// because *"tidak dapat dibatalkan"* on its own reads like every other confirmation
/// dialog, and this one is the only irreversible action in the application with no
/// counter-entry anywhere.
class DisposalFinalityNotice extends StatelessWidget {
  const DisposalFinalityNotice({super.key});

  static const Key noticeKey = ValueKey('disposalFinalityNotice');

  /// The exact sentence §31 asks the dialog to use. A constant rather than a
  /// literal, so the dialog, the header and the tests all quote the same words.
  static const String message =
      'Barang akan dikeluarkan dari stok sebagai pemusnahan. '
      'Tindakan ini tidak dapat diedit setelah diposting.';

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
            Icons.delete_forever_outlined,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
