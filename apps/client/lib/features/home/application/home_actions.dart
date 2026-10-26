import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/widgets/app_feedback.dart';

import '../../playback/application/playback_providers.dart';
import '../../playback/application/marker_analysis_providers.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/application/emby_providers.dart';
import '../../library/application/video_preferences_provider.dart';
import '../domain/home_snapshot.dart';
import 'home_providers.dart';

String homeDetailLocation(HomeVideo video) => Uri(
  pathSegments: [
    '',
    'home',
    'media',
    video.item.identity.sourceId,
    base64Url.encode(utf8.encode(video.item.identity.localId)),
  ],
).toString();

Future<void> homeVideoAction(
  BuildContext context,
  WidgetRef ref,
  HomeVideo video,
  String action,
) async {
  try {
    final sources = ref.read(sourceRepositoryProvider);
    final id = video.item.identity;
    await ref.read(homeRepositoryProvider).ensurePublic(id);
    if (!context.mounted) return;
    // Resolve live identity before any side effect; an old card may outlive a
    // source deletion or a successful synchronization.
    final item = await sources.media(id);
    if (!context.mounted) return;
    switch (action) {
      case 'play':
        if (item.isSeries && video.source.kind.isEmbyCompatible) {
          await prepareEmbySeries(ref, [id]);
          if (!context.mounted) return;
        }
        var target = id;
        if (item.isSeries) {
          final threshold = await ref.read(homeThresholdProvider.future);
          if (!context.mounted) return;
          target = await ref
              .read(homeRepositoryProvider)
              .playbackTarget(id, threshold);
        }
        if (context.mounted) {
          await ref.read(playbackLauncherProvider).open(target);
        }
      case 'watchlist':
        await ref
            .read(videoPreferencesRepositoryProvider)
            .setWatchlist(id, !video.entry.watchlist);
      case 'favorite':
        if (video.source.kind.isEmbyCompatible) {
          await ref
              .read(embyConnectionProvider)
              .setFavorite(id, !video.favorite);
        } else {
          await ref
              .read(videoPreferencesRepositoryProvider)
              .setLocalFavorite(id, !video.favorite);
        }
      case 'clear':
        if (video.source.kind.isEmbyCompatible) {
          final failed = await ref
              .read(embyConnectionProvider)
              .markPlayed([id], false, clearHistory: true);
          if (context.mounted && failed > 0) {
            showAppToast(
              context,
              '有 $failed 个条目未能写回远程服务器，本机播放记录已清除，请检查连接和服务器状态。后续同步可能恢复服务器记录。',
              kind: AppFeedbackKind.warning,
            );
          }
        } else {
          await ref.read(playbackRepositoryProvider).clearHistory([id]);
          sources.traceChanged(sourceIds: [id.sourceId]);
        }
        if (context.mounted) ref.invalidate(playbackRecordProvider(id));
      case 'markerAnalysis':
        await ref.read(markerAnalysisProvider).enqueue(item.identity);
    }
    if (context.mounted) ref.invalidate(homeSourceStatsProvider(id.sourceId));
  } catch (error) {
    if (context.mounted) {
      showAppToast(
        context,
        sourceErrorMessage(error),
        kind: AppFeedbackKind.error,
      );
    }
  }
}
