import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../platform/transient_file_access.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/data/source_repository.dart';
import '../domain/transient_playback_target.dart';
import 'playback_providers.dart';
import 'transient_playback_resolver.dart';

abstract interface class TransientPlaybackLauncher {
  Future<void> openFile(String path, {Uint8List? securityBookmark});
  Future<void> openStream(String value);
}

final transientPlaybackLauncherProvider = Provider<TransientPlaybackLauncher>((
  ref,
) {
  final launcher = ref.watch(playbackLauncherProvider);
  return TransientPlaybackService(
    sources: ref.watch(sourceRepositoryProvider),
    openLibrary: launcher.open,
    openTransient: (target) {
      if (launcher is! PlaybackTargetLauncher) {
        throw const SourceFailure('当前环境无法打开独立播放器。');
      }
      return launcher.openTransient(target);
    },
  );
});

class TransientPlaybackService implements TransientPlaybackLauncher {
  TransientPlaybackService({
    required this.sources,
    required this.openLibrary,
    required this.openTransient,
  });
  final SourceRepository sources;
  final Future<void> Function(MediaIdentity) openLibrary;
  final Future<void> Function(TransientPlaybackTarget) openTransient;
  Future<void> _pending = Future.value();
  Future<void> _serialize(Future<void> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> openFile(String path, {Uint8List? securityBookmark}) =>
      _serialize(() async {
        var target = TransientPlaybackTarget.file(path);
        final access = await TransientFileAccess.acquire(
          target.location,
          bookmark: securityBookmark,
        );
        try {
          await target.validate();
          target = target.withBookmark(access.bookmark);
          final identity = await indexedFileIdentity(sources, target.location);
          if (identity != null && access.bookmark == null) {
            await openLibrary(identity);
          } else {
            await openTransient(target);
          }
        } finally {
          await access.release();
        }
      });
  @override
  Future<void> openStream(String value) =>
      _serialize(() => openTransient(TransientPlaybackTarget.stream(value)));
}
