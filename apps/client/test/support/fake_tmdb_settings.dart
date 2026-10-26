import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';
import 'package:reelnest/storage/credential_store.dart';

/// Keeps unrelated settings/navigation tests away from native credential I/O.
class FakeTmdbSettingsRepository extends TmdbSettingsRepository {
  FakeTmdbSettingsRepository(super.database)
    : super(store: _MemoryCredentialStore());

  String _credential = '';
  String _language = 'zh-CN';

  @override
  Future<TmdbSettings> read() => Future.value(
    TmdbSettings(language: _language, hasCredential: _credential.isNotEmpty),
  );

  @override
  Future<String> credential() => Future.value(_credential);

  @override
  Future<void> saveCredential(String raw) {
    _credential = raw.trim();
    return Future.value();
  }

  @override
  Future<void> setLanguage(String raw) {
    _language = TmdbSettingsRepository.normalizedLanguage(raw);
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
