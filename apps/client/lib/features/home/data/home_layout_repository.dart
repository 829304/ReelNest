import 'package:drift/drift.dart';
import '../../../storage/library_database.dart';
import '../../../storage/preference_store.dart';
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
      await database.writePreference(
        entry.key,
        entry.value.isEmpty ? null : entry.value,
      );
    }
  });
}
