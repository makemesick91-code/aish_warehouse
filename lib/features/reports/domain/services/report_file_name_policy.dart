import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/reporting_models.dart';
import 'report_period_policy.dart';

/// G-L5's file name, built from sanitized tokens and nothing else.
///
/// ```text
/// {report_type}_{lokasi}_{periode}[_{kategori}].xlsx|pdf
/// ```
///
/// ### Deterministic, and deliberately not unique
///
/// Two exports of the same report on the same day produce the **same** name. That
/// is the specification's shape and it is also the right one: the name describes
/// what is in the file, and a UUID suffix would make every share sheet show the user
/// a string they cannot read and cannot use to find the file again. Uniqueness lives
/// one level up — each export writes into its own directory
/// `…/aish_reports/{exportId}/` (§37) — so two files can share a name without ever
/// overwriting each other.
///
/// ### The sanitizer is a security boundary, not tidiness
///
/// A category name is user-supplied master data. Unsanitized it reaches a path, and
/// `../../` in a category name is a directory traversal. [sanitizeToken] therefore
/// keeps only `A-Z a-z 0-9 - .` after folding whitespace to `-`, drops every `.`
/// run that could form `..`, and refuses to produce an empty token. Nothing here
/// builds a path — that is [ReportFileStore]'s job — but a name that cannot express
/// a traversal is a name no path builder can be tricked by.
abstract final class ReportFileNamePolicy {
  /// Longest a single token may be. Long enough for any real category name,
  /// short enough that the whole name stays under the 255-byte limit every
  /// filesystem in play enforces.
  static const int maxTokenLength = 40;

  /// Location token for a resolved scope.
  ///
  /// ```text
  /// WH               Warehouse Pusat
  /// CAB-01           one Gudang Cabang
  /// CAB-01-ALL       that branch's store and every room
  /// CAB-01-R1        one room
  /// LINTAS-CABANG    cross-branch recap
  /// ALL              every location, every branch
  /// ```
  ///
  /// Built from branch and room **codes** rather than names, because a code is
  /// already short, already unique and already the thing printed on the shelf.
  static String locationToken({
    required ReportScopeType scopeType,
    MasterBranch? branch,
    MasterRoom? room,
  }) {
    switch (scopeType) {
      case ReportScopeType.warehouse:
        return 'WH';
      case ReportScopeType.branchStore:
        return sanitizeToken(branch?.code ?? 'CABANG');
      case ReportScopeType.room:
        final branchToken = sanitizeToken(branch?.code ?? 'CABANG');
        final roomToken = sanitizeToken(room?.code ?? 'RUANG');
        return '$branchToken-$roomToken';
      case ReportScopeType.branchAll:
        return '${sanitizeToken(branch?.code ?? 'CABANG')}-ALL';
      case ReportScopeType.crossBranch:
        return 'LINTAS-CABANG';
      case ReportScopeType.allLocations:
        return 'ALL';
    }
  }

  /// Period token.
  ///
  /// ```text
  /// 20260730              as-of report, or a single day
  /// 2026-W31              a range that is exactly one ISO week
  /// 20260701-20260730     any other range
  /// ```
  ///
  /// The ISO-week form is used only when the range genuinely is that week
  /// ([ReportPeriodPolicy.isExactIsoWeek]) — G-L5's own example is
  /// `kartu_stok_R1_2026-W31.pdf`, and a Monday-to-Saturday range named `2026-W31`
  /// would label a file for a day it does not contain.
  static String periodToken(ReportPeriod period, {required bool isAsOf}) {
    if (isAsOf || period.isSingleDay) return _compact(period.periodEnd);
    if (ReportPeriodPolicy.isExactIsoWeek(period)) {
      return ReportPeriodPolicy.isoWeekOf(period).label;
    }
    return '${_compact(period.periodStart)}-${_compact(period.periodEnd)}';
  }

  /// The whole name. The only function anything outside this class calls.
  ///
  /// Throws [InvalidReportFileNameFailure] if the assembled name still fails
  /// [isSafe] — which it should not be able to, because every token went through
  /// [sanitizeToken]. The check exists so "should not be able to" is enforced
  /// rather than asserted.
  static String build({
    required ReportType reportType,
    required ReportFormat format,
    required ReportScopeType scopeType,
    required ReportPeriod period,
    MasterBranch? branch,
    MasterRoom? room,
    MasterCategory? category,
  }) {
    final buffer = StringBuffer()
      ..write(reportType.dbValue)
      ..write('_')
      ..write(locationToken(scopeType: scopeType, branch: branch, room: room))
      ..write('_')
      ..write(periodToken(period, isAsOf: reportType.isAsOfReport));
    if (category != null) {
      buffer
        ..write('_')
        ..write(sanitizeToken(category.name));
    }
    buffer.write(format.fileExtension);

    final fileName = buffer.toString();
    if (!isSafe(fileName)) {
      throw InvalidReportFileNameFailure(
        'Nama file laporan tidak valid.',
        fileName: fileName,
      );
    }
    return fileName;
  }

  /// Folds one piece of free text into a token that can never be a path.
  ///
  /// In order: trim, collapse whitespace runs to `-`, drop everything outside
  /// `A-Z a-z 0-9 - .`, collapse `-` runs, remove every `.` that is not between two
  /// alphanumerics (which is what makes `..` unrepresentable), trim leading and
  /// trailing separators, cap the length, and fall back to `DATA` if nothing
  /// survived. A token is never empty, because an empty token would collapse two
  /// `_` separators and change the name's shape.
  static String sanitizeToken(String raw) {
    var token = raw.trim();
    // Control characters first: a `\n` inside a name is not a display problem,
    // it is a way to forge a second line in a log.
    token = token.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    token = token.replaceAll(RegExp(r'\s+'), '-');
    token = token.replaceAll(RegExp(r'[^A-Za-z0-9\-.]'), '');
    // `..` — and any longer run — cannot survive: a dot is kept only when it sits
    // between two alphanumerics.
    token = token.replaceAllMapped(
      RegExp(r'\.+'),
      (match) =>
          match.start > 0 &&
              match.end < token.length &&
              _isAlphanumeric(token[match.start - 1]) &&
              _isAlphanumeric(token[match.end])
          ? '.'
          : '-',
    );
    token = token.replaceAll(RegExp(r'-{2,}'), '-');
    token = token.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    if (token.length > maxTokenLength) {
      token = token.substring(0, maxTokenLength);
      token = token.replaceAll(RegExp(r'[-.]+$'), '');
    }
    return token.isEmpty ? 'DATA' : token;
  }

  /// Whether [fileName] is a plain, addressable file name.
  ///
  /// Refuses path separators (both kinds — a Windows build is a supported target),
  /// `..` anywhere, control characters, an empty name, a leading dot, and anything
  /// over 255 characters.
  static bool isSafe(String fileName) {
    if (fileName.isEmpty || fileName.length > 255) return false;
    if (fileName.contains('/') || fileName.contains(r'\')) return false;
    if (fileName.contains('..')) return false;
    if (fileName.startsWith('.')) return false;
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(fileName)) return false;
    return true;
  }

  static bool _isAlphanumeric(String character) =>
      RegExp(r'^[A-Za-z0-9]$').hasMatch(character);

  /// `20260730`.
  static String _compact(DateTime date) =>
      DateOnly.formatIso(date).replaceAll('-', '');
}
