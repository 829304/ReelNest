import 'dart:async';

import '../../../storage/credential_store.dart';
import '../../../platform/secure_credential_store.dart';
import '../domain/online_subtitle.dart';
import 'player_preferences_repository.dart';

class OnlineSubtitleSettingsRepository {
  OnlineSubtitleSettingsRepository(this.preferences, {CredentialStore? store})
    : store =
          store ??
          SecureCredentialStore(
            key: 'io.github.user829304.reelnest.opensubtitles.api-key',
          );
  final PlayerPreferencesRepository preferences;
  final CredentialStore store;
  Future<void> _writes = Future.value();

  Future<OnlineSubtitleSettings> read() async => OnlineSubtitleSettings(
    language: await preferences.subtitleLanguage,
    apiKey: await store.read() ?? '',
  );

  Future<void> save({required String language, required String apiKey}) {
    final nextLanguage = language.trim().isEmpty ? 'zh-CN' : language.trim();
    final key = apiKey.trim();
    if (nextLanguage.length > 32 ||
        key.length > 1024 ||
        key.contains(RegExp(r'[^\x20-\x7e]'))) {
      return Future.error(const OnlineSubtitleFailure('字幕语言或 API Key 格式不正确。'));
    }
    final result = _writes.then((_) async {
      final before = await read();
      try {
        if (key.isEmpty) {
          await store.clear();
        } else {
          await store.write(key);
        }
        await preferences.rememberSubtitleLanguage(nextLanguage);
      } catch (_) {
        try {
          if (before.apiKey.isEmpty) {
            await store.clear();
          } else {
            await store.write(before.apiKey);
          }
        } catch (_) {
          throw const OnlineSubtitleFailure('字幕设置未能保存或完整恢复，请重新检查 API Key。');
        }
        throw const OnlineSubtitleFailure('字幕设置保存失败，请重试。');
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
