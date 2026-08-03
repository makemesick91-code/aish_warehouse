import 'package:aish_warehouse/core/sync/pull_sync_contracts.dart';
import 'package:aish_warehouse/core/sync/sync_entity_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// The entity classification the whole pull path branches on.
///
/// The mergeable lists here have a twin in
/// `app_private.pull_mergeable_fields`, and the two are pinned from both sides:
/// this file fixes the client's list literally, and
/// `supabase/tests/database/pull_sync.test.sql` fixes the server's. A change to
/// only one of them fails one of the two suites, which is the point — a client
/// that merges a column the server does not version has no ordering to merge by.
void main() {
  group('the classification says what may be merged', () {
    test('only master data merges per column', () {
      for (final policy in SyncEntityPolicies.all) {
        if (policy.entityClass == SyncEntityClass.master) continue;
        expect(
          policy.mergeableFields,
          isEmpty,
          reason:
              '${policy.entityType} is ${policy.entityClass.name}; G-Y3 permits '
              'per-column merging on non-final entities only',
        );
      }
    });

    test('the client and server mergeable lists agree', () {
      // Restated literally rather than derived, so a change has to be made in
      // both places deliberately.
      expect(SyncEntityPolicies.forType('branch')!.mergeableFields, {
        'name',
        'address',
        'is_active',
      });
      expect(SyncEntityPolicies.forType('room')!.mergeableFields, {
        'code',
        'name',
        'is_active',
      });
      expect(SyncEntityPolicies.forType('user')!.mergeableFields, {
        'full_name',
        'role',
        'branch_id',
        'is_active',
      });
      expect(SyncEntityPolicies.forType('category')!.mergeableFields, {'name'});
      expect(SyncEntityPolicies.forType('item')!.mergeableFields, {
        'name',
        'category_id',
        'unit',
        'min_stock_room',
        'min_stock_branch',
        'expiry_alert_days',
        'is_active',
      });
      expect(SyncEntityPolicies.forType('batch')!.mergeableFields, {
        'expiry_date',
      });
      expect(SyncEntityPolicies.forType('stock_location')!.mergeableFields, {
        'name',
      });
    });

    test('no reserved column is ever offered for merging', () {
      for (final policy in SyncEntityPolicies.all) {
        for (final field in policy.mergeableFields) {
          expect(
            SyncEntityPolicies.isReservedField(field),
            isFalse,
            reason: '$field on ${policy.entityType} is server or device owned',
          );
        }
      }
    });

    test('a mergeable column is never also immutable', () {
      for (final policy in SyncEntityPolicies.all) {
        expect(
          policy.mergeableFields.intersection(policy.immutableFields),
          isEmpty,
          reason:
              '${policy.entityType} cannot both negotiate and freeze a column',
        );
      }
    });

    test('the natural keys the import workflow uses are immutable', () {
      // G-M4 upserts by these keys. A merge that moved one would re-point every
      // historical row at a different thing.
      expect(
        SyncEntityPolicies.forType('item')!.immutableFields,
        contains('sku'),
      );
      expect(
        SyncEntityPolicies.forType('branch')!.immutableFields,
        contains('code'),
      );
      expect(
        SyncEntityPolicies.forType('user')!.immutableFields,
        contains('email'),
      );
      expect(
        SyncEntityPolicies.forType('batch')!.immutableFields,
        containsAll(<String>['item_id', 'batch_no']),
      );
    });
  });

  group('the classification says what may be tombstoned', () {
    test('an entity whose history is load-bearing is never tombstoned', () {
      // G-A4: master data used by transactions is deactivated, not deleted.
      // A domain user is an actor on every document they ever posted.
      for (final type in const ['branch', 'room', 'user', 'item']) {
        expect(
          SyncEntityPolicies.forType(type)!.tombstonable,
          isFalse,
          reason: '$type is deactivated with is_active, never deleted',
        );
      }
    });

    test('append-only and cache entities are never tombstoned', () {
      expect(
        SyncEntityPolicies.forType('stock_movement')!.tombstonable,
        isFalse,
        reason: 'G-A1 makes the ledger append-only',
      );
      expect(
        SyncEntityPolicies.forType('stock_balance')!.tombstonable,
        isFalse,
      );
    });

    test('the entities that can be soft-deleted do replicate a tombstone', () {
      for (final type in const ['category', 'batch', 'stock_location']) {
        expect(SyncEntityPolicies.forType(type)!.tombstonable, isTrue);
      }
    });
  });

  group('the classification says which documents are final', () {
    test('every document declares at least one final status', () {
      for (final policy in SyncEntityPolicies.all) {
        if (policy.entityClass != SyncEntityClass.document) continue;
        expect(
          policy.finalStatuses,
          isNotEmpty,
          reason:
              '${policy.entityType} needs a final state or G-Y2 has nothing to '
              'trigger server-wins on',
        );
      }
    });

    test('a posting status is final and a draft never is', () {
      expect(
        SyncEntityPolicies.forType('consumption')!.isFinalStatus('posted'),
        isTrue,
      );
      expect(
        SyncEntityPolicies.forType('consumption')!.isFinalStatus('draft'),
        isFalse,
      );
      expect(
        SyncEntityPolicies.forType('goods_return')!.isFinalStatus('received'),
        isTrue,
      );
      expect(
        SyncEntityPolicies.forType('item')!.isFinalStatus('posted'),
        isFalse,
      );
      expect(SyncEntityPolicies.forType('item')!.isFinalStatus(null), isFalse);
    });
  });

  group('the classification says how a document is assembled', () {
    test('every document names the child table its payload carries', () {
      for (final policy in SyncEntityPolicies.all) {
        if (policy.entityClass != SyncEntityClass.document) continue;
        expect(
          policy.child,
          isNotNull,
          reason: 'a document without its lines is a partial document',
        );
      }
    });

    test('a purchase request never posts to the ledger', () {
      // Spec §2.5: a request is a request. Only the shipment moves stock.
      expect(
        SyncEntityPolicies.forType('purchase_request')!.movementRefType,
        isNull,
      );
      expect(
        SyncEntityPolicies.forType('purchase_request')!.extraChildren,
        hasLength(1),
        reason: 'its opname links travel with it',
      );
    });

    test('every posting document names its ledger reference type', () {
      const posting = {
        'stock_opname': 'SO',
        'delivery_order': 'DO',
        'good_receipt': 'GR',
        'distribution': 'DIST',
        'disposal': 'DSP',
        'consumption': 'CONS',
        'goods_return': 'RET',
      };
      posting.forEach((type, ref) {
        expect(SyncEntityPolicies.forType(type)!.movementRefType, ref);
      });
    });
  });

  test('every pullable type resolves to a policy and a distinct table', () {
    final tables = <String>{};
    for (final type in SyncEntityPolicies.pullableTypes) {
      final policy = SyncEntityPolicies.forType(type);
      expect(policy, isNotNull);
      expect(policy!.entityType, type);
      expect(
        tables.add(policy.table),
        isTrue,
        reason: 'two entity types must not share a table',
      );
    }
  });

  test('an unknown entity type resolves to nothing rather than a default', () {
    expect(SyncEntityPolicies.forType('something_new'), isNull);
  });

  test('every resolution code the applier can write is a known one', () {
    expect(SyncConflictResolution.all, {
      SyncConflictResolution.serverFinalApplied,
      SyncConflictResolution.localNonFinalMerged,
      SyncConflictResolution.localChangeSuperseded,
      SyncConflictResolution.tombstoneApplied,
      SyncConflictResolution.manualReviewRequired,
    });
  });
}
