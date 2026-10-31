import 'dart:async';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';
import 'package:reelnest/features/sources/presentation/source_library_page.dart';
import 'package:reelnest/storage/library_database.dart';

class _PagedLocalRepository extends SourceRepository {
  _PagedLocalRepository({
    this.total = 180,
    this.kind = MediaSourceKind.localFolder,
    this.name = '本地媒体库',
  }) : super(
         database: LibraryDatabase(NativeDatabase.memory()),
         adapters: const {},
       );

  final int total;
  final MediaSourceKind kind;
  final String name;
  final calls = <int>[];
  final failures = <int>{};
  Completer<IndexedMediaPage>? pendingFirstPage;

  late final MediaSource fixtureSource = MediaSource(
    id: 'local',
    kind: kind,
    name: name,
    location: kind == MediaSourceKind.url
        ? 'url://local'
        : r'C:\fixture\library',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Future<List<MediaSource>> sources({bool includeCounts = true}) async => [
    fixtureSource,
  ];

  @override
  Future<IndexedMediaPage> browse(
    String id, {
    int offset = 0,
    int limit = 60,
    bool topLevelOnly = false,
  }) async {
    calls.add(offset);
    final pending = pendingFirstPage;
    if (offset == 0 && pending != null) {
      return pending.future;
    }
    if (failures.contains(offset)) {
      throw const SourceFailure('分页读取失败');
    }
    final end = math.min(offset + limit, total);
    return IndexedMediaPage(
      total: total,
      items: [
        for (var index = offset; index < end; index++)
          IndexedMedia(
            identity: (sourceId: id, localId: 'video-$index.mp4'),
            title: '媒体标题 ${index.toString().padLeft(5, '0')}',
            type: 'movie',
            bytes: 1024,
            modified: DateTime(2026),
          ),
      ],
    );
  }
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    _PagedLocalRepository repository, {
    Size physicalSize = const Size(1200, 900),
    double devicePixelRatio = 1,
    bool settle = true,
    bool closeRepository = true,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (closeRepository) addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sourceRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(body: SourceLibraryPage(sourceId: 'local')),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('loading and error bodies keep the same stable height', (
    tester,
  ) async {
    final repository = _PagedLocalRepository();
    final pending = Completer<IndexedMediaPage>();
    repository.pendingFirstPage = pending;
    await pumpPage(tester, repository, settle: false);

    final loading = find.byKey(const ValueKey('source-library-loading'));
    expect(loading, findsOneWidget);
    final loadingHeight = tester.getSize(loading).height;
    expect(loadingHeight, greaterThanOrEqualTo(420));

    pending.completeError(const SourceFailure('分页读取失败'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final error = find.byKey(const ValueKey('source-library-error'));
    expect(error, findsOneWidget);
    expect(tester.getSize(error).height, loadingHeight);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh failure retains loaded posters and scroll position', (
    tester,
  ) async {
    final repository = _PagedLocalRepository(total: 600);
    await pumpPage(tester, repository);
    expect(find.byType(LocalMediaCard), findsWidgets);
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    scroll.jumpTo(420);
    await tester.pump();
    final before = scroll.offset;

    repository.failures.add(0);
    repository.traceChanged();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(LocalMediaCard), findsWidgets);
    expect(find.byKey(const ValueKey('source-library-error')), findsNothing);
    expect(scroll.offset, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold pagination failure keeps earlier cards and one retry', (
    tester,
  ) async {
    final repository = _PagedLocalRepository(total: 120)..failures.add(60);
    await pumpPage(tester, repository);
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    // The second 60-card page starts around the middle of this 120-item grid.
    scroll.jumpTo(scroll.position.maxScrollExtent / 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('source-page-error-60')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'source-page-loading-60-',
            ),
      ),
      findsNothing,
    );
    expect(repository.calls, containsAllInOrder([0, 60]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long title, large library, resize and high DPI remain stable', (
    tester,
  ) async {
    final repository = _PagedLocalRepository(
      total: 10000,
      name: '这是一个用于验证长标题截断与高 DPI 布局稳定性的本地媒体资料库名称',
    );
    await pumpPage(
      tester,
      repository,
      physicalSize: const Size(2400, 1800),
      devicePixelRatio: 2,
    );

    final wideGrid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
      (wideGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      6,
    );
    expect(find.textContaining('10000 项'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(960, 1050);
    tester.view.devicePixelRatio = 1.5;
    await tester.pumpAndSettle();
    final compactGrid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
      (compactGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('URL and file sources use the same poster grid geometry', (
    tester,
  ) async {
    final fileRepository = _PagedLocalRepository(total: 4);
    await pumpPage(tester, fileRepository, closeRepository: false);
    final fileGrid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final fileDelegate =
        fileGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(fileDelegate.crossAxisSpacing, 20);
    expect(fileDelegate.mainAxisSpacing, 30);
    expect(fileDelegate.childAspectRatio, 2 / 3);

    await tester.pumpWidget(const SizedBox());
    await fileRepository.close();
    final urlRepository = _PagedLocalRepository(
      total: 4,
      kind: MediaSourceKind.url,
      name: 'URL 媒体源',
    );
    await pumpPage(tester, urlRepository);
    final urlGrid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final urlDelegate =
        urlGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(urlDelegate.crossAxisSpacing, fileDelegate.crossAxisSpacing);
    expect(urlDelegate.mainAxisSpacing, fileDelegate.mainAxisSpacing);
    expect(urlDelegate.childAspectRatio, fileDelegate.childAspectRatio);
    expect(tester.takeException(), isNull);
  });
}
