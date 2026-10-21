import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';

VideoLibraryEntry entry(String title, int index) {
  final identity = (sourceId: 'fixture', localId: '$index');
  return VideoLibraryEntry(
    item: IndexedMedia(
      identity: identity,
      title: title,
      type: 'movie',
      bytes: 0,
      modified: DateTime.utc(2026),
    ),
    record: PlaybackRecord(identity: identity),
    createdAt: DateTime.utc(2026),
    searchTerms: [title],
  );
}

void main() {
  test(
    'natural title order preserves zeros, case, huge numbers and ID ties',
    () {
      final titles = [
        '第10集',
        '第2集',
        'Movie 10',
        'movie 2',
        'Movie 02',
        '',
        'Movie 99999999999999999999999999999999999',
        'Movie 100000000000000000000000000000000000',
        'MOVIE 2',
      ];
      final items = [
        for (var i = 0; i < titles.length; i++) entry(titles[i], i),
      ];
      List<String> sorted(VideoLibrarySort sort, bool reverse) =>
          filterVideoLibrary(
            items,
            VideoLibrarySettings(sort: sort, reverse: reverse),
            .9,
          ).map((e) => e.item.identity.localId).toList();
      expect(sorted(VideoLibrarySort.title, false), [
        '5',
        '3',
        '4',
        '8',
        '2',
        '6',
        '7',
        '1',
        '0',
      ]);
      expect(sorted(VideoLibrarySort.title, true), [
        '0',
        '1',
        '7',
        '6',
        '2',
        '3',
        '4',
        '8',
        '5',
      ]);
      for (final sort in VideoLibrarySort.values.where(
        (s) => s != VideoLibrarySort.title,
      )) {
        // Equal primary values retain ascending title/ID ties, even in reverse.
        expect(sorted(sort, false), sorted(VideoLibrarySort.title, false));
        expect(sorted(sort, true), sorted(VideoLibrarySort.title, false));
      }
      expect(items.map((e) => e.item.title), titles);
    },
  );

  test('10k library sorting benchmark', () {
    final items = List.generate(
      10000,
      (i) => entry('电影 Movie ${i % 137} 第$i 集', i),
    )..shuffle(Random(42));
    for (final sort in [VideoLibrarySort.title, VideoLibrarySort.year]) {
      final settings = VideoLibrarySettings(sort: sort);
      filterVideoLibrary(items, settings, .9); // Warm runtime, not sort keys.
      final samples = <int>[];
      for (var n = 0; n < 5; n++) {
        final watch = Stopwatch()..start();
        final result = filterVideoLibrary(items, settings, .9);
        watch.stop();
        expect(result, hasLength(10000));
        samples.add(watch.elapsedMicroseconds);
      }
      samples.sort();
      // Reporting only: machine load must not make correctness tests flaky.
      debugPrint(
        '${sort.name}: median ${samples[2] / 1000} ms; samples $samples',
      );
    }
  }, skip: !const bool.fromEnvironment('RUN_SORT_BENCHMARK'));
}
