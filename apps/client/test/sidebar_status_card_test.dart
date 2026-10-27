import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/runtime_observations.dart';
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
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SizedBox(width: 252, child: SidebarStatusCard()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer container({HomeVideo? continuing}) => ProviderContainer(
    overrides: [
      sidebarSourcesProvider.overrideWith((ref) async => [source]),
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
      progress: .5,
    );
    scope.read(observedTasksProvider.notifier).replace('scan', [active]);
    await tester.pumpAndSettle();
    expect(find.text('进行中 · 50%'), findsOneWidget);

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
