import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/master/domain/models/master_admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'master_fixture.dart';

/// §52 (CRUD), §49 (historical integrity), §21 (user-role safeguards) and §22
/// (branch/room stock locations).
///
/// The invariant running through the whole file is §23's: **a rule a form
/// enforces is the rule the import enforces**, because both call the same
/// policies. Where a rule is asserted here on the CRUD path,
/// `master_import_commit_test.dart` asserts the same rule on the workbook path.
void main() {
  late MasterFixture fixture;
  late String actorId;

  DateTime clock() => DateTime.utc(2026, 7, 31, 4, 30);

  setUp(() async {
    fixture = MasterFixture.create(clock: clock);
    actorId = await fixture.seedSuperAdmin();
  });

  tearDown(() => fixture.dispose());

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
      minStockRoom: 2,
      minStockBranch: 10,
      hasExpiry: true,
      expiryAlertDays: 30,
    );
    return (branchId: branch.id, categoryId: category.id, itemId: item.id);
  }

  group('§22 cabang membawa tepat satu gudang', () {
    test('membuat cabang membuat satu branch_store', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Cabang Satu',
      );

      expect(await fixture.repository.branchStoreLocationCount(branch.id), 1);
      final rows = await fixture.database
          .customSelect(
            "SELECT type, branch_id, room_id, name, sync_status "
            'FROM stock_locations;',
          )
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('type'), 'branch_store');
      expect(rows.single.read<String>('branch_id'), branch.id);
      expect(rows.single.read<String?>('room_id'), isNull);
      expect(rows.single.read<String>('sync_status'), 'pending');
    });

    test('mengganti nama cabang mengganti nama gudang, bukan id-nya', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Cabang Satu',
      );
      final locationId =
          (await fixture.database
                  .customSelect('SELECT id FROM stock_locations;')
                  .getSingle())
              .read<String>('id');

      await fixture.updateBranch.call(
        actorUserId: actorId,
        branchId: branch.id,
        name: 'Cabang Berganti',
        isActive: true,
      );

      final after = await fixture.database
          .customSelect('SELECT id, name FROM stock_locations;')
          .getSingle();
      // The id never moves: every balance and movement keeps pointing at it.
      expect(after.read<String>('id'), locationId);
      expect(after.read<String>('name'), contains('Cabang Berganti'));
    });

    test('ruangan baru membawa tepat satu lokasi stok ruangan', () async {
      final seeded = await seed();
      final room = await fixture.createRoom.call(
        actorUserId: actorId,
        branchId: seeded.branchId,
        code: 'R1',
        name: 'Ruang Dental 1',
      );

      expect(await fixture.repository.roomLocationCount(room.id), 1);
      final location = await fixture.database
          .customSelect(
            "SELECT type, branch_id, room_id FROM stock_locations "
            "WHERE type = 'room';",
          )
          .getSingle();
      expect(location.read<String>('branch_id'), seeded.branchId);
      expect(location.read<String>('room_id'), room.id);
    });

    test('menonaktifkan cabang tidak menghapus lokasinya', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Cabang Satu',
      );
      await fixture.setBranchActive.call(
        actorUserId: actorId,
        branchId: branch.id,
        isActive: false,
      );

      expect(await fixture.countOf('stock_locations'), 1);
      expect(
        await fixture.database
            .customSelect('SELECT deleted_at FROM stock_locations;')
            .getSingle()
            .then((row) => row.read<String?>('deleted_at')),
        isNull,
      );
    });

    test('ruangan baru pada cabang nonaktif ditolak', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Cabang Satu',
      );
      await fixture.setBranchActive.call(
        actorUserId: actorId,
        branchId: branch.id,
        isActive: false,
      );

      await expectLater(
        fixture.createRoom.call(
          actorUserId: actorId,
          branchId: branch.id,
          code: 'R1',
          name: 'Ruang',
        ),
        throwsA(isA<MasterDependencyActiveFailure>()),
      );
      expect(await fixture.countOf('rooms'), 0);
      // Rolled back whole: no orphan room location either.
      expect(await fixture.countOf('stock_locations'), 1);
    });
  });

  group('§20 kunci alami tidak dapat diubah', () {
    test('kode cabang ganda ditolak', () async {
      await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      await expectLater(
        fixture.createBranch.call(
          actorUserId: actorId,
          code: 'cab-01',
          name: 'Dua',
        ),
        throwsA(isA<MasterNaturalKeyConflictFailure>()),
      );
      expect(await fixture.countOf('branches'), 1);
    });

    test('email ganda ditolak, email disimpan huruf kecil', () async {
      await fixture.createUser.call(
        actorUserId: actorId,
        fullName: 'Budi',
        email: 'Budi@Klinik.ID',
        role: UserRole.warehouse,
      );
      final stored = await fixture.repository.usersByEmail('budi@klinik.id');
      expect(stored.single.email, 'budi@klinik.id');

      await expectLater(
        fixture.createUser.call(
          actorUserId: actorId,
          fullName: 'Budi Lagi',
          email: 'budi@klinik.id',
          role: UserRole.warehouse,
        ),
        throwsA(isA<MasterNaturalKeyConflictFailure>()),
      );
    });

    test('nama kategori tidak dapat diganti lewat update', () async {
      final category = await fixture.createCategory.call(
        actorUserId: actorId,
        name: 'Obat',
      );
      await expectLater(
        fixture.updateCategory.call(
          actorUserId: actorId,
          categoryId: category.id,
          name: 'Obat Baru',
        ),
        throwsA(isA<MasterNaturalKeyImmutableFailure>()),
      );
      expect(
        (await fixture.repository.categoryById(category.id))!.name,
        'Obat',
      );
    });

    test('SKU ganda ditolak', () async {
      final seeded = await seed();
      await expectLater(
        fixture.createItem.call(
          actorUserId: actorId,
          sku: 'den-0001',
          name: 'Lain',
          categoryId: seeded.categoryId,
          unit: 'pcs',
        ),
        throwsA(isA<MasterNaturalKeyConflictFailure>()),
      );
    });

    test('kode ruangan sama di cabang berbeda diperbolehkan', () async {
      final first = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      final second = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-02',
        name: 'Dua',
      );

      await fixture.createRoom.call(
        actorUserId: actorId,
        branchId: first.id,
        code: 'R1',
        name: 'Ruang A',
      );
      await fixture.createRoom.call(
        actorUserId: actorId,
        branchId: second.id,
        code: 'R1',
        name: 'Ruang B',
      );

      expect(await fixture.countOf('rooms'), 2);
    });

    test('kode ruangan ganda dalam satu cabang ditolak', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      await fixture.createRoom.call(
        actorUserId: actorId,
        branchId: branch.id,
        code: 'R1',
        name: 'Ruang A',
      );
      await expectLater(
        fixture.createRoom.call(
          actorUserId: actorId,
          branchId: branch.id,
          code: 'r1',
          name: 'Ruang B',
        ),
        throwsA(isA<MasterNaturalKeyConflictFailure>()),
      );
      expect(await fixture.countOf('rooms'), 1);
    });
  });

  group('G-M5 kolom terlindungi hanya setelah dipakai', () {
    test(
      'satuan, kategori dan has_expiry bebas diubah selama belum dipakai',
      () async {
        final seeded = await seed();
        final other = await fixture.createCategory.call(
          actorUserId: actorId,
          name: 'APD',
        );

        final updated = await fixture.updateItem.call(
          actorUserId: actorId,
          itemId: seeded.itemId,
          name: 'Anestesi Baru',
          categoryId: other.id,
          unit: 'botol',
          minStockRoom: 5,
          minStockBranch: 20,
          hasExpiry: false,
          expiryAlertDays: 14,
          isActive: true,
        );

        expect(updated.unit, 'botol');
        expect(updated.categoryId, other.id);
        expect(updated.hasExpiry, isFalse);
      },
    );

    test('setelah dipakai ledger, satuan ditolak', () async {
      final seeded = await seed();
      await fixture.markItemUsed(itemId: seeded.itemId, actorUserId: actorId);

      await expectLater(
        fixture.updateItem.call(
          actorUserId: actorId,
          itemId: seeded.itemId,
          name: 'Anestesi',
          categoryId: seeded.categoryId,
          unit: 'botol',
          minStockRoom: 2,
          minStockBranch: 10,
          hasExpiry: true,
          expiryAlertDays: 30,
          isActive: true,
        ),
        throwsA(isA<MasterHistoricalFieldImmutableFailure>()),
      );
      expect((await fixture.repository.itemById(seeded.itemId))!.unit, 'ampul');
    });

    test('setelah dipakai ledger, kategori ditolak', () async {
      final seeded = await seed();
      final other = await fixture.createCategory.call(
        actorUserId: actorId,
        name: 'APD',
      );
      await fixture.markItemUsed(itemId: seeded.itemId, actorUserId: actorId);

      await expectLater(
        fixture.updateItem.call(
          actorUserId: actorId,
          itemId: seeded.itemId,
          name: 'Anestesi',
          categoryId: other.id,
          unit: 'ampul',
          minStockRoom: 2,
          minStockBranch: 10,
          hasExpiry: true,
          expiryAlertDays: 30,
          isActive: true,
        ),
        throwsA(isA<MasterHistoricalFieldImmutableFailure>()),
      );
    });

    test('setelah dipakai ledger, has_expiry ditolak', () async {
      final seeded = await seed();
      await fixture.markItemUsed(itemId: seeded.itemId, actorUserId: actorId);

      await expectLater(
        fixture.updateItem.call(
          actorUserId: actorId,
          itemId: seeded.itemId,
          name: 'Anestesi',
          categoryId: seeded.categoryId,
          unit: 'ampul',
          minStockRoom: 2,
          minStockBranch: 10,
          hasExpiry: false,
          expiryAlertDays: 30,
          isActive: true,
        ),
        throwsA(isA<MasterHistoricalFieldImmutableFailure>()),
      );
    });

    test('kolom aman tetap dapat diubah setelah dipakai', () async {
      final seeded = await seed();
      await fixture.markItemUsed(itemId: seeded.itemId, actorUserId: actorId);

      final updated = await fixture.updateItem.call(
        actorUserId: actorId,
        itemId: seeded.itemId,
        name: 'Anestesi Lokal',
        categoryId: seeded.categoryId,
        unit: 'ampul',
        minStockRoom: 9,
        minStockBranch: 99,
        hasExpiry: true,
        expiryAlertDays: 45,
        isActive: false,
      );

      expect(updated.name, 'Anestesi Lokal');
      expect(updated.minStockRoom, 9);
      expect(updated.minStockBranch, 99);
      expect(updated.expiryAlertDays, 45);
      expect(updated.isActive, isFalse);
      // The ledger row is untouched by any of it.
      expect(await fixture.countOf('stock_movements'), 1);
    });

    test('has_expiry tidak dapat dimatikan selama barang punya batch', () async {
      final seeded = await seed();
      await fixture.createBatch.call(
        actorUserId: actorId,
        itemId: seeded.itemId,
        batchNo: 'LOT-1',
        expiryDate: DateOnly.of(2026, 12, 31),
      );

      await expectLater(
        fixture.updateItem.call(
          actorUserId: actorId,
          itemId: seeded.itemId,
          name: 'Anestesi',
          categoryId: seeded.categoryId,
          unit: 'ampul',
          minStockRoom: 2,
          minStockBranch: 10,
          // Refused even though the item has never moved: `item_batches` for a
          // non-expiry item are rows nothing may reference (§20.2).
          hasExpiry: false,
          expiryAlertDays: 30,
          isActive: true,
        ),
        throwsA(isA<MasterHistoricalFieldImmutableFailure>()),
      );
    });

    test('tanggal kedaluwarsa batch terkunci setelah dipakai', () async {
      final seeded = await seed();
      final batch = await fixture.createBatch.call(
        actorUserId: actorId,
        itemId: seeded.itemId,
        batchNo: 'LOT-1',
        expiryDate: DateOnly.of(2026, 12, 31),
      );

      // Correctable while unused.
      final corrected = await fixture.updateBatch.call(
        actorUserId: actorId,
        batchId: batch.id,
        expiryDate: DateOnly.of(2027, 1, 31),
      );
      expect(corrected.expiryDate, DateOnly.of(2027, 1, 31));

      await fixture.markItemUsed(
        itemId: seeded.itemId,
        batchId: batch.id,
        actorUserId: actorId,
      );

      await expectLater(
        fixture.updateBatch.call(
          actorUserId: actorId,
          batchId: batch.id,
          expiryDate: DateOnly.of(2028, 1, 31),
        ),
        throwsA(isA<MasterHistoricalFieldImmutableFailure>()),
      );
      expect(
        (await fixture.repository.batchById(batch.id))!.expiryDate,
        DateOnly.of(2027, 1, 31),
      );
    });
  });

  group('§21 pengaman peran pengguna', () {
    test('perawat wajib punya cabang', () async {
      await expectLater(
        fixture.createUser.call(
          actorUserId: actorId,
          fullName: 'Perawat',
          email: 'perawat@aish.id',
          role: UserRole.perawat,
        ),
        throwsA(isA<MasterRoleBranchMismatchFailure>()),
      );
    });

    test('warehouse tidak boleh punya cabang', () async {
      final seeded = await seed();
      await expectLater(
        fixture.createUser.call(
          actorUserId: actorId,
          fullName: 'Gudang',
          email: 'gudang@aish.id',
          role: UserRole.warehouse,
          branchId: seeded.branchId,
        ),
        throwsA(isA<MasterRoleBranchMismatchFailure>()),
      );
    });

    test('Super Admin terakhir tidak dapat dinonaktifkan', () async {
      await expectLater(
        fixture.setUserActive.call(
          actorUserId: actorId,
          userId: actorId,
          isActive: false,
        ),
        // Self-deactivation fires first, and it is the more useful sentence.
        throwsA(isA<MasterSelfDeactivationFailure>()),
      );

      // With a second Super Admin present, the *other* one can be deactivated
      // and then the last one still cannot.
      final second = await fixture.seedUser(
        id: 'admin-2',
        email: 'admin2@aish.id',
        role: UserRole.superAdmin,
      );
      await fixture.setUserActive.call(
        actorUserId: actorId,
        userId: second,
        isActive: false,
      );
      expect(await fixture.columnOf('users', second, 'is_active'), '0');
    });

    test('Super Admin tidak dapat menonaktifkan dirinya sendiri', () async {
      await fixture.seedUser(
        id: 'admin-2',
        email: 'admin2@aish.id',
        role: UserRole.superAdmin,
      );

      await expectLater(
        fixture.setUserActive.call(
          actorUserId: actorId,
          userId: actorId,
          isActive: false,
        ),
        throwsA(isA<MasterSelfDeactivationFailure>()),
      );
      expect(await fixture.columnOf('users', actorId, 'is_active'), '1');
    });

    test('Super Admin tidak dapat melepas perannya sendiri', () async {
      await fixture.seedUser(
        id: 'admin-2',
        email: 'admin2@aish.id',
        role: UserRole.superAdmin,
      );

      await expectLater(
        fixture.updateUser.call(
          actorUserId: actorId,
          userId: actorId,
          fullName: 'Super Admin',
          role: UserRole.warehouse,
          isActive: true,
        ),
        throwsA(isA<MasterSelfDeactivationFailure>()),
      );
      expect(await fixture.columnOf('users', actorId, 'role'), 'super_admin');
    });

    test(
      'menurunkan Super Admin terakhir yang bukan diri sendiri ditolak',
      () async {
        // The actor is a Super Admin; a second one exists and the actor demotes it
        // — allowed. Then the actor is deactivated by raw SQL, leaving the second
        // as the only administrator, and demoting *it* is refused.
        final second = await fixture.seedUser(
          id: 'admin-2',
          email: 'admin2@aish.id',
          role: UserRole.superAdmin,
        );
        await fixture.deactivateRaw('users', actorId);
        await fixture.database.customStatement(
          "UPDATE users SET is_active = 1 WHERE id = ?;",
          [actorId],
        );

        // Both active: demoting one is fine.
        await fixture.updateUser.call(
          actorUserId: actorId,
          userId: second,
          fullName: 'Admin Dua',
          role: UserRole.warehouse,
          isActive: true,
        );
        expect(await fixture.columnOf('users', second, 'role'), 'warehouse');
      },
    );

    test('pengguna baru tidak boleh masuk cabang nonaktif', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      await fixture.setBranchActive.call(
        actorUserId: actorId,
        branchId: branch.id,
        isActive: false,
      );

      await expectLater(
        fixture.createUser.call(
          actorUserId: actorId,
          fullName: 'Perawat',
          email: 'perawat@aish.id',
          role: UserRole.perawat,
          branchId: branch.id,
        ),
        throwsA(isA<MasterDependencyActiveFailure>()),
      );
    });
  });

  group('§3.6 siklus hidup kategori dan batch', () {
    test('kategori diarsipkan lalu dipulihkan, bukan dihapus', () async {
      final category = await fixture.createCategory.call(
        actorUserId: actorId,
        name: 'Obat',
      );

      await fixture.archiveCategory.call(
        actorUserId: actorId,
        categoryId: category.id,
      );
      expect(
        await fixture.columnOf('item_categories', category.id, 'deleted_at'),
        isNotNull,
      );
      // Archived, not deleted: the row is still there.
      expect(await fixture.countOf('item_categories'), 1);

      await fixture.restoreCategory.call(
        actorUserId: actorId,
        categoryId: category.id,
      );
      expect(
        await fixture.columnOf('item_categories', category.id, 'deleted_at'),
        isNull,
      );
      expect(
        await fixture.columnOf('item_categories', category.id, 'sync_status'),
        SyncStatus.pending.dbValue,
      );
    });

    test('kategori yang masih dipakai barang tidak dapat diarsipkan', () async {
      final seeded = await seed();
      await expectLater(
        fixture.archiveCategory.call(
          actorUserId: actorId,
          categoryId: seeded.categoryId,
        ),
        throwsA(isA<MasterDependencyActiveFailure>()),
      );
    });

    test('batch diarsipkan lalu dipulihkan', () async {
      final seeded = await seed();
      final batch = await fixture.createBatch.call(
        actorUserId: actorId,
        itemId: seeded.itemId,
        batchNo: 'LOT-1',
        expiryDate: DateOnly.of(2026, 12, 31),
      );

      await fixture.archiveBatch.call(actorUserId: actorId, batchId: batch.id);
      expect(
        await fixture.columnOf('item_batches', batch.id, 'deleted_at'),
        isNotNull,
      );

      await fixture.restoreBatch.call(actorUserId: actorId, batchId: batch.id);
      expect(
        await fixture.columnOf('item_batches', batch.id, 'deleted_at'),
        isNull,
      );
    });

    test('batch kedaluwarsa boleh dibuat — ini riwayat master', () async {
      final seeded = await seed();
      // Well in the past relative to the injected clock. A lot on the shelf has
      // to be recordable, or a Pemusnahan has nothing to destroy (G-E7).
      final batch = await fixture.createBatch.call(
        actorUserId: actorId,
        itemId: seeded.itemId,
        batchNo: 'LOT-LAMA',
        expiryDate: DateOnly.of(2020, 1, 1),
      );
      expect(batch.expiryDate, DateOnly.of(2020, 1, 1));
      // And it creates no stock (§30).
      expect(await fixture.countOf('stock_balances'), 0);
      expect(await fixture.countOf('stock_movements'), 0);
    });

    test('batch pada barang tanpa kedaluwarsa ditolak', () async {
      final seeded = await seed();
      final plain = await fixture.createItem.call(
        actorUserId: actorId,
        sku: 'NOEXP-1',
        name: 'Tanpa ED',
        categoryId: seeded.categoryId,
        unit: 'pcs',
      );

      await expectLater(
        fixture.createBatch.call(
          actorUserId: actorId,
          itemId: plain.id,
          batchNo: 'LOT-1',
          expiryDate: DateOnly.of(2026, 12, 31),
        ),
        throwsA(isA<MasterDependencyActiveFailure>()),
      );
    });
  });

  group('G-Y setiap tulisan berstatus pending', () {
    test('insert dan update master berstatus pending', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      expect(
        await fixture.columnOf('branches', branch.id, 'sync_status'),
        SyncStatus.pending.dbValue,
      );

      // Mark it synced by hand, then update — it must go back to pending.
      await fixture.database.customStatement(
        "UPDATE branches SET sync_status = 'synced' WHERE id = ?;",
        [branch.id],
      );
      await fixture.updateBranch.call(
        actorUserId: actorId,
        branchId: branch.id,
        name: 'Satu Baru',
        isActive: true,
      );
      expect(
        await fixture.columnOf('branches', branch.id, 'sync_status'),
        SyncStatus.pending.dbValue,
      );

      await fixture.database.customStatement(
        "UPDATE branches SET sync_status = 'synced' WHERE id = ?;",
        [branch.id],
      );
      await fixture.setBranchActive.call(
        actorUserId: actorId,
        branchId: branch.id,
        isActive: false,
      );
      expect(
        await fixture.columnOf('branches', branch.id, 'sync_status'),
        SyncStatus.pending.dbValue,
      );
    });

    test('timestamp disimpan dalam UTC', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      final createdAt = await fixture.columnOf(
        'branches',
        branch.id,
        'created_at',
      );
      // Written by the injected clock, in UTC, with no local conversion.
      expect(createdAt, clock().toIso8601String());
    });
  });

  group('§40 daftar dan pencarian', () {
    test('daftar menyembunyikan baris nonaktif kecuali diminta', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-02',
        name: 'Dua',
      );
      await fixture.setBranchActive.call(
        actorUserId: actorId,
        branchId: branch.id,
        isActive: false,
      );

      final active = await fixture.repository.listBranches(
        const MasterListFilter(),
      );
      expect(active.map((view) => view.branch.code), ['CAB-02']);

      final all = await fixture.repository.listBranches(
        const MasterListFilter(includeInactive: true),
      );
      expect(all.map((view) => view.branch.code), ['CAB-01', 'CAB-02']);
    });

    test('pencarian cocok pada kode dan nama', () async {
      await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Kelapa Gading',
      );
      await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-02',
        name: 'Bintaro',
      );

      final byName = await fixture.repository.listBranches(
        const MasterListFilter(query: 'kelapa'),
      );
      expect(byName, hasLength(1));
      final byCode = await fixture.repository.listBranches(
        const MasterListFilter(query: 'cab-02'),
      );
      expect(byCode.single.branch.name, 'Bintaro');
    });

    test('badge riwayat menandai barang yang sudah dipakai', () async {
      final seeded = await seed();
      var views = await fixture.repository.listItems(const MasterListFilter());
      expect(views.single.usage.isUsed, isFalse);

      await fixture.markItemUsed(itemId: seeded.itemId, actorUserId: actorId);
      views = await fixture.repository.listItems(const MasterListFilter());
      expect(views.single.usage.isUsed, isTrue);
      expect(views.single.usage.describe(), contains('pergerakan stok'));
    });

    test('dashboard menghitung aktif dan nonaktif per entitas', () async {
      final branch = await fixture.createBranch.call(
        actorUserId: actorId,
        code: 'CAB-01',
        name: 'Satu',
      );
      await fixture.setBranchActive.call(
        actorUserId: actorId,
        branchId: branch.id,
        isActive: false,
      );

      final dashboard = await fixture.repository.dashboard();
      expect(dashboard.summaries, hasLength(6));
      final branches = dashboard.forEntity(MasterEntityType.branches)!;
      expect(branches.activeCount, 0);
      expect(branches.inactiveCount, 1);
      expect(branches.lastUpdatedAtUtc, isNotNull);
    });
  });

  group('§52 baris yang hilang ditolak, bukan diabaikan', () {
    test('memperbarui entitas yang tidak ada ditolak', () async {
      await expectLater(
        fixture.updateBranch.call(
          actorUserId: actorId,
          branchId: 'tidak-ada',
          name: 'X',
          isActive: true,
        ),
        throwsA(isA<MasterEntityNotFoundFailure>()),
      );
    });

    test('mengarsipkan kategori dua kali ditolak', () async {
      final category = await fixture.createCategory.call(
        actorUserId: actorId,
        name: 'Obat',
      );
      await fixture.archiveCategory.call(
        actorUserId: actorId,
        categoryId: category.id,
      );
      await expectLater(
        fixture.archiveCategory.call(
          actorUserId: actorId,
          categoryId: category.id,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
}
