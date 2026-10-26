import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../domain/media_source.dart';
import '../domain/tmdb_models.dart';

/// MetadataSearchService / TMDBEnrichmentService video metadata subset.
class TmdbClient {
  TmdbClient({
    Uri? apiBase,
    Uri? imageBase,
    this.allowInsecureForTesting = false,
    this.timeout = const Duration(seconds: 12),
    HttpClient Function()? createHttpClient,
  }) : apiBase = apiBase ?? Uri.parse('https://api.themoviedb.org/3/'),
       imageBase = imageBase ?? Uri.parse('https://image.tmdb.org/t/p/'),
       _createClient = createHttpClient ?? HttpClient.new;
  final HttpClient Function() _createClient;
  final Uri apiBase, imageBase;
  final bool allowInsecureForTesting;
  final Duration timeout;
  static const jsonLimit = 4 * 1024 * 1024, imageLimit = 8 * 1024 * 1024;

  Future<List<TmdbCandidate>> search(
    String query, {
    required String credential,
    required String language,
    required ScanCancellation cancellation,
    TmdbMediaKind kind = TmdbMediaKind.movie,
  }) => _decode(
    () => _search(
      query,
      kind: kind,
      credential: credential,
      language: language,
      cancellation: cancellation,
    ),
  );

  Future<List<TmdbCandidate>> _search(
    String query, {
    required String credential,
    required String language,
    required ScanCancellation cancellation,
    required TmdbMediaKind kind,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    if (clean.length > 1024) throw const SourceFailure('搜索关键词过长。');
    final json = await _json(
      'search/${kind.name}',
      {'query': clean, 'language': language, 'include_adult': 'false'},
      credential,
      cancellation,
    );
    final results = json['results'];
    if (results is! List) throw const SourceFailure('TMDB 返回了无法解析的搜索结果。');
    return List.unmodifiable(
      results
          .take(12)
          .map(
            (v) => _candidate(
              Map<String, dynamic>.from(v as Map),
              language,
              kind: kind,
            ),
          ),
    );
  }

  Future<TmdbMetadata> movie(
    int id, {
    required String credential,
    required String language,
    required ScanCancellation cancellation,
    TmdbCandidate? fallback,
  }) => _decode(
    () => _detail(
      id,
      kind: TmdbMediaKind.movie,
      credential: credential,
      language: language,
      cancellation: cancellation,
      fallback: fallback,
    ),
  );

  Future<TmdbMetadata> series(
    int id, {
    required String credential,
    required String language,
    required ScanCancellation cancellation,
    TmdbCandidate? fallback,
  }) => _decode(
    () => _detail(
      id,
      kind: TmdbMediaKind.tv,
      credential: credential,
      language: language,
      cancellation: cancellation,
      fallback: fallback,
    ),
  );

  Future<TmdbMetadata> _detail(
    int id, {
    required TmdbMediaKind kind,
    required String credential,
    required String language,
    required ScanCancellation cancellation,
    TmdbCandidate? fallback,
  }) async {
    if (id <= 0 || (fallback != null && fallback.kind != kind)) {
      throw const SourceFailure('TMDB 媒体标识无效。');
    }
    final tv = kind == TmdbMediaKind.tv;
    final json = await _json(
      '${kind.name}/$id',
      {
        'language': language,
        'append_to_response': tv
            ? 'aggregate_credits,external_ids,content_ratings'
            : 'credits,external_ids,release_dates',
      },
      credential,
      cancellation,
      retryTransient: true,
    );
    if (json['id'] != id) throw const SourceFailure('TMDB 返回了不一致的媒体资料。');
    final candidate = _candidate(
      json,
      language,
      kind: kind,
      fallback: fallback,
    );
    final credits =
        json[tv ? 'aggregate_credits' : 'credits'] as Map? ?? const {};
    final ordered =
        (credits['cast'] as List? ?? const []).asMap().entries.toList()
          ..sort((a, b) {
            final orderA = (a.value as Map)['order'] as int? ?? 0x7fffffff;
            final orderB = (b.value as Map)['order'] as int? ?? 0x7fffffff;
            final cmp = orderA.compareTo(orderB);
            return cmp == 0 ? a.key.compareTo(b.key) : cmp;
          });
    TmdbPerson person(Map v, String role) => TmdbPerson(
      id: v['id'] as int,
      name: _text(v['name']) ?? '未命名',
      role: role,
      profileUrl: _image(v['profile_path'], 'w185'),
    );
    final cast = [
      for (final e in ordered.take(16))
        person(
          e.value as Map,
          _text((e.value as Map)['character']) ??
              _text(
                ((e.value as Map)['roles'] as List?)?.firstOrNull?['character'],
              ) ??
              '演员',
        ),
    ];
    const jobs = {
      'Director': '导演',
      'Writer': '编剧',
      'Screenplay': '编剧',
      'Producer': '制片',
      'Original Music Composer': '配乐',
    };
    final seen = <int>{};
    final crew = <TmdbPerson>[];
    if (tv) {
      for (final raw in json['created_by'] as List? ?? const []) {
        final creator = raw as Map;
        if (crew.length >= 8) break;
        if (seen.add(creator['id'] as int)) crew.add(person(creator, '主创'));
      }
    }
    for (final raw in credits['crew'] as List? ?? const []) {
      if (crew.length >= 8) break;
      final member = raw as Map;
      final job =
          member['job'] ?? (member['jobs'] as List?)?.firstOrNull?['job'];
      if (jobs.containsKey(job) && seen.add(member['id'] as int)) {
        crew.add(person(member, jobs[job]!));
        if (crew.length >= 8) break;
      }
    }
    final runtime =
        (tv
                ? (json['episode_run_time'] as List?)?.firstOrNull as num?
                : json['runtime'] as num?)
            ?.toInt();
    final imdb = _text((json['external_ids'] as Map?)?['imdb_id']);
    final releases =
        (json['release_dates'] as Map?)?['results'] as List? ?? const [];
    final preferred =
        releases.where((v) => (v as Map)['iso_3166_1'] == 'US').firstOrNull ??
        releases.firstOrNull;
    final certifications =
        (preferred as Map?)?['release_dates'] as List? ?? const [];
    final movieRating = certifications
        .map((v) => _text((v as Map)['certification']))
        .whereType<String>()
        .firstOrNull;
    return TmdbMetadata(
      candidate: candidate,
      runtimeMinutes: runtime != null && runtime > 0 ? runtime : null,
      genres: candidate.genres,
      cast: List.unmodifiable(cast),
      crew: List.unmodifiable(crew),
      contentRating: tv ? _tvContentRating(json) : movieRating,
      status: tv ? _text(json['status']) : null,
      firstAirDate: tv ? _text(json['first_air_date']) : null,
      lastAirDate: tv ? _text(json['last_air_date']) : null,
      numberOfSeasons: tv ? json['number_of_seasons'] as int? : null,
      numberOfEpisodes: tv ? json['number_of_episodes'] as int? : null,
      seasons: tv
          ? List.unmodifiable([
              for (final raw in json['seasons'] as List? ?? const [])
                if ((raw as Map)['season_number'] case final int number
                    when number >= 0)
                  TmdbSeasonMetadata(
                    number: number,
                    title: _text(raw['name']) ?? '第 $number 季',
                    overview: _text(raw['overview']),
                    airDate: _text(raw['air_date']),
                    posterUrl: _image(raw['poster_path'], 'w500'),
                  ),
            ])
          : const [],
      imdbId: imdb != null && RegExp(r'^tt[0-9]+$').hasMatch(imdb)
          ? imdb
          : null,
      productionCompanies: List.unmodifiable([
        for (final raw in json['production_companies'] as List? ?? const [])
          if (_text((raw as Map)['name']) case final String name) name,
      ]),
    );
  }

  Future<Uint8List> artwork(String location, ScanCancellation cancellation) {
    final uri = Uri.tryParse(location);
    if (uri == null ||
        uri.origin != imageBase.origin ||
        !uri.path.startsWith(imageBase.path) ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const SourceFailure('TMDB 图片地址无效。');
    }
    return _request(uri, cancellation, maxBytes: imageLimit);
  }

  Future<T> _decode<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ScanCancelled {
      rethrow;
    } on SourceFailure {
      rethrow;
    } catch (_) {
      throw const SourceFailure('TMDB 返回了无法解析的资料。');
    }
  }

  Future<Map<String, dynamic>> _json(
    String endpoint,
    Map<String, String> params,
    String credential,
    ScanCancellation cancellation, {
    bool retryTransient = false,
  }) async {
    final token = credential.trim();
    if (token.isEmpty) {
      throw const SourceFailure('请先在设置中填写 TMDB API Key 或 Read Access Token。');
    }
    if (token.length > 4096 || token.contains(RegExp(r'[^\x21-\x7e]'))) {
      throw const SourceFailure('TMDB 凭据格式不正确。');
    }
    final bearer = token.contains('.') || token.length > 80;
    final uri = apiBase
        .resolve(endpoint)
        .replace(queryParameters: {...params, if (!bearer) 'api_key': token});
    final bytes = await _request(
      uri,
      cancellation,
      authorization: bearer ? 'Bearer $token' : null,
      maxBytes: jsonLimit,
      retryTransient: retryTransient,
    );
    try {
      final value = bytes.length > 65536
          ? await Isolate.run(() => jsonDecode(utf8.decode(bytes)))
          : jsonDecode(utf8.decode(bytes));
      cancellation.check();
      return Map<String, dynamic>.from(value as Map);
    } on ScanCancelled {
      rethrow;
    } catch (_) {
      throw const SourceFailure('TMDB 返回了无法解析的资料。');
    }
  }

  Future<Uint8List> _request(
    Uri uri,
    ScanCancellation cancellation, {
    String? authorization,
    required int maxBytes,
    bool retryTransient = false,
  }) async {
    cancellation.check();
    if (uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(allowInsecureForTesting &&
                uri.scheme == 'http' &&
                ['127.0.0.1', 'localhost', '::1'].contains(uri.host)))) {
      throw const SourceFailure('TMDB 请求地址无效。');
    }
    final client = _createClient()..connectionTimeout = timeout;
    final cancelled = Completer<Uint8List>();
    final unlisten = cancellation.listen(() {
      client.close(force: true);
      if (!cancelled.isCompleted) {
        cancelled.completeError(const ScanCancelled());
      }
    });
    var finished = false;
    Future<Uint8List> perform([int attempt = 0]) async {
      cancellation.check();
      if (finished) throw const ScanCancelled();
      final request = await client.getUrl(uri);
      cancellation.check();
      // No credentials, including query API keys, may escape via a redirect.
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'ReelNest/0.1.0');
      if (authorization != null) {
        request.headers.set(HttpHeaders.authorizationHeader, authorization);
      }
      final response = await request.close();
      cancellation.check();
      if (retryTransient &&
          attempt < 2 &&
          (response.statusCode == 429 ||
              (response.statusCode >= 500 && response.statusCode <= 599))) {
        final delay = retryDelay(
          response.headers.value('retry-after'),
          attempt + 1,
        );
        await response.listen((_) {}).cancel();
        await Future<void>.delayed(delay);
        return perform(attempt + 1);
      }
      if (response.statusCode != 200) {
        if ([401, 403].contains(response.statusCode)) {
          throw const SourceFailure('TMDB 拒绝访问，请检查 API Key 或 Token。');
        }
        if (response.statusCode == 429) {
          throw const SourceFailure('TMDB 请求过于频繁，请稍后重试。');
        }
        throw const SourceFailure('TMDB 请求失败，请稍后重试。');
      }
      if (response.contentLength > maxBytes) {
        throw const SourceFailure('TMDB 响应过大，已停止读取。');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        cancellation.check();
        if (bytes.length + chunk.length > maxBytes) {
          throw const SourceFailure('TMDB 响应过大，已停止读取。');
        }
        bytes.add(chunk);
      }
      cancellation.check();
      return bytes.takeBytes();
    }

    try {
      return await Future.any([perform(), cancelled.future]).timeout(timeout);
    } on ScanCancelled {
      rethrow;
    } on SourceFailure {
      rethrow;
    } on TimeoutException {
      throw const SourceFailure('TMDB 连接超时，请重试。');
    } catch (_) {
      throw const SourceFailure('TMDB 连接或响应异常，请稍后重试。');
    } finally {
      finished = true;
      unlisten();
      client.close(force: true);
    }
  }

  static Duration retryDelay(String? header, int attempt) {
    final parsed = double.tryParse(header ?? '');
    final seconds = parsed != null && parsed.isFinite
        ? parsed
        : attempt.toDouble();
    return Duration(milliseconds: (seconds.clamp(0.5, 4) * 1000).round());
  }

  TmdbCandidate _candidate(
    Map<String, dynamic> j,
    String language, {
    TmdbCandidate? fallback,
    TmdbMediaKind kind = TmdbMediaKind.movie,
  }) {
    final id = j['id'] as int;
    if (id <= 0) throw const SourceFailure('TMDB 电影标识无效。');
    final tv = kind == TmdbMediaKind.tv;
    final title = _text(j[tv ? 'name' : 'title']) ?? fallback?.title ?? '未命名';
    final original =
        _text(j[tv ? 'original_name' : 'original_title']) ??
        fallback?.originalTitle;
    final date =
        _text(j[tv ? 'first_air_date' : 'release_date']) ??
        fallback?.releaseDate;
    final value = (j['vote_average'] as num?)?.toDouble();
    final rating = value != null && value.isFinite && value > 0 && value <= 10
        ? value
        : null;
    final genres = j['genres'] as List?;
    return TmdbCandidate(
      id: id,
      kind: kind,
      title: title,
      provider: 'TMDB[${language.isEmpty ? 'zh-CN' : language}]',
      originalTitle: original != title ? original : fallback?.originalTitle,
      releaseDate: date,
      year:
          (date != null && date.length >= 4
              ? int.tryParse(date.substring(0, 4))
              : null) ??
          fallback?.year,
      overview: _text(j['overview']) ?? fallback?.overview,
      posterUrl: _image(j['poster_path'], 'w500') ?? fallback?.posterUrl,
      backdropUrl: _image(j['backdrop_path'], 'w780') ?? fallback?.backdropUrl,
      rating: rating ?? fallback?.rating,
      genres: List.unmodifiable(
        genres != null && genres.isNotEmpty
            ? [
                for (final raw in genres)
                  if (_text((raw as Map)['name']) case final String name) name,
              ]
            : fallback?.genres ??
                  [
                    for (final id in j['genre_ids'] as List? ?? const [])
                      if ((tv ? _tvGenres : _genres)[id] case final String name)
                        name,
                  ],
      ),
    );
  }

  static String? _tvContentRating(Map<String, dynamic> json) {
    final values =
        (json['content_ratings'] as Map?)?['results'] as List? ?? const [];
    final preferred =
        values.where((v) => (v as Map)['iso_3166_1'] == 'US').firstOrNull ??
        values.firstOrNull;
    return _text((preferred as Map?)?['rating']);
  }

  Future<TmdbSeasonMetadata> season(
    int seriesId,
    int number, {
    required String credential,
    required String language,
    required ScanCancellation cancellation,
  }) => _decode(() async {
    if (seriesId <= 0 || number < 0) throw const SourceFailure('TMDB 季标识无效。');
    final json = await _json(
      'tv/$seriesId/season/$number',
      {'language': language},
      credential,
      cancellation,
      retryTransient: true,
    );
    if (json['season_number'] != number) {
      throw const SourceFailure('TMDB 返回了不一致的季资料。');
    }
    final seen = <int>{};
    final episodes = <TmdbEpisodeMetadata>[];
    for (final raw in json['episodes'] as List? ?? const []) {
      final e = raw as Map;
      final episode = e['episode_number'] as int;
      final id = e['id'] as int;
      if (id <= 0 ||
          episode <= 0 ||
          e['season_number'] != number ||
          !seen.add(episode)) {
        throw const SourceFailure('TMDB 返回了不一致的单集资料。');
      }
      if (e['show_id'] != null && e['show_id'] != seriesId) {
        throw const SourceFailure('TMDB 返回了其他系列的单集资料。');
      }
      final runtime = (e['runtime'] as num?)?.toInt();
      final rating = (e['vote_average'] as num?)?.toDouble();
      episodes.add(
        TmdbEpisodeMetadata(
          id: id,
          seriesId: seriesId,
          seasonNumber: number,
          episodeNumber: episode,
          title: _text(e['name']) ?? '',
          overview: _text(e['overview']),
          airDate: _text(e['air_date']),
          runtimeMinutes: runtime != null && runtime > 0 ? runtime : null,
          rating:
              rating != null && rating.isFinite && rating > 0 && rating <= 10
              ? rating
              : null,
        ),
      );
    }
    return TmdbSeasonMetadata(
      number: number,
      title: _text(json['name']) ?? '第 $number 季',
      overview: _text(json['overview']),
      airDate: _text(json['air_date']),
      posterUrl: _image(json['poster_path'], 'w500'),
      episodes: List.unmodifiable(episodes),
    );
  });

  String? _image(Object? raw, String size) {
    if (raw is! String ||
        !RegExp(
          r'^/[A-Za-z0-9_-]+\.(?:jpg|jpeg|png|webp)$',
          caseSensitive: false,
        ).hasMatch(raw)) {
      return null;
    }
    return imageBase.resolve('$size$raw').toString();
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
  static const _tvGenres = {
    10759: '动作冒险',
    16: '动画',
    35: '喜剧',
    80: '犯罪',
    99: '纪录',
    18: '剧情',
    10751: '家庭',
    10762: '儿童',
    9648: '悬疑',
    10763: '新闻',
    10764: '真人秀',
    10765: '科幻奇幻',
    10766: '肥皂剧',
    10767: '脱口秀',
    10768: '战争政治',
    37: '西部',
  };
  static const _genres = {
    28: '动作',
    12: '冒险',
    16: '动画',
    35: '喜剧',
    80: '犯罪',
    99: '纪录',
    18: '剧情',
    10751: '家庭',
    14: '奇幻',
    36: '历史',
    27: '恐怖',
    10402: '音乐',
    9648: '悬疑',
    10749: '爱情',
    878: '科幻',
    10770: '电视电影',
    53: '惊悚',
    10752: '战争',
    37: '西部',
  };
}
