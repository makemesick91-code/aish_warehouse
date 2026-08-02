/// Test doubles for the four boundaries the reporting domain cannot cross in a
/// unit test: rendering, writing and sharing.
///
/// Every one of them records what it was asked to do, because most of the export
/// assertions are about *ordering* — was the share sheet opened after the audit
/// row, was the file deleted when the audit failed — and an assertion about
/// ordering needs something that remembers.
library;

import 'dart:typed_data';

import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/reports/domain/gateways/report_gateways.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:aish_warehouse/features/reports/domain/repositories/reporting_repository.dart';

/// A stand-in for the real workbook writer.
///
/// Produces bytes beginning with the ZIP magic an `.xlsx` really starts with, so a
/// test asserting *"the artifact looks like a spreadsheet"* is asserting the same
/// thing about the fake and the real exporter.
class FakeExcelReportExporter implements ReportExcelExporter {
  const FakeExcelReportExporter();

  @override
  Future<Uint8List> export(ReportDocument document) async =>
      Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...document.title.codeUnits]);
}

/// A stand-in for the real PDF writer, producing the `%PDF` magic.
class FakePdfReportExporter implements ReportPdfExporter {
  const FakePdfReportExporter();

  @override
  Future<Uint8List> export(ReportDocument document) async => Uint8List.fromList(
    [...'%PDF-1.7\n'.codeUnits, ...document.title.codeUnits],
  );
}

/// An exporter that always fails, for the *"generation fails → no file, no log,
/// no share"* row of §36's table.
class FailingExcelReportExporter implements ReportExcelExporter {
  const FailingExcelReportExporter();

  @override
  Future<Uint8List> export(ReportDocument document) async =>
      throw ReportExcelGenerationFailure(
        'File Excel gagal dibuat. Silakan coba lagi.',
        reportType: document.header.reportType,
      );
}

class FailingPdfReportExporter implements ReportPdfExporter {
  const FailingPdfReportExporter();

  @override
  Future<Uint8List> export(ReportDocument document) async =>
      throw ReportPdfGenerationFailure(
        'File PDF gagal dibuat. Silakan coba lagi.',
        reportType: document.header.reportType,
      );
}

/// A file store that keeps artifacts in a map instead of on disk.
///
/// The path it reports is `memory://<exportId>/<fileName>` — deliberately not a
/// real path, so a test that accidentally asserted on one would be obviously
/// wrong rather than subtly platform-dependent.
class InMemoryReportFileStore implements ReportFileStore {
  final Map<String, Uint8List> _files = <String, Uint8List>{};

  /// Every write that was attempted, in order, whether or not it survived.
  final List<String> writtenFileNames = <String>[];

  /// Every artifact that was deleted — what the audit-failure path is asserted on.
  final List<String> deletedFileNames = <String>[];

  int get fileCount => _files.length;

  bool hasFile(String fileName) =>
      _files.keys.any((key) => key.endsWith('/$fileName'));

  @override
  Future<ReportArtifactHandle> writeArtifact({
    required String exportId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path = 'memory://$exportId/$fileName';
    _files[path] = bytes;
    writtenFileNames.add(fileName);
    return ReportArtifactHandle(
      exportId: exportId,
      fileName: fileName,
      path: path,
      byteLength: bytes.length,
    );
  }

  @override
  Future<void> deleteArtifactBestEffort(ReportArtifactHandle handle) async {
    _files.remove(handle.path);
    deletedFileNames.add(handle.fileName);
  }

  @override
  Future<bool> exists(ReportArtifactHandle handle) async =>
      _files.containsKey(handle.path);

  @override
  Future<Uint8List> readBytes(ReportArtifactHandle handle) async =>
      _files[handle.path] ?? Uint8List(0);
}

/// A file store whose write always fails — the *"file write fails → no log, no
/// share"* row.
class FailingReportFileStore implements ReportFileStore {
  const FailingReportFileStore();

  @override
  Future<ReportArtifactHandle> writeArtifact({
    required String exportId,
    required String fileName,
    required Uint8List bytes,
  }) async => throw ReportFileWriteFailure(
    'File laporan gagal disimpan di perangkat. Silakan coba lagi.',
    fileName: fileName,
  );

  @override
  Future<void> deleteArtifactBestEffort(ReportArtifactHandle handle) async {}

  @override
  Future<bool> exists(ReportArtifactHandle handle) async => false;

  @override
  Future<Uint8List> readBytes(ReportArtifactHandle handle) async =>
      Uint8List(0);
}

/// A share gateway that records what it was handed and returns a chosen outcome.
class FakeReportShareGateway implements ReportShareGateway {
  FakeReportShareGateway({this.outcome = ReportShareOutcome.shared});

  final ReportShareOutcome outcome;

  /// The artifacts offered to the sheet, in order. Empty is the assertion that
  /// matters most: a failed export must never reach here.
  final List<ReportArtifactHandle> shared = <ReportArtifactHandle>[];

  @override
  Future<ReportShareOutcome> shareGeneratedReport(
    ReportArtifactHandle handle,
  ) async {
    shared.add(handle);
    return outcome;
  }
}

/// A share gateway that cannot open the sheet at all.
///
/// The export still succeeds — the file and the audit row both exist by then
/// (§3.16) — which is exactly what the test using this asserts.
class FailingReportShareGateway implements ReportShareGateway {
  const FailingReportShareGateway();

  @override
  Future<ReportShareOutcome> shareGeneratedReport(
    ReportArtifactHandle handle,
  ) async => throw ReportShareFailure(
    'Berbagi file gagal dibuka. File laporan tetap tersimpan di perangkat.',
    fileName: handle.fileName,
  );
}

/// A repository whose `insertExportLog` fails, delegating everything else.
///
/// The *"audit insert fails → file deleted, share not opened, export refused"* row
/// of §36 — the one ordering rule that cannot be tested any other way.
class AuditFailingReportingRepository implements ReportingRepository {
  AuditFailingReportingRepository(this._delegate);

  final ReportingRepository _delegate;

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      _delegate.transaction(action);

  @override
  Future<ExportLog> insertExportLog({
    required reportType,
    required format,
    required scopeType,
    String? locationId,
    String? categoryId,
    String? branchId,
    String? itemId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String exportedBy,
    required String fileName,
    required DateTime dataCutoffAtUtc,
    required String syncSummary,
    required int rowCount,
  }) async => throw StateError('audit unavailable');

  @override
  noSuchMethod(Invocation invocation) =>
      // Every other member is the real repository's. `noSuchMethod` rather than
      // sixteen hand-written delegates, because the point of this class is the one
      // method above and a hand-written wall would bury it.
      Function.apply(
        _memberOf(invocation),
        invocation.positionalArguments,
        invocation.namedArguments,
      );

  Function _memberOf(Invocation invocation) {
    final name = invocation.memberName;
    return switch (name.toString()) {
      'Symbol("resolveScope")' => _delegate.resolveScope,
      'Symbol("locationById")' => _delegate.locationById,
      'Symbol("categoryById")' => _delegate.categoryById,
      'Symbol("itemById")' => _delegate.itemById,
      'Symbol("branchById")' => _delegate.branchById,
      'Symbol("roomById")' => _delegate.roomById,
      'Symbol("userById")' => _delegate.userById,
      'Symbol("roomOfLocation")' => _delegate.roomOfLocation,
      'Symbol("loadLedgerSource")' => _delegate.loadLedgerSource,
      'Symbol("resolveDocumentNumbers")' => _delegate.resolveDocumentNumbers,
      'Symbol("loadOpnameRecap")' => _delegate.loadOpnameRecap,
      'Symbol("loadPurchaseRequestRecap")' =>
        _delegate.loadPurchaseRequestRecap,
      'Symbol("loadDeliveryOrderRecap")' => _delegate.loadDeliveryOrderRecap,
      'Symbol("loadGoodReceiptRecap")' => _delegate.loadGoodReceiptRecap,
      'Symbol("loadDistributionRecap")' => _delegate.loadDistributionRecap,
      'Symbol("loadConsumptionRecap")' => _delegate.loadConsumptionRecap,
      'Symbol("loadDisposalRecap")' => _delegate.loadDisposalRecap,
      'Symbol("loadGoodsReturnRecap")' => _delegate.loadGoodsReturnRecap,
      'Symbol("watchExportHistory")' => _delegate.watchExportHistory,
      'Symbol("watchExportHistoryOf")' => _delegate.watchExportHistoryOf,
      'Symbol("getExportLog")' => _delegate.getExportLog,
      'Symbol("getExportLogDetail")' => _delegate.getExportLogDetail,
      'Symbol("resolveExportLogDetails")' => _delegate.resolveExportLogDetails,
      _ => throw UnimplementedError('Unhandled member: $name'),
    };
  }
}

extension on ReportDocument {
  /// A short, stable string derived from the document — enough to tell two fake
  /// artifacts apart without any of them being a real file format.
  String get title => header.title;
}
