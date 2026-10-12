import 'package:drift/drift.dart';

import '../../../storage/library_database.dart';
import '../domain/home_layout.dart';

class HomeLayoutRepository {
  const HomeLayoutRepository(this.database);
  final LibraryDatabase database;
  static const orderKey = 'home.moduleOrder';
  static const hiddenKey = 'home.hiddenModules';

  Future<HomeLayout> load() async {
    final rows = await database
        .customSelect(
          'SELECT key,value FROM player_preferences WHERE key IN (?,?)',
          variables: [const Variable(orderKey), const Variable(hiddenKey)],
        )
        .get();
    final values = {
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
    return HomeLayout.decode(values[orderKey] ?? '', values[hiddenKey] ?? '');
  }

  /// One atomic local preference write; never emit an index/source change.
  Future<void> save(HomeLayout layout) => database.transaction(() async {
    for (final entry in {
      orderKey: layout.encodedOrder,
      hiddenKey: layout.encodedHidden,
    }.entries) {
      if (entry.value.isEmpty) {
        await database.customStatement(
          'DELETE FROM player_preferences WHERE key = ?',
          [entry.key],
        );
      } else {
        await database.customStatement(
          'INSERT INTO player_preferences(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          [entry.key, entry.value],
        );
      }
    }
  });
}
