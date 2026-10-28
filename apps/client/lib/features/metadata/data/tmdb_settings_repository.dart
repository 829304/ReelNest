import '../../../application/async_tasks.dart';
import '../../../domain/media_source.dart';
import '../../../domain/automatic_scan_interval.dart';
import '../../../platform/secure_credential_store.dart';
import '../../../storage/credential_store.dart';
import '../../../storage/library_database.dart';
import '../../../storage/preference_store.dart';
import '../domain/tmdb_models.dart';
import '../domain/tmdb_match_tolerance.dart';

class TmdbSettingsRepository {
  TmdbSettingsRepository(this.database, {CredentialStore? store})
    : store =
          store ??
          SecureCredentialStore(
            key: 'io.github.user829304.reelnest.tmdb.api-key',
          );
  final LibraryDatabase database;
  final CredentialStore store;
  static const automaticIntervalKey = 'global.automaticTMDBMatchInterval';
  static const toleranceKey = 'global.metadataMatchTolerance';
  static const languageKey = 'global.tmdbLanguage';
  final _writes = SerialTaskQueue();
  Future<String> credential() async {
    try {
      return (await store.read() ?? '').trim();
    } catch (_) {
      throw const SourceFailure('无法读取 TMDB 凭据，请重新填写。');
    }
  }

  Future<TmdbSettings> read() async {
    final language = await database.preferenceValue(languageKey);
    return TmdbSettings(
      language: normalizedLanguage(language ?? ''),
      matchTolerance: TmdbMatchTolerance.parse(
        await database.preferenceValue(toleranceKey),
      ),
      automaticMatchInterval: AutomaticScanInterval.parse(
        await database.preferenceValue(automaticIntervalKey),
      ),
      hasCredential: (await credential()).isNotEmpty,
    );
  }

  static String normalizedLanguage(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'zh-CN';
    if (!RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(clean) ||
        clean.length > 32) {
      throw const SourceFailure('TMDB 语言格式不正确，例如 zh-CN 或 en-US。');
    }
    return clean;
  }

  Future<void> saveCredential(String raw) => _writes.run(() async {
    final value = raw.trim();
    if (value.length > 4096 || value.contains(RegExp(r'[^\x21-\x7e]'))) {
      throw const SourceFailure('TMDB API Key 或 Token 格式不正确。');
    }
    try {
      if (value.isEmpty) {
        await store.clear();
      } else {
        await store.write(value);
      }
    } catch (_) {
      throw const SourceFailure('TMDB 凭据保存失败，原配置未更改，请重试。');
    }
  });
  Future<void> setAutomaticMatchInterval(AutomaticScanInterval value) =>
      _writes.run(() async {
        try {
          await database.writePreference(automaticIntervalKey, value.name);
        } catch (_) {
          throw const SourceFailure('自动拉取周期保存失败，请重试。');
        }
      });

  Future<void> setMatchTolerance(TmdbMatchTolerance value) =>
      _writes.run(() async {
        try {
          await database.writePreference(toleranceKey, value.name);
        } catch (_) {
          throw const SourceFailure('影视匹配宽容度保存失败，请重试。');
        }
      });

  Future<void> setLanguage(String raw) => _writes.run(() async {
    final value = normalizedLanguage(raw);
    try {
      await database.writePreference(languageKey, value);
    } catch (_) {
      throw const SourceFailure('TMDB 语言设置保存失败，请重试。');
    }
  });
}
