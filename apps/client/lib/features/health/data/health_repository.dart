import 'dart:async';

import '../../../domain/library_health.dart';
import '../../../storage/library_database.dart';

/// Original ignoredHealthIssueIDs semantics, with source-scoped media identity.
/// Deliberately independent of scan state and never writes media/source files.
class HealthRepository {
  HealthRepository(this.database);
  final LibraryDatabase database;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<Set<HealthIssueKey>> ignored() async {
    final rows = await database
        .customSelect('SELECT * FROM ignored_health_issues')
        .get();
    return {
      for (final row in rows)
        (
          kind: HealthIssueKind.values.firstWhere(
            (kind) => kind.storageValue == row.read<String>('category'),
          ),
          sourceId: row.read<String>('source_id'),
          localId: row.read<String>('local_id'),
        ),
    };
  }

  Future<void> ignore(HealthIssueKey key) async {
    await database.customStatement(
      'INSERT OR IGNORE INTO ignored_health_issues VALUES (?, ?, ?)',
      [key.kind.storageValue, key.sourceId, key.localId],
    );
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> restore() async {
    await database.customStatement('DELETE FROM ignored_health_issues');
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> close() => _changes.close();
}
