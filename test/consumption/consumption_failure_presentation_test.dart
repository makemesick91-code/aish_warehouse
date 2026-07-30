import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Pemakaian failure presents as a sentence a clinic user can act on (§34).
///
/// `describeFailure` returns `AppFailure.message` unchanged, so what this file really
/// asserts is the *content* of those messages: Indonesian, actionable, and free of the two
/// things that must never reach a screen — a raw exception string, and any hint about a
/// document the reader is not cleared for.
///
/// The two vocabulary bans get their own tests, because both are easy to reintroduce by
/// copying wording from another milestone:
///
/// * **no approval words.** There is no submit, approve or reject stage on this document
///   (§7), so *Ajukan*, *Setujui* and *Menunggu Persetujuan* must appear nowhere.
/// * **no patient words.** A consumption is an inventory document (§9), so no message may
///   name a patient, a record number or a diagnosis.
void main() {
  /// Every Pemakaian failure, constructed with realistic arguments.
  ///
  /// Built as a list rather than asserted one by one, so the vocabulary rules below apply
  /// to *all* of them — including one added later without a test of its own.
  final failures = <AppFailure>[
    const ConsumptionNotFoundFailure(
      'Pemakaian tidak ditemukan.',
      consumptionId: 'c1',
    ),
    const InvalidConsumptionStateFailure(
      'Pemakaian CNS-1 sudah diposting dan bersifat final.',
      consumptionId: 'c1',
      currentStatus: ConsumptionStatus.posted,
      attemptedStatus: ConsumptionStatus.posted,
    ),
    ConsumptionAlreadyPostedFailure(
      'Pemakaian CNS-1 sudah diposting, sehingga tidak dapat diubah lagi.',
      consumptionId: 'c1',
      postedAt: DateTime.utc(2026, 7, 30, 8),
    ),
    const ConsumptionLineRequiredFailure(
      'Pemakaian CNS-1 belum memuat barang, sehingga tidak dapat diposting.',
      consumptionId: 'c1',
    ),
    const ConsumptionLineNotFoundFailure(
      'Baris pemakaian tidak ditemukan pada dokumen ini.',
      lineId: 'l1',
    ),
    const ConsumptionNotOwnedFailure(
      'Pemakaian ini dicatat oleh perawat lain, sehingga tidak dapat diubah '
      'atau diposting dari akun ini.',
      consumptionId: 'c1',
      actorUserId: 'u1',
    ),
    const ConsumptionBranchMismatchFailure(
      'Pemakaian ini milik cabang lain, sehingga tidak dapat diakses dari akun '
      'ini.',
      actorUserId: 'u1',
      actorBranchId: 'b1',
      documentBranchId: 'b2',
    ),
    const ConsumptionRoomBranchMismatchFailure(
      'Ruangan ini bukan milik cabang Anda, sehingga pemakaiannya tidak dapat '
      'dicatat dari akun ini.',
      roomId: 'r1',
      documentBranchId: 'b1',
    ),
    const ConsumptionRoomInactiveFailure(
      'Ruangan "Ruang Dental 2" sudah dinonaktifkan, sehingga pemakaian di '
      'ruangan tersebut tidak dapat dicatat atau diposting.',
      roomId: 'r1',
    ),
    const ConsumptionRoomLocationNotFoundFailure(
      'Ruangan "Ruang Dental 2" belum memiliki lokasi stok yang valid, '
      'sehingga pemakaiannya tidak dapat dicatat. Hubungi administrator.',
      roomId: 'r1',
    ),
    const ConsumptionRoomLocationAmbiguousFailure(
      'Terdapat lebih dari satu lokasi stok untuk ruangan "Ruang Dental 1", '
      'sehingga sistem tidak dapat menentukan sumber pemakaian. Hubungi '
      'administrator.',
      roomId: 'r1',
      locationIds: ['l1', 'l2'],
    ),
    const ConsumptionItemHasNoStockFailure(
      'Barang CNS-0003 tidak memiliki saldo di ruangan ini, sehingga tidak '
      'dapat dicatat sebagai pemakaian.',
      itemId: 'i1',
      locationId: 'loc1',
    ),
    const ConsumptionBatchRequiredFailure(
      'Barang CNS-0001 memiliki tanggal kedaluwarsa, sehingga batch wajib '
      'dipilih untuk pemakaian.',
      itemId: 'i1',
    ),
    const ConsumptionBatchNotAllowedFailure(
      'Barang CNS-0003 tidak dilacak per batch, sehingga tidak boleh memiliki '
      'batch.',
      itemId: 'i1',
      batchId: 'b1',
    ),
    const InvalidConsumptionBatchFailure(
      'Batch A-VALID bukan milik barang CNS-0003.',
      itemId: 'i1',
      batchId: 'b1',
    ),
    ExpiredBatchForConsumptionFailure(
      'Batch D-EXPIRED sudah kedaluwarsa (ED 2026-07-27), sehingga tidak dapat '
      'dipakai. Barang kedaluwarsa hanya boleh dikeluarkan melalui pemusnahan.',
      batchId: 'b1',
      batchNo: 'D-EXPIRED',
      expiryDate: DateOnly.of(2026, 7, 27),
      lineId: 'l1',
    ),
    InvalidConsumptionQuantityFailure(
      'Jumlah pemakaian harus lebih besar dari 0 (diterima 0).',
      lineId: 'l1',
      qty: Quantity.zero(),
    ),
    InsufficientRoomStockFailure(
      'Saldo ruangan untuk CNS-0001 batch A-VALID tidak mencukupi: tersedia '
      '2.5 ampul, diminta 3 ampul.',
      itemId: 'i1',
      locationId: 'loc1',
      batchId: 'b1',
      available: Quantity.parse('2.5'),
      requested: Quantity.parse('3'),
    ),
    const DuplicateConsumptionLineFailure(
      'Batch ini sudah ada pada dokumen pemakaian ini. Ubah jumlah baris yang '
      'ada, bukan menambah baris baru.',
      consumptionId: 'c1',
      itemId: 'i1',
      batchId: 'b1',
    ),
    const ConsumptionLineIntegrityFailure(
      'Daftar barang pemakaian tidak dapat dimuat sepenuhnya, sehingga posting '
      'dibatalkan. Hubungi administrator.',
      consumptionId: 'c1',
      missingLineIds: ['l1'],
    ),
    const HistoricalConsumptionReferenceMissingFailure(
      'Pemakaian tidak dapat diproses karena batch historis tidak ditemukan. '
      'Hubungi administrator.',
      entity: 'item_batches',
      id: 'b1',
      consumptionId: 'c1',
    ),
    const ConcurrentConsumptionUpdateFailure(
      'Pemakaian CNS-1 baru saja diubah dari perangkat lain. Muat ulang '
      'halaman lalu coba lagi.',
      consumptionId: 'c1',
    ),
    InvalidConsumptionTimestampFailure(
      'Waktu perangkat lebih awal dari waktu pembuatan dokumen. Periksa '
      'pengaturan waktu perangkat.',
      consumptionId: 'c1',
      createdAtUtc: DateTime.utc(2026, 7, 30, 8),
      postedAtUtc: DateTime.utc(2026, 7, 30, 7),
    ),
  ];

  group('presentasi', () {
    test('setiap kegagalan menghasilkan pesan yang sama', () {
      for (final failure in failures) {
        expect(describeFailure(failure), failure.message);
      }
    });

    test('tidak ada pesan kosong atau placeholder', () {
      for (final failure in failures) {
        final message = describeFailure(failure);
        expect(message.trim(), isNotEmpty);
        expect(message, isNot('-'));
        expect(message, isNot('null'));
        expect(
          message,
          isNot(contains('Instance of')),
          reason: 'Pesan tidak boleh membocorkan toString objek.',
        );
        expect(
          message,
          isNot(contains('Exception')),
          reason: 'Pesan tidak boleh membocorkan nama kelas exception.',
        );
      }
    });

    test('setiap pesan berbahasa Indonesia dan diakhiri titik', () {
      for (final failure in failures) {
        final message = describeFailure(failure);
        expect(
          message.endsWith('.'),
          isTrue,
          reason: 'Pesan "$message" bukan kalimat lengkap.',
        );
        // A crude but effective check: every message contains at least one Indonesian
        // function word, which an English string copied from a library would not.
        expect(
          const [
            'tidak',
            'sudah',
            'belum',
            'harus',
            'wajib',
            'sehingga',
            'bukan',
            'dapat',
            'Hubungi',
            'Periksa',
            'Muat',
            'Ubah',
          ].any(message.contains),
          isTrue,
          reason: 'Pesan "$message" tampaknya bukan Bahasa Indonesia.',
        );
      }
    });

    test('kegagalan tak terduga memberi satu kalimat generik', () {
      // What a driver error or a bug becomes: never a stack trace, never a raw string.
      expect(
        describeFailure(Exception('boom')),
        'Terjadi kesalahan tak terduga. Silakan coba lagi.',
      );
      expect(
        describeFailure(StateError('no session')),
        'Sesi pengguna tidak tersedia. Muat ulang aplikasi lalu coba lagi.',
      );
    });
  });

  group('kosakata yang dilarang', () {
    test('tidak ada kata persetujuan (§7)', () {
      // There is no submit, approve or reject stage on this document. Wording that implied
      // one would describe a workflow that does not exist — and G-R4 is a reason not to
      // invent a second half rather than a licence to.
      const forbidden = [
        'Ajukan',
        'ajukan',
        'Setujui',
        'setujui',
        'disetujui',
        'Menunggu Persetujuan',
        'persetujuan',
        'approval',
        'approve',
        'ditolak oleh',
      ];
      for (final failure in failures) {
        final message = describeFailure(failure);
        for (final word in forbidden) {
          expect(
            message,
            isNot(contains(word)),
            reason: 'Pesan "$message" memakai kosakata persetujuan: $word.',
          );
        }
      }
    });

    test('tidak ada kata data pasien (§9)', () {
      const forbidden = [
        'pasien',
        'Pasien',
        'patient',
        'rekam medis',
        'diagnosis',
        'diagnosa',
        'tindakan medis',
      ];
      for (final failure in failures) {
        final message = describeFailure(failure);
        for (final word in forbidden) {
          expect(
            message,
            isNot(contains(word)),
            reason: 'Pesan "$message" menyebut data pasien: $word.',
          );
        }
      }
    });

    test('tidak ada kata FEFO wajib (§17)', () {
      // §17 is explicit that consumption inherits no mandatory FEFO override. A message
      // demanding a reason for picking a younger batch would be inventing the rule.
      for (final failure in failures) {
        final message = describeFailure(failure);
        expect(message, isNot(contains('FEFO')));
        expect(message, isNot(contains('alasan override')));
      }
    });
  });

  group('pesan tidak membocorkan dokumen orang lain', () {
    test('penolakan kepemilikan tidak menyebut nama perawat lain', () {
      const failure = ConsumptionNotOwnedFailure(
        'Pemakaian ini dicatat oleh perawat lain, sehingga tidak dapat diubah '
        'atau diposting dari akun ini.',
        consumptionId: 'c1',
        actorUserId: 'u1',
      );
      final message = describeFailure(failure);
      // "another nurse" rather than *which* nurse: naming them would tell one person about
      // another's shift.
      expect(message, contains('perawat lain'));
      expect(message, isNot(contains('u2')));
    });

    test('penolakan cabang tidak menyebut cabang mana', () {
      const failure = ConsumptionBranchMismatchFailure(
        'Pemakaian ini milik cabang lain, sehingga tidak dapat diakses dari '
        'akun ini.',
        actorUserId: 'u1',
        actorBranchId: 'b1',
        documentBranchId: 'b2',
      );
      final message = describeFailure(failure);
      expect(message, contains('cabang lain'));
      expect(
        message,
        isNot(contains('b2')),
        reason: 'Pesan tidak boleh mengonfirmasi cabang dokumen.',
      );
    });

    test('kegagalan tetap membawa data terstruktur untuk log', () {
      // The message withholds; the *fields* do not. That split is what lets a log say
      // exactly which branch and which document while the screen says neither.
      const failure = ConsumptionBranchMismatchFailure(
        'Pemakaian ini milik cabang lain.',
        actorUserId: 'u1',
        actorBranchId: 'b1',
        documentBranchId: 'b2',
      );
      expect(failure.documentBranchId, 'b2');
      expect(failure.actorBranchId, 'b1');
      expect(failure.actorUserId, 'u1');
    });
  });

  group('pesan menyebut angka yang dapat ditindaklanjuti', () {
    test('kekurangan stok menyebut tersedia dan diminta', () {
      final failure = InsufficientRoomStockFailure(
        'Saldo ruangan untuk CNS-0001 batch A-VALID tidak mencukupi: tersedia '
        '2.5 ampul, diminta 3 ampul.',
        itemId: 'i1',
        locationId: 'loc1',
        batchId: 'b1',
        available: Quantity.parse('2.5'),
        requested: Quantity.parse('3'),
      );
      final message = describeFailure(failure);
      expect(message, contains('2.5 ampul'));
      expect(message, contains('3 ampul'));
      // Never milli-units on a screen (Q-4).
      expect(message, isNot(contains('2500')));
      expect(message, isNot(contains('3000')));
    });

    test('batch kedaluwarsa menyebut tanggalnya dan jalur keluarnya', () {
      final failure = ExpiredBatchForConsumptionFailure(
        'Batch D-EXPIRED sudah kedaluwarsa (ED 2026-07-27), sehingga tidak '
        'dapat dipakai. Barang kedaluwarsa hanya boleh dikeluarkan melalui '
        'pemusnahan.',
        batchId: 'b1',
        batchNo: 'D-EXPIRED',
        expiryDate: DateOnly.of(2026, 7, 27),
      );
      final message = describeFailure(failure);
      expect(message, contains('D-EXPIRED'));
      expect(message, contains('2026-07-27'));
      // The next action, named: a refusal without one leaves the stock on the shelf.
      expect(message, contains('pemusnahan'));
    });

    test('kuantitas tidak valid menyebut nilai yang diterima', () {
      final failure = InvalidConsumptionQuantityFailure(
        'Jumlah pemakaian harus lebih besar dari 0 (diterima 0).',
        qty: Quantity.zero(),
      );
      expect(describeFailure(failure), contains('0'));
    });

    test('referensi historis hilang menyuruh menghubungi administrator', () {
      const failure = HistoricalConsumptionReferenceMissingFailure(
        'Pemakaian tidak dapat diproses karena batch historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'item_batches',
        id: 'b1',
        consumptionId: 'c1',
      );
      final message = describeFailure(failure);
      // A data fault is not the nurse's to fix, so the message says whose it is.
      expect(message, contains('Hubungi administrator'));
      // …and the table name stays out of the sentence while staying in the fields.
      expect(message, isNot(contains('item_batches')));
      expect(failure.entity, 'item_batches');
    });

    test('konflik perangkat lain menyuruh memuat ulang', () {
      const failure = ConcurrentConsumptionUpdateFailure(
        'Pemakaian CNS-1 baru saja diubah dari perangkat lain. Muat ulang '
        'halaman lalu coba lagi.',
        consumptionId: 'c1',
      );
      expect(describeFailure(failure), contains('Muat ulang'));
    });
  });
}
