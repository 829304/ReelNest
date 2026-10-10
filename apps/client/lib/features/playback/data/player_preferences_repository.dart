import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../storage/library_database.dart';
import '../domain/video_queue.dart';
import '../domain/playback_options.dart';

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
  Future<String> get subtitleLanguage async =>
      (await _read('global.subtitleLanguage')) ?? 'zh-CN';

  Future<VideoEndAction> get endAction async {
    final value = await _read('global.videoPlaybackEndAction');
    return VideoEndAction.values.where((a) => a.name == value).firstOrNull ??
        VideoEndAction.nextEpisode;
  }

  Future<void> rememberEndAction(VideoEndAction value) =>
      _write('global.videoPlaybackEndAction', value.name);

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
