import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../player/video_engine.dart';
import '../../sources/data/source_repository.dart';
import '../data/playback_repository.dart';

/// Owns a single engine; transitions and checkpoints are serialized. No widget
/// sends native commands or writes SQLite directly.
class PlaybackSession extends ChangeNotifier {
  PlaybackSession({
    required this.sources,
    required this.records,
    required this.createEngine,
    this.checkpointInterval = const Duration(seconds: 5),
  });
  final SourceRepository sources;
  final PlaybackRepository records;
  final VideoEngine Function() createEngine;
  final Duration checkpointInterval;
  VideoEngine? engine;
  IndexedMedia? item;
  VideoClock clock = const VideoClock();
  final timeline = ValueNotifier<VideoClock>(const VideoClock());
  bool loading = false;
  String? error;
  String? saveError;
  StreamSubscription<VideoClock>? _subscription;
  Timer? _checkpoint;
  Future<void> _operations = Future.value();
  Future<void> _writes = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  bool _hasClock = false;
  bool _completedSaved = false;

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> open(MediaIdentity identity) => _serialize(() async {
    if (_closed || _closing != null) return;
    if (engine != null) {
      try {
        await engine!.pause();
      } catch (_) {
        // Preserve the last valid clock even when the decoder has failed.
      }
      await save(completed: clock.completed);
      if (saveError != null) {
        notifyListeners();
        return;
      }
    }
    await _release(save: false);
    loading = true;
    error = null;
    saveError = null;
    item = null;
    clock = const VideoClock();
    _hasClock = false;
    _completedSaved = false;
    notifyListeners();
    try {
      final selected = await sources.media(identity);
      final source = await sources.source(identity.sourceId);
      if (!source.kind.isFileSource ||
          selected.isSeries ||
          selected.type == 'music' ||
          selected.type == 'photo') {
        throw const SourceFailure('请选择一个本地视频文件播放。');
      }
      final path = p.normalize(
        p.joinAll([source.location, ...p.posix.split(identity.localId)]),
      );
      if (!p.isWithin(source.location, path) ||
          !await sources.isReachable(source) ||
          !await File(path).exists()) {
        throw const SourceFailure('媒体文件不存在，可能是 NAS 未挂载、移动硬盘断开，或文件已被移动。');
      }
      final record = await records.read(identity);
      if (_closed || _closing != null) return;
      item = selected;
      final current = engine = createEngine();
      _subscription = current.changes.listen(
        _observe,
        onError: (Object e) {
          error = '视频播放失败，请检查文件或重新打开。';
          loading = false;
          notifyListeners();
        },
      );
      notifyListeners();
      await current
          .open(path, record.resumePosition)
          .timeout(const Duration(seconds: 25));
      if (_closed || _closing != null) return;
      loading = false;
      _observe(current.clock);
      _startCheckpoints();
    } catch (e) {
      error = e is SourceFailure ? e.message : '视频无法打开或加载超时，请检查文件后重试。';
      loading = false;
      await _release(save: false);
    }
    if (!_closed) notifyListeners();
  });

  void _startCheckpoints() {
    _checkpoint?.cancel();
    _checkpoint = Timer.periodic(checkpointInterval, (_) => unawaited(save()));
  }

  void _observe(VideoClock value) {
    if (_closed) return;
    clock = value;
    timeline.value = value;
    if (value.error != null) {
      error = '视频播放失败：${value.error}';
      loading = false;
      notifyListeners();
    }
    if (!loading && value.duration > Duration.zero) _hasClock = true;
    if (value.completed && !_completedSaved && !loading) {
      _completedSaved = true;
      _hasClock = true;
      unawaited(save(completed: true));
    }
  }

  Future<void> save({bool completed = false}) {
    final selected = item;
    final value = clock;
    if (!_hasClock || selected == null || value.duration <= Duration.zero) {
      return Future.value();
    }
    final next = _writes.then((_) async {
      try {
        await records.save(
          selected.identity,
          position: completed || value.completed
              ? value.duration
              : value.position,
          duration: value.duration,
        );
        saveError = null;
      } catch (_) {
        saveError = '播放进度保存失败，请检查本地索引。';
        if (!_closed) notifyListeners();
      }
    });
    _writes = next;
    return next;
  }

  Future<void> _command(Future<void> Function() action) => _serialize(() async {
    if (_closed || _closing != null) return;
    try {
      await action();
    } catch (_) {
      error = '播放器操作失败，请重新打开视频。';
      loading = false;
      notifyListeners();
    }
  });

  Future<void> toggle() => _command(() async {
    if (_closed || loading || error != null || engine == null) return;
    if (clock.playing) {
      await engine!.pause();
      await save();
    } else {
      await engine!.play();
    }
  });
  Future<void> seek(Duration target) => _command(() async {
    if (_closed ||
        loading ||
        error != null ||
        engine == null ||
        clock.duration <= Duration.zero) {
      return;
    }
    final clamped = target.inMilliseconds.clamp(
      0,
      clock.duration.inMilliseconds,
    );
    await engine!.seek(Duration(milliseconds: clamped));
  });
  Future<void> volume(double value) => _command(() async {
    if (!_closed && !loading && engine != null) {
      await engine!.setVolume(value.clamp(0, 100));
    }
  });

  Future<void> _release({bool save = true}) async {
    _checkpoint?.cancel();
    _checkpoint = null;
    final current = engine;
    if (current == null) return;
    try {
      await current.pause();
    } catch (_) {
      /* Still release a failed decoder. */
    }
    if (save) await this.save(completed: clock.completed);
    await _subscription?.cancel();
    _subscription = null;
    try {
      await current.dispose();
    } finally {
      engine = null;
    }
  }

  /// Pause and commit first. A failed checkpoint leaves the decoder and
  /// command queue available; only an explicit discard may bypass persistence.
  Future<void> close({bool discardProgress = false}) {
    if (_closed) return _closing ?? Future.value();
    if (_closing != null) return _closing!;
    final closing = _serialize(() async {
      _checkpoint?.cancel();
      _checkpoint = null;
      if (engine != null) {
        try {
          await engine!.pause();
        } catch (_) {
          // A failed decoder must not prevent persisting its last valid clock.
        }
      }
      if (!discardProgress) await save(completed: clock.completed);
      await _writes;
      if (!discardProgress && saveError != null) return;
      await _release(save: false);
      _closed = true;
    });
    _closing = closing;
    return closing.whenComplete(() {
      if (!_closed) {
        _closing = null;
        if (engine != null && _hasClock && !loading && error == null) {
          _startCheckpoints();
        }
      }
    });
  }

  @override
  void dispose() {
    _checkpoint?.cancel();
    timeline.dispose();
    super.dispose();
  }
}
