import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract interface class SyncPayloadHasher {
  String hash(Object? value);
}

final class Sha256SyncPayloadHasher implements SyncPayloadHasher {
  const Sha256SyncPayloadHasher();

  @override
  String hash(Object? value) =>
      sha256.convert(utf8.encode(canonicalJson(value))).toString();

  static String canonicalJson(Object? value) =>
      jsonEncode(_canonicalize(value));

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    throw ArgumentError.value(
      value,
      'value',
      'Unsupported canonical JSON value',
    );
  }
}
