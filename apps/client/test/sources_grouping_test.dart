import 'dart:async';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_scan.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/sources_page.dart';
import 'package:reelnest/sources/source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/ui/theme/app_theme.dart';

void main() {
  testWidgets('empty and loading states preserve the original page geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(836, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: const {},
    );
    addTearDown(repository.close);

    Future<void> pumpWith(Future<List<MediaSource>> Function() load) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              sourceRepositoryProvider.overrideWithValue(repository),
              sourcesProvider.overrideWith((ref) => load()),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: SourcesPage()),
            ),
          ),
        );

    await pumpWith(() async => const []);
    await tester.pumpAndSettle();
    final empty = find.byKey(const ValueKey('sources-empty-state'));
    expect(empty, findsOneWidget);
    expect(tester.getSize(empty).height, 320);
    expect(
      tester.getSize(find.byKey(const ValueKey('sources-empty-icon-glow'))),
      const Size.square(104),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('sources-empty-icon-tile'))),
      const Size.square(76),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpWith(() => Completer<List<MediaSource>>().future);
    await tester.pump();
    final loading = find.byKey(const ValueKey('sources-loading-state'));
    expect(loading, findsOneWidget);
    expect(tester.getSize(loading).height, greaterThanOrEqualTo(320));
    expect(
      tester.getSize(find.byKey(const ValueKey('sources-loading-row-0'))),
      const Size(736, 72),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'connected/offline groups, scan-all and focus refresh use actual reachability',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(
        836,
        720,
      ); // 1088 minus desktop sidebar.
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = _Files();
      final repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: files},
      );
      addTearDown(repository.close);
      for (final name in ['Online', 'Offline']) {
        await repository.add(
          kind: MediaSourceKind.localFolder,
          name: name,
          location: '/$name',
        );
      }
      final container = ProviderContainer(
        overrides: [sourceRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: SourcesPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已连接媒体源'), findsOneWidget);
      expect(find.text('已断开媒体源'), findsOneWidget);
      expect(find.text('1个'), findsNWidgets(2));
      expect(find.text('可访问'), findsOneWidget);
      expect(find.text('不可访问'), findsOneWidget);
      final persistedSources = await repository.sources();
      final firstCard = find.byKey(
        ValueKey('source-${persistedSources.first.id}'),
      );
      expect(firstCard, findsOneWidget);
      expect(
        find.descendant(of: firstCard, matching: find.byType(Card)),
        findsNothing,
      );
      final firstSource = persistedSources.first;
      expect(
        tester.getSize(find.byKey(ValueKey('source-avatar-${firstSource.id}'))),
        const Size.square(52),
      );
      expect(
        find.byKey(ValueKey('source-actions-${firstSource.id}')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstCard, matching: find.text('浏览媒体')),
        findsNothing,
      );
      expect(
        find.descendant(of: firstCard, matching: find.text('重新扫描')),
        findsNothing,
      );
      // The original has 16-point vertical insets around a 52-point avatar.
      expect(tester.getSize(firstCard).height, 84);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(firstCard));
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getSize(firstCard).height, 84);
      expect(tester.takeException(), isNull);
      final localSource = persistedSources.first;
      await tester.tap(find.byKey(ValueKey('source-more-${localSource.id}')));
      await tester.pumpAndSettle();
      final relocate = find.byKey(
        ValueKey('source-relocate-${localSource.id}'),
      );
      expect(relocate, findsOneWidget);
      expect(tester.widget<MenuItemButton>(relocate).onPressed, isNotNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rowScans = [
        for (final source in persistedSources)
          tester.widget<IconButton>(
            find.descendant(
              of: find.byKey(ValueKey('source-scan-${source.id}')),
              matching: find.byType(IconButton),
            ),
          ),
      ];
      expect(
        rowScans.where((button) => button.onPressed != null),
        hasLength(1),
      );
      await tester.tap(find.byKey(const ValueKey('scan-all')));
      await tester.pumpAndSettle();
      expect(files.scanned, ['/Online']);
      expect(
        container.read(sourceScansProvider).values.every((scan) => !scan.busy),
        isTrue,
      );

      files.connected.add('/Offline');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('已断开媒体源'), findsNothing);
      expect(find.text('2个'), findsOneWidget);
      tester.view.physicalSize = const Size(680, 382);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('add-source')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-source')));
      await tester.pumpAndSettle();
      expect(find.text('选择要接入 ReelNest 的来源类型。'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('选择文件夹并指定分类。'), findsOneWidget);
      await tester.tap(find.text('上一步'));
      await tester.pumpAndSettle();
      expect(find.text('选择要接入 ReelNest 的来源类型。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

class _Files implements SourceAdapter {
  final connected = {'/Online'};
  final scanned = <String>[];
  @override
  Future<bool> isReachable(String location) async =>
      connected.contains(location);
  @override
  Future<String> validateLocation(String location) async => location;
  @override
  Stream<SourceScanEvent> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    scanned.add(source.location);
    yield const ScanCatalogued(1);
    yield ScanFileProcessed(
      path: 'film.mp4',
      item: IndexedMedia(
        identity: (sourceId: source.id, localId: 'film.mp4'),
        title: 'Film',
        type: 'homeVideo',
        bytes: 52428800,
        modified: DateTime.utc(2026),
      ),
    );
  }
}
