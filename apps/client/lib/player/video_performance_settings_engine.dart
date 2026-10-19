import '../features/playback/domain/video_performance_settings.dart';

abstract interface class VideoPerformanceEngine {
  VideoPerformanceSettings get performanceSettings;
  Future<void> setPerformanceSettings(VideoPerformanceSettings value);
}

class VideoPerformanceRollbackFailure implements Exception {
  const VideoPerformanceRollbackFailure();
}

/// Original LibMpvClient.NetworkMemoryBuffer profiles and hwdec mapping.
/// Only these properties are owned; never rebuild the player, seek or change
/// renderer, tracks, filters or the Emby stream to apply a performance setting.
class MpvPerformanceCommands {
  MpvPerformanceCommands({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;

  static Map<String, String> properties(VideoPerformanceSettings value) => {
    'cache': value.memoryBufferingEnabled ? 'yes' : 'auto',
    'cache-secs': value.memoryBufferingEnabled ? '90' : '20',
    'demuxer-readahead-secs': value.memoryBufferingEnabled ? '90' : '20',
    'demuxer-max-bytes': value.memoryBufferingEnabled ? '256MiB' : '96MiB',
    'demuxer-max-back-bytes': value.memoryBufferingEnabled ? '96MiB' : '24MiB',
    'cache-pause': value.memoryBufferingEnabled ? 'yes' : 'no',
    'hwdec': value.hardwareDecodingMode.mpvValue,
  };

  static double? _number(String value) {
    final multiplier = value.endsWith('MiB') ? 1024 * 1024 : 1;
    final number = double.tryParse(
      multiplier == 1 ? value : value.substring(0, value.length - 3),
    );
    return number?.isFinite == true ? number! * multiplier : null;
  }

  static bool _matches(String actual, String expected) {
    if (actual == expected) return true;
    final a = _number(actual), b = _number(expected);
    return a != null && b != null && (a - b).abs() < .0001;
  }

  Future<Map<String, String>> _snapshot() async => {
    for (final name in properties(const VideoPerformanceSettings()).keys)
      name: await read(name),
  };

  Future<VideoPerformanceSettings> current() async {
    final values = await _snapshot();
    final mode = VideoHardwareDecodingMode.values.firstWhere(
      (m) => m.mpvValue == values['hwdec'],
    );
    for (final enabled in [true, false]) {
      final candidate = VideoPerformanceSettings(
        hardwareDecodingMode: mode,
        memoryBufferingEnabled: enabled,
      );
      if (properties(candidate).entries
          .every((entry) => _matches(values[entry.key]!, entry.value))) {
        return candidate;
      }
    }
    throw StateError('Incomplete native buffering profile');
  }

  Future<void> apply(VideoPerformanceSettings value) async {
    final before = await _snapshot();
    final touched = <String>[];
    try {
      for (final entry in properties(value).entries) {
        if (_matches(before[entry.key]!, entry.value)) continue;
        // Include a rejected write: a command may mutate before returning an
        // error, or succeed while a platform silently clamps the value.
        touched.add(entry.key);
        await command(['set', entry.key, entry.value]);
        if (!_matches(await read(entry.key), entry.value)) {
          throw StateError('Performance setting rejected: ${entry.key}');
        }
      }
    } catch (error, stack) {
      var failed = false;
      for (final name in touched.reversed) {
        try {
          await command(['set', name, before[name]!]);
          if (!_matches(await read(name), before[name]!)) failed = true;
        } catch (_) {
          failed = true;
        }
      }
      if (failed) throw const VideoPerformanceRollbackFailure();
      Error.throwWithStackTrace(error, stack);
    }
  }
}
