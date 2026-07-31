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

/// Every document-specific route builder in `router.dart` that is **not** wrapped
/// in a guard.
///
/// ### Why this replaced a count
///
/// Until Milestone 11 the invariant *"every `:id` route is guarded"* was checked
/// by comparing two counts: occurrences of `pathParameters['id']` against
/// occurrences of `…RouteGuard(`. That worked while every guarded route used a
/// per-document guard, and it broke the moment a **section** guard covered an
/// `:id` route — which `/master/{entity}/{id}` and `/imports/{id}` are the first
/// to do, because a Super Admin's reach over master data has no per-document
/// scope to check (G-M1).
///
/// Widening the count to include section guards would have made the totals
/// meaningless: a section guard also wraps routes that carry no id at all. So the
/// check became the thing the count was standing in for — for **each** id read,
/// is there a guard in the builder that reads it?
///
/// The shape every route in this application uses is:
///
/// ```dart
/// builder: (context, state) {
///   final id = state.pathParameters['id']!;
///   return SomethingGuard(…);
/// }
/// ```
///
/// so the guard appears within a few lines *after* the read. [window] is how far
/// after; the default is generous enough for the longest builder in the file and
/// far short of the next route.
///
/// Returns the offending snippets, so a failure names what is unguarded rather
/// than only that something is.
List<String> unguardedIdRoutes(
  String routerSource, {
  List<String> idParameters = const ['id', 'deliveryOrderId'],
  int window = 400,
}) {
  final pattern = RegExp("pathParameters\\['(?:${idParameters.join('|')})'\\]");
  final guard = RegExp(r'\w*(?:RouteGuard|SectionGuard)\(');
  final offenders = <String>[];

  for (final match in pattern.allMatches(routerSource)) {
    final end = (match.end + window).clamp(0, routerSource.length);
    final following = routerSource.substring(match.end, end);
    if (guard.hasMatch(following)) continue;
    final start = (match.start - 120).clamp(0, routerSource.length);
    offenders.add(routerSource.substring(start, match.end).trim());
  }
  return offenders;
}
