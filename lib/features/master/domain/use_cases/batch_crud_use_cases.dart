import '../../../../core/errors/failures.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../../../../core/time/date_only.dart';
import '../models/master_admin_models.dart';
import '../models/master_models.dart';
import '../repositories/master_admin_repository.dart';
import '../services/master_historical_integrity_policy.dart';
import '../services/master_import_normalization_policy.dart';
import 'master_admin_guard.dart';

/// Creates a batch for an expiry-tracked item.
///
/// ### An expired date is allowed, and that is not an oversight
///
/// A batch is master *history*. An expired lot sitting on a shelf has to be
/// recordable, or a Pemusnahan has nothing to destroy (G-E7) and a Stok Opname
/// has nothing to count. What refuses an expired batch is the **outbound**
/// movement — a shipment, a distribution, a consumption — which is a different
/// rule in a different module (G-E3/G-E4). Refusing it here would make the
/// application unable to describe the shelf it is standing in front of.
///
/// **No stock is created.** Creating a batch creates a batch: no balance row, no
/// inbound movement, no ledger entry of any kind (§30). Stock arrives through a
/// Good Receipt or a warehouse inbound, both of which are documents somebody
/// raises.
class CreateItemBatchUseCase with MasterAdminGuard {
  CreateItemBatchUseCase({
    required this.repository,
    this.outboxWriter = const NoopSyncOutboxWriter(),
  });

  @override
  final MasterAdminRepository repository;
  final SyncOutboxWriter outboxWriter;

  Future<MasterBatch> call({
    required String actorUserId,
    required String itemId,
    required String batchNo,
    required DateTime expiryDate,
  }) async {
    await requireSuperAdmin(actorUserId);

    final normalizedBatchNo = MasterImportNormalizationPolicy.text(batchNo);
    if (normalizedBatchNo.isEmpty) {
      throw const ValidationFailure('Nomor batch wajib diisi.');
    }
    // A civil date, carried as a UTC midnight and never converted (T-8).
    final civilDate = DateOnly.from(expiryDate);

    return repository.transaction(() async {
      final item = await repository.itemById(itemId);
      if (item == null) {
        throw const MasterEntityNotFoundFailure(
          'Barang tidak ditemukan.',
          entity: MasterEntityType.items,
        );
      }
      if (!item.hasExpiry) {
        throw MasterDependencyActiveFailure(
          'Barang "${item.sku}" tidak dilacak per batch (has_expiry = FALSE), '
          'sehingga tidak dapat memiliki batch.',
          entity: MasterEntityType.itemBatches,
          dependency: 'item.has_expiry',
        );
      }

      final existing = await repository.batchesByItemAndNumber(
        itemId: itemId,
        batchNo: normalizedBatchNo,
      );
      if (existing.isNotEmpty) {
        throw MasterNaturalKeyConflictFailure(
          'Batch "$normalizedBatchNo" sudah ada untuk barang "${item.sku}". '
          'Bila batch tersebut diarsipkan, pulihkan dari daftar batch.',
          entity: MasterEntityType.itemBatches,
          naturalKey: '${item.sku} $normalizedBatchNo',
        );
      }

      final batch = await repository.insertBatch(
        itemId: itemId,
        batchNo: normalizedBatchNo,
        expiryDate: civilDate,
      );
      await outboxWriter.enqueueCurrentAggregate(
        operation: SyncOperationType.upsertMaster,
        aggregateType: SyncAggregateType.batch,
        aggregateId: batch.id,
        actorUserId: actorUserId,
        occurredAtUtc: DateTime.now().toUtc(),
      );
      return batch;
    });
  }
}

/// Corrects a batch's expiry date, while it still may be corrected (§20.3).
///
/// `itemId` and `batchNo` are not parameters — together they are the identity.
/// `expiryDate` is the one column that can change, and it is locked the moment
/// the batch has moved: every quantity in the ledger was posted against a lot
/// that expires on the stored date, and rewriting it silently rewrites which of
/// those postings were of expired goods.
class UpdateItemBatchUseCase with MasterAdminGuard {
  UpdateItemBatchUseCase({
    required this.repository,
    this.outboxWriter = const NoopSyncOutboxWriter(),
  });

  @override
  final MasterAdminRepository repository;
  final SyncOutboxWriter outboxWriter;

  Future<MasterBatch> call({
    required String actorUserId,
    required String batchId,
    required DateTime expiryDate,
  }) async {
    await requireSuperAdmin(actorUserId);

    final civilDate = DateOnly.from(expiryDate);

    return repository.transaction(() async {
      final current = await repository.batchById(batchId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Batch tidak ditemukan.',
          entity: MasterEntityType.itemBatches,
        );
      }

      final usage = await repository.usageForBatch(batchId);
      MasterHistoricalIntegrityPolicy.ensureBatchUpdateAllowed(
        current: current,
        nextItemId: current.itemId,
        nextBatchNo: current.batchNo,
        nextExpiryDate: civilDate,
        usage: usage,
      );

      final rows = await repository.updateBatch(
        id: batchId,
        expiryDate: civilDate,
      );
      requireRowsAffected(
        rows,
        'Batch gagal diperbarui karena datanya baru saja berubah. Muat ulang '
        'lalu coba lagi.',
      );
      await outboxWriter.enqueueCurrentAggregate(
        operation: SyncOperationType.upsertMaster,
        aggregateType: SyncAggregateType.batch,
        aggregateId: batchId,
        actorUserId: actorUserId,
        occurredAtUtc: DateTime.now().toUtc(),
      );
      return (await repository.batchById(batchId))!;
    });
  }
}

/// Archives a batch — `deleted_at = now`, never a delete (§3.6, G-A5).
///
/// Batches carry no `is_active` column, and one was deliberately not added.
/// Archiving hides the batch from the pickers a new document offers while every
/// movement, balance and document line that ever named it still resolves — which
/// is what keeps a Kartu Stok readable after the lot is gone.
class ArchiveItemBatchUseCase with MasterAdminGuard {
  ArchiveItemBatchUseCase({
    required this.repository,
    this.outboxWriter = const NoopSyncOutboxWriter(),
  });

  @override
  final MasterAdminRepository repository;
  final SyncOutboxWriter outboxWriter;

  Future<void> call({
    required String actorUserId,
    required String batchId,
  }) async {
    await requireSuperAdmin(actorUserId);

    await repository.transaction(() async {
      final current = await repository.batchById(batchId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Batch tidak ditemukan.',
          entity: MasterEntityType.itemBatches,
        );
      }
      final rows = await repository.archiveBatch(batchId);
      requireRowsAffected(
        rows,
        'Batch gagal diarsipkan — mungkin sudah diarsipkan sebelumnya. Muat '
        'ulang lalu coba lagi.',
      );
      await outboxWriter.enqueueCurrentAggregate(
        operation: SyncOperationType.upsertMaster,
        aggregateType: SyncAggregateType.batch,
        aggregateId: batchId,
        actorUserId: actorUserId,
        occurredAtUtc: DateTime.now().toUtc(),
      );
    });
  }
}

/// Restores an archived batch — `deleted_at = NULL`.
///
/// Revalidates the item's `has_expiry` on the way back in: an item that stopped
/// tracking expiry while this batch was archived must not silently regain an
/// orphaned lot.
class RestoreItemBatchUseCase with MasterAdminGuard {
  RestoreItemBatchUseCase({
    required this.repository,
    this.outboxWriter = const NoopSyncOutboxWriter(),
  });

  @override
  final MasterAdminRepository repository;
  final SyncOutboxWriter outboxWriter;

  Future<void> call({
    required String actorUserId,
    required String batchId,
  }) async {
    await requireSuperAdmin(actorUserId);

    await repository.transaction(() async {
      final current = await repository.batchById(batchId);
      if (current == null) {
        throw const MasterEntityNotFoundFailure(
          'Batch tidak ditemukan.',
          entity: MasterEntityType.itemBatches,
        );
      }
      final item = await repository.itemById(current.itemId);
      if (item != null && !item.hasExpiry) {
        throw MasterDependencyActiveFailure(
          'Barang "${item.sku}" sudah tidak dilacak per batch, sehingga batch '
          'ini tidak dapat dipulihkan.',
          entity: MasterEntityType.itemBatches,
          dependency: 'item.has_expiry',
        );
      }
      final rows = await repository.restoreBatch(batchId);
      requireRowsAffected(
        rows,
        'Batch gagal dipulihkan — mungkin sudah aktif. Muat ulang lalu coba '
        'lagi.',
      );
      await outboxWriter.enqueueCurrentAggregate(
        operation: SyncOperationType.upsertMaster,
        aggregateType: SyncAggregateType.batch,
        aggregateId: batchId,
        actorUserId: actorUserId,
        occurredAtUtc: DateTime.now().toUtc(),
      );
    });
  }
}

/// The decisions a batch form needs (§41).
abstract final class BatchFormPolicy {
  /// Whether the item picker may be used at all. Only on create — a batch cannot
  /// be moved to another item (§20.3).
  static MasterWriteDecision itemDecision({required bool isCreating}) =>
      isCreating
      ? const MasterWriteDecision.allowed()
      : MasterWriteDecision.refused(
          field: 'item_id',
          reason: MasterHistoricalIntegrityPolicy.naturalKeyImmutableMessage(
            MasterEntityType.itemBatches,
            'item_id',
          ),
        );

  static MasterWriteDecision batchNoDecision({required bool isCreating}) =>
      isCreating
      ? const MasterWriteDecision.allowed()
      : MasterWriteDecision.refused(
          field: 'batch_no',
          reason: MasterHistoricalIntegrityPolicy.naturalKeyImmutableMessage(
            MasterEntityType.itemBatches,
            'batch_no',
          ),
        );

  static MasterWriteDecision expiryDecision({
    required bool isCreating,
    MasterHistoricalUsage usage = const MasterHistoricalUsage.none(),
  }) {
    if (isCreating || !usage.isUsed) {
      return const MasterWriteDecision.allowed();
    }
    return MasterWriteDecision.refused(
      field: 'expiry_date',
      reason: MasterHistoricalIntegrityPolicy.protectedFieldMessage(
        entity: MasterEntityType.itemBatches,
        field: 'expiry_date',
        usage: usage,
      ),
      usage: usage,
    );
  }
}
