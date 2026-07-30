/// Helpers for the tests that assert things about the **source** rather than about
/// runtime behaviour.
///
/// Some invariants no runtime test can catch, because breaking them still compiles
/// and still passes: a widget reaching past the repository into a DAO, a quantity path
/// that quietly grows a `double`, a `:id` route that ships without a guard. Those are
/// found in code review once and then slowly reintroduced; asserted here they fail the
/// build instead.
library;

import 'dart:io';

/// Every `.dart` file under [path], which may itself be a file.
List<String> dartFilesUnder(String path) {
  final file = File(path);
  if (file.existsSync()) return [path];

  return Directory(path)
      .listSync(recursive: true)
      .whereType<File>()
      .where((entry) => entry.path.endsWith('.dart'))
      .map((entry) => entry.path)
      .toList(growable: false);
}

/// The full text of one source file.
String readLibrarySource(String path) => File(path).readAsStringSync();

/// [path]'s source with `//` comment lines removed.
///
/// So a rule can be *explained* in prose without the test that enforces it reading the
/// explanation as a violation — several of these files discuss the very identifiers
/// they forbid.
String readCodeOnly(String path) => readLibrarySource(
  path,
).split('\n').where((line) => !line.trimLeft().startsWith('//')).join('\n');

/// Import targets of one file, ignoring comments.
List<String> importsOf(String path) {
  final pattern = RegExp(r"^\s*import\s+'([^']+)'", multiLine: true);
  return pattern
      .allMatches(readLibrarySource(path))
      .map((match) => match.group(1)!)
      .toList(growable: false);
}
