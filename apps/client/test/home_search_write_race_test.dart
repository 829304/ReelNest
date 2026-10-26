import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/home/domain/home_search.dart';
import 'package:reelnest/domain/media_source.dart';

class _WriteDuringSearch extends QueryInterceptor {
  _WriteDuringSearch(this.statement, {this.continuous = false});
  final String statement;
  final bool continuous;
  int reads = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String sql,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(sql, args);
    if (sql.contains('SELECT scope.*, d.value AS details')) {
      reads++;
      if (reads == 1 || continuous) await executor.runCustom(statement, []);
    }
    return rows;
  }
}

void main() {
  for (final mutation in ['unrelated', 'rename', 'delete', 'continuous']) {
    test(
      'search revalidates $mutation writes without false empty results',
      () async {
        final interceptor = _WriteDuringSearch(switch (mutation) {
          'rename' => "UPDATE media SET title='New Match' WHERE source_id='a'",
          'delete' => "DELETE FROM media WHERE source_id='a'",
          _ => "INSERT OR REPLACE INTO player_preferences(key,value) VALUES ('unrelated.setting','1')",
        }, continuous: mutation == 'continuous');
        final db = LibraryDatabase(
          NativeDatabase.memory().interceptWith(interceptor),
        );
        final sources = SourceRepository(database: db, adapters: {});
        addTearDown(sources.close);
        final source = await sources.add(
          sourceId: 'a',
          kind: MediaSourceKind.emby,
          name: 'a',
          location: 'emby://fixture/a',
        );
        await db.customStatement(
          "INSERT INTO media(source_id,local_id,title,type,bytes,modified,is_series,identity_kind) VALUES('a','film','Old Match','movie',0,1,0,'fixture')",
        );
        final home = HomeRepository(sources);
        final result = home.search(
          'a',
          'Match',
          scope: homeSearchScope(source),
          cancellation: ScanCancellation(),
        );
        if (mutation == 'continuous') {
          await expectLater(result, throwsA(isA<SourceFailure>()));
          expect(interceptor.reads, 3);
        } else {
          final matches = await result;
          expect(matches, hasLength(mutation == 'delete' ? 0 : 1));
          if (mutation == 'rename') {
            expect(matches.single.item.title, 'New Match');
          }
          expect(interceptor.reads, 2);
          await home.search(
            'a',
            'Match',
            scope: homeSearchScope(source),
            cancellation: ScanCancellation(),
          );
          expect(
            interceptor.reads,
            2,
            reason: 'Only the validated snapshot is cached',
          );
        }
      },
    );
  }
}
