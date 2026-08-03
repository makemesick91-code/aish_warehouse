import 'pull_sync_contracts.dart';
import 'sync_entity_policy.dart';

/// The outcome of reconciling one entity, before anything is written.
///
/// Keeping the decision separate from the write is what makes G-Y3 testable
/// without a database, and what makes it possible to say that the result depends
/// only on server versions — never on the order packets happened to arrive in.
final class EntityMergeDecision {
  const EntityMergeDecision({
    required this.values,
    required this.supersededFields,
    required this.preservedLocalFields,
    required this.immutableConflictFields,
  });

  /// Column to canonical value, for every column this reconciliation decides.
  /// Columns absent here are left exactly as they are locally.
  final Map<String, Object?> values;

  /// Local edits that lost to a newer server value for the same column.
  final Set<String> supersededFields;

  /// Local edits the server has not touched, kept and still owed to the server.
  final Set<String> preservedLocalFields;

  /// Columns that identify the row and nonetheless differ. Never merged.
  final Set<String> immutableConflictFields;

  bool get hasLocalWork => preservedLocalFields.isNotEmpty;
  bool get hasConflict =>
      supersededFields.isNotEmpty || immutableConflictFields.isNotEmpty;

  String? get resolution {
    if (immutableConflictFields.isNotEmpty) {
      return SyncConflictResolution.manualReviewRequired;
    }
    if (supersededFields.isNotEmpty) {
      return SyncConflictResolution.localChangeSuperseded;
    }
    if (preservedLocalFields.isNotEmpty) {
      return SyncConflictResolution.localNonFinalMerged;
    }
    return null;
  }
}

/// Decides, column by column, what a pulled entity should look like locally.
///
/// The rule is G-Y3 read strictly: on a non-final entity, the last write wins
/// *per column*, and the arbiter of "last" is the server's per-field version —
/// not a device clock, and not arrival order. Two devices editing different
/// columns therefore both survive, and two devices editing the same column
/// resolve the same way on both devices no matter which packet lands first.
final class EntityReconciler {
  const EntityReconciler();

  /// [serverRow], [localRow] and [baseline] must already be canonical (see
  /// `SyncValueCodec`), so a stored `1` and a JSON `true` compare equal.
  ///
  /// [baseline] is the last server state this device applied. Without it there
  /// is no way to tell a local edit from a column that merely differs, so the
  /// server is taken wholesale — which is correct, because a device with no
  /// baseline has never reconciled this entity and has no claim to make.
  ///
  /// [baseServerVersion] is the entity version this device last acknowledged.
  /// A field whose server version is above it changed after this device's last
  /// word on the subject.
  EntityMergeDecision reconcile({
    required SyncEntityPolicy policy,
    required Map<String, Object?> serverRow,
    required Map<String, Object?> localRow,
    required Map<String, Object?>? baseline,
    required Map<String, int> fieldVersions,
    required int baseServerVersion,
  }) {
    final values = <String, Object?>{};
    final superseded = <String>{};
    final preserved = <String>{};
    final immutableConflicts = <String>{};

    for (final entry in serverRow.entries) {
      final field = entry.key;
      final serverValue = entry.value;

      if (SyncEntityPolicies.isReservedField(field)) {
        // Server-controlled columns are applied verbatim and never negotiated;
        // `id`, `created_at` and `deleted_at` are handled by the applier, which
        // knows about tombstones and row identity.
        if (SyncEntityPolicies.serverControlledFields.contains(field)) {
          values[field] = serverValue;
        }
        continue;
      }

      if (policy.immutableFields.contains(field)) {
        // A natural key or a structural pointer that disagrees is not a merge
        // problem — one side is describing a different thing. The server value
        // is applied because it is authoritative, and the divergence is raised
        // rather than absorbed silently.
        if (localRow.containsKey(field) && localRow[field] != serverValue) {
          immutableConflicts.add(field);
        }
        values[field] = serverValue;
        continue;
      }

      if (!policy.mergeableFields.contains(field)) {
        // Not offered for merging: a document's state machine, its timestamps
        // and its actors all belong to the server (G-Y2).
        values[field] = serverValue;
        continue;
      }

      final localValue = localRow[field];
      final hasBaseline = baseline != null && baseline.containsKey(field);
      final baselineValue = hasBaseline ? baseline[field] : null;
      final localChanged = hasBaseline && localValue != baselineValue;
      final fieldVersion = fieldVersions[field];
      final serverChanged = fieldVersion != null
          ? fieldVersion > baseServerVersion
          : hasBaseline && serverValue != baselineValue;

      if (!localChanged) {
        values[field] = serverValue;
        continue;
      }
      if (serverChanged) {
        // Both sides moved the same column. The server's version is higher by
        // construction — it was assigned after this device's last acknowledged
        // version — so the server wins, deterministically and identically on
        // every device that reconciles this pair.
        values[field] = serverValue;
        if (localValue != serverValue) superseded.add(field);
        continue;
      }
      // Only this device moved it. Keeping the local value is what lets two
      // devices editing different columns both survive; the column is still
      // owed to the server, and the caller re-enqueues the push.
      preserved.add(field);
    }

    return EntityMergeDecision(
      values: values,
      supersededFields: superseded,
      preservedLocalFields: preserved,
      immutableConflictFields: immutableConflicts,
    );
  }

  /// Server state applied wholesale, with no column negotiated.
  ///
  /// Used for final documents (G-Y2), for the ledger and balances, and for any
  /// entity this device has no baseline for.
  EntityMergeDecision serverWins({
    required Map<String, Object?> serverRow,
    required Map<String, Object?> localRow,
    Set<String> localDirtyFields = const {},
  }) => EntityMergeDecision(
    values: {
      for (final entry in serverRow.entries)
        if (!SyncEntityPolicies.alwaysExcludedFields.contains(entry.key))
          entry.key: entry.value,
    },
    supersededFields: {
      for (final field in localDirtyFields)
        if (serverRow.containsKey(field) && serverRow[field] != localRow[field])
          field,
    },
    preservedLocalFields: const {},
    immutableConflictFields: const {},
  );
}
