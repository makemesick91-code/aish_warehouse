import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/app/guards/master_admin_route_guard.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/master/domain/models/import_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/master/domain/services/master_admin_access_policy.dart';
import 'package:aish_warehouse/features/master/presentation/pages/import_log_detail_page.dart';
import 'package:aish_warehouse/features/master/presentation/pages/master_dashboard_page.dart';
import 'package:aish_warehouse/features/master/presentation/pages/master_entity_list_pages.dart';
import 'package:aish_warehouse/features/master/presentation/pages/master_import_page.dart';
import 'package:aish_warehouse/features/master/presentation/providers/master_admin_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/widget_harness.dart';
import 'master_fixture.dart';

/// §56 — the screens, and §53's fourth layer: what an unauthorized widget tree
/// contains.
///
/// Every test here pumps against the in-memory database the domain tests use and
/// against fake gateways, so no picker opens and no share sheet appears. What is
/// being asserted is the *rendering* and the *wiring*: the rules themselves are
/// covered by the use-case tests, and a screen agreeing with them is what this
/// file adds.
void main() {
  late MasterFixture fixture;
  late String actorId;
  late MasterUser superAdmin;

  DateTime clock() => DateTime.utc(2026, 7, 31, 4, 30);

  setUp(() async {
    fixture = MasterFixture.create(clock: clock);
    actorId = await fixture.seedSuperAdmin();
    superAdmin = (await fixture.repository.adminUserById(actorId))!;
  });

  tearDown(() => fixture.dispose());

  Future<void> pump(
    WidgetTester tester, {
    required Widget child,
    MasterUser? actingAs,
    List<Override> overrides = const <Override>[],
    Size size = const Size(800, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(fixture.database),
          currentSessionProvider.overrideWith(
            () => FixedSessionController(actingAs ?? superAdmin),
          ),
          ...overrides,
        ],
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<({String branchId, String categoryId, String itemId})> seed() async {
    final branch = await fixture.createBranch.call(
      actorUserId: actorId,
      code: 'CAB-01',
      name: 'Cabang Satu',
    );
    final category = await fixture.createCategory.call(
      actorUserId: actorId,
      name: 'Obat',
    );
    final item = await fixture.createItem.call(
      actorUserId: actorId,
      sku: 'DEN-0001',
      name: 'Anestesi',
      categoryId: category.id,
      unit: 'ampul',
      hasExpiry: true,
    );
    return (branchId: branch.id, categoryId: category.id, itemId: item.id);
  }

  group('§39 dashboard master', () {
    testWidgets('menampilkan enam kartu dan dua pintu masuk import', (
      tester,
    ) async {
      await seed();
      await pump(tester, child: const MasterDashboardPage());

      for (final entity in MasterEntityType.values) {
        expect(
          find.byKey(Key('master-card-${entity.dbValue}')),
          findsOneWidget,
          reason: entity.dbValue,
        );
        expect(find.text(entity.label), findsWidgets);
      }
      expect(
        find.byKey(const Key('master-dashboard-template-import')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('master-dashboard-import-history')),
        findsOneWidget,
      );
    });

    testWidgets('menampilkan hitungan aktif dan nonaktif', (tester) async {
      final seeded = await seed();
      await fixture.setItemActive.call(
        actorUserId: actorId,
        itemId: seeded.itemId,
        isActive: false,
      );

      await pump(tester, child: const MasterDashboardPage());
      expect(find.text('0 aktif'), findsWidgets);
      expect(find.text('1 nonaktif/arsip'), findsWidgets);
    });

    testWidgets('layar sempit tidak overflow', (tester) async {
      await seed();
      await pump(
        tester,
        child: const MasterDashboardPage(),
        size: const Size(320, 640),
      );
      // `pumpAndSettle` throws on an overflow exception, and `takeException`
      // catches one that was merely reported.
      expect(tester.takeException(), isNull);
    });
  });

  group('§53 pohon widget tanpa akses tidak memuat data', () {
    for (final role in const [
      UserRole.perawat,
      UserRole.kepalaCabang,
      UserRole.warehouse,
    ]) {
      testWidgets('${role.dbValue} ditolak dan tidak melihat apa pun', (
        tester,
      ) async {
        final seeded = await seed();
        await fixture.seedUser(
          id: 'other-${role.dbValue}',
          email: '${role.dbValue}@aish.id',
          role: role,
          branchId: role.requiresBranch ? seeded.branchId : null,
        );
        final other = (await fixture.repository.adminUserById(
          'other-${role.dbValue}',
        ))!;

        await pump(
          tester,
          actingAs: other,
          child: const MasterAdminSectionGuard(
            kind: MasterAdminRouteKind.master,
            builder: _masterDashboard,
          ),
        );

        expect(find.byType(AccessDeniedPage), findsOneWidget);
        // Not one entity count, SKU, email or label anywhere in the tree.
        expect(find.text('Barang'), findsNothing);
        expect(find.textContaining('DEN-0001'), findsNothing);
        expect(find.textContaining('admin@aish.id'), findsNothing);
        expect(find.textContaining('aktif'), findsNothing);
        expect(find.byKey(const Key('master-card-items')), findsNothing);
      });
    }

    testWidgets('Super Admin nonaktif ditolak', (tester) async {
      await seed();
      await fixture.deactivateRaw('users', actorId);

      await pump(
        tester,
        child: const MasterAdminSectionGuard(
          kind: MasterAdminRouteKind.master,
          builder: _masterDashboard,
        ),
      );
      expect(find.byType(AccessDeniedPage), findsOneWidget);
    });

    testWidgets('daftar barang kosong untuk peran lain', (tester) async {
      final seeded = await seed();
      await fixture.seedUser(
        id: 'kacab',
        email: 'kacab@aish.id',
        role: UserRole.kepalaCabang,
        branchId: seeded.branchId,
      );
      final other = (await fixture.repository.adminUserById('kacab'))!;

      // The page pumped **directly**, with no guard: a provider can be read from
      // anywhere, and each one re-applies the policy (§53).
      await pump(tester, actingAs: other, child: const MasterItemListPage());

      expect(find.textContaining('DEN-0001'), findsNothing);
      expect(find.byKey(const Key('master-list-empty')), findsOneWidget);
    });

    testWidgets('riwayat import kosong untuk peran lain', (tester) async {
      final seeded = await seed();
      await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          fileName: 'rahasia-cabang.xlsx',
          rows: [
            {
              'code': 'CAB-77',
              'name': 'Tujuh',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );
      await fixture.seedUser(
        id: 'perawat',
        email: 'perawat@aish.id',
        role: UserRole.perawat,
        branchId: seeded.branchId,
      );
      final other = (await fixture.repository.adminUserById('perawat'))!;

      await pump(tester, actingAs: other, child: const MasterImportPage());
      await tester.tap(find.byKey(const Key('import-tab-history')));
      await tester.pumpAndSettle();

      expect(find.textContaining('rahasia-cabang.xlsx'), findsNothing);
      expect(find.byKey(const Key('import-history-empty')), findsOneWidget);
    });
  });

  group('§40 daftar master', () {
    testWidgets('menampilkan barang dengan badge dan tag sync', (tester) async {
      final seeded = await seed();
      await fixture.markItemUsed(itemId: seeded.itemId, actorUserId: actorId);

      await pump(tester, child: const MasterItemListPage());

      expect(find.byKey(const Key('item-row-DEN-0001')), findsOneWidget);
      expect(find.byKey(const Key('master-usage-badge')), findsOneWidget);
      expect(find.text('Menunggu sinkron'), findsWidgets);
      expect(find.byKey(const Key('master-list-add')), findsOneWidget);
    });

    testWidgets('filter nonaktif menyembunyikan lalu menampilkan', (
      tester,
    ) async {
      final seeded = await seed();
      await fixture.setItemActive.call(
        actorUserId: actorId,
        itemId: seeded.itemId,
        isActive: false,
      );

      await pump(tester, child: const MasterItemListPage());
      expect(find.byKey(const Key('item-row-DEN-0001')), findsNothing);
      expect(find.byKey(const Key('master-list-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('master-list-include-inactive')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('item-row-DEN-0001')), findsOneWidget);
      expect(
        find.byKey(const Key('master-lifecycle-inactive')),
        findsOneWidget,
      );
    });

    testWidgets('pencarian menyaring daftar', (tester) async {
      final seeded = await seed();
      await fixture.createItem.call(
        actorUserId: actorId,
        sku: 'APD-0001',
        name: 'Masker',
        categoryId: seeded.categoryId,
        unit: 'pcs',
      );

      await pump(tester, child: const MasterItemListPage());
      expect(find.byKey(const Key('item-row-DEN-0001')), findsOneWidget);
      expect(find.byKey(const Key('item-row-APD-0001')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('master-list-search')),
        'masker',
      );
      // The debounce §38 asks for.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('item-row-DEN-0001')), findsNothing);
      expect(find.byKey(const Key('item-row-APD-0001')), findsOneWidget);
    });

    testWidgets('kosakata siklus hidup: nonaktifkan, bukan hapus', (
      tester,
    ) async {
      await seed();
      await pump(tester, child: const MasterItemListPage());

      expect(find.text('Nonaktifkan'), findsWidgets);
      expect(find.textContaining('Hapus'), findsNothing);
      expect(find.textContaining('Delete'), findsNothing);
    });

    testWidgets('kategori memakai Arsipkan/Pulihkan', (tester) async {
      await fixture.createCategory.call(actorUserId: actorId, name: 'Obat');
      await pump(tester, child: const MasterCategoryListPage());

      expect(find.text('Arsipkan'), findsWidgets);
      expect(find.textContaining('Hapus'), findsNothing);
    });

    testWidgets('pengguna menampilkan badge Anda dan menyembunyikan aksinya', (
      tester,
    ) async {
      await pump(tester, child: const MasterUserListPage());

      expect(find.byKey(const Key('user-self-badge')), findsOneWidget);
      // §21: the actor cannot deactivate themselves, so the control is not there.
      expect(find.byKey(const Key('master-deactivate')), findsNothing);
    });

    testWidgets('konfirmasi muncul sebelum menonaktifkan', (tester) async {
      final seeded = await seed();
      await pump(tester, child: const MasterItemListPage());

      await tester.tap(find.byKey(const Key('master-deactivate')));
      await tester.pumpAndSettle();

      expect(find.text('Nonaktifkan'), findsWidgets);
      expect(find.textContaining('riwayat transaksinya tetap'), findsOneWidget);

      await tester.tap(find.byKey(const Key('master-confirm')));
      await tester.pumpAndSettle();

      expect(await fixture.columnOf('items', seeded.itemId, 'is_active'), '0');
    });

    testWidgets('ruangan menampilkan lokasi stoknya', (tester) async {
      final seeded = await seed();
      await fixture.createRoom.call(
        actorUserId: actorId,
        branchId: seeded.branchId,
        code: 'R1',
        name: 'Ruang Dental 1',
      );

      await pump(tester, child: const MasterRoomListPage());
      expect(find.byKey(const Key('room-row-CAB-01-R1')), findsOneWidget);
      expect(find.textContaining('Lokasi stok:'), findsOneWidget);
    });
  });

  group('§42 layar import', () {
    Future<void> pumpImport(
      WidgetTester tester, {
      PickedImportFile? pick,
      Size size = const Size(800, 1200),
    }) => pump(
      tester,
      child: const MasterImportPage(),
      size: size,
      overrides: [
        masterImportFilePickerProvider.overrideWithValue(
          FakeMasterImportFilePicker(pick),
        ),
        importSourceFileStoreProvider.overrideWithValue(
          fixture.sourceFileStore,
        ),
        masterTemplateFileStoreProvider.overrideWithValue(
          fixture.templateFileStore,
        ),
        masterTemplateShareGatewayProvider.overrideWithValue(
          fixture.shareGateway,
        ),
      ],
    );

    testWidgets('tiga tab dan enam pilihan entitas', (tester) async {
      await pumpImport(tester);

      expect(find.byKey(const Key('import-tab-new')), findsOneWidget);
      expect(find.byKey(const Key('import-tab-preview')), findsOneWidget);
      expect(find.byKey(const Key('import-tab-history')), findsOneWidget);
      for (final entity in MasterEntityType.values) {
        expect(
          find.byKey(Key('import-entity-${entity.dbValue}')),
          findsOneWidget,
        );
      }
    });

    testWidgets('mengunduh template melalui gateway palsu', (tester) async {
      await pumpImport(tester);
      await tester.tap(find.byKey(const Key('import-download-template')));
      await tester.pumpAndSettle();

      expect(fixture.shareGateway.shared, hasLength(1));
      expect(find.byKey(const Key('import-info')), findsOneWidget);
      // Never claims the file went to Downloads (§26).
      expect(find.textContaining('Downloads'), findsNothing);
      expect(await fixture.countOf('import_logs'), 0);
    });

    testWidgets('picker yang dibatalkan bukan error', (tester) async {
      await pumpImport(tester);
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-error')), findsNothing);
      expect(await fixture.countOf('import_logs'), 0);
    });

    testWidgets('validasi menampilkan ringkasan dan setiap baris', (
      tester,
    ) async {
      await pumpImport(
        tester,
        pick: pickedFile(
          entity: MasterEntityType.items,
          fileName: 'barang.xlsx',
          rows: const [
            {
              'sku': 'BARU-1',
              'name': 'Barang Baru',
              'category_name': 'Obat',
              'unit': 'pcs',
              'min_stock_room': '1',
              'min_stock_branch': '2',
              'has_expiry': 'FALSE',
              'expiry_alert_days': '30',
              'is_active': 'TRUE',
            },
          ],
        ),
      );
      await seed();

      await tester.tap(find.byKey(const Key('import-entity-items')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-picked-file')), findsOneWidget);

      await tester.tap(find.byKey(const Key('import-tab-preview')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-summary-total')), findsOneWidget);
      expect(find.text('Total: 1'), findsOneWidget);
      expect(find.text('Tambah: 1'), findsOneWidget);
      expect(find.text('Gagal: 0'), findsOneWidget);
      expect(find.byKey(const Key('import-row-3')), findsOneWidget);
    });

    testWidgets('commit nonaktif ketika ada baris gagal', (tester) async {
      await seed();
      await pumpImport(
        tester,
        pick: pickedFile(
          entity: MasterEntityType.branches,
          rows: const [
            {'code': '', 'name': '', 'address': '', 'is_active': 'salah'},
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('import-entity-branches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-tab-preview')));
      await tester.pumpAndSettle();

      final commit = tester.widget<FilledButton>(
        find.byKey(const Key('import-commit')),
      );
      // Structurally disabled, not merely styled (§42).
      expect(commit.onPressed, isNull);
      expect(find.byKey(const Key('import-has-errors')), findsOneWidget);
      expect(find.byKey(const Key('import-discard')), findsOneWidget);
    });

    testWidgets('commit menerapkan impor setelah konfirmasi', (tester) async {
      await seed();
      await pumpImport(
        tester,
        pick: pickedFile(
          entity: MasterEntityType.branches,
          rows: const [
            {
              'code': 'CAB-99',
              'name': 'Cabang Baru',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('import-entity-branches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-tab-preview')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import-commit')));
      await tester.pumpAndSettle();

      // The three facts §42 requires the dialog to state.
      expect(find.textContaining('satu transaksi'), findsOneWidget);
      expect(
        find.textContaining('Tidak ada data yang dihapus'),
        findsOneWidget,
      );
      expect(find.textContaining('pending untuk sinkronisasi'), findsOneWidget);

      await tester.tap(find.byKey(const Key('import-commit-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-finalised')), findsOneWidget);
      expect((await fixture.repository.branchesByCode('CAB-99')), hasLength(1));
    });

    testWidgets('discard membatalkan tanpa mengubah master', (tester) async {
      await seed();
      final fingerprint = await fixture.masterFingerprint();
      await pumpImport(
        tester,
        pick: pickedFile(
          entity: MasterEntityType.branches,
          rows: const [
            {
              'code': 'CAB-99',
              'name': 'Cabang Baru',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('import-entity-branches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-tab-preview')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('import-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-discard-confirm')));
      await tester.pumpAndSettle();

      expect(await fixture.masterFingerprint(), fingerprint);
      expect(find.byKey(const Key('import-no-preview')), findsOneWidget);
    });

    testWidgets('filter baris menyaring pratinjau', (tester) async {
      await seed();
      await pumpImport(
        tester,
        pick: pickedFile(
          entity: MasterEntityType.branches,
          rows: const [
            {
              'code': 'CAB-99',
              'name': 'Valid',
              'address': '',
              'is_active': 'TRUE',
            },
            {'code': '', 'name': '', 'address': '', 'is_active': 'TRUE'},
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('import-entity-branches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-tab-preview')));
      await tester.pumpAndSettle();

      // A file with errors opens on the error filter.
      expect(find.byKey(const Key('import-row-4')), findsOneWidget);
      expect(find.byKey(const Key('import-row-3')), findsNothing);

      await tester.tap(find.byKey(const Key('import-row-filter-valid')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-row-3')), findsOneWidget);
      expect(find.byKey(const Key('import-row-4')), findsNothing);
    });

    testWidgets('file baru ditolak selama pratinjau belum diproses', (
      tester,
    ) async {
      await seed();
      await pumpImport(
        tester,
        pick: pickedFile(
          entity: MasterEntityType.branches,
          rows: const [
            {
              'code': 'CAB-99',
              'name': 'Valid',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('import-entity-branches')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pumpAndSettle();

      // A second upload while a validated preview is unconsumed: refused with an
      // explanation rather than silently replacing it (§43).
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import-error')), findsOneWidget);
      expect(find.textContaining('belum diproses'), findsOneWidget);
      expect(await fixture.countOf('import_logs'), 1);
    });

    testWidgets('layar sempit tidak overflow', (tester) async {
      await seed();
      await pumpImport(tester, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });

    testWidgets('halaman dibuang saat validasi tidak melempar', (tester) async {
      await seed();
      final overrides = <Override>[
        appDatabaseProvider.overrideWithValue(fixture.database),
        currentSessionProvider.overrideWith(
          () => FixedSessionController(superAdmin),
        ),
        masterImportFilePickerProvider.overrideWithValue(
          FakeMasterImportFilePicker(
            pickedFile(
              entity: MasterEntityType.branches,
              rows: const [
                {
                  'code': 'CAB-99',
                  'name': 'Valid',
                  'address': '',
                  'is_active': 'TRUE',
                },
              ],
            ),
          ),
        ),
        importSourceFileStoreProvider.overrideWithValue(
          fixture.sourceFileStore,
        ),
        masterTemplateFileStoreProvider.overrideWithValue(
          fixture.templateFileStore,
        ),
        masterTemplateShareGatewayProvider.overrideWithValue(
          fixture.shareGateway,
        ),
      ];

      // The **same** scope throughout, with only the child swapped: Riverpod
      // forbids changing the number of overrides on an existing `ProviderScope`,
      // and re-pumping a differently-sized list would fail the test on the
      // harness rather than on the behaviour under test.
      Future<void> pumpChild(Widget child) => tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(home: child),
        ),
      );

      await pumpChild(const MasterImportPage());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-entity-branches')));
      await tester.pumpAndSettle();

      // Start the validation, then tear the page down mid-flight.
      await tester.tap(find.byKey(const Key('import-pick-file')));
      await tester.pump();
      await pumpChild(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // No dead-State callback and no write into a disposed controller. Whatever
      // reached the database before the teardown is still there — the audit row
      // is a fact, and the operator finds it in the history (§43).
      expect(tester.takeException(), isNull);
    });
  });

  group('§36 detail audit', () {
    testWidgets('menampilkan metadata tanpa jalur file', (tester) async {
      await seed();
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          fileName: 'cabang.xlsx',
          rows: const [
            {
              'code': 'CAB-99',
              'name': 'Baru',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );

      await pump(
        tester,
        child: ImportLogDetailPage(importId: session.importId),
      );

      expect(find.text('cabang.xlsx'), findsOneWidget);
      expect(find.text('Tervalidasi'), findsWidgets);
      expect(find.text(MasterTemplateVersion.current), findsOneWidget);
      expect(find.text(ImportLogDetail.sourceFileNotice), findsOneWidget);
      // The stored path never appears, and the hash is shortened.
      final storedPath = await fixture.importLogColumn(
        session.importId,
        'stored_file_path',
      );
      expect(find.textContaining(storedPath!), findsNothing);
      expect(
        find.textContaining('${session.sourceFile.shortHash}…'),
        findsOneWidget,
      );
    });

    testWidgets('id yang tidak ada menampilkan pesan netral', (tester) async {
      await pump(
        tester,
        child: const ImportLogDetailPage(importId: 'tidak-ada'),
      );
      expect(find.byKey(const Key('import-detail-missing')), findsOneWidget);
    });
  });
}

Widget _masterDashboard(BuildContext context) => const MasterDashboardPage();
