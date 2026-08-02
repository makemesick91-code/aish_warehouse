import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/sync_contracts.dart';

final class SupabaseTrustedFileUploadGateway
    implements TrustedFileUploadGateway {
  const SupabaseTrustedFileUploadGateway(this.client);

  final SupabaseClient client;

  @override
  Future<TrustedFileUploadResult> upload({
    required String requestId,
    required String entityType,
    required String entityId,
    required String localFilePath,
    required String originalFileName,
    required String sha256,
    required int sizeBytes,
    required String mimeType,
    required String remoteBucket,
  }) async {
    final policyLimit = TrustedUploadSizePolicy.limitFor(
      entityType: entityType,
      remoteBucket: remoteBucket,
    );
    if (policyLimit == null ||
        sizeBytes <= 0 ||
        sizeBytes > policyLimit ||
        sizeBytes > TrustedUploadSizePolicy.functionHardCeilingBytes) {
      throw const SyncPermanentFailure(
        'sync_upload_too_large',
        'Ukuran file melebihi batas unggah.',
      );
    }
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw const SyncPermanentFailure(
        'sync_upload_object_missing',
        'File lokal tidak ditemukan lagi.',
      );
    }
    final actualSize = await file.length();
    if (actualSize > policyLimit ||
        actualSize > TrustedUploadSizePolicy.functionHardCeilingBytes) {
      throw const SyncPermanentFailure(
        'sync_upload_too_large',
        'Ukuran file melebihi batas unggah.',
      );
    }
    if (actualSize != sizeBytes) {
      throw const SyncPermanentFailure(
        'sync_upload_size_mismatch',
        'Ukuran file lokal sudah berubah.',
      );
    }

    try {
      final intentResponse = await client.functions.invoke(
        'trusted-upload-intent',
        body: {
          'entity_type': entityType,
          'entity_id': entityId,
          'original_file_name': originalFileName,
          'expected_sha256': sha256,
          'expected_size_bytes': sizeBytes,
          'mime_type': mimeType,
          'request_id': requestId,
        },
      );
      final intent = Map<String, dynamic>.from(intentResponse.data as Map);
      final intentId = intent['intent_id'] as String;
      final bucket = intent['bucket_id'] as String;
      final objectKey = intent['object_key'] as String;
      if (bucket != remoteBucket) {
        throw const SyncPermanentFailure(
          'sync_upload_not_authorized',
          'Tujuan unggah tidak sesuai.',
        );
      }
      if (intent['already_finalized'] == true) {
        return TrustedFileUploadResult(
          remoteObjectId: intent['object_id'] as String,
          remoteObjectKey: objectKey,
        );
      }
      final token = intent['token'] as String;

      await client.storage
          .from(bucket)
          .uploadToSignedUrl(
            objectKey,
            token,
            file,
            FileOptions(contentType: mimeType, upsert: false),
          );

      final finalized = await client.functions.invoke(
        'trusted-upload-finalize',
        body: {'intent_id': intentId},
      );
      final result = Map<String, dynamic>.from(finalized.data as Map);
      return TrustedFileUploadResult(
        remoteObjectId: result['object_id'] as String,
        remoteObjectKey: objectKey,
      );
    } on SyncPushFailure {
      rethrow;
    } on TimeoutException {
      throw const SyncRetryableFailure(
        'sync_retry_later',
        'Unggahan tertunda dan akan dicoba lagi.',
      );
    } on FunctionException catch (error) {
      final code = _functionCode(error);
      if (error.status == 429 ||
          error.status >= 500 ||
          code == 'sync_retry_later' ||
          code == 'sync_upload_expired') {
        throw SyncRetryableFailure(code, _safeMessage(code));
      }
      throw SyncPermanentFailure(code, _safeMessage(code));
    } on StorageException catch (error) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status == 429 || (status != null && status >= 500)) {
        throw const SyncRetryableFailure(
          'sync_retry_later',
          'Unggahan tertunda dan akan dicoba lagi.',
        );
      }
      throw const SyncPermanentFailure(
        'sync_upload_not_authorized',
        'Unggahan tidak diizinkan.',
      );
    } on FileSystemException {
      throw const SyncPermanentFailure(
        'sync_upload_object_missing',
        'File lokal tidak dapat dibaca.',
      );
    }
  }

  static String _functionCode(FunctionException error) {
    final details = error.details;
    if (details is Map && details['code'] is String) {
      return details['code'] as String;
    }
    return error.status == 401 ? 'sync_auth_required' : 'sync_invalid_payload';
  }

  static String _safeMessage(String code) => switch (code) {
    'sync_upload_expired' => 'Izin unggah kedaluwarsa. Akan dibuat ulang.',
    'sync_upload_hash_mismatch' => 'Isi file tidak cocok dengan audit lokal.',
    'sync_upload_size_mismatch' =>
      'Ukuran file tidak cocok dengan audit lokal.',
    'sync_upload_object_missing' => 'File unggahan belum ditemukan server.',
    'sync_upload_too_large' => 'Ukuran file melebihi batas unggah.',
    'sync_auth_required' => 'Sesi berakhir. Silakan masuk kembali.',
    _ => 'Upload tidak dapat diproses.',
  };
}
