import 'package:aish_warehouse/core/config/supabase_config.dart';
import 'package:aish_warehouse/core/db/app_database.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/widgets/offline_banner.dart';
import 'package:aish_warehouse/core/widgets/sync_status_tag.dart';
import 'package:aish_warehouse/features/auth/presentation/providers/auth_providers.dart';
import 'package:aish_warehouse/features/sync/presentation/pages/sync_center_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in const <(SyncPresentationState, String)>[
    (SyncPresentationState.offline, 'Offline — perubahan akan disinkronkan'),
    (SyncPresentationState.pending, 'Perubahan menunggu sinkronisasi'),
    (SyncPresentationState.syncing, 'Sedang menyinkronkan…'),
    (SyncPresentationState.synced, 'Semua perubahan telah dikonfirmasi server'),
    (SyncPresentationState.conflict, 'Ada konflik yang perlu ditinjau'),
    (
      SyncPresentationState.retryableError,
      'Sinkronisasi tertunda — akan dicoba lagi',
    ),
  ]) {
    testWidgets('offline banner renders ${entry.$1.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OfflineBanner(state: entry.$1)),
        ),
      );
      expect(find.text(entry.$2), findsOneWidget);
    });
  }

  testWidgets('document status explains final pending and actor dependency', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SyncStatusTag(status: SyncStatus.pending, finalDocument: true),
              SyncStatusTag(
                status: SyncStatus.pending,
                waitingForOriginalActor: true,
              ),
              SyncStatusTag(
                status: SyncStatus.pending,
                originalActorUnknown: true,
              ),
              SyncStatusTag(
                status: SyncStatus.pending,
                dependencyBlocked: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Sudah diposting di perangkat ini, menunggu konfirmasi server.',
      ),
      findsOneWidget,
    );
    expect(find.text('Menunggu akun pembuat'), findsOneWidget);
    expect(
      find.text(
        'Tidak dapat disinkronkan karena akun pembuat data lama tidak dapat ditentukan.',
      ),
      findsOneWidget,
    );
    expect(find.text('Menunggu data terkait'), findsOneWidget);
  });

  testWidgets('sync center fits a narrow screen without exposing local paths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          currentDomainUserProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: SyncCenterPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pusat Sinkronisasi'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(SupabaseConfig.expectedSchemaRevision),
      200,
    );
    expect(find.text(SupabaseConfig.expectedSchemaRevision), findsOneWidget);
    expect(find.textContaining('/home/'), findsNothing);
    expect(tester.takeException(), isNull);

    // Dispose the provider subscriptions while fake time is still under this
    // test's control, then let Drift drain its zero-duration close timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  });
}
