import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/data/artwork_decode_queue.dart';
import 'package:reelnest/features/sources/data/artwork_image_pipeline.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';

final _date = DateTime.utc(2026, 10, 10);
final _source = MediaSource(
  id: 's',
  kind: MediaSourceKind.emby,
  name: 'Test',
  location: 'http://fixture.invalid',
  createdAt: _date,
  updatedAt: _date,
);

VideoLibraryEntry _entry(
  String id, {
  String source = 's',
  String? parent,
  bool favorite = false,
  bool watched = false,
  bool watchlist = false,
}) {
  final identity = (sourceId: source, localId: id);
  return VideoLibraryEntry(
    item: IndexedMedia(
      identity: identity,
      title: id,
      type: parent == null ? 'movie' : 'episode',
      bytes: 0,
      modified: _date,
      parentId: parent,
      posterPath: id,
      remote: RemoteMediaMetadata(
        externalId: id,
        libraryId: 'movies',
        favorite: favorite,
      ),
    ),
    record: PlaybackRecord(identity: identity, watched: watched),
    createdAt: _date,
    watchlist: watchlist,
  );
}

void main() {
  test(
    'snapshot lookups preserve source, parent and refreshed playback state',
    () {
      final original = [
        _entry('show', watchlist: true),
        _entry('episode', parent: 'show', watched: true),
        _entry('episode', source: 'other', parent: 'show'),
        _entry('favorite', favorite: true),
      ];
      final snapshot = EmbyVideoSnapshot(
        source: _source,
        libraries: [],
        entries: original,
      );
      original.clear();
      const show = (sourceId: 's', localId: 'show');
      expect(snapshot.childrenOf(show).single.record.watched, isTrue);
      expect(
        snapshot
            .childrenOf((sourceId: 'other', localId: 'show'))
            .single
            .item
            .identity
            .sourceId,
        'other',
      );
      expect(
        snapshot.entryFor((sourceId: 's', localId: 'episode'))!.record.watched,
        isTrue,
      );
      expect(
        snapshot.entryFor((sourceId: 'missing', localId: 'episode')),
        isNull,
      );
      expect(snapshot.childrenOf((sourceId: 's', localId: 'missing')), isEmpty);
      const destination = (
        sourceId: 's',
        section: EmbyVideoSection.videos,
        libraryId: 'movies',
      );
      expect(snapshot.scope(destination).map((e) => e.item.identity.localId), [
        'show',
        'favorite',
      ]);
      expect(snapshot.scope(destination), same(snapshot.scope(destination)));
      expect(
        snapshot
            .scope((
              sourceId: 's',
              section: EmbyVideoSection.watchlist,
              libraryId: null,
            ))
            .single
            .item
            .identity,
        show,
      );
      expect(
        snapshot
            .scope((
              sourceId: 's',
              section: EmbyVideoSection.favorites,
              libraryId: null,
            ))
            .single
            .item
            .title,
        'favorite',
      );
      expect(() => snapshot.childrenOf(show).clear(), throwsUnsupportedError);
      final refreshed = EmbyVideoSnapshot(
        source: _source,
        libraries: [],
        entries: [_entry('episode', parent: 'show', watched: false)],
      );
      expect(refreshed.childrenOf(show).single.record.watched, isFalse);
      expect(snapshot.childrenOf(show).single.record.watched, isTrue);
    },
  );

  test(
    'large library card lookup reaches the tail without per-card enumeration',
    () {
      final snapshot = EmbyVideoSnapshot(
        source: _source,
        libraries: [],
        entries: List.generate(
          92130,
          (i) => _entry('$i', parent: i.isOdd ? '${i - 1}' : null),
        ),
      );
      final timer = Stopwatch()..start();
      for (var i = 91800; i < 92130; i += 2) {
        final identity = (sourceId: 's', localId: '$i');
        expect(snapshot.entryFor(identity)!.item.title, '$i');
        expect(snapshot.childrenOf(identity).single.item.title, '${i + 1}');
      }
      timer.stop();
      // Diagnostic only: test correctness, never impose a machine-dependent FPS
      // or latency threshold on this synthetic Dart workload.
      debugPrint(
        '92130-entry indexed tail lookup: ${timer.elapsedMicroseconds} us',
      );
    },
  );

  test(
    'poster sizes follow physical display pixels and share nearby buckets',
    () {
      expect(posterDecodeSize(150, 1), (width: 192, height: 288));
      expect(posterDecodeSize(150, 2), (width: 320, height: 480));
      expect(posterDecodeSize(151, 2), posterDecodeSize(150, 2));
      expect(posterDecodeSize(3000, 2), (width: 2048, height: 3072));
    },
  );

  testWidgets(
    'card to larger detail keeps cached poster until sized image is ready',
    (tester) async {
      final queue = ArtworkDecodeQueue();
      final pipeline = _TransitionPipeline(queue);
      final navigator = GlobalKey<NavigatorState>();
      final item = _entry('poster').item;
      addTearDown(() {
        pipeline.dispose();
        queue.dispose();
      });
      Widget poster(double width) => Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: width * 1.5,
            child: LocalMediaArtwork(source: _source, item: item),
          ),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [embyImagePipelineProvider.overrideWithValue(pipeline)],
          child: MaterialApp(navigatorKey: navigator, home: poster(100)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(find.byType(LocalPosterPlaceholder), findsNothing);
      pipeline.hold = true;
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => poster(300)),
      );
      await tester.pumpAndSettle();
      expect(pipeline.waiting, isTrue);
      expect(find.byType(LocalPosterPlaceholder), findsNothing);
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((i) => i.image != null),
        isTrue,
      );
      pipeline.ready.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      expect(find.byType(LocalPosterPlaceholder), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'visible poster matches warmup size and hover retains its artwork subtree',
    (tester) async {
      final queue = ArtworkDecodeQueue();
      final pipeline = _Pipeline(queue);
      addTearDown(pipeline.dispose);
      addTearDown(queue.dispose);
      final item = _entry('poster').item;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [embyImagePipelineProvider.overrideWithValue(pipeline)],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 150,
                  height: 225,
                  child: LocalMediaCard(
                    source: _source,
                    item: item,
                    onOpen: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      final target = posterDecodeSize(150, tester.view.devicePixelRatio);
      expect(pipeline.keys.last.width, target.width);
      expect(pipeline.keys.last.height, target.height);
      final before = tester.widget<LocalMediaArtwork>(
        find.byType(LocalMediaArtwork),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(LocalMediaCard)));
      await tester.pump();
      expect(
        tester.widget<LocalMediaArtwork>(find.byType(LocalMediaArtwork)),
        same(before),
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('poster hover is cleared while its scroll view is moving', (
    tester,
  ) async {
    final queue = ArtworkDecodeQueue();
    final pipeline = _Pipeline(queue);
    final item = _entry('poster').item;
    var suppressHover = false;
    late StateSetter update;
    addTearDown(pipeline.dispose);
    addTearDown(queue.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [embyImagePipelineProvider.overrideWithValue(pipeline)],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Center(
                  child: SizedBox(
                    width: 150,
                    height: 225,
                    child: LocalMediaCard(
                      source: _source,
                      item: item,
                      suppressHover: suppressHover,
                      onOpen: () {},
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    final card = find.byType(LocalMediaCard);
    final scale = find.descendant(
      of: card,
      matching: find.byType(AnimatedScale),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(card));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(scale).scale, 1.018);

    update(() => suppressHover = true);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(scale).scale, 1);

    update(() => suppressHover = false);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(scale).scale, 1);

    await mouse.moveTo(Offset.zero);
    await mouse.moveTo(tester.getCenter(card));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(scale).scale, 1.018);
    await mouse.removePointer();
  });
}

class _Pipeline extends ArtworkImagePipeline {
  _Pipeline(ArtworkDecodeQueue queue) : super(decodes: queue);
  final keys = <ArtworkImageKey>[];
  @override
  ImageProvider<ArtworkImageKey> image(
    ArtworkImageKey key,
    Future<Uint8List> Function() bytes,
  ) {
    keys.add(key);
    return super.image(
      key,
      () async => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
  }
}

class _TransitionPipeline extends ArtworkImagePipeline {
  _TransitionPipeline(ArtworkDecodeQueue queue) : super(decodes: queue);
  bool hold = false, waiting = false;
  final ready = Completer<void>();
  @override
  ImageProvider<ArtworkImageKey> image(
    ArtworkImageKey key,
    Future<Uint8List> Function() bytes,
  ) => super.image(key, () async {
    if (hold) {
      waiting = true;
      await ready.future;
    }
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
  });
}
