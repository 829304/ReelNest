import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../sources/application/source_providers.dart';
import '../data/home_repository.dart';
import '../data/home_search_worker.dart';
import '../domain/home_search.dart';
import '../domain/home_snapshot.dart';
import 'home_providers.dart';

typedef HomeSearchQuery = ({String sourceId, String scope, String query});
typedef HomeSearchKey = ({String query, String scope});

final homeSearchSourceProvider = FutureProvider.autoDispose
    .family<List<HomeVideo>, HomeSearchQuery>((ref, key) {
      final sources = ref.watch(sourceRepositoryProvider);
      ref.watch(
        sourceChangesProvider.select(
          (_) => sources.sourceViewRevision(key.sourceId),
        ),
      );
      final cancellation = ScanCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .watch(homeRepositoryProvider)
          .search(
            key.sourceId,
            key.query,
            scope: key.scope,
            cancellation: cancellation,
          );
    }, retry: (_, _) => null);

/// Each source publishes independently. A slow/unavailable source cannot hold
/// back other hits. Different queries/configurations never reuse old results.
final homeSearchProvider = FutureProvider.autoDispose
    .family<HomeSearchState, HomeSearchKey>((ref, key) async {
      final cancellation = ScanCancellation();
      ref.onDispose(cancellation.cancel);
      final query = key.query;
      if (query.trim().isEmpty) return const HomeSearchState();
      final sources = ref.watch(sidebarSourcesProvider);
      final items = <HomeVideo>[];
      final errors = <String, String>{};
      var loading = sources.isLoading, partial = false;
      if (sources.hasError) {
        errors['sources'] = sourceErrorMessage(sources.error!);
      }
      for (final source in (sources.value ?? <MediaSource>[]).where(
        HomeRepository.accepts,
      )) {
        partial |= source.kind.isRemoteVideoSource && source.lastScan == null;
        final result = ref.watch(
          homeSearchSourceProvider((
            sourceId: source.id,
            scope: homeSearchScope(source),
            query: query,
          )),
        );
        loading |= result.isLoading;
        items.addAll(result.value ?? []);
        if (result.hasError) {
          errors[source.id] =
              '${source.name}：${sourceErrorMessage(result.error!)}';
        }
      }
      HomeSearchState merge() => HomeSearchState.merge(
        items,
        loading: loading,
        partial: partial,
        errors: errors,
      );
      return items.length > 180
          ? runHomeSearchWorker(merge, cancellation)
          : merge();
    }, retry: (_, _) => null);
