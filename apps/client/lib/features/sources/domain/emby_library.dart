import 'package:lpinyin/lpinyin.dart';

import '../../../domain/media_source.dart';
import '../../playback/domain/playback_record.dart';

enum EmbyVideoSection {
  videos('全部视频'),
  watchlist('想看'),
  favorites('收藏');

  const EmbyVideoSection(this.label);
  final String label;
}

enum LibraryWatchFilter {
  all('全部'),
  watching('正在观看'),
  unwatched('未观看'),
  watched('已观看'),
  watchlist('想看'),
  favorites('喜欢');

  const LibraryWatchFilter(this.label);
  final String label;
}

enum VideoLibrarySort {
  recentlyUpdated('最近更新'),
  dateAdded('最近添加'),
  title('标题'),
  year('年份'),
  runtime('时长'),
  progress('观看进度'),
  score('评分'),
  rating('评级');

  const VideoLibrarySort(this.label);
  final String label;
}

typedef EmbyVideoDestination = ({
  String sourceId,
  EmbyVideoSection section,
  String? libraryId,
});
String embyVideoLocation(EmbyVideoDestination value) => Uri(
  pathSegments: ['', 'sources', value.sourceId],
  queryParameters: {
    if (value.libraryId != null) 'library': value.libraryId!,
    if (value.libraryId == null && value.section != EmbyVideoSection.videos)
      'section': value.section.name,
  },
).toString();

class VideoLibrarySettings {
  const VideoLibrarySettings({
    this.sort = VideoLibrarySort.recentlyUpdated,
    this.reverse = false,
    this.filter = LibraryWatchFilter.all,
    this.search = '',
    this.genre = '',
    this.cachedOnly = false,
  });
  final VideoLibrarySort sort;
  final LibraryWatchFilter filter;
  final bool reverse;
  final bool cachedOnly;
  final String search, genre;
  VideoLibrarySettings copyWith({
    VideoLibrarySort? sort,
    bool? reverse,
    LibraryWatchFilter? filter,
    String? search,
    String? genre,
    bool? cachedOnly,
  }) => VideoLibrarySettings(
    sort: sort ?? this.sort,
    reverse: reverse ?? this.reverse,
    filter: filter ?? this.filter,
    search: search ?? this.search,
    genre: genre ?? this.genre,
    cachedOnly: cachedOnly ?? this.cachedOnly,
  );
  Map<String, dynamic> toJson() => {
    'sort': sort.name,
    'reverse': reverse,
    'filter': filter.name,
  };
  factory VideoLibrarySettings.fromJson(Map<String, dynamic> value) =>
      VideoLibrarySettings(
        sort:
            VideoLibrarySort.values
                .where((s) => s.name == value['sort'])
                .firstOrNull ??
            VideoLibrarySort.recentlyUpdated,
        filter:
            LibraryWatchFilter.values
                .where((s) => s.name == value['filter'])
                .firstOrNull ??
            LibraryWatchFilter.all,
        reverse: value['reverse'] == true,
      );
}

class VideoLibraryEntry {
  const VideoLibraryEntry({
    required this.item,
    required this.record,
    required this.createdAt,
    this.watchlist = false,
    this.userRating,
    this.searchTerms = const [],
  });
  final IndexedMedia item;
  final PlaybackRecord record;
  final DateTime createdAt;
  final bool watchlist;
  final double? userRating;
  final List<String?> searchTerms;
  double get progress {
    final duration = record.duration.inMilliseconds;
    if (duration <= 0) return 0;
    return (record.position.inMilliseconds / duration).clamp(0, 1);
  }

  bool watched(double threshold) => record.watched || progress >= threshold;
  bool get hasTrace =>
      record.position > Duration.zero || record.lastPlayedAt != null;
}

/// PinyinSearchMatcher's substring/full-pinyin/initial matching. No network or
/// per-keystroke library enumeration. Keep the same bounded source-form cache.
class LibrarySearchMatcher {
  static final _cache = <String, ({String joined, String initials})>{};
  static final _latin = RegExp(r'^[a-z0-9 ]+$');
  static final _words = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  static bool matches(String raw, Iterable<String?> fields) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return true;
    for (final field in fields) {
      if (field == null || field.isEmpty) continue;
      final lower = field.toLowerCase();
      if (lower.contains(query)) return true;
      if (!_latin.hasMatch(query)) continue;
      if (_cache.length >= 40000) _cache.clear();
      final forms = _cache.putIfAbsent(lower, () {
        final converted = lower.replaceAllMapped(
          RegExp(r'[\u3400-\u9fff]+'),
          (m) =>
              ' ${PinyinHelper.getPinyinE(m[0]!, separator: ' ', format: PinyinFormat.WITHOUT_TONE, defPinyin: ' ')} ',
        );
        final words = _words.allMatches(converted).map((m) => m[0]!).toList();
        return (joined: words.join(), initials: words.map((w) => w[0]).join());
      });
      if (forms.joined.contains(query) || forms.initials.contains(query)) {
        return true;
      }
    }
    return false;
  }
}

/// Numeric title segments follow localizedStandardCompare. Locale-specific
/// collation is a platform parity check, not a server sort request.
int libraryTitleCompare(String a, String b) {
  final parts = RegExp(r'\d+|\D+');
  final left = parts.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = parts.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = BigInt.tryParse(left[i]), y = BigInt.tryParse(right[i]);
    final result = x != null && y != null
        ? x.compareTo(y)
        : left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}

List<VideoLibraryEntry> filterVideoLibrary(
  List<VideoLibraryEntry> scoped,
  VideoLibrarySettings settings,
  double threshold,
) {
  final result = scoped.where((e) {
    final matched = switch (settings.filter) {
      LibraryWatchFilter.all => true,
      LibraryWatchFilter.watching => e.hasTrace && !e.watched(threshold),
      LibraryWatchFilter.unwatched => !e.watched(threshold),
      LibraryWatchFilter.watched => e.watched(threshold),
      LibraryWatchFilter.watchlist => e.watchlist,
      LibraryWatchFilter.favorites => e.item.remote?.favorite == true,
    };
    return matched &&
        (settings.genre.isEmpty ||
            (e.item.remote?.genres.contains(settings.genre) ?? false)) &&
        LibrarySearchMatcher.matches(settings.search, e.searchTerms);
  }).toList();
  result.sort((a, b) {
    final primary = switch (settings.sort) {
      VideoLibrarySort.title => libraryTitleCompare(a.item.title, b.item.title),
      VideoLibrarySort.recentlyUpdated =>
        (b.item.updatedAt ?? b.item.modified).compareTo(
          a.item.updatedAt ?? a.item.modified,
        ),
      VideoLibrarySort.dateAdded => b.createdAt.compareTo(a.createdAt),
      VideoLibrarySort.year => (b.item.year ?? 0).compareTo(a.item.year ?? 0),
      VideoLibrarySort.runtime => (b.item.remote?.durationMs ?? 0).compareTo(
        a.item.remote?.durationMs ?? 0,
      ),
      VideoLibrarySort.progress => b.progress.compareTo(a.progress),
      VideoLibrarySort.score => (b.item.remote?.rating ?? 0).compareTo(
        a.item.remote?.rating ?? 0,
      ),
      VideoLibrarySort.rating => (b.userRating ?? 0).compareTo(
        a.userRating ?? 0,
      ),
    };
    if (primary != 0) return settings.reverse ? -primary : primary;
    final title = libraryTitleCompare(a.item.title, b.item.title);
    return title != 0
        ? title
        : a.item.identity.localId.compareTo(b.item.identity.localId);
  });
  return result;
}
