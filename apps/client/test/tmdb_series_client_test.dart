import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';

import 'support/tmdb_fixture.dart';

void main() {
  late TmdbFixture fixture;
  setUp(() async {
    fixture = await TmdbFixture.start();
  });
  tearDown(() async {
    await fixture.close();
  });
  Future<List<TmdbCandidate>> search() => fixture.client().search(
    'Show',
    kind: TmdbMediaKind.tv,
    credential: 'fixture-key',
    language: 'zh-CN',
    cancellation: ScanCancellation(),
  );
  Future<TmdbMetadata> detail({TmdbCandidate? fallback}) =>
      fixture.client().series(
        1,
        credential: 'fixture-key',
        language: 'zh-CN',
        cancellation: ScanCancellation(),
        fallback: fallback,
      );
  Future<TmdbSeasonMetadata> season(int number, {ScanCancellation? token}) =>
      fixture.client().season(
        1,
        number,
        credential: 'fixture-key',
        language: 'zh-CN',
        cancellation: token ?? ScanCancellation(),
      );
  test('TV search uses original TV fields, relevance and genres with no year filter', () async {
    final results = await search();
    expect(results, hasLength(12));
    expect(results.first.kind, TmdbMediaKind.tv);
    expect(results.first.externalId, 'tmdb:tv:1');
    expect(results.first.title, '剧集 1');
    expect(results.first.originalTitle, 'Show 1');
    expect(results.first.releaseDate, '2021-02-03');
    expect(results.first.year, 2021);
    expect(results.first.genres, ['动作冒险', '科幻奇幻']);
    expect(fixture.requests.single.path, '/3/search/tv');
    expect(fixture.requests.single.queryParameters, {
      'query': 'Show',
      'language': 'zh-CN',
      'include_adult': 'false',
      'api_key': 'fixture-key',
    });
    expect(
      TmdbCandidate.fromJson(results.first.toJson()).externalId,
      'tmdb:tv:1',
    );
  });
  test('TV aggregate roles, creators, ratings, dates and season summaries round trip', () async {
    final value = await detail();
    expect(value.cast.single.role, '角色甲');
    expect(value.crew.map((c) => c.role), ['主创', '制片']);
    expect(value.runtimeMinutes, 45);
    expect(value.contentRating, 'TV-14');
    expect(value.firstAirDate, '2021-02-03');
    expect(value.lastAirDate, '2023-05-06');
    expect(value.numberOfEpisodes, 24);
    expect(value.numberOfSeasons, 3);
    expect(value.productionCompanies, ['TV Studio']);
    expect(value.status, 'Ended');
    expect(
      fixture.requests.single.queryParameters['append_to_response'],
      'aggregate_credits,external_ids,content_ratings',
    );
    final restored = TmdbMetadata.fromJson(value.toJson());
    expect(restored.candidate.kind, TmdbMediaKind.tv);
    expect(restored.seasons.map((s) => s.number), [0, 1, 2, 3]);
    expect(restored.cast.single.role, '角色甲');
  });
  test('empty TV detail fields retain selected candidate artwork and search description', () async {
    final choice = (await search()).first;
    fixture.intercept = (r) => fixture.json(r, {'id': 1});
    final value = await detail(fallback: choice);
    expect(value.candidate.title, choice.title);
    expect(value.candidate.overview, choice.overview);
    expect(value.candidate.posterUrl, choice.posterUrl);
    expect(value.candidate.rating, 8.6);
  });
  test('TV and movie candidates cannot cross namespaces', () async {
    await expectLater(
      detail(fallback: const TmdbCandidate(id: 1, title: 'Movie')),
      throwsA(isA<SourceFailure>()),
    );
    expect(fixture.requests, isEmpty);
  });
  test(
    'special season zero and exact episode identifiers are decoded',
    () async {
      final value = await season(0);
      expect(fixture.requests.single.path, '/3/tv/1/season/0');
      expect(value.number, 0);
      expect(value.episodes.first.seriesId, 1);
      expect(value.episodes.first.episodeNumber, 1);
      expect(value.episodes.first.title, '单集 0-1');
      expect(value.episodes.first.runtimeMinutes, 46);
      expect(value.episodes.first.rating, 7.7);
      expect(
        TmdbSeasonMetadata.fromJson(value.toJson()).episodes.last.episodeNumber,
        3,
      );
    },
  );
  test(
    'mismatched season and duplicate or wrong-series episodes are rejected',
    () async {
      for (final mode in ['season', 'duplicate', 'series']) {
        fixture.intercept = (r) async {
          final value = fixture.season(1, 1);
          final episodes = value['episodes'] as List;
          if (mode == 'season') value['season_number'] = 2;
          if (mode == 'duplicate') episodes.add(episodes.first);
          if (mode == 'series') (episodes.first as Map)['show_id'] = 99;
          await fixture.json(r, value);
        };
        await expectLater(season(1), throwsA(isA<SourceFailure>()));
      }
    },
  );
  test('season transport cancellation stops promptly and never retries a late response', () async {
    final started = Completer<void>(),
        gate = Completer<void>(),
        token = ScanCancellation();
    fixture.intercept = (r) async {
      started.complete();
      await gate.future;
      r.response.statusCode = 503;
      await r.response.close();
    };
    final work = expectLater(
      season(1, token: token),
      throwsA(isA<ScanCancelled>()),
    );
    await started.future;
    token.cancel();
    await work.timeout(const Duration(seconds: 1));
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(fixture.requests, hasLength(1));
  });
}
