import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:flutter_test/flutter_test.dart';

/// How Good Receipt failures reach a clinic user (§35).
///
/// Two properties, and the second is why this file exists at all.
///
/// Every failure carries an **Indonesian sentence written for the person on the other
/// side of the screen**, and `describeFailure` returns it unchanged. Anything else — a
/// database error, a bug — becomes one generic sentence, because a raw exception string
/// tells a branch head nothing and leaks internals.
///
/// And every failure carries the **structured facts** a screen needs to act: which line,
/// how much was shipped, how many days of shelf life are left, which locations were
/// ambiguous. A message alone would force the UI to parse prose.
void main() {
  /// Every Good Receipt failure, with a realistic message.
  List<AppFailure> allFailures() => <AppFailure>[
    const GoodReceiptNotFoundFailure(
      'Good Receipt tidak ditemukan.',
      grId: 'gr-1',
    ),
    const GoodReceiptAlreadyExistsFailure(
      'Surat Jalan ini sudah memiliki Good Receipt.',
      doId: 'do-1',
      grId: 'gr-1',
    ),
    const InvalidGoodReceiptStateFailure(
      'Good Receipt masih dalam pemeriksaan.',
      grId: 'gr-1',
      currentStatus: GoodReceiptStatus.checking,
      attemptedStatus: GoodReceiptStatus.posted,
    ),
    const GoodReceiptAlreadyPostedFailure(
      'Good Receipt sudah diposting, sehingga tidak dapat diubah lagi.',
      grId: 'gr-1',
    ),
    const InvalidDeliveryOrderForReceiptFailure(
      'Surat Jalan masih disiapkan Warehouse dan belum dikirim.',
      doId: 'do-1',
      currentStatus: DeliveryOrderStatus.preparing,
    ),
    const GoodReceiptLineRequiredFailure(
      'Surat Jalan tidak memuat barang, sehingga tidak ada yang dapat '
      'diperiksa.',
      doId: 'do-1',
    ),
    const GoodReceiptLineNotFoundFailure(
      'Baris pemeriksaan tidak ditemukan pada Good Receipt ini.',
      lineId: 'grl-1',
    ),
    const GoodReceiptLinesPendingFailure(
      'Semua barang harus diperiksa sebelum Good Receipt diposting.',
      grId: 'gr-1',
      pendingLineIds: ['grl-1', 'grl-2'],
    ),
    InvalidReceivedQuantityFailure(
      'Jumlah diterima tidak boleh negatif.',
      lineId: 'grl-1',
      received: Quantity.fromMilliUnits(-1),
    ),
    ReceivedQuantityExceedsShippedFailure(
      'Jumlah diterima melebihi jumlah yang dikirim.',
      lineId: 'grl-1',
      shipped: Quantity.parse('2.5'),
      received: Quantity.parse('3'),
    ),
    const GoodReceiptRejectReasonRequiredFailure(
      'Barang yang ditolak wajib disertai alasan penolakan.',
      lineId: 'grl-1',
    ),
    GoodReceiptExpiredBatchMustBeRejectedFailure(
      'Batch B-NEAR sudah kedaluwarsa, sehingga barang ini harus ditolak.',
      lineId: 'grl-1',
      batchId: 'batch-1',
      batchNo: 'B-NEAR',
      expiryDate: DateOnly.of(2026, 7, 20),
    ),
    const GoodReceiptNearExpiryBatchMustBeRejectedFailure(
      'Batch B-NEAR tersisa 12 hari, sehingga barang ini harus ditolak.',
      lineId: 'grl-1',
      batchId: 'batch-1',
      batchNo: 'B-NEAR',
      remainingDays: 12,
      expiryAlertDays: 30,
    ),
    const InvalidGoodReceiptBatchFailure(
      'Batch bukan milik barang ini.',
      itemId: 'item-1',
      batchId: 'batch-1',
    ),
    const GoodReceiptBranchMismatchFailure(
      'Pengiriman ini ditujukan ke cabang lain.',
      actorUserId: 'user-1',
      actorBranchId: 'branch-2',
      documentBranchId: 'branch-1',
    ),
    const GoodReceiptBranchStoreNotFoundFailure(
      'Lokasi Gudang Cabang belum tersedia, sehingga penerimaan tidak dapat '
      'diposting.',
      branchId: 'branch-1',
    ),
    const GoodReceiptBranchStoreAmbiguousFailure(
      'Terdapat lebih dari satu lokasi Gudang Cabang untuk cabang ini.',
      branchId: 'branch-1',
      locationIds: ['loc-1', 'loc-2'],
    ),
    const GoodReceiptLineIntegrityFailure(
      'Daftar barang Good Receipt tidak sama dengan Surat Jalan-nya.',
      grId: 'gr-1',
      missingDoLineIds: ['dol-1'],
      extraDoLineIds: ['dol-9'],
    ),
    const GoodReceiptHistoricalReferenceMissingFailure(
      'Good Receipt tidak dapat diproses karena batch historis tidak '
      'ditemukan.',
      entity: 'item_batches',
      id: 'batch-1',
      grId: 'gr-1',
    ),
    const ConcurrentGoodReceiptUpdateFailure(
      'Good Receipt baru saja diubah dari perangkat lain.',
      grId: 'gr-1',
    ),
  ];

  group('pesan untuk pengguna', () {
    test('setiap kegagalan mengembalikan pesannya sendiri', () {
      for (final failure in allFailures()) {
        expect(
          describeFailure(failure),
          failure.message,
          reason: '${failure.runtimeType} tidak mengembalikan pesannya.',
        );
      }
    });

    test('setiap pesan berbahasa Indonesia dan tidak teknis', () {
      for (final failure in allFailures()) {
        final message = failure.message;

        expect(message.trim(), isNotEmpty);
        // A sentence, not a code: it ends with a full stop and starts with a capital.
        expect(message.endsWith('.'), isTrue, reason: message);
        expect(message[0], message[0].toUpperCase(), reason: message);
        // No identifier, no exception name, no stack trace fragment.
        for (final leak in [
          'Exception',
          'Error:',
          'null',
          '_',
          'gr-1',
          'grl-1',
          'do-1',
          'branch-1',
          'SqliteException',
        ]) {
          expect(
            message.contains(leak),
            isFalse,
            reason: '"$message" membocorkan "$leak".',
          );
        }
      }
    });

    test('kegagalan tak terduga menjadi satu pesan generik', () {
      // A raw exception string or a stack trace tells a branch head nothing and leaks
      // internals.
      expect(
        describeFailure(StateError('boom')),
        'Sesi pengguna tidak tersedia. Muat ulang aplikasi lalu coba lagi.',
      );
      expect(
        describeFailure(FormatException('bad')),
        'Terjadi kesalahan tak terduga. Silakan coba lagi.',
      );
      expect(
        describeFailure(Exception('detail internal')),
        isNot(contains('detail internal')),
      );
    });

    test('pesan fallback dari pemanggil diteruskan', () {
      expect(
        describeFailure('Gagal memposting penerimaan.'),
        'Gagal memposting penerimaan.',
      );
    });
  });

  group('fakta terstruktur', () {
    test('kelebihan kuantitas dihitung eksak', () {
      final failure = ReceivedQuantityExceedsShippedFailure(
        'Jumlah diterima melebihi jumlah yang dikirim.',
        lineId: 'grl-1',
        shipped: Quantity.parse('2.5'),
        received: Quantity.parse('2.501'),
      );

      // Down to the milli-unit, so the UI can say *how much* too many rather than only
      // that the number is wrong.
      expect(failure.excess, Quantity.fromMilliUnits(1));
    });

    test('baris pending disebutkan agar layar dapat menunjuknya', () {
      const failure = GoodReceiptLinesPendingFailure(
        'Semua barang harus diperiksa sebelum Good Receipt diposting.',
        grId: 'gr-1',
        pendingLineIds: ['grl-1', 'grl-2', 'grl-3'],
      );

      expect(failure.pendingCount, 3);
      expect(failure.pendingLineIds, hasLength(3));
    });

    test('kegagalan expiry membawa sisa hari dan ambang', () {
      const failure = GoodReceiptNearExpiryBatchMustBeRejectedFailure(
        'Batch tersisa 12 hari.',
        lineId: 'grl-1',
        batchId: 'batch-1',
        batchNo: 'B-NEAR',
        remainingDays: 12,
        expiryAlertDays: 30,
      );

      expect(failure.remainingDays, lessThan(failure.expiryAlertDays));
      expect(failure.batchNo, 'B-NEAR');
    });

    test('kegagalan expired membawa tanggal sipil apa adanya', () {
      final failure = GoodReceiptExpiredBatchMustBeRejectedFailure(
        'Batch sudah kedaluwarsa.',
        lineId: 'grl-1',
        batchId: 'batch-1',
        batchNo: 'B-OLD',
        expiryDate: DateOnly.of(2026, 7, 20),
      );

      // T-8: a civil date is never timezone converted, so its fields survive verbatim.
      expect(failure.expiryDate, DateTime.utc(2026, 7, 20));
    });

    test('kegagalan Gudang Cabang ambigu menyebut setiap lokasi', () {
      const failure = GoodReceiptBranchStoreAmbiguousFailure(
        'Terdapat lebih dari satu lokasi Gudang Cabang.',
        branchId: 'branch-1',
        locationIds: ['loc-1', 'loc-2'],
      );

      // Refused rather than resolved: an administrator needs to know *which* rows to
      // reconcile.
      expect(failure.locationIds, hasLength(2));
    });

    test('kegagalan integritas menyebut kedua arah perbedaan', () {
      const failure = GoodReceiptLineIntegrityFailure(
        'Daftar barang tidak sama.',
        grId: 'gr-1',
        missingDoLineIds: ['dol-1'],
        extraDoLineIds: ['dol-9', 'dol-8'],
      );

      // Missing means the receipt checks in less than was sent; extra means it claims a
      // position the shipment never carried. They fail in opposite ways.
      expect(failure.missingDoLineIds, hasLength(1));
      expect(failure.extraDoLineIds, hasLength(2));
    });

    test('kegagalan referensi historis menyebut tabel dan id', () {
      const failure = GoodReceiptHistoricalReferenceMissingFailure(
        'Referensi historis tidak ditemukan.',
        entity: 'item_batches',
        id: 'batch-1',
        grId: 'gr-1',
      );

      expect(failure.entity, 'item_batches');
      expect(failure.id, 'batch-1');
      expect(failure.grId, 'gr-1');
    });

    test('kegagalan cabang menyebut kedua cabang', () {
      const failure = GoodReceiptBranchMismatchFailure(
        'Pengiriman ditujukan ke cabang lain.',
        actorUserId: 'user-1',
        actorBranchId: 'branch-2',
        documentBranchId: 'branch-1',
      );

      expect(failure.actorBranchId, isNot(failure.documentBranchId));
    });

    test('setiap kegagalan adalah AppFailure, bukan Exception mentah', () {
      for (final failure in allFailures()) {
        expect(failure, isA<AppFailure>());
      }
    });
  });
}
