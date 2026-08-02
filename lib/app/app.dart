import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase/supabase_client_provider.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import 'router.dart';
import 'theme.dart';

class AishWarehouseApp extends ConsumerStatefulWidget {
  const AishWarehouseApp({super.key});

  @override
  ConsumerState<AishWarehouseApp> createState() => _AishWarehouseAppState();
}

class _AishWarehouseAppState extends ConsumerState<AishWarehouseApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(supabaseConfigProvider).enabled) {
      unawaited(ref.read(authStateProvider.notifier).revalidate());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Aish Warehouse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
