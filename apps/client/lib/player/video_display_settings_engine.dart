import 'dart:convert';

import '../features/playback/domain/video_display_settings.dart';

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

  static Map<String, Object> properties(VideoDisplaySettings value) => {
    'video-aspect-override': value.aspectOverride.mpvValue,
    'panscan': value.cropMode.panscan,
    'deinterlace': value.deinterlaceMode.mpvValue,
    'video-rotate': value.rotationMode.degrees,
  };

  Map<String, String> _ownedFilters(String raw) {
    final list = raw.isEmpty ? const [] : jsonDecode(raw);
    if (list is! List) throw const FormatException('Invalid video filters');
    final result = <String, String>{};
    for (final entry in list.whereType<Map>()) {
      final label = entry['label'];
      if (label == _horizontal || label == _vertical) {
        final name = entry['name'];
        if (name != 'hflip' && name != 'vflip') {
          throw const FormatException('Unexpected owned video filter');
        }
        result[label as String] = name as String;
      }
    }
    return result;
  }

  Map<String, String> _flipFilters(VideoFlipMode mode) => {
    if (mode == VideoFlipMode.horizontal || mode == VideoFlipMode.both)
      _horizontal: 'hflip',
    if (mode == VideoFlipMode.vertical || mode == VideoFlipMode.both)
      _vertical: 'vflip',
  };

  bool _sameFilters(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);

  Future<void> _replaceFilters(Map<String, String> target) async {
    final current = _ownedFilters(await read('vf'));
    if (_sameFilters(current, target)) return;
    for (final label in current.keys) {
      await command(['vf', 'remove', '@$label']);
    }
    for (final entry in target.entries) {
      await command(['vf', 'add', '@${entry.key}:${entry.value}']);
    }
    if (!_sameFilters(_ownedFilters(await read('vf')), target)) {
      throw StateError('Video filter rejected');
    }
  }

  Future<void> apply(VideoDisplaySettings value) async {
    final values = properties(value);
    final before = <String, String>{};
    for (final name in values.keys) {
      before[name] = await read(name);
    }
    final filtersBefore = _ownedFilters(await read('vf'));
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
      await _replaceFilters(_flipFilters(value.flipMode));
    } catch (error, stack) {
      var failed = false;
      if (touchedFilters) {
        try {
          await _replaceFilters(filtersBefore);
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
      if (failed) throw const VideoDisplayRollbackFailure();
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
