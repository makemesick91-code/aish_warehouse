import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_period_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// §15 — a report's period is stated in GMT+8 civil dates and applied as a
/// half-open UTC window.
///
/// The boundary the specification pins is the one every test here revolves around:
///
/// ```text
/// GMT+8 2026-07-30 00:00  =  UTC 2026-07-29 16:00
/// GMT+8 2026-07-31 00:00  =  UTC 2026-07-30 16:00
/// ```
///
/// Getting it wrong by eight hours is invisible in every single-day test that runs
/// at midday and catastrophic for a clinic that counts stock in the evening.
void main() {
  group('rentang operasional GMT+8', () {
    test('awal periode adalah 00:00 GMT+8 dalam UTC', () {
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 30),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(period.startUtc, DateTime.utc(2026, 7, 29, 16));
    });

    test('akhir periode eksklusif adalah 00:00 GMT+8 hari berikutnya', () {
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 30),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(period.endExclusiveUtc, DateTime.utc(2026, 7, 30, 16));
    });

    test('instant tepat di awal periode termasuk', () {
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 30),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(period.contains(DateTime.utc(2026, 7, 29, 16)), isTrue);
    });

    test('instant tepat di akhir eksklusif tidak termasuk', () {
      // The half-open half of §15: a movement stamped here belongs to 31 Jul, and
      // counting it in both days would double it in a monthly recap.
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 30),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(period.contains(DateTime.utc(2026, 7, 30, 16)), isFalse);
    });

    test('satu mikrodetik sebelum akhir masih termasuk', () {
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 30),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(
        period.contains(DateTime.utc(2026, 7, 30, 15, 59, 59, 999, 999)),
        isTrue,
      );
    });

    test('pergerakan malam hari GMT+8 masuk hari operasional yang benar', () {
      // 23:30 GMT+8 on 30 Jul is 15:30 UTC on the same date — the case a naive UTC
      // window would push into the previous day.
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 30),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(period.contains(DateTime.utc(2026, 7, 30, 15, 30)), isTrue);
      // 07:00 GMT+8 on 30 Jul is 23:00 UTC on 29 Jul: still the same clinic day.
      expect(period.contains(DateTime.utc(2026, 7, 29, 23)), isTrue);
    });

    test('rentang beberapa hari mencakup keduanya inklusif', () {
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 1),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(period.startUtc, DateTime.utc(2026, 6, 30, 16));
      expect(period.endExclusiveUtc, DateTime.utc(2026, 7, 30, 16));
    });

    test('periode terbalik ditolak', () {
      expect(
        () => ReportPeriodPolicy.range(
          periodStart: DateOnly.of(2026, 7, 31),
          periodEnd: DateOnly.of(2026, 7, 30),
        ),
        throwsA(isA<InvalidReportPeriodFailure>()),
      );
    });

    test('waktu pada input diabaikan; hanya tanggal sipil yang dibaca', () {
      // The picker may hand over any time of day, and a device in another timezone
      // may hand over a local-flagged value. Neither may move the clinic day (T-9).
      final period = ReportPeriodPolicy.range(
        periodStart: DateTime.utc(2026, 7, 30, 21, 45),
        periodEnd: DateTime(2026, 7, 30, 3, 15),
      );

      expect(period.startUtc, DateTime.utc(2026, 7, 29, 16));
      expect(period.endExclusiveUtc, DateTime.utc(2026, 7, 30, 16));
    });
  });

  group('laporan as-of', () {
    test('start dinormalisasi sama dengan end', () {
      // §3.9: the audit row must not be able to say "as of one day" and "a range
      // whose start was lost" with the same two columns.
      final period = ReportPeriodPolicy.forReport(
        reportType: ReportType.stokLokasi,
        periodStart: DateOnly.of(2026, 7, 1),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(DateOnly.formatIso(period.periodStart), '2026-07-30');
      expect(DateOnly.formatIso(period.periodEnd), '2026-07-30');
      expect(period.isSingleDay, isTrue);
    });

    test('kedaluwarsa juga as-of', () {
      final period = ReportPeriodPolicy.forReport(
        reportType: ReportType.kadaluarsa,
        periodStart: DateOnly.of(2026, 1, 1),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(period.isSingleDay, isTrue);
    });

    test('laporan periode mempertahankan rentang penuh', () {
      final period = ReportPeriodPolicy.forReport(
        reportType: ReportType.kartuStok,
        periodStart: DateOnly.of(2026, 7, 1),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(DateOnly.formatIso(period.periodStart), '2026-07-01');
      expect(DateOnly.formatIso(period.periodEnd), '2026-07-30');
    });

    test('cutoff as-of memasukkan seluruh hari terakhir', () {
      final period = ReportPeriodPolicy.asOf(DateOnly.of(2026, 7, 30));

      expect(
        period.isAtOrBeforeCutoff(DateTime.utc(2026, 7, 30, 15, 59)),
        isTrue,
      );
      expect(period.isAtOrBeforeCutoff(DateTime.utc(2026, 7, 30, 16)), isFalse);
    });
  });

  group('minggu ISO', () {
    test('Senin sampai Minggu dikenali sebagai satu minggu ISO', () {
      // 2026-W31 runs Mon 27 Jul – Sun 2 Aug.
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 27),
        periodEnd: DateOnly.of(2026, 8, 2),
      );

      expect(ReportPeriodPolicy.isExactIsoWeek(period), isTrue);
      expect(ReportPeriodPolicy.isoWeekOf(period).label, '2026-W31');
    });

    test('Senin sampai Sabtu bukan satu minggu ISO', () {
      // The file name must not claim `2026-W31` for a range missing a day of it
      // (G-L5).
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 27),
        periodEnd: DateOnly.of(2026, 8, 1),
      );

      expect(ReportPeriodPolicy.isExactIsoWeek(period), isFalse);
    });
  });

  group('deskripsi header', () {
    test('as-of menyebut satu tanggal dan zona', () {
      final period = ReportPeriodPolicy.asOf(DateOnly.of(2026, 7, 30));

      expect(
        ReportPeriodPolicy.describe(period, isAsOf: true),
        'Per 30 Jul 2026 GMT+8',
      );
    });

    test('rentang menyebut kedua tanggal dan zona', () {
      final period = ReportPeriodPolicy.range(
        periodStart: DateOnly.of(2026, 7, 1),
        periodEnd: DateOnly.of(2026, 7, 30),
      );

      expect(
        ReportPeriodPolicy.describe(period, isAsOf: false),
        '01 Jul 2026 – 30 Jul 2026 GMT+8',
      );
    });
  });
}
