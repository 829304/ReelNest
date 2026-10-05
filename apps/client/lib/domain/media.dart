enum MediaSort {
  recentlyUpdated('最近更新'),
  title('标题'),
  year('年份');

  const MediaSort(this.label);
  final String label;
}

const mediaTypes = {
  'movie': '电影',
  'tvShow': '电视剧',
  'anime': '动漫',
  'documentary': '纪录片',
  'variety': '综艺',
  'homeVideo': '其他视频',
  'music': '音乐',
  'other': '其他',
  'episode': '剧集',
  'photo': '照片',
};

class MediaItem {
  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    required this.artworkAvailable,
    this.isSeries = false,
    this.year,
    this.artist,
    this.album,
    this.durationSeconds,
    this.progress = 0,
    this.watched = false,
    this.episodeNumber,
  });

  final String id;
  final String type;
  final String title;
  final bool artworkAvailable;
  final bool isSeries;
  final int? year;
  final String? artist;
  final String? album;
  final double? durationSeconds;
  final double progress;
  final bool watched;
  final int? episodeNumber;

  double get posterRatio => type == 'music' ? 1 : 2 / 3;
}

class MediaPage {
  MediaPage({
    required List<MediaItem> items,
    required this.total,
    required this.offset,
    required this.limit,
    required this.hasMore,
  }) : items = List.unmodifiable(items);

  final List<MediaItem> items;
  final int total;
  final int offset;
  final int limit;
  final bool hasMore;
  int get nextOffset => offset + items.length;
}

class MediaSeason {
  const MediaSeason({
    required this.id,
    required this.title,
    required this.number,
    required this.episodeCount,
    required this.watchedCount,
    required this.inProgressCount,
  });

  final String id;
  final String title;
  final int? number;
  final int episodeCount;
  final int watchedCount;
  final int inProgressCount;
  String get selector => number?.toString() ?? 'unspecified';
}

class SeriesSummary {
  SeriesSummary({
    required this.totalEpisodeCount,
    required List<MediaSeason> seasons,
  }) : seasons = List.unmodifiable(seasons);

  final int totalEpisodeCount;
  final List<MediaSeason> seasons;
}

class EpisodeContext {
  EpisodeContext({
    required this.seriesId,
    required this.seriesTitle,
    required List<MediaSeason> seasons,
    this.currentSeason,
  }) : seasons = List.unmodifiable(seasons);

  final String seriesId;
  final String seriesTitle;
  final List<MediaSeason> seasons;
  final int? currentSeason;
}

class MediaDetail {
  MediaDetail({
    required this.item,
    required List<String> genres,
    this.originalTitle,
    this.overview,
    this.communityRating,
    this.videoCodec,
    this.audioCodec,
    this.resolution,
    this.episodeContext,
    this.seriesSummary,
  }) : genres = List.unmodifiable(genres);

  final MediaItem item;
  final String? originalTitle;
  final String? overview;
  final List<String> genres;
  final double? communityRating;
  final String? videoCodec;
  final String? audioCodec;
  final String? resolution;
  final EpisodeContext? episodeContext;
  final SeriesSummary? seriesSummary;
}
