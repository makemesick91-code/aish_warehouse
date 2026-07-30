import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/widgets/status_card.dart';
import '../providers/good_receipt_providers.dart';
import 'branch_good_receipt_list_page.dart';

/// Penerimaan Cabang — the warehouse's read-only view of posted Good Receipts, across
/// every branch (§4.2).
///
/// Read-only, structurally rather than by omission. There is no create route, no decide
/// route and no post route for a warehouse actor, the queries behind this page return
/// `posted` receipts only, and the repository offers no writer this screen could reach.
/// Spec §3.1 marks *"Good Receipt (ceklis/tolak)"* for `kepala_cabang` alone.
///
/// A `checking` receipt is deliberately invisible here: it is a branch head part way
/// through a decision, and showing an intermediate state to the warehouse would raise a
/// return for goods that have not been refused yet.
class WarehouseGoodReceiptListPage extends ConsumerWidget {
  const WarehouseGoodReceiptListPage({super.key});

  static const Key listKey = ValueKey('warehouseGoodReceiptList');
  static const Key emptyKey = ValueKey('warehouseGoodReceiptEmpty');
  static const Key searchKey = ValueKey('warehouseGoodReceiptSearch');
  static const Key discrepancyLinkKey = ValueKey(
    'warehouseGoodReceiptDiscrepancyLink',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(warehouseGoodReceiptListProvider(null));
    final overdue = ref.watch(warehouseOverdueRemindersProvider(null));
    final nowUtc = ref.watch(goodReceiptClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Penerimaan Cabang')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(warehouseGoodReceiptListProvider(null)),
        child: ListView(
          key: listKey,
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                key: searchKey,
                onChanged: ref
                    .read(warehouseGoodReceiptSearchProvider.notifier)
                    .update,
                decoration: const InputDecoration(
                  labelText: 'Cari nomor GR / SJ / PR / cabang / barang',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: OutlinedButton.icon(
                key: discrepancyLinkKey,
                onPressed: () => context.pushNamed(
                  AppRoutes.warehouseGoodReceiptDiscrepanciesName,
                ),
                icon: const Icon(Icons.rule_folder_outlined),
                label: const Text('Selisih GR dari Cabang'),
              ),
            ),
            if (overdue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.report_gmailerrorred,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${overdue.length} pengiriman belum diposting '
                            'cabang dalam batas 2×24 jam.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            receipts.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ErrorNotice(
                  message: describeFailure(error),
                  onRetry: () =>
                      ref.invalidate(warehouseGoodReceiptListProvider(null)),
                ),
              ),
              data: (rows) => rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Card(
                        key: emptyKey,
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            'Belum ada Good Receipt yang diposting cabang.',
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final summary in rows)
                          GoodReceiptSummaryTile(
                            summary: summary,
                            nowUtc: nowUtc,
                            onTap: () => context.pushNamed(
                              AppRoutes.warehouseGoodReceiptDetailName,
                              pathParameters: {'id': summary.id},
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
