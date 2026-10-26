import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/app/reelnest_app.dart';
import 'package:reelnest/app/runtime_observations.dart';
import 'package:reelnest/app/router.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/source_scan.dart';
import 'package:reelnest/domain/source_settings_draft.dart';
import 'package:reelnest/features/health/application/health_providers.dart';
import 'package:reelnest/features/health/application/missing_index_cleanup.dart';
import 'package:reelnest/features/health/domain/local_health_evaluator.dart';
import 'package:reelnest/features/health/presentation/library_health_page.dart';
import 'package:reelnest/features/home/application/home_runtime_providers.dart';
import 'package:reelnest/features/playback/application/online_subtitle_providers.dart';
import 'package:reelnest/features/metadata/application/tmdb_providers.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/settings/presentation/settings_page.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/source_settings_sheet.dart';
import 'package:reelnest/sources/source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/ui/theme/app_theme.dart';

import 'support/fake_online_subtitle_settings.dart';
import 'support/fake_tmdb_settings.dart';

void main() {
  Finder settingsPageScroll() => find
      .descendant(
        of: find.byType(SettingsPage),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  Future<void> revealHealthSettings(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('数据、存储与诊断'),
      220,
      scrollable: settingsPageScroll(),
    );
    await tester.pumpAndSettle();
    final restore = find.text('恢复显示');
    expect(restore, findsOneWidget);
    await tester.ensureVisible(restore);
    await tester.pumpAndSettle();
  }

  Finder pageScroll() => find
      .descendant(
        of: find.byType(LibraryHealthPage),
        matching: find.byType(Scrollable),
      )
      .first;
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 180, scrollable: pageScroll());
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<SourceRepository> fixture(
    WidgetTester tester, {
    int count = 1,
    bool complete = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1088, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {
        MediaSourceKind.localFolder: _Files(count: count, complete: complete),
      },
    );
    addTearDown(repository.close);
    await repository.add(
      kind: MediaSourceKind.localFolder,
      name: '电影目录',
      location: '/online',
    );
    return repository;
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'video scores and duplicate/detail ignore at minimum size: $brightness',
      (tester) async {
        final repository = await fixture(tester, count: 2, complete: true);
        await repository.scan((await repository.sources()).single.id);
        final router = createRouter();
        addTearDown(router.dispose);
        final preview = GlobalKey();
        // Real fonts make this also exercise Chinese text widths, rather than
        // relying solely on the test font. Other hosts keep their normal fallback.
        if (Platform.isWindows) {
          await tester.runAsync(() async {
            for (final entry in {
              'HealthPreview': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'C:/Users/hzx/development/fvm/versions/3.47.6/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
              final file = File(entry.value);
              if (!await file.exists()) continue;
              final loader = FontLoader(entry.key);
              loader.addFont(file.readAsBytes().then(ByteData.sublistView));
              await loader.load();
            }
          });
        }
        var probes = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sourceRepositoryProvider.overrideWithValue(repository),
              onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
                FakeOnlineSubtitleSettingsRepository(
                  PlayerPreferencesRepository(repository.database),
                ),
              ),
              tmdbSettingsRepositoryProvider.overrideWithValue(
                FakeTmdbSettingsRepository(repository.database),
              ),
              localHealthEvaluatorProvider.overrideWithValue(
                LocalHealthEvaluator(
                  paths: p.Context(style: p.Style.posix),
                  exists: (_) async {
                    probes++;
                    return true;
                  },
                ),
              ),
            ],
            child: RepaintBoundary(
              key: preview,
              child: MaterialApp.router(
                routerConfig: router,
                theme:
                    (brightness == Brightness.dark
                            ? AppTheme.dark
                            : AppTheme.light)
                        .copyWith(
                          textTheme:
                              (brightness == Brightness.dark
                                      ? AppTheme.dark
                                      : AppTheme.light)
                                  .textTheme
                                  .apply(fontFamily: 'HealthPreview'),
                        ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(LibraryHealthPage)),
        );
        container.read(observedTasksProvider.notifier).replace('test', [
          for (var i = 0; i < 3; i++)
            RuntimeTask(
              id: '$i',
              group: 'test',
              sourceId: (await repository.sources()).single.id,
              title: '任务 $i',
              detail: '',
              stateTitle: i == 0 ? '进行中' : '有错误',
              active: i == 0,
              startedAt: DateTime.utc(2026),
            ),
        ]);
        await tester.pumpAndSettle();
        int? homeScore() =>
            container.read(homeRuntimeHealthProvider).totalScore;
        String score(String title) => tester
            .widget<Text>(find.byKey(ValueKey('health-overview-$title')))
            .data!;
        expect(score('健康评分'), '79%');
        expect(score('资料完整'), '88%');
        expect(score('来源可用'), '1/1');
        expect(score('后台任务'), '1');
        expect(find.text('2 个失败可处理'), findsOneWidget);
        expect(homeScore(), 73);
        expect(tester.takeException(), isNull);
        // Keep the two native Windows previews; platform variants still validate
        // the identical minimum desktop layout without overwriting these images.
        if (defaultTargetPlatform == TargetPlatform.windows) {
          await tester.runAsync(() async {
            final boundary =
                preview.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = await image.toByteData(format: ImageByteFormat.png);
              final file = File('build/health-score/${brightness.name}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        final probeCount = probes;
        final ignoreGroup = find.byTooltip('忽略此重复组，可在设置中恢复');
        await reveal(tester, ignoreGroup);
        await tester.tap(ignoreGroup);
        await tester.pumpAndSettle();
        expect(find.text('疑似重复条目'), findsNothing);
        expect(homeScore(), 75);
        for (var i = 0; i < 2; i++) {
          final ignoreDetail = find.byTooltip('忽略此详情资料检查，可在设置中恢复').first;
          await reveal(tester, ignoreDetail);
          await tester.tap(ignoreDetail);
          await tester.pumpAndSettle();
        }
        expect(homeScore(), 100);
        expect(probes, probeCount);
        await tester.tap(find.byKey(const ValueKey('nav-设置')));
        await tester.pumpAndSettle();
        await revealHealthSettings(tester);
        await tester.tap(find.text('恢复显示'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
        await tester.pumpAndSettle();
        expect(score('健康评分'), '79%');
        expect(homeScore(), 73);
        expect(probes, probeCount);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets(
    'dashboard ignore and settings restore keep native-minimum layout usable',
    (tester) async {
      final repository = await fixture(tester);
      final source = (await repository.sources()).single;
      await repository.scan(source.id);
      var probes = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(repository),
            onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
              FakeOnlineSubtitleSettingsRepository(
                PlayerPreferencesRepository(repository.database),
              ),
            ),
            tmdbSettingsRepositoryProvider.overrideWithValue(
              FakeTmdbSettingsRepository(repository.database),
            ),
            localHealthEvaluatorProvider.overrideWithValue(
              LocalHealthEvaluator(
                paths: p.Context(style: p.Style.posix),
                exists: (path) async {
                  probes++;
                  return path == '/online';
                },
              ),
            ),
          ],
          child: const ReelNestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
      await tester.pumpAndSettle();
      expect(find.text('挂载源在线监测'), findsOneWidget);
      await reveal(tester, find.text('缺封面等 3 项'));
      expect(find.text('缺封面等 3 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final count = probes;
      await tester.tap(find.byTooltip('永久忽略此检查结果，可在设置中恢复').first);
      await tester.pumpAndSettle();
      expect(find.text('影视元数据完整，无需补充。'), findsOneWidget);
      expect(probes, count);
      await tester.tap(find.byKey(const ValueKey('nav-设置')));
      await tester.pumpAndSettle();
      await revealHealthSettings(tester);
      expect(find.text('1 项'), findsOneWidget);
      await tester.tap(find.text('恢复显示'));
      await tester.pumpAndSettle();
      expect(find.text('0 项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('缺封面等 3 项'));
      expect(find.text('缺封面等 3 项'), findsOneWidget);
      expect(probes, count);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'missing index confirmation cancels and then removes only the index',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1088, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('reelnest-cleanup-ui-'),
      );
      addTearDown(() async {
        if (root != null &&
            p.isWithin(Directory.systemTemp.path, root.path) &&
            p.basename(root.path).startsWith('reelnest-cleanup-ui-')) {
          await root.delete(recursive: true);
        }
      });
      final repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: _Files()},
        identityLookup: (_) async => 'ui-test-volume',
      );
      addTearDown(repository.close);
      final source = await repository.add(
        kind: MediaSourceKind.localFolder,
        name: '电影目录',
        location: root!.path,
      );
      await repository.scan(source.id);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(repository),
            onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
              FakeOnlineSubtitleSettingsRepository(
                PlayerPreferencesRepository(repository.database),
              ),
            ),
            tmdbSettingsRepositoryProvider.overrideWithValue(
              FakeTmdbSettingsRepository(repository.database),
            ),
            localHealthEvaluatorProvider.overrideWithValue(
              LocalHealthEvaluator(
                paths: p.context,
                exists: (path) async => path == root.path,
                sourceAvailable: repository.isSafeDirectory,
              ),
            ),
            missingIndexCleanupProvider.overrideWithValue(
              MissingIndexCleanup(repository),
            ),
          ],
          child: const ReelNestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('移出索引'),
        180,
        scrollable: pageScroll(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出索引'));
      await tester.pumpAndSettle();
      expect(find.text('确认从索引移除“Film”？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect((await repository.browse(source.id)).total, 1);
      await tester.scrollUntilVisible(
        find.text('清理失效索引'),
        -180,
        scrollable: pageScroll(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理失效索引'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅从 ReelNest 索引移除'));
      // Real filesystem probes complete outside the widget test's virtual clock.
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if ((await repository.browse(source.id)).total == 0) break;
      }
      await tester.pumpAndSettle();
      expect((await repository.browse(source.id)).total, 0);
      expect(await tester.runAsync(root.exists), isTrue);
      expect(find.textContaining('已移除 1 个失效条目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'empty database shows empty states without probes or endless progress',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1088, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      addTearDown(repository.close);
      var probes = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(repository),
            onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
              FakeOnlineSubtitleSettingsRepository(
                PlayerPreferencesRepository(repository.database),
              ),
            ),
            tmdbSettingsRepositoryProvider.overrideWithValue(
              FakeTmdbSettingsRepository(repository.database),
            ),
            localHealthEvaluatorProvider.overrideWithValue(
              LocalHealthEvaluator(
                paths: p.context,
                exists: (_) async {
                  probes++;
                  return false;
                },
              ),
            ),
          ],
          child: const ReelNestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-媒体源')));
      await tester.pumpAndSettle();
      expect(find.text('媒体源待添加'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
      await tester.pumpAndSettle();
      expect(find.text('尚未添加媒体源'), findsOneWidget);
      expect(find.text('暂无媒体库'), findsOneWidget);
      expect(find.text('全部在线'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(probes, 0);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'database failure is explicit on both pages and never pretends to be empty',
    (tester) async {
      final repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      addTearDown(repository.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(repository),
            onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
              FakeOnlineSubtitleSettingsRepository(
                PlayerPreferencesRepository(repository.database),
              ),
            ),
            tmdbSettingsRepositoryProvider.overrideWithValue(
              FakeTmdbSettingsRepository(repository.database),
            ),
            sourcesProvider.overrideWith(
              (_) async => throw const LibrarySchemaMismatch(),
            ),
            rawLibraryHealthProvider.overrideWith(
              (_) async => throw const LibrarySchemaMismatch(),
            ),
          ],
          child: const ReelNestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-媒体源')));
      await tester.pumpAndSettle();
      expect(find.text(LibrarySchemaMismatch.message), findsOneWidget);
      expect(find.text('媒体源待添加'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
      await tester.pumpAndSettle();
      expect(find.text(LibrarySchemaMismatch.message), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'source settings draft cancel and save at minimum size: $brightness',
      (tester) async {
        final repository = await fixture(tester);
        final source = (await repository.sources()).single;
        SourceSettingsDraft? draft;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    draft = await showDialog<SourceSettingsDraft>(
                      context: context,
                      builder: (_) => SourceSettingsSheet(source: source),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('media-type-photo')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('media-type-homeVideo')));
        await tester.pumpAndSettle();
        expect(find.text('参与元数据拉取'), findsNothing);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(draft, isNull);
        expect(
          (await repository.source(source.id)).mediaType,
          SourceMediaType.auto,
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('参与健康检查'));
        await tester.tap(find.widgetWithText(TextButton, '参与健康检查'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存设置'));
        await tester.pumpAndSettle();
        expect(draft!.includeInHealthCheck, isFalse);
        expect(draft!.mediaType, SourceMediaType.auto);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Files implements SourceAdapter {
  _Files({this.count = 1, this.complete = false});
  final int count;
  final bool complete;
  @override
  Future<String> validateLocation(String location) async => location;
  @override
  Future<bool> isReachable(String location) async => true;
  @override
  Stream<SourceScanEvent> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    yield ScanCatalogued(count);
    for (var i = 0; i < count; i++) {
      final path = i == 0 ? 'Film.mkv' : 'Film-$i.mkv';
      yield ScanFileProcessed(
        path: path,
        item: IndexedMedia(
          identity: (sourceId: source.id, localId: path),
          title: 'Film',
          type: 'movie',
          bytes: 0,
          modified: DateTime.utc(2026),
          posterPath: complete ? 'poster.jpg' : null,
          year: complete ? 2026 : null,
          overview: complete ? 'Overview' : null,
        ),
      );
    }
  }
}
