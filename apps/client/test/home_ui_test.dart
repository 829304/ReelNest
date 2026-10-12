import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/router.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/home/application/home_providers.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/home/presentation/home_page.dart';
import 'package:reelnest/features/home/presentation/home_collection_page.dart';
import 'package:reelnest/features/home/presentation/widgets/home_video_card.dart';
import 'package:reelnest/features/home/presentation/widgets/home_hero.dart';
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
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
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
            theme: preview == null
                ? null
                : ThemeData(fontFamily: 'HomePreview'),
          ),
        ),
      ),
    );
    await settle(tester);
  }

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
        scrollable: find.byType(Scrollable).first,
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
