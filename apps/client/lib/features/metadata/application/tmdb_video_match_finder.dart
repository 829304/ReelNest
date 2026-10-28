import 'package:path/path.dart' as p;

import '../../../application/async_tasks.dart';
import '../../../domain/media_source.dart';
import '../data/tmdb_client.dart';
import '../domain/tmdb_match_scorer.dart';
import '../domain/tmdb_models.dart';

/// Shared original query variants, query budgets and singleton scoring for
/// series matching and health supplementation. Never mutates the library.
Future<ScoredTmdbMatch?> findTmdbVideoMatch({
  required TmdbClient client,
  required MediaSource source,
  required IndexedMedia item,
  required List<IndexedMedia> children,
  required TmdbMediaKind kind,
  required TmdbSettings settings,
  required String credential,
  required ScanCancellation cancellation,
  void Function(Object, StackTrace)? onFailure,
}) async {
  final folders = <String>{};
  for (final child in children) {
    final directory = p.dirname(
      p.join(source.location, p.joinAll(p.posix.split(child.identity.localId))),
    );
    folders.addAll([p.basename(directory), p.basename(p.dirname(directory))]);
  }
  final results = <TmdbCandidate>[], seen = <int>{}, singletons = <int>{};
  final queriesByID = <int, List<String>>{};
  var successful = 0, attempted = 0;
  for (final query in TmdbMatchScorer.queries(
    item,
    folders: folders,
  ).take(settings.matchTolerance.searchLimit)) {
    cancellation.check();
    attempted++;
    try {
      final response = await client.search(
        query,
        credential: credential,
        language: settings.language,
        cancellation: cancellation,
        kind: kind,
      );
      successful++;
      if (response.length == 1 && TmdbMatchScorer.specific(query)) {
        singletons.add(response.single.id);
      }
      for (final candidate in response) {
        (queriesByID[candidate.id] ??= []).add(query);
        if (seen.add(candidate.id)) results.add(candidate);
      }
    } on ScanCancelled {
      rethrow;
    } catch (error, stack) {
      cancellation.check();
      onFailure?.call(error, stack);
    }
  }
  cancellation.check();
  if (attempted > 0 && successful == 0) {
    throw const SourceFailure('TMDB 搜索失败，请稍后重试。');
  }
  return awaitWithCancellation(
    cancellation,
    () => TmdbMatchScorer.bestAsync(
      item,
      results,
      queriesByID,
      singletons,
      settings.matchTolerance,
    ),
  );
}
