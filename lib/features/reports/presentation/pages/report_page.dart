import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../domain/models/reporting_models.dart';
import '../../domain/services/report_access_policy.dart';
import '../../domain/services/report_filter_policy.dart';
import '../providers/reporting_providers.dart';
import '../widgets/export_buttons.dart';
import '../widgets/report_preview_view.dart';

/// `/reports` — the Laporan module, one screen for every role (§45).
///
/// ### One screen, four very different contents
///
/// A Perawat sees five report types and their own rooms; a Kepala Cabang sees
/// eleven and their branch; a Petugas Warehouse sees Warehouse Pusat and
/// cross-branch recaps; a Super Admin sees everything plus the audit trail. All of
/// that comes from [ReportAccessPolicy] through the providers — **nothing the actor
/// may not run appears in a list at all**, and nothing appears greyed out either. A
/// disabled *Gudang Cabang CAB-02* would tell a nurse that CAB-02 exists (§45).
///
/// The screen is a convenience, not the boundary: every preview and every export
/// re-reads the actor and re-applies the same policy (§16).
class ReportPage extends ConsumerWidget {
  const ReportPage({super.key});

  static const Key pageKey = ValueKey('reportPage');
  static const Key reportTypeFieldKey = ValueKey('reportTypeField');
  static const Key reportTypeSearchKey = ValueKey('reportTypeSearch');
  static const Key reportTypeEmptyKey = ValueKey('reportTypeEmpty');
  static const Key scopeFieldKey = ValueKey('reportScopeField');
  static const Key locationFieldKey = ValueKey('reportLocationField');
  static const Key branchFieldKey = ValueKey('reportBranchField');
  static const Key itemFieldKey = ValueKey('reportItemField');
  static const Key previewButtonKey = ValueKey('reportPreviewButton');
  static const Key exportHistoryLinkKey = ValueKey('reportExportHistoryLink');

  static const String title = 'Laporan';
  static const String previewLabel = 'Tampilkan Preview';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return Scaffold(
      key: pageKey,
      appBar: AppBar(
        title: const Text(title),
        actions: [
          if (canOpenExportHistoryForRole(ref.watch(actingRoleProvider)))
            IconButton(
              key: exportHistoryLinkKey,
              tooltip: 'Riwayat Ekspor',
              icon: const Icon(Icons.history),
              onPressed: () => context.go(AppRoutes.exportHistory),
            ),
        ],
      ),
      body: actor.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Gagal memuat pengguna.')),
        data: (user) => user == null
            ? const Center(child: Text('Sesi pengguna tidak tersedia.'))
            : _Body(actor: user),
      ),
    );
  }
}

/// Whether the audit entry point is drawn. Mirrors the route guard so the icon is
/// never a link to a refusal.
bool canOpenExportHistoryForRole(UserRole? role) =>
    ReportAccessPolicy.canReadExportHistory(role);

class _Body extends ConsumerWidget {
  const _Body({required this.actor});

  final MasterUser actor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reportDraftProvider);
    final preview = ref.watch(reportPreviewProvider);
    final ready = isReportDraftReady(draft);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _ActorCard(actor: actor),
        const SizedBox(height: AppSpacing.md),
        _FilterCard(draft: draft),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: ReportPage.previewButtonKey,
          // A preview is a `FutureProvider` that already fires when the draft is
          // complete, so this button is a *refresh*: the same question, asked again
          // against whatever the ledger holds now.
          onPressed: ready ? () => ref.invalidate(reportPreviewProvider) : null,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text(ReportPage.previewLabel),
        ),
        const SizedBox(height: AppSpacing.md),
        ExportButtons(enabled: ready),
        const SizedBox(height: AppSpacing.lg),
        if (!ready)
          const Text('Lengkapi filter untuk menampilkan laporan.')
        else
          preview.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) =>
                _ErrorCard(message: describeReportFailure(error)),
            data: (value) => value == null
                ? const SizedBox.shrink()
                : ReportPreviewView(preview: value),
          ),
      ],
    );
  }
}

class _ActorCard extends StatelessWidget {
  const _ActorCard({required this.actor});

  final MasterUser actor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: Text(actor.fullName),
        subtitle: Text(
          '${actor.role.label} · '
          '${ReportAccessPolicy.requiresOwnBranch(actor.role) ? 'Cakupan cabang sendiri' : 'Cakupan lintas cabang'}',
        ),
      ),
    );
  }
}

class _FilterCard extends ConsumerWidget {
  const _FilterCard({required this.draft});

  final ReportRequestDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(reportDraftProvider.notifier);
    final reportTypes = ref.watch(allowedReportTypesProvider);
    final scopes = ref.watch(allowedReportScopesProvider(draft.reportType));
    final locations = ref.watch(reportLocationOptionsProvider(draft.scopeType));
    final categories = ref.watch(reportCategoryOptionsProvider);
    final branches = ref.watch(reportBranchOptionsProvider);
    final role = ref.watch(actingRoleProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReportTypeField(
              options: reportTypes,
              selected: draft.reportType,
              onSelected: controller.setReportType,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ReportScopeType>(
              isExpanded: true,
              key: ReportPage.scopeFieldKey,
              initialValue: scopes.contains(draft.scopeType)
                  ? draft.scopeType
                  : null,
              decoration: const InputDecoration(labelText: 'Cakupan'),
              items: [
                for (final scope in scopes)
                  DropdownMenuItem(value: scope, child: Text(scope.label)),
              ],
              onChanged: (value) {
                if (value != null) controller.setScopeType(value);
              },
            ),
            if (draft.scopeType.requiresLocation) ...[
              const SizedBox(height: AppSpacing.sm),
              locations.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Gagal memuat lokasi.'),
                data: (options) => _LocationField(
                  options: options,
                  selectedId: draft.locationId,
                  onSelected: controller.setLocation,
                ),
              ),
            ],
            if (ReportFilterPolicy.supportsBranchFilter(
              role: role,
              reportType: draft.reportType,
              scopeType: draft.scopeType,
            )) ...[
              const SizedBox(height: AppSpacing.sm),
              branches.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Gagal memuat cabang.'),
                data: (options) => DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ReportPage.branchFieldKey,
                  initialValue: draft.branchId,
                  decoration: const InputDecoration(labelText: 'Cabang'),
                  items: [
                    for (final option in options)
                      DropdownMenuItem(
                        value: option.id,
                        child: Text('${option.code} · ${option.name}'),
                      ),
                  ],
                  onChanged: controller.setBranch,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _PeriodFields(draft: draft),
            const SizedBox(height: AppSpacing.sm),
            categories.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Gagal memuat kategori.'),
              data: (options) => _CategoryChips(
                categories: options,
                selectedId: draft.filter.categoryId,
                onSelected: controller.setCategory,
              ),
            ),
            if (ReportFilterPolicy.supportsItemFilter(draft.reportType)) ...[
              const SizedBox(height: AppSpacing.sm),
              _ItemSearchField(
                required: draft.reportType.requiresItem,
                selectedId: draft.filter.itemId,
                onSelected: controller.setItem,
              ),
            ],
            if (ReportFilterPolicy.statusOptionsFor(
              draft.reportType,
            ).isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _StatusChips(draft: draft),
            ],
            if (ReportFilterPolicy.supportsDiscrepancyFilter(
              draft.reportType,
            )) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<GoodReceiptDiscrepancyFilter>(
                isExpanded: true,
                initialValue: draft.filter.discrepancy,
                decoration: const InputDecoration(labelText: 'Selisih'),
                items: [
                  for (final option in GoodReceiptDiscrepancyFilter.values)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: (value) {
                  if (value != null) controller.setDiscrepancy(value);
                },
              ),
            ],
            if (ReportFilterPolicy.supportsSearchText(draft.reportType)) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                initialValue: draft.filter.searchText,
                decoration: const InputDecoration(
                  labelText: 'Cari dokumen / barang / cabang',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: controller.setSearchText,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// §4.3's SearchableDropdown, over the report types this actor may run.
///
/// A search field **and** a dropdown, which is what the component name says: the
/// dropdown always offers the complete allowed list, and typing narrows it as you
/// go — case-insensitively, capped at [maxSearchResults], with *"Tidak ditemukan"*
/// when nothing matches. Entirely in memory: the eleven labels are an enum, so
/// there is nothing to query and nothing that can fail offline.
///
/// What it never does is widen the list. [options] is
/// [allowedReportTypesProvider]'s, which the access policy already filtered, so a
/// query can only remove entries the actor could already run (§45).
class _ReportTypeField extends StatefulWidget {
  const _ReportTypeField({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<ReportType> options;
  final ReportType selected;
  final ValueChanged<ReportType> onSelected;

  @override
  State<_ReportTypeField> createState() => _ReportTypeFieldState();
}

class _ReportTypeFieldState extends State<_ReportTypeField> {
  String _query = '';

  List<ReportType> get _matches {
    final needle = _query.trim().toLowerCase();
    final matched = needle.isEmpty
        ? widget.options
        : widget.options
              .where((type) => type.label.toLowerCase().contains(needle))
              .toList();
    return matched.take(maxSearchResults).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: ReportPage.reportTypeSearchKey,
          decoration: const InputDecoration(
            labelText: 'Cari jenis laporan',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (matches.isEmpty)
          const Padding(
            key: ReportPage.reportTypeEmptyKey,
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('Tidak ditemukan'),
          )
        else
          DropdownButtonFormField<ReportType>(
            isExpanded: true,
            key: ReportPage.reportTypeFieldKey,
            initialValue: matches.contains(widget.selected)
                ? widget.selected
                : null,
            decoration: const InputDecoration(labelText: 'Jenis Laporan'),
            items: [
              for (final type in matches)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: (value) {
              if (value != null) widget.onSelected(value);
            },
          ),
      ],
    );
  }
}

/// The location picker, which selects itself when there is only one choice.
///
/// A Petugas Warehouse has exactly one Warehouse Pusat and most nurses have one
/// room, so a required dropdown with a single entry is a step that exists only to
/// be completed. Selecting it after the frame settles keeps the filter form
/// meaningful — the *"Lengkapi filter"* message then means something is genuinely
/// missing rather than that the obvious answer has not been re-typed.
///
/// It widens nothing: the list it picks from is already
/// [reportLocationOptionsProvider]'s, which the access policy filtered, and the
/// preview and export use cases revalidate the choice against a re-read actor
/// regardless (§16).
class _LocationField extends StatefulWidget {
  const _LocationField({
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<MasterLocation> options;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  State<_LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<_LocationField> {
  @override
  void initState() {
    super.initState();
    _selectSoleOption();
  }

  @override
  void didUpdateWidget(_LocationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectSoleOption();
  }

  /// Deferred to after the frame, because a notifier may not be written to during
  /// a build.
  void _selectSoleOption() {
    if (widget.selectedId != null || widget.options.length != 1) return;
    final only = widget.options.single.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSelected(only);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        widget.options.any((option) => option.id == widget.selectedId)
        ? widget.selectedId
        : null;

    return DropdownButtonFormField<String>(
      isExpanded: true,
      key: ReportPage.locationFieldKey,
      initialValue: selected,
      decoration: const InputDecoration(labelText: 'Lokasi'),
      items: [
        for (final option in widget.options)
          DropdownMenuItem(value: option.id, child: Text(option.name)),
      ],
      onChanged: widget.onSelected,
    );
  }
}

/// One date for an as-of report, two for a range one (§15).
class _PeriodFields extends ConsumerWidget {
  const _PeriodFields({required this.draft});

  final ReportRequestDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(reportDraftProvider.notifier);
    if (draft.reportType.isAsOfReport) {
      return _DateField(
        label: 'Per tanggal',
        value: draft.periodEnd,
        onChanged: (value) => controller.setPeriod(end: value),
      );
    }
    return Row(
      children: [
        Expanded(
          child: _DateField(
            label: 'Dari',
            value: draft.periodStart,
            onChanged: (value) => controller.setPeriod(start: value),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _DateField(
            label: 'Sampai',
            value: draft.periodEnd,
            onChanged: (value) => controller.setPeriod(end: value),
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.utc(2020),
          lastDate: DateTime.utc(2100),
        );
        // The picker returns a *civil* date; `DateOnly.from` keeps its calendar
        // fields verbatim rather than converting them through the device zone (T-9).
        if (picked != null) onChanged(DateOnly.from(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text('${DateOnly.formatIso(value)} ${AppTimeZone.label}'),
      ),
    );
  }
}

/// §4.3's CategoryFilterChips, over the reporting draft.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<MasterCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: const Text('Semua'),
              selected: selectedId == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: ChoiceChip(
                label: Text(category.name),
                selected: selectedId == category.id,
                onSelected: (_) => onSelected(category.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChips extends ConsumerWidget {
  const _StatusChips({required this.draft});

  final ReportRequestDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(reportDraftProvider.notifier);
    final options = ReportFilterPolicy.statusOptionsFor(draft.reportType);
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        for (final option in options)
          FilterChip(
            label: Text(option.label),
            selected: draft.filter.statuses.contains(option.value),
            onSelected: (_) => controller.toggleStatus(option.value),
          ),
      ],
    );
  }
}

/// §4.3's SearchableDropdown: typeahead, case-insensitive, capped at eight, with
/// *"Tidak ditemukan"* when nothing matches. Entirely local — it queries Drift, so
/// it works offline like everything else in this module.
class _ItemSearchField extends ConsumerStatefulWidget {
  const _ItemSearchField({
    required this.required,
    required this.selectedId,
    required this.onSelected,
  });

  final bool required;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  ConsumerState<_ItemSearchField> createState() => _ItemSearchFieldState();
}

class _ItemSearchFieldState extends ConsumerState<_ItemSearchField> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = _query.trim().isEmpty
        ? const AsyncValue<List<MasterItem>>.data(<MasterItem>[])
        : ref.watch(reportItemSearchProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: ReportPage.itemFieldKey,
          decoration: InputDecoration(
            labelText: widget.required ? 'Barang (wajib)' : 'Barang (opsional)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: widget.selectedId == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() => _query = '');
                      widget.onSelected(null);
                    },
                  ),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        results.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('Gagal mencari barang.'),
          data: (items) {
            if (_query.trim().isEmpty) return const SizedBox.shrink();
            if (items.isEmpty) return const Text('Tidak ditemukan');
            return Column(
              children: [
                for (final item in items)
                  ListTile(
                    dense: true,
                    title: Text(item.name),
                    subtitle: Text(item.sku),
                    selected: item.id == widget.selectedId,
                    onTap: () {
                      setState(() => _query = '');
                      widget.onSelected(item.id);
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.danger.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
