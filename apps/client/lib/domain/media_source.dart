import 'source_media_type.dart';

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
    this.lastScan,
    this.itemCount = 0,
    this.missingCount = 0,
  });

  final String id;
  final MediaSourceKind kind;
  final String name;
  final String location;
  final bool recursive;
  final bool ignoreHidden;
  final SourceMediaType mediaType;
  final int minimumFileSize;
  final DateTime? lastScan;
  final int itemCount;
  final int missingCount;
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
  });

  final MediaIdentity identity;
  final String title;
  final String type;
  final int bytes;
  final DateTime modified;
  final bool missing;
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
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const ScanCancelled();
  }
}
