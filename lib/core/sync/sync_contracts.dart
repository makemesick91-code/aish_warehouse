import 'dart:convert';

const syncOriginalActorUnknownCode = 'sync_original_actor_unknown';
const syncOriginalActorUnknownMessage =
    'Tidak dapat disinkronkan karena akun pembuat data lama tidak dapat ditentukan.';

abstract final class TrustedUploadSizePolicy {
  static const int importAuditMaxBytes = 10 * 1024 * 1024;
  static const int reportArtifactMaxBytes = 20 * 1024 * 1024;
  static const int functionHardCeilingBytes = 20 * 1024 * 1024;

  static int? limitFor({
    required String entityType,
    required String remoteBucket,
  }) => switch ((entityType, remoteBucket)) {
    ('import_audit', 'import-audit') => importAuditMaxBytes,
    ('report_artifact', 'report-artifacts') => reportArtifactMaxBytes,
    _ => null,
  };
}

enum SyncAggregateType {
  branch('branch'),
  room('room'),
  user('user'),
  category('category'),
  item('item'),
  batch('batch'),
  stockLocation('stock_location'),
  stockOpname('stock_opname'),
  purchaseRequest('purchase_request'),
  deliveryOrder('delivery_order'),
  goodReceipt('good_receipt'),
  distribution('distribution'),
  disposal('disposal'),
  consumption('consumption'),
  goodsReturn('goods_return'),
  importAudit('import_audit'),
  exportAudit('export_audit');

  const SyncAggregateType(this.wireValue);
  final String wireValue;
}

enum SyncOperationType {
  upsertMaster('upsert_master'),
  submitOpname('submit_opname'),
  reviewOpname('review_opname'),
  submitPurchaseRequest('submit_purchase_request'),
  processPurchaseRequest('process_purchase_request'),
  rejectPurchaseRequest('reject_purchase_request'),
  cancelPurchaseRequest('cancel_purchase_request'),
  shipDeliveryOrder('ship_delivery_order'),
  postGoodReceipt('post_good_receipt'),
  postDistribution('post_distribution'),
  postDisposal('post_disposal'),
  postConsumption('post_consumption'),
  shipGoodsReturn('ship_goods_return'),
  receiveGoodsReturn('receive_goods_return'),
  appendImportAudit('append_import_audit'),
  appendExportAudit('append_export_audit');

  const SyncOperationType(this.wireValue);
  final String wireValue;
}

extension type const SyncRequestId(String value) {}

abstract interface class SyncPayload {
  Map<String, Object?> toJson();
}

final class JsonSyncPayload implements SyncPayload {
  JsonSyncPayload(Map<String, Object?> value)
    : _value = Map<String, Object?>.unmodifiable(value);

  final Map<String, Object?> _value;

  @override
  Map<String, Object?> toJson() => _value;
}

final class SyncOperationEnvelope {
  const SyncOperationEnvelope({
    required this.requestId,
    required this.deviceId,
    required this.operation,
    required this.aggregateType,
    required this.aggregateId,
    required this.baseServerVersion,
    required this.occurredAtUtc,
    required this.payload,
    this.payloadVersion = 1,
  });

  final SyncRequestId requestId;
  final String deviceId;
  final SyncOperationType operation;
  final SyncAggregateType aggregateType;
  final String aggregateId;
  final int payloadVersion;
  final int baseServerVersion;
  final DateTime occurredAtUtc;
  final SyncPayload payload;

  Map<String, Object?> toJson() => {
    'request_id': requestId.value,
    'device_id': deviceId,
    'operation': operation.wireValue,
    'aggregate_type': aggregateType.wireValue,
    'aggregate_id': aggregateId,
    'payload_version': payloadVersion,
    'base_server_version': baseServerVersion,
    'occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
    'payload': payload.toJson(),
  };

  String encode() => jsonEncode(toJson());
}

sealed class SyncPushResult {
  const SyncPushResult({required this.requestId});
  final SyncRequestId requestId;
}

class SyncAcceptedResult extends SyncPushResult {
  const SyncAcceptedResult({
    required super.requestId,
    required this.serverVersion,
    required this.serverUpdatedAtUtc,
    this.finalDocumentNumber,
    this.movementIds = const [],
  });

  final int serverVersion;
  final DateTime serverUpdatedAtUtc;
  final String? finalDocumentNumber;
  final List<String> movementIds;
}

final class SyncReplayResult extends SyncAcceptedResult {
  const SyncReplayResult({
    required super.requestId,
    required super.serverVersion,
    required super.serverUpdatedAtUtc,
    super.finalDocumentNumber,
    super.movementIds,
  });
}

final class SyncConflictResult extends SyncPushResult {
  const SyncConflictResult({
    required super.requestId,
    required this.code,
    required this.safeMessage,
    required this.baseVersion,
    this.serverVersion,
  });

  final String code;
  final String safeMessage;
  final int baseVersion;
  final int? serverVersion;
}

sealed class SyncPushFailure implements Exception {
  const SyncPushFailure(this.code, this.safeMessage);
  final String code;
  final String safeMessage;
}

final class SyncRetryableFailure extends SyncPushFailure {
  const SyncRetryableFailure(super.code, super.safeMessage, {this.httpStatus});
  final int? httpStatus;
}

final class SyncPermanentFailure extends SyncPushFailure {
  const SyncPermanentFailure(super.code, super.safeMessage);
}

abstract interface class PushSyncGateway {
  Future<SyncPushResult> push(SyncOperationEnvelope envelope);
}

abstract interface class SyncDeviceGateway {
  Future<void> register({
    required String deviceId,
    required String appInstallId,
    String? displayLabel,
  });
}

abstract interface class TrustedFileUploadGateway {
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
  });
}

final class TrustedFileUploadResult {
  const TrustedFileUploadResult({
    required this.remoteObjectId,
    required this.remoteObjectKey,
  });

  final String remoteObjectId;
  final String remoteObjectKey;
}
