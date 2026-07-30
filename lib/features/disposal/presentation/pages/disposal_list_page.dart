import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/widgets/historical_master_badge.dart';
import '../../../../core/widgets/status_card.dart';
import '../../../../core/widgets/sync_status_tag.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/disposal_models.dart';
import '../../domain/services/disposal_access_policy.dart';
import '../providers/disposal_providers.dart';
import '../widgets/disposal_badges.dart';

/// Pemusnahan Stok — one screen, two scopes (§28/§29).
///
/// The Petugas Warehouse reaches it at `/warehouse/disposals` and sees exactly what
/// leaves Warehouse Pusat; the Kepala Cabang reaches it at `/disposals` and sees
/// exactly what leaves their own branch. Neither list ever contains one of the
/// other's documents — the scope travels into the SQL, so a foreign document is not
/// fetched rather than fetched and then withheld.
///
/// One widget for both because the *work* is the same: look at what has expired,
/// start a document, finish the ones you started, read the ones you finished. What
/// differs is a single fact — whether there is a source to choose — and [scope]
/// decides that rather than a copy of the screen.
///
/// Three sections, in the order §28 lists them:
///
/// 1. **Stok Kedaluwarsa** — what is on the shelf right now. This is the list that
///    makes G-E6 actionable rather than merely visible: every row is a batch that
///    can be destroyed today.
/// 2. **Draft Pemusnahan** — documents started and not yet posted.
/// 3. **Riwayat Diposting** — read-only history.
class DisposalListPage extends ConsumerStatefulWidget {
  const DisposalListPage({super.key, required this.scope});

  /// Which side of the document this screen is. Warehouse has one source and no
  /// selector; a branch head chooses between the store and their rooms.
  final DisposalLocationScope scope;

  static const Key tabsKey = ValueKey('disposalTabs');
  static const Key expiredTabKey = ValueKey('disposalExpiredTab');
  static const Key draftTabKey = ValueKey('disposalDraftTab');
  static const Key historyTabKey = ValueKey('disposalHistoryTab');
  static const Key createKey = ValueKey('disposalCreateButton');
  static const Key sourceSelectorKey = ValueKey('disposalSourceSelector');
  static const Key sourceHeaderKey = ValueKey('disposalSourceHeader');
  static const Key expiredListKey = ValueKey('disposalExpiredList');
  static const Key expiredEmptyKey = ValueKey('disposalExpiredEmpty');
  static const Key draftListKey = ValueKey('disposalDraftList');
  static const Key draftEmptyKey = ValueKey('disposalDraftEmpty');
  static const Key historyListKey = ValueKey('disposalHistoryList');
  static const Key historyEmptyKey = ValueKey('disposalHistoryEmpty');
  static const Key searchKey = ValueKey('disposalListSearch');
  static const Key candidateSearchKey = ValueKey('disposalCandidateSearch');

  static Key sourceChipKeyFor(String locationId) =>
      ValueKey('disposalSourceChip-$locationId');

  @override
  ConsumerState<DisposalListPage> createState() => _DisposalListPageState();
}

class _DisposalListPageState extends ConsumerState<DisposalListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _isBranch => widget.scope == DisposalLocationScope.branch;

  AsyncValue<List<DisposalSummary>> get _documents => _isBranch
      ? ref.watch(branchDisposalListProvider)
      : ref.watch(warehouseDisposalListProvider);

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(effectiveDisposalSourceProvider);
    final creating = ref.watch(createDisposalControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pemusnahan Stok'),
        bottom: TabBar(
          key: DisposalListPage.tabsKey,
          controller: _tabs,
          tabs: const [
            Tab(key: DisposalListPage.expiredTabKey, text: 'Stok Kedaluwarsa'),
            Tab(key: DisposalListPage.draftTabKey, text: 'Draft'),
            Tab(key: DisposalListPage.historyTabKey, text: 'Riwayat'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: DisposalListPage.createKey,
        // Disabled while a creation is in flight — two taps must not produce two
        // documents — and while there is no source to raise one against.
        onPressed: creating.isLoading || source.value == null
            ? null
            : () => _create(source.value!),
        icon: const Icon(Icons.add),
        label: const Text('Buat Pemusnahan'),
      ),
      body: Column(
        children: [
          if (_isBranch) const _SourceSelector() else const _SourceHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                const _ExpiredStockTab(),
                _DocumentsTab(
                  documents: _documents,
                  status: DisposalStatus.draft,
                  listKey: DisposalListPage.draftListKey,
                  emptyKey: DisposalListPage.draftEmptyKey,
                  emptyMessage:
                      'Belum ada draft pemusnahan. Pilih stok kedaluwarsa lalu '
                      'tekan "Buat Pemusnahan".',
                  scope: widget.scope,
                ),
                _DocumentsTab(
                  documents: _documents,
                  status: DisposalStatus.posted,
                  listKey: DisposalListPage.historyListKey,
                  emptyKey: DisposalListPage.historyEmptyKey,
                  emptyMessage: 'Belum ada pemusnahan yang diposting.',
                  scope: widget.scope,
                  showSearch: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create(MasterLocation source) async {
    final id = await ref
        .read(createDisposalControllerProvider.notifier)
        .create(sourceLocationId: source.id);
    if (!mounted) return;
    if (id == null) {
      final error = ref.read(createDisposalControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describeFailure(error ?? 'Gagal membuat pemusnahan.')),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    context.pushNamed(
      _isBranch
          ? AppRoutes.disposalEditName
          : AppRoutes.warehouseDisposalEditName,
      pathParameters: {'id': id},
    );
  }
}

/// The warehouse's fixed source, stated rather than chosen (§28).
///
/// A warehouse account has exactly one location it may destroy stock at, so offering
/// a picker would be offering a choice with one option — and, worse, a control a
/// future change could widen by accident.
class _SourceHeader extends ConsumerWidget {
  const _SourceHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(effectiveDisposalSourceProvider).value;
    if (source == null) return const SizedBox.shrink();

    return Padding(
      key: DisposalListPage.sourceHeaderKey,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          const Icon(Icons.warehouse_outlined, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              source.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The branch head's source selector (§29).
///
/// Built from [disposalSourceLocationsProvider], which resolves the *Gudang Cabang*
/// and every room of the acting user's own branch from master data. Dynamic rather
/// than a hard-coded `R1 / R2 / R3`: spec §2.1 makes rooms master data managed by
/// the Super Admin, and a branch with four rooms must show five chips.
///
/// There is no "semua lokasi" chip, and its absence is the one-source invariant made
/// visible: a document draws from exactly one shelf, so a selector that could mean
/// "all of them" would be offering something the document cannot express.
class _SourceSelector extends ConsumerWidget {
  const _SourceSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations =
        ref.watch(disposalSourceLocationsProvider).value ?? const [];
    if (locations.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(effectiveDisposalSourceProvider).value;

    return SingleChildScrollView(
      key: DisposalListPage.sourceSelectorKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          for (final location in locations) ...[
            FilterChip(
              key: DisposalListPage.sourceChipKeyFor(location.id),
              label: Text(location.name),
              avatar: Icon(
                location.type == StockLocationType.room
                    ? Icons.meeting_room_outlined
                    : Icons.store_mall_directory_outlined,
                size: 16,
              ),
              selected: selected?.id == location.id,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => ref
                  .read(selectedDisposalSourceProvider.notifier)
                  .select(location.id),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// The *Stok Kedaluwarsa* tab — what is on the selected shelf right now.
class _ExpiredStockTab extends ConsumerWidget {
  const _ExpiredStockTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positions = ref.watch(disposalExpiredPositionsProvider);
    final nowUtc = ref.watch(disposalClockProvider)();

    return Column(
      children: [
        const _CategoryFilterRow(),
        const _CandidateSearchField(),
        Expanded(
          child: positions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ErrorNotice(
                message: describeFailure(error),
                onRetry: () => ref.invalidate(disposalExpiredPositionsProvider),
              ),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Card(
                    key: DisposalListPage.expiredEmptyKey,
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'Tidak ada stok kedaluwarsa di lokasi ini. Barang yang '
                        'segera kedaluwarsa belum dapat dimusnahkan.',
                      ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                key: DisposalListPage.expiredListKey,
                padding: const EdgeInsets.only(bottom: AppSpacing.xl * 2),
                itemCount: rows.length,
                itemBuilder: (context, index) =>
                    ExpiredPositionTile(position: rows[index], nowUtc: nowUtc),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One expired position on the *Stok Kedaluwarsa* tab.
///
/// Read-only: it is a report of what is on the shelf, not a picker. Choosing what to
/// destroy happens inside a document, where the quantity can be validated against a
/// live balance.
class ExpiredPositionTile extends StatelessWidget {
  const ExpiredPositionTile({
    super.key,
    required this.position,
    required this.nowUtc,
  });

  final ExpiredStockPosition position;

  /// UTC instant used as the reference "now" (T-7).
  final DateTime nowUtc;

  static Key tileKeyFor(String positionKey) =>
      ValueKey('disposalExpiredTile-$positionKey');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        key: tileKeyFor(position.positionKey),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                position.itemName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${position.sku} · batch ${position.batchNo}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DisposalExpiryBadge(
                    expiryDate: position.expiryDate,
                    // The informational threshold is irrelevant here — every row on
                    // this tab is already expired — so the badge is handed a value
                    // that cannot change its verdict.
                    expiryAlertDays: 0,
                    nowUtc: nowUtc,
                  ),
                  DisposalPill(
                    label: position.qtyOnHand.formatWithUnit(position.unit),
                    color: theme.colorScheme.primary,
                  ),
                  if (position.usesHistoricalMaster)
                    HistoricalMasterBadge.forDetail(
                      [
                        if (position.itemIsHistorical) 'Barang',
                        if (position.batchIsHistorical) 'Batch',
                      ].join(', '),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryFilterRow extends ConsumerWidget {
  const _CategoryFilterRow();

  static Key keyFor(String categoryId) =>
      ValueKey('disposalCategoryFilter-$categoryId');

  static const Key allKey = ValueKey('disposalCategoryFilter-all');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(disposalCategoriesProvider).value ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(disposalCategoryFilterProvider);
    final notifier = ref.read(disposalCategoryFilterProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          FilterChip(
            key: allKey,
            label: const Text('Semua'),
            selected: selected == null,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => notifier.clear(),
          ),
          for (final category in categories) ...[
            const SizedBox(width: AppSpacing.sm),
            FilterChip(
              key: keyFor(category.id),
              label: Text(category.name),
              selected: selected == category.id,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => notifier.select(category.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _CandidateSearchField extends ConsumerStatefulWidget {
  const _CandidateSearchField();

  @override
  ConsumerState<_CandidateSearchField> createState() =>
      _CandidateSearchFieldState();
}

class _CandidateSearchFieldState extends ConsumerState<_CandidateSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: TextField(
        key: DisposalListPage.candidateSearchKey,
        controller: _controller,
        onChanged: (value) =>
            ref.read(disposalCandidateSearchProvider.notifier).update(value),
        decoration: const InputDecoration(
          labelText: 'Cari barang, SKU atau batch',
          prefixIcon: Icon(Icons.search),
        ),
      ),
    );
  }
}

/// The *Draft* and *Riwayat* tabs — the same list, filtered by status.
class _DocumentsTab extends ConsumerWidget {
  const _DocumentsTab({
    required this.documents,
    required this.status,
    required this.listKey,
    required this.emptyKey,
    required this.emptyMessage,
    required this.scope,
    this.showSearch = false,
  });

  final AsyncValue<List<DisposalSummary>> documents;
  final DisposalStatus status;
  final Key listKey;
  final Key emptyKey;
  final String emptyMessage;
  final DisposalLocationScope scope;
  final bool showSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        if (showSearch) const _DocumentSearchField(),
        Expanded(
          child: documents.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ErrorNotice(message: describeFailure(error)),
            ),
            data: (all) {
              final rows = all
                  .where((summary) => summary.status == status)
                  .toList(growable: false);
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Card(
                    key: emptyKey,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(emptyMessage),
                    ),
                  ),
                );
              }
              return ListView.builder(
                key: listKey,
                padding: const EdgeInsets.only(bottom: AppSpacing.xl * 2),
                itemCount: rows.length,
                itemBuilder: (context, index) => DisposalSummaryTile(
                  summary: rows[index],
                  onTap: () => context.pushNamed(
                    _routeFor(rows[index]),
                    pathParameters: {'id': rows[index].id},
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// A draft opens in the editor, a posted document in the read-only detail. Both
  /// routes are guarded independently; this only chooses which one to try.
  String _routeFor(DisposalSummary summary) {
    final branch = scope == DisposalLocationScope.branch;
    if (summary.disposal.isDraft) {
      return branch
          ? AppRoutes.disposalEditName
          : AppRoutes.warehouseDisposalEditName;
    }
    return branch
        ? AppRoutes.disposalDetailName
        : AppRoutes.warehouseDisposalDetailName;
  }
}

class _DocumentSearchField extends ConsumerStatefulWidget {
  const _DocumentSearchField();

  @override
  ConsumerState<_DocumentSearchField> createState() =>
      _DocumentSearchFieldState();
}

class _DocumentSearchFieldState extends ConsumerState<_DocumentSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: TextField(
        key: DisposalListPage.searchKey,
        controller: _controller,
        onChanged: (value) =>
            ref.read(disposalSearchProvider.notifier).update(value),
        decoration: const InputDecoration(
          labelText: 'Cari nomor, lokasi atau barang',
          prefixIcon: Icon(Icons.search),
        ),
      ),
    );
  }
}

/// One row of a disposal document list.
class DisposalSummaryTile extends StatelessWidget {
  const DisposalSummaryTile({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final DisposalSummary summary;
  final VoidCallback onTap;

  static Key tileKeyFor(String disposalId) =>
      ValueKey('disposalTile-$disposalId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disposal = summary.disposal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Card(
        child: InkWell(
          key: tileKeyFor(summary.id),
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.docNumber,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DisposalStatusChip(status: summary.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(summary.sourceLabel, style: theme.textTheme.bodySmall),
                Text(
                  'Dibuat ${summary.createdByName} · '
                  // Both instants are UTC in storage and rendered in operational
                  // time (T-1/T-2); `toLocal()` is never called.
                  '${AppDateTimeFormatter.dateTimeWithZone(disposal.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (disposal.postedAt != null)
                  Text(
                    'Diposting ${summary.postedByName ?? '-'} · '
                    '${AppDateTimeFormatter.dateTimeWithZone(disposal.postedAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (disposal.hasReason)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      disposal.reason!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(summary.label, style: theme.textTheme.bodySmall),
                    SyncStatusTag(status: disposal.syncStatus),
                    if (summary.usesHistoricalMaster)
                      HistoricalMasterBadge.forDetail(
                        [
                          if (summary.sourceIsHistorical) 'Lokasi',
                          if (summary.branchIsHistorical) 'Cabang',
                          if (summary.roomIsHistorical) 'Ruangan',
                          if (summary.createdByIsHistorical) 'Pembuat',
                          if (summary.postedByIsHistorical) 'Pemosting',
                        ].join(', '),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `/warehouse/disposals` and `/warehouse/disposals/new` both land here.
Widget warehouseDisposalListPage(BuildContext context) =>
    const DisposalListPage(scope: DisposalLocationScope.warehouse);

/// `/disposals` and `/disposals/new` both land here.
Widget branchDisposalListPage(BuildContext context) =>
    const DisposalListPage(scope: DisposalLocationScope.branch);

/// The route kinds the two section guards use, named here so the router does not
/// have to know which policy value belongs to which path.
const DisposalRouteKind warehouseListKind = DisposalRouteKind.warehouseList;
const DisposalRouteKind branchListKind = DisposalRouteKind.branchList;
