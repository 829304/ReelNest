import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/library_health.dart';
import 'package:reelnest/features/health/application/health_providers.dart';
import 'package:reelnest/features/health/presentation/library_health_page.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/application/url_video_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/data/url_video_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_sheets.dart';
import 'package:reelnest/features/sources/presentation/source_wizard_steps.dart';
import 'package:reelnest/features/sources/presentation/url_source_sheet.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/ui/theme/app_theme.dart';

void main() {
  testWidgets('source wizard steps share original geometry and semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    Future<void> pump(Brightness brightness, int current) => tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 572,
              child: SourceWizardSteps(
                key: const ValueKey('steps-under-test'),
                current: current,
              ),
            ),
          ),
        ),
      ),
    );

    await pump(Brightness.light, 0);
    final steps = find.byKey(const ValueKey('steps-under-test'));
    expect(tester.getSize(steps), const Size(572, 40));
    expect(tester.getSemantics(steps).label, contains('第 1 步，共 3 步'));
    await pump(Brightness.dark, 2);
    expect(tester.getSize(steps), const Size(572, 40));
    expect(tester.getSemantics(steps).label, contains('第 3 步，共 3 步'));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('source selection exposes the persistent URL source', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: SourceKindSheet()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-kind-url')), findsOneWidget);
    expect(find.text('URL 媒体源'), findsOneWidget);
    expect(find.text('持久保存网络视频地址'), findsOneWidget);
    final local = find.byKey(const ValueKey('source-kind-localFolder'));
    final url = find.byKey(const ValueKey('source-kind-url'));
    expect(tester.getSize(local), const Size(264, 88));
    expect(tester.getSize(url), const Size(264, 88));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(url));
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.getSize(url), const Size(264, 88));
    expect(tester.takeException(), isNull);
  });

  testWidgets('single URL add preserves the optional title and closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: const {},
    );
    final urls = UrlVideoRepository(sources);
    addTearDown(sources.close);
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        urlVideoRepositoryProvider.overrideWithValue(urls),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const _SheetHost(add: true),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('url-source-url')),
      'https://media.example/series/trailer.mp4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('url-source-title')),
      '预告片',
    );
    await tester.tap(find.byKey(const ValueKey('url-source-submit')));
    await tester.pumpAndSettle();
    final saved = await urls.list();
    expect(saved, hasLength(1));
    expect(saved.single.title, '预告片');
    expect(saved.single.url, 'https://media.example/series/trailer.mp4');
    expect(find.text('添加 URL 媒体源'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('management batch adds, edits and removes the URL container', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: const {},
    );
    final urls = UrlVideoRepository(sources);
    addTearDown(sources.close);
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        urlVideoRepositoryProvider.overrideWithValue(urls),
        urlVideoHealthProvider.overrideWith(_NoopHealth.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const _SheetHost(add: false),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('url-source-manager-url')),
      'https://media.example/one.mp4\n'
      'invalid\n'
      'https://media.example/two.mp4',
    );
    await tester.pump();
    expect(find.text('批量添加 2 个'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('url-source-manager-add')));
    await tester.pumpAndSettle();
    expect(find.text('已添加 2 个地址，跳过 1 个无效或重复地址。'), findsOneWidget);
    final added = await urls.list();
    expect(added, hasLength(2));

    final first = added.first;
    final firstRow = find.byKey(
      ValueKey('url-source-item-${first.identity.localId}'),
    );
    final rowSize = tester.getSize(firstRow);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(firstRow));
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.getSize(firstRow), rowSize);
    expect(find.byTooltip('编辑'), findsWidgets);

    await tester.tap(
      find.byKey(ValueKey('url-source-edit-button-${first.identity.localId}')),
    );
    await tester.pump();
    final fields = find.descendant(
      of: find.byKey(ValueKey('url-source-edit-${first.identity.localId}')),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), '修改后的名称');
    await tester.tap(
      find.byKey(ValueKey('url-source-save-${first.identity.localId}')),
    );
    await tester.pumpAndSettle();
    expect((await urls.list()).any((item) => item.title == '修改后的名称'), isTrue);

    for (final item in await urls.list()) {
      await tester.tap(
        find.byKey(ValueKey('url-source-delete-${item.identity.localId}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('删除 URL 地址？'), findsOneWidget);
      expect(find.text(item.title), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
    }
    expect(await urls.list(), isEmpty);
    expect(await sources.sources(), isEmpty);
    expect(find.text('还没有 URL 视频'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('health details show each failed URL with recovery actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1088, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: const {},
    );
    final urls = UrlVideoRepository(sources);
    addTearDown(sources.close);
    await urls.add('https://media.example/broken.mp4', title: '失效测试视频');
    final video = (await urls.list()).single;
    final source = (await sources.sources()).single;
    final item = await sources.media(video.identity);
    final snapshot = LibraryHealthSnapshot(
      inventory: (sources: [source], items: [item]),
      missing: const {},
      safeMissing: const {},
      offline: const {},
      metadataGaps: const {},
      unhealthyURLs: {video.identity: '无法访问'},
      evaluationComplete: true,
    );
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        urlVideoRepositoryProvider.overrideWithValue(urls),
        urlVideoHealthProvider.overrideWith(_NoopHealth.new),
        libraryHealthProvider.overrideWith((ref) async => snapshot),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: LibraryHealthPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final failedLinks = find.text('失效链接');
    final pageScroll = find
        .descendant(
          of: find.byType(LibraryHealthPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(failedLinks, 180, scrollable: pageScroll);
    await tester.pumpAndSettle();
    expect(failedLinks, findsOneWidget);
    expect(find.text('失效测试视频'), findsOneWidget);
    expect(
      find.textContaining('https://media.example/broken.mp4'),
      findsOneWidget,
    );
    expect(find.byTooltip('复制链接'), findsOneWidget);
    expect(find.byTooltip('移除链接'), findsOneWidget);
    expect(find.byTooltip('忽略此失效链接，可在设置中恢复'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '管理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.add});
  final bool add;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => add
              ? const UrlSourceAddSheet()
              : const UrlSourceManagementSheet(),
        ),
        child: const Text('打开'),
      ),
    ),
  );
}

class _NoopHealth extends UrlVideoHealthController {
  @override
  Map<({String sourceId, String localId}), UrlVideoHealth> build() => const {};

  @override
  Future<void> refresh() async {}
}
