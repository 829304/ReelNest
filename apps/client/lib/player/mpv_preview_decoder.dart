import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;

class MpvPreviewArguments {
  const MpvPreviewArguments({
    required this.library,
    required this.location,
    required this.position,
    required this.ready,
    this.format,
  });
  final String library;
  final String location;
  final Duration position;
  final String? format;
  final SendPort ready;
}

// Keep the Isolate.run closure outside the session/proxy stack. No player,
// credential repository or HTTP socket is accidentally captured and copied.
Future<Uint8List?> decodeMpvPreview(MpvPreviewArguments arguments) =>
    Isolate.run(() => _decode(arguments));

Future<Uint8List?> _decode(MpvPreviewArguments args) async {
  final control = ReceivePort();
  var cancelled = false;
  control.listen((_) {
    cancelled = true;
  });
  args.ready.send(control.sendPort);
  final api = mpv.MPV(DynamicLibrary.open(args.library));
  final context = api.mpv_create();
  if (context == nullptr) {
    control.close();
    return null;
  }
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  int option(String name, String value) {
    final key = name.toNativeUtf8();
    final text = value.toNativeUtf8();
    try {
      return api.mpv_set_option_string(context, key.cast(), text.cast());
    } finally {
      calloc.free(key);
      calloc.free(text);
    }
  }

  int command(List<String> values, {Pointer<mpv.mpv_node>? result}) {
    final array = calloc<Pointer<Int8>>(values.length + 1);
    final strings = values.map((v) => v.toNativeUtf8()).toList();
    try {
      for (var i = 0; i < strings.length; i++) {
        array[i] = strings[i].cast();
      }
      return result == null
          ? api.mpv_command(context, array)
          : api.mpv_command_ret(context, array, result);
    } finally {
      for (final s in strings) {
        calloc.free(s);
      }
      calloc.free(array);
    }
  }

  double? property(String name) {
    final key = name.toNativeUtf8();
    final value = calloc<Double>();
    try {
      return api.mpv_get_property(
                context,
                key.cast(),
                mpv.mpv_format.MPV_FORMAT_DOUBLE,
                value.cast(),
              ) >=
              0
          ? value.value
          : null;
    } finally {
      calloc.free(key);
      calloc.free(value);
    }
  }

  try {
    for (final entry in {
      'vo': 'null',
      'vid': 'auto',
      'aid': 'no',
      'sid': 'no',
      'sub-auto': 'no',
      'pause': 'yes',
      'keep-open': 'yes',
      'force-window': 'no',
      'hwdec': 'no',
      'cache': 'no',
      'cache-on-disk': 'no',
      'network-timeout': '5',
      'demuxer-max-bytes': '2097152',
      'demuxer-max-back-bytes': '0',
      'hr-seek': 'yes',
      'start': '${args.position.inMicroseconds / 1000000}',
      'demuxer-lavf-o': 'protocol_whitelist=%13%file,http,tcp',
      if (args.format != null) 'demuxer-lavf-format': args.format!,
    }.entries) {
      if (option(entry.key, entry.value) < 0) return null;
    }
    if (api.mpv_initialize(context) < 0) return null;
    if (command(['loadfile', args.location]) < 0) return null;
    var restarted = false;
    while (!cancelled && DateTime.now().isBefore(deadline)) {
      // Consume libmpv events on this worker, without any Flutter rendering
      // thread, output pipes, or synchronous wait on the UI isolate.
      final event = api.mpv_wait_event(context, .02);
      if (event.ref.event_id == mpv.mpv_event_id.MPV_EVENT_PLAYBACK_RESTART) {
        restarted = true;
      }
      if (event.ref.event_id == mpv.mpv_event_id.MPV_EVENT_END_FILE) {
        return null;
      }
      final pts = property('time-pos');
      if (restarted &&
          pts != null &&
          (pts - args.position.inMicroseconds / 1000000).abs() <= 1.5) {
        final w = property('video-out-params/w');
        final h = property('video-out-params/h');
        if (w == null ||
            h == null ||
            w < 1 ||
            h < 1 ||
            w * h * 4 > 36 * 1024 * 1024) {
          return null;
        }
        final result = calloc<mpv.mpv_node>();
        try {
          if (command(['screenshot-raw', 'video'], result: result) < 0 ||
              result.ref.format != mpv.mpv_format.MPV_FORMAT_NODE_MAP) {
            return null;
          }
          final map = result.ref.u.list.ref;
          var width = 0, height = 0, stride = 0;
          Pointer<mpv.mpv_byte_array>? pixels;
          for (var i = 0; i < map.num; i++) {
            final key = map.keys[i].cast<Utf8>().toDartString();
            final value = map.values[i];
            if (value.format == mpv.mpv_format.MPV_FORMAT_INT64) {
              if (key == 'w') width = value.u.int64;
              if (key == 'h') height = value.u.int64;
              if (key == 'stride') stride = value.u.int64;
            } else if (key == 'data' &&
                value.format == mpv.mpv_format.MPV_FORMAT_BYTE_ARRAY) {
              pixels = value.u.ba;
            }
          }
          if (width < 1 ||
              height < 1 ||
              width * height * 4 > 36 * 1024 * 1024 ||
              stride < width * 4 ||
              stride > width * 4 + 256 ||
              pixels == null ||
              pixels.ref.size < stride * height ||
              pixels.ref.size > 36 * 1024 * 1024) {
            return null;
          }
          final source = pixels.ref.data.cast<Uint8>().asTypedList(
            pixels.ref.size,
          );
          const outWidth = 312, outHeight = 176;
          final rgba = Uint8List(outWidth * outHeight * 4);
          final scale = (outWidth / width < outHeight / height)
              ? outWidth / width
              : outHeight / height;
          final drawWidth = (width * scale).round().clamp(1, outWidth);
          final drawHeight = (height * scale).round().clamp(1, outHeight);
          final left = (outWidth - drawWidth) ~/ 2;
          final top = (outHeight - drawHeight) ~/ 2;
          var dark = 0;
          for (var y = 0; y < outHeight; y++) {
            for (var x = 0; x < outWidth; x++) {
              final to = (y * outWidth + x) * 4;
              rgba[to + 3] = 255;
              if (x < left ||
                  y < top ||
                  x >= left + drawWidth ||
                  y >= top + drawHeight) {
                continue;
              }
              final sx = ((x - left) / scale).floor().clamp(0, width - 1);
              final sy = ((y - top) / scale).floor().clamp(0, height - 1);
              final from = sy * stride + sx * 4;
              rgba[to] = source[from + 2];
              rgba[to + 1] = source[from + 1];
              rgba[to + 2] = source[from];
              if ((rgba[to] + rgba[to + 1] + rgba[to + 2]) / 3 < 14) dark++;
            }
          }
          return dark / (drawWidth * drawHeight) > .90 ? null : rgba;
        } finally {
          api.mpv_free_node_contents(result);
          calloc.free(result);
        }
      }
      await Future<void>.delayed(
        Duration.zero,
      ); // Deliver cancellation messages.
    }
  } finally {
    control.close();
    api.mpv_terminate_destroy(context);
  }
  return null;
}
