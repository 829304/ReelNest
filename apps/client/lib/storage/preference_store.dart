import 'package:drift/drift.dart';

import 'library_database.dart';

/// Raw preference persistence. Defaults, trimming and validation belong to callers.
/// Uses the current database transaction and does not emit source notifications.
extension PreferenceStore on LibraryDatabase {
  Future<String?> preferenceValue(String key) async => (await customSelect(
    'SELECT value FROM player_preferences WHERE key = ?',
    variables: [Variable(key)],
  ).getSingleOrNull())?.read<String>('value');

  /// Null deletes; an empty string remains a stored value.
  Future<void> writePreference(String key, String? value) => value == null
      ? customStatement('DELETE FROM player_preferences WHERE key = ?', [key])
      : customStatement(
          'INSERT INTO player_preferences(key, value) VALUES(?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, value],
        );
}
