import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/widgets/sync_status_tag.dart';
import '../../../../core/enums/app_enums.dart';
import '../../domain/models/master_admin_models.dart';

/// The chrome every master list shares (§40): search, an active/archived toggle,
/// an add button, and the three states a list can be in.
///
/// One widget rather than six copies, because §40 asks all six lists for the same
/// affordances and a copy per entity is five more places for the archived filter
/// to be forgotten.
class MasterListScaffold extends StatefulWidget {
  const MasterListScaffold({
    super.key,
    required this.title,
    required this.query,
    required this.includeInactive,
    required this.onQueryChanged,
    required this.onIncludeInactiveChanged,
    required this.onAdd,
    required this.onRefresh,
    required this.child,
    this.filters = const [],
    this.addLabel = 'Tambah',
  });

  final String title;
  final String query;
  final bool includeInactive;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onIncludeInactiveChanged;
  final VoidCallback? onAdd;
  final Future<void> Function() onRefresh;
  final Widget child;

  /// Entity-specific filter chips, e.g. category or role.
  final List<Widget> filters;

  final String addLabel;

  @override
  State<MasterListScaffold> createState() => _MasterListScaffoldState();
}

class _MasterListScaffoldState extends State<MasterListScaffold> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// ~200 ms, the interval §38 asks for: long enough that typing a SKU issues one
  /// query rather than eight, short enough that the list does not feel stuck.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => widget.onQueryChanged(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: widget.onAdd == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('master-list-add'),
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add),
              label: Text(widget.addLabel),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              key: const Key('master-list-search'),
              controller: _controller,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  key: const Key('master-list-include-inactive'),
                  label: const Text('Tampilkan nonaktif/arsip'),
                  selected: widget.includeInactive,
                  onSelected: widget.onIncludeInactiveChanged,
                ),
                for (final filter in widget.filters) ...[
                  const SizedBox(width: 8),
                  filter,
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The empty state every list shows when a filter matched nothing (§40).
class MasterListEmptyState extends StatelessWidget {
  const MasterListEmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      Icon(
        Icons.inbox_outlined,
        size: 48,
        color: Theme.of(context).disabledColor,
      ),
      const SizedBox(height: 12),
      Text(
        message,
        key: const Key('master-list-empty'),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

/// The error state (§40). Never renders an exception string (§45).
class MasterListErrorState extends StatelessWidget {
  const MasterListErrorState({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(32),
    children: const [
      Text(
        'Data gagal dimuat. Tarik ke bawah untuk mencoba lagi.',
        key: Key('master-list-error'),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

/// The badge §40 asks every list to carry: whether this row already has history.
class MasterUsageBadge extends StatelessWidget {
  const MasterUsageBadge({super.key, required this.usage});

  final MasterHistoricalUsage usage;

  @override
  Widget build(BuildContext context) {
    if (!usage.isUsed) return const SizedBox.shrink();
    return Tooltip(
      message: usage.describe(),
      child: Chip(
        key: const Key('master-usage-badge'),
        visualDensity: VisualDensity.compact,
        label: const Text('Terpakai'),
      ),
    );
  }
}

/// The lifecycle tag: active, deactivated, or archived (§3.6, §40).
///
/// Three states rather than two, because they are three different facts and the
/// operator's next action differs: a deactivated row is reactivated, an archived
/// one is restored.
class MasterLifecycleTag extends StatelessWidget {
  const MasterLifecycleTag({
    super.key,
    required this.isActive,
    required this.isArchived,
  });

  final bool isActive;
  final bool isArchived;

  @override
  Widget build(BuildContext context) {
    if (isArchived) {
      return const Chip(
        key: Key('master-lifecycle-archived'),
        visualDensity: VisualDensity.compact,
        label: Text('Arsip'),
      );
    }
    if (!isActive) {
      return const Chip(
        key: Key('master-lifecycle-inactive'),
        visualDensity: VisualDensity.compact,
        label: Text('Nonaktif'),
      );
    }
    return const SizedBox.shrink();
  }
}

/// The sync tag, reusing the shared widget so master rows and document rows read
/// the same way (G-Y).
class MasterSyncTag extends StatelessWidget {
  const MasterSyncTag({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) => SyncStatusTag(status: status);
}
