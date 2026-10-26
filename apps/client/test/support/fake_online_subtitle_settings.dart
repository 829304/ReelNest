import 'package:reelnest/features/playback/data/online_subtitle_settings_repository.dart';
import 'package:reelnest/features/playback/domain/online_subtitle.dart';
import 'package:reelnest/storage/credential_store.dart';

/// Keeps unrelated UI tests isolated from the host credential store and disk.
class FakeOnlineSubtitleSettingsRepository
    extends OnlineSubtitleSettingsRepository {
  FakeOnlineSubtitleSettingsRepository(super.preferences)
    : super(store: _MemoryCredentialStore());

  OnlineSubtitleSettings _value = const OnlineSubtitleSettings();

  @override
  Future<OnlineSubtitleSettings> read() => Future.value(_value);

  @override
  Future<void> save({required String language, required String apiKey}) {
    _value = OnlineSubtitleSettings(
      language: language.trim().isEmpty ? 'zh-CN' : language.trim(),
      apiKey: apiKey.trim(),
    );
    return Future.value();
  }
}

class _MemoryCredentialStore implements CredentialStore {
  String? _value;

  @override
  Future<void> clear() async => _value = null;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async => _value = value;
}
