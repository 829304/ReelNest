import '../../../domain/media_source.dart';
import '../../sources/domain/emby_library.dart';

enum HomeCollection {
  seriesRecommendations('剧集推荐'),
  continueWatching('继续观看 · 剧集'),
  recentlyPlayed('最近播放'),
  watchlist('想看'),
  favorites('收藏'),
  recentSeries('最近添加 · 剧集'),
  highRated('高分精选');

  const HomeCollection(this.title);
  final String title;
}

class HomeVideo {
  const HomeVideo({
    required this.source,
    required this.entry,
    this.favorite = false,
  });
  final MediaSource source;
  final VideoLibraryEntry entry;
  final bool favorite;
  IndexedMedia get item => entry.item;
  DateTime get recency =>
      entry.record.lastPlayedAt ?? item.updatedAt ?? entry.createdAt;
  double get score {
    final provider = item.remote?.rating ?? 0;
    final user = (entry.userRating ?? 0) * 2;
    return provider > user ? provider : user;
  }
}

class HomeStats {
  const HomeStats({
    this.movies = 0,
    this.series = 0,
    this.episodes = 0,
    this.unwatched = 0,
  });
  final int movies, series, episodes, unwatched;
  HomeStats operator +(HomeStats other) => HomeStats(
    movies: movies + other.movies,
    series: series + other.series,
    episodes: episodes + other.episodes,
    unwatched: unwatched + other.unwatched,
  );
}

class HomeVideoPage {
  const HomeVideoPage(
    this.items, {
    required this.nextOffset,
    required this.hasMore,
  });
  final List<HomeVideo> items;
  final int nextOffset;
  final bool hasMore;
}

abstract final class HomeVideoPolicy {
  static const seriesTypes = {'tvShow', 'anime', 'documentary', 'variety'};
  static bool isSeries(HomeVideo item) =>
      seriesTypes.contains(item.item.displayType) ||
      item.item.type == 'episode';
  static int compare(HomeCollection collection, HomeVideo a, HomeVideo b) {
    final updatedA = a.item.updatedAt ?? a.entry.createdAt;
    final updatedB = b.item.updatedAt ?? b.entry.createdAt;
    final value = switch (collection) {
      HomeCollection.continueWatching =>
        (b.entry.record.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              a.entry.record.lastPlayedAt ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ),
      HomeCollection.recentlyPlayed => b.recency.compareTo(a.recency),
      HomeCollection.watchlist => b.score.compareTo(a.score),
      HomeCollection.favorites => b.recency.compareTo(a.recency),
      HomeCollection.recentSeries => updatedB.compareTo(updatedA),
      HomeCollection.seriesRecommendations ||
      HomeCollection.highRated => b.score.compareTo(a.score),
    };
    if (value != 0) return value;
    if (collection == HomeCollection.watchlist && updatedA != updatedB) {
      return updatedB.compareTo(updatedA);
    }
    if (collection == HomeCollection.favorites && a.score != b.score) {
      return b.score.compareTo(a.score);
    }
    return libraryTitleCompare(a.item.title, b.item.title);
  }

  static List<HomeVideo> merge(
    HomeCollection collection,
    Iterable<HomeVideo> items, {
    int? limit,
  }) {
    var result = {for (final video in items) video.item.identity: video}.values
        .toList();
    result.sort((a, b) => compare(collection, a, b));
    if (collection == HomeCollection.continueWatching && result.any(isSeries)) {
      result = result.where(isSeries).toList();
    }
    return List.unmodifiable(limit == null ? result : result.take(limit));
  }
}
