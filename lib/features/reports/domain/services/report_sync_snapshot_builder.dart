import '../../../../core/enums/app_enums.dart';
import '../../../../core/time/app_date_time_formatter.dart';
import '../models/reporting_models.dart';

/// One source row's contribution to the freshness snapshot.
///
/// A tiny record rather than a shared interface, so a movement, a document header
/// and a document line can all be counted by the same fold without any of them
/// growing a reporting-specific method.
typedef ReportSyncSample = ({SyncStatus status, DateTime updatedAtUtc});

/// The *"status sync terakhir"* every report header must carry (G-L3).
///
/// > *"header laporan wajib mencantumkan waktu cetak, rentang periode, lokasi, dan
/// > status sync terakhir agar jelas data per kapan."*
///
/// ### Counted from rows, never from the network
///
/// The tempting implementation is a connectivity check — *online, so the data is
/// current*. It answers a different question. A device with full signal can still
/// hold twenty movements that were never pushed, and a device that has been offline
/// for a week may hold nothing pending at all. G-L3 asks *"data per kapan"*, and the
/// only rows that can answer it are the rows the report actually used. So this
/// builder takes those rows and nothing else — there is no network dependency in
/// this file, in the module, or reachable from it.
///
/// ### Every row that produced a number is counted
///
/// The samples handed in are the ledger movements the figures came from **plus** the
/// document rows a recap listed. Counting only one of the two would let a report
/// whose documents are all pending print *"0 pending"* while every status column in
/// it is provisional.
abstract final class ReportSyncSnapshotBuilder {
  /// Folds [samples] into a snapshot.
  ///
  /// Duplicate rows are the caller's business, not this fold's: a recap that lists a
  /// header once per line hands the header in once, keyed by id, because counting it
  /// per line would make a ten-line document look like ten pending rows.
  static ReportSyncSnapshot build(Iterable<ReportSyncSample> samples) {
    var synced = 0;
    var pending = 0;
    var conflict = 0;
    DateTime? latest;

    for (final sample in samples) {
      switch (sample.status) {
        case SyncStatus.synced:
          synced++;
        case SyncStatus.pending:
          pending++;
        case SyncStatus.conflict:
          conflict++;
      }
      if (latest == null || sample.updatedAtUtc.isAfter(latest)) {
        latest = sample.updatedAtUtc;
      }
    }

    return ReportSyncSnapshot(
      syncedCount: synced,
      pendingCount: pending,
      conflictCount: conflict,
      latestUpdatedAtUtc: latest,
    );
  }

  /// De-duplicates samples by an id before folding.
  ///
  /// The entry point every recap builder uses, so *"one document, one sample"* is
  /// stated once rather than remembered eight times.
  static ReportSyncSnapshot buildDeduplicated(
    Iterable<({String id, SyncStatus status, DateTime updatedAtUtc})> samples,
  ) {
    final byId = <String, ReportSyncSample>{};
    for (final sample in samples) {
      byId[sample.id] = (
        status: sample.status,
        updatedAtUtc: sample.updatedAtUtc,
      );
    }
    return build(byId.values);
  }

  /// `Pembaruan data terakhir: 30 Jul 2026, 22:15 GMT+8`, or the empty sentence.
  ///
  /// Rendered through [AppDateTimeFormatter], so the instant is shown in operational
  /// time (GMT+8) rather than the device's — a report printed in Jakarta and one
  /// printed on a tablet still set to UTC must state the same moment (T-4).
  static String describeLastUpdate(ReportSyncSnapshot snapshot) {
    final latest = snapshot.latestUpdatedAtUtc;
    if (latest == null) return ReportSyncSnapshot.emptyLabel;
    return 'Pembaruan data terakhir: '
        '${AppDateTimeFormatter.dateTimeWithZone(latest)}';
  }

  /// The warning a header shows when some of the data behind it has not reached
  /// the server, or `null` when there is nothing to warn about.
  ///
  /// Worded as *"angka dapat berubah"* rather than *"data salah"*, because pending
  /// data is not wrong — G-Y1 makes working offline the normal case, and the figures
  /// are the honest local truth. What the reader needs to know is that the server
  /// may hold a different answer.
  static String? describeWarning(ReportSyncSnapshot snapshot) {
    if (snapshot.hasConflict) {
      return 'Sebagian data masih berstatus konflik '
          '(${snapshot.conflictCount} baris). Angka dapat berubah setelah '
          'konflik diselesaikan.';
    }
    if (snapshot.hasPending) {
      return 'Sebagian data belum tersinkron (${snapshot.pendingCount} baris). '
          'Angka dapat berubah setelah sinkronisasi.';
    }
    return null;
  }
}
