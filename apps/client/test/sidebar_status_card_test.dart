import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelnest/app/runtime_observations.dart';
import 'package:reelnest/domain/library_health.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/home/application/home_providers.dart';
import 'package:reelnest/features/home/application/home_runtime_providers.dart';
import 'package:reelnest/features/home/domain/home_runtime.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/shell/sidebar_status_card.dart';

void main() {
  final now = DateTime(2026, 10, 27, 12);
  final source = MediaSource(
    id: 'source',
    kind: MediaSourceKind.localFolder,
    name: '本地视频',
    location: 'C:/media',
    createdAt: now,
    updatedAt: now,
  );
  final identity = (sourceId: source.id, localId: 'movie');
  final continueVideo = HomeVideo(
    source: source,
    entry: VideoLibraryEntry(
      item: IndexedMedia(
        identity: identity,
        title: '继续观看影片',
        type: 'movie',
        bytes: 0,
        modified: now,
      ),
      record: PlaybackRecord(
        identity: identity,
        position: const Duration(minutes: 20),
        duration: const Duration(hours: 2),
        lastPlayedAt: now,
      ),
      createdAt: now,
    ),
  );

  Future<void> pumpCard(
    WidgetTester tester,
    ProviderContainer container, {
    Brightness brightness = Brightness.light,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(width: 252, child: SidebarStatusCard()),
            ),
          ),
        ),
        GoRoute(
          path: '/health',
          builder: (_, _) => const Scaffold(body: Text('健康中心页面')),
        ),
        GoRoute(
          path: '/sources',
          builder: (_, _) => const Scaffold(body: Text('媒体源页面')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData(brightness: brightness),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer container({
    HomeVideo? continuing,
    LibraryHealthSnapshot? snapshot,
    int observedRevision = 7,
  }) {
    final scope = ProviderContainer(
      overrides: [
        sidebarSourcesProvider.overrideWith((ref) async => [source]),
        sourceChangesProvider.overrideWith((ref) => Stream.value(7)),
        homeRuntimeHealthProvider.overrideWithValue(const HomeRuntimeHealth()),
        homeCollectionProvider.overrideWith(
          (ref, collection) => HomeCollectionState(
            items:
                collection == HomeCollection.continueWatching &&
                    continuing != null
                ? [continuing]
                : const [],
          ),
        ),
      ],
    );
    if (snapshot != null) {
      scope
          .read(observedHealthProvider.notifier)
          .record(snapshot, observedRevision);
    }
    return scope;
  }

  LibraryHealthSnapshot issueSnapshot({
    bool complete = true,
    MediaSource? scannedSource,
  }) {
    const missingID = (sourceId: 'source', localId: 'missing.mkv');
    const duplicateA = (sourceId: 'source', localId: 'duplicate-a.mkv');
    const duplicateB = (sourceId: 'source', localId: 'duplicate-b.mkv');
    final items = [
      IndexedMedia(
        identity: missingID,
        title: '失效影片',
        type: 'movie',
        bytes: 1,
        modified: now,
      ),
      IndexedMedia(
        identity: duplicateA,
        title: '重复影片',
        type: 'movie',
        bytes: 1,
        modified: now,
      ),
      IndexedMedia(
        identity: duplicateB,
        title: '重复影片',
        type: 'movie',
        bytes: 1,
        modified: now,
      ),
    ];
    return LibraryHealthSnapshot(
      inventory: (sources: [scannedSource ?? source], items: items),
      missing: const {missingID},
      safeMissing: const {},
      offline: const {},
      metadataGaps: const {},
      duplicates: [items.sublist(1)],
      evaluationComplete: complete,
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('original card geometry remains stable in $brightness', (
      tester,
    ) async {
      final scope = container();
      addTearDown(scope.dispose);
      await pumpCard(tester, scope, brightness: brightness);

      expect(
        tester.getSize(find.byKey(const ValueKey('sidebar-status-card'))),
        const Size(224, 58),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('sidebar-status-leading'))),
        const Size.square(32),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('sidebar-status-trailing'))),
        const Size.square(25),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'current missing and duplicate health issues rotate and open health',
    (tester) async {
      final scope = container(snapshot: issueSnapshot());
      addTearDown(scope.dispose);
      await pumpCard(tester, scope);

      const titles = {'1 个文件已失效', '发现 1 组疑似重复'};
      final first = tester
          .widget<Text>(find.byKey(const ValueKey('sidebar-status-title')))
          .data;
      expect(titles, contains(first));

      await tester.pump(const Duration(seconds: 60));
      await tester.pump(const Duration(milliseconds: 181));
      final second = tester
          .widget<Text>(find.byKey(const ValueKey('sidebar-status-title')))
          .data;
      expect(titles, contains(second));
      expect(second, isNot(first));

      await tester.tap(
        find.byKey(const ValueKey('sidebar-status-card-action')),
      );
      await tester.pumpAndSettle();
      expect(find.text('健康中心页面'), findsOneWidget);
    },
  );

  testWidgets(
    'stale incomplete or reconfigured health snapshots never surface issues',
    (tester) async {
      final scope = container(snapshot: issueSnapshot(), observedRevision: 6);
      addTearDown(scope.dispose);
      await pumpCard(tester, scope);
      expect(find.text('1 个媒体源'), findsOneWidget);
      expect(find.text('1 个文件已失效'), findsNothing);

      scope
          .read(observedHealthProvider.notifier)
          .record(issueSnapshot(complete: false), 7);
      await tester.pumpAndSettle();
      expect(find.text('1 个媒体源'), findsOneWidget);

      final moved = MediaSource(
        id: source.id,
        kind: source.kind,
        name: source.name,
        location: 'D:/moved',
        createdAt: source.createdAt,
        updatedAt: source.updatedAt,
      );
      scope
          .read(observedHealthProvider.notifier)
          .record(issueSnapshot(scannedSource: moved), 7);
      await tester.pumpAndSettle();
      expect(find.text('1 个媒体源'), findsOneWidget);
      expect(find.text('发现 1 组疑似重复'), findsNothing);
    },
  );

  testWidgets(
    'continue watching participates in the original ambient rotation',
    (tester) async {
      final scope = container(continuing: continueVideo);
      addTearDown(scope.dispose);
      await pumpCard(tester, scope);

      final initiallyContinue = find.text('继续观看影片').evaluate().isNotEmpty;
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      final thenContinue = find.text('继续观看影片').evaluate().isNotEmpty;

      expect(initiallyContinue, isNot(thenContinue));
      expect(find.text(thenContinue ? '继续播放上次内容' : '1 个媒体源'), findsOneWidget);
    },
  );

  testWidgets('cache snapshot rotates without starting a cache disk scan', (
    tester,
  ) async {
    final scope = container();
    addTearDown(scope.dispose);
    await pumpCard(tester, scope);

    scope.read(observedVideoCacheStorageProvider.notifier).record((
      count: 3,
      bytes: 1536 * 1024 * 1024,
      limit: 20,
    ));
    await tester.pumpAndSettle();
    final initiallyCache = find.text('已缓存 3 项离线内容').evaluate().isNotEmpty;
    final initiallyShowsSize = find.text('1.50 GB').evaluate().isNotEmpty;
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    final thenCache = find.text('已缓存 3 项离线内容').evaluate().isNotEmpty;
    final thenShowsSize = find.text('1.50 GB').evaluate().isNotEmpty;

    expect(initiallyCache, isNot(thenCache));
    expect(initiallyShowsSize || thenShowsSize, isTrue);
  });

  testWidgets('a completed task interrupts the rotating card for six seconds', (
    tester,
  ) async {
    final scope = container();
    addTearDown(scope.dispose);
    await pumpCard(tester, scope);
    final active = RuntimeTask(
      id: 'scan-1',
      group: 'scan',
      sourceId: source.id,
      title: '完整扫描 · 本地视频',
      detail: '正在扫描',
      stateTitle: '进行中',
      active: true,
      startedAt: now,
      progress: 0,
    );
    scope.read(observedTasksProvider.notifier).replace('scan', [active]);
    await tester.pumpAndSettle();
    expect(find.text('进行中 · 0%'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('sidebar-status-progress')))
          .width,
      10,
    );

    scope.read(observedTasksProvider.notifier).replace('scan', [
      RuntimeTask(
        id: active.id,
        group: active.group,
        sourceId: active.sourceId,
        title: active.title,
        detail: '扫描完成',
        stateTitle: '已完成',
        active: false,
        startedAt: active.startedAt,
        progress: 1,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('刚刚完成'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('刚刚完成'), findsNothing);
  });
}
