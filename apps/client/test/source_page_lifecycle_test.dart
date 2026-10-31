import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_item.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_library_selection_bar.dart';
import 'package:reelnest/features/sources/presentation/emby_video_library_page.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/features/sources/presentation/source_library_page.dart';
import 'package:reelnest/storage/library_database.dart';

class _DelayedSources extends SourceRepository {
  _DelayedSources()
    : super(database: LibraryDatabase(NativeDatabase.memory()), adapters: {});

  Completer<void>? pending;
  Object? failure;

  @override
  Future<List<MediaSource>> sources({bool includeCounts = true}) async {
    if (includeCounts) {
      await pending?.future;
      if (failure case final error?) throw error;
    }
    return super.sources(includeCounts: includeCounts);
  }
}

// Exercise the real browse cursor, SQLite page writes and source notifications;
// only the HTTP boundary is replaced, with deterministic 60-item pages.
class _Pages extends EmbyConnectionRepository {
  _Pages(SourceRepository sources, EmbyClient client)
    : super(
        sources: sources,
        client: Future.value(client),
        stores: (_) => throw StateError('No real login in this regression'),
      );

  final starts = <int>[];
  @override
  Future<EmbyItemPage> browsePage(
    String id, {
    String? parentId,
    String? personKey,
    bool episodesOnly = false,
    required int start,
    int limit = 60,
    ScanCancellation? cancellation,
  }) async {
    cancellation?.check();
    starts.add(start);
    return EmbyItemPage.fromJson({
      'TotalRecordCount': 180,
      'Items': [
        for (var n = start; n < (start + limit).clamp(0, 180); n++)
          {
            'Id': 'film-$n',
            'Name': 'Film ${n.toString().padLeft(3, '0')}',
            'Type': 'Movie',
          },
      ],
    });
  }
}

void main() {
  late _DelayedSources sources;
  late MediaSource source;
  late EmbyClient client;
  late _Pages pages;
  late ProviderContainer container;

  setUp(() async {
    sources = _DelayedSources();
    source = await sources.add(
      sourceId: 's',
      kind: MediaSourceKind.emby,
      name: '测试媒体库',
      location: 'emby://fixture/s',
    );
    await EmbyLibraryRepository(sources)
        .replaceViews(source.id, [const EmbyLibrary(id: 'movies', name: '电影')]);
    client = EmbyClient(deviceId: 'lifecycle-fixture');
    pages = _Pages(sources, client);
    container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        embyConnectionProvider.overrideWithValue(pages),
        embyCachedVideosProvider.overrideWith((_) async => []),
        embyDetailProvider.overrideWith((_, _) => const Stream.empty()),
      ],
    );
  });
  tearDown(() async {
    sources.pending?.complete();
    container.dispose();
    pages.dispose();
    client.close();
    await sources.close();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1088, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void assertReload() {
    final state = container.read(sourcesProvider);
    expect(state.isLoading, isTrue);
    expect(state.hasValue, isTrue);
    expect(state.asData, isNull);
  }

  void release() {
    sources.pending!.complete();
    sources.pending = null;
  }

  testWidgets(
    'source refresh preserves Emby element, scroll, selection and real paging cursor',
    (tester) async {
      await pump(
        tester,
        const SourceLibraryPage(sourceId: 's', libraryId: 'movies'),
      );
      expect(pages.starts, [0]);
      final element = tester.element(find.byType(EmbyVideoLibraryPage));
      final state = tester.state(find.byType(EmbyVideoLibraryPage));
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      final first = tester.widget<LocalMediaCard>(
        find.byType(LocalMediaCard).first,
      );
      first.onOpen();
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(700);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EmbyLibrarySelectionBar>(
              find.byType(EmbyLibrarySelectionBar),
            )
            .count,
        1,
      );

      sources.pending = Completer<void>();
      await sources.setRemoteFavorite(first.item.identity, true);
      await tester.pumpAndSettle();
      assertReload();
      expect(tester.element(find.byType(EmbyVideoLibraryPage)), same(element));
      expect(tester.state(find.byType(EmbyVideoLibraryPage)), same(state));
      expect(scroll.offset, 700);
      expect(
        tester
            .widget<EmbyLibrarySelectionBar>(
              find.byType(EmbyLibrarySelectionBar),
            )
            .count,
        1,
      );

      // Paging also emits a source refresh. It must advance the existing cursor,
      // rather than recreating the page and fetching StartIndex=0 again.
      scroll.jumpTo(scroll.position.maxScrollExtent - 500);
      await tester.pumpAndSettle();
      assertReload();
      expect(pages.starts, [0, 60]);
      expect(tester.state(find.byType(EmbyVideoLibraryPage)), same(state));
      final offset = scroll.offset;
      release();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(EmbyVideoLibraryPage)), same(state));
      expect(scroll.offset, offset);
      expect(
        tester
            .widget<EmbyLibrarySelectionBar>(
              find.byType(EmbyLibrarySelectionBar),
            )
            .count,
        1,
      );
      scroll.jumpTo(scroll.position.maxScrollExtent - 500);
      await tester.pumpAndSettle();
      expect(pages.starts, [0, 60, 120]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'detail retains content during source reload and only reports confirmed removal',
    (tester) async {
      await sources.database.customStatement(
        "UPDATE sources SET last_scan=1 WHERE id='s'",
      );
      await sources.database.customStatement(
        "INSERT INTO media(source_id,local_id,title,type,bytes,modified,identity_kind) VALUES ('s','film','详情影片','movie',0,1,'movie')",
      );
      await pump(
        tester,
        const LocalMediaDetailPage(identity: (sourceId: 's', localId: 'film')),
      );
      expect(find.text('详情影片'), findsNWidgets(2));
      final element = tester.element(find.byType(LocalMediaDetailPage));
      sources.pending = Completer<void>();
      sources.traceChanged();
      await tester.pumpAndSettle();
      assertReload();
      expect(find.text('此媒体源已移除。'), findsNothing);
      expect(find.text('详情影片'), findsNWidgets(2));
      expect(tester.element(find.byType(LocalMediaDetailPage)), same(element));
      release();
      await tester.pumpAndSettle();
      expect(find.text('详情影片'), findsNWidgets(2));

      sources.pending = Completer<void>();
      await sources.remove('s');
      await tester.pumpAndSettle();
      expect(find.text('此媒体源已移除。'), findsNothing);
      release();
      await tester.pumpAndSettle();
      expect(find.text('此媒体源已移除。'), findsOneWidget);
      expect(find.text('详情影片'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'cold loading and refresh errors are distinct from a removed source',
    (tester) async {
      sources.pending = Completer<void>();
      await pump(
        tester,
        const SourceLibraryPage(sourceId: 's', libraryId: 'movies'),
        settle: false,
      );
      expect(find.byType(EmbyVideoLibraryPage), findsNothing);
      expect(
        find.byKey(const ValueKey('source-library-loading')),
        findsOneWidget,
      );
      expect(find.text('此媒体源已移除。'), findsNothing);
      release();
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(EmbyVideoLibraryPage));
      sources.failure = const SourceFailure('读取来源失败');
      sources.traceChanged();
      await tester.pumpAndSettle();
      expect(container.read(sourcesProvider).hasError, isTrue);
      expect(tester.state(find.byType(EmbyVideoLibraryPage)), same(state));
      expect(find.text('此媒体源已移除。'), findsNothing);
      sources.failure = null;
      await sources.remove('s');
      await tester.pumpAndSettle();
      expect(find.byType(EmbyVideoLibraryPage), findsNothing);
      expect(find.text('此媒体源已移除。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
