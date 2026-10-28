import 'tmdb_match_tolerance.dart';
import '../../../domain/automatic_scan_interval.dart';

class TmdbSettings {
  const TmdbSettings({
    this.language = 'zh-CN',
    this.hasCredential = false,
    this.matchTolerance = TmdbMatchTolerance.loose,
    this.automaticMatchInterval = AutomaticScanInterval.disabled,
  });
  final String language;
  final bool hasCredential;
  final TmdbMatchTolerance matchTolerance;
  final AutomaticScanInterval automaticMatchInterval;
}

enum TmdbMediaKind { movie, tv }

/// Token-free values. Artwork URLs are public TMDB image resources.
class TmdbCandidate {
  const TmdbCandidate({
    required this.id,
    required this.title,
    this.kind = TmdbMediaKind.movie,
    this.provider = 'TMDB',
    this.originalTitle,
    this.releaseDate,
    this.year,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
    this.genres = const [],
  });
  final int id;
  final TmdbMediaKind kind;
  String get externalId => 'tmdb:${kind.name}:$id';
  final String title, provider;
  final String? originalTitle, releaseDate, overview, posterUrl, backdropUrl;
  final int? year;
  final double? rating;
  final List<String> genres;
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'provider': provider,
    'originalTitle': originalTitle,
    'releaseDate': releaseDate,
    'year': year,
    'overview': overview,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'rating': rating,
    'genres': genres,
  };
  factory TmdbCandidate.fromJson(Map<String, dynamic> j) => TmdbCandidate(
    id: j['id'] as int,
    kind: TmdbMediaKind.values.byName(j['kind'] as String? ?? 'movie'),
    title: j['title'] as String,
    provider: j['provider'] as String? ?? 'TMDB',
    originalTitle: j['originalTitle'] as String?,
    releaseDate: j['releaseDate'] as String?,
    year: j['year'] as int?,
    overview: j['overview'] as String?,
    posterUrl: j['posterUrl'] as String?,
    backdropUrl: j['backdropUrl'] as String?,
    rating: (j['rating'] as num?)?.toDouble(),
    genres: List.unmodifiable(
      (j['genres'] as List? ?? const []).cast<String>(),
    ),
  );
}

class TmdbPerson {
  const TmdbPerson({
    required this.id,
    required this.name,
    required this.role,
    this.profileUrl,
  });
  final int id;
  final String name, role;
  final String? profileUrl;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'profileUrl': profileUrl,
  };
  factory TmdbPerson.fromJson(Map<String, dynamic> j) => TmdbPerson(
    id: j['id'] as int,
    name: j['name'] as String,
    role: j['role'] as String,
    profileUrl: j['profileUrl'] as String?,
  );
}

class TmdbMetadata {
  const TmdbMetadata({
    required this.candidate,
    this.runtimeMinutes,
    this.genres = const [],
    this.cast = const [],
    this.crew = const [],
    this.imdbId,
    this.contentRating,
    this.productionCompanies = const [],
    this.status,
    this.firstAirDate,
    this.lastAirDate,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.seasons = const [],
  });
  final TmdbCandidate candidate;
  final int? runtimeMinutes;
  final List<String> genres, productionCompanies;
  final List<TmdbPerson> cast, crew;
  final String? imdbId, contentRating;
  final String? status, firstAirDate, lastAirDate;
  final int? numberOfSeasons, numberOfEpisodes;
  final List<TmdbSeasonMetadata> seasons;
  TmdbMetadata withSeasons(List<TmdbSeasonMetadata> value) => TmdbMetadata(
    candidate: candidate,
    runtimeMinutes: runtimeMinutes,
    genres: genres,
    cast: cast,
    crew: crew,
    imdbId: imdbId,
    contentRating: contentRating,
    productionCompanies: productionCompanies,
    status: status,
    firstAirDate: firstAirDate,
    lastAirDate: lastAirDate,
    numberOfSeasons: numberOfSeasons,
    numberOfEpisodes: numberOfEpisodes,
    seasons: List.unmodifiable(value),
  );
  Map<String, Object?> toJson() => {
    'candidate': candidate.toJson(),
    'runtimeMinutes': runtimeMinutes,
    'genres': genres,
    'cast': cast.map((p) => p.toJson()).toList(),
    'crew': crew.map((p) => p.toJson()).toList(),
    'imdbId': imdbId,
    'contentRating': contentRating,
    'productionCompanies': productionCompanies,
    'status': status,
    'firstAirDate': firstAirDate,
    'lastAirDate': lastAirDate,
    'numberOfSeasons': numberOfSeasons,
    'numberOfEpisodes': numberOfEpisodes,
    'seasons': seasons.map((s) => s.toJson()).toList(),
  };
  factory TmdbMetadata.fromJson(Map<String, dynamic> j) => TmdbMetadata(
    candidate: TmdbCandidate.fromJson(
      Map<String, dynamic>.from(j['candidate'] as Map),
    ),
    runtimeMinutes: j['runtimeMinutes'] as int?,
    genres: List.unmodifiable(
      (j['genres'] as List? ?? const []).cast<String>(),
    ),
    cast: List.unmodifiable(
      (j['cast'] as List? ?? const []).map(
        (v) => TmdbPerson.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    crew: List.unmodifiable(
      (j['crew'] as List? ?? const []).map(
        (v) => TmdbPerson.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
    imdbId: j['imdbId'] as String?,
    contentRating: j['contentRating'] as String?,
    status: j['status'] as String?,
    firstAirDate: j['firstAirDate'] as String?,
    lastAirDate: j['lastAirDate'] as String?,
    numberOfSeasons: j['numberOfSeasons'] as int?,
    numberOfEpisodes: j['numberOfEpisodes'] as int?,
    seasons: List.unmodifiable(
      (j['seasons'] as List? ?? const []).map(
        (s) => TmdbSeasonMetadata.fromJson(Map<String, dynamic>.from(s as Map)),
      ),
    ),
    productionCompanies: List.unmodifiable(
      (j['productionCompanies'] as List? ?? const []).cast<String>(),
    ),
  );
}

class TmdbSeasonMetadata {
  const TmdbSeasonMetadata({
    required this.number,
    required this.title,
    this.overview,
    this.airDate,
    this.posterUrl,
    this.episodes = const [],
  });
  final int number;
  final String title;
  final String? overview, airDate, posterUrl;
  final List<TmdbEpisodeMetadata> episodes;
  Map<String, Object?> toJson() => {
    'number': number,
    'title': title,
    'overview': overview,
    'airDate': airDate,
    'posterUrl': posterUrl,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
  factory TmdbSeasonMetadata.fromJson(Map<String, dynamic> j) =>
      TmdbSeasonMetadata(
        number: j['number'] as int,
        title: j['title'] as String,
        overview: j['overview'] as String?,
        airDate: j['airDate'] as String?,
        posterUrl: j['posterUrl'] as String?,
        episodes: List.unmodifiable(
          (j['episodes'] as List? ?? const []).map(
            (e) => TmdbEpisodeMetadata.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          ),
        ),
      );
}

class TmdbEpisodeMetadata {
  const TmdbEpisodeMetadata({
    required this.id,
    required this.seriesId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    this.overview,
    this.airDate,
    this.runtimeMinutes,
    this.rating,
  });
  final int id, seriesId, seasonNumber, episodeNumber;
  final String title;
  final String? overview, airDate;
  final int? runtimeMinutes;
  final double? rating;
  Map<String, Object?> toJson() => {
    'id': id,
    'seriesId': seriesId,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
    'title': title,
    'overview': overview,
    'airDate': airDate,
    'runtimeMinutes': runtimeMinutes,
    'rating': rating,
  };
  factory TmdbEpisodeMetadata.fromJson(Map<String, dynamic> j) =>
      TmdbEpisodeMetadata(
        id: j['id'] as int,
        seriesId: j['seriesId'] as int,
        seasonNumber: j['seasonNumber'] as int,
        episodeNumber: j['episodeNumber'] as int,
        title: j['title'] as String,
        overview: j['overview'] as String?,
        airDate: j['airDate'] as String?,
        runtimeMinutes: j['runtimeMinutes'] as int?,
        rating: (j['rating'] as num?)?.toDouble(),
      );
}

class TmdbApplyResult {
  const TmdbApplyResult({this.warnings = const []});
  final List<String> warnings;
}
