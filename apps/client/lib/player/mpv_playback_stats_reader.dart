import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'package:media_kit/media_kit.dart';

import 'video_playback_stats.dart';

/// The texture renderer's vo-passes is a native map, not a string property.
/// Read on the owning isolate after initialization, with no await between the
/// disposed check and C calls. All mpv allocations are released on every path.
Future<VideoPlaybackStats> readMpvPlaybackStats(NativePlayer player) async {
  await player.waitForPlayerInitialization;
  await player.waitForVideoControllerInitializationIfAttached;
  if (player.disposed || player.ctx == nullptr) {
    return const VideoPlaybackStats();
  }
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
    final key = name.toNativeUtf8();
    final node = calloc<mpv.mpv_node>();
    try {
      final result = player.mpv.mpv_get_property(
        player.ctx,
        key.cast(),
        mpv.mpv_format.MPV_FORMAT_NODE,
        node.cast(),
      );
      if (result >= 0) {
        final value = _decode(node.ref);
        if (name == 'demuxer-cache-state') {
          // Some bundled mpv versions expose the map but reject its subkeys.
          // Read the native map, keeping only the forward packet byte estimate.
          properties['demuxer-cache-state/fw-bytes'] = value is Map
              ? value['fw-bytes']
              : null;
        } else {
          properties[name] = value;
        }
      }
    } finally {
      player.mpv.mpv_free_node_contents(node);
      calloc.free(node);
      calloc.free(key);
    }
  }
  return VideoPlaybackStats.fromMpv(properties);
}

Object? _decode(mpv.mpv_node node, [int depth = 0]) {
  if (depth > 6) return null;
  switch (node.format) {
    case mpv.mpv_format.MPV_FORMAT_DOUBLE:
      return node.u.double_;
    case mpv.mpv_format.MPV_FORMAT_INT64:
      return node.u.int64;
    case mpv.mpv_format.MPV_FORMAT_STRING:
      return node.u.string == nullptr
          ? null
          : node.u.string.cast<Utf8>().toDartString();
    case mpv.mpv_format.MPV_FORMAT_NODE_ARRAY:
    case mpv.mpv_format.MPV_FORMAT_NODE_MAP:
      if (node.u.list == nullptr) return null;
      final list = node.u.list.ref;
      if (list.num < 0 || list.num > 1024 || list.values == nullptr) {
        return null;
      }
      if (node.format == mpv.mpv_format.MPV_FORMAT_NODE_ARRAY) {
        return [
          for (var i = 0; i < list.num; i++) _decode(list.values[i], depth + 1),
        ];
      }
      if (list.keys == nullptr) return null;
      final result = <String, Object?>{};
      for (var i = 0; i < list.num; i++) {
        if (list.keys[i] == nullptr) continue;
        final key = list.keys[i].cast<Utf8>().toDartString();
        // The raw per-pass sample history is neither displayed nor retained.
        if (key != 'samples') result[key] = _decode(list.values[i], depth + 1);
      }
      return result;
    default:
      return null;
  }
}
