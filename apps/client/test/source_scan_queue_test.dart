import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_scan.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/source_settings_draft.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  late SourceRepository repository;
  late ProviderContainer container;
  late _ControlledFiles files;
  late List<MediaSource> sources;
  setUp(() async {
    files = _ControlledFiles();
    repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: files},
    );
    sources = [];
    for (final name in ['a', 'b', 'c', 'd']) {
      sources.add(
        await repository.add(
          kind: MediaSourceKind.localFolder,
          name: name,
          location: '/$name',
        ),
      );
    }
    container = ProviderContainer(
      overrides: [sourceRepositoryProvider.overrideWithValue(repository)],
    );
  });
  tearDown(() async {
    container.dispose();
    for (final gate in files.gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await repository.close();
  });

  test('scan all is sequential, deduplicated and continues after offline/error sources', () async {
    files.gates['/a'] = Completer<void>();
    files.failures.add('/c');
    final controller = container.read(sourceScansProvider.notifier);
    final all = controller.scanAll(sources);
    await _until(() => files.started.isNotEmpty);
    final duplicate = controller.scan(sources.first.id);
    expect(container.read(sourceScansProvider)[sources[1].id]!.queued, isTrue);
    // Unplug after queuing: reachability must be checked at execution time.
    files.offline.add('/b');
    files.gates['/a']!.complete();
    await Future.wait([all, duplicate]);
    expect(files.started, ['/a', '/c', '/d']);
    expect(files.maximumParallel, 1);
    expect((await repository.browse(sources[3].id)).total, 1);
    final state = container.read(sourceScansProvider);
    expect(state.values.every((scan) => !scan.busy), isTrue);
    expect(state[sources[1].id]!.message, contains('不可访问'));
    expect(state[sources[2].id]!.message, '模拟扫描失败');
  });

  test(
    'cancelling active and queued work preserves old index and advances queue',
    () async {
      await repository.scan(sources.first.id);
      files.started.clear();
      files.gates['/a'] = Completer<void>();
      final controller = container.read(sourceScansProvider.notifier);
      final all = controller.scanAll(sources.take(3));
      await _until(() => files.started.isNotEmpty);
      controller.cancel(sources[1].id);
      controller.cancel(sources.first.id);
      files.gates['/a']!.complete();
      await all;
      expect(files.started, ['/a', '/c']);
      expect((await repository.browse(sources.first.id)).total, 1);
      expect((await repository.browse(sources[1].id)).total, 0);
      expect((await repository.browse(sources[2].id)).total, 1);
      expect(
        container.read(sourceScansProvider).values.every((scan) => !scan.busy),
        isTrue,
      );
    },
  );

  test(
    'disposing while checking reachability never starts a queued scan',
    () async {
      files.reachabilityGate = Completer<void>();
      final controller = container.read(sourceScansProvider.notifier);
      final all = controller.scanAll(sources);
      await _until(() => files.reachabilityChecks > 0);
      container.dispose();
      files.reachabilityGate!.complete();
      await all;
      await Future<void>.delayed(Duration.zero);
      expect(files.started, isEmpty);
    },
  );

  SourceSettingsDraft settings() => const SourceSettingsDraft(
    mediaType: SourceMediaType.music,
    includeInMetadataFetch: true,
    includeInHealthCheck: false,
    preferMetadataWriteToSource: false,
  );

  test('idle settings save persists without starting a scan', () async {
    await container
        .read(sourceScansProvider.notifier)
        .saveSettings(sources.first.id, settings());
    final saved = await repository.source(sources.first.id);
    expect(saved.mediaType, SourceMediaType.music);
    expect(saved.minimumFileSize, 512 * 1024);
    expect(saved.options.includeInHealthCheck, isFalse);
    expect(files.started, isEmpty);
  });

  test('save retires original batch, restarts edited source and preserves appended request', () async {
    files.gates['/a'] = Completer<void>();
    final controller = container.read(sourceScansProvider.notifier);
    final original = controller.scanAll(sources.take(2));
    await _until(() => files.started.isNotEmpty);
    final appended = controller.scan(sources[2].id);
    final save = controller.saveSettings(sources[3].id, settings());
    await _until(
      () =>
          container.read(sourceScansProvider)[sources.first.id]?.message ==
          '正在取消扫描…',
    );
    files.gates['/a']!.complete();
    await save;
    await Future.wait([original, appended, controller.scan(sources[3].id)]);
    expect(files.started, ['/a', '/d', '/c']);
    expect(files.maximumParallel, 1);
    expect((await repository.browse(sources[1].id)).total, 0);
    expect(
      container.read(sourceScansProvider).values.every((state) => !state.busy),
      isTrue,
    );
  });

  test(
    'failed settings save leaves running scan and original queue intact',
    () async {
      files.gates['/a'] = Completer<void>();
      final controller = container.read(sourceScansProvider.notifier);
      final original = controller.scanAll(sources.take(2));
      await _until(() => files.started.isNotEmpty);
      await repository.database.customStatement(
        "CREATE TRIGGER reject_settings BEFORE UPDATE OF media_type ON sources BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(
        controller.saveSettings(sources.first.id, settings()),
        throwsA(anything),
      );
      expect(
        container.read(sourceScansProvider)[sources.first.id]!.running,
        isTrue,
      );
      expect(
        container.read(sourceScansProvider)[sources[1].id]!.queued,
        isTrue,
      );
      files.gates['/a']!.complete();
      await original;
      expect(files.started, ['/a', '/b']);
      expect(
        (await repository.source(sources.first.id)).mediaType,
        SourceMediaType.auto,
      );
    },
  );
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('The scan queue did not reach the expected state');
}

class _ControlledFiles implements SourceAdapter {
  final gates = <String, Completer<void>>{};
  Completer<void>? reachabilityGate;
  int reachabilityChecks = 0;
  final offline = <String>{};
  final failures = <String>{};
  final started = <String>[];
  int parallel = 0;
  int maximumParallel = 0;
  @override
  Future<String> validateLocation(String location) async => location;
  @override
  Future<bool> isReachable(String location) async {
    reachabilityChecks++;
    await reachabilityGate?.future;
    return !offline.contains(location);
  }

  @override
  Stream<SourceScanEvent> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    parallel++;
    if (parallel > maximumParallel) maximumParallel = parallel;
    started.add(source.location);
    try {
      await gates[source.location]?.future;
      cancellation.check();
      if (failures.contains(source.location)) {
        throw const SourceFailure('模拟扫描失败');
      }
      yield const ScanCatalogued(1);
      yield ScanFileProcessed(
        path: 'film.mp4',
        item: IndexedMedia(
          identity: (sourceId: source.id, localId: 'film.mp4'),
          title: source.name,
          type: 'homeVideo',
          bytes: 52428800,
          modified: DateTime.utc(2026),
        ),
      );
    } finally {
      parallel--;
    }
  }
}
