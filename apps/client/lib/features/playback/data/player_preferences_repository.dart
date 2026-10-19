import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../storage/library_database.dart';
import '../domain/video_queue.dart';
import '../domain/playback_options.dart';
import '../domain/playback_marker.dart';
import '../domain/video_subtitle_settings.dart';
import '../domain/video_display_settings.dart';
import '../domain/video_color_adjustments.dart';
import '../domain/video_sharpen_mode.dart';
import '../domain/video_performance_settings.dart';
import '../domain/video_render_settings.dart';

/// TrackPreferenceStore's language/off semantics. Source identity is part of
/// the key because this client uses source-relative media IDs.
class PlayerPreferencesRepository {
  PlayerPreferencesRepository(this.database);
  final LibraryDatabase database;
  static const subtitleOff = '__off__';
  String _key(IndexedMedia item, String kind) => jsonEncode([
    item.identity.sourceId,
    item.parentId?.isNotEmpty == true ? item.parentId : item.identity.localId,
    kind,
  ]);
  Future<String?> _read(String key) async =>
      (await database
              .customSelect(
                'SELECT value FROM player_preferences WHERE key = ?',
                variables: [Variable(key)],
              )
              .getSingleOrNull())
          ?.read<String>('value');
  Future<void> _write(String key, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await database.customStatement(
        'DELETE FROM player_preferences WHERE key = ?',
        [key],
      );
    } else {
      await database.customStatement(
        'INSERT INTO player_preferences(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, trimmed],
      );
    }
  }

  Future<String?> audio(IndexedMedia item) => _read(_key(item, 'audio'));
  Future<String?> subtitle(IndexedMedia item) => _read(_key(item, 'sub'));
  Future<void> rememberAudio(IndexedMedia item, String? language) =>
      _write(_key(item, 'audio'), language);
  Future<void> rememberSubtitle(IndexedMedia item, String? language) =>
      _write(_key(item, 'sub'), language);
  Future<double> number(String key, double fallback) async {
    final value = double.tryParse(await _read('global.$key') ?? '');
    return value?.isFinite == true ? value! : fallback;
  }

  Future<void> rememberNumber(String key, double value) =>
      _write('global.$key', value.toString());
  Future<VideoSubtitleStyle> get subtitleStyle async {
    final raw = await _read('global.videoSubtitleStyle');
    if (raw == null) return VideoSubtitleStyle.standard;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic>
          ? VideoSubtitleStyle.fromJson(value)
          : VideoSubtitleStyle.standard;
    } on FormatException {
      return VideoSubtitleStyle.standard;
    } on TypeError {
      return VideoSubtitleStyle.standard;
    }
  }

  Future<void> rememberSubtitleStyle(VideoSubtitleStyle style) => _write(
    'global.videoSubtitleStyle',
    jsonEncode(style.normalized.toJson()),
  );
  Future<VideoTimingSettings> get timing async => VideoTimingSettings(
    audioDelay: await number('videoDefaultAudioDelay', 0),
    subtitleDelay: await number('videoDefaultSubtitleDelay', 0),
    subtitleScale: await number('videoDefaultSubtitleScale', 1),
    subtitlePosition: await number('videoDefaultSubtitlePosition', 100),
  ).normalized;
  Future<String> get subtitleLanguage async =>
      (await _read('global.subtitleLanguage')) ?? 'zh-CN';

  Future<VideoDisplaySettings> get displaySettings async {
    Future<T> mode<T extends Enum>(
      String key,
      List<T> choices,
      T fallback,
    ) async {
      final value = await _read('global.$key');
      return choices.where((choice) => choice.name == value).firstOrNull ??
          fallback;
    }

    return VideoDisplaySettings(
      aspectOverride: await mode(
        'videoAspectOverride',
        VideoAspectOverride.values,
        VideoAspectOverride.source,
      ),
      cropMode: await mode(
        'videoCropMode',
        VideoCropMode.values,
        VideoCropMode.none,
      ),
      deinterlaceMode: await mode(
        'videoDeinterlaceMode',
        VideoDeinterlaceMode.values,
        VideoDeinterlaceMode.off,
      ),
      rotationMode: await mode(
        'videoRotationMode',
        VideoRotationMode.values,
        VideoRotationMode.source,
      ),
      flipMode: await mode(
        'videoFlipMode',
        VideoFlipMode.values,
        VideoFlipMode.none,
      ),
    );
  }

  Future<void> rememberDisplaySettings(VideoDisplaySettings value) =>
      database.transaction(() async {
        await _write('global.videoAspectOverride', value.aspectOverride.name);
        await _write('global.videoCropMode', value.cropMode.name);
        await _write('global.videoDeinterlaceMode', value.deinterlaceMode.name);
        await _write('global.videoRotationMode', value.rotationMode.name);
        await _write('global.videoFlipMode', value.flipMode.name);
      });

  Future<VideoColorAdjustments> get colorAdjustments async {
    final raw = await _read('global.videoColorAdjustments');
    if (raw == null) return VideoColorAdjustments.neutral;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic>
          ? VideoColorAdjustments.fromJson(value)
          : VideoColorAdjustments.neutral;
    } on FormatException {
      return VideoColorAdjustments.neutral;
    } on TypeError {
      return VideoColorAdjustments.neutral;
    }
  }

  Future<void> rememberColorAdjustments(VideoColorAdjustments value) =>
      _write('global.videoColorAdjustments', jsonEncode(value.toJson()));

  Future<VideoSharpenMode> get sharpenMode async {
    final value = await _read('global.videoSharpenMode');
    return VideoSharpenMode.values
            .where((mode) => mode.name == value)
            .firstOrNull ??
        VideoSharpenMode.off;
  }

  Future<void> rememberSharpenMode(VideoSharpenMode mode) =>
      _write('global.videoSharpenMode', mode.name);

  Future<VideoPerformanceSettings> get performanceSettings async {
    final raw = await _read('global.videoPerformanceSettings');
    if (raw == null) return const VideoPerformanceSettings();
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic>
          ? VideoPerformanceSettings.fromJson(value)
          : const VideoPerformanceSettings();
    } on FormatException {
      return const VideoPerformanceSettings();
    }
  }

  Future<void> rememberPerformanceSettings(VideoPerformanceSettings value) =>
      _write('global.videoPerformanceSettings', jsonEncode(value.toJson()));

  Future<VideoRenderSettings> get renderSettings async {
    final raw = await _read('global.videoRenderSettings');
    if (raw == null) return const VideoRenderSettings();
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic>
          ? VideoRenderSettings.fromJson(value)
          : const VideoRenderSettings();
    } on FormatException {
      return const VideoRenderSettings();
    }
  }

  Future<void> rememberRenderSettings(VideoRenderSettings value) =>
      _write('global.videoRenderSettings', jsonEncode(value.toJson()));

  Future<VideoEndAction> get endAction async {
    final value = await _read('global.videoPlaybackEndAction');
    return VideoEndAction.values.where((a) => a.name == value).firstOrNull ??
        VideoEndAction.nextEpisode;
  }

  Future<void> rememberEndAction(VideoEndAction value) =>
      _write('global.videoPlaybackEndAction', value.name);

  Future<bool> get loopCurrentItem async =>
      await _read('global.videoLoopCurrentItem') == 'true';
  Future<void> rememberLoopCurrentItem(bool enabled) =>
      _write('global.videoLoopCurrentItem', '$enabled');

  Future<VideoMarkerSkipBehavior> get markerSkipBehavior async {
    final value = await _read('global.videoMarkerSkipBehavior');
    return VideoMarkerSkipBehavior.values
            .where((behavior) => behavior.name == value)
            .firstOrNull ??
        VideoMarkerSkipBehavior.prompt;
  }

  Future<void> rememberMarkerSkipBehavior(VideoMarkerSkipBehavior behavior) =>
      _write('global.videoMarkerSkipBehavior', behavior.name);

  Future<PlaybackOptions> get options async {
    final raw = await _read('global.playbackOptions');
    final value = raw == null
        ? const PlaybackOptions()
        : PlaybackOptions.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
    return value.copyWith(watchedThreshold: await watchedThreshold);
  }

  Future<double> get watchedThreshold async =>
      (await number('watchedThreshold', .9)).clamp(0, 1);
  Future<void> rememberWatchedThreshold(double value) => rememberNumber(
    'watchedThreshold',
    value.isFinite ? value.clamp(0, 1) : .9,
  );
  Future<void> rememberOptions(PlaybackOptions value) =>
      _write('global.playbackOptions', jsonEncode(value.toJson()));
  Future<double?> rate(IndexedMedia item) async {
    final value = double.tryParse(await _read(_key(item, 'rate')) ?? '');
    return value != null && value.isFinite && value > 0
        ? value.clamp(.5, 3)
        : null;
  }

  Future<void> rememberRate(IndexedMedia item, double rate) => _write(
    _key(item, 'rate'),
    (rate - 1).abs() <= .001 ? null : rate.toString(),
  );
}
