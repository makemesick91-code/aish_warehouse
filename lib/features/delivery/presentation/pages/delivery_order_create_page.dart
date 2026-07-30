import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../purchase_request/presentation/providers/purchase_request_providers.dart';
import '../providers/delivery_providers.dart';
import '../widgets/shipment_progress_bar.dart';

/// Buat Delivery Order — the step between a Purchase Request and a shipment
/// (§27.1, G-D1).
///
/// It exists as its own screen rather than as a button on the request detail
/// because it has something to show: what is still outstanding on every position
/// after the shipments already sent. A request whose every position is complete
/// offers no button at all, and says why (G-D2/G-D5).
///
/// Creating the document is deliberately the cheap step. It writes an **empty**
/// `preparing` header and — when the request was still `submitted` — moves it to
/// `processing` in the same transaction. Nothing is allocated and nothing is
/// posted; the allocation screen is next.
class DeliveryOrderCreatePage extends ConsumerWidget {
  const DeliveryOrderCreatePage({super.key, required this.purchaseRequestId});

  final String purchaseRequestId;

  static const Key createButtonKey = ValueKey('deliveryCreateButton');
  static const Key completeNoticeKey = ValueKey('deliveryCreateCompleteNotice');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detail = ref.watch(
      warehousePurchaseRequestDetailProvider(purchaseRequestId),
    );
    final progress = ref.watch(
      purchaseRequestShipmentProgressProvider(purchaseRequestId),
    );
    final controller = ref.watch(createDeliveryOrderControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Buat Delivery Order')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ErrorNotice(message: describeFailure(error)),
        ),
        data: (request) {
          if (request == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text('Purchase Request tidak ditemukan.'),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.summary.docNumber,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${request.summary.branchCode} · '
                          '${request.summary.branchName}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          'Diminta ${request.summary.requestedByName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Status ${request.status.label}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              progress.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: ErrorNotice(message: describeFailure(error)),
                ),
                data: (rows) {
                  final outstanding = rows
                      .where(
                        (entry) => entry.remainingBeforeCurrentDo.isPositive,
                      )
                      .toList(growable: false);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Text(
                          'Sisa yang belum dikirim',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final entry in rows)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            0,
                            AppSpacing.md,
                            AppSpacing.sm,
                          ),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.itemName,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    entry.sku,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  ShipmentProgressBar(progress: entry),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (outstanding.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Card(
                            key: DeliveryOrderCreatePage.completeNoticeKey,
                            child: Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'Seluruh barang pada Purchase Request ini sudah '
                                'terkirim penuh. Tidak ada Surat Jalan baru '
                                'yang perlu dibuat.',
                              ),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: FilledButton.icon(
                            key: DeliveryOrderCreatePage.createButtonKey,
                            // The in-flight guard is the double-tap guard: two
                            // taps must not produce two documents against the
                            // same request.
                            onPressed: controller.isLoading
                                ? null
                                : () => _create(context, ref),
                            icon: const Icon(Icons.local_shipping_outlined),
                            label: const Text('Buat Delivery Order'),
                          ),
                        ),
                      if (controller.hasError)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: ErrorNotice(
                            message: describeFailure(controller.error ?? ''),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final doId = await ref
        .read(createDeliveryOrderControllerProvider.notifier)
        .create(purchaseRequestId: purchaseRequestId);
    if (doId == null || !context.mounted) return;

    context.pushReplacementNamed(
      AppRoutes.warehouseDeliveryOrderEditName,
      pathParameters: {'id': doId},
    );
  }
}
