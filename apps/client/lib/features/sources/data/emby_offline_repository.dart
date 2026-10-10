import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../api/emby/emby_quality.dart';
import '../../../domain/media_source.dart';
import '../../../platform/network_status.dart';
import '../../playback/data/player_preferences_repository.dart';
import '../domain/emby_offline_subscription.dart';
import 'emby_cache_repository.dart';
import 'emby_connection_repository.dart';
import 'emby_library_repository.dart';
import 'source_repository.dart';

class OfflineState {
  const OfflineState({this.rules = const [], this.error});
  final List<OfflineSubscription> rules;
  final String? error;
}

/// AppState's subscription maintenance belongs to the main engine only.
/// A queue operation starts a bounded streaming download; maintenance never
/// waits for video bytes and never validates a server just to inspect a rule.
class EmbyOfflineRepository {
  EmbyOfflineRepository({
    required this.sources,
    required this.cache,
    DateTime Function()? now,
    Future<bool> Function()? wifiAvailable,
  }) : now = now ?? DateTime.now,
       wifiAvailable = wifiAvailable ?? desktopWifiAvailable;
  final SourceRepository sources;
  final EmbyCacheRepository cache;
  final DateTime Function() now;
  final Future<bool> Function() wifiAvailable;
  final state = ValueNotifier<OfflineState>(const OfflineState());
  Future<void> _operations = Future.value();
  Future<void>? _disposing;
  StreamSubscription<void>? _changes;
  Timer? _wake, _deadline, _networkTimer;
  bool _started = false, _disposed = false;
  final _plans = <MediaIdentity, String>{};

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _operations.then((_) {
      if (_disposed) throw const SourceFailure('自动缓存已关闭。');
      return action();
    });
    _operations = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> start() {
    if (_disposed || _started) return Future.value();
    _started = true;
    _changes = sources.changes.listen((_) => request());
    // OS probes are only performed when a runnable rule requires Wi-Fi.
    _networkTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (state.value.rules.any(
        (r) => r.runnable(now()) && r.network == OfflineNetwork.wifiOnly,
      )) {
        request();
      }
    });
    return maintain();
  }

  void request({Duration delay = const Duration(milliseconds: 700)}) {
    if (_disposed) return;
    _wake?.cancel();
    _wake = Timer(delay, () => unawaited(maintain()));
  }

  Future<List<OfflineSubscription>> rules() async {
    final rows = await sources.database
        .customSelect(
          'SELECT * FROM video_offline_subscriptions ORDER BY updated_at DESC, title COLLATE NOCASE',
        )
        .get();
    DateTime? date(QueryRow row, String name) {
      final value = row.readNullable<int>(name);
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    return rows
        .map(
          (r) => OfflineSubscription(
            id: r.read<String>('id'),
            series: (
              sourceId: r.read<String>('source_id'),
              localId: r.read<String>('series_id'),
            ),
            title: r.read<String>('title'),
            mode: OfflineMode.values.byName(r.read<String>('mode')),
            episodeLimit: r.read<int>('episode_limit'),
            season: r.readNullable<int>('season'),
            qualityId: r.readNullable<String>('quality_id'),
            enabled: r.read<int>('enabled') == 1,
            pausedUntil: date(r, 'paused_until'),
            expiresAt: date(r, 'expires_at'),
            network: OfflineNetwork.values.byName(r.read<String>('network')),
            createdAt: date(r, 'created_at')!,
            updatedAt: date(r, 'updated_at')!,
          ),
        )
        .toList();
  }

  Future<void> _publish({String? error}) async {
    final current = await rules();
    if (_disposed) return;
    state.value = OfflineState(rules: List.unmodifiable(current), error: error);
    _deadline?.cancel();
    final deadlines =
        current
            .expand((r) => [r.pausedUntil, r.expiresAt])
            .whereType<DateTime>()
            .where((d) => d.isAfter(now()))
            .toList()
          ..sort();
    if (deadlines.isNotEmpty) {
      final duration =
          deadlines.first.difference(now()) + const Duration(milliseconds: 10);
      _deadline = Timer(
        duration > const Duration(days: 1) ? const Duration(days: 1) : duration,
        () => request(delay: Duration.zero),
      );
    }
  }

  Future<OfflineSubscription> save(
    IndexedMedia item,
    OfflineMode mode, {
    int? episodeLimit,
    int? season,
    String? qualityId,
  }) => _serial(() async {
    final source = await sources.source(item.identity.sourceId);
    if (source.kind != MediaSourceKind.emby) {
      throw const SourceFailure('这个系列没有可缓存的远程剧集。');
    }
    final series = item.isSeries
        ? item
        : item.parentId == null
        ? null
        : await sources.media((
            sourceId: item.identity.sourceId,
            localId: item.parentId!,
          ));
    if (series == null || !series.isSeries) {
      throw const SourceFailure('这个系列没有可缓存的远程剧集。');
    }
    final snapshot = await EmbyLibraryRepository(sources).snapshot(source.id);
    final episodes =
        snapshot.entries
            .where(
              (e) =>
                  e.item.parentId == series.identity.localId &&
                  e.item.type == 'episode' &&
                  e.item.remote != null,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a.item.seasonNumber ?? 0).compareTo(
                      b.item.seasonNumber ?? 0,
                    ) ==
                    0
                ? (a.item.episodeNumber ?? 0).compareTo(
                    b.item.episodeNumber ?? 0,
                  )
                : (a.item.seasonNumber ?? 0).compareTo(
                    b.item.seasonNumber ?? 0,
                  ),
          );
    if (episodes.isEmpty) throw const SourceFailure('这个系列没有可缓存的远程剧集。');
    final threshold = await PlayerPreferencesRepository(sources.database)
        .watchedThreshold;
    final existing = (await rules())
        .where((r) => r.series == series.identity)
        .firstOrNull;
    final preferredSeason = item.type == 'episode'
        ? item.seasonNumber
        : (episodes.where((e) => !e.watched(threshold)).firstOrNull ??
                  episodes.first)
              .item
              .seasonNumber;
    final timestamp = now().toUtc();
    final rule = OfflineSubscription(
      id: existing?.id ?? newEmbyIdentity(),
      series: series.identity,
      title: series.title,
      mode: mode,
      episodeLimit: mode == OfflineMode.nextUnwatched
          ? episodeLimit ?? existing?.episodeLimit ?? 3
          : 1,
      season: mode == OfflineMode.season ? season ?? preferredSeason : null,
      qualityId: qualityId,
      network: existing?.network ?? OfflineNetwork.allowRemote,
      expiresAt: existing?.expiresAt?.isAfter(timestamp) == true
          ? existing!.expiresAt
          : null,
      createdAt: existing?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    await _write(rule);
    _plans.remove(rule.series);
    await _publish();
    sources.traceChanged();
    request(delay: const Duration(milliseconds: 80));
    return rule;
  });

  Future<void> _write(OfflineSubscription r) =>
      sources.database.customStatement(
        '''
    INSERT INTO video_offline_subscriptions(
      id,source_id,series_id,title,mode,episode_limit,season,quality_id,enabled,
      paused_until,expires_at,network,created_at,updated_at
    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(source_id,series_id) DO UPDATE SET
      title=excluded.title,mode=excluded.mode,episode_limit=excluded.episode_limit,
      season=excluded.season,quality_id=excluded.quality_id,enabled=excluded.enabled,
      paused_until=excluded.paused_until,expires_at=excluded.expires_at,
      network=excluded.network,updated_at=excluded.updated_at
  ''',
        [
          r.id,
          r.series.sourceId,
          r.series.localId,
          r.title,
          r.mode.name,
          r.episodeLimit,
          r.season,
          r.qualityId,
          r.enabled ? 1 : 0,
          r.pausedUntil?.millisecondsSinceEpoch,
          r.expiresAt?.millisecondsSinceEpoch,
          r.network.name,
          r.createdAt.millisecondsSinceEpoch,
          r.updatedAt.millisecondsSinceEpoch,
        ],
      );

  Future<void> update(
    MediaIdentity series, {
    bool? pause,
    OfflineNetwork? network,
    int? expirationDays,
    bool clearExpiration = false,
  }) => _serial(() async {
    final old = (await rules()).where((r) => r.series == series).firstOrNull;
    if (old == null) return;
    final timestamp = now().toUtc();
    final rule = OfflineSubscription(
      id: old.id,
      series: old.series,
      title: old.title,
      mode: old.mode,
      episodeLimit: old.episodeLimit,
      season: old.season,
      qualityId: old.qualityId,
      enabled: pause == false ? true : old.enabled,
      pausedUntil: pause == null
          ? old.pausedUntil
          : pause
          ? timestamp.add(const Duration(days: 7))
          : null,
      expiresAt: clearExpiration
          ? null
          : expirationDays == null
          ? old.expiresAt
          : timestamp.add(Duration(days: expirationDays.clamp(1, 36500))),
      network: network ?? old.network,
      createdAt: old.createdAt,
      updatedAt: timestamp,
    );
    await _write(rule);
    _plans.remove(series);
    await _publish();
    sources.traceChanged();
    request(delay: const Duration(milliseconds: 80));
  });

  Future<void> stop(MediaIdentity series) => _serial(() async {
    await sources.database.customStatement(
      'DELETE FROM video_offline_subscriptions WHERE source_id=? AND series_id=?',
      [series.sourceId, series.localId],
    );
    _plans.remove(series);
    await _publish();
    sources.traceChanged();
    // Stopping a subscription does not remove completed copies or cancel jobs.
  });

  Future<void> maintain() {
    if (_disposed) return Future.value();
    return _serial(() async {
      try {
        final timestamp = now().toUtc();
        final removed = await sources.database.customUpdate(
          'DELETE FROM video_offline_subscriptions WHERE expires_at IS NOT NULL AND expires_at<=?',
          variables: [Variable(timestamp.millisecondsSinceEpoch)],
        );
        if (removed > 0) sources.traceChanged();
        final current = await rules();
        _plans.removeWhere((id, _) => !current.any((r) => r.series == id));
        if (current.isEmpty) {
          await _publish();
          return;
        }
        final runnable = current.where((r) => r.runnable(timestamp)).toList();
        if (runnable.isEmpty) {
          await _publish();
          return;
        }
        final wifi = runnable.any((r) => r.network == OfflineNetwork.wifiOnly)
            ? await wifiAvailable()
            : false;
        if (_disposed) return;
        final cached = (await cache.entries()).map((c) => c.identity).toSet();
        final queued = cache.tasks.value.values
            .where(
              (t) => [
                VideoCacheTaskState.queued,
                VideoCacheTaskState.downloading,
                VideoCacheTaskState.saving,
                VideoCacheTaskState.paused,
              ].contains(t.state),
            )
            .map((t) => t.item.identity)
            .toSet();
        final threshold = await PlayerPreferencesRepository(sources.database)
            .watchedThreshold;
        final snapshots = <String, EmbyVideoSnapshot>{};
        String? failure;
        for (final rule in runnable) {
          if (_disposed) return;
          try {
            final snapshot = snapshots[rule.series.sourceId] ??=
                await EmbyLibraryRepository(sources)
                    .snapshot(rule.series.sourceId);
            final episodes = snapshot.entries
                .where((e) => e.item.parentId == rule.series.localId)
                .toList();
            // Cache publication also emits source changes. Do not re-download
            // evicted/failed/cancelled copies in an immediate feedback loop;
            // new library, viewing, rule or network state permits a new plan.
            final fingerprint = jsonEncode([
              rule.updatedAt.millisecondsSinceEpoch,
              snapshot.source.lastScan?.millisecondsSinceEpoch,
              threshold,
              rule.network == OfflineNetwork.wifiOnly ? wifi : null,
              for (final e in episodes)
                [
                  e.item.identity.localId,
                  e.record.position.inMilliseconds,
                  e.record.duration.inMilliseconds,
                  e.record.watched,
                ],
            ]);
            if (_plans[rule.series] == fingerprint) continue;
            final candidates = offlineCandidates(
              rule,
              episodes,
              cached: cached,
              queued: queued,
              wifi: wifi,
              host: Uri.parse(snapshot.source.location).host,
              threshold: threshold,
            );
            for (final entry in candidates) {
              if (_disposed) return;
              final item = entry.item;
              final quality =
                  EmbyVideoQuality.options(item)
                      .where((q) => q.id == rule.qualityId)
                      .firstOrNull ??
                  EmbyVideoQuality.source;
              await cache.enqueue(item, quality);
              queued.add(item.identity);
            }
            _plans[rule.series] = fingerprint;
          } catch (_) {
            failure = '部分自动缓存维护失败，请检查媒体源和缓存目录后重试。';
          }
        }
        await _publish(error: failure);
      } catch (_) {
        if (!_disposed) {
          state.value = OfflineState(
            rules: state.value.rules,
            error: '自动缓存维护失败，请检查本地索引或缓存目录后重试。',
          );
        }
      }
    }).onError((Object error, StackTrace stack) {
      // A maintenance operation may still be waiting in the serial queue when
      // the main window closes. Disposal cancels it without an unhandled Future.
      if (!_disposed) Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    _wake?.cancel();
    _deadline?.cancel();
    _networkTimer?.cancel();
    await _changes?.cancel();
    await _operations;
    state.dispose();
  }
}
