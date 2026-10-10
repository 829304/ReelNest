import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../domain/source_scan.dart';
import '../../../domain/source_settings_draft.dart';
import '../../../platform/directory_access.dart';
import '../../../sources/filesystem/file_source_adapter.dart';
import '../../../storage/library_database.dart';
import '../data/source_repository.dart';
import 'emby_providers.dart';

final directoryAccessProvider = Provider<DirectoryAccess>(
  (ref) => DesktopDirectoryAccess(),
);

final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  final files = FileSourceAdapter();
  final repository = SourceRepository(
    database: LibraryDatabase.open(),
    adapters: {
      MediaSourceKind.localFolder: files,
      MediaSourceKind.removableDrive: files,
      MediaSourceKind.mountedNas: files,
    },
  );
  ref.onDispose(() => unawaited(repository.close()));
  return repository;
});

// Riverpod compares stream values: repeated void/null events otherwise stop
// refreshing dependents after the first mutation.
final sourceChangesProvider = StreamProvider<int>((ref) {
  var revision = 0;
  return ref.watch(sourceRepositoryProvider).changes.map((_) => ++revision);
});

final sourcesProvider = FutureProvider<List<MediaSource>>((ref) {
  ref.watch(sourceChangesProvider);
  return ref.watch(sourceRepositoryProvider).sources();
});

final sourceReachabilityProvider = FutureProvider<Map<String, bool>>((
  ref,
) async {
  final repository = ref.watch(sourceRepositoryProvider);
  final sources = await ref.watch(sourcesProvider.future);
  final results = await Future.wait(
    sources.map(
      (source) async => MapEntry(
        source.id,
        source.kind == MediaSourceKind.emby
            ? await ref.read(embyConnectionProvider).isReachable(source)
            : await repository.isReachable(source),
      ),
    ),
  );
  return Map.fromEntries(results);
});

typedef SourcePageKey = ({String sourceId, int offset});
final sourceMediaProvider = FutureProvider.autoDispose
    .family<IndexedMediaPage, SourcePageKey>((ref, key) {
      ref.watch(sourceChangesProvider);
      return ref
          .watch(sourceRepositoryProvider)
          .browse(key.sourceId, offset: key.offset, topLevelOnly: true);
    });

final sourceMediaDetailProvider = FutureProvider.autoDispose
    .family<IndexedMedia, MediaIdentity>((ref, identity) {
      ref.watch(sourceChangesProvider);
      return ref.watch(sourceRepositoryProvider).media(identity);
    });

final sourceSeasonsProvider = FutureProvider.autoDispose
    .family<List<IndexedSeason>, MediaIdentity>((ref, identity) {
      ref.watch(sourceChangesProvider);
      return ref.watch(sourceRepositoryProvider).seasons(identity);
    });

typedef SourceEpisodePageKey = ({
  MediaIdentity series,
  int? season,
  int offset,
});
final sourceEpisodesProvider = FutureProvider.autoDispose
    .family<IndexedMediaPage, SourceEpisodePageKey>((ref, key) {
      ref.watch(sourceChangesProvider);
      return ref
          .watch(sourceRepositoryProvider)
          .episodes(key.series, seasonNumber: key.season, offset: key.offset);
    });

class SourceScanState {
  const SourceScanState({
    this.running = false,
    this.queued = false,
    this.progress = const SourceScanProgress(),
    this.message,
    this.failed = false,
    this.cancelled = false,
  });
  final bool running;
  final bool queued;
  final bool failed, cancelled;
  bool get busy => running || queued;
  final SourceScanProgress progress;
  int get count => progress.importedItems;
  final String? message;
}

final sourceScansProvider =
    NotifierProvider<SourceScans, Map<String, SourceScanState>>(
      SourceScans.new,
    );

class SourceScans extends Notifier<Map<String, SourceScanState>> {
  final _queue = <_ScanRequest>[];
  _ScanRequest? _active;
  late SourceRepository _repository;
  bool _disposed = false;
  bool _draining = false;
  bool _updatingSettings = false;

  @override
  Map<String, SourceScanState> build() {
    _repository = ref.read(sourceRepositoryProvider);
    ref.onDispose(() {
      _disposed = true;
      for (final request in [..._queue, ?_active]) {
        request.cancelled = true;
        _repository.cancel(request.id);
        if (!request.done.isCompleted) request.done.complete();
      }
      _queue.clear();
    });
    return {};
  }

  void _set(String id, SourceScanState value) {
    if (ref.mounted) state = {...state, id: value};
  }

  void clearFinished() {
    state = Map.fromEntries(state.entries.where((e) => e.value.busy));
  }

  void cancel(String id) {
    final queued = _queue.where((request) => request.id == id).toList();
    for (final request in queued) {
      _queue.remove(request);
      request.cancelled = true;
      request.done.complete();
    }
    if (_active?.id != id) {
      _set(
        id,
        const SourceScanState(message: '扫描已取消，保留上次索引。', cancelled: true),
      );
      return;
    }
    _active!.cancelled = true;
    _repository.cancel(id);
    _set(
      id,
      SourceScanState(
        running: true,
        progress: state[id]?.progress ?? const SourceScanProgress(),
        message: '正在取消扫描…',
      ),
    );
  }

  /// AppState.startScanQueue: one active local scan, ordered pending sources.
  /// Duplicate requests share the original future rather than scanning twice.
  Future<void> scan(String id) {
    if (_disposed) return Future.value();
    if (_active?.id == id) return _active!.done.future;
    for (final request in _queue) {
      if (request.id == id) return request.done.future;
    }
    final request = _ScanRequest(
      id,
      inCurrentRun: _active == null && !_updatingSettings,
    );
    _queue.add(request);
    _set(id, const SourceScanState(queued: true, message: '等待扫描'));
    if (_active == null && !_updatingSettings) unawaited(_drain());
    return request.done.future;
  }

  Future<void> scanAll(Iterable<MediaSource> sources) {
    // Original runScanQueue keeps the initial batch separate from requests
    // appended while running; restartScanIfNeeded discards the former.
    final initialBatch = _active == null && !_updatingSettings;
    final futures = <Future<void>>[];
    for (final source in sources.where(
      (s) => s.kind.isFileSource || s.kind == MediaSourceKind.emby,
    )) {
      futures.add(scan(source.id));
      if (initialBatch) {
        for (final request in _queue.where((r) => r.id == source.id)) {
          request.inCurrentRun = true;
        }
      }
    }
    return Future.wait(futures);
  }

  /// AppState.updateSource -> restartScanIfNeeded. Idle saves do not scan.
  /// When scanning, persist first, retire the old run, then restart this source.
  /// A failed save neither cancels scans nor discards queued work.
  Future<MediaSource> saveSettings(String id, SourceSettingsDraft draft) async {
    if (_disposed) throw const SourceFailure('媒体库已关闭。');
    if (_updatingSettings) throw const SourceFailure('媒体源设置正在保存，请稍后重试。');
    _updatingSettings = true;
    try {
      final current = await _repository.source(id);
      if (!current.kind.isFileSource) throw const SourceFailure('此来源的设置尚未接入。');
      final saved = await _repository.updateSettings(
        id,
        mediaType: draft.mediaType,
        options: draft.applyTo(current.options),
        allowDuringScan: true,
      );
      if (_disposed) return saved;
      if (_active != null) {
        final active = _active;
        for (final request in _queue.toList()) {
          if (request.inCurrentRun || request.id == id) {
            _queue.remove(request);
            request.cancelled = true;
            if (!request.done.isCompleted) request.done.complete();
            _set(request.id, const SourceScanState(message: '设置已更新，原扫描任务已取消。'));
          }
        }
        if (active != null) {
          cancel(active.id);
          await active.done.future;
        }
        if (!_disposed) {
          // A request may arrive while awaiting cancellation. Reuse its future
          // so the restart and that caller share one scan.
          final existing = _queue
              .where((request) => request.id == id)
              .firstOrNull;
          final restart = existing ?? _ScanRequest(id, inCurrentRun: true);
          _queue.remove(restart);
          restart.inCurrentRun = true;
          _queue.insert(0, restart);
          _set(
            id,
            const SourceScanState(queued: true, message: '设置已更新，等待重新扫描'),
          );
        }
      }
      // Repository change stream refreshes sources, artwork and detail data.
      // Health evaluation subscribes to the same stream and discards old runs.
      return saved;
    } finally {
      _updatingSettings = false;
      if (!_disposed && _active == null && _queue.isNotEmpty) {
        unawaited(_drain());
      }
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (!_disposed && !_updatingSettings && _queue.isNotEmpty) {
        final request = _queue.removeAt(0);
        _active = request;
        await _run(request);
        if (!request.done.isCompleted) request.done.complete();
        _active = null;
        // runScanQueue appends pendingScanSources after each completed source.
        // During a save retain that distinction until restart is coordinated.
        if (!_updatingSettings) {
          for (final pending in _queue) {
            pending.inCurrentRun = true;
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _run(_ScanRequest request) async {
    final id = request.id;
    _set(id, const SourceScanState(running: true));
    var progress = const SourceScanProgress();
    try {
      final source = await _repository.source(id);
      if (request.cancelled || _disposed) throw const ScanCancelled();
      void update(SourceScanProgress value) {
        progress = value;
        _set(id, SourceScanState(running: true, progress: value));
      }

      late SourceScanSummary summary;
      if (source.kind == MediaSourceKind.emby) {
        summary = await ref
            .read(embySyncProvider)
            .synchronize(id, onProgress: update);
      } else {
        final reachable = await _repository.isReachable(source);
        if (request.cancelled || _disposed) throw const ScanCancelled();
        if (!reachable) throw const SourceFailure('所选媒体源不可访问，请确认磁盘或 NAS 已挂载。');
        summary = await _repository.scan(id, onProgress: update);
      }
      _set(
        id,
        SourceScanState(
          progress: progress,
          failed: summary.errors.isNotEmpty,
          message: summary.errors.isEmpty
              ? (source.kind == MediaSourceKind.emby
                    ? '同步完成：${summary.importedItems} 个媒体条目'
                    : '扫描完成：${summary.importedItems} 个媒体文件')
              : '扫描结束：${summary.importedItems} 个媒体文件，${summary.errors.length} 个错误。${summary.errors.first}',
        ),
      );
    } on ScanCancelled {
      _set(
        id,
        SourceScanState(
          progress: progress,
          message: '操作已取消，原有索引已保留。',
          cancelled: true,
        ),
      );
    } catch (error) {
      _set(
        id,
        SourceScanState(
          progress: progress,
          message: sourceErrorMessage(error),
          failed: true,
        ),
      );
    } finally {
      if (!_disposed && ref.mounted) ref.invalidate(sourceReachabilityProvider);
    }
  }
}

class _ScanRequest {
  _ScanRequest(this.id, {required this.inCurrentRun});
  final String id;
  bool inCurrentRun;
  final done = Completer<void>();
  bool cancelled = false;
}

String sourceErrorMessage(Object error) => error is SourceFailure
    ? error.message
    : LibrarySchemaMismatch.isCause(error)
    ? LibrarySchemaMismatch.message
    : '无法读取或更新本地媒体索引，请重试。';
