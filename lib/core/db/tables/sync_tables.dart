import 'package:drift/drift.dart';

import 'base_columns.dart';

/// Stable installation identity. It is deliberately application-generated and
/// is neither a credential nor a hardware identifier.
@DataClassName('SyncDeviceRow')
@TableIndex(
  name: 'idx_sync_devices_install',
  columns: {#appInstallId},
  unique: true,
)
class SyncDevices extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  DateTimeColumn get createdAt => dateTime().clientDefault(nowUtc)();
  DateTimeColumn get lastSeenAt => dateTime().clientDefault(nowUtc)();
  TextColumn get appInstallId => text().withLength(min: 1, max: 128)();
  TextColumn get displayLabel => text().nullable().withLength(max: 128)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncOutboxRow')
@TableIndex(
  name: 'idx_sync_outbox_due',
  columns: {#status, #nextAttemptEpochMs},
)
@TableIndex(
  name: 'idx_sync_outbox_actor_status',
  columns: {#actorUserId, #status},
)
@TableIndex(
  name: 'idx_sync_outbox_aggregate',
  columns: {#aggregateType, #aggregateId},
)
@TableIndex(
  name: 'idx_sync_outbox_request',
  columns: {#requestId},
  unique: true,
)
@TableIndex(name: 'idx_sync_outbox_device', columns: {#deviceId})
class SyncOutbox extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get requestId => text()();
  TextColumn get deviceId => text().references(SyncDevices, #id)();
  TextColumn get operationType => text().withLength(min: 1, max: 64)();
  TextColumn get aggregateType => text().withLength(min: 1, max: 64)();
  TextColumn get aggregateId => text()();

  /// Original business actor. Legacy master rows created before schema v14 do
  /// not carry actor provenance, so their permanently blocked reconstruction
  /// deliberately stores NULL instead of inventing an identity.
  TextColumn get actorUserId => text().nullable()();
  IntColumn get payloadVersion => integer().withDefault(const Constant(1))();
  IntColumn get baseServerVersion => integer().withDefault(const Constant(0))();
  DateTimeColumn get occurredAtUtc => dateTime()();
  TextColumn get payloadHash => text()();
  TextColumn get status => text().withDefault(const Constant('queued'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptEpochMs =>
      integer().withDefault(const Constant(0))();
  IntColumn get leaseStartedEpochMs => integer().nullable()();
  TextColumn get lastErrorCode => text().nullable().withLength(max: 96)();
  TextColumn get lastErrorMessage => text().nullable().withLength(max: 512)();
  DateTimeColumn get createdAt => dateTime().clientDefault(nowUtc)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(nowUtc)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('queued','processing','blocked','conflict'))",
    'CHECK (attempt_count >= 0)',
    'CHECK (payload_version > 0)',
    'CHECK (base_server_version >= 0)',
    "CHECK (payload_hash GLOB '[0-9a-f]*' AND length(payload_hash) = 64)",
    "CHECK ((status = 'processing' AND lease_started_epoch_ms IS NOT NULL) OR "
        "(status <> 'processing' AND lease_started_epoch_ms IS NULL))",
  ];
}

@DataClassName('SyncEntityStateRow')
@TableIndex(
  name: 'idx_sync_entity_states_aggregate',
  columns: {#aggregateType, #aggregateId},
  unique: true,
)
class SyncEntityStates extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get aggregateType => text().withLength(min: 1, max: 64)();
  TextColumn get aggregateId => text()();
  IntColumn get serverVersion => integer().withDefault(const Constant(0))();
  DateTimeColumn get serverUpdatedAtUtc => dateTime().nullable()();
  TextColumn get lastSyncedPayloadHash => text().nullable()();
  TextColumn get lastSyncedRequestId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (server_version >= 0)',
    "CHECK (last_synced_payload_hash IS NULL OR "
        "(last_synced_payload_hash GLOB '[0-9a-f]*' AND "
        'length(last_synced_payload_hash) = 64))',
  ];
}

@DataClassName('SyncAttemptLogRow')
@TableIndex(
  name: 'idx_sync_attempt_logs_request',
  columns: {#requestId, #attemptNumber},
)
class SyncAttemptLogs extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get requestId => text()();
  IntColumn get attemptNumber => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime()();
  TextColumn get outcome => text().withLength(min: 1, max: 32)();
  IntColumn get httpStatus => integer().nullable()();
  TextColumn get safeErrorCode => text().nullable().withLength(max: 96)();
  TextColumn get safeErrorMessage => text().nullable().withLength(max: 512)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (attempt_number > 0)',
    "CHECK (outcome IN ('accepted','replayed','retryable','conflict','permanent','cancelled'))",
  ];
}

@DataClassName('SyncConflictLogRow')
@TableIndex(name: 'idx_sync_conflict_logs_request', columns: {#requestId})
@TableIndex(
  name: 'idx_sync_conflict_logs_aggregate',
  columns: {#aggregateType, #aggregateId},
)
class SyncConflictLogs extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get requestId => text()();
  TextColumn get aggregateType => text().withLength(min: 1, max: 64)();
  TextColumn get aggregateId => text()();
  TextColumn get operationType => text().withLength(min: 1, max: 64)();
  TextColumn get conflictCode => text().withLength(min: 1, max: 96)();
  IntColumn get baseVersion => integer()();
  IntColumn get serverVersion => integer().nullable()();
  TextColumn get safeDetailJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get detectedAt => dateTime().clientDefault(nowUtc)();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get resolution => text().nullable().withLength(max: 64)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (base_version >= 0)',
    'CHECK (server_version IS NULL OR server_version >= 0)',
    'CHECK ((resolved_at IS NULL AND resolution IS NULL) OR '
        '(resolved_at IS NOT NULL AND resolution IS NOT NULL))',
  ];
}

@DataClassName('SyncFileUploadRow')
@TableIndex(
  name: 'idx_sync_file_uploads_request',
  columns: {#requestId},
  unique: true,
)
@TableIndex(name: 'idx_sync_file_uploads_status', columns: {#status})
@TableIndex(
  name: 'idx_sync_file_uploads_actor_status',
  columns: {#actorUserId, #status},
)
class SyncFileUploads extends Table {
  TextColumn get id => text().clientDefault(newUuidV4)();
  TextColumn get requestId => text()();
  TextColumn get entityType => text().withLength(min: 1, max: 64)();
  TextColumn get entityId => text()();
  TextColumn get actorUserId => text()();
  TextColumn get localFilePath => text()();
  TextColumn get originalFileName => text().withLength(min: 1, max: 255)();
  TextColumn get sha256 => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get mimeType => text().withLength(min: 1, max: 128)();
  TextColumn get remoteBucket => text().withLength(min: 1, max: 64)();
  TextColumn get remoteObjectKey => text().nullable()();
  TextColumn get remoteObjectId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('queued'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptEpochMs =>
      integer().withDefault(const Constant(0))();
  IntColumn get leaseStartedEpochMs => integer().nullable()();
  TextColumn get lastErrorCode => text().nullable().withLength(max: 96)();
  TextColumn get lastErrorMessage => text().nullable().withLength(max: 512)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (sha256 GLOB '[0-9a-f]*' AND length(sha256) = 64)",
    'CHECK (size_bytes >= 0)',
    'CHECK (attempt_count >= 0)',
    'CHECK (next_attempt_epoch_ms >= 0)',
    "CHECK ((status = 'processing' AND lease_started_epoch_ms IS NOT NULL) OR "
        "(status <> 'processing' AND lease_started_epoch_ms IS NULL))",
    "CHECK (status IN ('queued','processing','uploaded','finalized','blocked','conflict'))",
    "CHECK (remote_bucket IN ('import-audit','report-artifacts'))",
  ];
}
