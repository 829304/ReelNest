import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../features/playback/application/playback_providers.dart';
import '../features/playback/presentation/player_window_app.dart';
import '../features/sources/application/source_providers.dart';
import 'reelnest_app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    runApp(const ProviderScope(child: ReelNestApp()));
    return;
  }
  await windowManager.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  final args = window.arguments.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(window.arguments) as Map<String, dynamic>;
  if (args['type'] == 'player') {
    runApp(
      ProviderScope(
        child: PlayerWindowApp(window: window, arguments: args),
      ),
    );
    return;
  }
  final container = ProviderContainer();
  await windowManager.setPreventClose(true);
  windowManager.addListener(_MainWindowClose(container));
  await window.setWindowMethodHandler((call) async {
    if (call.method == 'playbackChanged') {
      container.invalidate(playbackRecordProvider);
      return null;
    }
    throw UnsupportedError('Unknown main window method');
  });
  runApp(
    UncontrolledProviderScope(container: container, child: const ReelNestApp()),
  );
}

class _MainWindowClose with WindowListener {
  _MainWindowClose(this.container);
  final ProviderContainer container;
  bool closing = false;
  @override
  void onWindowClose() => unawaited(_close());
  Future<void> _close() async {
    if (closing) return;
    closing = true;
    try {
      for (final window in await WindowController.getAll()) {
        if (window.arguments.isEmpty) continue;
        final args = jsonDecode(window.arguments) as Map<String, dynamic>;
        if (args['type'] != 'player') continue;
        try {
          await window
              .invokeMethod('close')
              .timeout(const Duration(seconds: 30));
        } catch (_) {
          /* Window destruction may retire its reply channel. */
        }
        if ((await WindowController.getAll()).any(
          (w) => w.windowId == window.windowId,
        )) {
          return; // User kept the player open after a checkpoint failure.
        }
      }
      await container.read(sourceRepositoryProvider).close();
      container.dispose();
      // Request a native close after the channel reply has returned. Posting
      // WM_QUIT via destroy skips the normal HWND shutdown sequence on Windows.
      windowManager.removeListener(this);
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } finally {
      closing = false;
    }
  }
}
