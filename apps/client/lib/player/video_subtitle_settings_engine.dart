import '../features/playback/domain/video_subtitle_settings.dart';

abstract interface class VideoSubtitleSettingsEngine {
  VideoSubtitleStyle get subtitleStyle;
  VideoTimingSettings get timing;
  Future<void> setSubtitleStyle(VideoSubtitleStyle style);
  Future<void> setAudioDelay(double seconds);
  Future<void> setSubtitleScale(double scale);
  Future<void> setSubtitlePosition(double position);
}

/// Property order and values follow the original Swift policies. Commands are
/// argv lists (font names never become shell/script commands).
class MpvSubtitleSettingsCommands {
  MpvSubtitleSettingsCommands({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;

  static Map<String, Object> styleProperties(VideoSubtitleStyle input) {
    final style = input.normalized;
    final alpha = (style.backgroundOpacity * 255)
        .round()
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return {
      'sub-font': style.fontName ?? 'sans-serif',
      'sub-bold': style.bold,
      'sub-color': style.colorPreset.mpvColor,
      'sub-border-size': style.borderSize,
      'sub-back-color': '#${alpha}000000',
    };
  }

  Future<void> applyStyle(VideoSubtitleStyle style) =>
      apply(styleProperties(style));
  Future<void> apply(Map<String, Object> values) async {
    final before = <String, String>{};
    for (final name in values.keys) {
      before[name] = await read(name);
    }
    final touched = <String>[];
    try {
      for (final entry in values.entries) {
        if (_matches(entry.key, before[entry.key]!, entry.value)) continue;
        touched.add(entry.key);
        await command(['set', entry.key, _text(entry.value)]);
        if (!_matches(entry.key, await read(entry.key), entry.value)) {
          throw StateError('Subtitle setting rejected');
        }
      }
    } catch (error, stack) {
      var rollbackFailed = false;
      for (final name in touched.reversed) {
        try {
          await command(['set', name, before[name]!]);
          if (await read(name) != before[name]) rollbackFailed = true;
        } catch (_) {
          rollbackFailed = true;
        }
      }
      if (rollbackFailed) throw const SubtitleSettingsRollbackFailure();
      Error.throwWithStackTrace(error, stack);
    }
  }

  static String _text(Object value) =>
      value is bool ? (value ? 'yes' : 'no') : '$value';
  static bool _matches(String name, String actual, Object value) {
    if (value is num) {
      final number = double.tryParse(actual);
      return number != null &&
          number.isFinite &&
          (number - value).abs() < .0001;
    }
    if (name == 'sub-color' || name == 'sub-back-color') {
      String color(String v) => v.length == 7
          ? '#FF${v.substring(1)}'.toUpperCase()
          : v.toUpperCase();
      return color(actual) == color('$value');
    }
    return actual == _text(value);
  }
}

class SubtitleSettingsRollbackFailure implements Exception {
  const SubtitleSettingsRollbackFailure();
}
