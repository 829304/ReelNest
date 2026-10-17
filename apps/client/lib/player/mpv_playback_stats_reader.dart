import 'package:media_kit/media_kit.dart';

import 'mpv_node_property.dart';
import 'video_playback_stats.dart';

/// The texture renderer's vo-passes and cache state are native node maps.
Future<VideoPlaybackStats> readMpvPlaybackStats(NativePlayer player) async {
  await player.waitForPlayerInitialization;
  await player.waitForVideoControllerInitializationIfAttached;
  final properties = <String, Object?>{};
  for (final name in const [
    'estimated-vf-fps',
    'decoder-frame-drop-count',
    'frame-drop-count',
    'hwdec-current',
    'vo-passes',
    'demuxer-cache-state',
    'demuxer-cache-duration',
    'avsync',
  ]) {
    final value = readMpvNodeProperty(player, name, omitSamples: true);
    if (name == 'demuxer-cache-state') {
      properties['demuxer-cache-state/fw-bytes'] = value is Map
          ? value['fw-bytes']
          : null;
    } else {
      properties[name] = value;
    }
  }
  return VideoPlaybackStats.fromMpv(properties);
}
