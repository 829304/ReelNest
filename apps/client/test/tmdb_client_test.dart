import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/data/tmdb_client.dart';

import 'support/tmdb_fixture.dart';

void main() {
  late TmdbFixture fixture;
  setUp(() async {
    fixture = await TmdbFixture.start();
  });
  tearDown(() async {
    await fixture.close();
  });
  Future<dynamic> search({
    TmdbClient? client,
    String key = 'fixture-key',
    ScanCancellation? token,
  }) => (client ?? fixture.client()).search(
    '  电影 & film  ',
    credential: key,
    language: 'zh-CN',
    cancellation: token ?? ScanCancellation(),
  );
  test('original movie endpoint, unfiltered title, order, twelve results and normalized fields', () async {
    final results = await search();
    expect(results, hasLength(12));
    expect(results.first.id, 1);
    expect(results.last.id, 12);
    expect(results.first.originalTitle, 'Film 1');
    expect(results.first.year, 2020);
    expect(results.first.rating, 8.2);
    expect(results.first.genres, ['动作', '剧情']);
    expect(results.first.provider, 'TMDB[zh-CN]');
    final uri = fixture.requests.single;
    expect(uri.path, '/3/search/movie');
    expect(uri.queryParameters, {
      'query': '电影 & film',
      'language': 'zh-CN',
      'include_adult': 'false',
      'api_key': 'fixture-key',
    });
    expect(fixture.authorizations.single, isNull);
  });
  test(
    'Bearer detection and public artwork never receives either credential',
    () async {
      const key = 'fixture.access.token';
      final results = await search(key: key);
      expect(fixture.authorizations.first, 'Bearer $key');
      expect(
        fixture.requests.first.queryParameters.containsKey('api_key'),
        isFalse,
      );
      await fixture.client().artwork(
        results.first.posterUrl,
        ScanCancellation(),
      );
      expect(fixture.authorizations.last, isNull);
      expect(fixture.requests.last.hasQuery, isFalse);
    },
  );
  test(
    'detail merges missing search fields and original cast/crew rules',
    () async {
      final selected = (await search()).first;
      fixture.intercept = (request) async {
        final json = fixture.movie(1)
          ..remove('poster_path')
          ..remove('overview')
          ..remove('genres')
          ..remove('vote_average');
        await fixture.json(request, json);
      };
      final detail = await fixture.client().movie(
        1,
        credential: 'fixture-key',
        language: 'zh-CN',
        cancellation: ScanCancellation(),
        fallback: selected,
      );
      expect(detail.candidate.overview, selected.overview);
      expect(detail.candidate.posterUrl, selected.posterUrl);
      expect(detail.candidate.rating, selected.rating);
      expect(detail.genres, selected.genres);
      expect(detail.runtimeMinutes, 125);
      expect(detail.cast.map((v) => v.name), ['甲', '乙']);
      expect(detail.crew.map((v) => v.role), ['导演']);
      expect(detail.imdbId, 'tt0000042');
      expect(detail.productionCompanies, ['Studio']);
    },
  );
  test(
    'detail retries transient status with original delay policy and succeeds',
    () async {
      var attempts = 0;
      fixture.intercept = (request) async {
        attempts++;
        if (attempts == 1) {
          request.response.statusCode = 503;
          request.response.headers.set('Retry-After', '0');
          await request.response.close();
        } else {
          await fixture.json(request, fixture.movie(1));
        }
      };
      final result = await fixture.client().movie(
        1,
        credential: 'fixture-key',
        language: 'zh-CN',
        cancellation: ScanCancellation(),
      );
      expect(result.candidate.id, 1);
      expect(attempts, 2);
      expect(TmdbClient.retryDelay('-3', 1), const Duration(milliseconds: 500));
      expect(TmdbClient.retryDelay('Infinity', 2), const Duration(seconds: 2));
      expect(TmdbClient.retryDelay('1000', 1), const Duration(seconds: 4));
    },
  );
  test(
    'cancel while waiting to retry never sends an expired detail request',
    () async {
      final first = Completer<void>();
      fixture.intercept = (request) async {
        request.response.statusCode = 503;
        request.response.headers.set('Retry-After', '0');
        await request.response.close();
        if (!first.isCompleted) first.complete();
      };
      final token = ScanCancellation();
      final pending = fixture.client().movie(
        1,
        credential: 'fixture-key',
        language: 'zh-CN',
        cancellation: token,
      );
      await first.future;
      token.cancel();
      await expectLater(pending, throwsA(isA<ScanCancelled>()));
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(fixture.requests, hasLength(1));
    },
  );
  test('rejects wrong movie identity and invalid credentials without leaking secrets', () async {
    fixture.intercept = (request) => fixture.json(request, fixture.movie(2));
    await expectLater(
      fixture.client().movie(
        1,
        credential: 'fixture-key',
        language: 'zh-CN',
        cancellation: ScanCancellation(),
      ),
      throwsA(isA<SourceFailure>()),
    );
    await expectLater(
      search(key: 'secret\nheader'),
      throwsA(
        isA<SourceFailure>().having(
          (e) => e.message,
          'safe',
          isNot(contains('secret')),
        ),
      ),
    );
  });
  for (final status in [302, 401, 429, 503]) {
    test(
      'status $status fails safely and redirects never send credentials again',
      () async {
        fixture.intercept = (request) async {
          request.response.statusCode = status;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            fixture.base.resolve('stolen').toString(),
          );
          await request.response.close();
        };
        await expectLater(
          search(),
          throwsA(
            isA<SourceFailure>().having(
              (e) => e.message,
              'safe',
              isNot(contains('fixture-key')),
            ),
          ),
        );
        expect(fixture.requests, hasLength(1));
      },
    );
  }
  test('size cap rejects oversized declared body before download', () async {
    fixture.intercept = (request) async {
      request.response.contentLength = TmdbClient.jsonLimit + 1;
      request.response.add([0]);
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await request.response.close();
    };
    await expectLater(
      search(),
      throwsA(
        isA<SourceFailure>().having((e) => e.message, 'size', contains('过大')),
      ),
    );
  });
  test('size cap also rejects chunked data without Content-Length', () async {
    fixture.intercept = (request) async {
      for (var i = 0; i < 70; i++) {
        request.response.add(Uint8List(65536));
        await request.response.flush();
      }
      await request.response.close();
    };
    await expectLater(
      search(),
      throwsA(
        isA<SourceFailure>().having((e) => e.message, 'size', contains('过大')),
      ),
    );
  });
  test(
    'cancellation aborts a request while waiting for response headers',
    () async {
      final started = Completer<void>(), finish = Completer<void>();
      fixture.intercept = (request) async {
        started.complete();
        await finish.future;
        await request.response.close();
      };
      final token = ScanCancellation();
      final future = search(token: token);
      await started.future;
      token.cancel();
      await expectLater(
        future.timeout(const Duration(seconds: 1)),
        throwsA(isA<ScanCancelled>()),
      );
      finish.complete();
    },
  );
  test(
    'timeout covers a stalled response, with fixed safe error text',
    () async {
      final gate = Completer<void>();
      fixture.intercept = (request) async {
        await gate.future;
        await request.response.close();
      };
      await expectLater(
        search(
          client: fixture.client(timeout: const Duration(milliseconds: 70)),
        ),
        throwsA(
          isA<SourceFailure>().having(
            (e) => e.message,
            'timeout',
            contains('超时'),
          ),
        ),
      );
      gate.complete();
    },
  );
  test(
    'malformed DTO shape cannot leak parser exceptions or response data',
    () async {
      fixture.intercept = (request) => fixture.json(request, {
        'results': [
          {'id': 'fixture-key'},
        ],
      });
      await expectLater(
        search(),
        throwsA(
          isA<SourceFailure>().having(
            (e) => e.message,
            'safe',
            isNot(contains('fixture-key')),
          ),
        ),
      );
    },
  );
  test(
    'malformed JSON returns a safe failure and not an empty result',
    () async {
      fixture.intercept = (request) async {
        request.response.write('<html>private fixture-key</html>');
        await request.response.close();
      };
      await expectLater(
        search(),
        throwsA(
          isA<SourceFailure>().having(
            (e) => e.message,
            'safe',
            isNot(contains('fixture-key')),
          ),
        ),
      );
    },
  );
}
