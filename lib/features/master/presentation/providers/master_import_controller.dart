import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure_presenter.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../domain/models/import_models.dart';
import '../../domain/models/master_admin_models.dart';
import 'master_admin_providers.dart';

/// Which rows the preview table is showing (§42).
enum ImportPreviewRowFilter {
  all,
  valid,
  error,
  insert,
  update;

  String get label => switch (this) {
    all => 'Semua',
    valid => 'Valid',
    error => 'Error',
    insert => 'Tambah',
    update => 'Perbarui',
  };

  bool matches(ImportRowPreview row) => switch (this) {
    all => true,
    valid => row.isValid,
    error => !row.isValid,
    insert => row.action == ImportRowAction.insert,
    update => row.action == ImportRowAction.update,
  };
}

/// The import screen's whole state, in one immutable value.
class MasterImportState {
  const MasterImportState({
    this.entity = MasterEntityType.items,
    this.pickedFileName,
    this.pickedSizeBytes,
    this.session,
    this.isBusy = false,
    this.busyLabel,
    this.errorMessage,
    this.infoMessage,
    this.commitResult,
    this.rowFilter = ImportPreviewRowFilter.all,
    this.rowQuery = '',
  });

  final MasterEntityType entity;

  /// The name and size the operator picked, shown before validation runs (§42).
  final String? pickedFileName;
  final int? pickedSizeBytes;

  /// The validated preview, or `null` when there is none.
  final ImportPreviewSession? session;

  final bool isBusy;
  final String? busyLabel;

  /// Indonesian, always. Never a path, an exception string or a stack trace
  /// (§45) — everything here comes through [describeFailure].
  final String? errorMessage;

  final String? infoMessage;

  /// Set once a commit succeeds. The preview becomes read-only (§43).
  final ImportCommitResult? commitResult;

  final ImportPreviewRowFilter rowFilter;
  final String rowQuery;

  bool get hasPreview => session != null;

  bool get isFinalised => commitResult != null;

  /// G-M3, expressed once: total > 0, zero errors, still `validated`, and no
  /// commit in flight. The button reads this rather than deciding for itself, so
  /// a screen cannot enable something the use case would refuse (§42).
  bool get canCommit =>
      !isBusy && !isFinalised && session != null && session!.canCommit;

  bool get canDiscard => !isBusy && !isFinalised && session != null;

  List<ImportRowPreview> get visibleRows {
    final rows = session?.rows ?? const <ImportRowPreview>[];
    final needle = rowQuery.trim().toLowerCase();
    return rows
        .where(rowFilter.matches)
        .where(
          (row) =>
              needle.isEmpty ||
              row.naturalKeyDisplay.toLowerCase().contains(needle) ||
              '${row.rowNumber}'.contains(needle),
        )
        .toList(growable: false);
  }

  MasterImportState copyWith({
    MasterEntityType? entity,
    String? pickedFileName,
    int? pickedSizeBytes,
    bool clearPickedFile = false,
    ImportPreviewSession? session,
    bool clearSession = false,
    bool? isBusy,
    String? busyLabel,
    String? errorMessage,
    bool clearError = false,
    String? infoMessage,
    bool clearInfo = false,
    ImportCommitResult? commitResult,
    bool clearCommitResult = false,
    ImportPreviewRowFilter? rowFilter,
    String? rowQuery,
  }) => MasterImportState(
    entity: entity ?? this.entity,
    pickedFileName: clearPickedFile
        ? null
        : (pickedFileName ?? this.pickedFileName),
    pickedSizeBytes: clearPickedFile
        ? null
        : (pickedSizeBytes ?? this.pickedSizeBytes),
    session: clearSession ? null : (session ?? this.session),
    isBusy: isBusy ?? this.isBusy,
    busyLabel: (isBusy ?? this.isBusy) ? (busyLabel ?? this.busyLabel) : null,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
    commitResult: clearCommitResult
        ? null
        : (commitResult ?? this.commitResult),
    rowFilter: rowFilter ?? this.rowFilter,
    rowQuery: rowQuery ?? this.rowQuery,
  );
}

/// Drives the import screen (§42, §43).
///
/// ### Every operation is guarded against a dead controller
///
/// The five async operations here all check [ref.mounted] before writing state,
/// so a page disposed mid-validation neither throws nor writes into a controller
/// nobody is watching (§43). What has already reached the database stays there —
/// the audit row is a fact, and the operator finds it in the history.
///
/// ### A new file never silently replaces a validated preview
///
/// [pickFile] refuses while a preview is unconsumed and says so. The operator
/// commits it, discards it, or explicitly starts over ([startOver]) — because a
/// validated import already has an audit row and a retained source file, and
/// silently abandoning it would leave both with nothing on screen explaining
/// them.
class MasterImportController extends Notifier<MasterImportState> {
  @override
  MasterImportState build() => const MasterImportState();

  /// The acting user's id, **awaited**.
  ///
  /// `ref.read(masterAdminActorIdProvider)` is a synchronous snapshot of an
  /// asynchronous provider, and on a tab nothing else has read it from, that
  /// snapshot is `loading` — so a button tapped on a freshly-opened screen would
  /// silently do nothing. Awaiting the future is what makes the first tap work.
  ///
  /// Returns `null` when there is no session, or when the controller was disposed
  /// while the actor was resolving.
  Future<String?> _resolveActorId() async {
    final actor = await ref.read(actingUserProvider.future);
    if (!ref.mounted) return null;
    return actor?.id;
  }

  void selectEntity(MasterEntityType entity) {
    if (state.entity == entity) return;
    // Changing entity clears the picked file but **not** a validated preview:
    // that preview belongs to the entity it was validated for, and dropping it
    // silently is the thing this controller refuses to do.
    if (state.hasPreview && !state.isFinalised) {
      state = state.copyWith(
        errorMessage:
            'Selesaikan dulu pratinjau ${state.entity.label} yang aktif — '
            'terapkan atau batalkan — sebelum berpindah entitas.',
      );
      return;
    }
    state = MasterImportState(entity: entity);
  }

  void setRowFilter(ImportPreviewRowFilter filter) =>
      state = state.copyWith(rowFilter: filter);

  void setRowQuery(String query) => state = state.copyWith(rowQuery: query);

  void dismissMessages() =>
      state = state.copyWith(clearError: true, clearInfo: true);

  /// Clears the screen without touching anything already recorded.
  ///
  /// The audit row and the retained file stay: an import that was validated
  /// happened, whatever the operator does with the screen afterwards (§3.3).
  void startOver() => state = MasterImportState(entity: state.entity);

  Future<void> downloadTemplate() async {
    if (state.isBusy) return;
    final actorId = await _resolveActorId();
    if (!ref.mounted) return;
    if (actorId == null) return;

    state = state.copyWith(
      isBusy: true,
      busyLabel: 'Menyiapkan template…',
      clearError: true,
      clearInfo: true,
    );
    try {
      final result = await ref
          .read(downloadTemplateUseCaseProvider)
          .call(actorUserId: actorId, entity: state.entity);
      if (!ref.mounted) return;
      state = state.copyWith(
        isBusy: false,
        infoMessage: switch (result.shareOutcome) {
          // Never *"tersimpan di Downloads"* — the file is in app-private
          // storage, which is why no permission was needed to write it (§26).
          MasterTemplateShareOutcome.shared =>
            'Template ${result.artifact.fileName} siap dibagikan.',
          MasterTemplateShareOutcome.cancelled =>
            'Template ${result.artifact.fileName} sudah dibuat dan siap '
                'dibagikan kapan saja.',
          MasterTemplateShareOutcome.unavailable =>
            'Template ${result.artifact.fileName} sudah dibuat. Berbagi file '
                'tidak tersedia di perangkat ini.',
        },
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isBusy: false,
        errorMessage: describeFailure(error),
      );
    }
  }

  Future<void> pickAndValidate() async {
    if (state.isBusy) return;
    final actorId = await _resolveActorId();
    if (!ref.mounted) return;
    if (actorId == null) return;

    if (state.hasPreview && !state.isFinalised) {
      state = state.copyWith(
        errorMessage:
            'Masih ada pratinjau yang belum diproses. Terapkan atau batalkan '
            'pratinjau tersebut sebelum mengunggah file lain.',
      );
      return;
    }

    state = state.copyWith(
      isBusy: true,
      busyLabel: 'Membuka file…',
      clearError: true,
      clearInfo: true,
    );

    try {
      final picked = await ref
          .read(masterImportFilePickerProvider)
          .pickWorkbook();
      if (!ref.mounted) return;
      if (picked == null) {
        // A cancelled picker is an outcome, not an error (§27).
        state = state.copyWith(isBusy: false);
        return;
      }

      state = state.copyWith(
        isBusy: true,
        busyLabel: 'Memvalidasi ${picked.originalFileName}…',
        pickedFileName: picked.originalFileName,
        pickedSizeBytes: picked.sizeBytes,
      );

      final session = await ref
          .read(validateImportUseCaseProvider)
          .call(actorUserId: actorId, entity: state.entity, file: picked);
      if (!ref.mounted) return;

      state = state.copyWith(
        isBusy: false,
        session: session,
        clearCommitResult: true,
        rowFilter: session.summary.hasErrors
            ? ImportPreviewRowFilter.error
            : ImportPreviewRowFilter.all,
      );
      ref.invalidate(importHistoryFilterProvider);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isBusy: false,
        clearPickedFile: true,
        errorMessage: describeFailure(error),
      );
    }
  }

  Future<void> commit() async {
    if (state.isBusy) return;
    final actorId = await _resolveActorId();
    if (!ref.mounted) return;
    final session = state.session;
    if (actorId == null || session == null || !state.canCommit) return;

    state = state.copyWith(
      isBusy: true,
      busyLabel: 'Menerapkan impor…',
      clearError: true,
      clearInfo: true,
    );
    try {
      final result = await ref
          .read(commitImportUseCaseProvider)
          .call(actorUserId: actorId, importLogId: session.importId);
      if (!ref.mounted) return;
      state = state.copyWith(
        isBusy: false,
        commitResult: result,
        infoMessage:
            'Impor diterapkan: ${result.insertedRows} data baru, '
            '${result.updatedRows} data diperbarui.',
      );
      _invalidateMasterReads();
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isBusy: false,
        errorMessage: describeFailure(error),
      );
    }
  }

  Future<void> discard() async {
    if (state.isBusy) return;
    final actorId = await _resolveActorId();
    if (!ref.mounted) return;
    final session = state.session;
    if (actorId == null || session == null || !state.canDiscard) return;

    state = state.copyWith(
      isBusy: true,
      busyLabel: 'Membatalkan impor…',
      clearError: true,
      clearInfo: true,
    );
    try {
      await ref
          .read(discardImportUseCaseProvider)
          .call(actorUserId: actorId, importLogId: session.importId);
      if (!ref.mounted) return;
      state = MasterImportState(
        entity: state.entity,
        infoMessage:
            'Impor dibatalkan. Tidak ada data master yang berubah, dan file '
            'sumber tetap tersimpan untuk audit.',
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isBusy: false,
        errorMessage: describeFailure(error),
      );
    }
  }

  /// Every master read the commit may have changed.
  ///
  /// The dashboard and the six lists are `autoDispose` families, so invalidating
  /// the whole family is the cheap and correct move: a list still on screen
  /// refetches, and one that is not simply never rebuilds.
  void _invalidateMasterReads() {
    ref.invalidate(masterDashboardProvider);
    ref.invalidate(masterBranchListProvider);
    ref.invalidate(masterRoomListProvider);
    ref.invalidate(masterUserListProvider);
    ref.invalidate(masterCategoryListProvider);
    ref.invalidate(masterItemListProvider);
    ref.invalidate(masterBatchListProvider);
  }
}

/// The import screen's controller.
///
/// `autoDispose`, so leaving the screen releases the preview — and with it the
/// only reference this application keeps to the workbook's parsed rows. The
/// bytes themselves were released the moment validation finished: the use case
/// holds none, and the retained copy lives on disk (§43).
final masterImportControllerProvider =
    NotifierProvider.autoDispose<MasterImportController, MasterImportState>(
      MasterImportController.new,
    );
