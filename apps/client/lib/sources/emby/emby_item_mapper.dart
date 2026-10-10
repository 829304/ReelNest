import '../../api/emby/emby_client.dart';
import '../../api/emby/emby_item.dart';
import '../../api/emby/emby_detail.dart';
import '../../domain/media_source.dart';
import '../../domain/remote_media_metadata.dart';

/// EmbyService.mediaItem/syntheticSeriesParents; never stores authenticated URLs.
double? _providerRating(Object? value) {
  final rating = (value as num?)?.toDouble();
  return rating != null && rating.isFinite && rating > 0 && rating <= 10
      ? rating
      : null;
}

class EmbyItemMapper {
  const EmbyItemMapper(this.sourceId, this.modified);
  final String sourceId;
  final DateTime modified;
  IndexedMedia? map(EmbyItem dto, EmbyLibrary? library) {
    final type = switch (dto.type) {
      'movie' => 'movie',
      'series' => 'tvShow',
      'episode' => 'episode',
      'audio' => 'music',
      _ => null,
    };
    if (type == null) return null;
    final media = dto.mediaSource, user = dto.userData;
    final duration = dto.integer('RunTimeTicks');
    final technical = EmbyTechnicalInfo.fromSource(media, ticks: duration);
    final position = user['PlaybackPositionTicks'] as int? ?? 0;
    final rating = _providerRating(dto.data['CommunityRating']);
    final parent = dto.type == 'episode'
        ? dto.text('SeriesId') ?? dto.text('ParentId')
        : null;
    return IndexedMedia(
      identity: (sourceId: sourceId, localId: dto.id),
      title: dto.name,
      type: type,
      bytes: media['Size'] as int? ?? 0,
      modified: modified,
      isSeries: dto.type == 'series',
      parentId: parent,
      year: dto.integer('ProductionYear'),
      seasonNumber: dto.integer('ParentIndexNumber'),
      episodeNumber: dto.type == 'episode' ? dto.integer('IndexNumber') : null,
      originalTitle: dto.text('OriginalTitle'),
      overview: dto.text('Overview'),
      posterPath: dto.hasPoster ? dto.id : null,
      backdropPath: dto.hasBackdrop ? dto.id : null,
      remote: RemoteMediaMetadata(
        externalId: dto.id,
        libraryId: library?.id,
        libraryName: library?.name,
        durationMs: duration == null
            ? null
            : (duration ~/ 10000).clamp(0, 1 << 53),
        positionMs: (position ~/ 10000).clamp(0, 1 << 53),
        watched: user['Played'] as bool? ?? false,
        favorite: user['IsFavorite'] as bool? ?? false,
        rating: rating == null || !rating.isFinite ? null : rating.clamp(0, 10),
        artist: (dto.data['Artists'] as List?)?.firstOrNull as String?,
        album: dto.text('Album'),
        genres: List.unmodifiable(
          (dto.data['Genres'] as List?)?.cast<String>() ?? const <String>[],
        ),
        mediaSourceId: media['Id'] as String?,
        videoCodec: technical.videoCodec,
        audioCodec: technical.audioCodec,
        resolution: technical.resolution,
        bitrate: technical.bitrate,
        container: media['Container'] as String?,
        lastPlayedAt: DateTime.tryParse(
          user['LastPlayedDate'] as String? ?? '',
        ),
      ),
    );
  }

  IndexedMedia syntheticSeries(EmbyItem episode, EmbyLibrary? library) {
    final id = episode.text('SeriesId')!;
    return IndexedMedia(
      identity: (sourceId: sourceId, localId: id),
      title: episode.text('SeriesName')!,
      type: 'tvShow',
      bytes: 0,
      modified: modified,
      isSeries: true,
      year: episode.integer('ProductionYear'),
      posterPath: id,
      remote: RemoteMediaMetadata(
        externalId: id,
        libraryId: library?.id,
        libraryName: library?.name,
        rating: _providerRating(episode.data['CommunityRating']),
      ),
    );
  }
}
