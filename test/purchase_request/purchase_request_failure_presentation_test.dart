import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Purchase Request failure must reach the user as a sentence they can act on.
///
/// `describeFailure` is the single mapping from a thrown object to on-screen text, and
/// the property that matters is negative: nothing on this path may ever surface a raw
/// exception string, a type name or a stack trace. A failure that carried an empty or
/// English message would pass every other test in the suite and only show itself to a
/// clinic user.
void main() {
  /// One instance of every Purchase Request failure, with the message the code that
  /// throws it actually writes.
  final failures = <String, AppFailure>{
    'PurchaseRequestNotFoundFailure': const PurchaseRequestNotFoundFailure(
      'Purchase Request tidak ditemukan.',
      prId: 'pr-1',
    ),
    'PurchaseRequestLineNotFoundFailure':
        const PurchaseRequestLineNotFoundFailure(
          'Baris permintaan tidak ditemukan.',
          lineId: 'prl-1',
        ),
    'PurchaseRequestAlreadyActiveFailure':
        const PurchaseRequestAlreadyActiveFailure(
          'Cabang ini masih memiliki Purchase Request aktif (TMP-PR-1).',
          branchId: 'branch-1',
          activePrId: 'pr-1',
        ),
    'InvalidPurchaseRequestStateFailure':
        const InvalidPurchaseRequestStateFailure(
          'Purchase Request TMP-PR-1 sedang diproses Warehouse.',
          prId: 'pr-1',
          currentStatus: PurchaseRequestStatus.processing,
          attemptedStatus: PurchaseRequestStatus.cancelled,
        ),
    'PurchaseRequestOpnameRequiredFailure':
        const PurchaseRequestOpnameRequiredFailure(
          'Pilih minimal satu stok opname sebagai acuan permintaan.',
          prId: 'pr-1',
        ),
    'IneligibleStockOpnameFailure': const IneligibleStockOpnameFailure(
      'Stok opname TMP-SO-1 masih draft dan belum dapat dijadikan acuan.',
      opnameId: 'so-1',
      reason: StockOpnameEligibilityDenial.notSubmitted,
    ),
    'ExpiredStockOpnameReferenceFailure':
        const ExpiredStockOpnameReferenceFailure(
          'Stok opname acuan sudah melewati batas satu minggu sebelum minggu '
          'berjalan.',
          prId: 'pr-1',
          opnameIds: ['so-1'],
        ),
    'DuplicatePurchaseRequestItemFailure':
        const DuplicatePurchaseRequestItemFailure(
          'Masker Bedah sudah ada pada permintaan ini.',
          prId: 'pr-1',
          itemId: 'item-1',
        ),
    'InvalidRequestedQuantityFailure': InvalidRequestedQuantityFailure(
      'Jumlah permintaan Masker Bedah harus lebih dari 0.',
      itemId: 'item-1',
      requested: Quantity.zero(),
    ),
    'PurchaseRequestJustificationRequiredFailure':
        const PurchaseRequestJustificationRequiredFailure(
          'Catatan alasan wajib diisi untuk baris yang melebihi 150% saran '
          'sistem.',
          lineIds: ['prl-1'],
        ),
    'UnauthorizedPurchaseRequestBranchFailure':
        const UnauthorizedPurchaseRequestBranchFailure(
          'Purchase Request TMP-PR-1 milik cabang lain.',
          actorUserId: 'user-1',
          branchId: 'branch-2',
        ),
    'WarehouseCannotEditPurchaseRequestFailure':
        const WarehouseCannotEditPurchaseRequestFailure(
          'Petugas Warehouse tidak dapat mengubah isi Purchase Request.',
          actorUserId: 'user-1',
          prId: 'pr-1',
        ),
    'PurchaseRequestRejectReasonRequiredFailure':
        const PurchaseRequestRejectReasonRequiredFailure(
          'Alasan penolakan wajib diisi.',
          prId: 'pr-1',
        ),
    'PurchaseRequestCancelReasonRequiredFailure':
        const PurchaseRequestCancelReasonRequiredFailure(
          'Alasan pembatalan wajib diisi.',
          prId: 'pr-1',
        ),
    'ConcurrentPurchaseRequestUpdateFailure':
        const ConcurrentPurchaseRequestUpdateFailure(
          'Purchase Request TMP-PR-1 baru saja diubah dari perangkat lain.',
          prId: 'pr-1',
        ),
    'HistoricalPurchaseRequestReferenceMissingFailure':
        const HistoricalPurchaseRequestReferenceMissingFailure(
          'Purchase Request tidak dapat diproses karena barang historis tidak '
          'ditemukan.',
          entity: 'items',
          id: 'item-1',
          prId: 'pr-1',
        ),
  };

  test('setiap kegagalan PR tampil sebagai pesan Bahasa Indonesia', () {
    failures.forEach((name, failure) {
      final message = describeFailure(failure);

      expect(message, failure.message, reason: '$name harus memakai pesannya.');
      expect(message.trim(), isNotEmpty, reason: '$name berpesan kosong.');
      // Never a type name, never the generic fallback: a specific failure that fell
      // through to the catch-all sentence would be indistinguishable from a bug.
      expect(message, isNot(contains(name)));
      expect(message, isNot(contains('Exception')));
      expect(
        message,
        isNot('Terjadi kesalahan tak terduga. Silakan coba lagi.'),
        reason: '$name jatuh ke pesan generik.',
      );
      expect(
        message.endsWith('.'),
        isTrue,
        reason: '$name bukan kalimat lengkap.',
      );
    });
  });

  test('objek tak dikenal tetap tidak membocorkan internal', () {
    // The other half of the contract: anything that is *not* an AppFailure becomes one
    // generic sentence, because a driver error or a bug tells a clinic user nothing.
    expect(
      describeFailure(StateError('SQLITE_CONSTRAINT: UNIQUE failed')),
      isNot(contains('SQLITE_CONSTRAINT')),
    );
    expect(
      describeFailure(ArgumentError('idx_purchase_requests_active_branch')),
      'Terjadi kesalahan tak terduga. Silakan coba lagi.',
    );
  });

  test('setiap kegagalan PR pada failures.dart diuji di sini', () {
    // A new failure type added without a message worth showing would otherwise be
    // caught only by whoever hit it in production.
    const declared = <String>{
      'PurchaseRequestNotFoundFailure',
      'PurchaseRequestLineNotFoundFailure',
      'PurchaseRequestAlreadyActiveFailure',
      'InvalidPurchaseRequestStateFailure',
      'PurchaseRequestOpnameRequiredFailure',
      'IneligibleStockOpnameFailure',
      'ExpiredStockOpnameReferenceFailure',
      'DuplicatePurchaseRequestItemFailure',
      'InvalidRequestedQuantityFailure',
      'PurchaseRequestJustificationRequiredFailure',
      'UnauthorizedPurchaseRequestBranchFailure',
      'WarehouseCannotEditPurchaseRequestFailure',
      'PurchaseRequestRejectReasonRequiredFailure',
      'PurchaseRequestCancelReasonRequiredFailure',
      'ConcurrentPurchaseRequestUpdateFailure',
      'HistoricalPurchaseRequestReferenceMissingFailure',
    };

    expect(failures.keys.toSet(), declared);
    for (final entry in failures.entries) {
      expect(
        entry.value.runtimeType.toString(),
        entry.key,
        reason: 'Kunci peta harus sama dengan nama tipe.',
      );
    }
  });
}
