import 'dart:io';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/rebuild_pending_outbox_use_case.dart';
import 'package:aish_warehouse/core/sync/drift_sync_operation_planner.dart';
import 'package:aish_warehouse/core/sync/push_sync_worker.dart';
import 'package:aish_warehouse/core/sync/sync_contracts.dart';
import 'package:aish_warehouse/core/sync/sync_outbox_writer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSyncOutboxWriter writer;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    writer = DriftSyncOutboxWriter(database);
  });

  tearDown(() => database.close());

  test('enqueue is coalesced for the same queued aggregate', () async {
    final first = await writer.enqueue(
      operation: SyncOperationType.upsertMaster,
      aggregateType: SyncAggregateType.item,
      aggregateId: 'item-1',
      actorUserId: 'actor-1',
      occurredAtUtc: DateTime.utc(2026, 8, 2),
      payload: JsonSyncPayload({'name': 'A'}),
    );
    final second = await writer.enqueue(
      operation: SyncOperationType.upsertMaster,
      aggregateType: SyncAggregateType.item,
      aggregateId: 'item-1',
      actorUserId: 'actor-1',
      occurredAtUtc: DateTime.utc(2026, 8, 2),
      payload: JsonSyncPayload({'name': 'B'}),
    );
    expect(second, first);
    expect(await database.select(database.syncOutbox).get(), hasLength(1));
  });

  test('business write and outbox failure roll back together', () async {
    await expectLater(
      database.transaction(() async {
        await database.customStatement(
          "INSERT INTO branches (id, created_at, updated_at, sync_status, code, name, is_active) "
          "VALUES ('branch-1', ?, ?, 'pending', 'C1', 'Cabang', 1);",
          ['2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'],
        );
        await database.customStatement(
          "INSERT INTO sync_outbox (id,request_id,device_id,operation_type,aggregate_type,aggregate_id,actor_user_id,payload_version,payload_hash,status,attempt_count,next_attempt_epoch_ms,created_at,updated_at) "
          "VALUES ('bad','bad','missing','x','x','x','x',1,'not-a-hash','queued',0,0,?,?);",
          ['2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z'],
        );
      }),
      throwsA(anything),
    );
    final rows = await database.customSelect('SELECT id FROM branches').get();
    expect(rows, isEmpty);
  });

  test('expired processing lease returns to queued', () async {
    await writer.enqueue(
      operation: SyncOperationType.upsertMaster,
      aggregateType: SyncAggregateType.branch,
      aggregateId: 'branch-1',
      actorUserId: 'actor-1',
      occurredAtUtc: DateTime.utc(2026),
      payload: JsonSyncPayload({'code': 'C1'}),
    );
    final row = (await database.select(database.syncOutbox).get()).single;
    expect(
      await database.syncDao.acquireLease(
        requestId: row.requestId,
        nowEpochMs: 10,
      ),
      isTrue,
    );
    expect(
      await database.syncDao.recoverExpiredLeases(
        expiredBeforeEpochMs: 11,
        nowUtc: DateTime.utc(2026),
      ),
      1,
    );
    expect(
      (await database.select(database.syncOutbox).get()).single.status,
      'queued',
    );
  });

  test('legacy master stays blocked without adopting Super Admin', () async {
    const stamp = '2026-08-02T00:00:00.000Z';
    await database.customStatement(
      "INSERT INTO item_categories (id,created_at,updated_at,sync_status,name) VALUES "
      "('pending-category',?,?, 'pending','Pending'),"
      "('synced-category',?,?, 'synced','Synced');",
      [stamp, stamp, stamp, stamp],
    );
    final rebuild = RebuildPendingOutboxUseCase(database, writer);

    expect(await rebuild.call(), 1);
    expect(await rebuild.call(), 0);

    final rows = await database.select(database.syncOutbox).get();
    expect(rows, hasLength(1));
    expect(rows.single.aggregateId, 'pending-category');
    expect(rows.single.actorUserId, isNull);
    expect(rows.single.status, 'blocked');
    expect(rows.single.lastErrorCode, syncOriginalActorUnknownCode);

    final gateway = _AcceptedGateway(sessionActor: 'super-admin');
    final worker = PushSyncWorker(
      database: database,
      gateway: gateway,
      planner: DriftSyncOperationPlanner(database),
      acknowledgement: _DeletingAcknowledgement(database),
    );
    await worker.run(actorUserId: 'super-admin');
    await worker.run(actorUserId: 'super-admin');
    final stillBlocked =
        (await database.select(database.syncOutbox).get()).single;
    expect(gateway.calls, 0);
    expect(stillBlocked.status, 'blocked');
    expect(stillBlocked.attemptCount, 0);
    expect(await database.select(database.syncAttemptLogs).get(), isEmpty);
  });

  test('legacy actor schema audit covers every final/status/audit effect', () {
    expect(
      {
        for (final source in RebuildPendingOutboxUseCase.auditedActorSources)
          source.operation: source.actorColumn,
      },
      {
        SyncOperationType.submitOpname: 'counted_by',
        SyncOperationType.reviewOpname: 'reviewed_by',
        SyncOperationType.submitPurchaseRequest: 'requested_by',
        SyncOperationType.processPurchaseRequest: 'processed_by',
        SyncOperationType.rejectPurchaseRequest: 'rejected_by',
        SyncOperationType.cancelPurchaseRequest: 'cancelled_by',
        SyncOperationType.shipDeliveryOrder: 'shipped_by',
        SyncOperationType.postGoodReceipt: 'received_by',
        SyncOperationType.postDistribution: 'distributed_by',
        SyncOperationType.postDisposal: 'posted_by',
        SyncOperationType.postConsumption: 'posted_by',
        SyncOperationType.shipGoodsReturn: 'shipped_by',
        SyncOperationType.receiveGoodsReturn: 'received_by',
        SyncOperationType.appendImportAudit: 'imported_by',
        SyncOperationType.appendExportAudit: 'exported_by',
      },
    );
  });

  test(
    'v13 pending actor A waits through actor B and is processed only by A',
    () async {
      final directory = await Directory(
        '.dart_tool/test_tmp',
      ).create(recursive: true);
      final file = File('${directory.path}/legacy_actor_v13_to_v14.sqlite');
      if (file.existsSync()) await file.delete();
      var migratedDatabase = AppDatabase(NativeDatabase(file));
      const stamp = '2026-08-02T00:00:00.000Z';
      await migratedDatabase.customStatement('PRAGMA foreign_keys = OFF;');
      await migratedDatabase.customStatement(
        "INSERT INTO purchase_requests (id,created_at,updated_at,sync_status,doc_number,branch_id,requested_by,status,submitted_at) "
        "VALUES ('legacy-pr',?,?, 'pending','TMP-PR-legacy','branch-a','user-a','submitted',?);",
        [stamp, stamp, stamp],
      );
      for (final table in const [
        'sync_file_uploads',
        'sync_conflict_logs',
        'sync_attempt_logs',
        'sync_entity_states',
        'sync_outbox',
        'sync_devices',
      ]) {
        await migratedDatabase.customStatement('DROP TABLE $table;');
      }
      await migratedDatabase.customStatement('PRAGMA user_version = 13;');
      await migratedDatabase.close();

      // User B is the first login after the real v13 -> v14 open migration.
      migratedDatabase = AppDatabase(NativeDatabase(file));
      final migratedWriter = DriftSyncOutboxWriter(migratedDatabase);
      final rebuild = RebuildPendingOutboxUseCase(
        migratedDatabase,
        migratedWriter,
      );

      expect(await rebuild.call(), 1);
      final original =
          (await migratedDatabase.select(migratedDatabase.syncOutbox).get())
              .single;
      expect(original.actorUserId, 'user-a');
      expect(original.status, 'queued');

      final actorBGateway = _AcceptedGateway(sessionActor: 'user-b');
      await PushSyncWorker(
        database: migratedDatabase,
        gateway: actorBGateway,
        planner: DriftSyncOperationPlanner(migratedDatabase),
        acknowledgement: _DeletingAcknowledgement(migratedDatabase),
      ).run(actorUserId: 'user-b');
      final waiting =
          (await migratedDatabase.select(migratedDatabase.syncOutbox).get())
              .single;
      expect(actorBGateway.calls, 0);
      expect(waiting.requestId, original.requestId);
      expect(waiting.actorUserId, 'user-a');
      expect(waiting.attemptCount, 0);

      // Rebuild and account switches never rewrite the immutable actor.
      expect(await rebuild.call(), 0);
      final afterRebuild =
          (await migratedDatabase.select(migratedDatabase.syncOutbox).get())
              .single;
      expect(afterRebuild.requestId, original.requestId);
      expect(afterRebuild.actorUserId, 'user-a');

      final actorAGateway = _AcceptedGateway(sessionActor: 'user-a');
      await PushSyncWorker(
        database: migratedDatabase,
        gateway: actorAGateway,
        planner: DriftSyncOperationPlanner(migratedDatabase),
        acknowledgement: _DeletingAcknowledgement(migratedDatabase),
      ).run(actorUserId: 'user-a');
      expect(actorAGateway.calls, 1);
      expect(actorAGateway.receivedActors, ['user-a']);
      expect(
        await migratedDatabase.select(migratedDatabase.syncOutbox).get(),
        isEmpty,
      );
      await migratedDatabase.close();
      if (file.existsSync()) await file.delete();
    },
  );
}

final class _AcceptedGateway implements PushSyncGateway {
  _AcceptedGateway({required this.sessionActor});

  final String sessionActor;
  int calls = 0;
  final List<String> receivedActors = [];

  @override
  Future<SyncPushResult> push(SyncOperationEnvelope envelope) async {
    calls++;
    receivedActors.add(sessionActor);
    return SyncAcceptedResult(
      requestId: envelope.requestId,
      serverVersion: 1,
      serverUpdatedAtUtc: DateTime.utc(2026, 8, 2),
    );
  }
}

final class _DeletingAcknowledgement implements SyncAcknowledgementApplier {
  const _DeletingAcknowledgement(this.database);
  final AppDatabase database;

  @override
  Future<void> accept({
    required SyncOutboxRow outbox,
    required String pushedPayloadHash,
    required SyncAcceptedResult result,
  }) => database.syncDao.complete(outbox.requestId);

  @override
  Future<void> conflict({
    required SyncOutboxRow outbox,
    required SyncConflictResult result,
  }) => database.syncDao.markConflict(
    requestId: outbox.requestId,
    nowUtc: DateTime.utc(2026, 8, 2),
  );
}
