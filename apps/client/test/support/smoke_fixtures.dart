import 'package:reelnest/api/mlink/media_codec.dart';
import 'package:reelnest/api/mlink/mlink_client.dart';
import 'package:reelnest/api/mlink/mlink_codec.dart';
import 'package:reelnest/domain/app_failure.dart';
import 'package:reelnest/domain/library_catalog.dart';
import 'package:reelnest/domain/media.dart';
import 'package:reelnest/domain/server_address.dart';
import 'package:reelnest/domain/server_connection.dart';
import 'package:reelnest/storage/credential_store.dart';

const smokeSeriesId = 'series ?#汉';
const smokeToken = 'synthetic-access-token-for-smoke-tests-only';

Map<String, Object?> smokeDescriptor({bool series = true}) => {
  'serverID': 'smoke-server',
  'serverName': '冒烟测试服务器',
  'apiVersion': 'v1',
  'capabilities': [if (series) 'series-detail'],
};

Map<String, Object?> smokeTokens() => {
  'accessToken': smokeToken,
  'refreshToken': 'synthetic-refresh-token-for-smoke-tests-only',
  'tokenType': 'Bearer',
  'sessionID': 'smoke-session',
  'deviceID': 'smoke-device',
  'accessExpiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
  'refreshExpiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(days: 1))
      .toIso8601String(),
};

Map<String, Object?> smokeItem(
  String id,
  String title, {
  bool series = false,
}) => {
  'id': id,
  'title': title,
  'type': series ? 'tvShow' : 'episode',
  'artworkAvailable': false,
  'isSeries': series,
};

final smokeSeasons = [
  {
    'id': 'season-1',
    'seasonNumber': 1,
    'title': '第 1 季',
    'episodeCount': 1,
    'watchedCount': 0,
    'inProgressCount': 1,
  },
  {
    'id': 'season-0',
    'seasonNumber': 0,
    'title': '特别篇',
    'episodeCount': 1,
    'watchedCount': 1,
    'inProgressCount': 0,
  },
  {
    'id': 'unspecified',
    'title': '未分季',
    'episodeCount': 0,
    'watchedCount': 0,
    'inProgressCount': 0,
  },
];

Map<String, Object?> smokeSeries() => {
  ...smokeItem(smokeSeriesId, '测试系列', series: true),
  'genres': ['剧情'],
  'overview': '用于冒烟测试的系列简介。',
  'communityRating': 8.2,
  'totalEpisodeCount': 2,
  'seasons': smokeSeasons,
};

class MemoryCredentialStore implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

// Only the transport boundary is replaced: widgets, routing, repositories,
// session persistence and JSON decoding use production code.
class SmokeMlinkClient extends MlinkClient {
  bool supportsSeries = true;
  bool failNextPage = false;
  int summaryCalls = 0;
  int basicSeriesCalls = 0;
  final offsets = <int>[];
  final selectedSeasons = <String>[];

  @override
  Future<ServerDescriptor> discover(ServerAddress address) async =>
      decodeDescriptor(smokeDescriptor(series: supportsSeries));

  @override
  Future<MlinkTokens> login({
    required ServerAddress address,
    required String username,
    required String password,
    required String deviceName,
    required String platform,
  }) async => MlinkTokens.fromJson(smokeTokens());

  @override
  Future<LibraryCatalog> categories(
    ServerAddress address,
    String accessToken,
  ) async => decodeCatalog({
    'categories': [
      {'id': 'tvShow', 'title': '电视剧', 'itemCount': 2},
    ],
    'videoGroupItemCount': 2,
  }, DateTime.now());

  @override
  Future<MediaPage> browse(
    ServerAddress address,
    String token, {
    required String type,
    required int offset,
    required MediaSort sort,
    int limit = 48,
  }) async {
    offsets.add(offset);
    if (offset > 0 && failNextPage) {
      failNextPage = false;
      throw const AppFailure(FailureKind.network, '模拟追加失败');
    }
    return decodeMediaPage(
      {
        'offset': offset,
        'limit': limit,
        'totalItemCount': 2,
        'hasMore': offset == 0,
        'items': [
          offset == 0
              ? smokeItem(smokeSeriesId, '测试系列', series: true)
              : smokeItem('other-series', '另一个系列', series: true),
        ],
      },
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<MediaDetail> seriesDetail(
    ServerAddress address,
    String token,
    String id,
  ) async {
    if (id != smokeSeriesId) throw AppFailure.invalidResponse;
    summaryCalls++;
    return decodeSeriesDetail(smokeSeries(), id);
  }

  @override
  Future<MediaDetail> detail(
    ServerAddress address,
    String token,
    String id, {
    required bool isSeries,
  }) async {
    if (isSeries) {
      basicSeriesCalls++;
      return decodeMediaDetail(smokeSeries(), id, isSeries: true);
    }
    return decodeMediaDetail(
      {
        ...smokeItem(id, id == 'episode-0' ? '特别篇单集' : '首集'),
        'genres': [],
        'runtimeSeconds': 2400,
        'episodeContext': {
          'seriesID': smokeSeriesId,
          'seriesTitle': '测试系列',
          'seasonNumber': id == 'episode-0' ? 0 : 1,
          'seasons': smokeSeasons,
        },
      },
      id,
      isSeries: false,
    );
  }

  @override
  Future<MediaPage> episodes(
    ServerAddress address,
    String token, {
    required String seriesId,
    required String season,
    required int offset,
    int limit = 48,
  }) async {
    selectedSeasons.add(season);
    return decodeMediaPage(
      {
        'offset': offset,
        'limit': limit,
        'hasMore': false,
        'totalItemCount': season == 'unspecified' ? 0 : 1,
        'items': [
          if (season != 'unspecified')
            {
              ...smokeItem(
                season == '0' ? 'episode-0' : 'episode-1',
                season == '0' ? '特别篇单集' : '首集',
              ),
              'runtimeSeconds': 2400,
              'episodeNumber': 1,
            },
        ],
      },
      offset: offset,
      limit: limit,
      episodes: true,
    );
  }
}
