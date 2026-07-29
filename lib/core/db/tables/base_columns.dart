import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';

final _uuid = Uuid();

/// Client-side primary key generator. Public because drift copies this
/// reference into the generated part file of `app_database.dart`.
String newUuidV4() => _uuid.v4();

/// Timestamp used for every `created_at` / `updated_at` default.
DateTime nowUtc() => DateTime.now().toUtc();

/// Columns every business table must carry (specification §2).
///
/// * `id` — client generated UUID v4 so offline devices never collide.
/// * `created_at` / `updated_at` — stored in UTC.
/// * `deleted_at` — soft delete; business data is never hard deleted.
/// * `sync_status` — new local rows start as `pending`.
mixin BusinessColumns on Table {
  TextColumn get id => text().clientDefault(newUuidV4)();

  DateTimeColumn get createdAt => dateTime().clientDefault(nowUtc)();

  DateTimeColumn get updatedAt => dateTime().clientDefault(nowUtc)();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus => text()
      .map(const SyncStatusConverter())
      .clientDefault(() => SyncStatus.pending.dbValue)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
