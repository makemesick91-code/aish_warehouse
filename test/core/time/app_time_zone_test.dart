import 'package:aish_warehouse/core/time/app_date_time_formatter.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every value here is a fixed instant — no `DateTime.now()`, no `toLocal()`.
/// That is what makes the expectations identical on a machine in Jakarta, in
/// UTC and in New York (spec T-4/T-7).
void main() {
  group('konversi UTC ke waktu operasional', () {
    test('UTC ditambah 8 jam', () {
      final operational = AppTimeZone.utcToOperational(
        DateTime.utc(2026, 7, 29, 14, 30),
      );

      expect(operational.year, 2026);
      expect(operational.month, 7);
      expect(operational.day, 29);
      expect(operational.hour, 22);
      expect(operational.minute, 30);
    });

    test('konversi melewati pergantian tanggal', () {
      // 2026-07-29 16:30 UTC sudah tanggal 30 di GMT+8.
      final operational = AppTimeZone.utcToOperational(
        DateTime.utc(2026, 7, 29, 16, 30),
      );

      expect(operational.day, 30);
      expect(operational.month, 7);
      expect(operational.hour, 0);
      expect(operational.minute, 30);
    });

    test('offset aplikasi adalah UTC+08:00', () {
      expect(AppTimeZone.offset, const Duration(hours: 8));
      expect(AppTimeZone.label, 'GMT+8');
    });
  });

  group('konversi waktu operasional ke UTC', () {
    test('waktu operasional dikurangi 8 jam', () {
      final utc = AppTimeZone.operationalToUtc(
        DateTime.utc(2026, 7, 30, 0, 30),
      );

      expect(utc, DateTime.utc(2026, 7, 29, 16, 30));
    });

    test('bolak-balik konversi menghasilkan nilai semula', () {
      final original = DateTime.utc(2026, 2, 28, 19, 45, 12);

      expect(
        AppTimeZone.operationalToUtc(AppTimeZone.utcToOperational(original)),
        original,
      );
    });

    test('field waktu operasional dibaca apa adanya, bukan zona perangkat', () {
      // A DateTime that is *not* flagged UTC must still be read as an
      // operational wall clock, otherwise the device offset would leak in.
      final asLocalFlagged = DateTime(2026, 7, 30, 0, 30);
      final asUtcFlagged = DateTime.utc(2026, 7, 30, 0, 30);

      expect(
        AppTimeZone.operationalToUtc(asLocalFlagged),
        AppTimeZone.operationalToUtc(asUtcFlagged),
      );
    });
  });

  group('tanggal operasional', () {
    test('"hari ini" mengikuti GMT+8, bukan tanggal UTC', () {
      // Masih 29 Juli di UTC, tetapi sudah 30 Juli secara operasional.
      final reference = DateTime.utc(2026, 7, 29, 17, 0);

      expect(AppTimeZone.operationalDate(reference), DateOnly.of(2026, 7, 30));
    });

    test('tepat sebelum batas hari masih tanggal sebelumnya', () {
      final reference = DateTime.utc(2026, 7, 29, 15, 59, 59);

      expect(AppTimeZone.operationalDate(reference), DateOnly.of(2026, 7, 29));
    });

    test('awal hari operasional menghasilkan UTC yang tepat', () {
      expect(
        AppTimeZone.startOfOperationalDayUtc(DateOnly.of(2026, 7, 29)),
        DateTime.utc(2026, 7, 28, 16),
      );
    });

    test('akhir hari operasional menghasilkan UTC yang tepat', () {
      expect(
        AppTimeZone.endOfOperationalDayUtc(DateOnly.of(2026, 7, 29)),
        DateTime.utc(2026, 7, 29, 15, 59, 59, 999, 999),
      );
    });

    test('rentang hari operasional mencakup tepat satu hari', () {
      final date = DateOnly.of(2026, 7, 29);
      final start = AppTimeZone.startOfOperationalDayUtc(date);
      final end = AppTimeZone.endOfOperationalDayUtc(date);

      expect(AppTimeZone.operationalDate(start), date);
      expect(AppTimeZone.operationalDate(end), date);
      expect(
        AppTimeZone.operationalDate(end.add(const Duration(microseconds: 1))),
        DateOnly.of(2026, 7, 30),
      );
    });

    test('dua instant pada hari operasional yang sama dikenali', () {
      expect(
        AppTimeZone.isSameOperationalDay(
          DateTime.utc(2026, 7, 28, 16),
          DateTime.utc(2026, 7, 29, 15, 59),
        ),
        isTrue,
      );
      expect(
        AppTimeZone.isSameOperationalDay(
          DateTime.utc(2026, 7, 29, 15, 59),
          DateTime.utc(2026, 7, 29, 16, 1),
        ),
        isFalse,
      );
    });
  });

  group('minggu ISO', () {
    test('menghitung nomor minggu dari tanggal operasional', () {
      expect(AppTimeZone.isoWeekNumber(DateOnly.of(2026, 7, 29)), 31);
      expect(AppTimeZone.isoWeekYear(DateOnly.of(2026, 7, 29)), 2026);
    });

    test('awal tahun mengikuti aturan minggu ISO', () {
      // 1 Januari 2027 jatuh pada hari Jumat, sehingga masih minggu 53 / 2026.
      expect(AppTimeZone.isoWeekNumber(DateOnly.of(2027, 1, 1)), 53);
      expect(AppTimeZone.isoWeekYear(DateOnly.of(2027, 1, 1)), 2026);
    });
  });

  group('civil date tidak bergeser', () {
    test('tanggal kedaluwarsa tetap sama setelah diformat', () {
      final expiry = DateOnly.of(2026, 7, 29);

      expect(AppDateTimeFormatter.civilDate(expiry), '29 Jul 2026');
      expect(DateOnly.formatIso(expiry), '2026-07-29');
    });

    test('DateOnly.from membaca field apa adanya', () {
      // Sebuah tanggal yang dibuat sebagai waktu lokal perangkat tidak boleh
      // bergeser ke hari sebelumnya.
      expect(
        DateOnly.from(DateTime(2026, 7, 29, 23, 59)),
        DateOnly.of(2026, 7, 29),
      );
      expect(
        DateOnly.from(DateTime.utc(2026, 7, 29, 0, 1)),
        DateOnly.of(2026, 7, 29),
      );
    });

    test('parse dan format ISO bolak-balik', () {
      expect(DateOnly.parseIso('2026-07-29'), DateOnly.of(2026, 7, 29));
      expect(DateOnly.formatIso(DateOnly.parseIso('2026-01-05')), '2026-01-05');
      expect(() => DateOnly.parseIso('29-07-2026'), throwsFormatException);
    });

    test('selisih hari dihitung tepat', () {
      expect(
        DateOnly.daysBetween(
          DateOnly.of(2026, 7, 29),
          DateOnly.of(2026, 7, 30),
        ),
        1,
      );
      expect(
        DateOnly.daysBetween(
          DateOnly.of(2026, 7, 30),
          DateOnly.of(2026, 7, 29),
        ),
        -1,
      );
    });
  });

  group('format tampilan memakai GMT+8', () {
    test('tanggal dan jam dikonversi sebelum diformat', () {
      final utc = DateTime.utc(2026, 7, 29, 14, 30);

      expect(AppDateTimeFormatter.date(utc), '29 Jul 2026');
      expect(AppDateTimeFormatter.dateTime(utc), '29 Jul 2026, 22:30');
      expect(AppDateTimeFormatter.time(utc), '22:30');
      expect(
        AppDateTimeFormatter.dateTimeWithZone(utc),
        '29 Jul 2026, 22:30 GMT+8',
      );
    });

    test('format melewati pergantian hari', () {
      expect(
        AppDateTimeFormatter.dateTimeWithZone(
          DateTime.utc(2026, 7, 29, 16, 30),
        ),
        '30 Jul 2026, 00:30 GMT+8',
      );
    });

    test('nama bulan memakai Bahasa Indonesia', () {
      expect(
        AppDateTimeFormatter.civilDate(DateOnly.of(2026, 5, 1)),
        '01 Mei 2026',
      );
      expect(
        AppDateTimeFormatter.civilDate(DateOnly.of(2026, 8, 17)),
        '17 Agu 2026',
      );
      expect(
        AppDateTimeFormatter.civilDate(DateOnly.of(2026, 10, 2)),
        '02 Okt 2026',
      );
      expect(
        AppDateTimeFormatter.civilDate(DateOnly.of(2026, 12, 25)),
        '25 Des 2026',
      );
    });
  });
}
