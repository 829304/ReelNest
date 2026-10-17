import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'package:media_kit/media_kit.dart';

/// Read after initialization on the owning isolate. No await between the
/// disposed check and C calls; free every native node on exit.
Object? readMpvNodeProperty(
  NativePlayer player,
  String name, {
  bool omitSamples = false,
}) {
  if (player.disposed || player.ctx == nullptr) return null;
  final key = name.toNativeUtf8();
  final node = calloc<mpv.mpv_node>();
  try {
    final status = player.mpv.mpv_get_property(
      player.ctx,
      key.cast(),
      mpv.mpv_format.MPV_FORMAT_NODE,
      node.cast(),
    );
    return status < 0 ? null : _decode(node.ref, omitSamples, 0);
  } finally {
    player.mpv.mpv_free_node_contents(node);
    calloc.free(node);
    calloc.free(key);
  }
}

Object? _decode(mpv.mpv_node node, bool omitSamples, int depth) {
  if (depth > 6) return null;
  switch (node.format) {
    case mpv.mpv_format.MPV_FORMAT_DOUBLE:
      return node.u.double_;
    case mpv.mpv_format.MPV_FORMAT_INT64:
      return node.u.int64;
    case mpv.mpv_format.MPV_FORMAT_FLAG:
      return node.u.flag != 0;
    case mpv.mpv_format.MPV_FORMAT_STRING:
      return node.u.string == nullptr
          ? null
          : node.u.string.cast<Utf8>().toDartString();
    case mpv.mpv_format.MPV_FORMAT_NODE_ARRAY:
    case mpv.mpv_format.MPV_FORMAT_NODE_MAP:
      if (node.u.list == nullptr) return null;
      final list = node.u.list.ref;
      if (list.num < 0 || list.num > 1024) return null;
      if (node.format == mpv.mpv_format.MPV_FORMAT_NODE_ARRAY) {
        if (list.num > 0 && list.values == nullptr) return null;
        return [
          for (var i = 0; i < list.num; i++)
            _decode(list.values[i], omitSamples, depth + 1),
        ];
      }
      if (list.num > 0 && (list.keys == nullptr || list.values == nullptr)) {
        return null;
      }
      final result = <String, Object?>{};
      for (var i = 0; i < list.num; i++) {
        if (list.keys[i] == nullptr) continue;
        final key = list.keys[i].cast<Utf8>().toDartString();
        if (!omitSamples || key != 'samples') {
          result[key] = _decode(list.values[i], omitSamples, depth + 1);
        }
      }
      return result;
    default:
      return null;
  }
}
