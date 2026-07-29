import 'package:aish_warehouse/app/app.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_context.dart';

void main() {
  late TestContext context;

  setUp(() {
    context = TestContext.create();
  });

  tearDown(() => context.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // The app never talks to a device database in tests.
        overrides: [appDatabaseProvider.overrideWithValue(context.database)],
        child: const AishWarehouseApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Disposes the provider scope inside the test body. Drift schedules a timer
  /// when a query stream is cancelled, and flutter_test verifies that no timer
  /// is pending before `tearDown` runs — so this cannot move into a teardown.
  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('halaman pengembangan tampil dengan empty state', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Aish Warehouse'), findsOneWidget);
    expect(find.text('Belum ada data'), findsOneWidget);
    expect(find.text('Jalankan Seed Pengembangan'), findsOneWidget);
    expect(find.text('Saldo Warehouse Pusat'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('tombol seed mengisi ringkasan dan saldo warehouse', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Jalankan Seed Pengembangan'));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada data'), findsNothing);
    expect(find.text('Cabang'), findsOneWidget);
    expect(find.text('Ruangan'), findsOneWidget);
    expect(find.text('Barang'), findsOneWidget);
    expect(find.text('Masker Bedah 3 Ply'), findsOneWidget);

    await disposeApp(tester);
  });
}
