/// Wire contract for the Milestone 12C deterministic pull.
///
/// Nothing here trusts a device clock. Ordering is `changeSeq`, a server
/// sequence; recency of a column is `fieldVersions`, a server version. The
/// server timestamps are carried for display and diagnosis only.
library;

/// What the server did to an entity, as far as a puller is concerned.
enum RemoteChangeOperation {
  upsert('upsert'),
  tombstone('tombstone');

  const RemoteChangeOperation(this.wireValue);
  final String wireValue;

  static RemoteChangeOperation? fromWire(String value) {
    for (final operation in RemoteChangeOperation.values) {
      if (operation.wireValue == value) return operation;
    }
    return null;
  }
}

/// One journal entry, resolved to the entity state it points at.
final class RemoteChange {
  const RemoteChange({
    required this.changeSeq,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.serverVersion,
    required this.serverChangedAtUtc,
    required this.fieldVersions,
    this.payload,
  });

  final int changeSeq;
  final String entityType;
  final String entityId;
  final RemoteChangeOperation operation;
  final int serverVersion;
  final DateTime serverChangedAtUtc;

  /// Column name to the entity server version at which it last changed.
  /// Computed by the server; a client never sends these back.
  final Map<String, int> fieldVersions;

  /// The complete aggregate, or null for a tombstone. A document payload always
  /// carries its lines, so a partial document cannot be applied.
  final Map<String, Object?>? payload;

  static RemoteChange fromJson(Map<String, Object?> json) {
    final operation = RemoteChangeOperation.fromWire(
      json['operation'] as String? ?? '',
    );
    if (operation == null) {
      throw const PullSyncPermanentFailure(
        'sync_invalid_payload',
        'Data server tidak dikenali.',
      );
    }
    final rawPayload = json['payload'];
    final rawVersions = json['field_versions'];
    return RemoteChange(
      changeSeq: (json['change_seq'] as num).toInt(),
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as String,
      operation: operation,
      serverVersion: (json['server_version'] as num).toInt(),
      serverChangedAtUtc: DateTime.parse(
        json['server_changed_at_utc'] as String,
      ).toUtc(),
      fieldVersions: rawVersions is Map
          ? {
              for (final entry in rawVersions.entries)
                entry.key as String: (entry.value as num).toInt(),
            }
          : const {},
      payload: rawPayload is Map ? Map<String, Object?>.from(rawPayload) : null,
    );
  }
}

/// One page of the change feed.
final class RemoteChangeBatch {
  const RemoteChangeBatch({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
    required this.serverTimeUtc,
    required this.scopeFingerprint,
  });

  final List<RemoteChange> changes;

  /// The journal position this page consumed, including entries filtered out by
  /// server-side scope. Advancing to it is what stops a device re-reading rows
  /// it will never be shown.
  final int nextCursor;
  final bool hasMore;
  final DateTime serverTimeUtc;

  /// Digest of `user|role|branch`. A change here invalidates the cursor, because
  /// entries the actor could not previously see sit behind it.
  final String scopeFingerprint;

  static RemoteChangeBatch fromJson(Map<String, Object?> json) =>
      RemoteChangeBatch(
        changes: [
          for (final change in (json['changes'] as List<dynamic>? ?? const []))
            RemoteChange.fromJson(Map<String, Object?>.from(change as Map)),
        ],
        nextCursor: (json['next_cursor'] as num).toInt(),
        hasMore: json['has_more'] as bool? ?? false,
        serverTimeUtc: DateTime.parse(
          json['server_time_utc'] as String,
        ).toUtc(),
        scopeFingerprint: json['scope_fingerprint'] as String,
      );
}

/// The authenticated read side of sync. Mirrors [PushSyncGateway] in shape so
/// the two can be faked the same way in tests.
abstract interface class PullSyncGateway {
  Future<RemoteChangeBatch> pull({
    required int cursor,
    required int limit,
    required String deviceId,
    List<String>? entityTypes,
  });
}

sealed class PullSyncFailure implements Exception {
  const PullSyncFailure(this.code, this.safeMessage);
  final String code;
  final String safeMessage;
}

/// Worth trying again on the same cursor: the batch was not applied, so a retry
/// reproduces exactly the same state.
final class PullSyncRetryableFailure extends PullSyncFailure {
  const PullSyncRetryableFailure(
    super.code,
    super.safeMessage, {
    this.httpStatus,
  });
  final int? httpStatus;
}

/// Not worth retrying without operator or session change.
final class PullSyncPermanentFailure extends PullSyncFailure {
  const PullSyncPermanentFailure(super.code, super.safeMessage);
}

/// The stored cursor no longer addresses a readable position — the scope moved,
/// or retention pruned below it. Recovery is a full resync from zero, which is
/// safe because applying a change is idempotent.
final class PullSyncCursorResetRequired extends PullSyncFailure {
  const PullSyncCursorResetRequired()
    : super('sync_cursor_invalid', 'Menyiapkan ulang sinkronisasi data.');
}

/// Codes the pull path may surface. Anything else collapses to
/// `sync_invalid_payload`, so a raw server string never reaches a log or a
/// screen.
abstract final class PullSyncErrorCodes {
  static const cursorInvalid = 'sync_cursor_invalid';
  static const accessDenied = 'sync_access_denied';
  static const identityUnlinked = 'sync_identity_unlinked';
  static const userInactive = 'sync_user_inactive';
  static const invalidPayload = 'sync_invalid_payload';
  static const authRequired = 'sync_auth_required';
  static const retryLater = 'sync_retry_later';

  static const all = <String>{
    cursorInvalid,
    accessDenied,
    identityUnlinked,
    userInactive,
    invalidPayload,
    authRequired,
    retryLater,
  };

  static String messageFor(String code) => switch (code) {
    authRequired => 'Sesi berakhir. Silakan masuk kembali.',
    userInactive => 'Akun sudah tidak aktif.',
    accessDenied => 'Anda tidak berwenang membaca data ini.',
    identityUnlinked => 'Akun belum tertaut ke data aplikasi.',
    cursorInvalid => 'Menyiapkan ulang sinkronisasi data.',
    retryLater => 'Server belum dapat dihubungi. Akan dicoba lagi.',
    _ => 'Data server tidak dapat dibaca.',
  };
}

/// How a conflict or a divergence was settled. Stored in
/// `sync_conflict_logs.resolution`, shown in the Sync Center, and the only
/// vocabulary the UI has for describing an outcome.
abstract final class SyncConflictResolution {
  /// The server's final document replaced local state outright (G-Y2).
  static const serverFinalApplied = 'server_final_applied';

  /// A non-final entity was merged per column and both sides survived (G-Y3).
  static const localNonFinalMerged = 'local_nonfinal_merged';

  /// A local edit lost to a newer server value for the same column.
  static const localChangeSuperseded = 'local_change_superseded';

  /// The server deleted the entity; local state was soft-deleted to match.
  static const tombstoneApplied = 'tombstone_applied';

  /// Automatic recovery would have broken an invariant. A person has to look.
  static const manualReviewRequired = 'manual_review_required';

  static const all = <String>{
    serverFinalApplied,
    localNonFinalMerged,
    localChangeSuperseded,
    tombstoneApplied,
    manualReviewRequired,
  };
}
