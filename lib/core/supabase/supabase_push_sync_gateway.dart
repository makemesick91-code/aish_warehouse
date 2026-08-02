import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/sync_contracts.dart';
import '../sync/sync_payload_hasher.dart';

final class SupabasePushSyncGateway implements PushSyncGateway {
  const SupabasePushSyncGateway(this.client);
  final SupabaseClient client;

  @override
  Future<SyncPushResult> push(SyncOperationEnvelope envelope) async {
    try {
      final operationEnvelope = envelope.toJson();
      operationEnvelope['payload_hash'] = const Sha256SyncPayloadHasher().hash(
        operationEnvelope,
      );
      final raw = await client.rpc(
        'push_sync_operation',
        params: {'operation_envelope': operationEnvelope},
      );
      final value = Map<String, dynamic>.from(raw as Map);
      final outcome = value['outcome'] as String;
      final requestId = SyncRequestId(value['request_id'] as String);
      if (outcome == 'conflict') {
        return SyncConflictResult(
          requestId: requestId,
          code: value['code'] as String,
          safeMessage: value['message'] as String,
          baseVersion: value['base_server_version'] as int? ?? 0,
          serverVersion: value['server_version'] as int?,
        );
      }
      final result = SyncAcceptedResult(
        requestId: requestId,
        serverVersion: value['server_version'] as int,
        serverUpdatedAtUtc: DateTime.parse(
          value['server_updated_at_utc'] as String,
        ).toUtc(),
        finalDocumentNumber: value['final_document_number'] as String?,
        movementIds: (value['movement_ids'] as List<dynamic>? ?? const [])
            .cast<String>(),
      );
      if (outcome == 'replayed') {
        return SyncReplayResult(
          requestId: result.requestId,
          serverVersion: result.serverVersion,
          serverUpdatedAtUtc: result.serverUpdatedAtUtc,
          finalDocumentNumber: result.finalDocumentNumber,
          movementIds: result.movementIds,
        );
      }
      return result;
    } on TimeoutException {
      throw const SyncRetryableFailure(
        'sync_retry_later',
        'Server belum dapat dihubungi. Akan dicoba lagi.',
      );
    } on SocketException {
      throw const SyncRetryableFailure(
        'sync_retry_later',
        'Server belum dapat dihubungi. Akan dicoba lagi.',
      );
    } on PostgrestException catch (error) {
      final code = _stableCode(error);
      if (code == 'sync_retry_later' ||
          code == 'sync_dependency_pending' ||
          error.code == '429' ||
          (error.code?.startsWith('5') ?? false)) {
        throw SyncRetryableFailure(code, _message(code));
      }
      throw SyncPermanentFailure(code, _message(code));
    }
  }

  static String _stableCode(PostgrestException error) {
    if (_serverCodes.contains(error.message)) return error.message;
    final details = error.details;
    if (details is Map && details['code'] is String) {
      return details['code'] as String;
    }
    return switch (error.code) {
      '42501' => 'sync_access_denied',
      'PGRST301' => 'sync_auth_required',
      _ => 'sync_invalid_payload',
    };
  }

  static const _serverCodes = <String>{
    'sync_auth_required',
    'sync_identity_unlinked',
    'sync_user_inactive',
    'sync_actor_mismatch',
    'sync_access_denied',
    'sync_server_revision_mismatch',
    'sync_invalid_payload',
    'sync_payload_hash_mismatch',
    'sync_request_id_reused',
    'sync_stale_version',
    'sync_final_state_conflict',
    'sync_dependency_missing',
    'sync_dependency_pending',
    'sync_document_not_found',
    'sync_document_state_invalid',
    'sync_line_integrity_invalid',
    'sync_movement_plan_mismatch',
    'sync_insufficient_stock',
    'sync_batch_invalid',
    'sync_batch_expired',
    'sync_fefo_override_required',
    'sync_document_number_conflict',
    'sync_upload_not_authorized',
    'sync_upload_expired',
    'sync_upload_hash_mismatch',
    'sync_upload_size_mismatch',
    'sync_upload_object_missing',
    'sync_upload_too_large',
    'sync_retry_later',
  };

  static String _message(String code) => switch (code) {
    'sync_auth_required' => 'Sesi berakhir. Silakan masuk kembali.',
    'sync_user_inactive' => 'Akun sudah tidak aktif.',
    'sync_actor_mismatch' => 'Operasi menunggu akun pembuatnya.',
    'sync_access_denied' => 'Anda tidak berwenang menyinkronkan data ini.',
    'sync_stale_version' => 'Data server lebih baru dan perlu ditinjau.',
    'sync_insufficient_stock' => 'Stok server tidak mencukupi.',
    _ => 'Data tidak dapat diterima server.',
  };
}

final class SupabaseSyncDeviceGateway implements SyncDeviceGateway {
  const SupabaseSyncDeviceGateway(this.client);
  final SupabaseClient client;

  @override
  Future<void> register({
    required String deviceId,
    required String appInstallId,
    String? displayLabel,
  }) async {
    await client.rpc(
      'register_sync_device',
      params: {
        'device_id': deviceId,
        'requested_app_install_id': appInstallId,
        'requested_display_label': displayLabel,
      },
    );
  }
}
