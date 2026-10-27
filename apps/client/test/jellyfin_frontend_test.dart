import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_sidebar.dart';
import 'package:reelnest/features/sources/presentation/emby_video_library_page.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/features/sources/presentation/media_server_brand_mark.dart';
import 'package:reelnest/features/sources/presentation/source_library_page.dart';
import 'package:reelnest/features/sources/presentation/sources_page.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/emby_server_fixture.dart';

class _Store implements CredentialStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}

class _Http extends HttpOverrides {}

Map<String, dynamic> _movie(String id, String title) => {
  'Id': id,
  'Name': title,
  'Type': 'Movie',
  'ProductionYear': 2026,
  'CommunityRating': 8.8,
  'RunTimeTicks': 900000000,
  'Overview': 'Jellyfin fixture overview',
  'Genres': ['剧情'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late Map<String, _Store> stores;
  var resourcesClosed = false;

  setUp(() async {
    resourcesClosed = false;
    server = EmbyServerFixture(kind: MediaSourceKind.jellyfin);
    server.catalog['movies'] = [_movie('film', 'Jellyfin 影片')];
    await server.start();
    client = EmbyClient(
      deviceId: 'jellyfin-frontend-test',
      http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
    );
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    stores = {};
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores.putIfAbsent(id, _Store.new),
    );
  });

  tearDown(() async {
    if (!resourcesClosed) {
      connections.dispose();
      client.close();
      await sources.close();
      await server.close();
    }
  });

  ProviderContainer container() => ProviderContainer(
    overrides: [
      sourceRepositoryProvider.overrideWithValue(sources),
      embyConnectionProvider.overrideWithValue(connections),
      embyCachedVideosProvider.overrideWith((_) async => []),
    ],
  );

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int attempts = 400,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (condition()) {
        await tester.pump(const Duration(milliseconds: 100));
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    throw TimeoutException('Jellyfin frontend did not reach expected state');
  }

  Future<void> closeHarness(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    connections.dispose();
    client.close();
    await tester.runAsync(() async {
      await sources.close();
      await server.close();
    });
    resourcesClosed = true;
  }

  testWidgets(
    'source wizard connects Jellyfin with its own brand and opens reauthentication',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1088, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final scope = container();
      addTearDown(scope.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: const MaterialApp(home: Scaffold(body: SourcesPage())),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byKey(const ValueKey('add-source')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('add-source')));
      await tester.pumpAndSettle();

      final jellyfin = find.byKey(const ValueKey('source-kind-jellyfin'));
      expect(jellyfin, findsOneWidget);
      expect(
        find.descendant(
          of: jellyfin,
          matching: find.byType(MediaServerBrandMark),
        ),
        findsOneWidget,
      );
      await tester.tap(jellyfin);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('登录后同步到独立的 Jellyfin 目录。'), findsOneWidget);
      expect(find.text('登录后同步到独立的 Emby 目录。'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('jellyfin-server')),
        server.address,
      );
      await tester.enterText(
        find.byKey(const ValueKey('jellyfin-username')),
        'tester',
      );
      await tester.enterText(
        find.byKey(const ValueKey('jellyfin-password')),
        'pw',
      );
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('参与策略'), findsOneWidget);
      await tester.tap(find.text('登录并同步'));
      await pumpUntil(
        tester,
        () => find.text('Jellyfin 媒体库').evaluate().isNotEmpty,
      );

      expect(find.text('Jellyfin'), findsWidgets);
      expect(find.byKey(const ValueKey('jellyfin-brand-mark')), findsWidgets);
      expect(find.text('Emby 媒体库'), findsNothing);
      final saved = (await tester.runAsync(() => sources.sources()))!.single;
      expect(saved.kind, MediaSourceKind.jellyfin);
      expect(saved.name, 'Jellyfin 媒体库');
      expect(saved.location, startsWith('jellyfin://'));

      final reauthenticate = find.widgetWithText(TextButton, '重新认证');
      await pumpUntil(
        tester,
        () =>
            reauthenticate.evaluate().isNotEmpty &&
            tester.widget<TextButton>(reauthenticate).onPressed != null,
      );
      await tester.tap(reauthenticate);
      await tester.pumpAndSettle();
      expect(find.text('Jellyfin 重新认证'), findsOneWidget);
      expect(find.text('Emby 重新认证'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await pumpUntil(
        tester,
        () =>
            scope
                .read(sourceReachabilityProvider)
                .asData
                ?.value
                .containsKey(saved.id) ??
            false,
      );
      expect(tester.takeException(), isNull);
      await closeHarness(tester);
    },
  );

  testWidgets('sidebar, cached library and detail retain Jellyfin identity', (
    tester,
  ) async {
    final source = (await tester.runAsync(() async {
      final connected = await connections.connect(
        server.address,
        'tester',
        'pw',
        kind: MediaSourceKind.jellyfin,
      );
      await EmbySyncRepository(
        sources: sources,
        connections: connections,
      ).synchronize(connected.id);
      return connected;
    }))!;
    final scope = container();
    addTearDown(scope.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1088, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: EmbySidebar()),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await pumpUntil(
      tester,
      () => find
          .byKey(ValueKey('jellyfin-source-logo-${source.id}'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('Jellyfin 媒体库'), findsOneWidget);
    expect(find.byKey(ValueKey('emby-source-logo-${source.id}')), findsNothing);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          home: Scaffold(
            body: SourceLibraryPage(sourceId: source.id, libraryId: 'movies'),
          ),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.textContaining('浏览、筛选和管理当前内容').evaluate().isNotEmpty,
    );
    await pumpUntil(
      tester,
      () => find.text('Jellyfin 影片').evaluate().isNotEmpty,
    );
    expect(find.byType(EmbyVideoLibraryPage), findsOneWidget);
    expect(find.text('Jellyfin 影片'), findsWidgets);
    expect(find.textContaining('浏览与管理 Emby 视频内容'), findsNothing);

    const identity = (sourceId: '', localId: 'film');
    final itemIdentity = (sourceId: source.id, localId: identity.localId);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          home: Scaffold(body: LocalMediaDetailPage(identity: itemIdentity)),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.textContaining('Jellyfin 流媒体').evaluate().isNotEmpty,
    );
    expect(find.textContaining('Jellyfin 流媒体'), findsOneWidget);
    expect(find.textContaining('Emby 流媒体'), findsNothing);
    expect(tester.takeException(), isNull);
    await closeHarness(tester);
  });
}
