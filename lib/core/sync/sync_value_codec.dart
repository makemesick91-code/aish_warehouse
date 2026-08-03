import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// The storage shape of one column, as far as reconciliation cares.
enum SyncColumnKind { boolean, dateTime, integer, real, text, other }

/// Translates between a server JSON payload and the values this Drift schema
/// actually stores.
///
/// The column kinds are read from the generated table metadata rather than
/// guessed from the JSON. That matters in both directions: `is_active` arrives
/// as a JSON boolean and has to be stored as an integer, and `expiry_date`
/// arrives as `"2027-12-31"` while `posted_at` arrives as a full timestamp —
/// both are `DateTimeColumn` here, and a string comparison between the two
/// encodings would report a difference where there is none and hand the merge to
/// the wrong side.
final class SyncValueCodec {
  SyncValueCodec(AppDatabase database)
    : _sqlTypes = database.typeMapping,
      _kinds = {
        for (final table in database.allTables)
          table.actualTableName: {
            for (final column in table.$columns) column.name: _kindOf(column),
          },
      };

  final SqlTypes _sqlTypes;
  final Map<String, Map<String, SyncColumnKind>> _kinds;

  static SyncColumnKind _kindOf(GeneratedColumn<Object> column) {
    final type = column.type;
    if (type == DriftSqlType.bool) return SyncColumnKind.boolean;
    if (type == DriftSqlType.dateTime) return SyncColumnKind.dateTime;
    if (type == DriftSqlType.int) return SyncColumnKind.integer;
    if (type == DriftSqlType.bigInt) return SyncColumnKind.integer;
    if (type == DriftSqlType.double) return SyncColumnKind.real;
    if (type == DriftSqlType.string) return SyncColumnKind.text;
    return SyncColumnKind.other;
  }

  SyncColumnKind? kindOf(String table, String column) => _kinds[table]?[column];

  Iterable<String> columnsOf(String table) =>
      _kinds[table]?.keys ?? const <String>[];

  bool hasColumn(String table, String column) =>
      _kinds[table]?.containsKey(column) ?? false;

  /// Canonical Dart form of a value, whatever encoding it arrived in.
  ///
  /// Both sides of every merge comparison pass through here, so a server `true`,
  /// a stored `1` and a Dart `true` are one value rather than three.
  Object? canonical(String table, String column, Object? value) {
    if (value == null) return null;
    return switch (kindOf(table, column)) {
      SyncColumnKind.boolean => switch (value) {
        final bool boolean => boolean,
        final num number => number != 0,
        final String text => text == '1' || text.toLowerCase() == 'true',
        _ => value,
      },
      SyncColumnKind.dateTime => _asDateTime(value),
      SyncColumnKind.integer => value is num ? value.toInt() : value,
      SyncColumnKind.real => value is num ? value.toDouble() : value,
      SyncColumnKind.text => value is String ? value : value.toString(),
      _ => value,
    };
  }

  /// The value as this database would physically store it.
  ///
  /// Encoding goes through Drift's own type mapping rather than a hand-rolled
  /// `toIso8601String`, so a timestamp written by a pull is byte-identical to
  /// one written by a repository. Anything else would make a pulled row compare
  /// unequal to a locally written one that means the same thing — and every
  /// merge decision downstream is a comparison.
  Object? sqlValue(String table, String column, Object? value) =>
      _sqlTypes.mapToSqlVariable(canonical(table, column, value));

  /// Canonicalises a whole row against one table, dropping any key the local
  /// schema does not have. A server that grows a column must not make an older
  /// build fail its batch.
  Map<String, Object?> canonicalRow(String table, Map<String, Object?> row) => {
    for (final entry in row.entries)
      if (hasColumn(table, entry.key))
        entry.key: canonical(table, entry.key, entry.value),
  };

  static DateTime? _asDateTime(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt() * 1000,
        isUtc: true,
      );
    }
    if (value is! String || value.isEmpty) return null;
    // A Postgres `date` arrives without a time part. Reading it as local
    // midnight would move `expiry_date` across a day boundary in Asia/Makassar
    // and change every FEFO and expiry comparison that depends on it.
    final parsed = value.contains('T') || value.contains(' ')
        ? DateTime.tryParse(value)
        : DateTime.tryParse('${value}T00:00:00Z');
    return parsed?.toUtc();
  }
}
