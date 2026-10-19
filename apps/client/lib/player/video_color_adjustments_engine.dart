import '../features/playback/domain/video_color_adjustments.dart';

abstract interface class VideoColorEngine {
  VideoColorAdjustments get colorAdjustments;
  Future<void> setColorAdjustments(VideoColorAdjustments value);
}

class VideoColorRollbackFailure implements Exception {
  const VideoColorRollbackFailure();
}

/// Original VideoColorAdjustmentPolicy property names/order. Read every value
/// back: a rejected native command must not appear as an applied UI setting.
class MpvColorAdjustmentCommands {
  MpvColorAdjustmentCommands({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;

  Future<VideoColorAdjustments> current() async {
    final values = <String, double>{};
    for (final name in VideoColorAdjustments.neutral.toJson().keys) {
      final value = double.parse(await read(name));
      if (!value.isFinite) throw StateError('Invalid native color value');
      values[name] = value;
    }
    return VideoColorAdjustments.fromJson(values);
  }

  Future<void> apply(VideoColorAdjustments input) async {
    final values = input.toJson();
    final before = <String, String>{};
    for (final name in values.keys) {
      before[name] = await read(name);
    }
    final touched = <String>[];
    try {
      for (final entry in values.entries) {
        if (_matches(before[entry.key]!, entry.value)) continue;
        touched.add(entry.key);
        await command(['set', entry.key, '${entry.value}']);
        if (!_matches(await read(entry.key), entry.value)) {
          throw StateError('Video color setting rejected: ${entry.key}');
        }
      }
    } catch (error, stack) {
      var failed = false;
      for (final name in touched.reversed) {
        try {
          await command(['set', name, before[name]!]);
          final previous = double.tryParse(before[name]!);
          if (previous == null || !_matches(await read(name), previous)) {
            failed = true;
          }
        } catch (_) {
          failed = true;
        }
      }
      if (failed) throw const VideoColorRollbackFailure();
      Error.throwWithStackTrace(error, stack);
    }
  }

  bool _matches(String actual, double expected) {
    final number = double.tryParse(actual);
    return number != null &&
        number.isFinite &&
        (number - expected).abs() < .0001;
  }
}
