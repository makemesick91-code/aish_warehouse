import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String databaseFileName = 'aish_warehouse.sqlite';

/// Opens the on-device database lazily, so no file system work happens until
/// the first query is actually issued.
QueryExecutor openAppDatabaseConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, databaseFileName));
    return NativeDatabase.createInBackground(file);
  });
}
