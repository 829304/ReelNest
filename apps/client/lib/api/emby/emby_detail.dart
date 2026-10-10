import '../../domain/media_source.dart';

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
List<String> _texts(Object? value, {int? limit}) {
  final values = (value is List ? value : const [])
      .map(_text)
      .whereType<String>();
  return List.unmodifiable(limit == null ? values : values.take(limit));
}

int? _positive(Object? value) => value is int && value > 0 ? value : null;

/// Only display fields and image identities survive parsing. Never store the
/// raw server DTO: MediaSources/People can contain authenticated resource URLs.
class EmbyPerson {
  const EmbyPerson({
    required this.key,
    required this.name,
    required this.role,
    required this.category,
    this.imageId,
    this.department,
  });
  final String key, name, role, category;
  final String? imageId, department;
  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'role': role,
    'category': category,
    'imageId': imageId,
    'department': department,
  };
  factory EmbyPerson.fromJson(Map<String, dynamic> json) => EmbyPerson(
    key: json['key'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    category: json['category'] as String,
    imageId: json['imageId'] as String?,
    department: json['department'] as String?,
  );
}

class EmbyTechnicalInfo {
  const EmbyTechnicalInfo({
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.bitrate,
    this.size,
    this.container,
    this.durationMs,
  });
  final String? videoCodec, audioCodec, container;
  final int? width, height, bitrate, size, durationMs;
  String? get resolution =>
      width != null && height != null ? '${width}x$height' : null;
  factory EmbyTechnicalInfo.fromSource(Map source, {int? ticks}) {
    final streams = (source['MediaStreams'] as List? ?? []).whereType<Map>();
    final video =
        streams
            .where((s) => s['Type']?.toString().toLowerCase() == 'video')
            .firstOrNull ??
        const {};
    final audio =
        streams
            .where((s) => s['Type']?.toString().toLowerCase() == 'audio')
            .firstOrNull ??
        const {};
    return EmbyTechnicalInfo(
      videoCodec: _text(video['Codec']),
      audioCodec: _text(audio['Codec']),
      width: _positive(video['Width']),
      height: _positive(video['Height']),
      bitrate:
          _positive(source['Bitrate']) ??
          _positive(video['BitRate']) ??
          _positive(video['Bitrate']),
      size: _positive(source['Size']),
      container: _text(source['Container']),
      durationMs: ticks == null ? null : (ticks ~/ 10000).clamp(0, 1 << 53),
    );
  }
  Map<String, dynamic> toJson() => {
    'videoCodec': videoCodec,
    'audioCodec': audioCodec,
    'width': width,
    'height': height,
    'bitrate': bitrate,
    'size': size,
    'container': container,
    'durationMs': durationMs,
  };
  factory EmbyTechnicalInfo.fromJson(Map<String, dynamic> json) =>
      EmbyTechnicalInfo(
        videoCodec: json['videoCodec'] as String?,
        audioCodec: json['audioCodec'] as String?,
        width: json['width'] as int?,
        height: json['height'] as int?,
        bitrate: json['bitrate'] as int?,
        size: json['size'] as int?,
        container: json['container'] as String?,
        durationMs: json['durationMs'] as int?,
      );
}

class EmbyDetail {
  const EmbyDetail({
    required this.itemId,
    required this.people,
    required this.backdropCount,
    required this.hasPoster,
    required this.technical,
    this.overview,
    this.status,
    this.contentRating,
    this.tmdbId,
    this.imdbId,
    this.tmdbKind = 'movie',
    this.countries = const [],
    this.companies = const [],
    this.genres = const [],
  });
  final String itemId, tmdbKind;
  final String? overview, status, contentRating, tmdbId, imdbId;
  final List<EmbyPerson> people;
  final List<String> countries, companies, genres;
  final int backdropCount;
  final bool hasPoster;
  final EmbyTechnicalInfo technical;
  List<EmbyPerson> get cast =>
      people.where((p) => p.category == 'cast').toList(growable: false);
  List<EmbyPerson> get crew =>
      people.where((p) => p.category == 'crew').toList(growable: false);

  factory EmbyDetail.fromServer(
    Map<String, dynamic> dto,
    String expectedId, {
    String? mediaSourceId,
  }) {
    if (dto['Id'] != expectedId) throw const SourceFailure('Emby 详情条目标识不匹配。');
    for (final field in [
      'People',
      'BackdropImageTags',
      'Studios',
      'ProductionLocations',
      'Genres',
      'MediaSources',
    ]) {
      if (dto[field] != null && dto[field] is! List) {
        throw const SourceFailure('Emby 详情响应无效。');
      }
    }
    for (final field in ['ImageTags', 'ProviderIds']) {
      if (dto[field] != null && dto[field] is! Map) {
        throw const SourceFailure('Emby 详情响应无效。');
      }
    }
    final people = <EmbyPerson>[];
    final seen = <String>{};
    for (final raw
        in (dto['People'] as List? ?? []).take(28).whereType<Map>()) {
      final name = _text(raw['Name']);
      if (name == null) continue;
      final type = _text(raw['Type']) ?? _text(raw['type']);
      final category =
          ['actor', 'gueststar'].contains((type ?? 'Actor').toLowerCase())
          ? 'cast'
          : 'crew';
      final role =
          _text(raw['Role']) ??
          switch (type) {
            'Actor' || 'Composer' || 'GuestStar' || null => '演员',
            'Director' => '导演',
            'Writer' => '编剧',
            'Producer' => '制片',
            _ => type,
          };
      final personId = _text(raw['Id']);
      final key = personId ?? 'name:$name';
      if (!seen.add('$key|$category|$role')) continue;
      people.add(
        EmbyPerson(
          key: key,
          name: name,
          role: role,
          category: category,
          department: type,
          imageId: raw['PrimaryImageTag'] != null ? personId : null,
        ),
      );
    }
    final sources = (dto['MediaSources'] as List? ?? []).whereType<Map>();
    final source =
        sources.where((s) => s['Id'] == mediaSourceId).firstOrNull ??
        sources.firstOrNull ??
        const {};
    final providers = dto['ProviderIds'] as Map? ?? const {};
    final tmdb = _text(providers['Tmdb']) ?? _text(providers['TmdbId']);
    final imdb = _text(providers['Imdb']) ?? _text(providers['IMDB']);
    return EmbyDetail(
      itemId: expectedId,
      people: List.unmodifiable(people),
      backdropCount: (dto['BackdropImageTags'] as List? ?? []).length,
      hasPoster: (dto['ImageTags'] as Map?)?['Primary'] != null,
      technical: EmbyTechnicalInfo.fromSource(
        source,
        ticks: dto['RunTimeTicks'] as int?,
      ),
      overview: _text(dto['Overview']),
      status: _text(dto['Status']),
      contentRating: _text(dto['OfficialRating']),
      countries: _texts(dto['ProductionLocations'], limit: 8),
      companies: List.unmodifiable(
        (dto['Studios'] as List? ?? [])
            .whereType<Map>()
            .map((s) => _text(s['Name']))
            .whereType<String>()
            .take(8),
      ),
      genres: _texts(dto['Genres']),
      tmdbId: tmdb != null && RegExp(r'^\d+$').hasMatch(tmdb) ? tmdb : null,
      imdbId: imdb != null && RegExp(r'^tt\d+$').hasMatch(imdb) ? imdb : null,
      tmdbKind: dto['Type']?.toString().toLowerCase() == 'movie'
          ? 'movie'
          : 'tv',
    );
  }

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'people': people.map((p) => p.toJson()).toList(),
    'backdropCount': backdropCount,
    'hasPoster': hasPoster,
    'technical': technical.toJson(),
    'overview': overview,
    'status': status,
    'contentRating': contentRating,
    'tmdbId': tmdbId,
    'imdbId': imdbId,
    'tmdbKind': tmdbKind,
    'countries': countries,
    'companies': companies,
    'genres': genres,
  };
  factory EmbyDetail.fromJson(Map<String, dynamic> json) => EmbyDetail(
    itemId: json['itemId'] as String,
    people: List.unmodifiable(
      (json['people'] as List).map(
        (p) => EmbyPerson.fromJson(p as Map<String, dynamic>),
      ),
    ),
    backdropCount: json['backdropCount'] as int,
    hasPoster: json['hasPoster'] as bool,
    technical: EmbyTechnicalInfo.fromJson(
      json['technical'] as Map<String, dynamic>,
    ),
    overview: json['overview'] as String?,
    status: json['status'] as String?,
    contentRating: json['contentRating'] as String?,
    tmdbId: json['tmdbId'] as String?,
    imdbId: json['imdbId'] as String?,
    tmdbKind: json['tmdbKind'] as String,
    countries: (json['countries'] as List).cast<String>(),
    companies: (json['companies'] as List).cast<String>(),
    genres: (json['genres'] as List).cast<String>(),
  );
}
