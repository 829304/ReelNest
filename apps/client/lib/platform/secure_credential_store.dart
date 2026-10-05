import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/app_failure.dart';
import '../storage/credential_store.dart';

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // No Keychain sharing or app group is needed by the macOS client.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;
  static const _key = 'io.github.user829304.reelnest.mlink.session.v1';

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      throw AppFailure.storage;
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(key: _key, value: value);
      if (await _storage.read(key: _key) != value) {
        throw AppFailure.storage;
      }
    } catch (_) {
      throw AppFailure.storage;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
      if (await _storage.read(key: _key) != null) {
        throw AppFailure.storage;
      }
    } catch (_) {
      throw AppFailure.storage;
    }
  }
}
