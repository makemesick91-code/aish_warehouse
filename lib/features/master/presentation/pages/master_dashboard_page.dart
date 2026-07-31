import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../domain/models/master_admin_models.dart';
import '../providers/master_admin_providers.dart';

/// `/master` — the Super Admin's master section (§39).
///
/// Six cards, one per entity, each carrying the two counts §39 asks for and the
/// last time anything in that table changed. Below them, the two entries into the
/// import module.
///
/// The counts come from [masterDashboardProvider], which returns an **empty**
/// dashboard for an unauthorized actor rather than throwing — so a tree that
/// somehow rendered without the guard contains no numbers at all (§53).
class MasterDashboardPage extends ConsumerWidget {
  const MasterDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(masterDashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Master Data')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(masterDashboardProvider),
        child: dashboard.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Text(
                'Data master gagal dimuat. Tarik ke bawah untuk mencoba lagi.',
              ),
            ],
          ),
          data: (data) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // A narrow screen gets one column; a wide one gets two. Nothing
              // here has a fixed width, so §56's overflow assertion holds at
              // 320 dp.
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 640 ? 2 : 1;
                  // A fixed *height* rather than an aspect ratio: the card's
                  // content is four lines of text whose height does not shrink
                  // with the viewport, so a ratio that fits at 800 dp overflows
                  // at 320 (§56). 152 dp clears the tallest of them with the
                  // default text scale and leaves room for a larger one.
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio:
                        (constraints.maxWidth / columns - 12) / 152,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      for (final entity in _cardOrder)
                        _MasterEntityCard(
                          summary:
                              data.forEntity(entity) ??
                              MasterEntitySummary(
                                entity: entity,
                                activeCount: 0,
                                inactiveCount: 0,
                              ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('Import', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  key: const Key('master-dashboard-template-import'),
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Template Import'),
                  subtitle: const Text(
                    'Unduh template Excel, unggah file, lihat pratinjau, lalu '
                    'terapkan.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.imports),
                ),
              ),
              Card(
                child: ListTile(
                  key: const Key('master-dashboard-import-history'),
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Riwayat Import'),
                  subtitle: const Text(
                    'Catatan setiap impor: file, jumlah baris, siapa, dan '
                    'kapan.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(AppRoutes.imports),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The order §39 lists them in.
  static const List<MasterEntityType> _cardOrder = [
    MasterEntityType.items,
    MasterEntityType.itemCategories,
    MasterEntityType.branches,
    MasterEntityType.rooms,
    MasterEntityType.users,
    MasterEntityType.itemBatches,
  ];
}

class _MasterEntityCard extends StatelessWidget {
  const _MasterEntityCard({required this.summary});

  final MasterEntitySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('master-card-${summary.entity.dbValue}'),
      child: InkWell(
        onTap: () => context.go(_pathFor(summary.entity)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.entity.label,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${summary.activeCount} aktif',
                style: theme.textTheme.headlineSmall,
              ),
              Text(
                // "Nonaktif" covers both signals a card has room for: the
                // deactivated rows of the four entities with `is_active`, and
                // the archived rows of the two without (§3.6).
                '${summary.inactiveCount} nonaktif/arsip',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                summary.lastUpdatedAtUtc == null
                    ? 'Belum ada data'
                    : 'Diperbarui '
                          '${AppDateTimeFormatter.dateTimeWithZone(summary.lastUpdatedAtUtc!)}',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pathFor(MasterEntityType entity) => switch (entity) {
    MasterEntityType.items => '${AppRoutes.master}/${AppRoutes.masterItems}',
    MasterEntityType.itemCategories =>
      '${AppRoutes.master}/${AppRoutes.masterCategories}',
    MasterEntityType.branches =>
      '${AppRoutes.master}/${AppRoutes.masterBranches}',
    MasterEntityType.rooms => '${AppRoutes.master}/${AppRoutes.masterRooms}',
    MasterEntityType.users => '${AppRoutes.master}/${AppRoutes.masterUsers}',
    MasterEntityType.itemBatches =>
      '${AppRoutes.master}/${AppRoutes.masterBatches}',
  };
}
