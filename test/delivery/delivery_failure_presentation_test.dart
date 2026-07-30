import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:flutter_test/flutter_test.dart';

/// How Delivery Order failures reach a clinic user (§30).
///
/// Two properties, and the second is why this file exists at all.
///
/// Every failure carries an **Indonesian sentence written for the person on the
/// other side of the screen**, and `describeFailure` returns it unchanged. Anything
/// else — a database error, a bug — becomes one generic sentence, because a raw
/// exception string tells a warehouse officer nothing and leaks internals.
///
/// And every failure carries the **structured facts** a screen needs to act: which
/// batch, how much remains, how many days are left. A message alone would force the
/// UI to parse prose.
void main() {
  group('pesan untuk pengguna', () {
    test('setiap kegagalan Delivery mengembalikan pesannya sendiri', () {
      final failures = <AppFailure>[
        const DeliveryOrderNotFoundFailure(
          'Surat Jalan tidak ditemukan.',
          doId: 'do-1',
        ),
        const DeliveryOrderLineNotFoundFailure(
          'Baris Surat Jalan tidak ditemukan.',
          lineId: 'dol-1',
        ),
        const InvalidDeliveryOrderStateFailure(
          'Surat Jalan sudah diterima cabang dan bersifat final.',
          doId: 'do-1',
          currentStatus: DeliveryOrderStatus.received,
        ),
        const DeliveryOrderAlreadyShippedFailure(
          'Surat Jalan sudah dikirim, sehingga tidak dapat diubah lagi.',
          doId: 'do-1',
        ),
        const InvalidPurchaseRequestForDeliveryFailure(
          'Purchase Request sudah dibatalkan cabang.',
          prId: 'pr-1',
          currentStatus: PurchaseRequestStatus.cancelled,
        ),
        const DeliveryOrderLineRequiredFailure(
          'Surat Jalan belum memiliki barang untuk dikirim.',
          doId: 'do-1',
        ),
        const DeliveryItemNotInPurchaseRequestFailure(
          'Barang pada baris Surat Jalan tidak sama dengan barang yang diminta '
          'cabang.',
          doId: 'do-1',
          itemId: 'item-1',
        ),
        const DeliveryPrLineMismatchFailure(
          'Surat Jalan memuat baris yang bukan milik Purchase Request ini.',
          doId: 'do-1',
          prLineId: 'prl-1',
        ),
        const DuplicateDeliveryAllocationFailure(
          'Batch yang sama dialokasikan dua kali.',
          doId: 'do-1',
          prLineId: 'prl-1',
        ),
        DeliveryQuantityExceedsRequestedFailure(
          'Jumlah kirim melebihi permintaan cabang.',
          prLineId: 'prl-1',
          requested: Quantity.parse('3'),
          alreadyShipped: Quantity.parse('2'),
          attempted: Quantity.parse('2'),
        ),
        InsufficientWarehouseStockFailure(
          'Saldo warehouse tidak mencukupi.',
          itemId: 'item-1',
          available: Quantity.parse('1'),
          requested: Quantity.parse('2'),
        ),
        const WarehouseLocationNotFoundFailure(
          'Lokasi Warehouse Pusat belum tersedia.',
        ),
        const AmbiguousWarehouseLocationFailure(
          'Terdapat lebih dari satu lokasi Warehouse Pusat.',
          locationIds: ['wh-1', 'wh-2'],
        ),
        ExpiredBatchForDeliveryFailure(
          'Batch B-EXP sudah kedaluwarsa dan tidak dapat dikirim.',
          batchId: 'batch-1',
          batchNo: 'B-EXP',
          expiryDate: DateOnly.of(2026, 7, 1),
        ),
        const NearExpiryConfirmationRequiredFailure(
          'Batch B-NEAR tersisa 12 hari dan memerlukan konfirmasi eksplisit.',
          batchId: 'batch-1',
          batchNo: 'B-NEAR',
          remainingDays: 12,
          expiryAlertDays: 30,
        ),
        const FefoOverrideReasonRequiredFailure(
          'Isi alasan penggantian batch (FEFO) terlebih dahulu.',
          batchId: 'batch-1',
          batchNo: 'C-SAFE',
          skippedBatchNo: 'B-NEAR',
        ),
        const InvalidDeliveryBatchFailure(
          'Batch bukan milik barang tersebut.',
          itemId: 'item-1',
        ),
        const ConcurrentDeliveryOrderUpdateFailure(
          'Surat Jalan baru saja diubah dari perangkat lain.',
          doId: 'do-1',
        ),
        const HistoricalDeliveryReferenceMissingFailure(
          'Surat Jalan tidak dapat diproses karena batch historis tidak '
          'ditemukan.',
          entity: 'item_batches',
          id: 'batch-1',
          doId: 'do-1',
        ),
      ];

      for (final failure in failures) {
        final message = describeFailure(failure);
        expect(message, failure.message);
        // Written for a clinic user, not for a log: no identifiers, no class names,
        // no English.
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('Failure')));
        expect(message, isNot(contains('null')));
        expect(
          message.endsWith('.') || message.endsWith('?'),
          isTrue,
          reason: 'Pesan harus berupa kalimat: "$message"',
        );
      }
    });

    test('kesalahan tak terduga tidak membocorkan internal', () {
      // A driver error or a bug becomes one generic sentence — a raw exception
      // string tells a warehouse officer nothing and leaks internals.
      expect(
        describeFailure(Exception('SqliteException(19): UNIQUE constraint')),
        'Terjadi kesalahan tak terduga. Silakan coba lagi.',
      );
      expect(
        describeFailure(StateError('Tidak ada sesi pengguna aktif.')),
        contains('Sesi pengguna tidak tersedia'),
      );
      // And a caller-supplied fallback survives, so a screen can name the action
      // that failed.
      expect(
        describeFailure('Gagal mengirim Surat Jalan.'),
        'Gagal mengirim Surat Jalan.',
      );
    });
  });

  group('fakta terstruktur untuk UI', () {
    test('kelebihan kirim membawa sisa yang dapat ditampilkan', () {
      final failure = DeliveryQuantityExceedsRequestedFailure(
        'Jumlah kirim melebihi permintaan cabang.',
        prLineId: 'prl-1',
        requested: Quantity.parse('3'),
        alreadyShipped: Quantity.parse('2.5'),
        attempted: Quantity.parse('1'),
      );

      // Exact fixed point, so the sentence the UI builds from it is exact too.
      expect(failure.remaining, Quantity.parse('0.5'));
      expect(failure.remaining.format(), '0.5');
    });

    test('near-expiry membawa sisa hari dan ambang', () {
      const failure = NearExpiryConfirmationRequiredFailure(
        'Batch memerlukan konfirmasi.',
        batchId: 'batch-1',
        batchNo: 'B-NEAR',
        remainingDays: 12,
        expiryAlertDays: 30,
      );

      expect(failure.remainingDays, 12);
      expect(failure.expiryAlertDays, 30);
      expect(failure.batchNo, 'B-NEAR');
    });

    test('override FEFO menamai batch yang dilewati', () {
      const failure = FefoOverrideReasonRequiredFailure(
        'Isi alasan penggantian batch.',
        batchId: 'batch-safe',
        batchNo: 'C-SAFE',
        skippedBatchNo: 'B-NEAR',
      );

      // The one fact that makes the warning actionable: which batch should have been
      // taken instead.
      expect(failure.skippedBatchNo, 'B-NEAR');
      expect(failure.batchNo, 'C-SAFE');
    });

    test('batch kedaluwarsa membawa tanggal sebagai civil date', () {
      final failure = ExpiredBatchForDeliveryFailure(
        'Batch sudah kedaluwarsa.',
        batchId: 'batch-1',
        batchNo: 'B-EXP',
        expiryDate: DateOnly.of(2026, 7, 1),
      );

      // T-8: a civil date, so the UI prints it verbatim without a conversion.
      expect(DateOnly.formatIso(failure.expiryDate), '2026-07-01');
    });

    test('warehouse ambigu menamai lokasi yang bertabrakan', () {
      const failure = AmbiguousWarehouseLocationFailure(
        'Terdapat lebih dari satu lokasi Warehouse Pusat.',
        locationIds: ['wh-1', 'wh-2'],
      );

      // An administrator has to be able to find them; the user-facing sentence
      // deliberately does not print ids.
      expect(failure.locationIds, hasLength(2));
      expect(failure.message, isNot(contains('wh-1')));
    });

    test('kegagalan historis menamai tabel dan id untuk administrator', () {
      const failure = HistoricalDeliveryReferenceMissingFailure(
        'Surat Jalan tidak dapat diproses karena batch historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'item_batches',
        id: 'batch-1',
        doId: 'do-1',
      );

      expect(failure.entity, 'item_batches');
      expect(failure.id, 'batch-1');
      expect(failure.doId, 'do-1');
      // The user is told to contact an administrator rather than shown the row.
      expect(failure.message, contains('Hubungi administrator'));
      expect(failure.message, isNot(contains('item_batches')));
    });

    test('status dokumen tersedia untuk memilih affordance', () {
      const failure = InvalidDeliveryOrderStateFailure(
        'Surat Jalan sudah diterima cabang.',
        doId: 'do-1',
        currentStatus: DeliveryOrderStatus.received,
        attemptedStatus: DeliveryOrderStatus.shipped,
      );

      expect(failure.currentStatus.isFinal, isTrue);
      expect(failure.attemptedStatus, DeliveryOrderStatus.shipped);
    });
  });
}
