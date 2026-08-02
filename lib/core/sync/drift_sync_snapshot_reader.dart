import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'sync_contracts.dart';

/// Reads one complete local aggregate while the caller's Drift transaction is
/// still active. Header/children/movements are always hashed and pushed as one
/// snapshot; widgets and repositories never assemble partial RPC payloads.
final class DriftSyncSnapshotReader {
  const DriftSyncSnapshotReader(this._db);

  final AppDatabase _db;

  static const _table = <String, String>{
    'branch': 'branches',
    'room': 'rooms',
    'user': 'users',
    'category': 'item_categories',
    'item': 'items',
    'batch': 'item_batches',
    'stock_location': 'stock_locations',
    'stock_opname': 'stock_opnames',
    'purchase_request': 'purchase_requests',
    'delivery_order': 'delivery_orders',
    'good_receipt': 'good_receipts',
    'distribution': 'distributions',
    'disposal': 'disposals',
    'consumption': 'consumptions',
    'goods_return': 'goods_returns',
    'import_audit': 'import_logs',
    'export_audit': 'export_logs',
  };
  static const _children = <String, (String, String)>{
    'stock_opname': ('stock_opname_lines', 'opname_id'),
    'purchase_request': ('purchase_request_lines', 'pr_id'),
    'delivery_order': ('delivery_order_lines', 'do_id'),
    'good_receipt': ('good_receipt_lines', 'gr_id'),
    'distribution': ('distribution_lines', 'distribution_id'),
    'disposal': ('disposal_lines', 'disposal_id'),
    'consumption': ('consumption_lines', 'consumption_id'),
    'goods_return': ('goods_return_lines', 'goods_return_id'),
  };
  static const _ref = <String, String>{
    'stock_opname': 'SO',
    'delivery_order': 'DO',
    'good_receipt': 'GR',
    'distribution': 'DIST',
    'disposal': 'DSP',
    'consumption': 'CONS',
    'goods_return': 'RET',
  };

  Future<JsonSyncPayload> read({
    required SyncAggregateType aggregateType,
    required String aggregateId,
  }) async {
    final wireType = aggregateType.wireValue;
    final table = _table[wireType];
    if (table == null) {
      throw const SyncPermanentFailure(
        'sync_invalid_payload',
        'Jenis data tidak dikenal.',
      );
    }
    final header = await _db
        .customSelect(
          // Include soft-deleted master/audit rows: archiving is itself a
          // server-authoritative mutation and must be represented in the
          // aggregate snapshot. Document operations are only planned from
          // live headers, so widening this lookup cannot resurrect a document.
          'SELECT * FROM $table WHERE id = ?;',
          variables: [Variable<String>(aggregateId)],
        )
        .getSingleOrNull();
    if (header == null) {
      throw const SyncPermanentFailure(
        'sync_document_not_found',
        'Data lokal tidak ditemukan.',
      );
    }
    final payload = <String, Object?>{
      for (final entry in header.data.entries) entry.key: _wire(entry.value),
    };
    // The server binds an import audit to the finalized private object. An
    // absolute device path is neither portable nor safe to transmit.
    if (wireType == 'import_audit') payload.remove('stored_file_path');
    if (wireType == 'branch' || wireType == 'room') {
      final foreignKey = wireType == 'branch' ? 'branch_id' : 'room_id';
      final locations = await _db
          .customSelect(
            'SELECT * FROM stock_locations WHERE $foreignKey = ? '
            'ORDER BY id;',
            variables: [Variable<String>(aggregateId)],
          )
          .get();
      payload['stock_locations'] = [
        for (final location in locations)
          {
            for (final entry in location.data.entries)
              entry.key: _wire(entry.value),
          },
      ];
    }
    final child = _children[wireType];
    if (child != null) {
      final lines = await _db
          .customSelect(
            'SELECT * FROM ${child.$1} WHERE ${child.$2} = ? '
            'AND deleted_at IS NULL ORDER BY id;',
            variables: [Variable<String>(aggregateId)],
          )
          .get();
      payload['lines'] = [
        for (final line in lines)
          {
            for (final entry in line.data.entries)
              entry.key: _wire(entry.value),
          },
      ];
    }
    if (wireType == 'purchase_request') {
      final links = await _db
          .customSelect(
            'SELECT * FROM purchase_request_opnames WHERE pr_id = ? '
            'AND deleted_at IS NULL ORDER BY id;',
            variables: [Variable<String>(aggregateId)],
          )
          .get();
      payload['opname_links'] = [
        for (final link in links)
          {
            for (final entry in link.data.entries)
              entry.key: _wire(entry.value),
          },
      ];
    }
    final ref = _ref[wireType];
    if (ref != null) {
      final movements = await _db
          .customSelect(
            'SELECT * FROM stock_movements WHERE ref_doc_type = ? '
            'AND ref_doc_id = ? ORDER BY id;',
            variables: [Variable<String>(ref), Variable<String>(aggregateId)],
          )
          .get();
      payload['movements'] = [
        for (final movement in movements)
          {
            for (final entry in movement.data.entries)
              entry.key: _wire(entry.value),
          },
      ];
    }
    return JsonSyncPayload(payload);
  }

  static Object? _wire(Object? value) =>
      value is DateTime ? value.toUtc().toIso8601String() : value;
}
