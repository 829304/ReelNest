import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/automatic_scan_interval.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/sources/application/automatic_source_scanner.dart';
import 'package:reelnest/sources/filesystem/local_file_monitor.dart';

void main() {
  late AutomaticSourceScanner scanner;
  late StreamController<void> changes;
  late List<MediaSource> sources;
  late List<_Monitor> monitors;
  late List<({String id, Set<String>? paths})> scheduled;
  var revision = 0, reads = 0;
  var online = true, busy = false;
  final root = p.join(Directory.systemTemp.path, 'automatic-source-root');
  MediaSource source(
    String id,
    String path, {
    bool auto = true,
    MediaSourceKind kind = MediaSourceKind.localFolder,
  }) => MediaSource(
    id: id,
    kind: kind,
    name: id,
    location: path,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    options: SourceOptions(autoScan: auto),
  );
  setUp(() {
    reads = revision = 0;
    online = true;
    busy = false;
    sources = [source('a', root)];
    monitors = [];
    scheduled = [];
    changes = StreamController.broadcast();
    scanner = AutomaticSourceScanner(
      sources: () async {
        reads++;
        return sources;
      },
      isReachable: (_) async => online,
      schedule: (id, {paths}) async {
        scheduled.add((id: id, paths: paths == null ? null : {...paths}));
      },
      isBusy: () => busy,
      changes: changes.stream,
      configurationRevision: () => revision,
      onError: (error, stack) => fail('$error'),
      watch: (source, callback) async {
        final monitor = _Monitor(callback);
        monitors.add(monitor);
        return monitor;
      },
      debounce: const Duration(milliseconds: 15),
    );
  });
  tearDown(() async {
    await scanner.dispose();
    await changes.close();
  });

  test(
    'native watcher failure is reported and schedules a guarded full scan',
    () async {
      await scanner.dispose();
      final errors = <Object>[];
      scanner = AutomaticSourceScanner(
        sources: () async => sources,
        isReachable: (_) async => true,
        schedule: (id, {paths}) async {
          scheduled.add((id: id, paths: paths));
        },
        isBusy: () => false,
        changes: changes.stream,
        configurationRevision: () => 0,
        onError: (error, stack) => errors.add(error),
        watch: (source, callback) async => _Monitor(callback),
      );
      await scanner.setInterval(AutomaticScanInterval.hourly);
      final error = FileSystemException('native watcher failed', root);
      scanner.receive(LocalFileChange(root, fullScan: true, error: error));
      scanner.flush();
      expect(errors, [error]);
      expect(scheduled.single.paths, isNull);
    },
  );

  test('default disabled never probes directories, watches or scans', () async {
    revision++;
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    await scanner.refreshSources();
    await scanner.tick();
    scanner.receive(LocalFileChange(p.join(root, 'a.mkv')));
    scanner.flush();
    expect(reads, 0);
    expect(monitors, isEmpty);
    expect(scheduled, isEmpty);
  });

  test(
    'enable waits for timer; debounce merges paths and full scan supersedes',
    () async {
      await scanner.setInterval(AutomaticScanInterval.hourly);
      expect(scheduled, isEmpty);
      final a = p.join(root, 'a.mkv'), b = p.join(root, 'b.mkv');
      scanner.receive(LocalFileChange(a));
      scanner.receive(LocalFileChange(a));
      scanner.receive(LocalFileChange(b));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(scheduled.single.paths, {a, b});
      scheduled.clear();
      scanner.receive(LocalFileChange(a));
      scanner.receive(LocalFileChange(root, fullScan: true));
      scanner.receive(LocalFileChange(b));
      scanner.flush();
      expect(scheduled.single.paths, isNull);
    },
  );

  test(
    'nested roots use the longest match, remote/opted-out roots excluded',
    () async {
      sources = [
        source('a', root),
        source('nested', p.join(root, 'nested')),
        source('off', p.join(root, 'off'), auto: false),
        source('remote', 'emby://server/id', kind: MediaSourceKind.emby),
      ];
      await scanner.setInterval(AutomaticScanInterval.daily);
      expect(monitors.length, 2);
      scanner.receive(LocalFileChange(p.join(root, 'nested', 'one.mkv')));
      scanner.receive(const LocalFileChange('relative.mkv'));
      scanner.flush();
      expect(scheduled.single.id, 'nested');
    },
  );

  test(
    'disable discards debounce, stops monitors; disposal is idempotent',
    () async {
      await scanner.setInterval(AutomaticScanInterval.hourly);
      scanner.receive(LocalFileChange(p.join(root, 'one.mkv')));
      await scanner.setInterval(AutomaticScanInterval.disabled);
      scanner.flush();
      await scanner.tick();
      expect(monitors.single.closed, isTrue);
      expect(scheduled, isEmpty);
      await scanner.dispose();
      await scanner.dispose();
    },
  );

  test(
    'offline disk keeps index idle; periodic refresh reinstalls monitors',
    () async {
      await scanner.setInterval(AutomaticScanInterval.hourly);
      online = false;
      await scanner.tick();
      expect(monitors.single.closed, isTrue);
      expect(scheduled, isEmpty);
      online = true;
      await scanner.tick();
      expect(monitors.length, 2);
      expect(scheduled.single.paths, isNull);
    },
  );

  test(
    'busy timer skips work and removed sources cannot flush old changes',
    () async {
      await scanner.setInterval(AutomaticScanInterval.hourly);
      busy = true;
      await scanner.tick();
      expect(scheduled, isEmpty);
      scanner.receive(LocalFileChange(p.join(root, 'a.mkv')));
      sources = [];
      revision++;
      changes.add(null);
      await scanner.refreshSources();
      scanner.flush();
      expect(monitors.single.closed, isTrue);
      expect(scheduled, isEmpty);
    },
  );

  test(
    'dispose during asynchronous watcher startup closes the late watcher',
    () async {
      await scanner.dispose();
      final gate = Completer<FileChangeMonitor>();
      scanner = AutomaticSourceScanner(
        sources: () async => sources,
        isReachable: (_) async => true,
        schedule: (id, {paths}) async {},
        isBusy: () => false,
        changes: changes.stream,
        configurationRevision: () => 0,
        onError: (e, s) => fail('$e'),
        watch: (s, cb) => gate.future,
      );
      final enabling = scanner.setInterval(AutomaticScanInterval.hourly);
      await Future<void>.delayed(Duration.zero);
      await scanner.dispose();
      final monitor = _Monitor((_) {});
      gate.complete(monitor);
      await enabling;
      expect(monitor.closed, isTrue);
    },
  );
}

class _Monitor implements FileChangeMonitor {
  _Monitor(this.callback);
  final void Function(LocalFileChange) callback;
  bool closed = false;
  @override
  bool get isActive => !closed;
  @override
  Future<void> close() async {
    closed = true;
  }
}
