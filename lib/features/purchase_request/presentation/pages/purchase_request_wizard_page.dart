import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../../../../core/time/date_only.dart';
import '../../../../core/widgets/status_card.dart';
import '../providers/purchase_request_providers.dart';
import '../widgets/eligible_opname_tile.dart';

/// Step 1 of the create wizard: **pilih stok opname** (§24.2).
///
/// The list offered here is already the eligible one — the actor's own branch,
/// `submitted`/`reviewed`, current or previous operational week (G-P1) — because
/// the query behind it says so. Nothing on this screen filters an ineligible count
/// out after fetching it, which is what keeps another branch's document from ever
/// being read.
///
/// Picking counts and creating the draft are one step rather than two screens with
/// a "next" in between: the suggestions cannot be computed until the citations are
/// known, so the second step *is* the draft. On success the wizard replaces itself
/// with the editor, so the back button returns to the list rather than to a wizard
/// whose draft already exists.
class PurchaseRequestWizardPage extends ConsumerStatefulWidget {
  const PurchaseRequestWizardPage({super.key});

  /// Lets tests address the screen without matching on prose.
  static const Key pageKey = ValueKey('purchaseRequestWizard');
  static const Key continueButtonKey = ValueKey(
    'purchaseRequestWizardContinue',
  );

  @override
  ConsumerState<PurchaseRequestWizardPage> createState() =>
      _PurchaseRequestWizardPageState();
}

class _PurchaseRequestWizardPageState
    extends ConsumerState<PurchaseRequestWizardPage> {
  final TextEditingController _noteController = TextEditingController();
  DateTime? _neededDate;

  /// Set after a rejected "Lanjut" so the empty selection is explained in place
  /// rather than only in a snack bar that has already gone.
  bool _selectionMissing = false;

  @override
  void initState() {
    super.initState();
    // Selection state is autoDispose but the wizard can be re-entered within one
    // frame of leaving it, so start from a clean slate explicitly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedOpnameIdsProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickNeededDate() async {
    // The picker works in civil dates: "today" is the operational day in GMT+8,
    // never the device's (T-3), and the chosen value is stored verbatim (T-8).
    final today = DateOnly.from(
      ref.read(currentPurchaseRequestPeriodProvider).mondayDate,
    );
    final initial = _neededDate ?? DateOnly.addDays(today, 7);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateOnly.addDays(today, -30),
      lastDate: DateOnly.addDays(today, 365),
    );
    if (picked == null || !mounted) return;
    setState(() => _neededDate = DateOnly.from(picked));
  }

  Future<void> _continue() async {
    final selected = ref.read(selectedOpnameIdsProvider);
    if (selected.isEmpty) {
      setState(() => _selectionMissing = true);
      _notify('Pilih minimal satu stok opname sebagai acuan permintaan.');
      return;
    }

    final note = _noteController.text.trim();
    final prId = await ref
        .read(createPurchaseRequestControllerProvider.notifier)
        .create(
          opnameIds: selected,
          neededDate: _neededDate,
          note: note.isEmpty ? null : note,
        );
    if (!mounted) return;

    if (prId == null) {
      _notify(
        describeFailure(
          ref.read(createPurchaseRequestControllerProvider).error ??
              'Gagal membuat Purchase Request.',
        ),
      );
      return;
    }

    ref.read(selectedOpnameIdsProvider.notifier).clear();
    // `pushReplacementNamed`, so the back button goes to the list rather than to
    // a wizard whose draft has already been created.
    context.pushReplacementNamed(
      AppRoutes.purchaseRequestEditName,
      pathParameters: {'id': prId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final eligible = ref.watch(eligibleOpnamesProvider);
    final selected = ref.watch(selectedOpnameIdsProvider);
    final creating = ref
        .watch(createPurchaseRequestControllerProvider)
        .isLoading;
    final periods = ref.watch(purchaseRequestEligiblePeriodsProvider);

    return Scaffold(
      key: PurchaseRequestWizardPage.pageKey,
      appBar: AppBar(title: const Text('Buat Purchase Request')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FilledButton.icon(
            key: PurchaseRequestWizardPage.continueButtonKey,
            onPressed: creating ? null : _continue,
            icon: creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward),
            label: Text(
              creating
                  ? 'Menyiapkan permintaan…'
                  : 'Lanjut: Tinjau & Sesuaikan',
            ),
          ),
        ),
      ),
      body: ListView(
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
                    const Text(
                      'Langkah 1 dari 2 — Pilih Stok Opname',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Permintaan harus mengacu pada minimal satu stok opname '
                      'yang sudah dikirim atau direview, dari minggu '
                      '${periods.map((week) => week.label).join(' atau ')}.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          eligible.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ErrorNotice(
                message: describeFailure(error),
                onRetry: () => ref.invalidate(eligibleOpnamesProvider),
              ),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Card(
                    key: ValueKey('eligibleOpnameEmptyState'),
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Belum ada stok opname yang dapat dijadikan '
                            'acuan',
                          ),
                          SizedBox(height: AppSpacing.sm),
                          Text(
                            'Stok opname harus berstatus Menunggu Review atau '
                            'Selesai Direview, dan berasal dari minggu '
                            'berjalan atau minggu sebelumnya.',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  if (_selectionMissing && selected.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Container(
                        key: const ValueKey('opnameSelectionRequired'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Text(
                          'Pilih minimal satu stok opname sebagai acuan '
                          'permintaan.',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ),
                  for (final reference in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: Card(
                        child: EligibleOpnameTile(
                          reference: reference,
                          selected: selected.contains(reference.opnameId),
                          onChanged: (_) {
                            setState(() => _selectionMissing = false);
                            ref
                                .read(selectedOpnameIdsProvider.notifier)
                                .toggle(reference.opnameId);
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Informasi permintaan',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ListTile(
                      key: const ValueKey('prNeededDatePicker'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Tanggal barang dibutuhkan'),
                      subtitle: Text(
                        _neededDate == null
                            ? 'Belum dipilih (opsional)'
                            : AppDateTimeFormatter.civilDate(_neededDate!),
                      ),
                      trailing: _neededDate == null
                          ? null
                          : IconButton(
                              tooltip: 'Hapus tanggal',
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _neededDate = null),
                            ),
                      onTap: _pickNeededDate,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      key: const ValueKey('prHeaderNote'),
                      controller: _noteController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Catatan permintaan (opsional)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
