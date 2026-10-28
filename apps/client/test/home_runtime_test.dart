import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelnest/app/runtime_observations.dart';
import 'package:reelnest/domain/library_health.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/source_scan.dart';
import 'package:reelnest/features/health/application/health_providers.dart';
import 'package:reelnest/features/home/application/home_providers.dart';
import 'package:reelnest/features/home/application/home_runtime_providers.dart';
import 'package:reelnest/features/home/domain/home_runtime.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/home/presentation/widgets/home_runtime_status.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';

class _ControlledScan extends SourceRepository {
  _ControlledScan()
    : super(database: LibraryDatabase(NativeDatabase.memory()), adapters: {});
  final entered = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<bool> isReachable(MediaSource source) async => true;
  @override
  Future<SourceScanSummary> scan(
    String id, {
    void Function(SourceScanProgress progress)? onProgress,
    Set<String>? changedPaths,
  }) async {
    onProgress?.call(const SourceScanProgress(processedFiles: 12));
    if (!entered.isCompleted) entered.complete();
    await finish.future;
    onProgress?.call(
      const SourceScanProgress(processedFiles: 20, totalFiles: 20),
    );
    return SourceScanSummary(
      scannedFiles: 20,
      importedItems: 20,
      skippedFiles: 0,
      errors: [],
    );
  }
}

final _date = DateTime(2026, 10, 12);
MediaSource source(
  String id, {
  MediaSourceKind kind = MediaSourceKind.localFolder,
  SourceMediaType type = SourceMediaType.auto,
  String location = '/media',
  DateTime? lastScan,
}) => MediaSource(
  id: id,
  kind: kind,
  name: '来源 $id',
  location: location,
  mediaType: type,
  createdAt: _date,
  updatedAt: _date,
  lastScan: lastScan,
);

RuntimeTask task(
  String id, {
  String sourceId = 'local',
  bool active = true,
  DateTime? start,
  DateTime? finish,
  bool cache = false,
  bool hidden = false,
  double? progress,
  String? stateTitle,
}) => RuntimeTask(
  id: id,
  group: cache ? 'cache' : 'scan',
  sourceId: sourceId,
  title: '缓存 · 私密影片',
  detail: '/secret/video.mkv',
  stateTitle: stateTitle ?? (active ? '进行中' : '已完成'),
  active: active,
  startedAt: start ?? _date,
  finishedAt: finish,
  isCache: cache,
  hidesDetail: hidden,
  progress: progress,
);

LibraryHealthSnapshot health(MediaSource local, {bool gap = true}) {
  final id = (sourceId: local.id, localId: 'movie.mkv');
  return LibraryHealthSnapshot(
    inventory: (
      sources: [local],
      items: [
        IndexedMedia(
          identity: id,
          title: 'movie',
          type: 'movie',
          bytes: 1,
          modified: _date,
        ),
      ],
    ),
    missing: {},
    safeMissing: {},
    offline: {},
    metadataGaps: {
      if (gap) id: ['封面'],
    },
  );
}

void main() {
  test('existing scan publishes unknown-length progress, completion, retry and clearing', () async {
    final repository = _ControlledScan();
    final local = await repository.add(
      kind: MediaSourceKind.emby,
      name: '测试来源',
      location: 'emby://fixture/local',
    );
    await repository.database.customStatement(
      "UPDATE sources SET kind='localFolder' WHERE id=?",
      [local.id],
    );
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(repository),
        sourceReachabilityProvider.overrideWith((ref) => {}),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repository.close();
    });
    final scans = container.read(sourceScansProvider.notifier);
    final work = scans.scan(local.id);
    await repository.entered.future;
    final running = container.read(observedTasksProvider).single;
    expect(running.active, true);
    expect(running.progress, isNull);
    expect(running.detail, '已读取 12 个媒体条目');
    repository.finish.complete();
    await work;
    final done = container.read(observedTasksProvider).single;
    expect(done.id, running.id);
    expect(done.startedAt, running.startedAt);
    expect(done.stateTitle, '已完成');
    expect(done.progress, 1);
    expect(done.finishedAt, isNotNull);
    await scans.scan(local.id);
    expect(container.read(observedTasksProvider).single.id, isNot(done.id));
    scans.clearFinished();
    expect(container.read(observedTasksProvider), isEmpty);
  });

  test('completed dashboard check publishes summary without hiding ignored offline state', () async {
    final local = source('local');
    final snapshot = health(local);
    final raw = LibraryHealthSnapshot(
      inventory: snapshot.inventory,
      missing: {},
      safeMissing: {},
      offline: {local.id},
      metadataGaps: snapshot.metadataGaps,
    );
    final container = ProviderContainer(
      overrides: [
        sourceChangesProvider.overrideWith((ref) => const Stream.empty()),
        rawLibraryHealthProvider.overrideWith((ref) => raw),
        ignoredHealthIssuesProvider.overrideWith(
          (ref) => {
            (
              kind: HealthIssueKind.offlineSource,
              sourceId: local.id,
              localId: '',
            ),
          },
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(observedHealthProvider), isNull);
    final result = await container.read(libraryHealthProvider.future);
    expect(result.offline, isEmpty);
    expect(container.read(observedHealthProvider)!.snapshot, same(result));
    expect(
      HomeRuntimePolicy.online(
        local,
        container.read(observedReachabilityProvider),
      ),
      false,
    );
  });

  test('original source/metadata scoring preserves penalties and bounds', () {
    expect(HomeRuntimePolicy.sourceHealth(0, 0, 0), 100);
    expect(HomeRuntimePolicy.sourceHealth(3, 1, 1), 74);
    expect(HomeRuntimePolicy.sourceHealth(30, 20, 4), 35);
    expect(HomeRuntimePolicy.metadataHealth(100, 1), 97);
    expect(HomeRuntimePolicy.metadataHealth(100, 12), 64);
    expect(HomeRuntimePolicy.metadataHealth(0, 1), 45);
    expect(HomeRuntimePolicy.metadataHealth(1000, 0), 100);
  });

  test('unknown reachability and moved/reconfigured sources stay unknown', () {
    final local = source('local');
    final observations = {
      'local': (sourceKey: runtimeSourceKey(local), online: false),
    };
    expect(HomeRuntimePolicy.online(local, {}), isNull);
    expect(HomeRuntimePolicy.online(local, observations), false);
    expect(
      HomeRuntimePolicy.online(
        source('local', location: '/replacement'),
        observations,
      ),
      isNull,
    );
    expect(
      HomeRuntimePolicy.online(
        source('local', kind: MediaSourceKind.emby),
        observations,
      ),
      isNull,
    );
  });

  test(
    'basic metadata rejects stale, remote and unimplemented music coverage',
    () {
      final local = source('local');
      final snapshot = health(local);
      expect(HomeRuntimePolicy.basicMetadata(snapshot, [local]), 45);
      expect(
        HomeRuntimePolicy.basicMetadata(health(local, gap: false), [local]),
        100,
      );
      expect(
        HomeRuntimePolicy.basicMetadata(snapshot, [
          source('local', lastScan: _date),
        ]),
        isNull,
      );
      expect(
        HomeRuntimePolicy.basicMetadata(snapshot, [
          source('local', kind: MediaSourceKind.emby),
        ]),
        isNull,
      );
      expect(
        HomeRuntimePolicy.basicMetadata(snapshot, [
          source('local', type: SourceMediaType.music),
        ]),
        isNull,
      );
      expect(
        const HomeRuntimeHealth(
          sourcePercent: 100,
          metadataPercent: 100,
        ).totalScore,
        isNull,
      );
    },
  );

  test('active/paused tasks sort first, then latest completion, with deterministic ties', () {
    final tasks = HomeRuntimePolicy.tasks(
      [
        task('old', active: false, finish: _date),
        task('new', active: false, finish: _date.add(const Duration(hours: 2))),
        task(
          'paused',
          stateTitle: '已暂停',
          start: _date.add(const Duration(minutes: 1)),
        ),
        task('running'),
      ],
      [source('local')],
    );
    expect(tasks.map((t) => t.id), ['paused', 'running', 'new', 'old']);
    expect(tasks.first.active, true);
    expect(tasks.first.progress, isNull);
  });

  test('private source/item tasks redact titles and paths; removed sources disappear', () {
    final result = HomeRuntimePolicy.tasks(
      [
        task('private', sourceId: 'vault'),
        task('item', cache: true, hidden: true),
        task('removed', sourceId: 'removed'),
      ],
      [
        source('local'),
        source('vault', type: SourceMediaType.privateCollection),
      ],
    );
    expect(result.length, 2);
    expect(result.every((t) => t.detail == '任务正在后台处理。'), true);
    expect(result.map((t) => t.title), containsAll(['完整扫描', '视频缓存']));
  });

  test(
    'task snapshots retain timestamps and isolate producer clearing/retries',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(observedTasksProvider.notifier);
      store.replace('scan', [task('scan')]);
      store.replace('cache', [task('cache', cache: true)]);
      store.replace('scan', [
        task('scan', start: _date.add(const Duration(hours: 1)), progress: .5),
      ]);
      expect(container.read(observedTasksProvider).last.startedAt, _date);
      store.replace('scan', [task('scan', active: false)]);
      final finished = container.read(observedTasksProvider).last.finishedAt;
      store.replace('scan', [task('scan', active: false, progress: 1)]);
      expect(container.read(observedTasksProvider).last.finishedAt, finished);
      store.replace('scan', []);
      expect(container.read(observedTasksProvider).single.id, 'cache');
      final retry = _date.add(const Duration(hours: 3));
      store.replace('cache', [task('cache-retry', cache: true, start: retry)]);
      expect(container.read(observedTasksProvider).single.startedAt, retry);
    },
  );

  test(
    'passive health projection invalidates metadata after index changes',
    () async {
      final changes = StreamController<int>();
      final local = source('local');
      final container = ProviderContainer(
        overrides: [
          sidebarSourcesProvider.overrideWith((ref) => [local]),
          sourceChangesProvider.overrideWith((ref) => changes.stream),
          rawLibraryHealthProvider.overrideWith(
            (ref) => throw StateError('must not probe'),
          ),
          sourceReachabilityProvider.overrideWith(
            (ref) => throw StateError('must not connect'),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await changes.close();
      });
      await container.read(sidebarSourcesProvider.future);
      final subscription = container.listen(
        homeRuntimeHealthProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(container.read(homeRuntimeHealthProvider).sourcePercent, isNull);
      container.read(observedHealthProvider.notifier).record(health(local), 0);
      container.read(observedReachabilityProvider.notifier).record(local, true);
      expect(container.read(homeRuntimeHealthProvider).sourcePercent, 100);
      expect(container.read(homeRuntimeHealthProvider).metadataPercent, 45);
      changes.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(homeRuntimeHealthProvider).metadataPercent, isNull);
      expect(container.read(homeRuntimeHealthProvider).sourcePercent, 100);
      expect(container.exists(rawLibraryHealthProvider), false);
      expect(container.exists(sourceReachabilityProvider), false);
    },
  );

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'runtime cards at desktop minimum width $platform dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(764, 350);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final preview = GlobalKey();
          final renderPreview =
              platform == TargetPlatform.windows && Platform.isWindows;
          if (renderPreview) {
            await tester.runAsync(() async {
              for (final entry in {
                'HomeRuntimePreview': 'C:/Windows/Fonts/msyh.ttc',
                'MaterialIcons': 'C:/Users/hzx/development/fvm/versions/3.47.6/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              }.entries) {
                if (!await File(entry.value).exists()) continue;
                final loader = FontLoader(entry.key);
                loader.addFont(
                  File(entry.value).readAsBytes().then(ByteData.sublistView),
                );
                await loader.load();
              }
            });
          }
          final local = source('local');
          final container = ProviderContainer(
            overrides: [
              sidebarSourcesProvider.overrideWith(
                (ref) => [
                  local,
                  for (var i = 0; i < 8; i++) source('long-server-alias-$i'),
                  source(
                    'hidden-alias',
                    type: SourceMediaType.privateCollection,
                  ),
                ],
              ),
              sourceChangesProvider.overrideWith((ref) => const Stream.empty()),
              homeSourceStatsProvider.overrideWith(
                (ref, id) => const HomeStats(movies: 2, series: 1, episodes: 4),
              ),
              sourceRepositoryProvider.overrideWith(
                (ref) => throw StateError('runtime must not read inventory'),
              ),
              rawLibraryHealthProvider.overrideWith(
                (ref) => throw StateError('must not probe'),
              ),
              sourceReachabilityProvider.overrideWith(
                (ref) => throw StateError('must not connect'),
              ),
              embyCacheProvider.overrideWith(
                (ref) => throw StateError('must not initialize cache'),
              ),
            ],
          );
          addTearDown(container.dispose);
          await container.read(sidebarSourcesProvider.future);
          container.read(observedTasksProvider.notifier).replace('scan', [
            task('active', progress: .5),
            task('paused', stateTitle: '已暂停'),
            task('finished', active: false),
            task('fourth', active: false),
          ]);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: RepaintBoundary(
                key: preview,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    fontFamily: renderPreview ? 'HomeRuntimePreview' : null,
                    platform: platform,
                    brightness: dark ? Brightness.dark : Brightness.light,
                  ),
                  home: const Scaffold(body: HomeRuntimeStatus()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('运行状态'), findsOneWidget);
          expect(find.text('hidden-alias'), findsNothing);
          expect(find.text('2 进行中'), findsOneWidget);
          expect(find.text('—/9'), findsOneWidget);
          expect(find.text('进行中'), findsOneWidget);
          expect(find.text('已暂停'), findsOneWidget);
          expect(find.text('已完成'), findsOneWidget);
          expect(find.text('—'), findsNWidgets(3));
          if (renderPreview) {
            await tester.runAsync(() async {
              final boundary =
                  preview.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              try {
                final bytes = await image.toByteData(
                  format: ImageByteFormat.png,
                );
                await Directory('build/home-runtime').create(recursive: true);
                await File(
                  'build/home-runtime/runtime-${dark ? 'dark' : 'light'}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          final list = find.byType(ListView);
          await tester.drag(list, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(find.text('来源 long-server-alias-7'), findsOneWidget);
          expect(container.exists(rawLibraryHealthProvider), false);
          expect(container.exists(sourceReachabilityProvider), false);
          expect(container.exists(embyCacheProvider), false);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  for (final target in ['sources', 'health', 'tasks']) {
    testWidgets('runtime $target card navigates to existing page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: HomeRuntimeStatus()),
          ),
          GoRoute(
            path: '/sources',
            builder: (_, _) => const Text('sources destination'),
          ),
          GoRoute(
            path: '/health',
            builder: (_, _) => const Text('health destination'),
            routes: [
              GoRoute(
                path: 'tasks',
                builder: (_, _) => const Text('tasks destination'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sidebarSourcesProvider.overrideWith((ref) => [source('local')]),
            sourceChangesProvider.overrideWith((ref) => const Stream.empty()),
            homeSourceStatsProvider.overrideWith(
              (ref, id) => const HomeStats(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('home-runtime-$target')));
      await tester.pumpAndSettle();
      expect(find.text('$target destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
