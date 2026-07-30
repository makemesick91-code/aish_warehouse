import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../domain/services/goods_return_access_policy.dart';
import '../providers/goods_return_providers.dart';

/// *"What happened to the return for this rejection?"*, as a chip (§33).
///
/// Rendered on the Warehouse's Good Receipt discrepancy queue, and only against a
/// **rejected** line. That restriction is the point of the whole integration: a
/// `checked` line that arrived short is a *shortage* — a quantity that never left the
/// Warehouse — so there is no box coming back and no document whose status could be
/// shown. Those rows keep reading *Kekurangan* and carry no chip, no link and no
/// *Buat Retur* button anywhere in this application (§16.10/§33).
///
/// ### What it shows, and what it deliberately does not
///
/// Four states — *Retur belum dibuat*, *Draft*, *Dikirim*, *Diterima* — plus the
/// document number once one exists. That is a **status**, not content: a Warehouse user
/// already sees every branch's discrepancies on this screen (§4.2), and what they must
/// not get from it is the inside of a branch's draft. Tapping through is offered only
/// for the two statuses the Warehouse is scoped to open; a draft's chip is inert,
/// because the route behind it would refuse anyway and a link that always fails is
/// worse than no link.
class GoodsReturnLinkChip extends ConsumerWidget {
  const GoodsReturnLinkChip({
    super.key,
    required this.grId,
    required this.lineId,
  });

  /// The Good Receipt the rejection belongs to — the key a return is found by.
  final String grId;

  /// Only used to key the widget, so two rejections of one receipt render distinctly.
  final String lineId;

  static Key keyFor(String lineId) => ValueKey('goodsReturnLinkChip-$lineId');

  static const String notCreatedLabel = 'Retur belum dibuat';

  static String labelFor(GoodsReturnStatus? status) => switch (status) {
    null => notCreatedLabel,
    GoodsReturnStatus.draft => 'Retur: Draft',
    GoodsReturnStatus.shipped => 'Retur: Dikirim',
    GoodsReturnStatus.received => 'Retur: Diterima',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(goodsReturnStatusByReceiptProvider(grId)).value;
    final status = document?.status;

    final color = switch (status) {
      null => AppColors.warning,
      GoodsReturnStatus.draft => AppColors.warning,
      GoodsReturnStatus.shipped => AppColors.primary,
      GoodsReturnStatus.received => AppColors.success,
    };

    // Only the two statuses the Warehouse scope admits are openable — see the class
    // note. A draft's chip renders the status and goes nowhere.
    final canOpen =
        document != null &&
        GoodsReturnAccessPolicy.warehouseVisibleStatuses.contains(status) &&
        GoodsReturnAccessPolicy.canReceive(ref.watch(actingRoleProvider));

    final chip = Container(
      key: keyFor(lineId),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_return_outlined, size: 14, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            document == null
                ? labelFor(status)
                : '${labelFor(status)} · ${document.docNumber}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (canOpen) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right, size: 14, color: color),
          ],
        ],
      ),
    );

    if (!canOpen) return chip;
    return InkWell(
      onTap: () => context.pushNamed(
        AppRoutes.warehouseReturnDetailName,
        pathParameters: {'id': document.id},
      ),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: chip,
    );
  }
}
