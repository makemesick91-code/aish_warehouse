import 'package:aish_warehouse/core/sync/sync_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'trusted upload caps are independent and bounded by Function ceiling',
    () {
      expect(TrustedUploadSizePolicy.importAuditMaxBytes, 10 * 1024 * 1024);
      expect(TrustedUploadSizePolicy.reportArtifactMaxBytes, 20 * 1024 * 1024);
      expect(
        TrustedUploadSizePolicy.functionHardCeilingBytes,
        20 * 1024 * 1024,
      );
      expect(
        TrustedUploadSizePolicy.limitFor(
          entityType: 'import_audit',
          remoteBucket: 'import-audit',
        ),
        TrustedUploadSizePolicy.importAuditMaxBytes,
      );
      expect(
        TrustedUploadSizePolicy.limitFor(
          entityType: 'report_artifact',
          remoteBucket: 'report-artifacts',
        ),
        TrustedUploadSizePolicy.reportArtifactMaxBytes,
      );
      expect(
        TrustedUploadSizePolicy.limitFor(
          entityType: 'import_audit',
          remoteBucket: 'report-artifacts',
        ),
        isNull,
      );
    },
  );
}
