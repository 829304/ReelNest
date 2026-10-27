import 'dart:convert';
import '../../../domain/media_source.dart';
import '../../../storage/library_database.dart';
import '../../../storage/preference_store.dart';
import '../domain/external_player_settings.dart';

class ExternalPlayerSettingsRepository {
  ExternalPlayerSettingsRepository(this.database);
  final LibraryDatabase database;
  static const key = 'global.externalVideoPlayerSettings';
  Future<ExternalPlayerSettings> load() async {
    final raw = await database.preferenceValue(key);
    if (raw == null) return const ExternalPlayerSettings();
    try {
      if (raw.length > 256 * 1024) throw const FormatException();
      return ExternalPlayerSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const SourceFailure('无法读取外部播放器设置，请重新选择播放器。');
    }
  }

  Future<void> save(ExternalPlayerSettings value) =>
      database.writePreference(key, jsonEncode(value.toJson()));
}
