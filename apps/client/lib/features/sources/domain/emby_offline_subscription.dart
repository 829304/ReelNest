import '../../../domain/media_source.dart';
import 'emby_library.dart';

enum OfflineMode { nextEpisode, nextUnwatched, season, fullSeries }

enum OfflineNetwork {
  allowRemote('允许远程网络'),
  localNetworkOnly('仅本机局域网'),
  wifiOnly('仅 Wi-Fi');

  const OfflineNetwork(this.label);
  final String label;
}

class OfflineSubscription {
  OfflineSubscription({
    required this.id,
    required this.series,
    required String title,
    required this.mode,
    int episodeLimit = 3,
    int? season,
    String? qualityId,
    this.enabled = true,
    this.pausedUntil,
    this.expiresAt,
    this.network = OfflineNetwork.allowRemote,
    required this.createdAt,
    required this.updatedAt,
  }) : title = title.trim().isEmpty ? '未命名系列' : title.trim(),
       episodeLimit = episodeLimit.clamp(1, 99),
       season = season == null || season <= 0 ? null : season.clamp(1, 999),
       qualityId =
           qualityId == null ||
               qualityId.trim().isEmpty ||
               qualityId == 'original'
           ? null
           : qualityId.trim();
  final String id, title;
  final MediaIdentity series;
  final OfflineMode mode;
  final int episodeLimit;
  final int? season;
  final String? qualityId;
  final bool enabled;
  final DateTime? pausedUntil, expiresAt;
  final OfflineNetwork network;
  final DateTime createdAt, updatedAt;
  bool expired(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);
  bool paused(DateTime now) => pausedUntil != null && pausedUntil!.isAfter(now);
  bool runnable(DateTime now) => enabled && !expired(now) && !paused(now);
  String get compact => switch (mode) {
    OfflineMode.nextEpisode => '下一集',
    OfflineMode.nextUnwatched => '未看 $episodeLimit 集',
    OfflineMode.season => season == null ? '整季' : '第 $season 季',
    OfflineMode.fullSeries => '全系列',
  };
  String get label => '自动缓存$compact';
}

/// VideoOfflinePolicy: choose the unwatched window BEFORE excluding existing
/// copies and queued work. Cached episodes still occupy a place in that window.
List<VideoLibraryEntry> offlineCandidates(
  OfflineSubscription rule,
  List<VideoLibraryEntry> episodes, {
  required Set<MediaIdentity> cached,
  required Set<MediaIdentity> queued,
  required bool wifi,
  required String host,
  required double threshold,
}) {
  final candidates =
      episodes
          .where(
            (e) =>
                e.item.type == 'episode' &&
                e.item.remote != null &&
                e.item.parentId == rule.series.localId &&
                e.item.identity.sourceId == rule.series.sourceId,
          )
          .toList()
        ..sort((a, b) {
          var result = (a.item.seasonNumber ?? 0).compareTo(
            b.item.seasonNumber ?? 0,
          );
          if (result == 0) {
            result = (a.item.episodeNumber ?? 0).compareTo(
              b.item.episodeNumber ?? 0,
            );
          }
          return result == 0
              ? libraryTitleCompare(a.item.title, b.item.title)
              : result;
        });
  final limit = threshold.isFinite && threshold > 0 && threshold <= 1
      ? threshold
      : .9;
  final unwatched = candidates.where(
    (e) => !e.record.watched && e.progress < limit,
  );
  final planned = switch (rule.mode) {
    OfflineMode.fullSeries => candidates,
    OfflineMode.nextEpisode => unwatched.take(1),
    OfflineMode.nextUnwatched => unwatched.take(rule.episodeLimit),
    OfflineMode.season => candidates.where(
      (e) => rule.season == null || e.item.seasonNumber == rule.season,
    ),
  };
  final allowed = switch (rule.network) {
    OfflineNetwork.allowRemote => true,
    OfflineNetwork.wifiOnly => wifi,
    OfflineNetwork.localNetworkOnly => isLocalNetworkHost(host),
  };
  if (!allowed) return [];
  return planned
      .where(
        (e) =>
            !cached.contains(e.item.identity) &&
            !queued.contains(e.item.identity),
      )
      .toList();
}

bool isLocalNetworkHost(String value) {
  final host = value.trim().toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  if (host == 'localhost' || host == '::1' || host.endsWith('.local')) {
    return true;
  }
  if (host.startsWith('fe80:') ||
      ((host.startsWith('fc') || host.startsWith('fd')) &&
          host.contains(':'))) {
    return true;
  }
  final parts = host.split('.');
  if (parts.length != 4 || parts.any((p) => !RegExp(r'^\d+$').hasMatch(p))) {
    return false;
  }
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((n) => n == null || n < 0 || n > 255)) return false;
  return octets[0] == 10 ||
      octets[0] == 127 ||
      (octets[0] == 192 && octets[1] == 168) ||
      (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31);
}
