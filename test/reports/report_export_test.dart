import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/report_fakes.dart';
import '../helpers/test_context.dart';
import 'reporting_fixture.dart';

/// §36 — the export ordering, and what survives each way it can fail.
///
/// The table the use case is written around:
///
/// | fails | file | log | share |
/// |---|---|---|---|
/// | generation | none | none | not opened |
/// | file write | none | none | not opened |
/// | audit insert | deleted | none | not opened |
/// | share | kept | kept | reported |
///
/// Every row of it is a test here, because each is a decision that could
/// defensibly have gone the other way and only one of them keeps G-L2's promise:
/// no exported copy of clinic data without an audit row.
void main() {
  late TestContext context;
  late ReportingFixture fixture;

  final postedAtUtc = DateTime.utc(2026, 7, 20, 2);

  setUp(() async {
    context = TestContext.create();
    fixture = await buildReportingFixture(context, postedAtUtc: postedAtUtc);
  });

  tearDown(() => context.dispose());

  ReportRequestDraft warehouseStockDraft({
    String? categoryId,
    ReportType reportType = ReportType.stokLokasi,
    String? itemId,
  }) => ReportRequestDraft(
    reportType: reportType,
    scopeType: ReportScopeType.warehouse,
    periodStart: fixture.asOfNearDate,
    periodEnd: fixture.asOfNearDate,
    locationId: fixture.warehouse.id,
    filter: ReportFilter(categoryId: categoryId, itemId: itemId),
  );

  group('ekspor berhasil', () {
    test(
      'menghasilkan file, satu export log dan membuka share sheet',
      () async {
        final store = InMemoryReportFileStore();
        final share = FakeReportShareGateway();

        final artifact = await context
            .exportReport(
              clock: () => fixture.asOfNearUtc,
              idGenerator: () => 'export-1',
              fileStore: store,
              shareGateway: share,
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              draft: warehouseStockDraft(),
              format: ReportFormat.xlsx,
            );

        expect(store.writtenFileNames, ['stok_lokasi_WH_20260722.xlsx']);
        expect(store.deletedFileNames, isEmpty);
        expect(share.shared.single.fileName, artifact.fileName);
        expect(await context.exportLogCount(), 1);
        expect(artifact.shareOutcome, ReportShareOutcome.shared);
      },
    );

    test('export log merekam setiap kolom audit', () async {
      // G-L2: *"siapa, laporan apa, lokasi & periode apa, kapan"* — plus the four
      // extension columns §12 adds.
      await context
          .exportReport(
            clock: () => fixture.asOfNearUtc,
            idGenerator: () => 'export-1',
          )
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(categoryId: fixture.obatCategory.id),
            format: ReportFormat.pdf,
          );

      final row = (await context.exportLogRows()).single;
      expect(row['report_type'], 'stok_lokasi');
      expect(row['format'], 'pdf');
      expect(row['scope_type'], 'warehouse');
      expect(row['location_id'], fixture.warehouse.id);
      expect(row['category_id'], fixture.obatCategory.id);
      expect(row['branch_id'], isNull);
      expect(row['exported_by'], fixture.warehouseUser.id);
      expect(row['file_name'], endsWith('.pdf'));
      expect(row['sync_summary'], isNotEmpty);
      expect(row['row_count'], greaterThan(0));
      expect(row['sync_status'], 'pending');
      expect(row['deleted_at'], isNull);
    });

    test('periode as-of menyimpan start sama dengan end', () async {
      // §3.9: "as of one day" must not look like "a range whose start was lost".
      await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(),
            format: ReportFormat.xlsx,
          );

      final row = (await context.exportLogRows()).single;
      expect(row['period_start'], row['period_end']);
      expect(
        (row['period_start']! as String).startsWith(
          DateOnly.formatIso(fixture.asOfNearDate),
        ),
        isTrue,
      );
    });

    test('data_cutoff_at sama dengan waktu cetak di header', () async {
      await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(),
            format: ReportFormat.xlsx,
          );

      final row = (await context.exportLogRows()).single;
      expect(
        DateTime.parse(row['data_cutoff_at']! as String).toUtc(),
        fixture.asOfNearUtc,
      );
    });

    test('kartu stok mencatat item_id', () async {
      await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: ReportRequestDraft(
              reportType: ReportType.kartuStok,
              scopeType: ReportScopeType.warehouse,
              periodStart: fixture.postedDate,
              periodEnd: fixture.asOfNearDate,
              locationId: fixture.warehouse.id,
              filter: ReportFilter(itemId: fixture.obatItem.id),
            ),
            format: ReportFormat.pdf,
          );

      final row = (await context.exportLogRows()).single;
      expect(row['item_id'], fixture.obatItem.id);
      expect(row['report_type'], 'kartu_stok');
    });

    test('laporan kosong tetap diekspor dan dicatat', () async {
      // §52: an export that found nothing is exactly the kind of thing an audit
      // should record rather than swallow.
      final store = InMemoryReportFileStore();

      final artifact = await context
          .exportReport(
            clock: () => DateTime.utc(2026, 7, 19, 2),
            fileStore: store,
          )
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: ReportRequestDraft(
              reportType: ReportType.stokLokasi,
              scopeType: ReportScopeType.warehouse,
              periodStart: DateOnly.of(2026, 7, 19),
              periodEnd: DateOnly.of(2026, 7, 19),
              locationId: fixture.warehouse.id,
            ),
            format: ReportFormat.xlsx,
          );

      expect(artifact.rowCount, 0);
      expect(store.fileCount, 1);
      expect((await context.exportLogRows()).single['row_count'], 0);
    });

    test('dua ekspor menghasilkan dua log dan dua direktori', () async {
      // §37: the canonical name is deterministic, so the per-export directory is
      // what keeps the second file from overwriting the first.
      final store = InMemoryReportFileStore();
      var counter = 0;
      final useCase = context.exportReport(
        clock: () => fixture.asOfNearUtc,
        idGenerator: () => 'export-${counter++}',
        fileStore: store,
      );

      final first = await useCase.call(
        actorUserId: fixture.warehouseUser.id,
        draft: warehouseStockDraft(),
        format: ReportFormat.xlsx,
      );
      final second = await useCase.call(
        actorUserId: fixture.warehouseUser.id,
        draft: warehouseStockDraft(),
        format: ReportFormat.xlsx,
      );

      expect(first.fileName, second.fileName);
      expect(first.exportLogId, isNot(second.exportLogId));
      expect(await context.exportLogCount(), 2);
      expect(store.fileCount, 2);
    });
  });

  group('kegagalan', () {
    test('generasi gagal: tanpa file, tanpa log, tanpa share', () async {
      final store = InMemoryReportFileStore();
      final share = FakeReportShareGateway();

      await expectLater(
        context
            .exportReport(
              clock: () => fixture.asOfNearUtc,
              excelExporter: const FailingExcelReportExporter(),
              fileStore: store,
              shareGateway: share,
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              draft: warehouseStockDraft(),
              format: ReportFormat.xlsx,
            ),
        throwsA(isA<ReportExcelGenerationFailure>()),
      );

      expect(store.writtenFileNames, isEmpty);
      expect(share.shared, isEmpty);
      expect(await context.exportLogCount(), 0);
    });

    test('PDF gagal juga tidak meninggalkan jejak', () async {
      final share = FakeReportShareGateway();

      await expectLater(
        context
            .exportReport(
              clock: () => fixture.asOfNearUtc,
              pdfExporter: const FailingPdfReportExporter(),
              shareGateway: share,
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              draft: warehouseStockDraft(),
              format: ReportFormat.pdf,
            ),
        throwsA(isA<ReportPdfGenerationFailure>()),
      );

      expect(share.shared, isEmpty);
      expect(await context.exportLogCount(), 0);
    });

    test('penulisan file gagal: tanpa log, tanpa share', () async {
      final share = FakeReportShareGateway();

      await expectLater(
        context
            .exportReport(
              clock: () => fixture.asOfNearUtc,
              fileStore: const FailingReportFileStore(),
              shareGateway: share,
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              draft: warehouseStockDraft(),
              format: ReportFormat.xlsx,
            ),
        throwsA(isA<ReportFileWriteFailure>()),
      );

      expect(share.shared, isEmpty);
      expect(await context.exportLogCount(), 0);
    });

    test('pencatatan audit gagal: file dihapus, share tidak dibuka', () async {
      // §3.17, and the decision worth arguing about: the file was written fine, and
      // it is still removed — an unaccounted copy of clinic data is exactly what
      // G-L2 forbids.
      final store = InMemoryReportFileStore();
      final share = FakeReportShareGateway();

      await expectLater(
        context
            .exportReport(
              clock: () => fixture.asOfNearUtc,
              fileStore: store,
              shareGateway: share,
              reportingRepository: AuditFailingReportingRepository(
                context.reporting,
              ),
            )
            .call(
              actorUserId: fixture.warehouseUser.id,
              draft: warehouseStockDraft(),
              format: ReportFormat.xlsx,
            ),
        throwsA(isA<ReportAuditWriteFailure>()),
      );

      expect(store.writtenFileNames, hasLength(1));
      expect(store.deletedFileNames, hasLength(1));
      expect(store.fileCount, 0);
      expect(share.shared, isEmpty);
      expect(await context.exportLogCount(), 0);
    });

    test('share gagal: file dan log tetap ada', () async {
      // §3.16, the opposite call: once the audit row exists the export happened.
      final store = InMemoryReportFileStore();

      final artifact = await context
          .exportReport(
            clock: () => fixture.asOfNearUtc,
            fileStore: store,
            shareGateway: const FailingReportShareGateway(),
          )
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(),
            format: ReportFormat.xlsx,
          );

      expect(artifact.shareOutcome, ReportShareOutcome.unavailable);
      expect(store.fileCount, 1);
      expect(store.deletedFileNames, isEmpty);
      expect(await context.exportLogCount(), 1);
    });

    test('share dibatalkan: ekspor tetap sukses', () async {
      final artifact = await context
          .exportReport(
            clock: () => fixture.asOfNearUtc,
            shareGateway: FakeReportShareGateway(
              outcome: ReportShareOutcome.cancelled,
            ),
          )
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(),
            format: ReportFormat.xlsx,
          );

      expect(artifact.shareOutcome, ReportShareOutcome.cancelled);
      expect(await context.exportLogCount(), 1);
    });
  });

  group('akses pada jalur ekspor', () {
    test('perawat tidak dapat mengekspor stok warehouse', () async {
      // The export path re-checks against a reloaded actor: the screen never
      // offered this, and that is not why it is refused (§16).
      await expectLater(
        context
            .exportReport(clock: () => fixture.asOfNearUtc)
            .call(
              actorUserId: fixture.nurse.id,
              draft: warehouseStockDraft(),
              format: ReportFormat.xlsx,
            ),
        throwsA(isA<ReportAccessDeniedFailure>()),
      );
      expect(await context.exportLogCount(), 0);
    });

    test('akun dinonaktifkan setelah sesi dibuka ditolak', () async {
      // O-8: the actor is re-read, so a session that was valid a minute ago is not
      // a licence.
      await context.deactivate('users', fixture.warehouseUser.id);

      await expectLater(
        context
            .exportReport(clock: () => fixture.asOfNearUtc)
            .call(
              actorUserId: fixture.warehouseUser.id,
              draft: warehouseStockDraft(),
              format: ReportFormat.xlsx,
            ),
        throwsA(isA<ReportAccessDeniedFailure>()),
      );
      expect(await context.exportLogCount(), 0);
    });

    test('kepala cabang tidak dapat mengekspor cabang lain', () async {
      await expectLater(
        context
            .exportReport(clock: () => fixture.asOfNearUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              draft: ReportRequestDraft(
                reportType: ReportType.stokLokasi,
                scopeType: ReportScopeType.branchStore,
                periodStart: fixture.asOfNearDate,
                periodEnd: fixture.asOfNearDate,
                locationId: fixture.otherBranchStore.id,
              ),
              format: ReportFormat.xlsx,
            ),
        throwsA(isA<ReportAccessDeniedFailure>()),
      );
    });

    test('cabang pada log selalu cabang aktor, bukan yang diminta', () async {
      // §16: a branch-scoped role's branch is the policy's answer, never the form's.
      await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            draft: ReportRequestDraft(
              reportType: ReportType.stokLokasi,
              scopeType: ReportScopeType.branchAll,
              periodStart: fixture.asOfNearDate,
              periodEnd: fixture.asOfNearDate,
              branchId: fixture.otherBranch.id,
            ),
            format: ReportFormat.xlsx,
          );

      final row = (await context.exportLogRows()).single;
      expect(row['branch_id'], fixture.branch.id);
    });
  });

  group('riwayat ekspor', () {
    test('super admin melihat seluruh log, terbaru dulu', () async {
      var counter = 0;
      final useCase = context.exportReport(
        clock: () => fixture.asOfNearUtc,
        idGenerator: () => 'export-${counter++}',
      );
      await useCase.call(
        actorUserId: fixture.warehouseUser.id,
        draft: warehouseStockDraft(),
        format: ReportFormat.xlsx,
      );
      await useCase.call(
        actorUserId: fixture.warehouseUser.id,
        draft: warehouseStockDraft(),
        format: ReportFormat.pdf,
      );

      final logs = await context.watchExportHistory
          .call(actor: fixture.superAdmin)
          .first;

      expect(logs, hasLength(2));
      expect(
        logs.first.exportedAtUtc.isBefore(logs.last.exportedAtUtc),
        isFalse,
      );
    });

    test('peran lain melihat daftar kosong', () async {
      await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(),
            format: ReportFormat.xlsx,
          );

      for (final actor in [
        fixture.warehouseUser,
        fixture.branchHead,
        fixture.nurse,
      ]) {
        expect(
          await context.watchExportHistory.call(actor: actor).first,
          isEmpty,
          reason: actor.role.dbValue,
        );
      }
    });

    test('ekspor sendiri terlihat oleh pemiliknya saja', () async {
      await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(),
            format: ReportFormat.xlsx,
          );

      expect(
        await context.watchExportHistory.own(actor: fixture.warehouseUser),
        hasLength(1),
      );
      expect(
        await context.watchExportHistory.own(actor: fixture.branchHead),
        isEmpty,
      );
    });

    test('detail log memakai label historis, bukan UUID', () async {
      final artifact = await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(categoryId: fixture.obatCategory.id),
            format: ReportFormat.xlsx,
          );
      // The branch is closed after the export; the audit must still name it.
      await context.deactivate('users', fixture.warehouseUser.id);

      final detail = await context.getExportLogDetail.call(
        actor: fixture.superAdmin,
        exportLogId: artifact.exportLogId,
      );

      expect(detail, isNotNull);
      expect(detail!.exportedByLabel, fixture.warehouseUser.fullName);
      expect(detail.categoryLabel, fixture.obatCategory.name);
      expect(detail.locationLabel, fixture.warehouse.name);
    });

    test('detail ditolak untuk peran lain dengan jawaban yang sama', () async {
      // §43: "no such log" and "not your business" must be indistinguishable.
      final artifact = await context
          .exportReport(clock: () => fixture.asOfNearUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            draft: warehouseStockDraft(),
            format: ReportFormat.xlsx,
          );

      expect(
        await context.getExportLogDetail.call(
          actor: fixture.branchHead,
          exportLogId: artifact.exportLogId,
        ),
        isNull,
      );
      expect(
        await context.getExportLogDetail.call(
          actor: fixture.superAdmin,
          exportLogId: 'tidak-ada',
        ),
        isNull,
      );
    });
  });
}
