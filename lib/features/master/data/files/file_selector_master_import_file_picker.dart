import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/gateways/master_import_gateways.dart';
import '../../domain/models/import_models.dart';
import '../../domain/services/master_import_normalization_policy.dart';
import '../../domain/services/master_import_workbook_validator.dart';

/// The production file picker (§27).
///
/// ### The only platform channel this milestone adds
///
/// Generating a template, parsing a workbook, validating every row, committing
/// in one transaction and writing the audit trail are all pure Dart over local
/// SQLite. This class and the share gateway talk to the OS, which is why both are
/// behind interfaces: every test in this milestone runs against a fake, and none
/// of them opens a real picker.
///
/// ### Why `file_selector` and not `file_picker`
///
/// A dependency conflict with a Windows-only transitive package, resolved in
/// favour of the option that changes nothing else. Every stable `file_picker`
/// requires `win32 ^5.9.0`; `share_plus` 13 — which this project has shipped
/// since Milestone 10 and whose Android plugin is what actually builds — requires
/// `win32 ^6.0.1`. Downgrading `share_plus` to the 12.x line resolves the
/// version solve and then fails to compile on Android, so it is not an option
/// either.
///
/// `file_selector` is the Flutter team's own document picker from
/// `flutter/packages`. It depends on no `win32` at all, so both packages coexist
/// at their current versions, no `dependency_override` is needed, and the
/// Milestone 10 reporting stack is untouched.
///
/// ### No storage permission
///
/// An `XTypeGroup` restricted to one extension opens the platform's **document**
/// picker, which hands back a file the user explicitly chose. That is not gallery
/// access and not a media scan, so there is no `READ_EXTERNAL_STORAGE`, no
/// `READ_MEDIA_*` and no permission prompt — the same story the share sheet has.
///
/// ### Cancellation is not a failure
///
/// `null` means the user dismissed the picker. A screen that showed them an error
/// for changing their mind would be wrong, so this returns rather than throws.
class FileSelectorMasterImportFilePicker implements MasterImportFilePicker {
  const FileSelectorMasterImportFilePicker();

  /// One group, one extension. `openFile` is single-selection by construction —
  /// §27 asks for one file, and a multi-select would make "which of these did you
  /// mean" a question the domain would have to answer.
  static const XTypeGroup _xlsxGroup = XTypeGroup(
    label: 'Excel (.xlsx)',
    extensions: <String>['xlsx'],
    // The MIME type Android's document picker filters on. Without it the picker
    // shows every file and the extension check below is doing all the work.
    mimeTypes: <String>[
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ],
    uniformTypeIdentifiers: <String>['org.openxmlformats.spreadsheetml.sheet'],
  );

  @override
  Future<PickedImportFile?> pickWorkbook() async {
    final XFile? picked;
    try {
      picked = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[_xlsxGroup],
        confirmButtonText: 'Pilih',
      );
    } catch (_) {
      throw const ImportUnsupportedFileFailure(
        'Pemilih file tidak dapat dibuka. Coba lagi, atau pastikan aplikasi '
        'memiliki akses untuk membuka dokumen.',
        fileName: '',
      );
    }

    if (picked == null) return null;

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      throw ImportFileEmptyFailure(
        'File yang dipilih tidak dapat dibaca. Coba pilih ulang.',
        fileName: picked.name,
      );
    }

    if (bytes.isEmpty) {
      throw ImportFileEmptyFailure(
        'File yang dipilih kosong. Pastikan file template sudah terisi lalu '
        'coba lagi.',
        fileName: picked.name,
      );
    }
    if (bytes.length > MasterImportLimits.maxFileBytes) {
      throw ImportFileTooLargeFailure(
        'Ukuran file melebihi batas ${MasterImportLimits.maxFileSizeLabel}. '
        'Pecah data menjadi beberapa file lalu impor bergantian.',
        fileName: picked.name,
        sizeBytes: bytes.length,
        maxBytes: MasterImportLimits.maxFileBytes,
      );
    }

    final file = PickedImportFile(originalFileName: picked.name, bytes: bytes);

    // The platform filter is a convenience, not a guarantee: several Android
    // document providers ignore the type group entirely. The extension is
    // therefore re-checked here, and checked a third time by the validate use
    // case — the picker is a UI affordance, not the boundary.
    MasterImportWorkbookValidator.ensureSupportedExtension(file);
    MasterImportWorkbookValidator.ensureWithinSizeLimit(file);

    return file;
  }
}
