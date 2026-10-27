import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/plex/plex_client.dart';
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

import 'support/plex_fixture.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlexFixture server;
  late EmbyClient embyClient;
  late PlexClient plexClient;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late Map<String, _Store> stores;
  var resourcesClosed = false;

  setUp(() async {
    resourcesClosed = false;
    server = PlexFixture();
    server.catalog['1'] = [plexMovie(title: 'Plex 影片')];
    await server.start();
    embyClient = EmbyClient(
      deviceId: 'plex-frontend-test',
      http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
    );
    plexClient = PlexClient(
      accountEndpoint: server.accountEndpoint,
      deviceId: 'plex-frontend-test',
      http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
    );
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    stores = {};
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(embyClient),
      plexClient: Future.value(plexClient),
      stores: (id) => stores.putIfAbsent(id, _Store.new),
    );
  });

  tearDown(() async {
    if (!resourcesClosed) {
      connections.dispose();
      embyClient.close();
      plexClient.close();
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
    throw TimeoutException('Plex frontend did not reach expected state');
  }

  Future<void> closeHarness(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    connections.dispose();
    embyClient.close();
    plexClient.close();
    await tester.runAsync(() async {
      await sources.close();
      await server.close();
    });
    resourcesClosed = true;
  }

  testWidgets(
    'source wizard connects Plex with its own brand and opens reauthentication',
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

      final plex = find.byKey(const ValueKey('source-kind-plex'));
      expect(plex, findsOneWidget);
      expect(
        find.descendant(of: plex, matching: find.byType(MediaServerBrandMark)),
        findsOneWidget,
      );
      await tester.tap(plex);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('连接后同步到独立的 Plex 目录。'), findsOneWidget);
      expect(find.text('登录后同步到独立的 Emby 目录。'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('plex-server')),
        server.address,
      );
      expect(find.byKey(const ValueKey('plex-username')), findsNothing);
      expect(find.byKey(const ValueKey('plex-password')), findsNothing);
      await tester.tap(find.text('下一步'));
      await tester.pump();
      expect(find.text('请输入 Plex Token。'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('plex-token')),
        server.token,
      );
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('参与策略'), findsOneWidget);
      await tester.tap(find.text('连接并同步'));
      await pumpUntil(
        tester,
        () => find.text('Plex 媒体库').evaluate().isNotEmpty,
      );

      expect(find.text('Plex'), findsWidgets);
      expect(find.byKey(const ValueKey('plex-brand-mark')), findsWidgets);
      expect(find.text('Emby 媒体库'), findsNothing);
      final saved = (await tester.runAsync(() => sources.sources()))!.single;
      expect(saved.kind, MediaSourceKind.plex);
      expect(saved.name, 'Plex 媒体库');
      expect(saved.location, startsWith('plex://'));

      final reauthenticate = find.widgetWithText(TextButton, '重新认证');
      await pumpUntil(
        tester,
        () =>
            reauthenticate.evaluate().isNotEmpty &&
            tester.widget<TextButton>(reauthenticate).onPressed != null,
      );
      await tester.tap(reauthenticate);
      await tester.pumpAndSettle();
      expect(find.text('Plex 重新认证'), findsOneWidget);
      expect(find.text('Emby 重新认证'), findsNothing);
      expect(find.byKey(const ValueKey('plex-token')), findsOneWidget);
      expect(find.byKey(const ValueKey('plex-server')), findsNothing);
      expect(find.byKey(const ValueKey('plex-username')), findsNothing);
      expect(find.byKey(const ValueKey('plex-password')), findsNothing);
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

  testWidgets('sidebar, cached library and detail retain Plex identity', (
    tester,
  ) async {
    final source = (await tester.runAsync(() async {
      final connected = await connections.connectPlex(
        server.address,
        server.token,
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
          .byKey(ValueKey('plex-source-logo-${source.id}'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('Plex 媒体库'), findsOneWidget);
    expect(find.byKey(ValueKey('emby-source-logo-${source.id}')), findsNothing);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          home: Scaffold(
            body: SourceLibraryPage(
              sourceId: source.id,
              libraryId: 'section:1',
            ),
          ),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.textContaining('浏览、筛选和管理当前内容').evaluate().isNotEmpty,
    );
    await pumpUntil(tester, () => find.text('Plex 影片').evaluate().isNotEmpty);
    expect(find.byType(EmbyVideoLibraryPage), findsOneWidget);
    expect(find.text('Plex 影片'), findsWidgets);
    expect(find.textContaining('浏览与管理 Emby 视频内容'), findsNothing);

    const identity = (sourceId: '', localId: '101');
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
      () => find.textContaining('Plex 流媒体').evaluate().isNotEmpty,
    );
    await pumpUntil(tester, () => find.text('Plex 演员').evaluate().isNotEmpty);
    expect(find.textContaining('Emby 流媒体'), findsNothing);
    expect(find.text('Plex 演员'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeHarness(tester);
  });
}
