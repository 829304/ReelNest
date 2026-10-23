import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'package:media_kit/media_kit.dart';
// Pinned media_kit 1.2.6 has no public resolved-library-path getter. Use the
// same loaded module as the owning player, as the preview adapter does.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/core/native_library.dart';

import '../features/playback/domain/video_screenshot.dart';

typedef MpvScreenshotPixels = ({
  Uint8List bgra,
  int width,
  int height,
  int stride,
});

/// The engine must retain the native player until this Future settles. Only
/// primitive handle/library/mode values cross the worker boundary; no player,
/// session, authenticated resource URL or extra decoder is transferred.
Future<MpvScreenshotPixels> captureMpvScreenshot(
  NativePlayer player,
  VideoScreenshotMode mode,
) async {
  await player.waitForPlayerInitialization;
  await player.waitForVideoControllerInitializationIfAttached;
  if (player.disposed ||
      player.ctx == nullptr ||
      mode == VideoScreenshotMode.window) {
    throw const VideoScreenshotFailure('当前画面暂不可截图，请稍后重试。');
  }
  final args = (
    address: player.ctx.address,
    library: NativeLibrary.path,
    mode: mode.name,
  );
  return _captureOnWorker(args);
}

Future<MpvScreenshotPixels> _captureOnWorker(
  ({int address, String library, String mode}) args,
) => Isolate.run(() => _capture(args));

MpvScreenshotPixels _capture(
  ({int address, String library, String mode}) args,
) {
  final api = mpv.MPV(DynamicLibrary.open(args.library));
  final context = Pointer<mpv.mpv_handle>.fromAddress(args.address);
  final strings = [
    'screenshot-raw',
    args.mode,
  ].map((s) => s.toNativeUtf8()).toList();
  final command = calloc<Pointer<Int8>>(strings.length + 1);
  final node = calloc<mpv.mpv_node>();
  int property(String name) {
    final key = name.toNativeUtf8();
    final value = calloc<Int64>();
    try {
      return api.mpv_get_property(
                context,
                key.cast(),
                mpv.mpv_format.MPV_FORMAT_INT64,
                value.cast(),
              ) <
              0
          ? 0
          : value.value;
    } finally {
      calloc.free(key);
      calloc.free(value);
    }
  }

  try {
    VideoScreenshotLimits.dimensions(
      property('video-out-params/w'),
      property('video-out-params/h'),
    );
    for (var i = 0; i < strings.length; i++) {
      command[i] = strings[i].cast();
    }
    if (api.mpv_command_ret(context, command, node) < 0 ||
        node.ref.format != mpv.mpv_format.MPV_FORMAT_NODE_MAP ||
        node.ref.u.list == nullptr) {
      throw const VideoScreenshotFailure('当前画面暂不可截图，请稍后重试。');
    }
    final map = node.ref.u.list.ref;
    if (map.num < 1 ||
        map.num > 32 ||
        map.keys == nullptr ||
        map.values == nullptr) {
      throw const VideoScreenshotFailure('截图像素不可用，请重试。');
    }
    var width = 0, height = 0, stride = 0;
    String? format;
    Pointer<mpv.mpv_byte_array>? pixels;
    for (var i = 0; i < map.num; i++) {
      if (map.keys[i] == nullptr) continue;
      final key = map.keys[i].cast<Utf8>().toDartString();
      final value = map.values[i];
      if (value.format == mpv.mpv_format.MPV_FORMAT_INT64) {
        if (key == 'w') width = value.u.int64;
        if (key == 'h') height = value.u.int64;
        if (key == 'stride') stride = value.u.int64;
      } else if (key == 'data' &&
          value.format == mpv.mpv_format.MPV_FORMAT_BYTE_ARRAY) {
        pixels = value.u.ba;
      } else if (key == 'format' &&
          value.format == mpv.mpv_format.MPV_FORMAT_STRING &&
          value.u.string != nullptr) {
        format = value.u.string.cast<Utf8>().toDartString();
      }
    }
    VideoScreenshotLimits.dimensions(width, height);
    if ((format != 'bgr0' && format != 'bgra') ||
        stride < width * 4 ||
        stride > width * 4 + 256 ||
        pixels == null ||
        pixels == nullptr ||
        pixels.ref.data == nullptr ||
        pixels.ref.size < stride * height ||
        pixels.ref.size >
            VideoScreenshotLimits.maxPixels * 4 +
                VideoScreenshotLimits.maxDimension * 256) {
      throw const VideoScreenshotFailure('截图像素不可用，请重试。');
    }
    // Copy before freeing the mpv node, respecting stride. screenshot-raw is
    // BGR0; its unused byte must be opaque rather than interpreted as alpha.
    final result = Uint8List.fromList(
      pixels.ref.data.cast<Uint8>().asTypedList(stride * height),
    );
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        result[y * stride + x * 4 + 3] = 255;
      }
    }
    return (bgra: result, width: width, height: height, stride: stride);
  } finally {
    api.mpv_free_node_contents(node);
    calloc.free(node);
    calloc.free(command);
    for (final text in strings) {
      calloc.free(text);
    }
  }
}
