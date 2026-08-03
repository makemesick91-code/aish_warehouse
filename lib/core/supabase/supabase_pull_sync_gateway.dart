import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/pull_sync_contracts.dart';

/// Calls the authenticated pull RPC and maps every failure onto a stable code.
///
/// No server string reaches the caller. A Postgres message, a constraint name or
/// a function signature would all be true and all be a leak, and the codes below
/// are the same vocabulary the push gateway already established.
final class SupabasePullSyncGateway implements PullSyncGateway {
  const SupabasePullSyncGateway(this.client);
  final SupabaseClient client;

  @override
  Future<RemoteChangeBatch> pull({
    required int cursor,
    required int limit,
    required String deviceId,
    List<String>? entityTypes,
  }) async {
    try {
      final raw = await client.rpc(
        'pull_sync_changes',
        params: {
          'after_cursor': cursor,
          'batch_limit': limit,
          'device_id': deviceId,
          'entity_types': ?entityTypes,
        },
      );
      if (raw is! Map) {
        throw const PullSyncPermanentFailure(
          PullSyncErrorCodes.invalidPayload,
          'Data server tidak dapat dibaca.',
        );
      }
      return RemoteChangeBatch.fromJson(Map<String, Object?>.from(raw));
    } on TimeoutException {
      throw const PullSyncRetryableFailure(
        PullSyncErrorCodes.retryLater,
        'Server belum dapat dihubungi. Akan dicoba lagi.',
      );
    } on SocketException {
      throw const PullSyncRetryableFailure(
        PullSyncErrorCodes.retryLater,
        'Server belum dapat dihubungi. Akan dicoba lagi.',
      );
    } on PostgrestException catch (error) {
      final code = _stableCode(error);
      if (code == PullSyncErrorCodes.cursorInvalid) {
        throw const PullSyncCursorResetRequired();
      }
      if (code == PullSyncErrorCodes.retryLater ||
          error.code == '429' ||
          (error.code?.startsWith('5') ?? false)) {
        throw PullSyncRetryableFailure(
          code,
          PullSyncErrorCodes.messageFor(code),
        );
      }
      throw PullSyncPermanentFailure(code, PullSyncErrorCodes.messageFor(code));
    }
  }

  static String _stableCode(PostgrestException error) {
    if (PullSyncErrorCodes.all.contains(error.message)) return error.message;
    final details = error.details;
    if (details is Map && details['code'] is String) {
      final code = details['code'] as String;
      if (PullSyncErrorCodes.all.contains(code)) return code;
    }
    return switch (error.code) {
      '42501' => PullSyncErrorCodes.accessDenied,
      'PGRST301' => PullSyncErrorCodes.authRequired,
      _ => PullSyncErrorCodes.invalidPayload,
    };
  }
}
