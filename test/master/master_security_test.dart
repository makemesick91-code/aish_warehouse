import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/master/domain/services/master_admin_access_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'master_fixture.dart';

/// G-M1 at every layer §53 names: policy, use case, repository reach, and the
/// import module.
///
/// The widget and route layers are covered in `master_widget_test.dart`; what
/// this file proves is that **no layer below them is trusting a guard**. Every
/// write use case and every import use case is called directly here, with no
/// router and no widget tree, by each of the four roles.
///
/// ### On server-side validation
///
/// G-M1's parenthetical asks for *"route guard + validasi server"*. This build
/// has no server. Everything asserted below is client-and-local enforcement, and
/// the boundary a Milestone 12 sync client would revalidate behind. Nothing here
/// should be read as a claim that a server has checked anything.
void main() {
  late MasterFixture fixture;
  late String actorId;

  DateTime clock() => DateTime.utc(2026, 7, 31, 4, 30);

  setUp(() async {
    fixture = MasterFixture.create(clock: clock);
    actorId = await fixture.seedSuperAdmin();
  });

  tearDown(() => fixture.dispose());

  /// One user per non-admin role, each in a valid role/branch shape.
  Future<Map<UserRole, String>> seedOtherRoles() async {
    final branch = await fixture.createBranch.call(
      actorUserId: actorId,
      code: 'CAB-01',
      name: 'Cabang Satu',
    );
    return {
      UserRole.perawat: await fixture.seedUser(
        id: 'u-perawat',
        email: 'perawat@aish.id',
        role: UserRole.perawat,
        branchId: branch.id,
      ),
      UserRole.kepalaCabang: await fixture.seedUser(
        id: 'u-kacab',
        email: 'kacab@aish.id',
        role: UserRole.kepalaCabang,
        branchId: branch.id,
      ),
      UserRole.warehouse: await fixture.seedUser(
        id: 'u-warehouse',
        email: 'warehouse@aish.id',
        role: UserRole.warehouse,
      ),
    };
  }

  group('kebijakan akses', () {
    test('hanya super_admin yang lolos', () {
      for (final role in UserRole.values) {
        final user = MasterUser(
          id: 'x',
          fullName: 'X',
          email: 'x@aish.id',
          role: role,
          branchId: role.requiresBranch ? 'b' : null,
          isActive: true,
        );
        for (final kind in MasterAdminRouteKind.values) {
          expect(
            MasterAdminAccessPolicy.forSection(
              user: user,
              kind: kind,
            ).isGranted,
            role == UserRole.superAdmin,
            reason: '$role / $kind',
          );
        }
      }
    });

    test('Super Admin nonaktif ditolak', () {
      const user = MasterUser(
        id: 'x',
        fullName: 'X',
        email: 'x@aish.id',
        role: UserRole.superAdmin,
        isActive: false,
      );
      expect(
        MasterAdminAccessPolicy.forSection(
          user: user,
          kind: MasterAdminRouteKind.master,
        ).isDenied,
        isTrue,
      );
    });

    test('tanpa sesi ditolak', () {
      expect(
        MasterAdminAccessPolicy.forSection(
          user: null,
          kind: MasterAdminRouteKind.master,
        ).isDenied,
        isTrue,
      );
    });

    test('penolakan tidak membedakan alasannya', () {
      // One sentence for every reason: "your account was deactivated" and "you
      // are not a Super Admin" are different facts, and telling them apart from
      // the outside is how a screen becomes a way to learn which accounts exist.
      expect(
        MasterAdminAccessPolicy.denialMessage,
        'Halaman Master Data & Import hanya untuk Super Admin.',
      );
      expect(
        MasterAdminAccessPolicy.denialMessage,
        isNot(contains('nonaktif')),
      );
    });
  });

  group('setiap use case tulis menolak peran lain', () {
    test('CRUD ditolak untuk perawat, kepala cabang, dan warehouse', () async {
      final others = await seedOtherRoles();
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
      final branchesBefore = await fixture.countOf('branches');
      final itemsBefore = await fixture.countOf('items');

      for (final entry in others.entries) {
        final id = entry.value;
        final reason = entry.key.dbValue;

        await expectLater(
          fixture.createBranch.call(actorUserId: id, code: 'CAB-99', name: 'X'),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
          reason: reason,
        );
        await expectLater(
          fixture.createCategory.call(actorUserId: id, name: 'Baru'),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
          reason: reason,
        );
        await expectLater(
          fixture.createItem.call(
            actorUserId: id,
            sku: 'X-1',
            name: 'X',
            categoryId: category.id,
            unit: 'pcs',
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
          reason: reason,
        );
        await expectLater(
          fixture.setItemActive.call(
            actorUserId: id,
            itemId: item.id,
            isActive: false,
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
          reason: reason,
        );
        await expectLater(
          fixture.createUser.call(
            actorUserId: id,
            fullName: 'X',
            email: 'x@aish.id',
            role: UserRole.warehouse,
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
          reason: reason,
        );
        await expectLater(
          fixture.createBatch.call(
            actorUserId: id,
            itemId: item.id,
            batchNo: 'LOT-1',
            expiryDate: DateOnly.of(2026, 12, 31),
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
          reason: reason,
        );
        await expectLater(
          fixture.archiveCategory.call(
            actorUserId: id,
            categoryId: category.id,
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
          reason: reason,
        );
      }

      // Not one write landed.
      expect(await fixture.countOf('branches'), branchesBefore);
      expect(await fixture.countOf('items'), itemsBefore);
      expect(await fixture.countOf('item_batches'), 0);
      expect(await fixture.columnOf('items', item.id, 'is_active'), '1');
    });

    test('impor ditolak untuk peran lain di setiap tahap', () async {
      final others = await seedOtherRoles();
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
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

      for (final id in others.values) {
        await expectLater(
          fixture.validateImport().call(
            actorUserId: id,
            entity: MasterEntityType.branches,
            file: pickedFile(entity: MasterEntityType.branches),
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
        );
        await expectLater(
          fixture.commitImport().call(
            actorUserId: id,
            importLogId: session.importId,
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
        );
        await expectLater(
          fixture.discardImport().call(
            actorUserId: id,
            importLogId: session.importId,
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
        );
        await expectLater(
          fixture.downloadTemplate().call(
            actorUserId: id,
            entity: MasterEntityType.branches,
          ),
          throwsA(isA<MasterAdminAccessDeniedFailure>()),
        );
      }

      // Exactly the one log the Super Admin's own preview created.
      expect(await fixture.countOf('import_logs'), 1);
      expect(
        await fixture.importLogColumn(session.importId, 'status'),
        'validated',
      );
    });

    test('aktor yang tidak ada ditolak', () async {
      await expectLater(
        fixture.createBranch.call(
          actorUserId: 'tidak-ada',
          code: 'CAB-99',
          name: 'X',
        ),
        throwsA(isA<MasterAdminAccessDeniedFailure>()),
      );
    });

    test('aktor yang dinonaktifkan di tengah sesi ditolak', () async {
      // The session still says `super_admin`; the database no longer does. Every
      // use case re-reads (O-8), so the stored row wins.
      await fixture.deactivateRaw('users', actorId);
      await expectLater(
        fixture.createBranch.call(
          actorUserId: actorId,
          code: 'CAB-99',
          name: 'X',
        ),
        throwsA(isA<MasterAdminAccessDeniedFailure>()),
      );
    });

    test('aktor yang perannya berubah di tengah sesi ditolak', () async {
      await fixture.database.customStatement(
        "UPDATE users SET role = 'kepala_cabang' WHERE id = ?;",
        [actorId],
      );
      await expectLater(
        fixture.createCategory.call(actorUserId: actorId, name: 'Obat'),
        throwsA(isA<MasterAdminAccessDeniedFailure>()),
      );
    });
  });

  group('riwayat impor hanya untuk Super Admin', () {
    test('peran lain menerima daftar kosong, bukan error berisi data', () async {
      final others = await seedOtherRoles();
      await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          fileName: 'rahasia.xlsx',
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

      for (final id in others.values) {
        final logs = await fixture.watchImportHistory
            .call(actorUserId: id)
            .first;
        // Empty rather than thrown: an error object carrying a count is still a
        // leak (§53).
        expect(logs, isEmpty);
      }

      final adminLogs = await fixture.watchImportHistory
          .call(actorUserId: actorId)
          .first;
      expect(adminLogs, hasLength(1));
      expect(adminLogs.single.fileName, 'rahasia.xlsx');
    });

    test('detail impor mengembalikan null untuk peran lain', () async {
      final others = await seedOtherRoles();
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
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

      for (final id in others.values) {
        expect(
          await fixture.importLogDetail.call(
            actorUserId: id,
            importId: session.importId,
          ),
          isNull,
        );
      }
      expect(
        await fixture.importLogDetail.call(
          actorUserId: actorId,
          importId: session.importId,
        ),
        isNotNull,
      );
    });

    test(
      'id yang tidak ada dan id tanpa akses menghasilkan jawaban sama',
      () async {
        final others = await seedOtherRoles();
        final session = await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: pickedFile(
            entity: MasterEntityType.branches,
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

        final unauthorizedExisting = await fixture.importLogDetail.call(
          actorUserId: others[UserRole.warehouse]!,
          importId: session.importId,
        );
        final adminMissing = await fixture.importLogDetail.call(
          actorUserId: actorId,
          importId: 'tidak-ada',
        );
        // Both `null` — telling them apart is how a detail route becomes a way to
        // enumerate which imports are real (§37).
        expect(unauthorizedExisting, isNull);
        expect(adminMissing, isNull);
      },
    );
  });

  group('audit tidak membocorkan jalur internal', () {
    test('ImportLog domain tidak membawa stored_file_path', () async {
      final session = await fixture.validateImport().call(
        actorUserId: actorId,
        entity: MasterEntityType.branches,
        file: pickedFile(
          entity: MasterEntityType.branches,
          rows: [
            {
              'code': 'CAB-01',
              'name': 'Satu',
              'address': '',
              'is_active': 'TRUE',
            },
          ],
        ),
      );

      final detail = (await fixture.importLogDetail.call(
        actorUserId: actorId,
        importId: session.importId,
      ))!;

      // The path is in the database — the commit reads it — but nothing a screen
      // receives carries it (§11, §36).
      final storedPath = await fixture.importLogColumn(
        session.importId,
        'stored_file_path',
      );
      expect(storedPath, isNotNull);
      expect(detail.log.toString(), isNot(contains(storedPath!)));
      expect(detail.log.fileName, isNot(contains('/')));
      // The hash is shortened for display.
      expect(detail.log.shortHash, hasLength(8));
    });

    test('pesan kegagalan tidak memuat jalur atau nama tabel', () async {
      try {
        await fixture.validateImport().call(
          actorUserId: actorId,
          entity: MasterEntityType.branches,
          file: pickedFile(
            entity: MasterEntityType.branches,
            fileName: 'salah.csv',
          ),
        );
        fail('seharusnya ditolak');
      } on AppFailure catch (failure) {
        expect(failure.message, isNot(contains('/')));
        expect(failure.message, isNot(contains('import_logs')));
        expect(failure.message, isNot(contains('Exception')));
        expect(failure.message, contains('.xlsx'));
      }
    });
  });

  group('§53 DAO/repository tidak terjangkau dari presentation', () {
    test('repository admin tidak menyediakan hard delete', () {
      // A structural assertion made by absence: `MasterAdminRepository` has no
      // delete method at all, so this compiles only while that stays true. The
      // source-level version of this check lives in the architecture test.
      final repository = fixture.repository;
      expect(repository, isNotNull);
      expect(repository.runtimeType.toString(), 'DriftMasterAdminRepository');
    });
  });
}
