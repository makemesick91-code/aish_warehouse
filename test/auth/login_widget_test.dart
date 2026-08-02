import 'package:aish_warehouse/core/config/app_environment.dart';
import 'package:aish_warehouse/core/config/supabase_config.dart';
import 'package:aish_warehouse/core/supabase/supabase_client_provider.dart';
import 'package:aish_warehouse/features/auth/domain/models/auth_models.dart';
import 'package:aish_warehouse/features/auth/presentation/pages/login_page.dart';
import 'package:aish_warehouse/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_fakes.dart';

const _config = SupabaseConfig(
  environment: AppEnvironment.development,
  enabled: true,
  url: 'http://127.0.0.1:54321',
  publishableKey: 'sb_publishable_test',
);

ProviderContainer _container(FakeAuthRepository repository) =>
    ProviderContainer(
      overrides: [
        supabaseConfigProvider.overrideWithValue(_config),
        authRepositoryProvider.overrideWithValue(repository),
        supabaseHealthGatewayProvider.overrideWithValue(FakeHealthGateway()),
      ],
    );

void main() {
  testWidgets(
    'form has password visibility and no public signup or role picker',
    (tester) async {
      final repository = FakeAuthRepository();
      final container = _container(repository);
      addTearDown(container.dispose);
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LoginPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aish Warehouse'), findsOneWidget);
      expect(find.byKey(const ValueKey('loginEmail')), findsOneWidget);
      expect(find.byKey(const ValueKey('loginPassword')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('togglePasswordVisibility')),
        findsOneWidget,
      );
      expect(find.text('Daftar'), findsNothing);
      expect(find.textContaining('Pilih peran'), findsNothing);
      expect(find.textContaining('Pilih cabang'), findsNothing);

      final password = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('loginPassword')),
          matching: find.byType(EditableText),
        ),
      );
      expect(password.obscureText, isTrue);
      await tester.tap(find.byKey(const ValueKey('togglePasswordVisibility')));
      await tester.pump();
      final visible = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('loginPassword')),
          matching: find.byType(EditableText),
        ),
      );
      expect(visible.obscureText, isFalse);
    },
  );

  testWidgets('invalid credentials render only the safe Indonesian message', (
    tester,
  ) async {
    final repository = FakeAuthRepository()
      ..signInError = const AuthInvalidCredentialsFailure();
    final container = _container(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('loginEmail')),
      'unknown@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('loginPassword')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const ValueKey('loginSubmit')));
    await tester.pumpAndSettle();

    expect(find.text('Email atau kata sandi tidak sesuai.'), findsOneWidget);
    expect(find.textContaining('AuthException'), findsNothing);
  });

  testWidgets('narrow screen scrolls without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeAuthRepository();
    final container = _container(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
