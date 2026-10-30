import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/home/presentation/widgets/home_video_card.dart';
import 'package:reelnest/features/playback/application/marker_analysis_providers.dart';
import 'package:reelnest/features/playback/data/marker_analysis_repository.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_cache_repository.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_offline_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_task_center.dart';
import 'package:reelnest/features/sources/presentation/marker_analysis_menu.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/ui/theme/app_theme.dart';

class _Scans extends SourceScans {
  @override
  Map<String, SourceScanState> build() => {};
}

class _MarkerController extends PlaybackMarkerAnalysisController {
  _MarkerController(super.repository);

  MediaIdentity? enqueued;
  String? cancelled;
  String? retried;
  var clearCount = 0;

  @override
  Future<String> enqueue(MediaIdentity root) async {
    enqueued = root;
    return 'menu-task';
  }

  @override
  void cancel(String id) {
    cancelled = id;
    tasks.value = [
      for (final task in tasks.value)
        task.id == id
            ? task.copyWith(
                state: MarkerAnalysisState.cancelled,
                finishedAt: DateTime.now().toUtc(),
              )
            : task,
    ];
  }

  @override
  bool canRetry(MarkerAnalysisTask task) =>
      task.state == MarkerAnalysisState.failed;

  @override
  Future<String?> retry(String id) async {
    retried = id;
    tasks.value = [
      for (final task in tasks.value)
        task.id == id ? task.copyWith(state: MarkerAnalysisState.queued) : task,
    ];
    return 'retry-task';
  }

  @override
  Future<void> clearFinished() async {
    clearCount++;
    tasks.value = tasks.value.where((task) => task.active).toList();
  }
}

class _EligibilityProbe {
  int calls = 0;
  Completer<bool>? gate;

  Future<bool> check() {
    calls++;
    return gate?.future ?? Future.value(true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<
    ({
      ProviderContainer container,
      _MarkerController markers,
      _EligibilityProbe eligibility,
      SourceRepository sources,
    })
  >
  fixture(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1088, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    return (await tester.runAsync(() async {
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      await sources.sources();
      final client = EmbyClient(deviceId: 'marker-analysis-ui');
      final connections = EmbyConnectionRepository(
        sources: sources,
        client: Future.value(client),
        stores: (_) => throw StateError('No credentials in widget tests'),
      );
      final cache = EmbyCacheRepository(
        sources: sources,
        connections: connections,
      );
      final offline = EmbyOfflineRepository(sources: sources, cache: cache);
      final markers = _MarkerController(MarkerAnalysisRepository(sources));
      final eligibility = _EligibilityProbe();
      await markers.ready;
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          sourcesProvider.overrideWith((_) async => <MediaSource>[]),
          sourceScansProvider.overrideWith(_Scans.new),
          embyCacheProvider.overrideWithValue(cache),
          embyOfflineProvider.overrideWithValue(offline),
          markerAnalysisProvider.overrideWithValue(markers),
          markerAnalysisEligibilityProvider.overrideWith(
            (ref, id) => eligibility.check(),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await markers.dispose();
        await offline.dispose();
        await cache.dispose();
        connections.dispose();
        client.close();
        await sources.close();
      });
      return (
        container: container,
        markers: markers,
        eligibility: eligibility,
        sources: sources,
      );
    }))!;
  }

  testWidgets('media context menu enqueues the stored root identity', (
    tester,
  ) async {
    final harness = await fixture(tester);
    const identity = (sourceId: 'local', localId: 'Series');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const MaterialApp(
          home: Scaffold(
            body: MarkerAnalysisContextMenu(
              identity: identity,
              child: SizedBox(
                key: ValueKey('marker-context-target'),
                width: 160,
                height: 90,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.eligibility.calls, 0);
    harness.eligibility.gate = Completer<bool>();

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('marker-context-target'))),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.pump();
    expect(harness.eligibility.calls, 1);
    expect(find.text('检测片头片尾'), findsNothing);
    harness.eligibility.gate!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('检测片头片尾'), findsOneWidget);
    await tester.tap(find.text('检测片头片尾'));
    await tester.pump();
    expect(harness.markers.enqueued, identity);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('home card lazily checks and enqueues its series root', (
    tester,
  ) async {
    final harness = await fixture(tester);
    late HomeVideo video;
    await tester.runAsync(() async {
      final source = await harness.sources.add(
        kind: MediaSourceKind.emby,
        name: '首页媒体',
        location: 'emby://fixture/server',
      );
      await harness.sources.database.customStatement(
        '''INSERT INTO media(source_id,local_id,title,type,bytes,modified,identity_kind,is_series)
        VALUES (?,?,?,?,0,1000,'video',1)''',
        [source.id, 'series-root', '首页系列', 'tvShow'],
      );
      await harness.sources.database.customStatement(
        'INSERT INTO playback_states VALUES (?,?,0,120000,0,0)',
        [source.id, 'series-root'],
      );
      video = (await HomeRepository(
        harness.sources,
      ).recommendationCandidates(source.id)).single;
    });
    final identity = video.item.identity;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: HomeVideoCard(video: video)),
        ),
      ),
    );
    await tester.pump();
    expect(harness.eligibility.calls, 0);

    await tester.tap(
      find.byKey(ValueKey('home-open-$identity')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(harness.eligibility.calls, 1);
    expect(find.text('检测片头片尾'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-context-play-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-context-watchlist-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-context-favorite-icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-context-markerAnalysis-icon')),
      findsOneWidget,
    );
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    await tester.tap(find.text('检测片头片尾'));
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (harness.markers.enqueued != null) break;
    }
    expect(harness.markers.enqueued, identity);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('task center shows marker progress and supports all actions', (
    tester,
  ) async {
    final harness = await fixture(tester);
    final now = DateTime.utc(2026, 10, 15);
    harness.markers.tasks.value = [
      MarkerAnalysisTask(
        id: 'running',
        root: (sourceId: 's', localId: 'series'),
        title: '片头片尾检测 · 测试系列',
        startedAt: now,
        state: MarkerAnalysisState.running,
        total: 10,
        processed: 4,
      ),
      MarkerAnalysisTask(
        id: 'failed',
        root: (sourceId: 's', localId: 'episode'),
        title: '片头片尾检测 · 失败影片',
        startedAt: now.subtract(const Duration(minutes: 1)),
        state: MarkerAnalysisState.failed,
        total: 1,
        error: '媒体源配置已变化，请重新检测。',
      ),
      MarkerAnalysisTask(
        id: 'completed',
        root: (sourceId: 's', localId: 'movie'),
        title: '片头片尾检测 · 完成影片',
        startedAt: now.subtract(const Duration(minutes: 2)),
        state: MarkerAnalysisState.completed,
        total: 1,
        processed: 1,
        createdCandidates: 2,
      ),
    ];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const MaterialApp(home: Scaffold(body: EmbyTaskCenterPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('任务记录 · 3 项'), findsOneWidget);
    expect(find.text('已分析 4/10 个视频'), findsOneWidget);
    expect(find.text('新增 2 个待审核标记'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator).first,
    );
    expect(progress.value, .4);

    await tester.tap(find.byTooltip('取消检测'));
    await tester.pump();
    expect(harness.markers.cancelled, 'running');
    expect(find.text('已取消'), findsOneWidget);

    await tester.tap(find.byTooltip('重试任务'));
    await tester.pump();
    expect(harness.markers.retried, 'failed');
    expect(find.text('等待中'), findsOneWidget);

    await tester.tap(find.text('清除记录'));
    await tester.pump();
    expect(harness.markers.clearCount, 1);
    expect(find.textContaining('完成影片'), findsNothing);
    expect(find.textContaining('测试系列'), findsNothing);
    expect(find.textContaining('失败影片'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
