import 'dart:async';

import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/pull_sync_contracts.dart';
import 'package:aish_warehouse/core/sync/pull_sync_worker.dart';
import 'package:aish_warehouse/core/sync/push_sync_worker.dart';
import 'package:aish_warehouse/core/sync/sync_contracts.dart';
import 'package:aish_warehouse/core/sync/sync_outbox_writer.dart';
import 'package:aish_warehouse/core/sync/sync_cursor_repository.dart';
import 'package:aish_warehouse/core/sync/sync_orchestrator.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pull_test_fixtures.dart';

/// Acceptance 31 and the orchestration rules: push and pull compose without
/// looping, without racing a logout, and without producing a duplicate
/// transaction when both retry at once.
void main() {
  late AppDatabase database;
  late List<String> order;
  final now = DateTime.utc(2026, 8, 3);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    order = [];
    await seedLocalMaster(database);
    await database.customStatement(
      'INSERT INTO sync_devices (id,created_at,last_seen_at,app_install_id) '
      'VALUES (?,?,?,?);',
      ['device-1', fixtureNow, fixtureNow, 'install-1'],
    );
  });

  tearDown(() => database.close());

  PushSyncCoordinator push({Completer<void>? gate}) => PushSyncCoordinator(
    PushSyncWorker(
      database: database,
      gateway: _RecordingPushGateway(order),
      planner: _UnusedPlanner(),
      acknowledgement: _NoopAcknowledgement(),
      clock: () => now,
    ),
    beforePush: (_) async {
      order.add('push');
      if (gate != null) await gate.future;
    },
  );

  PullSyncWorker pull(PullSyncGateway gateway) => PullSyncWorker(
    database: database,
    gateway: gateway,
    cursors: SyncCursorRepository(database),
    clock: () => now,
  );

  SyncOrchestrator orchestrator({
    required PullSyncGateway gateway,
    Completer<void>? pushGate,
    int followUpRounds = 1,
  }) => SyncOrchestrator(
    database: database,
    push: push(gate: pushGate),
    pull: pull(gateway),
    deviceIdProvider: () async => (await database.syncDao.device())?.id,
    maxFollowUpPushRounds: followUpRounds,
  );

  test('a cycle pushes before it pulls', () async {
    final gateway = _OrderedPullGateway(order, [
      batch([
        change(
          seq: 1,
          entityType: 'item',
          entityId: 'item-1',
          payload: serverItem(),
        ),
      ], nextCursor: 1),
    ]);

    await orchestrator(gateway: gateway).run(actorUserId: 'actor-1');

    expect(
      order.take(2).toList(),
      ['push', 'pull'],
      reason:
          'the server must have seen this device before the pull decides truth',
    );
  });

  test('a merge that keeps local work triggers exactly one more push', () async {
    // The device holds a pending edit to a column the server never touched, so
    // reconciliation preserves it and the column is still owed to the server.
    await database.customStatement(
      "UPDATE items SET unit = 'pack' WHERE id = ?;",
      ['item-1'],
    );
    await database.customStatement(
      'INSERT INTO sync_entity_snapshots (id,entity_type,entity_id,'
      'server_version,snapshot_json,applied_at_utc) VALUES (?,?,?,?,?,?);',
      [
        'item:item-1',
        'item',
        'item-1',
        4,
        '{"id":"item-1","unit":"box","name":"Masker Bedah"}',
        fixtureNow,
      ],
    );
    await database.customStatement(
      'INSERT INTO sync_entity_states (id,aggregate_type,aggregate_id,'
      'server_version) VALUES (?,?,?,?);',
      ['state-1', 'item', 'item-1', 4],
    );

    final gateway = _OrderedPullGateway(order, [
      batch([
        change(
          seq: 1,
          entityType: 'item',
          entityId: 'item-1',
          serverVersion: 5,
          payload: serverItem(name: 'Nama Server', serverVersion: 5),
          fieldVersions: {'name': 5, 'unit': 2},
        ),
      ], nextCursor: 1),
    ]);

    await orchestrator(gateway: gateway).run(actorUserId: 'actor-1');

    expect(order.where((step) => step == 'push').length, 2);
    expect(
      order,
      containsAllInOrder(['push', 'pull', 'push', 'pull']),
      reason: 'the preserved column is pushed, then the result is re-read',
    );
  });

  test('the follow-up round is bounded, so the cycle cannot loop', () async {
    // Every pull keeps reporting preserved local work. Without a bound this is
    // exactly the shape of an infinite push/pull loop.
    await database.customStatement(
      "UPDATE items SET unit = 'pack' WHERE id = ?;",
      ['item-1'],
    );
    await database.customStatement(
      'INSERT INTO sync_entity_snapshots (id,entity_type,entity_id,'
      'server_version,snapshot_json,applied_at_utc) VALUES (?,?,?,?,?,?);',
      [
        'item:item-1',
        'item',
        'item-1',
        4,
        '{"id":"item-1","unit":"box"}',
        fixtureNow,
      ],
    );

    final gateway = _AlwaysReconcilingGateway(order);
    await orchestrator(gateway: gateway).run(actorUserId: 'actor-1');

    expect(
      order.where((step) => step == 'push').length,
      2,
      reason: 'one initial push and exactly one follow-up round',
    );
  });

  test('the cycle is single-flight', () async {
    final gate = Completer<void>();
    final gateway = _OrderedPullGateway(order, [
      batch(const [], nextCursor: 0),
    ]);
    final sync = orchestrator(gateway: gateway, pushGate: gate);

    final first = sync.run(actorUserId: 'actor-1');
    final second = sync.run(actorUserId: 'actor-1');
    gate.complete();
    await Future.wait([first, second]);

    expect(
      order.where((step) => step == 'push').length,
      1,
      reason: 'a concurrent trigger joins the cycle already running',
    );
  });

  test('a logout mid-cycle stops before the pull touches the cursor', () async {
    final gate = Completer<void>();
    final gateway = _OrderedPullGateway(order, [
      batch([
        change(
          seq: 1,
          entityType: 'item',
          entityId: 'item-1',
          payload: serverItem(name: 'Tidak Boleh Diterapkan'),
        ),
      ], nextCursor: 1),
    ]);
    final sync = orchestrator(gateway: gateway, pushGate: gate);

    final cycle = sync.run(actorUserId: 'actor-1');
    sync.cancelForActorChange();
    gate.complete();
    await cycle;

    expect(order, isNot(contains('pull')));
    expect(
      (await database.select(database.items).get()).single.name,
      'Masker Bedah',
    );
    expect(
      await SyncCursorRepository(
        database,
      ).cursorFor(actorUserId: 'actor-1', scopeFingerprint: 'scope-a'),
      0,
    );
  });

  test('an actor switch mid-cycle abandons the outgoing actor', () async {
    final gate = Completer<void>();
    final gateway = _OrderedPullGateway(order, [
      batch(const [], nextCursor: 5),
    ]);
    final sync = orchestrator(gateway: gateway, pushGate: gate);

    final cycle = sync.run(actorUserId: 'actor-1');
    // A different actor signs in while the first cycle is still pushing.
    sync.cancelForActorChange();
    gate.complete();
    await cycle;

    expect(sync.lastReport, isNull);
  });

  test('no device row means no cycle at all', () async {
    await database.customStatement('DELETE FROM sync_devices;');
    final gateway = _OrderedPullGateway(order, [batch(const [])]);

    await orchestrator(gateway: gateway).run(actorUserId: 'actor-1');

    expect(
      order,
      isEmpty,
      reason: 'a pull has nothing to authenticate with before a device exists',
    );
  });

  test('a completed cycle reports what it did', () async {
    final gateway = _OrderedPullGateway(order, [
      batch([
        change(
          seq: 1,
          entityType: 'item',
          entityId: 'item-1',
          payload: serverItem(),
        ),
      ], nextCursor: 3),
    ]);
    final sync = orchestrator(gateway: gateway);

    await sync.run(actorUserId: 'actor-1');

    expect(sync.lastReport, isNotNull);
    expect(sync.lastReport!.applied, 1);
    expect(sync.lastReport!.cursor, 3);
    expect(sync.lastReport!.reachedEnd, isTrue);
    expect(sync.lastReport!.succeeded, isTrue);
  });
}

final class _OrderedPullGateway implements PullSyncGateway {
  _OrderedPullGateway(this.order, this.pages);
  final List<String> order;
  final List<RemoteChangeBatch> pages;

  @override
  Future<RemoteChangeBatch> pull({
    required int cursor,
    required int limit,
    required String deviceId,
    List<String>? entityTypes,
  }) async {
    order.add('pull');
    return pages.firstWhere(
      (page) =>
          page.changes.isNotEmpty &&
          page.changes.every((change) => change.changeSeq > cursor),
      orElse: () => batch(const [], nextCursor: cursor),
    );
  }
}

/// Always reports the same reconcilable change, so the follow-up bound is what
/// stops the cycle rather than the data running out.
final class _AlwaysReconcilingGateway implements PullSyncGateway {
  _AlwaysReconcilingGateway(this.order);
  final List<String> order;
  int _seq = 0;

  @override
  Future<RemoteChangeBatch> pull({
    required int cursor,
    required int limit,
    required String deviceId,
    List<String>? entityTypes,
  }) async {
    order.add('pull');
    _seq += 1;
    return batch([
      change(
        seq: _seq,
        entityType: 'item',
        entityId: 'item-1',
        serverVersion: 4 + _seq,
        payload: serverItem(name: 'Nama $_seq', serverVersion: 4 + _seq),
        fieldVersions: {'name': 4 + _seq, 'unit': 1},
      ),
    ], nextCursor: _seq);
  }
}

final class _RecordingPushGateway implements PushSyncGateway {
  const _RecordingPushGateway(this.order);
  final List<String> order;

  @override
  Future<SyncPushResult> push(SyncOperationEnvelope envelope) async =>
      SyncAcceptedResult(
        requestId: envelope.requestId,
        serverVersion: 1,
        serverUpdatedAtUtc: DateTime.utc(2026, 8, 3),
      );
}

final class _UnusedPlanner implements SyncOperationPlanner {
  @override
  Future<SyncOperationEnvelope> build(SyncOutboxRow row) =>
      throw UnimplementedError('no outbox row is enqueued in these tests');
}

final class _NoopAcknowledgement implements SyncAcknowledgementApplier {
  @override
  Future<void> accept({
    required SyncOutboxRow outbox,
    required String pushedPayloadHash,
    required SyncAcceptedResult result,
  }) async {}

  @override
  Future<void> conflict({
    required SyncOutboxRow outbox,
    required SyncConflictResult result,
  }) async {}
}
