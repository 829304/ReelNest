import '../../../domain/media_source.dart';
import 'nfo_metadata_update.dart';
import 'tmdb_models.dart';

/// AppState.supplementalVideoUpdate: existing descriptive fields win; titles
/// are kept when the localized TMDB identity already matches.
({TmdbMetadata metadata, NfoMetadataUpdate sidecar}) supplementalTmdbMetadata(
  IndexedMedia before,
  TmdbMetadata detail,
  TmdbMetadata? previous,
) {
  final candidate = detail.candidate, old = previous?.candidate;
  final same =
      old?.id == candidate.id &&
      old?.kind == candidate.kind &&
      old?.provider == candidate.provider;
  final keepOverview = before.overview?.trim().isNotEmpty ?? false;
  final genres = previous?.genres.isNotEmpty == true
      ? previous!.genres
      : detail.genres;
  final merged = TmdbMetadata(
    candidate: TmdbCandidate(
      id: candidate.id,
      kind: candidate.kind,
      provider: candidate.provider,
      title: same ? before.title : candidate.title,
      originalTitle: same ? before.originalTitle : candidate.originalTitle,
      year: before.year ?? candidate.year,
      overview: keepOverview ? before.overview : candidate.overview,
      rating: old?.rating ?? candidate.rating,
      releaseDate: candidate.releaseDate,
      posterUrl: candidate.posterUrl,
      backdropUrl: candidate.backdropUrl,
      genres: genres,
    ),
    runtimeMinutes: previous?.runtimeMinutes ?? detail.runtimeMinutes,
    genres: genres,
    cast: previous?.cast.isNotEmpty == true ? previous!.cast : detail.cast,
    crew: previous?.crew.isNotEmpty == true ? previous!.crew : detail.crew,
    imdbId: previous?.imdbId ?? detail.imdbId,
    contentRating: previous?.contentRating ?? detail.contentRating,
    productionCompanies: previous?.productionCompanies.isNotEmpty == true
        ? previous!.productionCompanies
        : detail.productionCompanies,
    status: previous?.status ?? detail.status,
    firstAirDate: previous?.firstAirDate ?? detail.firstAirDate,
    lastAirDate: previous?.lastAirDate ?? detail.lastAirDate,
    numberOfSeasons: previous?.numberOfSeasons ?? detail.numberOfSeasons,
    numberOfEpisodes: previous?.numberOfEpisodes ?? detail.numberOfEpisodes,
    seasons: previous?.seasons ?? const [],
  );
  return (
    metadata: merged,
    sidecar: NfoMetadataUpdate(
      title: same ? null : candidate.title,
      originalTitle: same ? null : candidate.originalTitle,
      year: before.year == null ? candidate.year : null,
      overview: keepOverview ? null : candidate.overview,
      rating: old?.rating == null ? candidate.rating : null,
      genre: previous?.genres.isNotEmpty == true
          ? null
          : (detail.genres.isEmpty ? null : detail.genres.join(' / ')),
      externalId: old?.id == candidate.id ? null : candidate.externalId,
    ),
  );
}
