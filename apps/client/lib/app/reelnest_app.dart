import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/sources/application/emby_providers.dart';
import '../features/sources/application/automatic_scan_providers.dart';
import '../features/metadata/application/automatic_tmdb_providers.dart';

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
    ref.read(automaticScanIntervalProvider);
    ref.read(automaticTmdbMatcherProvider);
    unawaited(ref.read(embyOfflineProvider).start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    releaseWindowsTextInputOnFocusLoss(state);
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

/// Windows Flutter currently keeps its legacy IME context attached when a
/// window loses native focus. Leaving an active TextField connected across a
/// long focus loss can make the restored window accept ordinary key events but
/// stop receiving Chinese/Japanese/Korean composition messages. Disconnect the
/// framework text client while the desktop window is inactive; the next click
/// reconnects it with the current input method.
@visibleForTesting
void releaseWindowsTextInputOnFocusLoss(AppLifecycleState state) {
  if (!Platform.isWindows) return;
  if (state == AppLifecycleState.inactive ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused) {
    FocusManager.instance.primaryFocus?.unfocus();
  }
}
