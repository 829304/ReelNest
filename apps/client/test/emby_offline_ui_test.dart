import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_quality.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_cache_repository.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_offline_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_offline_menu.dart';
import 'package:reelnest/features/sources/presentation/emby_task_center.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/ui/widgets/source_sheet_button.dart';

class _Cache extends EmbyCacheRepository {
  _Cache({required super.sources, required super.connections});
  void changed() => tasks.value = {...tasks.value};
  @override
  void pause(VideoCacheTask task) {
    task.state = VideoCacheTaskState.paused;
    changed();
  }

  @override
  Future<void> resume(VideoCacheTask task) async {
    task.state = VideoCacheTaskState.queued;
    changed();
  }

  @override
  Future<void> cancel(VideoCacheTask task) async {
    task.state = VideoCacheTaskState.cancelled;
    changed();
  }

  @override
  Future<void> enqueue(IndexedMedia item, EmbyVideoQuality quality) async {
    tasks.value[item.identity]!.state = VideoCacheTaskState.queued;
    changed();
  }
}

VideoCacheTask task(String id, VideoCacheTaskState state) =>
    VideoCacheTask(
        IndexedMedia(
          identity: (sourceId: 's', localId: id),
          title: id,
          type: 'movie',
          bytes: 100,
          modified: DateTime.utc(2026),
        ),
        EmbyVideoQuality.source,
      )
      ..state = state
      ..expected = 100
      ..received = 25;

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'offline limit sheet: $platform $brightness bounds, draft and save',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1088, 720);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          int? saved;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform, brightness: brightness),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      saved = await showDialog<int>(
                        context: context,
                        builder: (_) => const OfflineLimitSheet(title: '测试系列'),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          final content = find.descendant(
            of: find.byType(Dialog),
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width == 500,
            ),
          );
          expect(tester.getSize(content).width, 500);
          await tester.enterText(find.byType(TextField), '0');
          await tester.pump();
          expect(
            tester
                .widget<SourceSheetButton>(
                  find.widgetWithText(SourceSheetButton, '保存'),
                )
                .onPressed,
            isNull,
          );
          await tester.enterText(find.byType(TextField), '99');
          await tester.pump();
          expect(
            tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (w) => w is IconButton && w.tooltip == '增加集数',
                  ),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byTooltip('减少集数'));
          await tester.pump();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '98',
          );
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(saved, isNull);
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '3',
          );
          await tester.tap(find.text('保存'));
          await tester.pumpAndSettle();
          expect(saved, 3);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  Future<ProviderContainer> fixture(
    WidgetTester tester, {
    List<VideoCacheTask> tasks = const [],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1088, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    // The repositories own real asynchronous Futures; construct and retire
    // them outside the widget clock, like the local HTTP repository fixtures.
    return (await tester.runAsync(() async {
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      await sources.sources();
      final client = EmbyClient(deviceId: 'offline-widget-fixture');
      final connections = EmbyConnectionRepository(
        sources: sources,
        client: Future.value(client),
        stores: (_) =>
            throw StateError('Widget test must not access credentials'),
      );
      final cache = _Cache(sources: sources, connections: connections);
      cache.tasks.value = {for (final t in tasks) t.item.identity: t};
      final offline = EmbyOfflineRepository(sources: sources, cache: cache);
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          sourcesProvider.overrideWith((_) async => <MediaSource>[]),
          embyCacheProvider.overrideWithValue(cache),
          embyOfflineProvider.overrideWithValue(offline),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await offline.dispose();
        await cache.dispose();
        connections.dispose();
        client.close();
        await sources.close();
      });
      return container;
    }))!;
  }

  testWidgets(
    'empty task center displays empty state without scan or progress',
    (tester) async {
      final container = await fixture(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: EmbyTaskCenterPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无后台任务'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'task center keeps active first and supports resume, pause, cancel, retry and clearing',
    (tester) async {
      final finished = task('finished', VideoCacheTaskState.complete);
      final paused = task('paused', VideoCacheTaskState.paused);
      final failed = task('failed', VideoCacheTaskState.failed);
      final container = await fixture(
        tester,
        tasks: [finished, paused, failed],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: EmbyTaskCenterPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('缓存 · paused')).dy,
        lessThan(tester.getTopLeft(find.text('缓存 · finished')).dy),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip('继续缓存'));
      await tester.pump();
      expect(paused.state, VideoCacheTaskState.queued);
      await tester.tap(find.byTooltip('暂停缓存'));
      await tester.pump();
      expect(paused.state, VideoCacheTaskState.paused);
      await tester.tap(find.byTooltip('取消缓存'));
      await tester.pump();
      expect(paused.state, VideoCacheTaskState.cancelled);
      await tester.tap(find.byTooltip('重试任务'));
      await tester.pump();
      expect(failed.state, VideoCacheTaskState.queued);
      await tester.tap(find.text('清除记录'));
      await tester.pump();
      expect(container.read(embyCacheProvider).tasks.value.keys, [
        failed.item.identity,
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'cache usage is a static capacity meter, including an empty library',
    (tester) async {
      final container = await fixture(tester);
      final child = ProviderScope(
        overrides: [
          embyCacheStorageProvider.overrideWith(
            (_) async => (count: 0, bytes: 0, limit: 0.0),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: EmbyCacheDashboard())),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: child),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 个缓存'), findsOneWidget);
      expect(
        tester
            .widget<FractionallySizedBox>(
              find.byKey(const ValueKey('cache-storage-fraction')),
            )
            .widthFactor,
        0,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
