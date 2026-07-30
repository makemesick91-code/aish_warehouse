import 'package:aish_warehouse/app/router.dart';
import 'package:aish_warehouse/app/theme.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/opname/presentation/pages/opname_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` — the type of a ProviderScope override — lives here rather than in
// the main barrel file in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_context.dart';

/// A session controller pinned to one user, so a test acts as exactly the role
/// it means to and never depends on which user the seed happened to create
/// first.
///
/// Public because the provider-level access tests build their own
/// `ProviderContainer` rather than pumping a widget.
class FixedSessionController extends DevelopmentSessionController {
  FixedSessionController(this._user);

  final MasterUser _user;

  @override
  Future<CurrentUserSession?> build() async => CurrentUserSession(_user);
}

/// Pumps [child] with the in-memory database and a fixed acting user.
///
/// Widget tests never touch a device database: the same [TestContext] the
/// domain tests use is injected through `appDatabaseProvider`, which is the
/// single place the app obtains its database.
///
/// Named for the app rather than for one feature, because Stok Opname and Purchase
/// Request need exactly the same scaffolding. [pumpOpnameWidget] is kept as the
/// original name so the Milestone 2 tests read as they did.
Future<void> pumpAppWidget(
  WidgetTester tester, {
  required TestContext context,
  required MasterUser actingAs,
  required Widget child,
  List<Override> overrides = const <Override>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(context.database),
        currentSessionProvider.overrideWith(
          () => FixedSessionController(actingAs),
        ),
        ...overrides,
      ],
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// The original name of [pumpAppWidget].
Future<void> pumpOpnameWidget(
  WidgetTester tester, {
  required TestContext context,
  required MasterUser actingAs,
  required Widget child,
  List<Override> overrides = const <Override>[],
}) => pumpAppWidget(
  tester,
  context: context,
  actingAs: actingAs,
  child: child,
  overrides: overrides,
);

/// Pumps the **real** app — router, redirect and route guards included — and
/// navigates straight to [location].
///
/// This is what makes the IDOR assertions mean something. Pumping a page
/// directly with an id bypasses exactly the layer under test; typing the URL is
/// the attack, so the test has to type the URL.
Future<ProviderContainer> pumpAppAt(
  WidgetTester tester, {
  required TestContext context,
  required MasterUser actingAs,
  required String location,
  List<Override> overrides = const <Override>[],
}) async {
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(context.database),
      currentSessionProvider.overrideWith(
        () => FixedSessionController(actingAs),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Scrolls the list of counted lines until [finder] is built.
///
/// The opname form is a lazy `ListView.builder`, so a line below the fold does
/// not exist in the tree yet. The list is addressed by its key because the page
/// holds three scrollables — the category chips, the search field's internal
/// editable, and this one.
Future<Finder> revealLine(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return finder;
  await tester.scrollUntilVisible(
    finder,
    200,
    // `.first` because each card's text fields carry their own editable
    // scrollable; the list's own is the outermost, and therefore first.
    scrollable: find
        .descendant(
          of: find.byKey(opnameLineListKey),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  return finder;
}

/// The card of one item on the form, scrolled into view.
Future<Finder> revealCard(WidgetTester tester, String itemName) async {
  await revealLine(tester, find.text(itemName));
  return find
      .ancestor(of: find.text(itemName), matching: find.byType(Card))
      .first;
}

/// Tears the widget tree down inside the test body.
///
/// Drift schedules a timer when a query stream is cancelled and flutter_test
/// checks for pending timers before `tearDown` runs, so this cannot move into
/// a teardown callback.
Future<void> disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

/// Sizes the test surface like the clinic tablets the app is built for.
///
/// The default 800×600 test window is smaller than any device in use, and a document
/// form is a tall thing: with the default surface almost every line card sits below the
/// fold in a lazy `ListView` and is simply not built, which reads as "the widget is
/// missing" rather than "the widget is off screen". A realistic portrait tablet is both
/// more honest and still narrow enough for a horizontal overflow to show up.
void useTabletSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1024, 1366);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Scrolls [finder] into view inside the scrollable identified by [listKey].
///
/// A lazy `ListView` has not built what is below the fold, so a finder for it matches
/// nothing until the list is scrolled. Addressing the list by key matters because these
/// screens hold several scrollables — the category chips scroll horizontally, and every
/// text field has its own editable scrollable.
Future<Finder> revealInList(
  WidgetTester tester,
  Finder finder, {
  required Key listKey,
  double delta = 300,
}) async {
  if (finder.evaluate().isNotEmpty) return finder;
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find
        .descendant(of: find.byKey(listKey), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
  return finder;
}
