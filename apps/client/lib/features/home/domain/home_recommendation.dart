import 'dart:convert';
import 'dart:math' as math;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../domain/media_source.dart';
import '../../sources/domain/emby_library.dart';
import 'home_snapshot.dart';

/// HomeView.swift / HomeOverviewSnapshotBuilder. No networking or widget state.
class HomeRecommendation {
  const HomeRecommendation({
    this.hero = const [],
    this.series = const [],
    this.highRated = const [],
    this.recentSeries = const [],
    this.theme = const [],
    this.offline = const [],
    this.genre,
  });
  final List<HomeVideo> hero, series, highRated, recentSeries, theme, offline;
  final String? genre;
  String get subtitle => genre == null
      ? '先从库内高分系列和近期偏好里挑一些适合看的。'
      : '根据你的观看和标星偏好，优先挑 $genre 与高分系列。';
}

abstract final class HomeRecommendationPolicy {
  static int daySeed(DateTime date) =>
      DateTime.utc(
        date.year,
        date.month,
        date.day,
      ).difference(DateTime.utc(1, 1, 1)).inDays +
      1;

  /// Explicit UInt64 wrapping; Dart's platform integer/hashCode is not a seed.
  static double dailyValue(String id, int seed, String salt) {
    var hash = BigInt.from(5381);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final rune in '$id-$salt-$seed'.runes) {
      hash = (hash * BigInt.from(33) + BigInt.from(rune)) & mask;
    }
    return (hash % BigInt.from(997)).toInt() / 997;
  }

  static double providerScore(double? rating) =>
      rating == null || !rating.isFinite || rating <= 0
      ? 0
      : rating <= 5
      ? rating * 2
      : math.min(rating, 10);
  static double userScore(double? rating) =>
      rating == null || !rating.isFinite || rating <= 0
      ? 0
      : math.min(rating, 5) * 2;

  static Map<String, String> genres(Iterable<String> values) {
    final result = <String, String>{};
    for (final raw in values.expand((v) => v.split(RegExp('[,，、/|;；]')))) {
      final display = raw.trim();
      final widthFold = String.fromCharCodes(
        display.runes.map(
          (r) => r >= 0xff01 && r <= 0xff5e
              ? r - 0xfee0
              : r == 0x3000
              ? 32
              : r,
        ),
      );
      final key = unorm
          .nfd(widthFold)
          .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
          .toLowerCase();
      if (key.isNotEmpty) result.putIfAbsent(key, () => display);
    }
    return result;
  }

  static HomeRecommendation build(
    Iterable<HomeVideo> videos, {
    required DateTime now,
    double threshold = .9,
    Iterable<HomeVideo> playbackSignals = const [],
    Set<MediaIdentity> offline = const {},
  }) {
    final seed = daySeed(now);
    final nodes = <MediaIdentity, _Video>{};
    for (final v in videos) {
      if (v.item.parentId == null &&
          !{
            'music',
            'episode',
            'photo',
            'private',
            'privateCollection',
          }.contains(v.item.displayType)) {
        nodes[v.item.identity] = _Video(v);
      }
    }
    final visible = nodes.values.toList();
    final profile = _Profile();
    final signals = {...nodes};
    for (final v in playbackSignals) {
      signals.putIfAbsent(v.item.identity, () => _Video(v));
    }
    for (final v in signals.values) {
      final weight = v.signal(now, threshold);
      if (weight <= 0) continue;
      profile.signals.add(v.id);
      profile.types.update(
        v.type,
        (n) => n + weight * (v.series ? 1.1 : .8),
        ifAbsent: () => weight * (v.series ? 1.1 : .8),
      );
      for (final g in v.genres.entries) {
        profile.genres.update(
          g.key,
          (n) => n + weight / v.genres.length,
          ifAbsent: () => weight / v.genres.length,
        );
        profile.names.putIfAbsent(g.key, () => g.value);
      }
    }
    final genreKeys = profile.genres.keys.toList()
      ..sort((a, b) {
        final weight = profile.genres[b]!.compareTo(profile.genres[a]!);
        return weight != 0 ? weight : libraryTitleCompare(a, b);
      });
    final genre = genreKeys.firstOrNull;
    final maxGenre = profile.genres.values.fold(0.0, math.max);
    final maxType = profile.types.values.fold(0.0, math.max);
    double affinity(_Video v) {
      final raw = v.genres.keys.fold(
        0.0,
        (n, g) => n + (profile.genres[g] ?? 0),
      );
      return (maxGenre > 0 ? math.min(raw / maxGenre, 2.4) * 2.1 : 0) +
          (maxType > 0
              ? math.min((profile.types[v.type] ?? 0) / maxType, 1.4) * 1.35
              : 0);
    }

    double daily(_Video v, String salt) => dailyValue(v.seedId, seed, salt);
    double score(_Video v) =>
        math.max(v.provider, v.user) * 1.25 +
        affinity(v) +
        (v.series ? 1.35 : .3) +
        (v.listed ? 1 : 0) +
        (v.favorite ? .4 : 0) +
        (v.progress <= .02 && !v.watched ? .75 : 0) +
        _recency(v.updated, 420, now) * .35 +
        daily(v, 'item') * 1.65 -
        (v.finished(threshold)
            ? 3.8
            : v.progress > .12
            ? 1.2
            : 0) -
        (profile.signals.contains(v.id) && !v.listed ? .7 : 0);
    List<_Video> rank(
      Iterable<_Video> base,
      int limit,
      double Function(_Video) score,
    ) => _rank(base, limit, score, now);
    final preferred = visible
        .where((v) => !v.finished(threshold) || v.listed)
        .toList();
    final recommended = rank(
      preferred.length >= 6 ? preferred : visible,
      12,
      score,
    );
    final recommendedIDs = recommended.map((v) => v.id).toSet();
    final theme = genre == null
        ? <_Video>[]
        : rank(
            visible.where(
              (v) =>
                  !recommendedIDs.contains(v.id) &&
                  v.genres.containsKey(genre) &&
                  v.high &&
                  !v.finished(threshold),
            ),
            12,
            (v) => score(v) + 1.6,
          );
    final themeIDs = theme.map((v) => v.id).toSet();
    final highSeries = rank(
      visible.where(
        (v) =>
            !recommendedIDs.contains(v.id) &&
            !themeIDs.contains(v.id) &&
            v.series &&
            v.high &&
            !v.finished(threshold),
      ),
      12,
      (v) => score(v) + 1.2,
    );
    final excluded = {...recommendedIDs, ...highSeries.map((v) => v.id)};
    final recent = rank(
      visible.where((v) => !excluded.contains(v.id) && v.series),
      24,
      (v) =>
          _recency(v.updated, 120, now) * 2.1 +
          math.max(v.provider, v.user) * .22 +
          affinity(v) * .65 +
          (v.finished(threshold) ? -.65 : .35) +
          daily(v, 'recent-series') * .75,
    );
    final primary = visible
        .where(
          (v) =>
              !excluded.contains(v.id) &&
              !v.series &&
              v.high &&
              !v.finished(threshold),
        )
        .toList();
    final high = rank(
      primary.length >= 6
          ? primary
          : visible.where(
              (v) =>
                  !excluded.contains(v.id) && v.high && !v.finished(threshold),
            ),
      12,
      (v) =>
          v.provider * 1.8 +
          v.user * 1.4 +
          _recency(v.updated, 240, now) * .8 +
          affinity(v) * .45 +
          daily(v, 'recent-high-rated') * 1.75,
    );
    final qualified = visible
        .where((v) => v.provider > 8 || v.user > 8)
        .toList();
    final banner = rank(
      qualified.length >= 3
          ? qualified
          : {...qualified, ...visible.where((v) => v.high)},
      7,
      (v) =>
          v.provider * .42 +
          v.user * .48 +
          affinity(v) * 1.55 +
          (v.video.item.backdropPath?.isNotEmpty == true ? 1.35 : -.45) +
          (v.listed ? .55 : 0) +
          (v.favorite ? .42 : 0) +
          (v.finished(threshold) ? -.92 : 0) +
          _recency(v.updated, 540, now) * .28 +
          daily(v, 'daily-banner') * 3.2,
    );
    // Vivid's getter fallbacks differ from the legacy board's empty content.
    final series = highSeries.isNotEmpty
        ? highSeries
        : recommended.any((v) => v.series)
        ? recommended.where((v) => v.series).toList()
        : (visible.where((v) => v.series).toList()..sort(_updatedOrder))
              .take(24)
              .toList();
    final highFallback =
        visible.where((v) => (v.video.item.remote?.rating ?? 0) >= 8).toList()
          ..sort((a, b) {
            final rating = b.video.item.remote!.rating!.compareTo(
              a.video.item.remote!.rating!,
            );
            return rating != 0 ? rating : _updatedOrder(a, b);
          });
    List<HomeVideo> output(Iterable<_Video> n) =>
        List.unmodifiable(n.map((v) => v.video));
    final fallbackHero = {
      ...qualified,
      ...(high.isNotEmpty
          ? high
          : theme.isNotEmpty
          ? theme
          : highFallback.take(24)),
      ...recommended,
    }.toList();
    if (banner.isEmpty) {
      // The asynchronous board is empty for an unrated library; Vivid still
      // supplies its recommendation fallback, with its original plain sort.
      double bannerScore(_Video v) =>
          v.provider * .42 +
          v.user * .48 +
          affinity(v) * 1.55 +
          (v.video.item.backdropPath?.isNotEmpty == true ? 1.35 : -.45) +
          (v.listed ? .55 : 0) +
          (v.favorite ? .42 : 0) +
          (v.finished(threshold) ? -.92 : 0) +
          _recency(v.updated, 540, now) * .28 +
          daily(v, 'daily-banner') * 3.2;
      fallbackHero.sort((a, b) {
        final value = bannerScore(b).compareTo(bannerScore(a));
        return value != 0
            ? value
            : libraryTitleCompare(a.video.item.title, b.video.item.title);
      });
    }
    return HomeRecommendation(
      hero: output(banner.isEmpty ? fallbackHero.take(7) : banner),
      series: output(series),
      highRated: output(
        high.isNotEmpty
            ? high
            : theme.isNotEmpty
            ? theme
            : highFallback.take(24),
      ),
      recentSeries: output(
        recent.isNotEmpty
            ? recent
            : (visible.where((v) => v.series).toList()..sort(_updatedOrder))
                  .take(24),
      ),
      theme: output(theme),
      offline: output(
        rank(
          visible.where((v) => offline.contains(v.id)),
          12,
          (v) => score(v) + 1.4,
        ),
      ),
      genre: profile.names[genre],
    );
  }

  static int _updatedOrder(_Video a, _Video b) {
    final value = b.updated.compareTo(a.updated);
    return value != 0
        ? value
        : libraryTitleCompare(a.video.item.title, b.video.item.title);
  }
}

class _Profile {
  final genres = <String, double>{}, types = <String, double>{};
  final names = <String, String>{};
  final signals = <MediaIdentity>{};
}

class _Video {
  _Video(this.video)
    : genres = HomeRecommendationPolicy.genres(video.item.remote?.genres ?? []),
      type = video.item.displayType,
      seedId = jsonEncode([
        video.item.identity.sourceId,
        video.item.identity.localId,
      ]),
      provider = HomeRecommendationPolicy.providerScore(
        video.item.remote?.rating,
      ),
      user = HomeRecommendationPolicy.userScore(video.entry.userRating);
  final HomeVideo video;
  final Map<String, String> genres;
  final String type, seedId;
  final double provider, user;
  MediaIdentity get id => video.item.identity;
  bool get series => HomeVideoPolicy.seriesTypes.contains(type);
  bool get listed => video.entry.watchlist;
  bool get favorite => video.favorite;
  bool get watched => video.entry.record.watched;
  double get progress => video.entry.progress;
  DateTime get updated => video.item.updatedAt ?? video.entry.createdAt;
  bool get high => provider >= 7.3 || user >= 8;
  bool finished(double threshold) => watched || progress >= threshold;
  double signal(DateTime now, double threshold) {
    if ({'music', 'private', 'privateCollection'}.contains(type)) return 0;
    var weight = (favorite ? 4.2 : 0.0) + (listed ? 1.4 : 0.0);
    final rating = video.entry.userRating ?? 0;
    if (rating.isFinite) {
      weight += rating >= 4
          ? rating * 1.15
          : rating >= 3
          ? rating * .65
          : 0;
    }
    weight += finished(threshold)
        ? 3
        : progress >= .12
        ? math.min(progress, .95) * 2.4
        : 0;
    if (video.entry.record.lastPlayedAt case final date?) {
      final days = math.max(0, now.difference(date).inMilliseconds / 86400000);
      if (days <= 120) weight += math.max(0, 1.6 - days / 75);
    }
    return weight + (provider >= 8 ? .5 : 0);
  }
}

double _recency(DateTime? date, double horizon, DateTime now) => date == null
    ? 0
    : math.max(
        0,
        1 -
            math.min(
                  math.max(0, now.difference(date).inMilliseconds / 86400000),
                  horizon,
                ) /
                horizon,
      );

List<_Video> _rank(
  Iterable<_Video> candidates,
  int limit,
  double Function(_Video) score,
  DateTime now,
) {
  final remaining = {for (final v in candidates) v.id: v}.values
      .map((v) => (video: v, score: score(v)))
      .toList();
  final selected = <_Video>[];
  final types = <String, int>{},
      genres = <String, int>{},
      sources = <String, int>{};
  double adjusted(({_Video video, double score}) entry) {
    final v = entry.video;
    final penalty = v.genres.keys.fold(
      0.0,
      (n, g) => n + (genres[g] ?? 0) * .28,
    );
    return entry.score -
        (types[v.type] ?? 0) * .42 -
        math.min(penalty, 1.4) -
        (sources[v.video.source.location] ?? 0) * .16 +
        _recency(v.video.entry.record.lastPlayedAt, 7, now) * .04;
  }

  while (remaining.isNotEmpty && selected.length < limit) {
    var best = 0;
    var bestScore = adjusted(remaining[0]);
    for (var n = 1; n < remaining.length; n++) {
      final value = adjusted(remaining[n]);
      if (value > bestScore ||
          (value == bestScore &&
              libraryTitleCompare(
                    remaining[n].video.video.item.title,
                    remaining[best].video.video.item.title,
                  ) <
                  0)) {
        best = n;
        bestScore = value;
      }
    }
    final picked = remaining.removeAt(best).video;
    selected.add(picked);
    types.update(picked.type, (n) => n + 1, ifAbsent: () => 1);
    for (final g in picked.genres.keys) {
      genres.update(g, (n) => n + 1, ifAbsent: () => 1);
    }
    sources.update(
      picked.video.source.location,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  return selected;
}
