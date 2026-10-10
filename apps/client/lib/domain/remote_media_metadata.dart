/// Token-free server metadata. Resource URLs are prepared with a live session.
class RemoteMediaMetadata {
  const RemoteMediaMetadata({
    required this.externalId,
    this.libraryId,
    this.libraryName,
    this.durationMs,
    this.positionMs = 0,
    this.watched = false,
    this.favorite = false,
    this.rating,
    this.artist,
    this.album,
    this.genres = const [],
    this.mediaSourceId,
    this.container,
    this.lastPlayedAt,
    this.videoCodec,
    this.audioCodec,
    this.resolution,
    this.bitrate,
  });
  final String externalId;
  final String? libraryId, libraryName, artist, album, mediaSourceId, container;
  final int? durationMs;
  final int positionMs;
  final bool watched, favorite;
  final double? rating;
  final List<String> genres;
  final DateTime? lastPlayedAt;
  final String? videoCodec, audioCodec, resolution;
  final int? bitrate;
  Map<String, dynamic> toJson() => {
    'externalId': externalId,
    'libraryId': libraryId,
    'libraryName': libraryName,
    'durationMs': durationMs,
    'positionMs': positionMs,
    'watched': watched,
    'favorite': favorite,
    'rating': rating,
    'artist': artist,
    'album': album,
    'genres': genres,
    'mediaSourceId': mediaSourceId,
    'container': container,
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'videoCodec': videoCodec,
    'audioCodec': audioCodec,
    'resolution': resolution,
    'bitrate': bitrate,
  };
  factory RemoteMediaMetadata.fromJson(Map<String, dynamic> json) =>
      RemoteMediaMetadata(
        externalId: json['externalId'] as String,
        libraryId: json['libraryId'] as String?,
        libraryName: json['libraryName'] as String?,
        durationMs: json['durationMs'] as int?,
        positionMs: json['positionMs'] as int? ?? 0,
        watched: json['watched'] as bool? ?? false,
        favorite: json['favorite'] as bool? ?? false,
        rating: (json['rating'] as num?)?.toDouble(),
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        genres: (json['genres'] as List?)?.cast<String>() ?? const [],
        mediaSourceId: json['mediaSourceId'] as String?,
        container: json['container'] as String?,
        lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
        videoCodec: json['videoCodec'] as String?,
        audioCodec: json['audioCodec'] as String?,
        resolution: json['resolution'] as String?,
        bitrate: json['bitrate'] as int?,
      );
}
