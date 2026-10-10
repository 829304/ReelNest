import 'source_media_type.dart';
import 'remote_media_metadata.dart';
import 'source_options.dart';

enum MediaSourceKind {
  localFolder('本地文件夹'),
  removableDrive('移动硬盘'),
  mountedNas('已挂载 NAS'),
  emby('Emby'),
  jellyfin('Jellyfin'),
  plex('Plex');

  const MediaSourceKind(this.label);
  final String label;
  bool get isFileSource => switch (this) {
    localFolder || removableDrive || mountedNas => true,
    _ => false,
  };
}

class MediaSource {
  const MediaSource({
    required this.id,
    required this.kind,
    required this.name,
    required this.location,
    this.recursive = true,
    this.ignoreHidden = true,
    this.mediaType = SourceMediaType.auto,
    this.minimumFileSize = 50 * 1024 * 1024,
    this.options = const SourceOptions.defaults(),
    required this.createdAt,
    required this.updatedAt,
    this.lastScan,
    this.itemCount = 0,
    this.missingCount = 0,
    this.accessIdentity,
  });

  final String id;
  final MediaSourceKind kind;
  final String name;
  final String location;
  final bool recursive;
  final bool ignoreHidden;
  final SourceMediaType mediaType;
  final int minimumFileSize;
  final SourceOptions options;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastScan;
  final int itemCount;
  final int missingCount;
  final String? accessIdentity;
}

/// A source-scoped identity. A path/remote ID alone is not globally unique.
typedef MediaIdentity = ({String sourceId, String localId});

class IndexedMedia {
  const IndexedMedia({
    required this.identity,
    required this.title,
    required this.type,
    required this.bytes,
    required this.modified,
    this.missing = false,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.seriesDirectory,
    this.isSeries = false,
    this.parentId,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.updatedAt,
    this.remote,
  });

  final MediaIdentity identity;
  final String title;
  final String type;
  final int bytes;
  final DateTime modified;
  final bool missing;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;

  /// Portable paths relative to the source root, so remounts preserve artwork.
  final String? seriesDirectory;
  final bool isSeries;
  final String? parentId;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final DateTime? updatedAt;
  final RemoteMediaMetadata? remote;

  String? get filePath => isSeries ? null : identity.localId;

  String get episodeLabel {
    if (seasonNumber != null && episodeNumber != null) {
      return 'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
    }
    if (episodeNumber != null) {
      return '第 ${episodeNumber.toString().padLeft(2, '0')} 集';
    }
    return '剧集';
  }

  String get cardTitle => type == 'episode' ? '$episodeLabel  $title' : title;
}

class IndexedSeason {
  const IndexedSeason({required this.number, required this.episodeCount});
  final int? number;
  final int episodeCount;
  String get key => number?.toString() ?? 'unspecified';
  String get title => number == null
      ? '未分季'
      : number == 0
      ? '特别篇'
      : '第 $number 季';
}

class IndexedMediaPage {
  const IndexedMediaPage({required this.items, required this.total});
  final List<IndexedMedia> items;
  final int total;
}

class SourceFailure implements Exception {
  const SourceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ScanCancelled implements Exception {
  const ScanCancelled();
}

class ScanCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>{};
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  void Function() listen(void Function() listener) {
    check();
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void check() {
    if (_cancelled) throw const ScanCancelled();
  }
}
