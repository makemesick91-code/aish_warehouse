import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Distribusi failure, as the person on the other side of the screen reads it
/// (§33).
///
/// The rule this file enforces is small and easy to break: a failure that reaches a
/// clinic user must be a **sentence in Indonesian that says what to do**, never a class
/// name, never an id, never a stack trace. `describeFailure` returns `AppFailure.message`
/// verbatim, so the message *is* the UI copy — which is exactly why it needs a test of
/// its own rather than being reviewed once and then quietly edited.
void main() {
  final expiry = DateOnly.of(2026, 7, 20);

  /// One instance of every Distribusi failure, with the message the use cases actually
  /// pass. Written out rather than generated: the point is to read them as a set and
  /// notice one that does not belong.
  final failures = <String, AppFailure>{
    'notFound': const DistributionNotFoundFailure(
      'Distribusi tidak ditemukan.',
      distributionId: 'd-1',
    ),
    'invalidState': const InvalidDistributionStateFailure(
      'Distribusi TMP-DIST-1 sudah diposting dan bersifat final.',
      distributionId: 'd-1',
      currentStatus: DistributionStatus.posted,
      attemptedStatus: DistributionStatus.posted,
    ),
    'alreadyPosted': DistributionAlreadyPostedFailure(
      'Distribusi TMP-DIST-1 sudah diposting, sehingga tidak dapat diubah '
      'lagi.',
      distributionId: 'd-1',
      postedAt: DateTime.utc(2026, 7, 30, 3),
    ),
    'lineRequired': const DistributionLineRequiredFailure(
      'Distribusi TMP-DIST-1 belum memuat barang, sehingga tidak dapat '
      'diposting.',
      distributionId: 'd-1',
    ),
    'lineNotFound': const DistributionLineNotFoundFailure(
      'Baris distribusi tidak ditemukan pada dokumen ini.',
      lineId: 'l-1',
    ),
    'branchMismatch': const DistributionBranchMismatchFailure(
      'Distribusi ini milik cabang lain, sehingga tidak dapat diakses dari '
      'akun ini.',
      actorUserId: 'u-1',
      actorBranchId: 'b-1',
      documentBranchId: 'b-2',
    ),
    'roomBranchMismatch': const DistributionRoomBranchMismatchFailure(
      'Ruangan tujuan bukan milik cabang ini, sehingga tidak dapat menjadi '
      'tujuan distribusi.',
      roomId: 'r-1',
      documentBranchId: 'b-1',
    ),
    'roomInactive': const DistributionRoomInactiveFailure(
      'Ruangan "Ruang Dental 2" sudah dinonaktifkan, sehingga stok tidak dapat '
      'dipindahkan ke ruangan tersebut. Hapus atau ganti barisnya.',
      roomId: 'r-2',
    ),
    'roomLocationNotFound': const DistributionRoomLocationNotFoundFailure(
      'Ruangan "Ruang Dental 2" belum memiliki lokasi stok yang valid, '
      'sehingga tidak dapat menerima distribusi. Hubungi administrator.',
      roomId: 'r-2',
    ),
    'roomLocationAmbiguous': const DistributionRoomLocationAmbiguousFailure(
      'Terdapat lebih dari satu lokasi stok untuk ruangan "Ruang Dental 2", '
      'sehingga sistem tidak dapat menentukan tujuan distribusi. Hubungi '
      'administrator.',
      roomId: 'r-2',
      locationIds: ['loc-1', 'loc-2'],
    ),
    'branchStoreNotFound': const DistributionBranchStoreNotFoundFailure(
      'Lokasi Gudang Cabang belum tersedia atau sudah tidak aktif, sehingga '
      'distribusi tidak dapat dilakukan. Hubungi administrator.',
      branchId: 'b-1',
    ),
    'branchStoreAmbiguous': const DistributionBranchStoreAmbiguousFailure(
      'Terdapat lebih dari satu lokasi Gudang Cabang untuk cabang ini, '
      'sehingga sistem tidak dapat menentukan sumber distribusi. Hubungi '
      'administrator.',
      branchId: 'b-1',
      locationIds: ['loc-1', 'loc-2'],
    ),
    'invalidQty': InvalidDistributionQuantityFailure(
      'Jumlah distribusi harus lebih besar dari 0 (diterima 0).',
      qty: Quantity.zero(),
    ),
    'insufficientStock': InsufficientBranchStockFailure(
      'Saldo Gudang Cabang untuk DIST-0001 tidak mencukupi: tersedia 2 box, '
      'dibutuhkan 5 box untuk seluruh ruangan pada distribusi ini.',
      itemId: 'i-1',
      locationId: 'loc-1',
      available: Quantity.parse('2'),
      requested: Quantity.parse('5'),
    ),
    'itemHasNoStock': const DistributionItemHasNoStockFailure(
      'Barang DIST-0004 tidak memiliki saldo di Gudang Cabang, sehingga tidak '
      'dapat didistribusikan.',
      itemId: 'i-4',
      locationId: 'loc-1',
    ),
    'invalidBatch': const InvalidDistributionBatchFailure(
      'Barang DIST-0002 memiliki tanggal kedaluwarsa, sehingga batch wajib '
      'dipilih untuk distribusi.',
      itemId: 'i-2',
    ),
    'expiredBatch': ExpiredBatchForDistributionFailure(
      'Batch C-EXPIRED sudah kedaluwarsa (ED 2026-07-20), sehingga tidak dapat '
      'didistribusikan. Barang kedaluwarsa hanya boleh dikeluarkan melalui '
      'pemusnahan.',
      batchId: 'b-exp',
      batchNo: 'C-EXPIRED',
      expiryDate: expiry,
    ),
    'fefoReasonRequired': DistributionFefoOverrideReasonRequiredFailure(
      'Batch A-NEW dipilih meskipun batch B-OLD (ED 2026-07-20) masih tersisa '
      '2. Untuk DIST-0002, pemilihan di luar urutan FEFO wajib disertai '
      'catatan alasan.',
      itemId: 'i-2',
      selectedBatchId: 'b-new',
      selectedBatchNo: 'A-NEW',
      skippedBatchId: 'b-old',
      skippedBatchNo: 'B-OLD',
      skippedExpiryDate: expiry,
    ),
    'duplicateLine': const DuplicateDistributionLineFailure(
      'Barang ini sudah ada pada ruangan tersebut. Ubah jumlah baris yang ada, '
      'bukan menambah baris baru.',
      distributionId: 'd-1',
      roomId: 'r-1',
      itemId: 'i-1',
    ),
    'lineIntegrity': const DistributionLineIntegrityFailure(
      'Daftar barang distribusi tidak dapat dimuat sepenuhnya, sehingga '
      'posting dibatalkan. Hubungi administrator.',
      distributionId: 'd-1',
      missingLineIds: ['l-1'],
    ),
    'historicalMissing': const HistoricalDistributionReferenceMissingFailure(
      'Distribusi tidak dapat diproses karena barang historis tidak ditemukan. '
      'Hubungi administrator.',
      entity: 'items',
      id: 'i-1',
      distributionId: 'd-1',
    ),
    'concurrentUpdate': const ConcurrentDistributionUpdateFailure(
      'Distribusi TMP-DIST-1 baru saja diubah dari perangkat lain. Muat ulang '
      'halaman lalu coba lagi.',
      distributionId: 'd-1',
    ),
    'invalidTimestamp': InvalidDistributionTimestampFailure(
      'Waktu perangkat lebih awal dari waktu pembuatan dokumen. Periksa '
      'pengaturan waktu perangkat.',
      distributionId: 'd-1',
      createdAtUtc: DateTime.utc(2026, 7, 30, 3),
      postedAtUtc: DateTime.utc(2026, 7, 30, 2),
    ),
  };

  group('setiap kegagalan punya pesan yang dapat ditindaklanjuti', () {
    test('describeFailure meneruskan pesan bisnis apa adanya', () {
      for (final entry in failures.entries) {
        expect(
          describeFailure(entry.value),
          entry.value.message,
          reason: '${entry.key} tidak diteruskan apa adanya.',
        );
      }
    });

    test('tidak ada pesan kosong atau terlalu pendek', () {
      for (final entry in failures.entries) {
        final message = entry.value.message.trim();
        expect(message, isNotEmpty, reason: '${entry.key} kosong.');
        expect(
          message.length,
          greaterThan(20),
          reason: '${entry.key} terlalu pendek untuk menjelaskan apa pun.',
        );
      }
    });

    test('pesan diakhiri tanda baca', () {
      for (final entry in failures.entries) {
        expect(
          entry.value.message.trim(),
          endsWith('.'),
          reason: '${entry.key} bukan kalimat lengkap.',
        );
      }
    });

    test('tidak ada nama kelas, tipe atau jejak stack pada pesan', () {
      for (final entry in failures.entries) {
        final message = entry.value.message;
        for (final leak in [
          'Failure',
          'Exception',
          'Error',
          '#0',
          'package:',
          'null',
          'Instance of',
        ]) {
          expect(
            message.contains(leak),
            isFalse,
            reason: '${entry.key} membocorkan "$leak".',
          );
        }
      }
    });

    test('tidak ada id teknis pada pesan', () {
      // An id tells a clinic user nothing and is exactly what a support ticket should
      // carry instead. The failure *object* keeps them for logs; the sentence does not.
      for (final entry in failures.entries) {
        final message = entry.value.message;
        for (final id in [
          'd-1',
          'l-1',
          'r-1',
          'r-2',
          'b-1',
          'b-2',
          'i-1',
          'i-2',
          'i-4',
          'loc-1',
          'loc-2',
          'u-1',
        ]) {
          expect(
            message.contains(id),
            isFalse,
            reason: '${entry.key} membocorkan id "$id".',
          );
        }
      }
    });

    test('pesan berbahasa Indonesia', () {
      // A crude but effective check: every message has to contain at least one Indonesian
      // function word. An English sentence that slipped in would fail here rather than in
      // front of a nurse.
      const markers = [
        'tidak',
        'sudah',
        'harus',
        'belum',
        'dapat',
        'wajib',
        'sehingga',
        'untuk',
        'pada',
        'lagi',
        'dari',
        'lalu',
      ];
      for (final entry in failures.entries) {
        final message = entry.value.message.toLowerCase();
        expect(
          markers.any(message.contains),
          isTrue,
          reason: '${entry.key} tampaknya bukan Bahasa Indonesia.',
        );
      }
    });
  });

  group('pesan menyebut fakta yang membuatnya dapat ditindaklanjuti', () {
    test('kekurangan stok menyebut tersedia dan dibutuhkan', () {
      final message = failures['insufficientStock']!.message;
      expect(message, contains('tersedia 2 box'));
      expect(message, contains('dibutuhkan 5 box'));
      // And that the total is across every room — the fact that makes an "but I only
      // asked for 3" objection answerable.
      expect(message, contains('seluruh ruangan'));
    });

    test('batch kedaluwarsa menyebut nomor batch, ED dan jalan keluarnya', () {
      final message = failures['expiredBatch']!.message;
      expect(message, contains('C-EXPIRED'));
      expect(message, contains('2026-07-20'));
      // G-E7: the answer is disposal, and saying so is what stops the branch head hunting
      // for a way to force it through.
      expect(message, contains('pemusnahan'));
    });

    test('alasan FEFO menyebut batch yang dipilih dan yang dilewati', () {
      final message = failures['fefoReasonRequired']!.message;
      expect(message, contains('A-NEW'));
      expect(message, contains('B-OLD'));
      expect(message, contains('catatan alasan'));
    });

    test('ruangan cabang lain tidak mengonfirmasi cabang mana', () {
      // Telling a branch head *which* branch owns the room would be a small enumeration
      // oracle. The message says only that it is not theirs.
      final message = failures['roomBranchMismatch']!.message;
      expect(message, contains('bukan milik cabang ini'));
      expect(message.contains('CAB-'), isFalse);
    });

    test('kegagalan concurrency menyuruh memuat ulang, bukan mencoba lagi', () {
      final message = failures['concurrentUpdate']!.message;
      expect(message, contains('Muat ulang'));
    });

    test('kegagalan yang butuh administrator mengatakannya', () {
      for (final key in [
        'roomLocationNotFound',
        'roomLocationAmbiguous',
        'branchStoreNotFound',
        'branchStoreAmbiguous',
        'lineIntegrity',
        'historicalMissing',
      ]) {
        expect(
          failures[key]!.message,
          contains('administrator'),
          reason: '$key tidak mengarahkan ke administrator.',
        );
      }
    });

    test('ruangan nonaktif menyebut jalan keluar bagi pengguna', () {
      // §32: the way out is to remove or replace the line, and a message that only says
      // "blocked" leaves the branch head stuck.
      final message = failures['roomInactive']!.message;
      expect(message, contains('Hapus atau ganti'));
    });

    test('posisi ganda menyuruh mengubah baris yang ada', () {
      expect(
        failures['duplicateLine']!.message,
        contains('Ubah jumlah baris yang ada'),
      );
    });
  });

  group('fallback', () {
    test('kegagalan tak dikenal menjadi satu kalimat generik', () {
      expect(
        describeFailure(StateError('boom')),
        'Sesi pengguna tidak tersedia. Muat ulang aplikasi lalu coba lagi.',
      );
      expect(
        describeFailure(Exception('boom')),
        'Terjadi kesalahan tak terduga. Silakan coba lagi.',
      );
      // A caller-supplied fallback sentence survives, which is what lets a screen say
      // something specific when it has no failure object at all.
      expect(
        describeFailure('Gagal membuat distribusi.'),
        'Gagal membuat distribusi.',
      );
    });

    test('pesan generik tidak membocorkan detail teknis', () {
      final message = describeFailure(
        Exception('SqliteException(19): UNIQUE constraint failed'),
      );
      expect(message.contains('Sqlite'), isFalse);
      expect(message.contains('UNIQUE'), isFalse);
    });
  });

  group('label status', () {
    test('setiap status punya label Bahasa Indonesia', () {
      expect(DistributionStatus.draft.label, 'Draft');
      expect(DistributionStatus.posted.label, 'Selesai Diposting');
      for (final status in DistributionStatus.values) {
        expect(status.label.trim(), isNotEmpty);
        expect(status.label, isNot(status.dbValue));
      }
    });
  });
}
