import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/widgets/status_card.dart';
import '../providers/good_receipt_providers.dart';

/// `Mulai Pemeriksaan` — creates the Good Receipt for one shipment, then hands over to
/// the checklist (§30/§31, G-G1).
///
/// A page of its own rather than a button that navigates, for two reasons:
///
/// * creating the receipt is a **write**, and a write that happens during a route
///   transition has nowhere to show a failure. Here it does — an ambiguous branch store,
///   a shipment somebody else already started, a missing master row all render as a
///   sentence with a way back;
/// * the receipt's id is not known until the write returns, so the checklist route
///   cannot be built until it does.
///
/// The write runs once, from `initState`, and the controller's in-flight state is the
/// double-tap guard. Should two attempts race anyway, the unique index on
/// `good_receipts.do_id` lets exactly one through and the loser lands on the sentence
/// telling them to continue the receipt that exists.
class GoodReceiptStartPage extends ConsumerStatefulWidget {
  const GoodReceiptStartPage({super.key, required this.deliveryOrderId});

  final String deliveryOrderId;

  static const Key progressKey = ValueKey('goodReceiptStartProgress');
  static const Key errorKey = ValueKey('goodReceiptStartError');
  static const Key backKey = ValueKey('goodReceiptStartBack');

  @override
  ConsumerState<GoodReceiptStartPage> createState() =>
      _GoodReceiptStartPageState();
}

class _GoodReceiptStartPageState extends ConsumerState<GoodReceiptStartPage> {
  @override
  void initState() {
    super.initState();
    // After the first frame: `create` writes to a provider, and mutating provider state
    // during a build is what Riverpod refuses.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final grId = await ref
        .read(createGoodReceiptControllerProvider.notifier)
        .create(deliveryOrderId: widget.deliveryOrderId);
    if (!mounted || grId == null) return;

    // `pushReplacementNamed`, so the back gesture returns to the Penerimaan list rather
    // than to a page that would create a second receipt.
    context.pushReplacementNamed(
      AppRoutes.receiptDetailName,
      pathParameters: {'id': grId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createGoodReceiptControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mulai Pemeriksaan')),
      body: state.hasError
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ErrorNotice(
                    key: GoodReceiptStartPage.errorKey,
                    message: describeFailure(state.error!),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    key: GoodReceiptStartPage.backKey,
                    onPressed: () => context.pop(),
                    child: const Text('Kembali ke Penerimaan'),
                  ),
                ],
              ),
            )
          : const Center(
              key: GoodReceiptStartPage.progressKey,
              child: CircularProgressIndicator(),
            ),
    );
  }
}
