// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncDevicesTable get syncDevices => attachedDatabase.syncDevices;
  $SyncOutboxTable get syncOutbox => attachedDatabase.syncOutbox;
  $SyncEntityStatesTable get syncEntityStates =>
      attachedDatabase.syncEntityStates;
  $SyncAttemptLogsTable get syncAttemptLogs => attachedDatabase.syncAttemptLogs;
  $SyncConflictLogsTable get syncConflictLogs =>
      attachedDatabase.syncConflictLogs;
  $SyncFileUploadsTable get syncFileUploads => attachedDatabase.syncFileUploads;
}
