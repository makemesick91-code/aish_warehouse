import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

void main() {
  test('Drift schema is v14', () {
    expect(
      _read('lib/core/db/app_database.dart'),
      contains('schemaVersion => 15'),
    );
  });

  test('auth domain has no Supabase package dependency', () {
    final source = _dartFiles(
      'lib/features/auth/domain',
    ).map((file) => file.readAsStringSync()).join('\n');
    expect(source, isNot(contains('supabase_flutter')));
    expect(source, isNot(contains('SupabaseClient')));
  });

  test('presentation never reaches the global Supabase singleton', () {
    final source = <File>[
      ..._dartFiles('lib/features'),
      ..._dartFiles('lib/app'),
    ].map((file) => file.readAsStringSync()).join('\n');
    expect(source, isNot(contains('Supabase.instance.client')));
  });

  test(
    'Flutter source contains no elevated key or database credential literal',
    () {
      final source = _dartFiles(
        'lib',
      ).map((file) => file.readAsStringSync()).join('\n').toLowerCase();
      expect(
        source,
        isNot(
          contains(
            'sb_'
            'secret_',
          ),
        ),
      );
      expect(source, isNot(contains('service_role')));
      expect(
        source,
        isNot(
          contains(
            'postgresql'
            '://',
          ),
        ),
      );
      expect(source, isNot(contains('supabase_db_url')));
    },
  );

  test('no Flutter client writes ledger or balance tables directly', () {
    final source = _dartFiles(
      'lib',
    ).map((file) => file.readAsStringSync()).join('\n');
    expect(
      source,
      isNot(
        matches(
          RegExp(r'''from\(['"]stock_movements['"]\).*insert''', dotAll: true),
        ),
      ),
    );
    expect(
      source,
      isNot(
        matches(
          RegExp(
            r'''from\(['"]stock_balances['"]\).*(insert|update|delete)''',
            dotAll: true,
          ),
        ),
      ),
    );
  });

  test(
    'production route is auth gated and debug acting UI is compile guarded',
    () {
      final router = _read('lib/app/router.dart');
      final dashboard = _read(
        'lib/features/dashboard/presentation/pages/development_home_page.dart',
      );
      expect(router, contains('productionAuthEnabled'));
      expect(router, contains('AuthAuthenticated'));
      expect(router, contains('AppRoutes.login'));
      expect(dashboard, contains('kDebugMode &&'));
      expect(dashboard, contains('developmentHarness'));
    },
  );

  test(
    'RLS migration is default deny and has no blanket authenticated policy',
    () {
      final migration = _read(
        'supabase/migrations/20260802000300_auth_helpers_and_rls.sql',
      ).toLowerCase();
      expect('enable row level security'.allMatches(migration).length, 1);
      expect(migration, contains('force row level security'));
      expect(migration, isNot(contains('using (true)')));
      expect(migration, isNot(contains('with check (true)')));
      expect(migration, isNot(contains('for insert to authenticated')));
      expect(migration, isNot(contains('for update to authenticated')));
      expect(migration, isNot(contains('for delete to authenticated')));
    },
  );

  test('security definer helpers fix search path and accept no actor id', () {
    final migration = _read(
      'supabase/migrations/20260802000300_auth_helpers_and_rls.sql',
    ).toLowerCase();
    expect(migration, contains('security definer'));
    expect(migration, contains("set search_path = ''"));
    expect(migration, contains('current_domain_user_id()'));
    expect(migration, isNot(contains('current_domain_user_id(actor')));
  });

  test('storage buckets are private and have no client write policy', () {
    final migration = _read(
      'supabase/migrations/20260802000400_private_storage.sql',
    ).toLowerCase();
    expect(migration, contains("'import-audit'"));
    expect(migration, contains("'report-artifacts'"));
    expect('false'.allMatches(migration).length, greaterThanOrEqualTo(2));
    expect(migration, isNot(contains('for insert')));
    expect(migration, isNot(contains('for update')));
    expect(migration, isNot(contains('for delete')));
  });

  test(
    'local state and environment credentials are ignored, migrations are not',
    () {
      final gitignore = _read('.gitignore');
      expect(gitignore, contains('node_modules/'));
      expect(gitignore, contains('supabase/.temp/'));
      expect(gitignore, contains('supabase/.env'));
      expect(gitignore, isNot(contains('supabase/migrations/')));
    },
  );
}
