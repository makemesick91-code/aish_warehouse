import 'package:drift/drift.dart';

import 'base_columns.dart';

/// How far this device has consumed the server change journal, per
/// authorization scope.
///
/// The scope is `(actor, fingerprint)` rather than the actor alone. A cursor is
/// a position in a feed that was already filtered by role and branch, so a
/// promotion or branch move makes it meaningless: entries for entities the actor
/// could not previously see sit permanently behind it and cannot be recovered by
/// reading forward. The server returns a fingerprint of
/// `user|role|branch` with every page, and a value this device has not seen
/// before simply starts at zero. Nothing is shared across accounts.
@DataClassName('SyncPullCursorRow')
@TableIndex(
  name: 'idx_sync_pull_cursors_scope',
  columns: {#actorUserId, #scopeFingerprint},
  unique: true,
)
class SyncPullCursors extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get actorUserId => text()();
  TextColumn get scopeFingerprint => text().withLength(min: 1, max: 128)();
  IntColumn get cursorValue => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPulledAtUtc => dateTime().nullable()();
  DateTimeColumn get lastServerTimeUtc => dateTime().nullable()();
  DateTimeColumn get lastSuccessAtUtc => dateTime().nullable()();
  IntColumn get appliedChangeCount =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (cursor_value >= 0)',
    'CHECK (applied_change_count >= 0)',
  ];
}

/// The last server state this device applied for an entity, kept as the
/// baseline of a three-way merge.
///
/// Field-level last-write-wins (G-Y3) needs to distinguish "the user changed
/// this column" from "this column simply differs from the server", and only a
/// baseline can tell those apart. Storing it here rather than adding per-column
/// dirty flags to every business table keeps the reconciliation concern out of
/// the domain schema entirely.
@DataClassName('SyncEntitySnapshotRow')
@TableIndex(
  name: 'idx_sync_entity_snapshots_entity',
  columns: {#entityType, #entityId},
  unique: true,
)
class SyncEntitySnapshots extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get entityType => text().withLength(min: 1, max: 64)();
  TextColumn get entityId => text()();
  IntColumn get serverVersion => integer()();
  DateTimeColumn get serverChangedAtUtc => dateTime().nullable()();
  TextColumn get snapshotJson => text()();
  DateTimeColumn get appliedAtUtc => dateTime().clientDefault(nowUtc)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (server_version >= 0)'];
}

/// Per-column server versions, mirrored from the pull response.
///
/// The value is the entity's `server_version` at the moment that column last
/// changed, which is what makes the merge deterministic without consulting any
/// device clock. These rows are read-only mirrors: nothing local ever writes a
/// version the server did not send.
@DataClassName('SyncFieldVersionRow')
@TableIndex(
  name: 'idx_sync_field_versions_field',
  columns: {#entityType, #entityId, #fieldName},
  unique: true,
)
class SyncFieldVersions extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get entityType => text().withLength(min: 1, max: 64)();
  TextColumn get entityId => text()();
  TextColumn get fieldName => text().withLength(min: 1, max: 64)();
  IntColumn get fieldVersion => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (field_version >= 0)'];
}

/// Records that the server deleted an entity, so a later stale write cannot
/// bring it back.
///
/// This is deliberately *not* a hard delete. Applying a tombstone writes
/// `deleted_at` on the business row and leaves everything else intact, so
/// foreign keys still resolve and the historical record survives (G-A5). The row
/// here is the memory that makes the deletion stick: an upsert arriving with a
/// server version at or below [serverVersion] is refused, which is what stops a
/// device that was offline for a week from resurrecting a record when it
/// reconnects.
///
/// [hadLocalRow] separates "the server deleted something this device held" from
/// "the server deleted something this device never had", which are different
/// facts and lead to different Sync Center wording.
@DataClassName('SyncTombstoneRow')
@TableIndex(
  name: 'idx_sync_tombstones_entity',
  columns: {#entityType, #entityId},
  unique: true,
)
class SyncTombstones extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get entityType => text().withLength(min: 1, max: 64)();
  TextColumn get entityId => text()();
  IntColumn get serverVersion => integer()();
  DateTimeColumn get tombstonedAtUtc => dateTime().nullable()();
  DateTimeColumn get appliedAtUtc => dateTime().clientDefault(nowUtc)();
  BoolColumn get hadLocalRow => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (server_version >= 0)'];
}

/// One row per pull attempt, for the Sync Center and for after-the-fact
/// diagnosis.
///
/// Deliberately narrow: cursors, counts, and a stable error code. No payload, no
/// entity name, no server message beyond the safe codes the gateway already
/// maps. A log a user can open is a log an attacker can read over their
/// shoulder.
@DataClassName('SyncPullLogRow')
@TableIndex(name: 'idx_sync_pull_logs_finished', columns: {#finishedAt})
@TableIndex(name: 'idx_sync_pull_logs_actor', columns: {#actorUserId})
class SyncPullLogs extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get actorUserId => text()();
  TextColumn get scopeFingerprint => text().nullable().withLength(max: 128)();
  IntColumn get fromCursor => integer()();
  IntColumn get toCursor => integer()();
  IntColumn get changeCount => integer().withDefault(const Constant(0))();
  IntColumn get tombstoneCount => integer().withDefault(const Constant(0))();
  IntColumn get conflictCount => integer().withDefault(const Constant(0))();
  TextColumn get outcome => text().withLength(min: 1, max: 32)();
  TextColumn get safeErrorCode => text().nullable().withLength(max: 96)();
  TextColumn get safeErrorMessage => text().nullable().withLength(max: 512)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (from_cursor >= 0)',
    'CHECK (to_cursor >= 0)',
    'CHECK (change_count >= 0)',
    'CHECK (tombstone_count >= 0)',
    'CHECK (conflict_count >= 0)',
    "CHECK (outcome IN ('applied','empty','failed','cancelled','scope_reset'))",
  ];
}
