import '../features/playback/domain/video_display_settings.dart';
import 'mpv_owned_video_filters.dart';

abstract interface class VideoDisplayEngine {
  VideoDisplaySettings get displaySettings;
  Future<void> setDisplaySettings(VideoDisplaySettings value);
}

class VideoDisplayRollbackFailure implements Exception {
  const VideoDisplayRollbackFailure();
}

/// Original mpv properties; flipping owns only named filters so it cannot wipe
/// a quality/scale filter or another video processing stage from the vf chain.
class MpvDisplaySettingsCommands {
  MpvDisplaySettingsCommands({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;
  static const _horizontal = 'reelnest-hflip';
  static const _vertical = 'reelnest-vflip';
  late final _filters = MpvOwnedVideoFilters(command: command, read: read);

  static Map<String, Object> properties(VideoDisplaySettings value) => {
    'video-aspect-override': value.aspectOverride.mpvValue,
    'panscan': value.cropMode.panscan,
    'deinterlace': value.deinterlaceMode.mpvValue,
    'video-rotate': value.rotationMode.degrees,
  };

  Map<String, MpvVideoFilter?> _flipFilters(VideoFlipMode mode) => {
    _horizontal: mode == VideoFlipMode.horizontal || mode == VideoFlipMode.both
        ? const MpvVideoFilter(_horizontal, 'hflip')
        : null,
    _vertical: mode == VideoFlipMode.vertical || mode == VideoFlipMode.both
        ? const MpvVideoFilter(_vertical, 'vflip')
        : null,
  };

  Future<void> apply(VideoDisplaySettings value) async {
    final values = properties(value);
    final before = <String, String>{};
    for (final name in values.keys) {
      before[name] = await read(name);
    }
    final filtersBefore = await _filters.snapshot();
    final touched = <String>[];
    var touchedFilters = false;
    try {
      for (final entry in values.entries) {
        if (_matches(entry.key, before[entry.key]!, entry.value)) continue;
        touched.add(entry.key);
        await command(['set', entry.key, '${entry.value}']);
        final actual = await read(entry.key);
        if (!_matches(entry.key, actual, entry.value)) {
          throw StateError('Video display setting rejected: ${entry.key}');
        }
      }
      touchedFilters = true;
      await _filters.update(_flipFilters(value.flipMode));
    } catch (error, stack) {
      var failed = false;
      if (touchedFilters) {
        try {
          await _filters.restore(filtersBefore);
        } catch (_) {
          failed = true;
        }
      }
      for (final name in touched.reversed) {
        try {
          final previous =
              name == 'video-aspect-override' &&
                  (double.tryParse(before[name]!) ?? 1) <= 0
              ? 'no'
              : before[name]!;
          await command(['set', name, previous]);
          if (!_matches(name, await read(name), previous)) failed = true;
        } catch (_) {
          failed = true;
        }
      }
      if (failed || error is VideoFilterRollbackFailure) {
        throw const VideoDisplayRollbackFailure();
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  bool _matches(String name, String actual, Object expected) {
    double? ratio(String value) {
      final parts = value.split(':');
      if (parts.length == 1) return double.tryParse(value);
      if (parts.length != 2) return null;
      final a = double.tryParse(parts[0]), b = double.tryParse(parts[1]);
      return a == null || b == null || b == 0 ? null : a / b;
    }

    if (name == 'video-aspect-override') {
      if (expected == 'no') {
        // Bundled libmpv also stringifies the symbolic "no" as 0.000000.
        return actual == 'no' || (double.tryParse(actual) ?? 1) <= 0;
      }
      final a = ratio(actual), b = ratio('$expected');
      return a != null && b != null && (a - b).abs() < .0001;
    }
    if (expected is num || name == 'panscan' || name == 'video-rotate') {
      return ((double.tryParse(actual) ?? double.infinity) -
                  (double.tryParse('$expected') ?? double.infinity))
              .abs() <
          .0001;
    }
    return actual == '$expected';
  }
}
