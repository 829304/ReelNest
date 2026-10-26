enum OnlineSubtitleProvider { podnapisi, openSubtitles }

class OnlineSubtitleResult {
  const OnlineSubtitleResult({
    required this.id,
    required this.provider,
    required this.fileId,
    required this.displayName,
    required this.language,
    this.downloads = 0,
  });
  final String id, displayName, language;
  final OnlineSubtitleProvider provider;
  final int fileId, downloads;
  String get sourceName => provider == OnlineSubtitleProvider.podnapisi
      ? 'Podnapisi'
      : 'OpenSubtitles';
}

class OnlineSubtitleSettings {
  const OnlineSubtitleSettings({this.language = 'zh-CN', this.apiKey = ''});
  final String language, apiKey;
  @override
  String toString() => 'OnlineSubtitleSettings(<redacted>)';
}

class OnlineSubtitleQuery {
  const OnlineSubtitleQuery({
    required this.title,
    this.year,
    this.imdbID,
    this.season,
    this.episode,
  });
  final String title;
  final int? year, season, episode;
  final String? imdbID;
}

class OnlineSubtitleSearch {
  const OnlineSubtitleSearch(this.results, this.warnings);
  final List<OnlineSubtitleResult> results;
  final List<String> warnings;
}

class OnlineSubtitleFailure implements Exception {
  const OnlineSubtitleFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
