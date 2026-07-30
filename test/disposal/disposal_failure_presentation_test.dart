import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/disposal/domain/services/disposal_reason_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a Pemusnahan failure says to the person on the other side of the screen
/// (§35).
///
/// Two rules, and both are about the same thing — a refusal is only useful if it can
/// be acted on:
///
/// * every failure carries an Indonesian sentence, never a type name, never a stack
///   trace, never a raw driver error;
/// * the sentences that refuse a *scope* deliberately say less than they know, so a
///   refusal cannot be used to work out what exists elsewhere.
void main() {
  /// Every Pemusnahan failure, constructed the way the guards construct them.
  final failures = <String, AppFailure>{
    'notFound': const DisposalNotFoundFailure(
      'Pemusnahan tidak ditemukan.',
      disposalId: 'd1',
    ),
    'invalidState': const InvalidDisposalStateFailure(
      'Pemusnahan TMP-DSP-1 masih draft.',
      disposalId: 'd1',
      currentStatus: DisposalStatus.draft,
    ),
    'alreadyPosted': const DisposalAlreadyPostedFailure(
      'Pemusnahan TMP-DSP-1 sudah diposting, sehingga tidak dapat diubah lagi.',
      disposalId: 'd1',
    ),
    'lineRequired': const DisposalLineRequiredFailure(
      'Pemusnahan TMP-DSP-1 belum memuat barang, sehingga tidak dapat diposting.',
      disposalId: 'd1',
    ),
    'lineNotFound': const DisposalLineNotFoundFailure(
      'Baris pemusnahan tidak ditemukan pada dokumen ini.',
      lineId: 'l1',
    ),
    'reasonRequired': const DisposalReasonRequiredFailure(
      'Catatan pemusnahan wajib diisi sebelum dokumen dapat diposting.',
      disposalId: 'd1',
    ),
    'sourceNotFound': const DisposalSourceLocationNotFoundFailure(
      'Lokasi sumber tidak ditemukan.',
      locationId: 'loc1',
    ),
    'sourceInactive': const DisposalSourceLocationInactiveFailure(
      'Lokasi "Ruang Dental 2" sudah tidak aktif, sehingga tidak dapat dipakai '
      'untuk pemusnahan baru.',
      locationId: 'loc1',
    ),
    'accessDenied': const DisposalSourceLocationAccessDeniedFailure(
      'Anda tidak berwenang memusnahkan stok dari lokasi ini.',
      actorUserId: 'u1',
      locationId: 'loc1',
    ),
    'branchMismatch': const DisposalBranchMismatchFailure(
      'Lokasi ini bukan milik cabang Anda, sehingga stoknya tidak dapat '
      'dimusnahkan dari akun ini.',
      actorUserId: 'u1',
      locationId: 'loc1',
    ),
    'roomMismatch': const DisposalRoomMismatchFailure(
      'Lokasi stok ini tidak valid untuk pemusnahan. Hubungi administrator.',
      locationId: 'loc1',
    ),
    'mustHaveExpiry': const DisposalItemMustHaveExpiryFailure(
      'Barang DSP-0003 tidak dilacak per batch, sehingga tidak dapat dimusnahkan '
      'melalui dokumen ini.',
      itemId: 'i1',
    ),
    'batchRequired': const DisposalBatchRequiredFailure(
      'Batch wajib dipilih untuk pemusnahan.',
      itemId: 'i1',
    ),
    'invalidBatch': const InvalidDisposalBatchFailure(
      'Batch B-1 bukan milik barang DSP-0001.',
      itemId: 'i1',
      batchId: 'b1',
    ),
    'notExpired': DisposalTestFailures.notExpired,
    'invalidQty': InvalidDisposalQuantityFailure(
      'Jumlah pemusnahan harus lebih besar dari 0 (diterima 0).',
      qty: Quantity.zero(),
    ),
    'insufficient': InvalidDisposalStock.failure,
    'duplicate': const DuplicateDisposalLineFailure(
      'Batch ini sudah ada pada dokumen pemusnahan ini. Ubah jumlah baris yang '
      'ada, bukan menambah baris baru.',
      disposalId: 'd1',
      itemId: 'i1',
      batchId: 'b1',
    ),
    'integrity': const DisposalLineIntegrityFailure(
      'Daftar barang pemusnahan tidak dapat dimuat sepenuhnya, sehingga posting '
      'dibatalkan. Hubungi administrator.',
      disposalId: 'd1',
    ),
    'historical': const HistoricalDisposalReferenceMissingFailure(
      'Pemusnahan tidak dapat diproses karena batch historis tidak ditemukan. '
      'Hubungi administrator.',
      entity: 'item_batches',
      id: 'b1',
      disposalId: 'd1',
    ),
    'concurrent': const ConcurrentDisposalUpdateFailure(
      'Pemusnahan TMP-DSP-1 baru saja diubah dari perangkat lain. Muat ulang '
      'halaman lalu coba lagi.',
      disposalId: 'd1',
    ),
    'timestamp': DisposalTestFailures.timestamp,
  };

  group('presentasi', () {
    test('setiap kegagalan memiliki kalimat, bukan nama tipe', () {
      for (final entry in failures.entries) {
        final message = describeFailure(entry.value);
        expect(message, isNotEmpty, reason: '${entry.key} tanpa pesan.');
        expect(
          message.contains('Failure'),
          isFalse,
          reason: '${entry.key} membocorkan nama tipe: $message',
        );
        expect(
          message.contains('Exception'),
          isFalse,
          reason: '${entry.key} membocorkan nama tipe: $message',
        );
        expect(
          message.contains('#0'),
          isFalse,
          reason: '${entry.key} membocorkan stack trace.',
        );
      }
    });

    test('setiap kegagalan diakhiri tanda baca dan berbahasa Indonesia', () {
      for (final entry in failures.entries) {
        final message = describeFailure(entry.value);
        expect(
          message.endsWith('.'),
          isTrue,
          reason: '${entry.key} tidak diakhiri titik: $message',
        );
        // A crude but effective screen for accidentally shipping an English string.
        for (final english in const [
          ' the ',
          ' cannot ',
          ' must ',
          ' is not ',
        ]) {
          expect(
            message.toLowerCase().contains(english),
            isFalse,
            reason: '${entry.key} tampak berbahasa Inggris: $message',
          );
        }
      }
    });

    test('penolakan cakupan tidak menyebut cabang atau lokasi lain', () {
      // Telling "another branch's room" apart from "no such location" would let the
      // location table be probed from the address bar.
      for (final key in const [
        'accessDenied',
        'branchMismatch',
        'sourceNotFound',
      ]) {
        final message = describeFailure(failures[key]!);
        for (final leak in const ['Cabang Lain', 'Warehouse Pusat', 'loc1']) {
          expect(
            message.contains(leak),
            isFalse,
            reason: '$key membocorkan $leak.',
          );
        }
      }
    });

    test('penolakan kedaluwarsa menyebut batch dan tanggalnya', () {
      // The one fact that makes the refusal actionable: which batch, and until when.
      final message = describeFailure(failures['notExpired']!);
      expect(message, contains('B-1'));
      expect(message, contains('2026-08-30'));
      expect(message, contains('belum kedaluwarsa'));
    });

    test('penolakan stok menyebut jumlah tersedia dan diminta', () {
      final message = describeFailure(failures['insufficient']!);
      expect(message, contains('1.5'));
      expect(message, contains('3'));
    });

    test('objek tak dikenal menjadi satu kalimat generik', () {
      // A raw driver error tells a clinic user nothing and leaks internals.
      expect(
        describeFailure(StateError('sqlite3 error 275')),
        isNot(contains('sqlite3')),
      );
      expect(
        describeFailure(Exception('UNIQUE constraint failed')),
        'Terjadi kesalahan tak terduga. Silakan coba lagi.',
      );
    });
  });

  group('kebijakan alasan (§19)', () {
    test('preset menghasilkan label yang dapat dibaca, bukan kode', () {
      expect(
        DisposalReasonPolicy.compose(presetCode: 'expired'),
        'Kedaluwarsa',
      );
      expect(
        DisposalReasonPolicy.compose(presetCode: 'cleanup'),
        'Pembersihan stok lama',
      );
      // What would be stored if the code leaked instead of the label.
      expect(
        DisposalReasonPolicy.compose(presetCode: 'cleanup'),
        isNot(contains('cleanup')),
      );
    });

    test('preset dengan detail digabung menjadi satu kalimat audit', () {
      expect(
        DisposalReasonPolicy.compose(
          presetCode: 'cleanup',
          detail: 'Ditemukan saat audit bulanan',
        ),
        'Pembersihan stok lama — Ditemukan saat audit bulanan',
      );
    });

    test('Lainnya tanpa detail ditolak', () {
      // A stored reason of the literal word "Lainnya" explains nothing to the person
      // reading the ledger a year later — the reader G-E7 is written for.
      expect(DisposalReasonPolicy.compose(presetCode: 'other'), isNull);
      expect(
        DisposalReasonPolicy.compose(presetCode: 'other', detail: '   '),
        isNull,
      );
      expect(
        DisposalReasonPolicy.compose(
          presetCode: 'other',
          detail: 'Recall dari distributor',
        ),
        'Lainnya — Recall dari distributor',
      );
    });

    test('tanpa preset, teks bebas menjadi seluruh alasan', () {
      expect(
        DisposalReasonPolicy.compose(detail: 'Rusak saat penyimpanan'),
        'Rusak saat penyimpanan',
      );
      expect(DisposalReasonPolicy.compose(detail: '  '), isNull);
      expect(DisposalReasonPolicy.compose(), isNull);
    });

    test('whitespace bukan alasan, termasuk tab dan baris baru', () {
      // SQLite's `trim()` strips spaces only; `String.trim()` strips these too. The
      // domain is the authority, the CHECK is the floor.
      for (final blank in const ['', '   ', '\n', '\t', ' \n\t ']) {
        expect(
          DisposalReasonPolicy.isValid(blank),
          isFalse,
          reason: '"$blank" diterima sebagai alasan.',
        );
        expect(DisposalReasonPolicy.normalize(blank), isNull);
      }
    });

    test('catatan movement deterministik', () {
      expect(
        DisposalReasonPolicy.movementNote(reason: 'Kedaluwarsa'),
        'Kedaluwarsa',
      );
      expect(
        DisposalReasonPolicy.movementNote(
          reason: 'Kedaluwarsa',
          lineNote: 'Kemasan bocor',
        ),
        'Kedaluwarsa — Kemasan bocor',
      );
      // A blank line note adds nothing rather than a trailing separator.
      expect(
        DisposalReasonPolicy.movementNote(
          reason: 'Kedaluwarsa',
          lineNote: '   ',
        ),
        'Kedaluwarsa',
      );
    });

    test('catatan movement menolak alasan kosong daripada mengarang kalimat', () {
      // A caller that has not checked is a caller that would write an unexplained
      // movement, so this throws rather than inventing a fallback.
      expect(
        () => DisposalReasonPolicy.movementNote(reason: '  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('setiap preset memiliki label yang berbeda', () {
      final labels = DisposalReasonPolicy.presets
          .map((preset) => preset.label)
          .toSet();
      expect(labels, hasLength(DisposalReasonPolicy.presets.length));
      // Exactly one preset says too little on its own.
      expect(
        DisposalReasonPolicy.presets
            .where((preset) => preset.requiresDetail)
            .map((preset) => preset.code),
        ['other'],
      );
    });
  });
}

/// Failures whose constructors need non-const values, kept out of the map literal so
/// it stays readable.
abstract final class DisposalTestFailures {
  static final notExpired = BatchNotExpiredForDisposalFailure(
    'Batch B-1 belum kedaluwarsa (ED 2026-08-30), sehingga tidak dapat '
    'dimusnahkan. Hanya barang yang sudah melewati tanggal kedaluwarsa yang '
    'boleh dimusnahkan.',
    batchId: 'b1',
    batchNo: 'B-1',
    expiryDate: DateTime.utc(2026, 8, 30),
  );

  static final timestamp = InvalidDisposalTimestampFailure(
    'Waktu perangkat lebih awal dari waktu pembuatan dokumen. Periksa '
    'pengaturan waktu perangkat.',
    disposalId: 'd1',
    createdAtUtc: DateTime.utc(2026, 7, 30),
    postedAtUtc: DateTime.utc(2026, 7, 29),
  );
}

/// The insufficient-stock failure, with quantities the message quotes.
abstract final class InvalidDisposalStock {
  static final failure = InsufficientDisposalStockFailure(
    'Saldo DSP-0001 batch B-1 di lokasi ini tidak mencukupi: tersedia 1.5 ampul, '
    'diminta 3 ampul.',
    itemId: 'i1',
    locationId: 'loc1',
    batchId: 'b1',
    available: Quantity.parse('1.5'),
    requested: Quantity.parse('3'),
  );
}
