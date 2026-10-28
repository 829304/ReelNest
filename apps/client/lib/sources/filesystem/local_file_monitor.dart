import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/media_source.dart';
import '../../platform/hidden_file_access.dart';

class LocalFileChange {
  const LocalFileChange(
    this.path, {
    this.fullScan = false,
    this.error,
    this.stack,
  });
  final String path;
  final bool fullScan;
  final Object? error;
  final StackTrace? stack;
}

abstract interface class FileChangeMonitor {
  bool get isActive;
  Future<void> close();
}

typedef FileChangeMonitorFactory = Future<FileChangeMonitor> Function(
  MediaSource source,
  void Function(LocalFileChange) onChange,
);

/// Dart uses ReadDirectoryChangesW/FSEvents on Windows/macOS. Linux inotify is
/// not recursive: subscribe each directory before enumerating its children and
/// rebuild that subscription tree whenever a structural event arrives.
class LocalFileMonitor implements FileChangeMonitor {
  LocalFileMonitor._(this.source, this.onChange, this._perDirectory);
  final MediaSource source;
  final void Function(LocalFileChange) onChange;
  final bool _perDirectory;
  final _subscriptions = <String, StreamSubscription<FileSystemEvent>>{};
  bool _closed = false, _refreshing = false, _refreshAgain = false;

  @override
  bool get isActive => !_closed && _subscriptions.isNotEmpty;

  static Future<FileChangeMonitor> start(
    MediaSource source,
    void Function(LocalFileChange) onChange, {
    bool? perDirectory,
  }) async {
    final monitor = LocalFileMonitor._(
      source,
      onChange,
      perDirectory ?? Platform.isLinux,
    );
    try {
      await monitor._refresh();
      return monitor;
    } catch (_) {
      await monitor.close();
      rethrow;
    }
  }

  void _watch(String path) {
    if (_closed || _subscriptions.containsKey(path)) return;
    _subscriptions[path] = Directory(path)
        .watch(recursive: source.recursive && !_perDirectory)
        .listen(
          (event) {
            if (_closed) return;
            final structural =
                event.isDirectory || p.equals(event.path, source.location);
            onChange(LocalFileChange(event.path, fullScan: structural));
            if (event is FileSystemMoveEvent && event.destination != null) {
              onChange(
                LocalFileChange(event.destination!, fullScan: structural),
              );
            }
            if (_perDirectory && structural) {
              unawaited(
                _refresh().catchError((Object error, StackTrace stack) {
                  if (!_closed) {
                    onChange(
                      LocalFileChange(
                        source.location,
                        fullScan: true,
                        error: error,
                        stack: stack,
                      ),
                    );
                  }
                }),
              );
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!_closed) {
              onChange(
                LocalFileChange(
                  source.location,
                  fullScan: true,
                  error: error,
                  stack: stack,
                ),
              );
            }
          },
          onDone: () {
            _subscriptions.remove(path);
            // Root deletion, buffer overflow or an interrupted native watcher:
            // request a guarded full scan rather than treating the index as empty.
            if (!_closed) {
              onChange(LocalFileChange(source.location, fullScan: true));
            }
          },
        );
  }

  Future<void> _refresh() async {
    if (_closed) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final pending = [source.location];
        final desired = <String>{};
        while (!_closed && pending.isNotEmpty) {
          final path = pending.removeLast();
          if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.directory) {
            continue;
          }
          if (_closed) return;
          desired.add(path);
          _watch(path);
          if (_perDirectory && source.recursive) {
            final children = await Directory(path)
                .list(followLinks: false)
                .where((entity) => entity is Directory)
                .toList();
            if (_closed) return;
            final hidden = source.ignoreHidden
                ? await hiddenFilePaths(
                    children.map((entity) => entity.path).toList(),
                  )
                : const <String>{};
            if (_closed) return;
            pending.addAll(
              children
                  .where((entity) => !hidden.contains(entity.path))
                  .map((entity) => entity.path),
            );
          }
        }
        for (final path in _subscriptions.keys.toList()) {
          if (!desired.contains(path)) {
            await _subscriptions.remove(path)?.cancel();
          }
        }
      } while (_refreshAgain && !_closed);
    } finally {
      _refreshing = false;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final subscriptions = _subscriptions.values.toList();
    _subscriptions.clear();
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }
}
