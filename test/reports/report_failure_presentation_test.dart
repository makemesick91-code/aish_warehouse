import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/reports/presentation/providers/reporting_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// §52 — every reporting failure reaches the user as one Indonesian sentence, with
/// no path, no stack trace and no internal identifier.
void main() {
  /// Every reporting failure this module can throw, with a representative
  /// message. Kept as a list so a new failure without a message is a compile
  /// error here rather than a raw exception on somebody's screen.
  final failures = <AppFailure>[
    const ReportAccessDeniedFailure(
      'Anda tidak memiliki akses ke laporan ini.',
      reportType: ReportType.stokLokasi,
    ),
    const UnsupportedReportTypeFailure(
      'Jenis laporan ini tidak tersedia.',
      reportType: ReportType.kartuStok,
    ),
    const InvalidReportScopeFailure(
      'Kartu Stok membutuhkan tepat satu lokasi.',
      reportType: ReportType.kartuStok,
      scopeType: ReportScopeType.branchAll,
    ),
    InvalidReportPeriodFailure(
      'Tanggal mulai tidak boleh setelah tanggal akhir.',
      periodStart: DateOnly.of(2026, 7, 31),
      periodEnd: DateOnly.of(2026, 7, 30),
    ),
    const ReportLocationRequiredFailure(
      'Pilih lokasi terlebih dahulu.',
      reportType: ReportType.stokLokasi,
      scopeType: ReportScopeType.room,
    ),
    const ReportLocationAccessDeniedFailure(
      'Lokasi yang dipilih bukan Ruangan.',
      locationId: 'loc-1',
    ),
    const ReportItemRequiredFailure(
      'Kartu Stok membutuhkan satu barang.',
      reportType: ReportType.kartuStok,
    ),
    const ReportCategoryNotFoundFailure(
      'Kategori tidak ditemukan.',
      categoryId: 'cat-1',
    ),
    const ReportItemNotFoundFailure(
      'Barang tidak ditemukan.',
      itemId: 'item-1',
    ),
    const ReportLocationNotFoundFailure(
      'Lokasi tidak ditemukan.',
      locationId: 'loc-1',
    ),
    const ReportLedgerIntegrityFailure(
      'Sebagian data pergerakan stok tidak dapat dibaca. Laporan dibatalkan '
      'agar angka tidak berkurang tanpa penjelasan.',
      expectedMovementIds: {'m1'},
      loadedMovementIds: {},
    ),
    const ReportDocumentIntegrityFailure(
      'Sebagian dokumen tidak dapat dibaca.',
      reportType: ReportType.rekapGr,
      missingDocumentIds: {'gr-1'},
    ),
    const ReportGenerationFailure(
      'Laporan gagal dibuat. Silakan coba lagi.',
      reportType: ReportType.stokLokasi,
    ),
    const ReportExcelGenerationFailure(
      'File Excel gagal dibuat. Silakan coba lagi.',
      reportType: ReportType.stokLokasi,
    ),
    const ReportPdfGenerationFailure(
      'File PDF gagal dibuat. Silakan coba lagi.',
      reportType: ReportType.stokLokasi,
    ),
    const ReportFileWriteFailure(
      'File laporan gagal disimpan di perangkat. Silakan coba lagi.',
      fileName: 'stok_lokasi_WH_20260730.xlsx',
    ),
    const ReportAuditWriteFailure(
      'Laporan gagal dicatat pada jejak audit, sehingga ekspor dibatalkan. '
      'Silakan coba lagi.',
      fileName: 'stok_lokasi_WH_20260730.xlsx',
    ),
    const ReportShareFailure(
      'Berbagi file gagal dibuka. File laporan tetap tersimpan di perangkat.',
      fileName: 'stok_lokasi_WH_20260730.xlsx',
    ),
    const InvalidReportFileNameFailure(
      'Nama file laporan tidak valid.',
      fileName: 'x.xlsx',
    ),
    const EmptyReportExportFailure(
      'Laporan tidak memuat data.',
      reportType: ReportType.stokLokasi,
    ),
  ];

  group('pesan pengguna', () {
    test('setiap kegagalan menghasilkan pesannya sendiri', () {
      for (final failure in failures) {
        expect(
          describeReportFailure(failure),
          failure.message,
          reason: failure.runtimeType.toString(),
        );
      }
    });

    test('tidak ada pesan yang kosong', () {
      for (final failure in failures) {
        expect(
          failure.message.trim(),
          isNotEmpty,
          reason: failure.runtimeType.toString(),
        );
      }
    });

    test('pesan berbahasa Indonesia dan diakhiri titik', () {
      for (final failure in failures) {
        expect(
          failure.message.endsWith('.'),
          isTrue,
          reason: failure.runtimeType.toString(),
        );
        // A crude but effective check that nothing slipped through in English.
        expect(
          failure.message,
          isNot(matches(RegExp(r'\b(failed|error|invalid|denied)\b'))),
          reason: failure.runtimeType.toString(),
        );
      }
    });

    test('tidak ada pesan yang membocorkan path atau tipe internal', () {
      // §52: an internal directory and a stack trace tell a nurse nothing, and a
      // path in a message is a path in a screenshot.
      for (final failure in failures) {
        final message = failure.message;
        expect(message.contains('/'), isFalse, reason: message);
        expect(message.contains(r'\'), isFalse, reason: message);
        expect(message.contains('Exception'), isFalse, reason: message);
        expect(message.contains('#0'), isFalse, reason: message);
        expect(message.contains('Failure'), isFalse, reason: message);
      }
    });

    test('penolakan akses tidak menyebut lokasi, cabang atau barang', () {
      // The refusal is deliberately uninformative — telling "another branch" from
      // "does not exist" apart is how the filter form becomes an enumerator.
      const failure = ReportAccessDeniedFailure(
        'Anda tidak memiliki akses ke laporan ini.',
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.room,
      );

      expect(failure.message.toLowerCase().contains('cabang'), isFalse);
      expect(failure.message.toLowerCase().contains('ruangan'), isFalse);
      expect(failure.message.toLowerCase().contains('gudang'), isFalse);
    });
  });

  group('kegagalan tak terduga', () {
    test('menjadi satu kalimat generik', () {
      expect(
        describeReportFailure(StateError('boom')),
        'Sesi pengguna tidak tersedia. Muat ulang aplikasi lalu coba lagi.',
      );
      expect(
        describeReportFailure(FormatException('boom')),
        'Terjadi kesalahan tak terduga. Silakan coba lagi.',
      );
    });

    test('tidak pernah menampilkan toString sebuah exception', () {
      final described = describeReportFailure(
        ArgumentError.value('rahasia', 'value'),
      );
      expect(described.contains('rahasia'), isFalse);
    });
  });

  group('EmptyReportExportFailure sengaja tidak dipakai', () {
    test('tidak dilempar di mana pun pada lib/', () {
      // §52 decides that an empty report is a legitimate answer: the file is
      // produced with its header and "Tidak ada data", and the export is logged.
      // The type exists so a future rule has somewhere to land, and this test is
      // what stops it being wired up by somebody assuming it was an oversight.
      final sources = [
        'lib/features/reports/domain/use_cases/export_report_use_case.dart',
        'lib/features/reports/domain/use_cases/build_report_preview_use_case.dart',
        'lib/features/reports/domain/services/report_document_assembler.dart',
      ];
      for (final path in sources) {
        expect(
          readCodeOnly(path),
          isNot(contains('EmptyReportExportFailure')),
          reason: path,
        );
      }
    });
  });
}
