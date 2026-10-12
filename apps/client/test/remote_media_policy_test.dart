import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/domain/remote_media_policy.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';

IndexedMedia _item({
  String type = 'movie',
  String? parentId,
  bool isSeries = false,
  RemoteMediaMetadata? remote,
}) => IndexedMedia(
  identity: (sourceId: 'source', localId: 'item'),
  title: 'Sample',
  type: type,
  bytes: 0,
  modified: DateTime.utc(2026),
  parentId: parentId,
  isSeries: isSeries,
  remote: remote,
);

void main() {
  test('community score seeds rounded and clamped 1-5 stars', () {
    for (final (score, stars) in [
      (0.1, 1.0),
      (1.0, 1.0),
      (2.9, 1.0),
      (3.0, 2.0),
      (5.0, 3.0),
      (8.2, 4.0),
      (8.4, 4.0),
      (9.0, 5.0),
      (10.0, 5.0),
    ]) {
      expect(RemoteRatingPolicy.seedUserRating(score), stars, reason: '$score');
      expect(RemoteRatingPolicy.normalizedProviderRating(score), score);
    }
  });
  test(
    'missing non-finite and out of range community scores are not ratings',
    () {
      for (final score in [
        null,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1.0,
        0.0,
        10.1,
      ]) {
        expect(RemoteRatingPolicy.seedUserRating(score), isNull);
        expect(RemoteRatingPolicy.normalizedProviderRating(score), isNull);
      }
    },
  );
  test('library name precedes genre and collection type', () {
    expect(
      RemoteLibraryClassificationPolicy.inferredMediaType(
        type: 'movie',
        libraryName: '动漫剧场',
        genres: ['Documentary'],
        collectionType: 'movies',
      ),
      'anime',
    );
  });
  test('genre precedes collection type when library name has no match', () {
    expect(
      RemoteLibraryClassificationPolicy.inferredMediaType(
        type: 'movie',
        libraryName: 'Unsorted',
        genres: ['Reality', 'Talk Show'],
        collectionType: 'movies',
      ),
      'variety',
    );
  });
  test('collection type is the third fallback with original rule order', () {
    for (final (collection, type) in [
      ('movies', 'movie'),
      ('movie', 'movie'),
      ('tvshows', 'tvShow'),
      ('series', 'tvShow'),
      ('homevideos', 'homeVideo'),
      ('Home Video', 'homeVideo'),
      ('musicvideos', 'music'),
      ('homevideos movies', 'movie'),
    ]) {
      expect(
        RemoteLibraryClassificationPolicy.inferredMediaType(
          type: 'other',
          libraryName: 'Archive',
          collectionType: collection,
        ),
        type,
        reason: collection,
      );
    }
    expect(
      RemoteLibraryClassificationPolicy.inferFromCollectionType('mixed'),
      isNull,
    );
  });
  test('unclassified items keep their original type and episodes fall back to series', () {
    expect(
      RemoteLibraryClassificationPolicy.inferredMediaType(
        type: 'documentary',
        libraryName: 'Archive',
        collectionType: 'mixed',
      ),
      'documentary',
    );
    expect(
      RemoteLibraryClassificationPolicy.inferredMediaType(type: 'episode'),
      'tvShow',
    );
    expect(
      RemoteLibraryClassificationPolicy.inferredMediaType(type: 'other'),
      'other',
    );
  });
  test(
    'overlapping keywords follow original ordering rather than token position',
    () {
      for (final (name, type) in [
        ('Movies Anime', 'anime'),
        ('电影纪录', 'documentary'),
        ('Reality Documentary', 'documentary'),
        ('Home Movies', 'homeVideo'),
        ('家庭影像电影', 'homeVideo'),
        ('电视剧电影', 'movie'),
      ]) {
        expect(
          RemoteLibraryClassificationPolicy.inferFromLibraryName(name),
          type,
        );
      }
      expect(
        RemoteLibraryClassificationPolicy.inferredMediaType(
          type: 'movie',
          genres: ['Documentary', 'Animation'],
        ),
        'anime',
      );
    },
  );
  test(
    'original Chinese and English classification families are supported',
    () {
      for (final (name, type) in [
        ('新番', 'anime'),
        ('Bangumi', 'anime'),
        ('纪实', 'documentary'),
        ('Documentaries', 'documentary'),
        ('脱口秀', 'variety'),
        ('Talkshow', 'variety'),
        ('生活录像', 'homeVideo'),
        ('Other Videos', 'homeVideo'),
        ('影院', 'movie'),
        ('Cinema', 'movie'),
        ('华语剧', 'tvShow'),
        ('Drama', 'tvShow'),
      ]) {
        expect(
          RemoteLibraryClassificationPolicy.inferFromLibraryName(name),
          type,
        );
      }
      // Film/Drama are library-name rules, not genre rules.
      expect(
        RemoteLibraryClassificationPolicy.inferFromGenre('Film, Drama'),
        isNull,
      );
      expect(
        RemoteLibraryClassificationPolicy.inferFromLibraryName(null),
        isNull,
      );
    },
  );
  test(
    'classifier decodes percent encoding and folds case width and accents',
    () {
      for (final (name, type) in [
        ('Home%20Movies', 'homeVideo'),
        ('%E5%8A%A8%E6%BC%AB', 'anime'),
        ('ＡＮＩＭＥ', 'anime'),
        ('ＨＯＭＥ　ＭＯＶＩＥＳ', 'homeVideo'),
        ('Anİmé', 'anime'),
        ('ANI\u0301ME\u0301', 'anime'),
        ('Dócumentáry', 'documentary'),
      ]) {
        expect(
          RemoteLibraryClassificationPolicy.inferFromLibraryName(name),
          type,
          reason: name,
        );
      }
      // URL query semantics must not turn plus into space.
      expect(
        RemoteLibraryClassificationPolicy.inferFromLibraryName('Home+Videos'),
        isNull,
      );
    },
  );
  test('malformed percent input uses the original text without throwing', () {
    for (final name in ['Anime%', 'Anime%ZZ', 'Anime%FF']) {
      expect(
        RemoteLibraryClassificationPolicy.inferFromLibraryName(name),
        'anime',
      );
    }
    expect(
      RemoteLibraryClassificationPolicy.inferFromLibraryName('%ZZ'),
      isNull,
    );
  });
  test(
    'only remote non-music top-level items receive display classification',
    () {
      const metadata = RemoteMediaMetadata(
        externalId: 'item',
        libraryName: '动漫电影',
        collectionType: 'movies',
      );
      expect(_item().displayType, 'movie');
      expect(_item(type: 'music', remote: metadata).displayType, 'music');
      final episode = _item(
        type: 'episode',
        parentId: 'show',
        remote: metadata,
      );
      expect(episode.displayType, 'episode');
      expect(episode.parentId, 'show');
      expect(episode.cardTitle, '剧集  Sample');
    },
  );
  test(
    'display classification preserves stored playback and series identity',
    () {
      const metadata = RemoteMediaMetadata(
        externalId: 'item',
        libraryName: '动漫',
        collectionType: 'tvshows',
      );
      final series = _item(type: 'tvShow', isSeries: true, remote: metadata);
      expect(series.displayType, 'anime');
      expect(series.type, 'tvShow');
      expect(series.isSeries, isTrue);
      expect(series.filePath, isNull);
      final movie = _item(remote: metadata);
      expect(movie.displayType, 'anime');
      expect(movie.type, 'movie');
      expect(movie.filePath, 'item');
    },
  );
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform poster fallback uses display classification', (
      tester,
    ) async {
      final item = _item(
        remote: const RemoteMediaMetadata(
          externalId: 'item',
          libraryName: '纪录片',
          collectionType: 'movies',
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: SizedBox(
                width: 180,
                height: 270,
                child: LocalMediaArtwork(
                  source: MediaSource(
                    id: 'source',
                    kind: MediaSourceKind.emby,
                    name: 'Test',
                    location: 'http://localhost:8096',
                    createdAt: DateTime.utc(2026),
                    updatedAt: DateTime.utc(2026),
                  ),
                  item: item,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('纪录片'), findsOneWidget);
      expect(find.text('电影'), findsNothing);
      expect(item.type, 'movie');
      expect(tester.takeException(), isNull);
    });
  }
}
