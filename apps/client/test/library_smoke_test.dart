import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/reelnest_app.dart';
import 'package:reelnest/app/router.dart';
import 'package:reelnest/app/service_providers.dart';
import 'package:reelnest/features/servers/data/server_repository.dart';

import 'support/smoke_fixtures.dart';

void main() {
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<MemoryCredentialStore> login(
    WidgetTester tester,
    SmokeMlinkClient client,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryCredentialStore();
    final repository = ServerRepository(
      client: client,
      store: store,
      platform: 'test',
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverRepositoryProvider.overrideWithValue(repository),
          routerProvider.overrideWith((ref) {
            final router = createRouter(
              enableLegacyMlink: true,
              initialLocation: '/servers',
            );
            ref.onDispose(router.dispose);
            return router;
          }),
        ],
        child: const ReelNestApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'https://smoke.invalid',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'smoke-user');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'synthetic-password',
    );
    await tap(tester, find.text('登录并同步'));
    expect(find.text('冒烟测试服务器'), findsOneWidget);
    expect(store.value, isNotNull);
    expect(store.value, isNot(contains('synthetic-password')));
    await tap(tester, find.text('查看媒体库'));
    await tap(tester, find.text('电视剧'));
    return store;
  }

  testWidgets('login, pagination retry, seasons, episode and logout', (
    tester,
  ) async {
    final client = SmokeMlinkClient()..failNextPage = true;
    final store = await login(tester, client);
    await tap(tester, find.text('加载更多'));
    expect(find.text('模拟追加失败'), findsOneWidget);
    expect(find.text('测试系列'), findsOneWidget);
    await tap(tester, find.text('重试'));
    expect(client.offsets, [0, 1, 1]);
    expect(find.text('另一个系列'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey(smokeSeriesId)));
    expect(client.summaryCalls, 1);
    expect(find.text('2 集 · 3 个季分组'), findsOneWidget);
    expect(find.text('首集'), findsOneWidget);
    await tap(tester, find.byType(DropdownButton<String>));
    await tap(tester, find.text('未分季 · 0 集').last);
    expect(find.text('这一季暂时没有可访问的剧集。'), findsOneWidget);
    await tap(tester, find.byType(DropdownButton<String>));
    await tap(tester, find.text('特别篇 · 1 集').last);
    await tap(tester, find.text('特别篇单集'));
    expect(client.selectedSeasons, containsAll(['1', 'unspecified', '0']));
    expect(find.textContaining('当前单集'), findsOneWidget);
    final current = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '特别篇单集'),
    );
    expect(current.selected, isTrue);
    expect(current.onTap, isNull);

    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 1000);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();
    await tap(tester, find.text('返回'));
    await tap(tester, find.text('返回'));
    expect(find.text('另一个系列'), findsOneWidget);
    await tap(tester, find.text('媒体库'));
    await tap(tester, find.text('管理服务器'));
    await tap(tester, find.text('退出此设备'));
    expect(store.value, isNull);
    expect(find.text('还没有服务器'), findsOneWidget);
  });

  testWidgets('old server fallback re-discovers capabilities after upgrade', (
    tester,
  ) async {
    final client = SmokeMlinkClient()..supportsSeries = false;
    await login(tester, client);
    await tap(tester, find.byKey(const ValueKey(smokeSeriesId)));
    expect(find.textContaining('当前服务器尚未支持系列季列表'), findsOneWidget);
    expect(client.basicSeriesCalls, 1);
    expect(client.summaryCalls, 0);
    client.supportsSeries = true;
    await tap(tester, find.text('刷新详情'));
    expect(client.summaryCalls, 1);
    expect(find.text('首集'), findsOneWidget);
    expect(find.textContaining('当前服务器尚未支持系列季列表'), findsNothing);
  });
}
