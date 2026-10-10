import 'dart:convert';
import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../sources/application/source_providers.dart';
import '../data/playback_repository.dart';
import '../domain/playback_record.dart';

final playbackRepositoryProvider = Provider<PlaybackRepository>(
  (ref) => PlaybackRepository(ref.watch(sourceRepositoryProvider).database),
);
final playbackRecordProvider = FutureProvider.autoDispose
    .family<PlaybackRecord, MediaIdentity>((ref, id) {
      ref.watch(sourceChangesProvider);
      return ref.watch(playbackRepositoryProvider).read(id);
    });

abstract interface class PlaybackLauncher {
  Future<void> open(MediaIdentity identity);
}

final playbackLauncherProvider = Provider<PlaybackLauncher>(
  (_) => DesktopPlaybackLauncher(),
);

/// Main and player windows have separate engines. Keep one video window and
/// send only media identity; paths and access checks are resolved afresh there.
class DesktopPlaybackLauncher implements PlaybackLauncher {
  Future<void> _operations = Future.value();
  @override
  Future<void> open(MediaIdentity identity) {
    final next = _operations.then((_) => _open(identity));
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> _open(MediaIdentity identity) async {
    final current = await WindowController.fromCurrentEngine();
    final payload = {
      'type': 'player',
      'sourceId': identity.sourceId,
      'localId': identity.localId,
      'mainWindowId': current.windowId,
    };
    for (final window in await WindowController.getAll()) {
      if (window.arguments.isEmpty) continue;
      final args = jsonDecode(window.arguments) as Map<String, dynamic>;
      if (args['type'] == 'player') {
        await _waitForChannel(window);
        await window
            .invokeMethod('play', payload)
            .timeout(const Duration(seconds: 30));
        await window.show();
        return;
      }
    }
    final created = await WindowController.create(
      WindowConfiguration(arguments: jsonEncode(payload), hiddenAtLaunch: true),
    );
    await _waitForChannel(created);
    // The player configures its close handler and geometry before showing.
  }

  Future<void> _waitForChannel(WindowController window) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      try {
        await window
            .invokeMethod('status')
            .timeout(const Duration(milliseconds: 500));
        return;
      } on WindowChannelException {
        // Engine and plugin registration are asynchronous after native creation.
      } on TimeoutException {
        // Retry the readiness probe without duplicating a playback command.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('播放器窗口未能启动，请重试。');
  }
}
