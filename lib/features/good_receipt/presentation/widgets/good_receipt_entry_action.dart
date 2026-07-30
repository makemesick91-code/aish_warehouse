import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../providers/good_receipt_providers.dart';

/// Good Receipt's entry point on a shipment's detail screen (§28).
///
/// Lives in the Good Receipt feature rather than in the Delivery Order one, so the
/// knowledge of *when a receipt may be started, and where that route is* stays in one
/// place. The delivery screen only decides that this is a branch head looking at a
/// shipment that has been sent; everything about the receipt is answered here.
///
/// Which sentence appears depends on whether a receipt already exists — *Terima Barang*
/// creates one, *Lanjutkan Pemeriksaan* opens the one already open. The answer comes
/// from [branchReceiptForDeliveryProvider], which is derived from the branch-scoped
/// awaiting queue, so it cannot report on a shipment the acting branch may not see.
///
/// Both destinations go through their own route guards. This widget is an affordance,
/// never an authorization: a branch head who reaches the route another way still has the
/// guard, the scoped provider and the use case's own checks in front of them.
class GoodReceiptEntryAction extends ConsumerWidget {
  const GoodReceiptEntryAction({super.key, required this.deliveryOrderId});

  final String deliveryOrderId;

  static const Key actionKey = ValueKey('deliveryReceiveAction');

  /// The two labels, as constants so a widget test can assert them without retyping
  /// prose.
  static const String startLabel = 'Terima Barang';
  static const String resumeLabel = 'Lanjutkan Pemeriksaan';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final awaiting = ref.watch(
      branchReceiptForDeliveryProvider(deliveryOrderId),
    );
    // Absent from the awaiting queue means the shipment is not this branch's to receive,
    // or has already been received. Rendering nothing is the honest answer — a button
    // whose route would refuse is worse than no button.
    if (awaiting == null) return const SizedBox.shrink();

    final started = awaiting.hasReceipt;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: actionKey,
          onPressed: () {
            if (started) {
              context.pushNamed(
                AppRoutes.receiptDetailName,
                pathParameters: {'id': awaiting.receiptId!},
              );
            } else {
              context.pushNamed(
                AppRoutes.receiptNewName,
                pathParameters: {'deliveryOrderId': deliveryOrderId},
              );
            }
          },
          icon: Icon(started ? Icons.fact_check_outlined : Icons.inventory),
          label: Text(started ? resumeLabel : startLabel),
        ),
      ),
    );
  }
}
