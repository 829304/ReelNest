import 'dart:async';

import 'package:flutter/material.dart';

import '../features/sources/application/emby_providers.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/application/appearance_controller.dart';
import '../ui/theme/app_theme.dart';
import 'router.dart';

class ReelNestApp extends ConsumerStatefulWidget {
  const ReelNestApp({super.key});
  @override
  ConsumerState<ReelNestApp> createState() => _ReelNestAppState();
}

class _ReelNestAppState extends ConsumerState<ReelNestApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(embyOfflineProvider).start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(embyOfflineProvider).request();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '映栖 · ReelNest',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(appearanceProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
