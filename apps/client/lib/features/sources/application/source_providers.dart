import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../platform/directory_access.dart';
import '../../../sources/filesystem/file_source_adapter.dart';
import '../../../storage/library_database.dart';
import '../data/source_repository.dart';

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

final _sourceChangesProvider = StreamProvider<void>(
  (ref) => ref.watch(sourceRepositoryProvider).changes,
);

final sourcesProvider = FutureProvider<List<MediaSource>>((ref) {
  ref.watch(_sourceChangesProvider);
  return ref.watch(sourceRepositoryProvider).sources();
});

final sourceReachabilityProvider = FutureProvider<Map<String, bool>>((
  ref,
) async {
  final repository = ref.watch(sourceRepositoryProvider);
  final sources = await ref.watch(sourcesProvider.future);
  final results = await Future.wait(
    sources.map(
      (source) async =>
          MapEntry(source.id, await repository.isReachable(source)),
    ),
  );
  return Map.fromEntries(results);
});

typedef SourcePageKey = ({String sourceId, int offset});
final sourceMediaProvider = FutureProvider.autoDispose
    .family<IndexedMediaPage, SourcePageKey>((ref, key) {
      ref.watch(_sourceChangesProvider);
      return ref
          .watch(sourceRepositoryProvider)
          .browse(key.sourceId, offset: key.offset);
    });

class SourceScanState {
  const SourceScanState({
    this.running = false,
    this.queued = false,
    this.count = 0,
    this.message,
  });
  final bool running;
  final bool queued;
  bool get busy => running || queued;
  final int count;
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

  void cancel(String id) {
    final queued = _queue.where((request) => request.id == id).toList();
    for (final request in queued) {
      _queue.remove(request);
      request.cancelled = true;
      request.done.complete();
    }
    if (_active?.id != id) {
      _set(id, const SourceScanState(message: '扫描已取消，保留上次索引。'));
      return;
    }
    _active!.cancelled = true;
    _repository.cancel(id);
    _set(
      id,
      SourceScanState(
        running: true,
        count: state[id]?.count ?? 0,
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
    final request = _ScanRequest(id);
    _queue.add(request);
    _set(id, const SourceScanState(queued: true, message: '等待扫描'));
    if (_active == null) unawaited(_drain());
    return request.done.future;
  }

  Future<void> scanAll(Iterable<MediaSource> sources) => Future.wait(
    sources.where((s) => s.kind.isFileSource).map((s) => scan(s.id)),
  );

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (!_disposed && _queue.isNotEmpty) {
        final request = _queue.removeAt(0);
        _active = request;
        await _run(request);
        if (!request.done.isCompleted) request.done.complete();
        _active = null;
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _run(_ScanRequest request) async {
    final id = request.id;
    _set(id, const SourceScanState(running: true));
    var count = 0;
    try {
      final source = await _repository.source(id);
      final reachable = await _repository.isReachable(source);
      if (request.cancelled || _disposed) throw const ScanCancelled();
      if (!reachable) {
        throw const SourceFailure('所选媒体源不可访问，请确认磁盘或 NAS 已挂载。');
      }
      await _repository.scan(
        id,
        onProgress: (value) {
          count = value;
          _set(id, SourceScanState(running: true, count: value));
        },
      );
      _set(id, SourceScanState(count: count, message: '扫描完成：$count 个媒体文件'));
    } on ScanCancelled {
      _set(id, const SourceScanState(message: '扫描已取消，保留上次索引。'));
    } catch (error) {
      _set(id, SourceScanState(message: sourceErrorMessage(error)));
    } finally {
      if (!_disposed && ref.mounted) ref.invalidate(sourceReachabilityProvider);
    }
  }
}

class _ScanRequest {
  _ScanRequest(this.id);
  final String id;
  final done = Completer<void>();
  bool cancelled = false;
}

String sourceErrorMessage(Object error) =>
    error is SourceFailure ? error.message : '媒体库操作失败，请检查目录权限、磁盘空间后重试。';
