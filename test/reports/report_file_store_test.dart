import 'dart:io';
import 'dart:typed_data';

import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/features/reports/data/files/local_report_file_store.dart';
import 'package:aish_warehouse/features/reports/domain/gateways/report_gateways.dart';
import 'package:flutter_test/flutter_test.dart';

/// §41 — the real file store, against the real filesystem.
///
/// It runs without a platform channel: `getApplicationDocumentsDirectory` throws in
/// a plain test host, and the store falls back to the system temp directory. That
/// fallback is what makes this testable at all, and it changes nothing about the
/// permission story — both locations are inside the app sandbox on a device.
void main() {
  const store = LocalReportFileStore();

  Uint8List bytesOf(String text) => Uint8List.fromList(text.codeUnits);

  /// Removes whatever an export left behind, so one test cannot see another's file.
  Future<void> cleanUp(String exportId) async {
    final directory = Directory(
      '${Directory.systemTemp.path}/${LocalReportFileStore.rootFolderName}/'
      '$exportId',
    );
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  group('menulis artefak', () {
    test('menulis byte dan mengembalikan handle', () async {
      const exportId = 'store-test-1';
      addTearDown(() => cleanUp(exportId));

      final handle = await store.writeArtifact(
        exportId: exportId,
        fileName: 'stok_lokasi_WH_20260730.xlsx',
        bytes: bytesOf('halo'),
      );

      expect(handle.fileName, 'stok_lokasi_WH_20260730.xlsx');
      expect(handle.byteLength, 4);
      expect(await store.exists(handle), isTrue);
      expect(await store.readBytes(handle), bytesOf('halo'));
    });

    test('setiap ekspor mendapat direktorinya sendiri', () async {
      // §37: G-L5's name is deterministic, so two exports of the same report share
      // it — and the per-export directory is the only thing keeping the second from
      // overwriting the first.
      const first = 'store-test-2a';
      const second = 'store-test-2b';
      addTearDown(() => cleanUp(first));
      addTearDown(() => cleanUp(second));
      const fileName = 'stok_lokasi_WH_20260730.xlsx';

      final a = await store.writeArtifact(
        exportId: first,
        fileName: fileName,
        bytes: bytesOf('pertama'),
      );
      final b = await store.writeArtifact(
        exportId: second,
        fileName: fileName,
        bytes: bytesOf('kedua'),
      );

      expect(a.fileName, b.fileName);
      expect(a.path, isNot(b.path));
      expect(await store.readBytes(a), bytesOf('pertama'));
      expect(await store.readBytes(b), bytesOf('kedua'));
    });

    test('path berada di bawah folder aish_reports', () async {
      const exportId = 'store-test-3';
      addTearDown(() => cleanUp(exportId));

      final handle = await store.writeArtifact(
        exportId: exportId,
        fileName: 'kadaluarsa_WH_20260730.pdf',
        bytes: bytesOf('pdf'),
      );

      expect(handle.path, contains(LocalReportFileStore.rootFolderName));
      expect(handle.path, endsWith('kadaluarsa_WH_20260730.pdf'));
    });
  });

  group('nama file berbahaya ditolak', () {
    test('nama dengan pemisah path ditolak', () async {
      // Unreachable through `ReportFileNamePolicy`, which sanitizes every token —
      // which is exactly why the one call that builds a path from a name refuses to
      // build one from a name that could escape (§37).
      await expectLater(
        store.writeArtifact(
          exportId: 'store-test-4',
          fileName: '../../escape.xlsx',
          bytes: bytesOf('x'),
        ),
        throwsA(isA<InvalidReportFileNameFailure>()),
      );
    });

    test('export id dengan pemisah path ditolak', () async {
      await expectLater(
        store.writeArtifact(
          exportId: '../evil',
          fileName: 'stok_lokasi_WH_20260730.xlsx',
          bytes: bytesOf('x'),
        ),
        throwsA(isA<InvalidReportFileNameFailure>()),
      );
    });

    test('nama kosong ditolak', () async {
      await expectLater(
        store.writeArtifact(
          exportId: 'store-test-5',
          fileName: '',
          bytes: bytesOf('x'),
        ),
        throwsA(isA<InvalidReportFileNameFailure>()),
      );
    });
  });

  group('penghapusan best-effort', () {
    test('menghapus file dan direktorinya', () async {
      const exportId = 'store-test-6';
      addTearDown(() => cleanUp(exportId));

      final handle = await store.writeArtifact(
        exportId: exportId,
        fileName: 'stok_lokasi_WH_20260730.xlsx',
        bytes: bytesOf('x'),
      );
      await store.deleteArtifactBestEffort(handle);

      expect(await store.exists(handle), isFalse);
      expect(File(handle.path).parent.existsSync(), isFalse);
    });

    test('menghapus dua kali tidak melempar', () async {
      // It runs only when the export has *already* failed, so a delete that threw
      // would replace one honest error with a confusing one.
      const exportId = 'store-test-7';
      addTearDown(() => cleanUp(exportId));

      final handle = await store.writeArtifact(
        exportId: exportId,
        fileName: 'stok_lokasi_WH_20260730.xlsx',
        bytes: bytesOf('x'),
      );

      await store.deleteArtifactBestEffort(handle);
      await store.deleteArtifactBestEffort(handle);

      expect(await store.exists(handle), isFalse);
    });

    test('menghapus handle yang tidak pernah ditulis tidak melempar', () async {
      await store.deleteArtifactBestEffort(
        ReportArtifactHandle(
          exportId: 'store-test-8',
          fileName: 'tidak-ada.xlsx',
          path:
              '${Directory.systemTemp.path}/'
              '${LocalReportFileStore.rootFolderName}/store-test-8/'
              'tidak-ada.xlsx',
          byteLength: 0,
        ),
      );
    });
  });
}
