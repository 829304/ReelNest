/// MediaLibCore/Models/MediaType.swift. Source classification is distinct from
/// the kind of connection (local directory, Emby, ...).
enum SourceMediaType {
  auto('自动识别'),
  movie('电影'),
  tvShow('电视剧'),
  anime('动漫'),
  documentary('纪录片'),
  variety('综艺'),
  homeVideo('其他视频'),
  music('音乐'),
  other('其他'),
  privateCollection('保险库'),
  episode('剧集'),
  photo('照片');

  const SourceMediaType(this.label);
  final String label;

  String get storageValue => this == privateCollection ? 'private' : name;

  static SourceMediaType fromStorage(String value) =>
      value == 'private' ? privateCollection : values.byName(value);

  /// AppState.addSources overrides the model default for music libraries.
  int get newSourceMinimumFileSize =>
      this == music ? 512 * 1024 : 50 * 1024 * 1024;
}
