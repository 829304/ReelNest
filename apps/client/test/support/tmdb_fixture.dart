import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:reelnest/features/metadata/data/tmdb_client.dart';

final tmdbFixturePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _RealHttp extends HttpOverrides {}

class TmdbFixture {
  TmdbFixture._(this.server) {
    server.listen((request) async {
      try {
        await handle(request);
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
  }
  final HttpServer server;
  final requests = <Uri>[];
  final authorizations = <String?>[];
  Future<void> Function(HttpRequest)? intercept;
  bool failDetail = false, failImages = false;
  Future<void>? detailGate;
  final detailStarted = Completer<void>();
  static Future<TmdbFixture> start() async =>
      TmdbFixture._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  Uri get base => Uri.parse('http://127.0.0.1:${server.port}/');
  TmdbClient client({Duration timeout = const Duration(seconds: 2)}) =>
      TmdbClient(
        apiBase: base.resolve('3/'),
        imageBase: base.resolve('t/p/'),
        allowInsecureForTesting: true,
        timeout: timeout,
        createHttpClient: () =>
            HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp()),
      );
  Map<String, dynamic> candidate(int id) => {
    'id': id,
    'title': '电影 $id',
    'original_title': 'Film $id',
    'release_date': '2020-03-04',
    'overview': 'Search overview',
    'poster_path': '/poster.png',
    'backdrop_path': '/backdrop.png',
    'vote_average': 8.2,
    'genre_ids': [28, 18],
  };
  Map<String, dynamic> movie(int id) => {
    ...candidate(id),
    'title': '完整电影 $id',
    'runtime': 125,
    'overview': 'Detailed overview',
    'genres': [
      {'id': 28, 'name': '动作'},
    ],
    'external_ids': {'imdb_id': 'tt0000042'},
    'production_companies': [
      {'name': 'Studio'},
    ],
    'credits': {
      'cast': [
        {
          'id': 2,
          'name': '乙',
          'character': '配角',
          'order': 2,
          'profile_path': '/actor.png',
        },
        {
          'id': 1,
          'name': '甲',
          'character': '主角',
          'order': 0,
          'profile_path': '/actor.png',
        },
      ],
      'crew': [
        {'id': 3, 'name': '导演', 'job': 'Director'},
        {'id': 3, 'name': '导演', 'job': 'Writer'},
        {'id': 4, 'name': '其他', 'job': 'Assistant'},
      ],
    },
  };
  Map<String, dynamic> tvCandidate(int id) => {
    'id': id,
    'name': '剧集 $id',
    'original_name': 'Show $id',
    'first_air_date': '2021-02-03',
    'overview': 'Series search overview',
    'poster_path': '/poster.png',
    'backdrop_path': '/backdrop.png',
    'vote_average': 8.6,
    'genre_ids': [10759, 10765],
  };
  Map<String, dynamic> series(int id) => {
    ...tvCandidate(id),
    'name': '完整剧集 $id',
    'overview': 'Series detail overview',
    'episode_run_time': [45],
    'status': 'Ended',
    'last_air_date': '2023-05-06',
    'number_of_seasons': 3,
    'number_of_episodes': 24,
    'genres': [
      {'id': 10765, 'name': '科幻奇幻'},
    ],
    'created_by': [
      {'id': 5, 'name': '主创甲'},
    ],
    'aggregate_credits': {
      'cast': [
        {
          'id': 6,
          'name': '演员甲',
          'order': 0,
          'roles': [
            {'character': '角色甲', 'episode_count': 24},
          ],
          'profile_path': '/actor.png',
        },
      ],
      'crew': [
        {
          'id': 5,
          'name': '主创甲',
          'jobs': [
            {'job': 'Writer'},
          ],
        },
        {
          'id': 7,
          'name': '制片甲',
          'jobs': [
            {'job': 'Producer'},
          ],
        },
      ],
    },
    'content_ratings': {
      'results': [
        {'iso_3166_1': 'US', 'rating': 'TV-14'},
      ],
    },
    'external_ids': {'imdb_id': 'tt1234567'},
    'production_companies': [
      {'name': 'TV Studio'},
    ],
    'seasons': [
      for (final number in [0, 1, 2, 3])
        {
          'season_number': number,
          'name': '第 $number 季',
          'overview': 'Season summary',
        },
    ],
  };
  Map<String, dynamic> season(int id, int number) => {
    'id': 100 + number,
    'season_number': number,
    'name': '季 $number',
    'overview': 'Season $number overview',
    'air_date': '2021-02-03',
    'episodes': [
      for (final n in [1, 2, 3])
        {
          'id': id * 10000 + number * 100 + n,
          'show_id': id,
          'season_number': number,
          'episode_number': n,
          'name': '单集 $number-$n',
          'overview': 'Episode $number-$n overview',
          'air_date': '2021-02-03',
          'runtime': 46,
          'vote_average': 7.7,
        },
    ],
  };
  Future<void> json(HttpRequest request, Object value) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(value));
    await request.response.close();
  }

  Future<void> handle(HttpRequest request) async {
    requests.add(request.uri);
    authorizations.add(request.headers.value(HttpHeaders.authorizationHeader));
    if (intercept != null) {
      await intercept!(request);
      return;
    }
    if (request.uri.path == '/3/search/movie') {
      await json(request, {
        'results': List.generate(14, (i) => candidate(i + 1)),
      });
      return;
    }
    if (request.uri.path == '/3/search/tv') {
      await json(request, {
        'results': List.generate(14, (i) => tvCandidate(i + 1)),
      });
      return;
    }
    if (request.uri.path.startsWith('/3/tv/')) {
      final parts = request.uri.pathSegments;
      if (parts.length == 5 && parts[3] == 'season') {
        await json(request, season(int.parse(parts[2]), int.parse(parts[4])));
        return;
      }
      if (!detailStarted.isCompleted) detailStarted.complete();
      await detailGate;
      if (failDetail) {
        request.response.statusCode = 503;
        await request.response.close();
        return;
      }
      await json(request, series(int.parse(parts[2])));
      return;
    }
    if (request.uri.path.startsWith('/3/movie/')) {
      if (!detailStarted.isCompleted) detailStarted.complete();
      await detailGate;
      if (failDetail) {
        request.response.statusCode = 503;
        await request.response.close();
        return;
      }
      await json(request, movie(int.parse(request.uri.pathSegments.last)));
      return;
    }
    if (request.uri.path.startsWith('/t/p/')) {
      if (failImages) {
        request.response.statusCode = 404;
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(Uint8List.fromList(tmdbFixturePng));
      }
      await request.response.close();
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  }

  Future<void>? _closing;
  Future<void> close() => _closing ??= server.close(force: true).then((_) {});
}
