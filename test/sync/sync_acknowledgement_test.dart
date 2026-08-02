import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/sync_acknowledgement_applier.dart';
import 'package:aish_warehouse/core/sync/sync_contracts.dart';
import 'package:aish_warehouse/core/sync/sync_outbox_writer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSyncOutboxWriter writer;
  late DriftSyncAcknowledgementApplier acknowledgement;
  final now = DateTime.utc(2026, 8, 2);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    writer = DriftSyncOutboxWriter(database, clock: () => now);
    acknowledgement = DriftSyncAcknowledgementApplier(database);
    await _seedPurchaseRequest(database, now);
  });

  tearDown(() => database.close());

  Future<SyncOutboxRow> enqueue() async {
    await writer.enqueueCurrentAggregate(
      operation: SyncOperationType.submitPurchaseRequest,
      aggregateType: SyncAggregateType.purchaseRequest,
      aggregateId: 'pr-1',
      actorUserId: 'user-1',
      occurredAtUtc: now,
    );
    return (await database.select(database.syncOutbox).get()).single;
  }

  test(
    'accepted ack replaces TMP and records server metadata atomically',
    () async {
      final row = await enqueue();
      await acknowledgement.accept(
        outbox: row,
        pushedPayloadHash: row.payloadHash,
        result: SyncAcceptedResult(
          requestId: SyncRequestId(row.requestId),
          serverVersion: 4,
          serverUpdatedAtUtc: now,
          finalDocumentNumber: 'PR-C1-20260802-0001',
        ),
      );

      final request =
          (await database.select(database.purchaseRequests).get()).single;
      expect(request.docNumber, 'PR-C1-20260802-0001');
      expect(request.syncStatus.dbValue, 'synced');
      expect(
        (await database.select(database.purchaseRequestLines).get())
            .single
            .syncStatus
            .dbValue,
        'synced',
      );
      final state =
          (await database.select(database.syncEntityStates).get()).single;
      expect(state.serverVersion, 4);
      expect(state.lastSyncedRequestId, row.requestId);
      expect(await database.select(database.syncOutbox).get(), isEmpty);
    },
  );

  test('replay cannot replace an already-final server number', () async {
    await database.customStatement(
      "UPDATE purchase_requests SET doc_number='PR-C1-20260802-0001' WHERE id='pr-1';",
    );
    final row = await enqueue();
    await acknowledgement.accept(
      outbox: row,
      pushedPayloadHash: row.payloadHash,
      result: SyncReplayResult(
        requestId: SyncRequestId(row.requestId),
        serverVersion: 4,
        serverUpdatedAtUtc: now,
        finalDocumentNumber: 'PR-C1-20260802-9999',
      ),
    );

    expect(
      (await database.select(database.purchaseRequests).get()).single.docNumber,
      'PR-C1-20260802-0001',
    );
  });

  test(
    'new local mutation remains pending and receives successor request',
    () async {
      final row = await enqueue();
      await database.customStatement(
        "UPDATE purchase_requests SET note='changed while in flight' WHERE id='pr-1';",
      );

      await acknowledgement.accept(
        outbox: row,
        pushedPayloadHash: row.payloadHash,
        result: SyncAcceptedResult(
          requestId: SyncRequestId(row.requestId),
          serverVersion: 7,
          serverUpdatedAtUtc: now,
          finalDocumentNumber: 'PR-C1-20260802-0001',
        ),
      );

      final request =
          (await database.select(database.purchaseRequests).get()).single;
      expect(request.docNumber, 'PR-C1-20260802-0001');
      expect(request.syncStatus.dbValue, 'pending');
      final successor =
          (await database.select(database.syncOutbox).get()).single;
      expect(successor.requestId, isNot(row.requestId));
      expect(successor.baseServerVersion, 7);
    },
  );

  test(
    'conflict marks aggregate children and appends safe conflict audit',
    () async {
      final row = await enqueue();
      await acknowledgement.conflict(
        outbox: row,
        result: SyncConflictResult(
          requestId: SyncRequestId(row.requestId),
          code: 'sync_stale_version',
          safeMessage: 'Versi server lebih baru.',
          baseVersion: 1,
          serverVersion: 2,
        ),
      );

      expect(
        (await database.select(database.purchaseRequests).get())
            .single
            .syncStatus
            .dbValue,
        'conflict',
      );
      expect(
        (await database.select(database.purchaseRequestLines).get())
            .single
            .syncStatus
            .dbValue,
        'conflict',
      );
      final conflict =
          (await database.select(database.syncConflictLogs).get()).single;
      expect(conflict.conflictCode, 'sync_stale_version');
      expect(conflict.safeDetailJson, contains('Versi server lebih baru.'));
    },
  );
}

Future<void> _seedPurchaseRequest(AppDatabase database, DateTime now) async {
  final timestamp = now.toIso8601String();
  await database.customStatement(
    "INSERT INTO branches (id,created_at,updated_at,sync_status,code,name,is_active) "
    "VALUES ('branch-1',?,?, 'synced','C1','Cabang',1);",
    [timestamp, timestamp],
  );
  await database.customStatement(
    "INSERT INTO users (id,created_at,updated_at,sync_status,full_name,email,role,branch_id,is_active) "
    "VALUES ('user-1',?,?, 'synced','Kepala','head@example.test','kepala_cabang','branch-1',1);",
    [timestamp, timestamp],
  );
  await database.customStatement(
    "INSERT INTO item_categories (id,created_at,updated_at,sync_status,name) "
    "VALUES ('category-1',?,?, 'synced','Kategori');",
    [timestamp, timestamp],
  );
  await database.customStatement(
    "INSERT INTO items (id,created_at,updated_at,sync_status,sku,name,category_id,unit,min_stock_room,min_stock_branch,has_expiry,expiry_alert_days,is_active) "
    "VALUES ('item-1',?,?, 'synced','SKU','Barang','category-1','pcs',0,0,0,30,1);",
    [timestamp, timestamp],
  );
  await database.customStatement(
    "INSERT INTO purchase_requests (id,created_at,updated_at,sync_status,doc_number,branch_id,requested_by,status,submitted_at) "
    "VALUES ('pr-1',?,?, 'pending','TMP-PR-pr-1','branch-1','user-1','submitted',?);",
    [timestamp, timestamp, timestamp],
  );
  await database.customStatement(
    "INSERT INTO purchase_request_lines (id,created_at,updated_at,sync_status,pr_id,item_id,suggested_qty,requested_qty) "
    "VALUES ('line-1',?,?, 'pending','pr-1','item-1',1000,1000);",
    [timestamp, timestamp],
  );
}
