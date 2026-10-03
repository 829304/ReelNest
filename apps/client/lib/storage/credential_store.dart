/// Stores one versioned session document. Implementations must not log values.
abstract interface class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}
