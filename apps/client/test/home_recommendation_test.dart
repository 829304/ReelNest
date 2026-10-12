import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/features/home/domain/home_artwork_palette.dart';
import 'package:reelnest/features/home/domain/home_recommendation.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/features/home/application/home_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';

final now = DateTime(2026, 10, 12, 12);
HomeVideo video(
  String id, {
  String source = 'source',
  String type = 'movie',
  double? rating = 9,
  double? user,
  bool watched = false,
  double progress = 0,
  bool favorite = false,
  bool listed = false,
  List<String> genres = const [],
  String? parent,
  DateTime? lastPlayed,
  DateTime? updated,
}) {
  final identity = (sourceId: source, localId: id);
  final date = updated ?? now.subtract(const Duration(days: 10));
  return HomeVideo(
    source: MediaSource(
      id: source,
      kind: MediaSourceKind.emby,
      name: source,
      location: 'emby://fixture/$source',
      createdAt: date,
      updatedAt: date,
    ),
    favorite: favorite,
    entry: VideoLibraryEntry(
      item: IndexedMedia(
        identity: identity,
        title: id,
        type: type,
        isSeries: type == 'tvShow',
        bytes: 0,
        modified: date,
        updatedAt: date,
        parentId: parent,
        remote: RemoteMediaMetadata(
          externalId: id,
          rating: rating,
          genres: genres,
        ),
      ),
      record: PlaybackRecord(
        identity: identity,
        position: Duration(milliseconds: (progress * 100000).round()),
        duration: const Duration(milliseconds: 100000),
        watched: watched,
        lastPlayedAt: lastPlayed,
      ),
      createdAt: date,
      userRating: user,
      watchlist: listed,
    ),
  );
}

List<MediaIdentity> ids(List<HomeVideo> list) =>
    list.map((v) => v.item.identity).toList();

class _Date extends HomeDate {
  @override
  DateTime build() => now;
  void nextDay() => state = state.add(const Duration(days: 1));
}

Future<HomeRecommendation> ready(ProviderContainer container) async {
  await container.pump();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await container.pump();
  return container.read(homeRecommendationProvider.future);
}

void main() {
  testWidgets(
    'available source renders while another waits; late removed source cannot return',
    (tester) async {
      await tester.runAsync(() async {
        final a = video('a', source: 'a'), b = video('b', source: 'b');
        var sources = [a.source, b.source];
        final delayed = Completer<List<HomeVideo>>();
        final container = ProviderContainer(
          overrides: [
            sidebarSourcesProvider.overrideWith((ref) async => sources),
            homeThresholdProvider.overrideWith((ref) async => .9),
            homeDateProvider.overrideWith(_Date.new),
            homeRecommendationCandidatesProvider.overrideWith(
              (ref, id) => id == 'a' ? Future.value([a]) : delayed.future,
            ),
            homeVideoPageProvider.overrideWith(
              (ref, query) async =>
                  const HomeVideoPage([], nextOffset: 0, hasMore: false),
            ),
            embyCachedVideosProvider.overrideWith(
              (ref) async => throw StateError('cache disk unavailable'),
            ),
          ],
        );
        final subscription = container.listen(
          homeRecommendationProvider,
          (_, _) {},
        );
        try {
          expect(ids((await ready(container)).hero), [a.item.identity]);
          sources = [a.source];
          container.invalidate(sidebarSourcesProvider);
          await ready(container);
          delayed.complete([b]);
          expect(ids((await ready(container)).hero), [a.item.identity]);
        } finally {
          subscription.close();
          container.dispose();
        }
      });
    },
  );
  testWidgets(
    'date refresh rescoring is isolated and does not reread candidates',
    (tester) async {
      await tester.runAsync(() async {
        final items = [for (var n = 0; n < 220; n++) video('candidate$n')];
        var reads = 0;
        final container = ProviderContainer(
          overrides: [
            sidebarSourcesProvider.overrideWith(
              (ref) async => [items.first.source],
            ),
            homeThresholdProvider.overrideWith((ref) async => .9),
            homeDateProvider.overrideWith(_Date.new),
            homeRecommendationCandidatesProvider.overrideWith((ref, id) async {
              reads++;
              return items;
            }),
            homeVideoPageProvider.overrideWith(
              (ref, query) async =>
                  const HomeVideoPage([], nextOffset: 0, hasMore: false),
            ),
            embyCachedVideosProvider.overrideWith((ref) async => []),
          ],
        );
        final subscription = container.listen(
          homeRecommendationProvider,
          (_, _) {},
        );
        try {
          final first = await ready(container);
          final oldReads = reads;
          (container.read(homeDateProvider.notifier) as _Date).nextDay();
          final next = await ready(container);
          expect(identical(first, next), isFalse);
          expect(reads, oldReads);
          expect(
            ids(next.hero),
            ids(
              HomeRecommendationPolicy.build(
                items,
                now: now.add(const Duration(days: 1)),
              ).hero,
            ),
          );
        } finally {
          subscription.close();
          container.dispose();
        }
      });
    },
  );
  test('daily UInt64 scalar hash and local calendar ordinal are stable', () {
    expect(HomeRecommendationPolicy.daySeed(DateTime(1, 1, 1)), 1);
    expect(
      HomeRecommendationPolicy.daySeed(DateTime(2024, 3, 1)) -
          HomeRecommendationPolicy.daySeed(DateTime(2024, 2, 28)),
      2,
    );
    expect(
      HomeRecommendationPolicy.daySeed(now),
      HomeRecommendationPolicy.daySeed(DateTime(2026, 10, 12, 23, 59)),
    );
    expect(HomeRecommendationPolicy.dailyValue('a', 1, 'item'), 659 / 997);
    expect(
      HomeRecommendationPolicy.dailyValue('中文😀', 739901, 'daily-banner'),
      620 / 997,
    );
  });
  test('original score normalization and folded genre splitting', () {
    expect(HomeRecommendationPolicy.providerScore(4.5), 9);
    expect(HomeRecommendationPolicy.providerScore(10.5), 10);
    expect(HomeRecommendationPolicy.providerScore(double.nan), 0);
    expect(HomeRecommendationPolicy.userScore(4.5), 9);
    expect(HomeRecommendationPolicy.userScore(-1), 0);
    expect(
      HomeRecommendationPolicy.genres([' ＣＡＦÉ / cafe，CAFÉ;动作、动作| Drama ']),
      {'cafe': 'ＣＡＦÉ', '动作': '动作', 'drama': 'Drama'},
    );
  });
  test(
    'qualified daily banner is seven unique high score public top-level videos',
    () {
      final items = [
        for (var n = 0; n < 30; n++) video('high$n'),
        video('low', rating: 7),
        video('child', type: 'episode', parent: 'series'),
        video('music', type: 'music'),
        video('vault', type: 'private'),
        video('photo', type: 'photo'),
      ];
      final board = HomeRecommendationPolicy.build(items, now: now);
      expect(board.hero, hasLength(7));
      expect(ids(board.hero).toSet(), hasLength(7));
      expect(board.hero.every((v) => v.item.title.startsWith('high')), isTrue);
      final repeated = HomeRecommendationPolicy.build(items.reversed, now: now);
      expect(ids(repeated.hero), ids(board.hero));
      final seed = HomeRecommendationPolicy.daySeed(now);
      expect(
        HomeRecommendationPolicy.dailyValue('high6', seed, 'daily-banner'),
        isNot(
          HomeRecommendationPolicy.dailyValue(
            'high6',
            seed + 1,
            'daily-banner',
          ),
        ),
      );
      // Original hashing changes scores each day, but does not promise that
      // every adjacent day's top seven differ.
    },
  );
  test(
    'unrated first library still supplies Vivid hero and series fallback',
    () {
      final board = HomeRecommendationPolicy.build([
        video('movie', rating: null),
        video('series', type: 'tvShow', rating: null),
      ], now: now);
      expect(board.hero, hasLength(2));
      expect(board.series.single.item.title, 'series');
      expect(board.highRated, isEmpty);
    },
  );
  test('same remote ID across sources stays distinct and favorite signals affect genre', () {
    final items = [
      video(
        'same',
        source: 'a',
        rating: 7.5,
        genres: ['Drama'],
        favorite: true,
      ),
      video('same', source: 'b', rating: 7.5, genres: ['Action']),
      for (var n = 0; n < 40; n++)
        video('drama$n', rating: 7.5, genres: ['Drama']),
    ];
    final board = HomeRecommendationPolicy.build(items, now: now);
    expect(board.genre, 'Drama');
    expect(board.theme, isNotEmpty);
    expect(
      board.theme.every((v) => v.item.remote!.genres.contains('Drama')),
      isTrue,
    );
    final small = HomeRecommendationPolicy.build(items.take(2), now: now);
    expect(ids(small.hero).toSet(), {
      (sourceId: 'a', localId: 'same'),
      (sourceId: 'b', localId: 'same'),
    });
  });
  test('high-rated primary prefers unfinished nonseries and excludes earlier series choices', () {
    final board = HomeRecommendationPolicy.build([
      for (var n = 0; n < 80; n++) video('movie$n', rating: 8.5),
      for (var n = 0; n < 60; n++)
        video('series$n', type: 'tvShow', rating: 9.5),
      video('watched', watched: true, rating: 10),
      video('threshold', progress: .9, rating: 10),
    ], now: now);
    expect(board.series, hasLength(12));
    expect(board.highRated, hasLength(12));
    expect(
      board.highRated.every(
        (v) =>
            v.item.type == 'movie' &&
            !v.entry.record.watched &&
            v.entry.progress < .9,
      ),
      isTrue,
    );
    expect(
      ids(board.series).toSet().intersection(ids(board.recentSeries).toSet()),
      isEmpty,
    );
    expect(
      ids(board.series).toSet().intersection(ids(board.highRated).toSet()),
      isEmpty,
    );
  });
  test(
    'offline projection uses only externally validated scoped cache identities',
    () {
      final a = video('same', source: 'a'), b = video('same', source: 'b');
      final board = HomeRecommendationPolicy.build(
        [a, b],
        now: now,
        offline: {a.item.identity, (sourceId: 'missing', localId: 'same')},
      );
      expect(ids(board.offline), [a.item.identity]);
    },
  );
  test('original palette keeps neutral artwork neutral and colorful artwork in its hue family', () {
    Uint8List rgba(Color color) => Uint8List.fromList(
      List.generate(
        36 * 36,
        (_) => [
          (color.r * 255).round(),
          (color.g * 255).round(),
          (color.b * 255).round(),
          255,
        ],
      ).expand((p) => p).toList(),
    );
    final neutral = HomeArtworkPalette.fromRgba(
      rgba(const Color(0xFFCCCCCC)),
      36,
      36,
    );
    expect(HSVColor.fromColor(neutral.primary).saturation, 0);
    expect(HSVColor.fromColor(neutral.glowPrimary).saturation, 0);
    final blue = HomeArtworkPalette.fromRgba(
      rgba(const Color(0xFF2050C0)),
      36,
      36,
    );
    expect(HSVColor.fromColor(blue.primary).hue, closeTo(222, 4));
    expect(HSVColor.fromColor(blue.glowPrimary).saturation, greaterThan(.3));
    expect(
      HomeArtworkPalette.fromRgba(Uint8List(0), 0, 0),
      HomeArtworkPalette.fallback,
    );
  });
}
