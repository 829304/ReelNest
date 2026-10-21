import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/router.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/home/application/home_providers.dart';
import 'package:reelnest/features/home/application/home_layout_provider.dart';
import 'package:reelnest/features/home/data/home_layout_repository.dart';
import 'package:reelnest/features/home/domain/home_layout.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/home/presentation/home_page.dart';
import 'package:reelnest/features/home/presentation/home_collection_page.dart';
import 'package:reelnest/features/home/presentation/widgets/home_video_card.dart';
import 'package:reelnest/features/home/presentation/widgets/home_hero.dart';
import 'package:reelnest/features/home/presentation/widgets/home_search_results.dart';
import 'package:reelnest/features/home/presentation/widgets/home_layout_editor.dart';
import 'package:reelnest/features/library/data/video_preferences_repository.dart';
import 'package:reelnest/features/playback/application/playback_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/application/emby_library_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/storage/library_database.dart';

class _Launcher implements PlaybackLauncher {
  final opened = <MediaIdentity>[];
  @override
  Future<void> open(MediaIdentity id) async {
    opened.add(id);
  }
}

class _SlowSource extends HomeRepository {
  _SlowSource(super.sources, this.slow);
  final String slow;
  @override
  Future<HomeStats> stats(String id, double threshold) =>
      id == slow ? Completer<HomeStats>().future : super.stats(id, threshold);
  @override
  Future<HomeVideoPage> page(
    String id,
    HomeCollection collection, {
    int offset = 0,
    int limit = 36,
    double threshold = .9,
  }) => id == slow
      ? Completer<HomeVideoPage>().future
      : super.page(
          id,
          collection,
          offset: offset,
          limit: limit,
          threshold: threshold,
        );
}

class _CountingHome extends HomeRepository {
  _CountingHome(super.sources);
  int queries = 0;
  @override
  Future<HomeStats> stats(String sourceId, double threshold) {
    queries++;
    return super.stats(sourceId, threshold);
  }

  @override
  Future<HomeVideoPage> page(
    String sourceId,
    HomeCollection collection, {
    int offset = 0,
    int limit = 36,
    double threshold = .9,
  }) {
    queries++;
    return super.page(
      sourceId,
      collection,
      offset: offset,
      limit: limit,
      threshold: threshold,
    );
  }

  @override
  Future<List<HomeVideo>> recommendationCandidates(String sourceId) {
    queries++;
    return super.recommendationCandidates(sourceId);
  }
}

class _FailingLayout extends HomeLayoutRepository {
  _FailingLayout(super.database);
  bool fail = true;
  @override
  Future<void> save(HomeLayout layout) async {
    if (fail) throw StateError('test disk full');
    await super.save(layout);
  }
}

void main() {
  late SourceRepository sources;
  late MediaSource local;
  setUp(() async {
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    local = await sources.add(
      kind: MediaSourceKind.emby,
      name: '本地电影',
      location: 'emby://fixture/local',
    );
    await sources.database.customStatement(
      "UPDATE sources SET kind='localFolder',last_scan=1 WHERE id=?",
      [local.id],
    );
    local = await sources.source(local.id, includeCounts: false);
  });
  tearDown(() => sources.close());
  Future<void> seed(
    String id, {
    bool series = false,
    bool played = false,
    bool favorite = false,
  }) async {
    await sources.database.customStatement(
      '''INSERT INTO media(source_id,local_id,title,type,bytes,modified,identity_kind,is_series)
      VALUES (?,?,?,?,0,1000,'video',?)''',
      [local.id, id, id, series ? 'tvShow' : 'movie', series ? 1 : 0],
    );
    await sources.database.customStatement(
      'INSERT INTO media_library_preferences VALUES (?,?,1,4,1000)',
      [local.id, id],
    );
    if (played) {
      await sources.database.customStatement(
        'INSERT INTO playback_states VALUES (?,?,20000,100000,0,2000)',
        [local.id, id],
      );
    }
    if (favorite) {
      await VideoPreferencesRepository(sources)
          .setLocalFavorite((sourceId: local.id, localId: id), true);
    }
  }

  Future<void> settle(WidgetTester tester) async {
    // Local file status uses actual asynchronous filesystem I/O.
    for (var n = 0; n < 4; n++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester, {
    HomeRepository? home,
    _Launcher? launcher,
    GlobalKey? preview,
    HomeLayoutRepository? layoutRepository,
    Size size = const Size(1280, 900),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createRouter();
    addTearDown(router.dispose);
    if (preview != null && Platform.isWindows) {
      await tester.runAsync(() async {
        final fonts = {
          'HomePreview': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons': 'C:/Users/hzx/development/fvm/versions/3.47.6/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        };
        for (final entry in fonts.entries) {
          if (!await File(entry.value).exists()) continue;
          final loader = FontLoader(entry.key);
          loader.addFont(
            File(entry.value)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          );
          await loader.load();
        }
      });
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          if (home != null) homeRepositoryProvider.overrideWithValue(home),
          if (layoutRepository != null)
            homeLayoutRepositoryProvider.overrideWithValue(layoutRepository),
          if (launcher != null)
            playbackLauncherProvider.overrideWithValue(launcher),
          embyVideoSnapshotProvider.overrideWith(
            (ref, id) =>
                throw StateError('home must not subscribe to full snapshots'),
          ),
        ],
        child: RepaintBoundary(
          key: preview,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(
              brightness: brightness,
              fontFamily: preview == null ? null : 'HomePreview',
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'homepage editing reorders by mouse without requerying or disposing strips',
    (tester) async {
      for (var i = 0; i < 20; i++) {
        await seed('收藏影片 $i', favorite: true);
      }
      final counting = _CountingHome(sources);
      final launcher = _Launcher();
      await pump(tester, home: counting, launcher: launcher);
      final favorites = find.byKey(
        const ValueKey(HomeCollection.favorites),
        skipOffstage: false,
      );
      await tester.ensureVisible(favorites);
      await settle(tester);
      final rowState = tester.state(favorites);
      final horizontal = find.descendant(
        of: favorites,
        matching: find.byType(Scrollable),
      );
      await tester.drag(horizontal, const Offset(-300, 0));
      await settle(tester);
      final horizontalState = tester.state<ScrollableState>(horizontal);
      final offset = horizontalState.position.pixels;
      expect(offset, greaterThan(0));
      expect(find.byType(LocalMediaDetailPage), findsNothing);
      final queries = counting.queries;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-edit')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('home-edit'))),
        alignment: .5,
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomePage)),
      );
      final controller = container.read(homeLayoutProvider.notifier);
      controller.move(HomeModule.favorites, HomeModule.stats);
      await settle(tester);
      expect(tester.state(favorites), same(rowState));
      expect(horizontalState.position.pixels, offset);
      Finder module(HomeModule module) => find.byWidgetPredicate(
        (widget) => widget is HomeEditableModule && widget.module == module,
        skipOffstage: false,
      );
      await tester.ensureVisible(module(HomeModule.favorites));
      await settle(tester);
      final start = tester.getCenter(module(HomeModule.stats));
      final target = tester.getCenter(module(HomeModule.favorites));
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveTo(target);
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await settle(tester);
      final layout = container.read(homeLayoutProvider).layout;
      expect(
        layout.order.indexOf(HomeModule.stats),
        lessThan(layout.order.indexOf(HomeModule.favorites)),
      );
      expect(tester.state(favorites), same(rowState));
      expect(horizontalState.position.pixels, offset);
      expect(counting.queries, queries);
      expect(launcher.opened, isEmpty);
      expect(tester.takeException(), isNull);

      // Removing is the original right-click action, rather than a new inline X.
      await tester.ensureVisible(module(HomeModule.favorites));
      await settle(tester);
      await tester.tapAt(
        tester.getCenter(module(HomeModule.favorites)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除收藏'));
      await settle(tester);
      expect(favorites, findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-layout-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-add-favorites')));
      await settle(tester);
      expect(
        container.read(homeLayoutProvider).layout.order.last,
        HomeModule.favorites,
      );
      await tester.ensureVisible(favorites);
      await settle(tester);
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(of: favorites, matching: find.byType(Scrollable)),
            )
            .position
            .pixels,
        offset,
      );
      expect(counting.queries, queries);
      await tester.tap(find.byKey(const ValueKey('home-layout-done')));
      await settle(tester);
      expect(find.byType(HomeLayoutEditorDock), findsNothing);
      expect(launcher.opened, isEmpty);
      final saved = await HomeLayoutRepository(sources.database).load();
      expect(saved.order.last, HomeModule.favorites);
      await tester.pumpWidget(const SizedBox.shrink());
      await pump(tester, home: counting);
      final restarted = ProviderScope.containerOf(
        tester.element(find.byType(HomePage)),
      );
      expect(restarted.read(homeLayoutProvider).layout.sameAs(saved), true);
      expect(restarted.read(homeLayoutProvider).editing, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'layout save failure keeps editor and draft; retry and reset save without touching videos',
    (tester) async {
      await seed('保留影片');
      final repository = _FailingLayout(sources.database);
      await pump(tester, layoutRepository: repository);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-edit')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomePage)),
      );
      container.read(homeLayoutProvider.notifier).hide(HomeModule.hero);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('home-layout-done')));
      await settle(tester);
      expect(find.byType(HomeLayoutEditorDock), findsOneWidget);
      expect(find.text('首页布局保存失败，当前调整已保留，请重试。'), findsOneWidget);
      expect(find.byType(HomeHero), findsNothing);
      repository.fail = false;
      await tester.tap(find.text('重试'));
      await settle(tester);
      expect((await repository.load()).hidden, {HomeModule.hero});
      expect(find.text('首页布局保存失败，当前调整已保留，请重试。'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-layout-reset')));
      await settle(tester);
      expect(find.byType(HomeHero), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-layout-done')));
      await settle(tester);
      expect((await repository.load()).canReset, false);
      expect(
        (await sources.browse(local.id, topLevelOnly: true)).items.single.title,
        '保留影片',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'edit dock follows overview/search and add popover exposes no deferred modules',
    (tester) async {
      await seed('影片');
      await pump(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-edit')),
        400,
        scrollable: find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('home-layout-add')));
      await tester.pumpAndSettle();
      expect(find.text('所有组件均已添加'), findsOneWidget);
      expect(find.text('音乐推荐'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('home-search-field'));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(HomePage)),
          scrollDelta: const Offset(0, -3000),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(search, '影片');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 180));
      await settle(tester);
      expect(find.byType(HomeLayoutEditorDock), findsNothing);
      await tester.enterText(search, '');
      await tester.pump(const Duration(milliseconds: 180));
      await settle(tester);
      expect(find.byType(HomeLayoutEditorDock), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'home editor dock and add panel fit minimum desktop $brightness',
      (tester) async {
        await seed('布局预览影片');
        final preview = GlobalKey();
        await pump(
          tester,
          preview: preview,
          size: const Size(1088, 720),
          brightness: brightness,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('home-edit')),
          400,
          scrollable: find
              .descendant(
                of: find.byType(HomePage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle(tester);
        await Scrollable.ensureVisible(
          tester.element(find.byKey(const ValueKey('home-edit'))),
          alignment: .5,
        );
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('home-edit')));
        await settle(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomePage)),
        );
        container.read(homeLayoutProvider.notifier).hide(HomeModule.stats);
        container.read(homeLayoutProvider.notifier).hide(HomeModule.highRated);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('home-layout-add')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-add-stats')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home-add-highRated')),
          findsOneWidget,
        );
        expect(
          tester
              .getBottomRight(find.byKey(const ValueKey('home-add-highRated')))
              .dy,
          lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('home-layout-add'))).dy,
          ),
        );
        expect(tester.takeException(), isNull);
        if (Theme.of(tester.element(find.byType(HomePage))).platform ==
            TargetPlatform.windows) {
          await tester.runAsync(() async {
            final boundary =
                preview.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = await image.toByteData(format: ImageByteFormat.png);
              await Directory('build/home-layout').create(recursive: true);
              await File(
                'build/home-layout/editor-${brightness == Brightness.dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('home-layout-reset')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('home-layout-done')));
        await settle(tester);
        expect(find.byType(HomeLayoutEditorDock), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets('dragging near viewport edge scrolls and release stops it', (
    tester,
  ) async {
    for (var i = 0; i < 20; i++) {
      await seed('影片$i', favorite: true);
    }
    await pump(tester);
    final homeScroll = find
        .descendant(
          of: find.byType(HomePage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('home-edit')),
      400,
      scrollable: homeScroll,
    );
    await tester.tap(find.byKey(const ValueKey('home-edit')));
    await settle(tester);
    final stats = find.byWidgetPredicate(
      (w) => w is HomeEditableModule && w.module == HomeModule.stats,
      skipOffstage: false,
    );
    await tester.ensureVisible(stats);
    await settle(tester);
    final scroll = tester.state<ScrollableState>(homeScroll).position;
    final before = scroll.pixels;
    final gesture = await tester.startGesture(
      tester.getCenter(stats),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveTo(
      Offset(
        tester.getCenter(stats).dx,
        tester.getBottomRight(find.byType(HomePage)).dy - 4,
      ),
    );
    await tester.pump(const Duration(milliseconds: 160));
    expect(scroll.pixels, greaterThan(before));
    await gesture.up();
    await settle(tester);
    final stopped = scroll.pixels;
    await tester.pump(const Duration(milliseconds: 200));
    expect(scroll.pixels, stopped);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'homepage search debounces, submits immediately and clears back to overview',
    (tester) async {
      await seed('贝加尔湖');
      await seed('其他影片');
      await pump(tester);
      final field = find.byKey(const ValueKey('home-search-field'));
      await tester.enterText(field, 'bje');
      await tester.pump(const Duration(milliseconds: 179));
      expect(find.byType(HomeSearchResults), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await settle(tester);
      expect(find.byType(HomeSearchResults), findsOneWidget);
      expect(
        find.byKey(
          ValueKey('home-search-open-${(sourceId: local.id, localId: '贝加尔湖')}'),
        ),
        findsOneWidget,
      );
      expect(find.text('其他影片'), findsNothing);
      await tester.enterText(field, '没有这个标题');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        tester.widget<HomeSearchResults>(find.byType(HomeSearchResults)).query,
        '没有这个标题',
      );
      await settle(tester);
      expect(find.text('无匹配结果'), findsOneWidget);
      await tester.enterText(field, '');
      await tester.pump(const Duration(milliseconds: 180));
      await settle(tester);
      expect(find.byType(HomeSearchResults), findsNothing);
      expect(find.byKey(const ValueKey('home-stat-影片')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'lazy search retains query and scroll across refresh and detail return',
    (tester) async {
      for (var n = 0; n < 48; n++) {
        await seed('影片$n');
      }
      await pump(tester);
      final field = find.byKey(const ValueKey('home-search-field'));
      await tester.enterText(field, '影片');
      await tester.pump(const Duration(milliseconds: 180));
      await settle(tester);
      final view = find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(CustomScrollView),
      );
      final scrollable = find
          .descendant(of: view, matching: find.byType(Scrollable))
          .first;
      final state = tester.state<ScrollableState>(scrollable);
      expect(
        find.text('影片47'),
        findsNothing,
        reason: 'offscreen rows are lazy',
      );
      await tester.drag(view, const Offset(0, -1100));
      await settle(tester);
      final offset = state.position.pixels;
      expect(offset, greaterThan(600));
      sources.traceChanged();
      await settle(tester);
      expect(tester.state(scrollable), same(state));
      expect(state.position.pixels, closeTo(offset, .5));
      final rows = find.byWidgetPredicate(
        (w) =>
            w is InkWell &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('home-search-open-'),
      );
      final visible = rows.hitTestable().first;
      await tester.tap(visible);
      await settle(tester);
      expect(find.byType(LocalMediaDetailPage), findsOneWidget);
      await tester.tap(find.text('返回').last);
      await settle(tester);
      expect(
        tester.widget<HomeSearchResults>(find.byType(HomeSearchResults)).query,
        '影片',
      );
      expect(tester.state(scrollable), same(state));
      expect(state.position.pixels, closeTo(offset, .5));
      state.position.jumpTo(0);
      await settle(tester);
      expect(tester.widget<TextField>(field).controller!.text, '影片');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'search header and grouped rows render at desktop minimum width',
    (tester) async {
      await seed('影片1');
      await seed('影片2');
      await seed('影片系列', series: true);
      final preview = GlobalKey();
      await pump(tester, preview: preview);
      tester.view.physicalSize = const Size(1088, 720);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('home-search-field')),
        '影片',
      );
      await tester.pump(const Duration(milliseconds: 180));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            preview.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          await Directory('build/home-search').create(recursive: true);
          await File('build/home-search/search-preview.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'home chrome uses focused search, elevated stats and neutral section actions',
    (tester) async {
      for (var n = 0; n < 3; n++) {
        await seed('视觉影片$n');
      }
      await pump(
        tester,
        size: const Size(1088, 720),
        brightness: Brightness.dark,
      );

      final searchSurface = find.byKey(const ValueKey('home-search-surface'));
      final beforeSearch = tester.widget<AnimatedContainer>(searchSurface);
      final beforeBorder =
          (beforeSearch.decoration! as BoxDecoration).border! as Border;
      await tester.tap(find.byKey(const ValueKey('home-search-field')));
      await tester.pump(const Duration(milliseconds: 180));
      final afterSearch = tester.widget<AnimatedContainer>(searchSurface);
      final afterBorder =
          (afterSearch.decoration! as BoxDecoration).border! as Border;
      expect(afterBorder.top.color, isNot(beforeBorder.top.color));

      final stat = find.byKey(const ValueKey('home-stat-card-影片'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(stat));
      await tester.pump(const Duration(milliseconds: 180));
      final elevated = tester.widget<AnimatedContainer>(stat);
      expect(elevated.transform!.getTranslation().y, -4);
      expect((elevated.decoration! as BoxDecoration).boxShadow, isNotEmpty);

      await tester.drag(
        find.descendant(
          of: find.byType(HomePage),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -420),
      );
      await settle(tester);
      final dashboardButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('进入仪表盘 ›'),
          matching: find.byType(TextButton),
        ),
      );
      final actionColor = dashboardButton.style?.foregroundColor?.resolve({});
      expect(
        actionColor,
        isNot(Theme.of(tester.element(stat)).colorScheme.primary),
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets('home overview remains usable in compact desktop viewport', (
    tester,
  ) async {
    for (var n = 0; n < 3; n++) {
      await seed('紧凑影片$n');
    }
    await pump(tester, size: const Size(680, 382), brightness: Brightness.dark);
    expect(find.byKey(const ValueKey('home-search-field')), findsOneWidget);
    expect(find.byType(HomeHero), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(CustomScrollView),
      ),
      const Offset(0, -720),
    );
    await settle(tester);
    expect(find.text('运行状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets(
    'home displays cached modules, plays, enters details and returns in its own branch',
    (tester) async {
      await seed('本地影片', played: true, favorite: true);
      await seed('测试电视剧', series: true, favorite: true);
      final launcher = _Launcher();
      final preview = GlobalKey();
      await pump(tester, launcher: launcher, preview: preview);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('继续观看 · 剧集'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('home-stat-影片'))).data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('home-stat-系列'))).data,
        '1',
      );
      final film = (sourceId: local.id, localId: '本地影片');
      await tester.ensureVisible(find.byKey(ValueKey('home-open-$film')).first);
      await settle(tester);
      await tester.tap(
        find.byKey(ValueKey('home-open-$film')).first,
        buttons: 2,
      );
      await settle(tester);
      await tester.tap(find.text('播放').last);
      await settle(tester);
      expect(launcher.opened, [film]);
      await tester.tap(find.byKey(ValueKey('home-open-$film')).first);
      await settle(tester);
      expect(find.byType(LocalMediaDetailPage), findsOneWidget);
      await tester.tap(find.text('返回'));
      await settle(tester);
      expect(find.byType(LocalMediaDetailPage), findsNothing);
      // Widget render inspection is separate from release/native verification.
      await tester.runAsync(() async {
        final boundary =
            preview.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        await Directory('build/home-h1').create(recursive: true);
        await File('build/home-h1/home-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'view-more reads beyond 36 and detail return restores the collection',
    (tester) async {
      for (var n = 0; n < 50; n++) {
        await seed('影片 ${n.toString().padLeft(2, '0')}', favorite: true);
      }
      await pump(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-more-favorites')),
        350,
        scrollable: find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-more-favorites')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('home-more-favorites')));
      await settle(tester);
      expect(find.byType(HomeCollectionPage), findsOneWidget);
      expect(find.text('已载入 36 项'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(
          ValueKey('home-open-${(sourceId: local.id, localId: '影片 49')}'),
        ),
        450,
        scrollable: find.byType(Scrollable).last,
      );
      final card = tester.widget<HomeVideoCard>(
        find.byType(HomeVideoCard).last,
      );
      await tester.tap(
        find.byKey(ValueKey('home-open-${card.video.item.identity}')),
      );
      await settle(tester);
      expect(find.byType(LocalMediaDetailPage), findsOneWidget);
      await tester.tap(find.text('返回'));
      await settle(tester);
      expect(find.byType(HomeCollectionPage), findsOneWidget);
      final scroll = tester.widget<CustomScrollView>(
        find.descendant(
          of: find.byType(HomeCollectionPage),
          matching: find.byType(CustomScrollView),
        ),
      );
      scroll.controller!.jumpTo(0);
      await settle(tester);
      expect(find.text('已载入 50 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'new movie-only library has hero without any watchlist favorites or playback',
    (tester) async {
      for (var n = 0; n < 3; n++) {
        await seed('新影片$n');
      }
      await sources.database.customStatement(
        'UPDATE media_library_preferences SET watchlist=0,user_rating=NULL',
      );
      final launcher = _Launcher();
      final preview = GlobalKey();
      await pump(tester, launcher: launcher, preview: preview);
      expect(find.byType(HomeHero), findsOneWidget);
      expect(find.text('继续观看 · 剧集'), findsNothing);
      expect(find.text('收藏'), findsNothing);
      await tester.runAsync(() async {
        final boundary =
            preview.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          await Directory('build/home-h2').create(recursive: true);
          await File('build/home-h2/home-preview.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      await tester.tap(find.text('立即播放'));
      await settle(tester);
      expect(launcher.opened, hasLength(1));
      await tester.tap(find.text('＋ 加入想看'));
      await settle(tester);
      expect(find.text('✓ 已想看'), findsOneWidget);
      expect(find.text('想看'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-hero-dot-1')));
      await settle(tester);
      expect(find.text('＋ 加入想看'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets(
    'recommendation view-more keeps board order and returns to overview',
    (tester) async {
      for (var n = 0; n < 20; n++) {
        await seed('剧集$n', series: true);
      }
      await pump(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('home-more-seriesRecommendations')),
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('home-more-seriesRecommendations')),
      );
      await settle(tester);
      expect(find.byType(HomeCollectionPage), findsOneWidget);
      expect(find.text('剧集推荐'), findsOneWidget);
      await tester.tap(find.text('返回'));
      await settle(tester);
      expect(find.byType(HomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'one slow source does not hide available content or falsely report empty',
    (tester) async {
      await seed('可用影片', played: true);
      final slow = await sources.add(
        kind: MediaSourceKind.emby,
        name: '慢来源',
        location: 'emby://fixture/slow',
      );
      await sources.database.customStatement(
        'UPDATE sources SET last_scan=1 WHERE id=?',
        [slow.id],
      );
      await pump(tester, home: _SlowSource(sources, slow.id));
      expect(find.text('可用影片'), findsWidgets);
      expect(find.text('媒体源待添加'), findsNothing);
      expect(find.text('正在整理媒体库… 已有内容可先浏览。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
