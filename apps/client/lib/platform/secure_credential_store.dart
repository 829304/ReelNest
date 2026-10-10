import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/app_failure.dart';
import '../storage/credential_store.dart';

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage, this.key = _defaultKey})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // No Keychain sharing or app group is needed by the macOS client.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;
  static const _defaultKey = 'io.github.user829304.reelnest.mlink.session.v1';
  final String key;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      throw AppFailure.storage;
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(key: key, value: value);
      if (await _storage.read(key: key) != value) {
        throw AppFailure.storage;
      }
    } catch (_) {
      throw AppFailure.storage;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: key);
      if (await _storage.read(key: key) != null) {
        throw AppFailure.storage;
      }
    } catch (_) {
      throw AppFailure.storage;
    }
  }
}
