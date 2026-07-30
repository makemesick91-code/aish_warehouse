import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/sync/sync_gateway.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_sync_snapshot_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/report_fakes.dart';
import '../helpers/test_context.dart';
import 'reporting_fixture.dart';

/// G-L3 / §50 — *"Laporan dihasilkan **lokal dari Drift** (tetap bisa offline);
/// header laporan wajib mencantumkan … status sync terakhir agar jelas data per
/// kapan."*
///
/// The architecture test asserts the *absence* of a network path at the source.
/// This one asserts the behaviour: a report is produced, exported and audited with
/// nothing but SQLite and the filesystem, and the header tells the reader exactly
/// how provisional the numbers are.
void main() {
  late TestContext context;
  late ReportingFixture fixture;

  final postedAtUtc = DateTime.utc(2026, 7, 20, 2);

  setUp(() async {
    context = TestContext.create();
    fixture = await buildReportingFixture(context, postedAtUtc: postedAtUtc);
  });

  tearDown(() => context.dispose());

  ReportRequestDraft warehouseDraft() => ReportRequestDraft(
    reportType: ReportType.stokLokasi,
    scopeType: ReportScopeType.warehouse,
    periodStart: fixture.asOfNearDate,
    periodEnd: fixture.asOfNearDate,
    locationId: fixture.warehouse.id,
  );

  group('tanpa jaringan', () {
    test('preview dihasilkan dari database lokal', () async {
      final result = await context
          .buildReportPreview(clock: () => fixture.asOfNearUtc)
          .call(actorUserId: fixture.warehouseUser.id, draft: warehouseDraft());

      expect(result.document.rows, isNotEmpty);
    });

    test('ekspor Excel dan PDF berjalan tanpa jaringan', () async {
      final store = InMemoryReportFileStore();
      final useCase = context.exportReport(
        clock: () => fixture.asOfNearUtc,
        fileStore: store,
      );

      for (final format in ReportFormat.values) {
        await useCase.call(
          actorUserId: fixture.warehouseUser.id,
          draft: warehouseDraft(),
          format: format,
        );
      }

      expect(store.writtenFileNames, hasLength(2));
      expect(await context.exportLogCount(), 2);
    });

    test('NoopSyncGateway tidak menghalangi apa pun', () async {
      // The gateway that stands in for the sync backend does nothing, and the
      // reporting module never asks it anything (§50) — so this asserts that
      // running it changes no report.
      const gateway = NoopSyncGateway();
      await gateway.pushPendingChanges();
      await gateway.pullServerChanges();

      final result = await context
          .buildReportPreview(clock: () => fixture.asOfNearUtc)
          .call(actorUserId: fixture.warehouseUser.id, draft: warehouseDraft());

      expect(result.document.rows, isNotEmpty);
    });
  });

  group('status sync pada header (G-L3)', () {
    test('data pending tetap masuk laporan dan dihitung', () async {
      // G-Y1 makes working offline the normal case: local rows are `pending` and
      // the report is the honest local truth, labelled as provisional.
      final result = await context
          .buildReportPreview(clock: () => fixture.asOfNearUtc)
          .call(actorUserId: fixture.warehouseUser.id, draft: warehouseDraft());

      final snapshot = result.document.header.syncSnapshot;
      expect(result.document.rows, isNotEmpty);
      expect(snapshot.pendingCount, greaterThan(0));
      expect(snapshot.label, contains('pending'));
      expect(
        ReportSyncSnapshotBuilder.describeWarning(snapshot),
        contains('belum tersinkron'),
      );
    });

    test('data tersinkron menghilangkan peringatan', () async {
      await context.markMovementsSynced();

      final result = await context
          .buildReportPreview(clock: () => fixture.asOfNearUtc)
          .call(actorUserId: fixture.warehouseUser.id, draft: warehouseDraft());

      final snapshot = result.document.header.syncSnapshot;
      expect(snapshot.pendingCount, 0);
      expect(snapshot.syncedCount, greaterThan(0));
      expect(ReportSyncSnapshotBuilder.describeWarning(snapshot), isNull);
    });

    test('data konflik memberi peringatan yang lebih keras', () async {
      await context.database.customStatement(
        "UPDATE stock_movements SET sync_status = 'conflict';",
      );

      final result = await context
          .buildReportPreview(clock: () => fixture.asOfNearUtc)
          .call(actorUserId: fixture.warehouseUser.id, draft: warehouseDraft());

      final snapshot = result.document.header.syncSnapshot;
      expect(snapshot.conflictCount, greaterThan(0));
      expect(
        ReportSyncSnapshotBuilder.describeWarning(snapshot),
        contains('konflik'),
      );
      // The rows are still there: a conflicted row is data with a caveat, not data
      // to hide.
      expect(result.document.rows, isNotEmpty);
    });

    test('filter tanpa hasil menyebutkan itu, bukan angka nol palsu', () async {
      final result = await context
          .buildReportPreview(clock: () => DateTime.utc(2026, 7, 19, 2))
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: ReportRequestDraft(
              reportType: ReportType.stokLokasi,
              scopeType: ReportScopeType.warehouse,
              // A day before anything was posted: the filter genuinely matches
              // nothing, which is different from matching zero.
              periodStart: DateOnly.of(2026, 7, 19),
              periodEnd: DateOnly.of(2026, 7, 19),
              locationId: fixture.warehouse.id,
            ),
          );

      expect(
        result.document.header.syncSnapshot.label,
        ReportSyncSnapshot.emptyLabel,
      );
      expect(
        ReportSyncSnapshotBuilder.describeLastUpdate(
          result.document.header.syncSnapshot,
        ),
        ReportSyncSnapshot.emptyLabel,
      );
    });

    test('ringkasan sync yang tersimpan sama dengan yang tercetak', () async {
      // The audit row and the file header must agree about how fresh the data was,
      // or a reader comparing them learns the wrong thing.
      final preview = await context
          .buildReportPreview(clock: () => fixture.asOfNearUtc)
          .call(actorUserId: fixture.warehouseUser.id, draft: warehouseDraft());
      await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseDraft(),
            format: ReportFormat.xlsx,
          );

      final row = (await context.exportLogRows()).single;
      expect(row['sync_summary'], preview.document.header.syncSnapshot.label);
    });
  });

  group('§53 — seed pengembangan tidak menulis audit', () {
    test('menjalankan seed tidak menghasilkan export log', () async {
      // No fake trail: an audit row that describes a file nobody produced is
      // indistinguishable from a real one in the Super Admin's screen.
      final seeded = TestContext.create();
      addTearDown(seeded.dispose);

      await seeded.seed.run();

      expect(await seeded.exportLogCount(), 0);
    });
  });
}
