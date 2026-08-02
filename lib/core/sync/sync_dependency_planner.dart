import '../db/app_database.dart';

/// Stable coarse ordering for push dependencies. A workflow snapshot remains a
/// single atomic operation; only independent outbox rows are reordered.
final class SyncDependencyPlanner {
  const SyncDependencyPlanner();

  List<SyncOutboxRow> order(Iterable<SyncOutboxRow> rows) {
    final ordered = rows.toList(growable: false);
    ordered.sort((left, right) {
      final priority = _priority(left).compareTo(_priority(right));
      if (priority != 0) return priority;
      final created = left.createdAt.compareTo(right.createdAt);
      if (created != 0) return created;
      return left.requestId.compareTo(right.requestId);
    });
    return ordered;
  }

  static int _priority(SyncOutboxRow row) => switch (row.aggregateType) {
    'branch' || 'category' => 0,
    'room' || 'user' || 'item' => 1,
    'batch' || 'stock_location' => 2,
    'stock_opname' ||
    'purchase_request' ||
    'delivery_order' ||
    'good_receipt' ||
    'distribution' ||
    'disposal' ||
    'consumption' ||
    'goods_return' => 3,
    'import_audit' || 'export_audit' => 4,
    _ => 5,
  };
}
