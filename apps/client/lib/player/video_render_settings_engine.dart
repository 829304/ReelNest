import '../features/playback/domain/video_render_settings.dart';

abstract interface class VideoRenderEngine {
  VideoRenderSettings get renderSettings;
  Future<void> setRenderSettings(VideoRenderSettings value);
}

class VideoRenderRollbackFailure implements Exception {
  const VideoRenderRollbackFailure();
}

class VideoRenderUnavailable implements Exception {
  const VideoRenderUnavailable();
  static const message = '当前纯软件渲染不支持去色带或 HDR 映射，设置未更改。';
}

/// GPU VO controls from the original policies. Property readback establishes
/// configuration acceptance, not that a software renderer implements a shader.
class MpvRenderSettingsCommands {
  MpvRenderSettingsCommands({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;

  static Map<String, String> properties(VideoRenderSettings value) => {
    'deband': value.debandMode == VideoDebandMode.off ? 'no' : 'yes',
    'deband-threshold': '${value.debandMode.threshold}',
    'deband-range': '${value.debandMode.range}',
    'deband-grain': '${value.debandMode.grain}',
    'tone-mapping': value.toneMappingMode.mpvValue,
  };

  static bool _matches(String actual, String expected) {
    if (actual == expected) return true;
    final a = double.tryParse(actual), b = double.tryParse(expected);
    return a != null &&
        b != null &&
        a.isFinite &&
        b.isFinite &&
        (a - b).abs() < .0001;
  }

  Future<Map<String, String>> _snapshot() async => {
    for (final name in properties(const VideoRenderSettings()).keys)
      name: await read(name),
  };

  Future<VideoRenderSettings> current() async {
    final values = await _snapshot();
    for (final deband in VideoDebandMode.values) {
      for (final tone in VideoToneMappingMode.values) {
        final settings = VideoRenderSettings(
          debandMode: deband,
          toneMappingMode: tone,
        );
        if (properties(settings).entries
            .every((e) => _matches(values[e.key]!, e.value))) {
          return settings;
        }
      }
    }
    throw StateError('Incomplete native render settings');
  }

  Future<void> apply(VideoRenderSettings value) async {
    final before = await _snapshot();
    final touched = <String>[];
    try {
      for (final entry in properties(value).entries) {
        if (_matches(before[entry.key]!, entry.value)) continue;
        touched.add(entry.key);
        await command(['set', entry.key, entry.value]);
        if (!_matches(await read(entry.key), entry.value)) {
          throw StateError('Render setting rejected: ${entry.key}');
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
      if (failed) throw const VideoRenderRollbackFailure();
      Error.throwWithStackTrace(error, stack);
    }
  }
}
