import '../../../../core/errors/failures.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_historical_integrity_policy.dart';
import '../services/master_import_normalization_policy.dart';
import 'master_admin_guard.dart';

/// Creates a room **and the one stock location it must have** (§22).
///
/// The room's location carries `branch_id = room.branchId` and
/// `room_id = room.id`, which is what the `stock_locations` CHECK requires of a
/// `room` row and what every Distribusi and Pemakaian resolves against. A room
/// without one cannot hold stock and therefore cannot be counted — so it is
/// created here, in the same transaction, and the count is verified before the
/// transaction is allowed to close.
class CreateRoomUseCase with MasterAdminGuard {
  CreateRoomUseCase({
    required this.repository,
    this.outboxWriter = const NoopSyncOutboxWriter(),
  });

  @override
  final MasterAdminRepository repository;
  final SyncOutboxWriter outboxWriter;

  Future<MasterRoom> call({
    required String actorUserId,
    required String branchId,
    required String code,
    required String name,
    bool isActive = true,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedCode = MasterImportNormalizationPolicy.text(code);
    final normalizedName = MasterImportNormalizationPolicy.text(name);
    if (normalizedCode.isEmpty) {
      throw const ValidationFailure('Kode ruangan wajib diisi.');
    }
    if (normalizedName.isEmpty) {
      throw const ValidationFailure('Nama ruangan wajib diisi.');
    }

    return repository.transaction(() async {
      final branch = await repository.branchById(branchId);
      if (branch == null) {
        throw const MasterEntityNotFoundFailure(
          'Cabang tidak ditemukan.',
          entity: MasterEntityType.branches,
        );
      }
      if (!branch.isActive) {
        throw const MasterDependencyActiveFailure(
          'Cabang ini sedang nonaktif, sehingga ruangan baru tidak dapat '
          'ditambahkan. Aktifkan cabang terlebih dahulu.',
          entity: MasterEntityType.rooms,
          dependency: 'branch',
        );
      }

      // `branch + code`, never `code` alone (§3.1): the schema allows `R1` in
      // every branch, and a global check would refuse a legitimate room.
      final existing = await repository.roomsByBranchAndCode(
        branchId: branchId,
        code: normalizedCode,
      );
      if (existing.isNotEmpty) {
        throw MasterNaturalKeyConflictFailure(
          'Kode ruangan "$normalizedCode" sudah dipakai di cabang '
          '${branch.code}. Gunakan kode lain.',
          entity: MasterEntityType.rooms,
          naturalKey: '${branch.code} $normalizedCode',
        );
      }

      final room = await repository.insertRoom(
        branchId: branchId,
        code: normalizedCode,
        name: normalizedName,
        isActive: isActive,
      );
      await repository.ensureRoomLocation(
        branchId: branchId,
        roomId: room.id,
        roomName: normalizedName,
      );

      final locations = await repository.roomLocationCount(room.id);
      if (locations != 1) {
        throw MasterStockLocationIntegrityFailure(
          'Lokasi stok gagal disiapkan untuk ruangan ini. Perubahan '
          'dibatalkan.',
          entity: MasterEntityType.rooms,
          locationCount: locations,
        );
      }
      await outboxWriter.enqueueCurrentAggregate(
        operation: SyncOperationType.upsertMaster,
        aggregateType: SyncAggregateType.room,
        aggregateId: room.id,
        actorUserId: actorUserId,
        occurredAtUtc: DateTime.now().toUtc(),
      );
      return room;
    });
  }
}

/// Updates a room's safe fields (§20.4).
///
/// Neither `branchId` nor `code` is a parameter. Both are natural-key columns,
/// and `branch_id` in particular is refused *even on an unused room*: the room's
/// stock location is already filed under the branch it was created in, and moving
/// the room would leave the location behind — the exact split-brain §22 exists to
/// prevent.
class UpdateRoomUseCase with MasterAdminGuard {
  UpdateRoomUseCase({
    required this.repository,
    this.outboxWriter = const NoopSyncOutboxWriter(),
  });

  @override
  final MasterAdminRepository repository;
  final SyncOutboxWriter outboxWriter;

  Future<MasterRoom> call({
    required String actorUserId,
    required String roomId,
    required String name,
    required bool isActive,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedName = MasterImportNormalizationPolicy.text(name);
    if (normalizedName.isEmpty) {
      throw const ValidationFailure('Nama ruangan wajib diisi.');
    }

    return repository.transaction(() async {
      final current = await repository.roomById(roomId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Ruangan tidak ditemukan.',
          entity: MasterEntityType.rooms,
        );
      }

      final rows = await repository.updateRoom(
        id: roomId,
        name: normalizedName,
        isActive: isActive,
      );
      requireRowsAffected(
        rows,
        'Ruangan gagal diperbarui karena datanya baru saja berubah. Muat ulang '
        'lalu coba lagi.',
      );

      // The location's name follows the room; its id does not move.
      await repository.renameRoomLocation(
        roomId: roomId,
        roomName: normalizedName,
      );

      await outboxWriter.enqueueCurrentAggregate(
        operation: SyncOperationType.upsertMaster,
        aggregateType: SyncAggregateType.room,
        aggregateId: roomId,
        actorUserId: actorUserId,
        occurredAtUtc: DateTime.now().toUtc(),
      );

      return (await repository.roomById(roomId))!;
    });
  }
}

/// Deactivates or reactivates a room (G-A4).
///
/// The room's stock location is **not** deleted and **not** archived. Balances
/// stay where they are, historic documents still resolve, and a Pemakaian raised
/// last month still renders (§49) — `is_active` only decides what a new document
/// may choose.
class SetRoomActiveUseCase with MasterAdminGuard {
  SetRoomActiveUseCase({
    required this.repository,
    this.outboxWriter = const NoopSyncOutboxWriter(),
  });

  @override
  final MasterAdminRepository repository;
  final SyncOutboxWriter outboxWriter;

  Future<void> call({
    required String actorUserId,
    required String roomId,
    required bool isActive,
  }) async {
    await requireSuperAdmin(actorUserId);

    await repository.transaction(() async {
      final current = await repository.roomById(roomId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Ruangan tidak ditemukan.',
          entity: MasterEntityType.rooms,
        );
      }
      if (isActive) {
        // Reactivating into a deactivated branch would produce a room nothing
        // can reach — the branch filter hides it everywhere it would be offered.
        final branch = await repository.branchById(current.branchId);
        if (branch != null && !branch.isActive) {
          throw const MasterDependencyActiveFailure(
            'Cabang ruangan ini sedang nonaktif. Aktifkan cabangnya terlebih '
            'dahulu.',
            entity: MasterEntityType.rooms,
            dependency: 'branch',
          );
        }
      }
      final rows = await repository.setRoomActive(
        id: roomId,
        isActive: isActive,
      );
      requireRowsAffected(
        rows,
        'Status ruangan gagal diubah. Muat ulang lalu coba lagi.',
      );
      await outboxWriter.enqueueCurrentAggregate(
        operation: SyncOperationType.upsertMaster,
        aggregateType: SyncAggregateType.room,
        aggregateId: roomId,
        actorUserId: actorUserId,
        occurredAtUtc: DateTime.now().toUtc(),
      );
    });
  }
}

/// The decisions a room form needs (§41).
abstract final class RoomFormPolicy {
  static MasterWriteDecision codeDecision({required bool isCreating}) =>
      isCreating
      ? const MasterWriteDecision.allowed()
      : MasterWriteDecision.refused(
          field: 'code',
          reason: MasterHistoricalIntegrityPolicy.naturalKeyImmutableMessage(
            MasterEntityType.rooms,
            'code',
          ),
        );

  static MasterWriteDecision branchDecision({required bool isCreating}) =>
      isCreating
      ? const MasterWriteDecision.allowed()
      : MasterWriteDecision.refused(
          field: 'branch_id',
          reason:
              'Ruangan tidak dapat dipindahkan ke cabang lain. Buat ruangan '
              'baru di cabang tujuan lalu nonaktifkan ruangan ini.',
        );
}
