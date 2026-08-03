import 'package:aish_warehouse/core/sync/entity_reconciler.dart';
import 'package:aish_warehouse/core/sync/pull_sync_contracts.dart';
import 'package:aish_warehouse/core/sync/sync_entity_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Field-level last-write-wins (G-Y3), tested as pure logic.
///
/// Nothing here touches a database, which is the point: the rule must hold on
/// values and versions alone, with no help from arrival order, transaction
/// timing or a device clock.
void main() {
  const reconciler = EntityReconciler();
  final item = SyncEntityPolicies.forType('item')!;

  /// The state both devices started from.
  Map<String, Object?> baseline() => {
    'id': 'item-1',
    'sku': 'SKU-1',
    'name': 'Masker Bedah',
    'unit': 'box',
    'min_stock_room': 1000,
    'is_active': true,
  };

  EntityMergeDecision merge({
    required Map<String, Object?> server,
    required Map<String, Object?> local,
    Map<String, Object?>? base,
    Map<String, int> fieldVersions = const {},
    int baseServerVersion = 4,
  }) => reconciler.reconcile(
    policy: item,
    serverRow: server,
    localRow: local,
    baseline: base ?? baseline(),
    fieldVersions: fieldVersions,
    baseServerVersion: baseServerVersion,
  );

  group('acceptance 19: different fields from two devices both survive', () {
    test('a local edit the server has not touched is preserved', () {
      // Device A changed `name` and it reached the server (version 5).
      // Device B changed `unit` locally and has not pushed yet.
      final decision = merge(
        server: {...baseline(), 'name': 'Masker Bedah 3 Ply'},
        local: {...baseline(), 'unit': 'pack'},
        fieldVersions: {'name': 5, 'unit': 3},
      );

      expect(decision.values['name'], 'Masker Bedah 3 Ply');
      expect(
        decision.preservedLocalFields,
        {'unit'},
        reason: 'the column the server never moved stays with the device',
      );
      expect(
        decision.values.containsKey('unit'),
        isFalse,
        reason: 'a preserved column is not written back over the local value',
      );
      expect(decision.supersededFields, isEmpty);
      expect(decision.resolution, SyncConflictResolution.localNonFinalMerged);
      expect(decision.hasLocalWork, isTrue);
    });

    test('several untouched local edits all survive one server change', () {
      final decision = merge(
        server: {...baseline(), 'name': 'Nama Server'},
        local: {...baseline(), 'unit': 'pack', 'min_stock_room': 5000},
        fieldVersions: {'name': 5, 'unit': 2, 'min_stock_room': 2},
      );

      expect(decision.preservedLocalFields, {'unit', 'min_stock_room'});
      expect(decision.values['name'], 'Nama Server');
    });
  });

  group('acceptance 20: the same field resolves deterministically', () {
    test('a newer server version beats the local edit', () {
      final decision = merge(
        server: {...baseline(), 'name': 'Nama Server'},
        local: {...baseline(), 'name': 'Nama Lokal'},
        fieldVersions: {'name': 5},
      );

      expect(decision.values['name'], 'Nama Server');
      expect(decision.supersededFields, {'name'});
      expect(decision.resolution, SyncConflictResolution.localChangeSuperseded);
    });

    test('the outcome does not depend on which side is evaluated first', () {
      // The same pair of edits, presented from each device's point of view. Both
      // devices must land on the server value, or they would diverge for good.
      final fromDeviceA = merge(
        server: {...baseline(), 'name': 'Nama Server'},
        local: {...baseline(), 'name': 'Lokal A'},
        fieldVersions: {'name': 5},
      );
      final fromDeviceB = merge(
        server: {...baseline(), 'name': 'Nama Server'},
        local: {...baseline(), 'name': 'Lokal B'},
        fieldVersions: {'name': 5},
      );

      expect(fromDeviceA.values['name'], fromDeviceB.values['name']);
      expect(fromDeviceA.values['name'], 'Nama Server');
    });

    test('a field version at or below the base is not a server change', () {
      // The server row differs, but the version says the change predates this
      // device's last acknowledgement — so it is this device's own pending edit
      // reflected back, not a competing write.
      final decision = merge(
        server: {...baseline(), 'name': 'Nama Lama'},
        local: {...baseline(), 'name': 'Nama Lokal'},
        fieldVersions: {'name': 4},
        baseServerVersion: 4,
      );

      expect(decision.preservedLocalFields, {'name'});
      expect(decision.supersededFields, isEmpty);
    });

    test('a merge is stable when replayed against its own result', () {
      final first = merge(
        server: {...baseline(), 'name': 'Nama Server'},
        local: {...baseline(), 'name': 'Nama Lokal', 'unit': 'pack'},
        fieldVersions: {'name': 5, 'unit': 2},
      );
      final merged = {...baseline(), ...first.values, 'unit': 'pack'};
      final second = reconciler.reconcile(
        policy: item,
        serverRow: {...baseline(), 'name': 'Nama Server'},
        localRow: merged,
        baseline: {...baseline(), 'name': 'Nama Server'},
        fieldVersions: {'name': 5, 'unit': 2},
        baseServerVersion: 5,
      );

      expect(second.supersededFields, isEmpty);
      expect(second.preservedLocalFields, {'unit'});
    });
  });

  group('acceptance 21: server-controlled fields cannot be overwritten', () {
    test('server-owned columns are always taken from the server', () {
      final decision = merge(
        server: {
          ...baseline(),
          'server_version': 9,
          'doc_number': 'PR-2026-0001',
          'sync_status': 'synced',
        },
        local: {
          ...baseline(),
          'server_version': 1,
          'doc_number': 'TMP-LOCAL',
          'sync_status': 'pending',
        },
      );

      expect(decision.values['server_version'], 9);
      expect(decision.values['doc_number'], 'PR-2026-0001');
      expect(decision.values['sync_status'], 'synced');
    });

    test('a column outside the allowlist is never merged', () {
      // `has_expiry` decides whether the item is batch tracked at all. It is
      // declared immutable, so a difference is raised rather than absorbed.
      final decision = merge(
        server: {...baseline(), 'has_expiry': true},
        local: {...baseline(), 'has_expiry': false},
      );

      expect(decision.values['has_expiry'], true);
      expect(decision.immutableConflictFields, {'has_expiry'});
      expect(decision.resolution, SyncConflictResolution.manualReviewRequired);
    });

    test('the natural import key is immutable', () {
      final decision = merge(
        server: {...baseline(), 'sku': 'SKU-SERVER'},
        local: {...baseline(), 'sku': 'SKU-LOKAL'},
      );

      expect(decision.immutableConflictFields, {'sku'});
      expect(decision.values['sku'], 'SKU-SERVER');
    });

    test('identity and device bookkeeping columns are never decided', () {
      final decision = merge(
        server: {
          ...baseline(),
          'created_at': DateTime.utc(2020),
          'updated_at': DateTime.utc(2020),
          'deleted_at': DateTime.utc(2020),
        },
        local: baseline(),
      );

      expect(decision.values.containsKey('id'), isFalse);
      expect(decision.values.containsKey('created_at'), isFalse);
      expect(decision.values.containsKey('updated_at'), isFalse);
      expect(
        decision.values.containsKey('deleted_at'),
        isFalse,
        reason: 'deletion travels as a tombstone, not as a merged column',
      );
    });
  });

  group('a device with no baseline makes no claim', () {
    test('the server is taken wholesale when nothing was ever applied', () {
      final decision = reconciler.reconcile(
        policy: item,
        serverRow: {...baseline(), 'name': 'Nama Server', 'unit': 'pack'},
        localRow: {...baseline(), 'name': 'Nama Lokal'},
        baseline: null,
        fieldVersions: const {},
        baseServerVersion: 0,
      );

      expect(decision.values['name'], 'Nama Server');
      expect(decision.values['unit'], 'pack');
      expect(
        decision.preservedLocalFields,
        isEmpty,
        reason:
            'without a baseline a difference cannot be attributed to the user',
      );
    });
  });

  group('an unchanged entity produces no work and no noise', () {
    test('identical rows resolve to nothing at all', () {
      final decision = merge(server: baseline(), local: baseline());

      expect(decision.supersededFields, isEmpty);
      expect(decision.preservedLocalFields, isEmpty);
      expect(decision.immutableConflictFields, isEmpty);
      expect(decision.resolution, isNull);
      expect(decision.hasConflict, isFalse);
    });
  });

  group('serverWins is absolute', () {
    test('every server column is applied and local dirt is reported', () {
      final decision = reconciler.serverWins(
        serverRow: {...baseline(), 'name': 'Server'},
        localRow: {...baseline(), 'name': 'Lokal'},
        localDirtyFields: {'name'},
      );

      expect(decision.values['name'], 'Server');
      expect(decision.supersededFields, {'name'});
      expect(decision.preservedLocalFields, isEmpty);
    });

    test('a local value that already matches is not reported as lost', () {
      final decision = reconciler.serverWins(
        serverRow: baseline(),
        localRow: baseline(),
        localDirtyFields: {'name'},
      );

      expect(decision.supersededFields, isEmpty);
    });
  });
}
