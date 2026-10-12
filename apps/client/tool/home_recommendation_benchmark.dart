import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/features/home/domain/home_recommendation.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';

/// Synthetic public top-level candidates only. No real database or network.
/// Run with `fvm dart run tool/home_recommendation_benchmark.dart`.
Future<void> main() async {
  final now = DateTime(2026, 10, 12, 12);
  final sources = [
    for (var n = 0; n < 4; n++)
      MediaSource(
        id: 'source$n',
        kind: MediaSourceKind.emby,
        name: 'fixture$n',
        location: 'emby://fixture/$n',
        createdAt: now,
        updatedAt: now,
      ),
  ];
  final videos = [
    for (var n = 0; n < 10000; n++) _video(n, sources[n % 4], now),
  ];
  var heartbeats = 0;
  final timer = Timer.periodic(
    const Duration(milliseconds: 10),
    (_) => heartbeats++,
  );
  final watch = Stopwatch()..start();
  try {
    final result = await Isolate.run(
      () => HomeRecommendationPolicy.build(videos, now: now),
    );
    watch.stop();
    stdout.writeln(
      jsonEncode({
        'candidates': videos.length,
        'elapsedMs': watch.elapsedMilliseconds,
        'mainIsolateHeartbeats': heartbeats,
        'hero': result.hero.length,
        'series': result.series.length,
        'highRated': result.highRated.length,
        'recentSeries': result.recentSeries.length,
      }),
    );
  } finally {
    timer.cancel();
  }
}

HomeVideo _video(int n, MediaSource source, DateTime now) {
  final id = (sourceId: source.id, localId: 'item$n');
  final date = now.subtract(Duration(days: n % 700));
  return HomeVideo(
    source: source,
    favorite: n % 17 == 0,
    entry: VideoLibraryEntry(
      item: IndexedMedia(
        identity: id,
        title: '影片 $n',
        type: n % 3 == 0 ? 'tvShow' : 'movie',
        bytes: 0,
        modified: date,
        updatedAt: date,
        isSeries: n % 3 == 0,
        remote: RemoteMediaMetadata(
          externalId: id.localId,
          rating: 5 + n % 50 / 10,
          genres: [
            ['剧情', '动作', 'Comedy', '动画'][n % 4],
          ],
        ),
      ),
      record: PlaybackRecord(
        identity: id,
        watched: n % 9 == 0,
        position: Duration(seconds: n % 11 == 0 ? 30 : 0),
        duration: const Duration(seconds: 100),
        lastPlayedAt: n % 11 == 0 ? date : null,
      ),
      createdAt: date,
      watchlist: n % 23 == 0,
      userRating: n % 7 == 0 ? 4 : null,
    ),
  );
}
