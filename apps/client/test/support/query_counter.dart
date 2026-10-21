import 'package:drift/drift.dart';

/// Counts actual rows crossing the SQLite boundary, not repository calls.
class QueryCounter extends QueryInterceptor {
  final reads = <({String sql, int rows})>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    reads.add((sql: statement, rows: result.length));
    return result;
  }
}
