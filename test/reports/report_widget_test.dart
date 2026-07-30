import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/reports/domain/gateways/report_gateways.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:aish_warehouse/features/reports/presentation/pages/export_history_page.dart';
import 'package:aish_warehouse/features/reports/presentation/pages/report_page.dart';
import 'package:aish_warehouse/features/reports/presentation/providers/reporting_providers.dart';
import 'package:aish_warehouse/features/reports/presentation/widgets/export_buttons.dart';
import 'package:aish_warehouse/features/reports/presentation/widgets/report_preview_view.dart';
import 'package:aish_warehouse/features/reports/presentation/widgets/reporting_dashboard_cards.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/report_fakes.dart';
import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';
import 'reporting_fixture.dart';

/// The reporting screens (§45–§49).
///
/// Every export in this file runs against fakes: the real file store writes to a
/// device directory and the real share gateway opens a platform sheet, and a widget
/// test may do neither (§7).
void main() {
  late TestContext context;
  late ReportingFixture fixture;
  late InMemoryReportFileStore fileStore;
  late FakeReportShareGateway shareGateway;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildReportingFixture(
      context,
      postedAtUtc: DateTime.utc(2026, 7, 20, 2),
    );
    fileStore = InMemoryReportFileStore();
    shareGateway = FakeReportShareGateway();
  });

  tearDown(() => context.dispose());

  /// The module's four platform boundaries plus its clock, all faked.
  ///
  /// Riverpod refuses two overrides of one provider in a container, so a test that
  /// wants a different share gateway or exporter passes it here rather than
  /// appending a second override — which is also why every collaborator is a named
  /// parameter with a default.
  List<Override> reportOverrides({
    DateTime? clockUtc,
    ReportShareGateway? share,
    ReportExcelExporter? excel,
    ReportPdfExporter? pdf,
  }) => [
    reportClockProvider.overrideWithValue(
      () => clockUtc ?? fixture.asOfNearUtc,
    ),
    reportFileStoreProvider.overrideWithValue(fileStore),
    reportShareGatewayProvider.overrideWithValue(share ?? shareGateway),
    reportExcelExporterProvider.overrideWithValue(
      excel ?? const FakeExcelReportExporter(),
    ),
    reportPdfExporterProvider.overrideWithValue(
      pdf ?? const FakePdfReportExporter(),
    ),
  ];

  Future<void> pumpReports(
    WidgetTester tester, {
    required MasterUser actingAs,
    DateTime? clockUtc,
    ReportShareGateway? share,
    ReportExcelExporter? excel,
    ReportPdfExporter? pdf,
  }) async {
    useTabletSurface(tester);
    await pumpAppWidget(
      tester,
      context: context,
      actingAs: actingAs,
      child: const ReportPage(),
      overrides: reportOverrides(
        clockUtc: clockUtc,
        share: share,
        excel: excel,
        pdf: pdf,
      ),
    );
  }

  group('halaman Laporan', () {
    testWidgets('menampilkan judul, peran dan filter', (tester) async {
      await pumpReports(tester, actingAs: fixture.warehouseUser);

      expect(find.text(ReportPage.title), findsOneWidget);
      expect(find.text(fixture.warehouseUser.fullName), findsWidgets);
      expect(find.byKey(ReportPage.reportTypeFieldKey), findsOneWidget);
      expect(find.byKey(ReportPage.scopeFieldKey), findsOneWidget);
      expect(find.text(ReportPage.previewLabel), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('tombol ekspor tersedia', (tester) async {
      await pumpReports(tester, actingAs: fixture.warehouseUser);

      expect(find.byKey(ExportButtons.excelButtonKey), findsOneWidget);
      expect(find.byKey(ExportButtons.pdfButtonKey), findsOneWidget);
      expect(find.text(ExportButtons.excelLabel), findsOneWidget);
      expect(find.text(ExportButtons.pdfLabel), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('daftar jenis laporan perawat tidak memuat rekap gudang', (
      tester,
    ) async {
      // §45: an unauthorized entry is *absent*, never disabled — a greyed-out
      // "Rekap Distribusi" would tell a nurse the report exists.
      await pumpReports(tester, actingAs: fixture.nurse);
      await tester.tap(find.byKey(ReportPage.reportTypeFieldKey));
      await tester.pumpAndSettle();

      expect(find.text(ReportType.stokLokasi.label), findsWidgets);
      expect(find.text(ReportType.rekapDistribusi.label), findsNothing);
      expect(find.text(ReportType.rekapGr.label), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('pencarian jenis laporan menyaring seiring ketikan', (
      tester,
    ) async {
      // §4.3's SearchableDropdown behaviour: typeahead, case-insensitive.
      await pumpReports(tester, actingAs: fixture.warehouseUser);

      await tester.enterText(
        find.byKey(ReportPage.reportTypeSearchKey),
        'kartu',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReportPage.reportTypeFieldKey));
      await tester.pumpAndSettle();

      expect(find.text(ReportType.kartuStok.label), findsWidgets);
      expect(find.text(ReportType.rekapGr.label), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('pencarian tanpa hasil menyebut Tidak ditemukan', (
      tester,
    ) async {
      await pumpReports(tester, actingAs: fixture.warehouseUser);

      await tester.enterText(
        find.byKey(ReportPage.reportTypeSearchKey),
        'zzzz',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ReportPage.reportTypeEmptyKey), findsOneWidget);
      expect(find.text('Tidak ditemukan'), findsOneWidget);
      expect(find.byKey(ReportPage.reportTypeFieldKey), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('perawat tidak ditawari Gudang Cabang', (tester) async {
      await pumpReports(tester, actingAs: fixture.nurse);
      await tester.tap(find.byKey(ReportPage.scopeFieldKey));
      await tester.pumpAndSettle();

      expect(find.text(ReportScopeType.room.label), findsWidgets);
      expect(find.text(ReportScopeType.branchStore.label), findsNothing);
      expect(find.text(ReportScopeType.warehouse.label), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('preview stok warehouse menampilkan header dan total', (
      tester,
    ) async {
      await pumpReports(tester, actingAs: fixture.warehouseUser);
      await tester.pumpAndSettle();

      expect(find.text(ReportHeader.appTitle), findsOneWidget);
      expect(find.textContaining('tersinkron'), findsWidgets);
      expect(find.byKey(ReportPreviewView.tableKey), findsOneWidget);
      expect(find.textContaining('Total Keseluruhan'), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('preview kosong menampilkan pesan tidak ada data', (
      tester,
    ) async {
      // A cutoff before every movement: the report is legitimately empty.
      await pumpReports(
        tester,
        actingAs: fixture.warehouseUser,
        clockUtc: DateTime.utc(2026, 7, 19, 2),
      );
      await tester.pumpAndSettle();
      // The page holds several scrollables — the category chips scroll
      // horizontally — so the outer list has to be named rather than guessed at.
      await tester.scrollUntilVisible(
        find.byKey(ReportPreviewView.emptyKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ReportPreviewView.emptyKey), findsOneWidget);
      expect(find.text(ReportDocument.emptyMessage), findsWidgets);

      await disposeWidget(tester);
    });

    testWidgets('tabel dapat digulir horizontal pada layar sempit', (
      tester,
    ) async {
      // §46: a fourteen-column stock card cannot be made to fit a phone, so it
      // scrolls rather than overflowing.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.warehouseUser,
        child: const ReportPage(),
        overrides: reportOverrides(),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await disposeWidget(tester);
    });
  });

  group('ExportButtons (§47)', () {
    testWidgets('mengunduh Excel: file dibuat, log dicatat, share dibuka', (
      tester,
    ) async {
      await pumpReports(tester, actingAs: fixture.warehouseUser);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ExportButtons.excelButtonKey));
      await tester.pumpAndSettle();

      expect(fileStore.writtenFileNames, ['stok_lokasi_WH_20260722.xlsx']);
      expect(shareGateway.shared, hasLength(1));
      expect(await context.exportLogCount(), 1);

      await disposeWidget(tester);
    });

    testWidgets('pesan sukses menyebut file, bukan folder Downloads', (
      tester,
    ) async {
      // §47: the file is in the app's private directory; telling a user to look in
      // Downloads would send them looking for something that is not there.
      await pumpReports(tester, actingAs: fixture.warehouseUser);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ExportButtons.pdfButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Laporan PDF berhasil dibuat.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('siap disimpan atau dibagikan'),
        findsOneWidget,
      );
      expect(find.textContaining('Downloads'), findsNothing);
      expect(
        find.textContaining('stok_lokasi_WH_20260722.pdf'),
        findsOneWidget,
      );

      await disposeWidget(tester);
    });

    testWidgets('share dibatalkan tetap dilaporkan sebagai file dibuat', (
      tester,
    ) async {
      await pumpReports(
        tester,
        actingAs: fixture.warehouseUser,
        share: FakeReportShareGateway(outcome: ReportShareOutcome.cancelled),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ExportButtons.excelButtonKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('berhasil dibuat'), findsOneWidget);
      expect(find.textContaining('Berbagi dibatalkan'), findsOneWidget);
      expect(await context.exportLogCount(), 1);

      await disposeWidget(tester);
    });

    testWidgets('kegagalan menampilkan pesan Indonesia tanpa path', (
      tester,
    ) async {
      await pumpReports(
        tester,
        actingAs: fixture.warehouseUser,
        excel: const FailingExcelReportExporter(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ExportButtons.excelButtonKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('File Excel gagal dibuat'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('/'), findsNothing);
      expect(await context.exportLogCount(), 0);

      await disposeWidget(tester);
    });

    testWidgets('kartu stok tanpa barang menonaktifkan tombol ekspor', (
      tester,
    ) async {
      await pumpReports(tester, actingAs: fixture.warehouseUser);

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(ReportPage.pageKey)),
      );
      container
          .read(reportDraftProvider.notifier)
          .setReportType(ReportType.kartuStok);
      await tester.pumpAndSettle();

      final excel = tester.widget<FilledButton>(
        find.byKey(ExportButtons.excelButtonKey),
      );
      expect(excel.onPressed, isNull);

      await disposeWidget(tester);
    });
  });

  group('halaman Riwayat Ekspor (§48)', () {
    Future<void> pumpHistory(WidgetTester tester) async {
      useTabletSurface(tester);
      await pumpAppWidget(
        tester,
        context: context,
        actingAs: fixture.superAdmin,
        child: const ExportHistoryPage(),
        overrides: reportOverrides(),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('kosong menampilkan pesan, bukan tabel', (tester) async {
      await pumpHistory(tester);

      expect(find.byKey(ExportHistoryPage.emptyKey), findsOneWidget);
      expect(find.text(ExportHistoryPage.emptyMessage), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('menjelaskan bahwa ini jejak audit, bukan arsip file', (
      tester,
    ) async {
      await pumpHistory(tester);

      expect(find.text(ExportHistoryPage.archiveNotice), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('menampilkan setiap kolom audit untuk satu ekspor', (
      tester,
    ) async {
      await context
          .exportReport(
            clock: () => fixture.asOfNearUtc,
            fileStore: fileStore,
            shareGateway: shareGateway,
          )
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: ReportRequestDraft(
              reportType: ReportType.stokLokasi,
              scopeType: ReportScopeType.warehouse,
              periodStart: fixture.asOfNearDate,
              periodEnd: fixture.asOfNearDate,
              locationId: fixture.warehouse.id,
            ),
            format: ReportFormat.xlsx,
          );

      await pumpHistory(tester);
      expect(find.byKey(ExportHistoryPage.listKey), findsOneWidget);
      expect(find.text('stok_lokasi_WH_20260722.xlsx'), findsOneWidget);

      await tester.tap(find.text('stok_lokasi_WH_20260722.xlsx'));
      await tester.pumpAndSettle();

      expect(find.text('Format'), findsOneWidget);
      expect(find.text('Cakupan'), findsOneWidget);
      expect(find.text('Diekspor oleh'), findsOneWidget);
      expect(find.text('Jumlah baris'), findsOneWidget);
      expect(find.text('Data per'), findsOneWidget);
      expect(find.text('Status sinkronisasi data'), findsOneWidget);
      expect(find.text(fixture.warehouseUser.fullName), findsOneWidget);

      await disposeWidget(tester);
    });

    testWidgets('tidak menyediakan hapus, edit atau unduh ulang', (
      tester,
    ) async {
      await pumpHistory(tester);

      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.textContaining('Hapus'), findsNothing);
      expect(find.textContaining('Unduh ulang'), findsNothing);

      await disposeWidget(tester);
    });
  });

  group('kartu dashboard (§49)', () {
    /// Pumps the cards with **bounded** frames rather than `pumpAndSettle`.
    ///
    /// The audit cards render a progress indicator while their stream resolves, and
    /// an indeterminate indicator is an animation that never ends — `pumpAndSettle`
    /// waits for it forever. A fixed number of frames is enough for the providers to
    /// deliver and is what the assertions actually need.
    Future<void> pumpCards(
      WidgetTester tester,
      MasterUser actor, {
      List<ExportLog> ownExports = const <ExportLog>[],
    }) async {
      useTabletSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(context.database),
            currentSessionProvider.overrideWith(
              () => FixedSessionController(actor),
            ),
            // The own-exports card reads a **drift query stream**, and a widget
            // test's faked clock never lets one deliver — the card would sit on its
            // progress indicator forever. What the stream does is asserted for real
            // in `report_export_test.dart`; what this test is about is what the card
            // renders once it has an answer.
            recentOwnExportsProvider.overrideWith((ref) async => ownExports),
            ...reportOverrides(),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ReportingDashboardCard(),
                    RecentOwnExportsCard(),
                    ExportAuditSummaryCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      // A bounded number of frames — enough for the providers to deliver, and
      // never waiting on the indeterminate progress animation that would make
      // `pumpAndSettle` hang.
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
    }

    testWidgets('label entri laporan mengikuti peran', (tester) async {
      for (final entry in <MasterUser, String>{
        fixture.nurse: 'Laporan Ruangan',
        fixture.branchHead: 'Laporan Cabang',
        fixture.warehouseUser: 'Laporan Warehouse & Lintas Cabang',
        fixture.superAdmin: 'Semua Laporan',
      }.entries) {
        await pumpCards(tester, entry.key);
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: entry.key.role.dbValue,
        );
        await disposeWidget(tester);
      }
    });

    testWidgets('ringkasan audit hanya untuk super admin', (tester) async {
      await pumpCards(tester, fixture.superAdmin);
      expect(find.byKey(ExportAuditSummaryCard.cardKey), findsOneWidget);
      expect(find.text('Ekspor hari ini'), findsOneWidget);
      await disposeWidget(tester);

      await pumpCards(tester, fixture.branchHead);
      expect(find.byKey(ExportAuditSummaryCard.cardKey), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('ekspor terbaru saya kosong sebelum ada ekspor', (
      tester,
    ) async {
      await pumpCards(tester, fixture.branchHead);

      expect(find.text(RecentOwnExportsCard.emptyMessage), findsOneWidget);

      await disposeWidget(tester);
    });
  });
}
