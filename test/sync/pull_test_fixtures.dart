import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/sync/pull_sync_contracts.dart';

/// Fixtures shared by the Milestone 12C pull tests.
///
/// Server payloads are written the way PostgREST actually delivers them —
/// booleans as JSON booleans, timestamps as ISO strings with an offset, dates
/// without a time part — so the tests exercise the same decoding path the real
/// gateway does rather than a Dart-shaped convenience.
const fixtureNow = '2026-08-03T00:00:00.000Z';

/// Minimal master data every document fixture depends on.
Future<void> seedLocalMaster(AppDatabase database) async {
  await database.customStatement(
    'INSERT INTO branches (id,created_at,updated_at,sync_status,code,name,'
    'is_active) VALUES (?,?,?,?,?,?,?);',
    ['branch-1', fixtureNow, fixtureNow, 'synced', 'B1', 'Cabang Satu', 1],
  );
  await database.customStatement(
    'INSERT INTO rooms (id,created_at,updated_at,sync_status,branch_id,code,'
    'name,is_active) VALUES (?,?,?,?,?,?,?,?);',
    ['room-1', fixtureNow, fixtureNow, 'synced', 'branch-1', 'R1', 'Ruang', 1],
  );
  await database.customStatement(
    'INSERT INTO users (id,created_at,updated_at,sync_status,full_name,email,'
    'role,branch_id,is_active) VALUES (?,?,?,?,?,?,?,?,?);',
    [
      'user-1',
      fixtureNow,
      fixtureNow,
      'synced',
      'Perawat',
      'perawat@example.test',
      'perawat',
      'branch-1',
      1,
    ],
  );
  await database.customStatement(
    'INSERT INTO item_categories (id,created_at,updated_at,sync_status,name) '
    'VALUES (?,?,?,?,?);',
    ['cat-1', fixtureNow, fixtureNow, 'synced', 'Kategori'],
  );
  await database.customStatement(
    'INSERT INTO items (id,created_at,updated_at,sync_status,sku,name,'
    'category_id,unit,min_stock_room,min_stock_branch,has_expiry,'
    'expiry_alert_days,is_active) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);',
    [
      'item-1',
      fixtureNow,
      fixtureNow,
      'synced',
      'SKU-1',
      'Masker Bedah',
      'cat-1',
      'box',
      1000,
      3000,
      0,
      30,
      1,
    ],
  );
  await database.customStatement(
    'INSERT INTO stock_locations (id,created_at,updated_at,sync_status,type,'
    'branch_id,room_id,name) VALUES (?,?,?,?,?,?,?,?);',
    [
      'loc-room',
      fixtureNow,
      fixtureNow,
      'synced',
      'room',
      'branch-1',
      'room-1',
      'Ruang',
    ],
  );
  await database.customStatement(
    'INSERT INTO stock_locations (id,created_at,updated_at,sync_status,type,'
    'branch_id,room_id,name) VALUES (?,?,?,?,?,?,?,?);',
    [
      'loc-store',
      fixtureNow,
      fixtureNow,
      'synced',
      'branch_store',
      'branch-1',
      null,
      'Gudang Cabang',
    ],
  );
}

/// The header columns a server `items` row carries on the wire.
Map<String, Object?> serverItem({
  String id = 'item-1',
  String name = 'Masker Bedah',
  String unit = 'box',
  int minStockRoom = 1000,
  bool isActive = true,
  String sku = 'SKU-1',
  int serverVersion = 5,
}) => {
  'id': id,
  'created_at': '2026-08-01T00:00:00+00:00',
  'updated_at': '2026-08-03T00:00:00+00:00',
  'deleted_at': null,
  'sync_status': 'synced',
  'server_version': serverVersion,
  'server_updated_at': '2026-08-03T00:00:00+00:00',
  'sku': sku,
  'name': name,
  'category_id': 'cat-1',
  'unit': unit,
  'min_stock_room': minStockRoom,
  'min_stock_branch': 3000,
  'has_expiry': false,
  'expiry_alert_days': 30,
  'is_active': isActive,
};

/// A posted consumption with one line and one movement — a complete aggregate,
/// which is the only shape a document ever arrives in.
Map<String, Object?> serverConsumption({
  String id = 'cons-1',
  String status = 'posted',
  String docNumber = 'CNS-2026-0001',
  List<Map<String, Object?>>? movements,
}) => {
  'id': id,
  'created_at': '2026-08-01T00:00:00+00:00',
  'updated_at': '2026-08-03T00:00:00+00:00',
  'deleted_at': null,
  'sync_status': 'synced',
  'server_version': 3,
  'doc_number': docNumber,
  'branch_id': 'branch-1',
  'room_id': 'room-1',
  'created_by': 'user-1',
  'status': status,
  'posted_by': 'user-1',
  'posted_at': '2026-08-03T00:00:00+00:00',
  'note': null,
  'lines': [
    {
      'id': 'cons-line-1',
      'created_at': '2026-08-01T00:00:00+00:00',
      'updated_at': '2026-08-03T00:00:00+00:00',
      'deleted_at': null,
      'sync_status': 'synced',
      'consumption_id': id,
      'item_id': 'item-1',
      'batch_id': null,
      'qty': 1000,
      'note': null,
    },
  ],
  'movements':
      movements ??
      [
        {
          'id': 'mov-server-1',
          'created_at': '2026-08-03T00:00:00+00:00',
          'updated_at': '2026-08-03T00:00:00+00:00',
          'deleted_at': null,
          'sync_status': 'synced',
          'item_id': 'item-1',
          'batch_id': null,
          'from_location_id': 'loc-room',
          'to_location_id': null,
          'qty': 1000,
          'movement_type': 'consumption',
          'ref_doc_type': 'CONS',
          'ref_doc_id': id,
          'actor_user_id': 'user-1',
          'note': null,
          'reversal_of_movement_id': null,
        },
      ],
};

RemoteChange change({
  required int seq,
  required String entityType,
  required String entityId,
  RemoteChangeOperation operation = RemoteChangeOperation.upsert,
  int serverVersion = 5,
  Map<String, Object?>? payload,
  Map<String, int> fieldVersions = const {},
}) => RemoteChange(
  changeSeq: seq,
  entityType: entityType,
  entityId: entityId,
  operation: operation,
  serverVersion: serverVersion,
  serverChangedAtUtc: DateTime.utc(2026, 8, 3),
  fieldVersions: fieldVersions,
  payload: payload,
);

RemoteChangeBatch batch(
  List<RemoteChange> changes, {
  int? nextCursor,
  bool hasMore = false,
  String fingerprint = 'scope-a',
}) => RemoteChangeBatch(
  changes: changes,
  nextCursor: nextCursor ?? (changes.isEmpty ? 0 : changes.last.changeSeq),
  hasMore: hasMore,
  serverTimeUtc: DateTime.utc(2026, 8, 3),
  scopeFingerprint: fingerprint,
);

/// A gateway that serves pre-built pages and records what was asked for.
///
/// Pages are selected by cursor rather than by call order, so a resync from zero
/// re-serves exactly what it served the first time — which is the property the
/// idempotency tests are about. When no page is left the fallback keeps the
/// scope fingerprint of the configured pages: a server does not change scope
/// just because a client has caught up.
final class FakePullGateway implements PullSyncGateway {
  FakePullGateway(this.pages);

  final List<RemoteChangeBatch> pages;
  final List<int> requestedCursors = [];
  int calls = 0;
  Object? failWith;
  int failAfterCalls = -1;
  void Function()? onPull;

  @override
  Future<RemoteChangeBatch> pull({
    required int cursor,
    required int limit,
    required String deviceId,
    List<String>? entityTypes,
  }) async {
    requestedCursors.add(cursor);
    calls += 1;
    onPull?.call();
    if (failWith != null && calls > failAfterCalls) {
      throw failWith!;
    }
    return pages.firstWhere(
      (page) =>
          page.changes.isNotEmpty &&
          page.changes.every((change) => change.changeSeq > cursor),
      orElse: () => batch(
        const [],
        nextCursor: cursor,
        fingerprint: pages.isEmpty ? 'scope-a' : pages.last.scopeFingerprint,
      ),
    );
  }
}
