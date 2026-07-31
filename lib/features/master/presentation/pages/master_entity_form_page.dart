/// The six master forms (§41).
///
/// ### Three rules every form here follows
///
/// **A natural-key field is editable on create and read-only on edit.** Not
/// hidden — an administrator has to be able to *see* which item they are editing —
/// and always with the reason beside it, so a greyed-out SKU reads as a rule
/// rather than a bug.
///
/// **A historically protected field is disabled only when the policy says so.**
/// [ItemFormPolicy] is asked, not guessed: an item nobody has moved has an
/// editable unit, and the same item after one movement does not. The reason shown
/// is the reason the use case would throw.
///
/// **The use case still enforces every one of them.** A disabled field is a
/// courtesy, and §37 is explicit that the guard is not the boundary — a form
/// assembled by a test, or a future screen that forgets, still hits the same
/// refusal.
///
/// There is no delete button anywhere in this file, and no wording that promises
/// one (§41).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/time/date_only.dart';
import '../../domain/models/master_admin_models.dart';
import '../../domain/models/master_models.dart';
import '../../domain/services/master_historical_integrity_policy.dart';
import '../../domain/services/master_user_role_policy.dart';
import '../../domain/use_cases/batch_crud_use_cases.dart';
import '../../domain/use_cases/item_crud_use_cases.dart';
import '../providers/master_admin_providers.dart';

/// One form, parameterised by entity and by whether a row is being created.
class MasterEntityFormPage extends ConsumerStatefulWidget {
  const MasterEntityFormPage({super.key, required this.entity, this.entityId});

  final MasterEntityType entity;

  /// `null` on create.
  final String? entityId;

  bool get isCreating => entityId == null;

  @override
  ConsumerState<MasterEntityFormPage> createState() =>
      _MasterEntityFormPageState();
}

class _MasterEntityFormPageState extends ConsumerState<MasterEntityFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};

  UserRole _role = UserRole.perawat;
  String? _branchId;
  String? _categoryId;
  String? _itemId;
  bool _isActive = true;
  bool _hasExpiry = false;
  DateTime _expiryDate = DateOnly.from(DateTime.now().toUtc());

  bool _isSaving = false;
  bool _loaded = false;
  String? _errorMessage;

  MasterItem? _currentItem;
  MasterHistoricalUsage _usage = const MasterHistoricalUsage.none();
  int _batchCount = 0;

  @override
  void initState() {
    super.initState();
    for (final header in widget.entity.headers) {
      _fields[header] = TextEditingController();
    }
    if (!widget.isCreating) {
      // Loaded after the first frame so the provider container is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _loaded = true;
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repository = ref.read(masterAdminRepositoryProvider);
    final id = widget.entityId!;
    switch (widget.entity) {
      case MasterEntityType.branches:
        final row = await repository.branchById(id);
        if (row == null || !mounted) return;
        _fields['code']!.text = row.code;
        _fields['name']!.text = row.name;
        _fields['address']!.text = row.address ?? '';
        _isActive = row.isActive;
      case MasterEntityType.rooms:
        final row = await repository.roomById(id);
        if (row == null || !mounted) return;
        _fields['code']!.text = row.code;
        _fields['name']!.text = row.name;
        _branchId = row.branchId;
        _isActive = row.isActive;
      case MasterEntityType.users:
        final row = await repository.adminUserById(id);
        if (row == null || !mounted) return;
        _fields['full_name']!.text = row.fullName;
        _fields['email']!.text = row.email;
        _role = row.role;
        _branchId = row.branchId;
        _isActive = row.isActive;
      case MasterEntityType.itemCategories:
        final row = await repository.categoryById(id);
        if (row == null || !mounted) return;
        _fields['name']!.text = row.name;
      case MasterEntityType.items:
        final row = await repository.itemById(id);
        if (row == null || !mounted) return;
        _currentItem = row;
        _fields['sku']!.text = row.sku;
        _fields['name']!.text = row.name;
        _fields['unit']!.text = row.unit;
        _fields['min_stock_room']!.text = '${row.minStockRoom}';
        _fields['min_stock_branch']!.text = '${row.minStockBranch}';
        _fields['expiry_alert_days']!.text = '${row.expiryAlertDays}';
        _categoryId = row.categoryId;
        _hasExpiry = row.hasExpiry;
        _isActive = row.isActive;
        _usage = await repository.usageForItem(id);
        _batchCount = (await repository.batchCountsForItems([id]))[id] ?? 0;
      case MasterEntityType.itemBatches:
        final row = await repository.batchById(id);
        if (row == null || !mounted) return;
        _fields['batch_no']!.text = row.batchNo;
        _itemId = row.itemId;
        _expiryDate = row.expiryDate;
        _usage = await repository.usageForBatch(id);
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final title =
        '${widget.isCreating ? 'Tambah' : 'Ubah'} ${widget.entity.label}';

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorMessage!,
                  key: const Key('master-form-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ..._fieldsFor(context),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('master-form-submit'),
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  // --- field builders -----------------------------------------------------------

  List<Widget> _fieldsFor(BuildContext context) => switch (widget.entity) {
    MasterEntityType.branches => [
      _naturalKeyField('code', 'Kode cabang'),
      _textField('name', 'Nama cabang', required: true),
      _textField('address', 'Alamat'),
      _activeSwitch(),
    ],
    MasterEntityType.rooms => [
      _branchPicker(
        decision: widget.isCreating
            ? const MasterWriteDecision.allowed()
            : MasterWriteDecision.refused(
                field: 'branch_id',
                reason:
                    'Ruangan tidak dapat dipindahkan ke cabang lain. Buat '
                    'ruangan baru di cabang tujuan lalu nonaktifkan yang ini.',
              ),
      ),
      _naturalKeyField('code', 'Kode ruangan'),
      _textField('name', 'Nama ruangan', required: true),
      _activeSwitch(),
    ],
    MasterEntityType.users => [
      _textField('full_name', 'Nama lengkap', required: true),
      _naturalKeyField('email', 'Email'),
      _rolePicker(),
      // The branch picker is cleared and disabled the moment an unscoped role is
      // chosen, so the form cannot submit a pair §21 would refuse.
      if (MasterUserRolePolicy.requiresBranch(_role))
        _branchPicker(decision: const MasterWriteDecision.allowed())
      else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            MasterUserRolePolicy.branchRequirementLabel(_role),
            key: const Key('user-form-branch-hint'),
          ),
        ),
      _activeSwitch(enabled: _canChangeOwnStatus()),
    ],
    MasterEntityType.itemCategories => [
      _naturalKeyField('name', 'Nama kategori'),
    ],
    MasterEntityType.items => _itemFields(),
    MasterEntityType.itemBatches => [
      _itemPicker(),
      _naturalKeyField('batch_no', 'Nomor batch'),
      _expiryDateField(),
    ],
  };

  List<Widget> _itemFields() {
    final decisions = ItemFormPolicy.decisionsFor(
      isCreating: widget.isCreating,
      current: _currentItem,
      usage: _usage,
      batchCount: _batchCount,
    );
    return [
      _naturalKeyField('sku', 'SKU'),
      _textField('name', 'Nama barang', required: true),
      _categoryPicker(decisions['category_id']),
      _textField('unit', 'Satuan', required: true, decision: decisions['unit']),
      _intField('min_stock_room', 'Stok minimum ruangan'),
      _intField('min_stock_branch', 'Stok minimum cabang'),
      _expirySwitch(decisions['has_expiry']),
      _intField('expiry_alert_days', 'Ambang peringatan (hari)'),
      _activeSwitch(),
    ];
  }

  /// A natural-key field: editable on create, read-only afterwards (§41).
  Widget _naturalKeyField(String name, String label) {
    final readOnly = !widget.isCreating;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        key: Key('master-form-$name'),
        controller: _fields[name],
        readOnly: readOnly,
        enabled: !readOnly,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          helperMaxLines: 3,
          helperText: readOnly
              ? MasterHistoricalIntegrityPolicy.naturalKeyImmutableNotice
              : null,
        ),
        validator: (value) =>
            (value ?? '').trim().isEmpty ? '$label wajib diisi.' : null,
      ),
    );
  }

  Widget _textField(
    String name,
    String label, {
    bool required = false,
    MasterWriteDecision? decision,
  }) {
    final locked = decision?.isRefused ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        key: Key('master-form-$name'),
        controller: _fields[name],
        readOnly: locked,
        enabled: !locked,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          helperMaxLines: 4,
          helperText: decision?.reason,
        ),
        validator: (value) => required && (value ?? '').trim().isEmpty
            ? '$label wajib diisi.'
            : null,
      ),
    );
  }

  Widget _intField(String name, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      key: Key('master-form-$name'),
      controller: _fields[name],
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final parsed = int.tryParse((value ?? '').trim());
        if (parsed == null) return '$label harus berupa bilangan bulat.';
        if (parsed < 0) return '$label tidak boleh negatif.';
        return null;
      },
    ),
  );

  Widget _activeSwitch({bool enabled = true}) => SwitchListTile(
    key: const Key('master-form-is-active'),
    value: _isActive,
    onChanged: enabled ? (value) => setState(() => _isActive = value) : null,
    title: const Text('Aktif'),
    subtitle: Text(
      enabled
          ? 'Data nonaktif tidak dapat dipilih pada dokumen baru, tetapi '
                'riwayatnya tetap tersimpan.'
          : 'Anda tidak dapat menonaktifkan akun Anda sendiri.',
    ),
  );

  Widget _expirySwitch(MasterWriteDecision? decision) {
    final locked = decision?.isRefused ?? false;
    return SwitchListTile(
      key: const Key('master-form-has-expiry'),
      value: _hasExpiry,
      onChanged: locked ? null : (value) => setState(() => _hasExpiry = value),
      title: const Text('Dilacak per batch (ber-kedaluwarsa)'),
      subtitle: Text(
        decision?.reason ??
            'Barang ber-kedaluwarsa wajib mencantumkan batch pada setiap '
                'pergerakan stok.',
      ),
    );
  }

  Widget _rolePicker() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<UserRole>(
      key: const Key('master-form-role'),
      initialValue: _role,
      decoration: const InputDecoration(
        labelText: 'Peran',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final role in UserRole.values)
          DropdownMenuItem(value: role, child: Text(role.label)),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _role = value;
          // Cleared the moment the role forbids one, so the invariant holds
          // before the form is even submitted (§21).
          if (!MasterUserRolePolicy.requiresBranch(value)) _branchId = null;
        });
      },
    ),
  );

  Widget _branchPicker({required MasterWriteDecision decision}) {
    final branches = ref.watch(
      masterBranchListProvider(const MasterListFilter()),
    );
    return branches.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Daftar cabang gagal dimuat.'),
      data: (views) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          key: const Key('master-form-branch'),
          initialValue: views.any((view) => view.branch.id == _branchId)
              ? _branchId
              : null,
          decoration: InputDecoration(
            labelText: 'Cabang',
            border: const OutlineInputBorder(),
            helperMaxLines: 4,
            helperText: decision.reason,
          ),
          items: [
            for (final view in views)
              DropdownMenuItem(
                value: view.branch.id,
                child: Text('${view.branch.code} · ${view.branch.name}'),
              ),
          ],
          onChanged: decision.isRefused
              ? null
              : (value) => setState(() => _branchId = value),
          validator: (value) =>
              MasterUserRolePolicy.requiresBranch(_role) &&
                  widget.entity == MasterEntityType.users &&
                  value == null
              ? 'Cabang wajib dipilih untuk peran ini.'
              : (widget.entity == MasterEntityType.rooms && value == null
                    ? 'Cabang wajib dipilih.'
                    : null),
        ),
      ),
    );
  }

  Widget _categoryPicker(MasterWriteDecision? decision) {
    final categories = ref.watch(
      masterCategoryListProvider(const MasterListFilter()),
    );
    final locked = decision?.isRefused ?? false;
    return categories.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Daftar kategori gagal dimuat.'),
      data: (views) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          key: const Key('master-form-category'),
          initialValue: views.any((view) => view.category.id == _categoryId)
              ? _categoryId
              : null,
          decoration: InputDecoration(
            labelText: 'Kategori',
            border: const OutlineInputBorder(),
            helperMaxLines: 4,
            helperText: decision?.reason,
          ),
          items: [
            for (final view in views)
              DropdownMenuItem(
                value: view.category.id,
                child: Text(view.category.name),
              ),
          ],
          onChanged: locked
              ? null
              : (value) => setState(() => _categoryId = value),
          validator: (value) =>
              value == null ? 'Kategori wajib dipilih.' : null,
        ),
      ),
    );
  }

  /// Only expiry-tracked items may hold a batch (§41, §14.6).
  Widget _itemPicker() {
    final items = ref.watch(
      masterItemListProvider(const MasterListFilter(hasExpiry: true)),
    );
    final decision = BatchFormPolicy.itemDecision(
      isCreating: widget.isCreating,
    );
    return items.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Daftar barang gagal dimuat.'),
      data: (views) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          key: const Key('master-form-item'),
          initialValue: views.any((view) => view.item.id == _itemId)
              ? _itemId
              : null,
          decoration: InputDecoration(
            labelText: 'Barang (hanya yang ber-kedaluwarsa)',
            border: const OutlineInputBorder(),
            helperMaxLines: 4,
            helperText: decision.reason,
          ),
          items: [
            for (final view in views)
              DropdownMenuItem(
                value: view.item.id,
                child: Text('${view.item.sku} · ${view.item.name}'),
              ),
          ],
          onChanged: decision.isRefused
              ? null
              : (value) => setState(() => _itemId = value),
          validator: (value) => value == null ? 'Barang wajib dipilih.' : null,
        ),
      ),
    );
  }

  Widget _expiryDateField() {
    final decision = BatchFormPolicy.expiryDecision(
      isCreating: widget.isCreating,
      usage: _usage,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        key: const Key('master-form-expiry-date'),
        title: const Text('Tanggal kedaluwarsa'),
        subtitle: Text(
          decision.isRefused
              ? '${DateOnly.formatIso(_expiryDate)} — ${decision.reason}'
              : DateOnly.formatIso(_expiryDate),
        ),
        trailing: const Icon(Icons.calendar_today),
        enabled: !decision.isRefused,
        onTap: decision.isRefused
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _expiryDate,
                  firstDate: DateTime.utc(2000),
                  lastDate: DateTime.utc(2100),
                );
                if (picked == null || !mounted) return;
                // A civil date: the calendar fields verbatim, never converted
                // (T-8).
                setState(() => _expiryDate = DateOnly.from(picked));
              },
      ),
    );
  }

  bool _canChangeOwnStatus() {
    if (widget.entity != MasterEntityType.users || widget.isCreating) {
      return true;
    }
    final actorId = ref.read(masterAdminActorIdProvider);
    return actorId == null || actorId != widget.entityId;
  }

  // --- submit ---------------------------------------------------------------------

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final actorId = ref.read(masterAdminActorIdProvider);
    if (actorId == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _performWrite(actorId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.entity.label} disimpan.')),
      );
      _invalidateLists();
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      // Never an exception string, a table name or a path (§45).
      setState(() => _errorMessage = describeFailure(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _performWrite(String actorId) async {
    final id = widget.entityId;
    switch (widget.entity) {
      case MasterEntityType.branches:
        if (widget.isCreating) {
          await ref
              .read(createBranchUseCaseProvider)
              .call(
                actorUserId: actorId,
                code: _fields['code']!.text,
                name: _fields['name']!.text,
                address: _fields['address']!.text,
                isActive: _isActive,
              );
        } else {
          await ref
              .read(updateBranchUseCaseProvider)
              .call(
                actorUserId: actorId,
                branchId: id!,
                name: _fields['name']!.text,
                address: _fields['address']!.text,
                isActive: _isActive,
              );
        }
      case MasterEntityType.rooms:
        if (widget.isCreating) {
          await ref
              .read(createRoomUseCaseProvider)
              .call(
                actorUserId: actorId,
                branchId: _branchId!,
                code: _fields['code']!.text,
                name: _fields['name']!.text,
                isActive: _isActive,
              );
        } else {
          await ref
              .read(updateRoomUseCaseProvider)
              .call(
                actorUserId: actorId,
                roomId: id!,
                name: _fields['name']!.text,
                isActive: _isActive,
              );
        }
      case MasterEntityType.users:
        if (widget.isCreating) {
          await ref
              .read(createUserUseCaseProvider)
              .call(
                actorUserId: actorId,
                fullName: _fields['full_name']!.text,
                email: _fields['email']!.text,
                role: _role,
                branchId: _branchId,
                isActive: _isActive,
              );
        } else {
          await ref
              .read(updateUserUseCaseProvider)
              .call(
                actorUserId: actorId,
                userId: id!,
                fullName: _fields['full_name']!.text,
                role: _role,
                branchId: _branchId,
                isActive: _isActive,
              );
        }
      case MasterEntityType.itemCategories:
        // Create only: a category's name is its identity, so there is no rename
        // path at all (§20.7). The form is not offered for an existing row.
        await ref
            .read(createCategoryUseCaseProvider)
            .call(actorUserId: actorId, name: _fields['name']!.text);
      case MasterEntityType.items:
        if (widget.isCreating) {
          await ref
              .read(createItemUseCaseProvider)
              .call(
                actorUserId: actorId,
                sku: _fields['sku']!.text,
                name: _fields['name']!.text,
                categoryId: _categoryId!,
                unit: _fields['unit']!.text,
                minStockRoom: int.parse(_fields['min_stock_room']!.text),
                minStockBranch: int.parse(_fields['min_stock_branch']!.text),
                hasExpiry: _hasExpiry,
                expiryAlertDays: int.parse(_fields['expiry_alert_days']!.text),
                isActive: _isActive,
              );
        } else {
          await ref
              .read(updateItemUseCaseProvider)
              .call(
                actorUserId: actorId,
                itemId: id!,
                name: _fields['name']!.text,
                categoryId: _categoryId!,
                unit: _fields['unit']!.text,
                minStockRoom: int.parse(_fields['min_stock_room']!.text),
                minStockBranch: int.parse(_fields['min_stock_branch']!.text),
                hasExpiry: _hasExpiry,
                expiryAlertDays: int.parse(_fields['expiry_alert_days']!.text),
                isActive: _isActive,
              );
        }
      case MasterEntityType.itemBatches:
        if (widget.isCreating) {
          await ref
              .read(createBatchUseCaseProvider)
              .call(
                actorUserId: actorId,
                itemId: _itemId!,
                batchNo: _fields['batch_no']!.text,
                expiryDate: _expiryDate,
              );
        } else {
          await ref
              .read(updateBatchUseCaseProvider)
              .call(
                actorUserId: actorId,
                batchId: id!,
                expiryDate: _expiryDate,
              );
        }
    }
  }

  void _invalidateLists() {
    ref.invalidate(masterDashboardProvider);
    switch (widget.entity) {
      case MasterEntityType.branches:
        ref.invalidate(masterBranchListProvider);
      case MasterEntityType.rooms:
        ref.invalidate(masterRoomListProvider);
      case MasterEntityType.users:
        ref.invalidate(masterUserListProvider);
      case MasterEntityType.itemCategories:
        ref.invalidate(masterCategoryListProvider);
      case MasterEntityType.items:
        ref.invalidate(masterItemListProvider);
      case MasterEntityType.itemBatches:
        ref.invalidate(masterBatchListProvider);
    }
  }
}
