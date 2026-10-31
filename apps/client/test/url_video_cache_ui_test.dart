import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_quality.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/application/url_video_providers.dart';
import 'package:reelnest/features/sources/data/emby_cache_repository.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/data/url_video_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_task_center.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/features/sources/presentation/url_video_cache_actions.dart';
import 'package:reelnest/features/sources/presentation/url_video_context_menu.dart';
import 'package:reelnest/storage/library_database.dart';

class _Scans extends SourceScans {
  @override
  build() => const {};
}

class _Cache extends EmbyCacheRepository {
  _Cache({required super.sources, required super.connections});

  final cached = <CachedVideo>[];
  final enqueued = <({MediaIdentity identity, String quality})>[];
  final removed = <MediaIdentity>[];

  @override
  Future<List<CachedVideo>> entries({MediaIdentity? identity}) async =>
      List.unmodifiable(
        identity == null
            ? cached
            : cached.where((entry) => entry.identity == identity),
      );

  @override
  Future<void> enqueue(IndexedMedia item, EmbyVideoQuality quality) async {
    enqueued.add((identity: item.identity, quality: quality.id));
    final existing = tasks.value[item.identity];
    if (existing != null) {
      existing
        ..state = VideoCacheTaskState.queued
        ..error = null;
      tasks.value = {...tasks.value};
    }
  }

  @override
  Future<void> maintenance({
    bool clear = false,
    MediaIdentity? remove,
    String? protectedBundle,
  }) async {
    if (remove == null) return;
    removed.add(remove);
    cached.removeWhere((entry) => entry.identity == remove);
    sources.traceChanged();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SourceRepository sources;
  late UrlVideoRepository urls;
  late EmbyClient client;
  late EmbyConnectionRepository connections;
  late _Cache cache;
  late IndexedMedia httpVideo;
  late IndexedMedia rtspVideo;
  late IndexedMedia hlsVideo;

  setUp(() async {
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: const {},
    );
    urls = UrlVideoRepository(sources);
    await urls.add('https://media.example/movie.mp4', title: 'HTTP 视频');
    await urls.add('rtsp://media.example/live', title: 'RTSP 视频');
    await urls.add('https://media.example/live.m3u8', title: 'HLS 视频');
    final values = await urls.list();
    Future<IndexedMedia> media(String title) => sources.media(
      values.firstWhere((value) => value.title == title).identity,
    );
    httpVideo = await media('HTTP 视频');
    rtspVideo = await media('RTSP 视频');
    hlsVideo = await media('HLS 视频');
    client = EmbyClient(deviceId: 'url-cache-ui-test');
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (_) => throw StateError('URL cache UI must not authenticate'),
    );
    cache = _Cache(sources: sources, connections: connections);
  });

  tearDown(() async {
    await cache.dispose();
    connections.dispose();
    client.close();
    await sources.close();
  });

  Widget app(Widget child) => ProviderScope(
    overrides: [
      sourceRepositoryProvider.overrideWithValue(sources),
      urlVideoRepositoryProvider.overrideWithValue(urls),
      embyCacheProvider.overrideWithValue(cache),
      sourceScansProvider.overrideWith(_Scans.new),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  String downloadKey(IndexedMedia item) =>
      'cache-video-${item.identity.sourceId}-${item.identity.localId}-original';
  String deleteKey(IndexedMedia item) =>
      'delete-cache-${item.identity.sourceId}-${item.identity.localId}';

  testWidgets(
    'HTTP exposes download while RTSP and HLS stay disabled and cached RTSP remains removable',
    (tester) async {
      cache.cached.add(
        CachedVideo(rtspVideo.identity, 'cached-rtsp', 'video.mp4', 1024, '原画'),
      );
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 460,
            child: Column(
              children: [
                UrlVideoContextMenu(
                  item: httpVideo,
                  child: const SizedBox(
                    key: ValueKey('url-cache-context-target'),
                    width: 180,
                    height: 72,
                  ),
                ),
                UrlVideoCacheActions(item: rtspVideo, menuOnly: true),
                UrlVideoCacheActions(item: hlsVideo, menuOnly: true),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(
        tester.getCenter(
          find.byKey(const ValueKey('url-cache-context-target')),
        ),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      final http = tester.widget<MenuItemButton>(
        find.byKey(ValueKey(downloadKey(httpVideo))),
      );
      final rtsp = tester.widget<MenuItemButton>(
        find.byKey(ValueKey(downloadKey(rtspVideo))),
      );
      final hls = tester.widget<MenuItemButton>(
        find.byKey(ValueKey(downloadKey(hlsVideo))),
      );
      expect(http.onPressed, isNotNull);
      expect(rtsp.onPressed, isNull);
      expect(hls.onPressed, isNull);
      expect(find.text('仅 HTTP/HTTPS 直链可离线缓存'), findsNWidgets(2));

      await tester.tap(find.byKey(ValueKey(downloadKey(httpVideo))));
      await tester.pump();
      expect(cache.enqueued, [
        (identity: httpVideo.identity, quality: 'original'),
      ]);

      final remove = find.byKey(ValueKey(deleteKey(rtspVideo)));
      expect(remove, findsOneWidget);
      expect(tester.widget<MenuItemButton>(remove).onPressed, isNotNull);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(cache.removed, [rtspVideo.identity]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('URL detail action bar exposes the shared cache control', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1088, 820);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      app(LocalMediaDetailPage(identity: httpVideo.identity)),
    );
    await tester.pumpAndSettle();

    final actions = find.byKey(const ValueKey('media-detail-actions'));
    expect(actions, findsOneWidget);
    expect(
      find.descendant(of: actions, matching: find.byType(UrlVideoCacheActions)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: actions,
        matching: find.byKey(
          ValueKey(
            'cache-video-popup-${httpVideo.identity.sourceId}-${httpVideo.identity.localId}',
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('task center retries a failed URL cache with original quality', (
    tester,
  ) async {
    final task = VideoCacheTask(httpVideo, EmbyVideoQuality.source)
      ..state = VideoCacheTaskState.failed
      ..error = '下载失败（HTTP 500）。';
    cache.tasks.value = {httpVideo.identity: task};
    await tester.pumpWidget(app(const EmbyTaskCenterPage()));
    await tester.pumpAndSettle();

    expect(find.text('缓存 · HTTP 视频'), findsOneWidget);
    expect(find.text('下载失败（HTTP 500）。'), findsOneWidget);
    final retry = find.byTooltip('重试任务');
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    expect(task.state, VideoCacheTaskState.queued);
    await tester.pump(const Duration(milliseconds: 16));

    expect(cache.enqueued, [
      (identity: httpVideo.identity, quality: 'original'),
    ]);
    expect(task.error, isNull);
    expect(tester.takeException(), isNull);
  });
}
