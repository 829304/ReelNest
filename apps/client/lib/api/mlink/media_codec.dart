import '../../domain/app_failure.dart';
import '../../domain/media.dart';
import 'mlink_codec.dart';

String mediaIdentifier(Object? value) {
  final id = jsonText(value, 512);
  if (id == '.' || id == '..' || id.contains(RegExp(r'[/\\\x00-\x1f\x7f-\x9f]'))) {
    throw AppFailure.invalidResponse;
  }
  return id;
}

String _title(Object? value) {
  final text = jsonText(value, 2048);
  if (text.trim().isEmpty) throw AppFailure.invalidResponse;
  return text;
}

String? _optionalText(Object? value, int limit) =>
    value == null ? null : jsonText(value, limit, minBytes: 0);

int _integer(Object? value, {int max = 10000000}) {
  if (value is! int || value < 0 || value > max) throw AppFailure.invalidResponse;
  return value;
}

int? _optionalInteger(Object? value, {int max = 10000}) =>
    value == null ? null : _integer(value, max: max);

double? _number(Object? value, double max) {
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 0 || value > max) {
    throw AppFailure.invalidResponse;
  }
  return value.toDouble();
}

bool _boolean(Object? value, {bool? fallback}) {
  if (value == null && fallback != null) return fallback;
  if (value is! bool) throw AppFailure.invalidResponse;
  return value;
}

List<dynamic> _list(Object? value, int max) {
  if (value is! List || value.length > max) throw AppFailure.invalidResponse;
  return value;
}

MediaItem decodeMediaItem(Map<String, dynamic> json, {bool episode = false}) {
  final id = mediaIdentifier(json['id']);
  final type = episode ? 'episode' : jsonText(json['type'], 64);
  if (!mediaTypes.containsKey(type)) throw AppFailure.invalidResponse;
  final state = json['userState'] == null ? null : jsonObject(json['userState']);
  if (state != null && state['itemID'] != id) throw AppFailure.invalidResponse;
  final year = _optionalInteger(json['year'], max: 3000);
  if (year != null && year < 1800) throw AppFailure.invalidResponse;
  return MediaItem(
    id: id, type: type, title: _title(json['title']), year: year,
    artworkAvailable: _boolean(json['artworkAvailable']),
    isSeries: _boolean(json['isSeries'], fallback: false),
    artist: _optionalText(json['artist'], 2048),
    album: _optionalText(json['album'], 2048),
    durationSeconds: _number(json[episode ? 'runtimeSeconds' : 'durationSeconds'], 31536000),
    progress: state == null ? 0 : _number(state['progress'], 1) ?? 0,
    watched: state == null ? false : _boolean(state['isWatched']),
    episodeNumber: _optionalInteger(json['episodeNumber']),
  );
}

MediaPage decodeMediaPage(Map<String, dynamic> json, {
  required int offset, required int limit, bool episodes = false,
}) {
  if (_integer(json['offset'], max: 1000000) != offset ||
      _integer(json['limit'], max: 100) != limit) {
    throw AppFailure.invalidResponse;
  }
  final total = _integer(json['totalItemCount']);
  final ids = <String>{};
  final items = _list(json['items'], limit).map((entry) {
    final item = decodeMediaItem(jsonObject(entry), episode: episodes);
    if (!ids.add(item.id)) throw AppFailure.invalidResponse;
    return item;
  }).toList();
  final hasMore = _boolean(json['hasMore']);
  if ((items.isNotEmpty && offset + items.length > total) ||
      hasMore != (offset + items.length < total) ||
      (hasMore && items.isEmpty)) {
    throw AppFailure.invalidResponse;
  }
  return MediaPage(items: items, total: total, offset: offset,
    limit: limit, hasMore: hasMore);
}

List<MediaSeason> _seasons(Object? value) {
  final ids = <String>{};
  final selectors = <String>{};
  // Season 0, numbered seasons 1..10000, and the unspecified bucket.
  return _list(value, 10002).map((entry) {
    final data = jsonObject(entry);
    final count = _integer(data['episodeCount']);
    final season = MediaSeason(
      id: jsonText(data['id'], 128), title: _title(data['title']),
      number: _optionalInteger(data['seasonNumber']), episodeCount: count,
      watchedCount: _integer(data['watchedCount'], max: count),
      inProgressCount: _integer(data['inProgressCount'], max: count),
    );
    if (!ids.add(season.id) || !selectors.add(season.selector)) {
      throw AppFailure.invalidResponse;
    }
    return season;
  }).toList();
}

MediaDetail decodeSeriesDetail(Map<String, dynamic> json, String id) {
  if (json['id'] != id) throw AppFailure.invalidResponse;
  return MediaDetail(
    item: decodeMediaItem({...json, 'isSeries': true}),
    originalTitle: _optionalText(json['originalTitle'], 2048),
    overview: _optionalText(json['overview'], 32000),
    genres: _list(json['genres'], 128).map((v) => jsonText(v, 512)).toList(),
    communityRating: _number(json['communityRating'], 10),
    seriesSummary: SeriesSummary(
      totalEpisodeCount: _integer(json['totalEpisodeCount']),
      seasons: _seasons(json['seasons']),
    ),
  );
}

MediaDetail decodeMediaDetail(Map<String, dynamic> json, String id, {
  required bool isSeries,
}) {
  if (json['id'] != id) throw AppFailure.invalidResponse;
  final item = decodeMediaItem({
    ...json, 'isSeries': isSeries, 'durationSeconds': json['runtimeSeconds'],
  });
  EpisodeContext? context;
  if (json['episodeContext'] != null) {
    final data = jsonObject(json['episodeContext']);
    context = EpisodeContext(seriesId: mediaIdentifier(data['seriesID']),
      seriesTitle: _title(data['seriesTitle']), seasons: _seasons(data['seasons']),
      currentSeason: _optionalInteger(data['seasonNumber']));
  }
  return MediaDetail(
    item: item,
    originalTitle: _optionalText(json['originalTitle'], 2048),
    overview: _optionalText(json['overview'], 32000),
    genres: _list(json['genres'], 128).map((v) => jsonText(v, 512)).toList(),
    communityRating: _number(json['communityRating'], 10),
    videoCodec: _optionalText(json['videoCodec'], 256),
    audioCodec: _optionalText(json['audioCodec'], 256),
    resolution: _optionalText(json['resolution'], 256),
    episodeContext: context,
  );
}
