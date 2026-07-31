/// The six master lists (§40).
///
/// ### One vocabulary, everywhere
///
/// The four entities with `is_active` say *Nonaktifkan* / *Aktifkan Kembali*; the
/// two without say *Arsipkan* / *Pulihkan* (§41). Neither ever says *Hapus* or
/// *Delete*, because neither ever deletes: G-A4 and G-A5 leave soft-delete as the
/// only retirement, and a button labelled *Hapus Permanen* would be a button
/// promising something no code path performs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/date_only.dart';
import '../../domain/models/master_admin_models.dart';
import '../providers/master_admin_providers.dart';
import '../widgets/master_list_scaffold.dart';

/// Shared confirmation dialog, so every list asks the same way.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('master-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Runs a write and reports it, without ever surfacing an exception (§45).
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  required String successMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(describeFailure(error))));
  }
}

// --- branches ---------------------------------------------------------------

class MasterBranchListPage extends ConsumerWidget {
  const MasterBranchListPage({super.key});

  static const entity = MasterEntityType.branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(masterListFilterProvider(entity));
    final rows = ref.watch(masterBranchListProvider(filter));
    final actorId = ref.watch(masterAdminActorIdProvider);

    return MasterListScaffold(
      title: 'Cabang',
      addLabel: 'Tambah Cabang',
      query: filter.query,
      includeInactive: filter.includeInactive,
      onQueryChanged: (value) =>
          ref.read(masterListFiltersProvider.notifier).setQuery(entity, value),
      onIncludeInactiveChanged: (value) => ref
          .read(masterListFiltersProvider.notifier)
          .setIncludeInactive(entity, value),
      onAdd: () => context.go(
        '${AppRoutes.master}/${AppRoutes.masterBranches}/'
        '${AppRoutes.masterEntityNew}',
      ),
      onRefresh: () async => ref.invalidate(masterBranchListProvider),
      child: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const MasterListErrorState(),
        data: (views) => views.isEmpty
            ? const MasterListEmptyState(
                message: 'Belum ada cabang yang cocok dengan pencarian ini.',
              )
            : ListView.separated(
                itemCount: views.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final view = views[index];
                  return ListTile(
                    key: Key('branch-row-${view.branch.code}'),
                    title: Text('${view.branch.code} · ${view.branch.name}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (view.branch.address != null)
                          Text(view.branch.address!),
                        Text(
                          '${view.roomCount} ruangan · '
                          '${view.activeUserCount} pengguna aktif',
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MasterLifecycleTag(
                              isActive: view.branch.isActive,
                              isArchived: view.branch.isArchived,
                            ),
                            MasterSyncTag(status: view.syncStatus),
                          ],
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: actorId == null
                        ? null
                        : _LifecycleButton(
                            isActive: view.branch.isActive,
                            onPressed: () async {
                              final next = !view.branch.isActive;
                              if (!await _confirm(
                                context,
                                title: next
                                    ? 'Aktifkan Kembali'
                                    : 'Nonaktifkan',
                                message: next
                                    ? 'Aktifkan kembali cabang '
                                          '${view.branch.code}?'
                                    : 'Nonaktifkan cabang ${view.branch.code}? '
                                          'Data historis tetap tersimpan.',
                                confirmLabel: next
                                    ? 'Aktifkan Kembali'
                                    : 'Nonaktifkan',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              await _run(
                                context,
                                ref,
                                () => ref
                                    .read(setBranchActiveUseCaseProvider)
                                    .call(
                                      actorUserId: actorId,
                                      branchId: view.branch.id,
                                      isActive: next,
                                    ),
                                successMessage: next
                                    ? 'Cabang diaktifkan kembali.'
                                    : 'Cabang dinonaktifkan.',
                              );
                              ref.invalidate(masterBranchListProvider);
                            },
                          ),
                    onTap: () => context.go(
                      '${AppRoutes.master}/${AppRoutes.masterBranches}/'
                      '${view.branch.id}',
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// --- rooms ------------------------------------------------------------------

class MasterRoomListPage extends ConsumerWidget {
  const MasterRoomListPage({super.key});

  static const entity = MasterEntityType.rooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(masterListFilterProvider(entity));
    final rows = ref.watch(masterRoomListProvider(filter));
    final actorId = ref.watch(masterAdminActorIdProvider);

    return MasterListScaffold(
      title: 'Ruangan',
      addLabel: 'Tambah Ruangan',
      query: filter.query,
      includeInactive: filter.includeInactive,
      onQueryChanged: (value) =>
          ref.read(masterListFiltersProvider.notifier).setQuery(entity, value),
      onIncludeInactiveChanged: (value) => ref
          .read(masterListFiltersProvider.notifier)
          .setIncludeInactive(entity, value),
      onAdd: () => context.go(
        '${AppRoutes.master}/${AppRoutes.masterRooms}/'
        '${AppRoutes.masterEntityNew}',
      ),
      onRefresh: () async => ref.invalidate(masterRoomListProvider),
      child: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const MasterListErrorState(),
        data: (views) => views.isEmpty
            ? const MasterListEmptyState(
                message: 'Belum ada ruangan yang cocok dengan pencarian ini.',
              )
            : ListView.separated(
                itemCount: views.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final view = views[index];
                  return ListTile(
                    key: Key('room-row-${view.branchCode}-${view.room.code}'),
                    title: Text(
                      '${view.branchCode} / ${view.room.code} · '
                      '${view.room.name}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // §22: a room without a stock location is an integrity
                          // problem to surface rather than to hide.
                          view.stockLocationName == null
                              ? 'Lokasi stok belum tersedia'
                              : 'Lokasi stok: ${view.stockLocationName}',
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MasterLifecycleTag(
                              isActive: view.room.isActive,
                              isArchived: view.room.isArchived,
                            ),
                            MasterSyncTag(status: view.syncStatus),
                          ],
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: actorId == null
                        ? null
                        : _LifecycleButton(
                            isActive: view.room.isActive,
                            onPressed: () async {
                              final next = !view.room.isActive;
                              if (!await _confirm(
                                context,
                                title: next
                                    ? 'Aktifkan Kembali'
                                    : 'Nonaktifkan',
                                message: next
                                    ? 'Aktifkan kembali ruangan '
                                          '${view.room.code}?'
                                    : 'Nonaktifkan ruangan ${view.room.code}? '
                                          'Stok dan riwayatnya tetap tersimpan.',
                                confirmLabel: next
                                    ? 'Aktifkan Kembali'
                                    : 'Nonaktifkan',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              await _run(
                                context,
                                ref,
                                () => ref
                                    .read(setRoomActiveUseCaseProvider)
                                    .call(
                                      actorUserId: actorId,
                                      roomId: view.room.id,
                                      isActive: next,
                                    ),
                                successMessage: next
                                    ? 'Ruangan diaktifkan kembali.'
                                    : 'Ruangan dinonaktifkan.',
                              );
                              ref.invalidate(masterRoomListProvider);
                            },
                          ),
                    onTap: () => context.go(
                      '${AppRoutes.master}/${AppRoutes.masterRooms}/'
                      '${view.room.id}',
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// --- users -------------------------------------------------------------------

class MasterUserListPage extends ConsumerWidget {
  const MasterUserListPage({super.key});

  static const entity = MasterEntityType.users;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(masterListFilterProvider(entity));
    final rows = ref.watch(masterUserListProvider(filter));
    final actorId = ref.watch(masterAdminActorIdProvider);

    return MasterListScaffold(
      title: 'Pengguna',
      addLabel: 'Tambah Pengguna',
      query: filter.query,
      includeInactive: filter.includeInactive,
      onQueryChanged: (value) =>
          ref.read(masterListFiltersProvider.notifier).setQuery(entity, value),
      onIncludeInactiveChanged: (value) => ref
          .read(masterListFiltersProvider.notifier)
          .setIncludeInactive(entity, value),
      filters: [
        for (final role in UserRole.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              key: Key('user-role-filter-${role.dbValue}'),
              label: Text(role.label),
              selected: filter.role == role,
              onSelected: (selected) => ref
                  .read(masterListFiltersProvider.notifier)
                  .setRole(entity, selected ? role : null),
            ),
          ),
      ],
      onAdd: () => context.go(
        '${AppRoutes.master}/${AppRoutes.masterUsers}/'
        '${AppRoutes.masterEntityNew}',
      ),
      onRefresh: () async => ref.invalidate(masterUserListProvider),
      child: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const MasterListErrorState(),
        data: (views) => views.isEmpty
            ? const MasterListEmptyState(
                message: 'Belum ada pengguna yang cocok dengan pencarian ini.',
              )
            : ListView.separated(
                itemCount: views.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final view = views[index];
                  return ListTile(
                    key: Key('user-row-${view.user.email}'),
                    title: Row(
                      children: [
                        Expanded(child: Text(view.user.fullName)),
                        if (view.isSelf)
                          const Chip(
                            key: Key('user-self-badge'),
                            visualDensity: VisualDensity.compact,
                            label: Text('Anda'),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(view.user.email),
                        Text(
                          '${view.user.role.label}'
                          '${view.branchCode == null ? '' : ' · ${view.branchCode}'}',
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MasterLifecycleTag(
                              isActive: view.user.isActive,
                              isArchived: false,
                            ),
                            MasterSyncTag(status: view.syncStatus),
                          ],
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    // §21: the actor may not deactivate themselves, so the
                    // control that would submit it is simply not offered.
                    trailing: actorId == null || view.isSelf
                        ? null
                        : _LifecycleButton(
                            isActive: view.user.isActive,
                            onPressed: () async {
                              final next = !view.user.isActive;
                              if (!await _confirm(
                                context,
                                title: next
                                    ? 'Aktifkan Kembali'
                                    : 'Nonaktifkan',
                                message: next
                                    ? 'Aktifkan kembali akun '
                                          '${view.user.email}?'
                                    : 'Nonaktifkan akun ${view.user.email}? '
                                          'Riwayat dokumennya tetap tersimpan.',
                                confirmLabel: next
                                    ? 'Aktifkan Kembali'
                                    : 'Nonaktifkan',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              await _run(
                                context,
                                ref,
                                () => ref
                                    .read(setUserActiveUseCaseProvider)
                                    .call(
                                      actorUserId: actorId,
                                      userId: view.user.id,
                                      isActive: next,
                                    ),
                                successMessage: next
                                    ? 'Pengguna diaktifkan kembali.'
                                    : 'Pengguna dinonaktifkan.',
                              );
                              ref.invalidate(masterUserListProvider);
                            },
                          ),
                    onTap: () => context.go(
                      '${AppRoutes.master}/${AppRoutes.masterUsers}/'
                      '${view.user.id}',
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// --- categories -----------------------------------------------------------------

class MasterCategoryListPage extends ConsumerWidget {
  const MasterCategoryListPage({super.key});

  static const entity = MasterEntityType.itemCategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(masterListFilterProvider(entity));
    final rows = ref.watch(masterCategoryListProvider(filter));
    final actorId = ref.watch(masterAdminActorIdProvider);

    return MasterListScaffold(
      title: 'Kategori',
      addLabel: 'Tambah Kategori',
      query: filter.query,
      includeInactive: filter.includeInactive,
      onQueryChanged: (value) =>
          ref.read(masterListFiltersProvider.notifier).setQuery(entity, value),
      onIncludeInactiveChanged: (value) => ref
          .read(masterListFiltersProvider.notifier)
          .setIncludeInactive(entity, value),
      onAdd: () => context.go(
        '${AppRoutes.master}/${AppRoutes.masterCategories}/'
        '${AppRoutes.masterEntityNew}',
      ),
      onRefresh: () async => ref.invalidate(masterCategoryListProvider),
      child: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const MasterListErrorState(),
        data: (views) => views.isEmpty
            ? const MasterListEmptyState(
                message: 'Belum ada kategori yang cocok dengan pencarian ini.',
              )
            : ListView.separated(
                itemCount: views.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final view = views[index];
                  return ListTile(
                    key: Key('category-row-${view.category.name}'),
                    title: Text(view.category.name),
                    subtitle: Row(
                      children: [
                        Text('${view.itemCount} barang'),
                        const SizedBox(width: 8),
                        MasterLifecycleTag(
                          isActive: true,
                          isArchived: view.isArchived,
                        ),
                        const SizedBox(width: 8),
                        MasterSyncTag(status: view.syncStatus),
                      ],
                    ),
                    trailing: actorId == null
                        ? null
                        : TextButton(
                            key: Key(
                              'category-lifecycle-${view.category.name}',
                            ),
                            onPressed: () async {
                              // Categories have no `is_active`, so the words are
                              // *Arsipkan* / *Pulihkan* rather than
                              // *Nonaktifkan* / *Aktifkan Kembali* (§41).
                              final restore = view.isArchived;
                              if (!await _confirm(
                                context,
                                title: restore ? 'Pulihkan' : 'Arsipkan',
                                message: restore
                                    ? 'Pulihkan kategori '
                                          '${view.category.name}?'
                                    : 'Arsipkan kategori '
                                          '${view.category.name}? Barang yang '
                                          'pernah memakainya tetap tercatat.',
                                confirmLabel: restore ? 'Pulihkan' : 'Arsipkan',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              await _run(
                                context,
                                ref,
                                () => restore
                                    ? ref
                                          .read(restoreCategoryUseCaseProvider)
                                          .call(
                                            actorUserId: actorId,
                                            categoryId: view.category.id,
                                          )
                                    : ref
                                          .read(archiveCategoryUseCaseProvider)
                                          .call(
                                            actorUserId: actorId,
                                            categoryId: view.category.id,
                                          ),
                                successMessage: restore
                                    ? 'Kategori dipulihkan.'
                                    : 'Kategori diarsipkan.',
                              );
                              ref.invalidate(masterCategoryListProvider);
                            },
                            child: Text(
                              view.isArchived ? 'Pulihkan' : 'Arsipkan',
                            ),
                          ),
                  );
                },
              ),
      ),
    );
  }
}

// --- items ------------------------------------------------------------------------

class MasterItemListPage extends ConsumerWidget {
  const MasterItemListPage({super.key});

  static const entity = MasterEntityType.items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(masterListFilterProvider(entity));
    final rows = ref.watch(masterItemListProvider(filter));
    final actorId = ref.watch(masterAdminActorIdProvider);

    return MasterListScaffold(
      title: 'Barang',
      addLabel: 'Tambah Barang',
      query: filter.query,
      includeInactive: filter.includeInactive,
      onQueryChanged: (value) =>
          ref.read(masterListFiltersProvider.notifier).setQuery(entity, value),
      onIncludeInactiveChanged: (value) => ref
          .read(masterListFiltersProvider.notifier)
          .setIncludeInactive(entity, value),
      filters: [
        FilterChip(
          key: const Key('item-has-expiry-filter'),
          label: const Text('Ber-kedaluwarsa'),
          selected: filter.hasExpiry == true,
          onSelected: (selected) => ref
              .read(masterListFiltersProvider.notifier)
              .setHasExpiry(entity, selected ? true : null),
        ),
      ],
      onAdd: () => context.go(
        '${AppRoutes.master}/${AppRoutes.masterItems}/'
        '${AppRoutes.masterEntityNew}',
      ),
      onRefresh: () async => ref.invalidate(masterItemListProvider),
      child: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const MasterListErrorState(),
        data: (views) => views.isEmpty
            ? const MasterListEmptyState(
                message: 'Belum ada barang yang cocok dengan pencarian ini.',
              )
            : ListView.separated(
                itemCount: views.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final view = views[index];
                  return ListTile(
                    key: Key('item-row-${view.item.sku}'),
                    title: Text('${view.item.sku} · ${view.item.name}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${view.categoryName} · ${view.item.unit} · '
                          'min ruangan ${view.item.minStockRoom} · '
                          'min cabang ${view.item.minStockBranch}',
                        ),
                        Text(
                          view.item.hasExpiry
                              ? 'Ber-kedaluwarsa · peringatan '
                                    '${view.item.expiryAlertDays} hari · '
                                    '${view.batchCount} batch'
                              : 'Tanpa kedaluwarsa',
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MasterLifecycleTag(
                              isActive: view.item.isActive,
                              isArchived: view.isArchived,
                            ),
                            MasterUsageBadge(usage: view.usage),
                            MasterSyncTag(status: view.syncStatus),
                          ],
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: actorId == null
                        ? null
                        : _LifecycleButton(
                            isActive: view.item.isActive,
                            onPressed: () async {
                              final next = !view.item.isActive;
                              if (!await _confirm(
                                context,
                                title: next
                                    ? 'Aktifkan Kembali'
                                    : 'Nonaktifkan',
                                message: next
                                    ? 'Aktifkan kembali barang '
                                          '${view.item.sku}?'
                                    : 'Nonaktifkan barang ${view.item.sku}? '
                                          'Seluruh riwayat transaksinya tetap '
                                          'tersimpan.',
                                confirmLabel: next
                                    ? 'Aktifkan Kembali'
                                    : 'Nonaktifkan',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              await _run(
                                context,
                                ref,
                                () => ref
                                    .read(setItemActiveUseCaseProvider)
                                    .call(
                                      actorUserId: actorId,
                                      itemId: view.item.id,
                                      isActive: next,
                                    ),
                                successMessage: next
                                    ? 'Barang diaktifkan kembali.'
                                    : 'Barang dinonaktifkan.',
                              );
                              ref.invalidate(masterItemListProvider);
                            },
                          ),
                    onTap: () => context.go(
                      '${AppRoutes.master}/${AppRoutes.masterItems}/'
                      '${view.item.id}',
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// --- batches -----------------------------------------------------------------------

class MasterBatchListPage extends ConsumerWidget {
  const MasterBatchListPage({super.key});

  static const entity = MasterEntityType.itemBatches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(masterListFilterProvider(entity));
    final rows = ref.watch(masterBatchListProvider(filter));
    final actorId = ref.watch(masterAdminActorIdProvider);

    return MasterListScaffold(
      title: 'Batch',
      addLabel: 'Tambah Batch',
      query: filter.query,
      includeInactive: filter.includeInactive,
      onQueryChanged: (value) =>
          ref.read(masterListFiltersProvider.notifier).setQuery(entity, value),
      onIncludeInactiveChanged: (value) => ref
          .read(masterListFiltersProvider.notifier)
          .setIncludeInactive(entity, value),
      onAdd: () => context.go(
        '${AppRoutes.master}/${AppRoutes.masterBatches}/'
        '${AppRoutes.masterEntityNew}',
      ),
      onRefresh: () async => ref.invalidate(masterBatchListProvider),
      child: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const MasterListErrorState(),
        data: (views) => views.isEmpty
            ? const MasterListEmptyState(
                message: 'Belum ada batch yang cocok dengan pencarian ini.',
              )
            : ListView.separated(
                itemCount: views.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final view = views[index];
                  return ListTile(
                    key: Key('batch-row-${view.itemSku}-${view.batch.batchNo}'),
                    title: Text('${view.itemSku} · ${view.batch.batchNo}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(view.itemName),
                        Text(
                          'Kedaluwarsa '
                          '${DateOnly.formatIso(view.batch.expiryDate)}',
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MasterLifecycleTag(
                              isActive: true,
                              isArchived: view.isArchived,
                            ),
                            MasterUsageBadge(usage: view.usage),
                            MasterSyncTag(status: view.syncStatus),
                          ],
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: actorId == null
                        ? null
                        : TextButton(
                            key: Key(
                              'batch-lifecycle-${view.itemSku}-'
                              '${view.batch.batchNo}',
                            ),
                            onPressed: () async {
                              final restore = view.isArchived;
                              if (!await _confirm(
                                context,
                                title: restore ? 'Pulihkan' : 'Arsipkan',
                                message: restore
                                    ? 'Pulihkan batch '
                                          '${view.batch.batchNo}?'
                                    : 'Arsipkan batch ${view.batch.batchNo}? '
                                          'Saldo dan riwayatnya tetap '
                                          'tersimpan.',
                                confirmLabel: restore ? 'Pulihkan' : 'Arsipkan',
                              )) {
                                return;
                              }
                              if (!context.mounted) return;
                              await _run(
                                context,
                                ref,
                                () => restore
                                    ? ref
                                          .read(restoreBatchUseCaseProvider)
                                          .call(
                                            actorUserId: actorId,
                                            batchId: view.batch.id,
                                          )
                                    : ref
                                          .read(archiveBatchUseCaseProvider)
                                          .call(
                                            actorUserId: actorId,
                                            batchId: view.batch.id,
                                          ),
                                successMessage: restore
                                    ? 'Batch dipulihkan.'
                                    : 'Batch diarsipkan.',
                              );
                              ref.invalidate(masterBatchListProvider);
                            },
                            child: Text(
                              view.isArchived ? 'Pulihkan' : 'Arsipkan',
                            ),
                          ),
                    onTap: () => context.go(
                      '${AppRoutes.master}/${AppRoutes.masterBatches}/'
                      '${view.batch.id}',
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// *Nonaktifkan* / *Aktifkan Kembali* — never *Hapus* (§41).
class _LifecycleButton extends StatelessWidget {
  const _LifecycleButton({required this.isActive, required this.onPressed});

  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    key: Key(isActive ? 'master-deactivate' : 'master-reactivate'),
    onPressed: onPressed,
    child: Text(isActive ? 'Nonaktifkan' : 'Aktifkan Kembali'),
  );
}
