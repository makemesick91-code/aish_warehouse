import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/app/routes.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:aish_warehouse/features/reports/presentation/pages/export_history_page.dart';
import 'package:aish_warehouse/features/reports/presentation/pages/report_page.dart';
import 'package:aish_warehouse/features/reports/presentation/providers/reporting_providers.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/session/acting_user_providers.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/report_fakes.dart';
import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';
import 'reporting_fixture.dart';

/// §43 and §55 — what a refused reporting route reveals, which is nothing.
///
/// The route tests navigate by **URL** rather than pumping a page directly, because
/// typing the address is the attack: pumping the page bypasses exactly the layer
/// under test.
void main() {
  late TestContext context;
  late ReportingFixture fixture;

  setUp(() async {
    context = TestContext.create();
    fixture = await buildReportingFixture(
      context,
      postedAtUtc: DateTime.utc(2026, 7, 20, 2),
    );
  });

  tearDown(() => context.dispose());

  Future<void> openAt(
    WidgetTester tester, {
    required MasterUser actingAs,
    required String location,
  }) => pumpAppAt(
    tester,
    context: context,
    actingAs: actingAs,
    location: location,
  ).then((_) {});

  group('/reports', () {
    for (final entry in <String, MasterUser Function()>{
      'perawat': () => fixture.nurse,
      'kepala cabang': () => fixture.branchHead,
      'warehouse': () => fixture.warehouseUser,
      'super admin': () => fixture.superAdmin,
    }.entries) {
      testWidgets('${entry.key} dapat membuka modul laporan', (tester) async {
        // §3.1 gives report access to every role; what each finds inside differs.
        useTabletSurface(tester);
        await openAt(
          tester,
          actingAs: entry.value(),
          location: AppRoutes.reports,
        );

        expect(find.byKey(ReportPage.pageKey), findsOneWidget);
        expect(find.byKey(AccessDeniedPage.pageKey), findsNothing);

        await disposeWidget(tester);
      });
    }
  });

  group('/reports/export-history', () {
    testWidgets('super admin melihat jejak audit', (tester) async {
      useTabletSurface(tester);
      await openAt(
        tester,
        actingAs: fixture.superAdmin,
        location: AppRoutes.exportHistory,
      );

      expect(find.byKey(ExportHistoryPage.pageKey), findsOneWidget);

      await disposeWidget(tester);
    });

    for (final entry in <String, MasterUser Function()>{
      'perawat': () => fixture.nurse,
      'kepala cabang': () => fixture.branchHead,
      'warehouse': () => fixture.warehouseUser,
    }.entries) {
      testWidgets('${entry.key} tidak dapat membuka riwayat ekspor', (
        tester,
      ) async {
        useTabletSurface(tester);
        await openAt(
          tester,
          actingAs: entry.value(),
          location: AppRoutes.exportHistory,
        );

        expect(find.byKey(ExportHistoryPage.pageKey), findsNothing);

        await disposeWidget(tester);
      });
    }

    testWidgets('URL riwayat tidak membocorkan apa pun', (tester) async {
      // The refusal must name nothing: not the file, not the branch, not the
      // exporter, not that an export happened at all (§43).
      await context
          .exportReport(clock: () => fixture.asOfNearUtc)
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

      useTabletSurface(tester);
      await openAt(
        tester,
        actingAs: fixture.branchHead,
        location: AppRoutes.exportHistory,
      );

      expect(find.textContaining('stok_lokasi_WH'), findsNothing);
      expect(find.textContaining(fixture.warehouseUser.fullName), findsNothing);
      expect(find.textContaining(fixture.warehouse.name), findsNothing);
      expect(find.byKey(ExportHistoryPage.listKey), findsNothing);

      await disposeWidget(tester);
    });

    testWidgets('pintasan riwayat hanya tampil untuk super admin', (
      tester,
    ) async {
      useTabletSurface(tester);

      await openAt(
        tester,
        actingAs: fixture.superAdmin,
        location: AppRoutes.reports,
      );
      expect(find.byKey(ReportPage.exportHistoryLinkKey), findsOneWidget);
      await disposeWidget(tester);

      await openAt(
        tester,
        actingAs: fixture.branchHead,
        location: AppRoutes.reports,
      );
      expect(find.byKey(ReportPage.exportHistoryLinkKey), findsNothing);
      await disposeWidget(tester);
    });
  });

  group('pilihan yang tidak boleh tidak ditawarkan (§45)', () {
    /// A container wired exactly as the app wires itself, minus the widget tree.
    ///
    /// The provider-level assertions build their own container rather than pumping
    /// a screen, because what is under test is the *list a screen would be given* —
    /// and reading it directly is the only way to assert that an unauthorized entry
    /// is absent rather than merely not drawn.
    Future<ProviderContainer> containerFor(MasterUser actor) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(context.database),
          currentSessionProvider.overrideWith(
            () => FixedSessionController(actor),
          ),
        ],
      );
      addTearDown(container.dispose);
      // The session is an `AsyncNotifier`, so every derived provider reads `null`
      // until it resolves. A widget would rebuild; a container has to be awaited.
      await container.read(currentSessionProvider.future);
      return container;
    }

    test('perawat hanya melihat lima jenis laporan', () async {
      final container = await containerFor(fixture.nurse);

      expect(container.read(allowedReportTypesProvider), [
        ReportType.stokLokasi,
        ReportType.kartuStok,
        ReportType.rekapOpname,
        ReportType.rekapPemakaian,
        ReportType.kadaluarsa,
      ]);
    });

    test('perawat hanya melihat cakupan ruangan', () async {
      final container = await containerFor(fixture.nurse);

      expect(
        container.read(allowedReportScopesProvider(ReportType.stokLokasi)),
        [ReportScopeType.room],
      );
    });

    test('warehouse tidak ditawari cakupan ruangan untuk stok', () async {
      final container = await containerFor(fixture.warehouseUser);

      expect(
        container.read(allowedReportScopesProvider(ReportType.stokLokasi)),
        [ReportScopeType.warehouse],
      );
    });

    test('daftar lokasi perawat hanya ruangan cabangnya', () async {
      final container = await containerFor(fixture.nurse);
      await container.read(actingUserProvider.future);

      final locations = await container.read(
        reportLocationOptionsProvider(ReportScopeType.room).future,
      );

      expect(locations.map((location) => location.id), [
        fixture.roomLocation.id,
      ]);
      expect(
        locations.any(
          (location) => location.id == fixture.otherRoomLocation.id,
        ),
        isFalse,
      );
    });

    test('daftar lokasi kepala cabang hanya gudang cabangnya', () async {
      final container = await containerFor(fixture.branchHead);
      await container.read(actingUserProvider.future);

      final locations = await container.read(
        reportLocationOptionsProvider(ReportScopeType.branchStore).future,
      );

      expect(locations.map((location) => location.id), [
        fixture.branchStore.id,
      ]);
    });

    test('filter cabang hanya untuk peran lintas cabang', () async {
      final branchContainer = await containerFor(fixture.branchHead);
      expect(
        await branchContainer.read(reportBranchOptionsProvider.future),
        isEmpty,
      );

      final warehouseContainer = await containerFor(fixture.warehouseUser);
      expect(
        await warehouseContainer.read(reportBranchOptionsProvider.future),
        isNotEmpty,
      );
    });
  });

  group('pergantian sesi (§44)', () {
    test('draft dibangun ulang untuk aktor baru', () async {
      Future<ProviderContainer> containerFor(MasterUser actor) async {
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(context.database),
            currentSessionProvider.overrideWith(
              () => FixedSessionController(actor),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(currentSessionProvider.future);
        return container;
      }

      final nurseContainer = await containerFor(fixture.nurse);
      final warehouseContainer = await containerFor(fixture.warehouseUser);

      expect(
        nurseContainer.read(reportDraftProvider).scopeType,
        ReportScopeType.room,
      );
      expect(
        warehouseContainer.read(reportDraftProvider).scopeType,
        ReportScopeType.warehouse,
      );
    });
  });

  group('riwayat ekspor sebagai stream', () {
    test('stream kosong untuk peran selain super admin', () async {
      await context
          .exportReport(
            clock: () => fixture.asOfNearUtc,
            fileStore: InMemoryReportFileStore(),
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

      // The provider is not the boundary — the use case checks the re-read actor,
      // so reading it from anywhere still yields nothing.
      expect(
        await context.watchExportHistory.call(actor: fixture.nurse).first,
        isEmpty,
      );
      expect(await context.watchExportHistory.call(actor: null).first, isEmpty);
    });

    test('akun super admin nonaktif tidak melihat apa pun', () async {
      final inactive = MasterUser(
        id: fixture.superAdmin.id,
        fullName: fixture.superAdmin.fullName,
        email: fixture.superAdmin.email,
        role: UserRole.superAdmin,
        isActive: false,
      );

      expect(
        await context.watchExportHistory.call(actor: inactive).first,
        isEmpty,
      );
    });
  });
}
