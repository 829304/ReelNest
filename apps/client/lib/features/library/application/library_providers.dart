import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/service_providers.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/media.dart';
import '../../servers/application/connection_controller.dart';
import '../../servers/data/server_repository.dart';
import '../data/artwork_repository.dart';

final libraryScopeProvider = Provider<int?>((ref) {
  final state = ref.watch(connectionControllerProvider);
  return state.connection == null || state.requiresLogin ||
      state.pendingSave || state.pendingClear || state.needsRestore
      ? null : state.generation;
});

typedef BrowseKey = ({int scope, String type, MediaSort sort,
  String? seriesId, String? season});
typedef DetailKey = ({int scope, String id, bool isSeries});
typedef ArtworkKey = ({int scope, String id});

final mediaDetailProvider = FutureProvider.autoDispose.family<MediaDetail, DetailKey>(
  (ref, key) => ref.watch(serverRepositoryProvider).detail(key.scope, key.id, key.isSeries),
  retry: (_, _) => null,
);

final artworkRepositoryProvider = Provider.autoDispose.family<ArtworkRepository, int>(
  (ref, scope) {
    final repository = ArtworkRepository(ref.watch(serverRepositoryProvider), scope);
    ref.onDispose(repository.dispose);
    return repository;
  },
);

final artworkProvider = FutureProvider.autoDispose.family<Uint8List, ArtworkKey>(
  (ref, key) {
    final repository = ref.watch(artworkRepositoryProvider(key.scope));
    ref.onDispose(() => repository.cancelQueued(key.id));
    return repository.load(key.id);
  },
  retry: (_, _) => null,
);

class BrowseState {
  const BrowseState({this.items = const [], this.total = 0,
    this.nextOffset = 0, this.hasMore = false, this.loading = false,
    this.loadingMore = false, this.failure, this.limitReached = false,
    this.appendFailure = false});

  final List<MediaItem> items;
  final int total;
  final int nextOffset;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final AppFailure? failure;
  final bool limitReached;
  final bool appendFailure;
}

final browseProvider = NotifierProvider.autoDispose.family<
  BrowseController, BrowseState, BrowseKey>(BrowseController.new);

class BrowseController extends Notifier<BrowseState> {
  BrowseController(this.query);
  final BrowseKey query;
  late ServerRepository _repository;
  bool _disposed = false;
  int _request = 0;

  @override
  BrowseState build() {
    _repository = ref.read(serverRepositoryProvider);
    ref.onDispose(() { _disposed = true; _request++; });
    unawaited(Future<void>.microtask(refresh));
    return const BrowseState(loading: true);
  }

  Future<void> refresh() => _load(reset: true);

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    await _load(reset: false);
  }

  Future<void> _load({required bool reset}) async {
    if (_disposed) return;
    final ticket = ++_request;
    final before = state;
    final offset = reset ? 0 : before.nextOffset;
    state = BrowseState(items: before.items, total: before.total,
      nextOffset: before.nextOffset, hasMore: before.hasMore,
      loading: reset, loadingMore: !reset);
    try {
      final page = query.seriesId == null
          ? await _repository.browse(query.scope, query.type, query.sort, offset)
          : await _repository.episodes(query.scope, query.seriesId!, query.season!, offset);
      if (_disposed || ticket != _request) return;
      final items = reset ? <MediaItem>[] : [...before.items];
      final ids = items.map((item) => item.id).toSet();
      final additions = page.items.where((item) => ids.add(item.id)).toList();
      if (!reset && page.hasMore && additions.isEmpty) {
        throw const AppFailure(FailureKind.invalidResponse,
          '媒体库内容发生变化，当前页没有新条目。请刷新列表后重试。');
      }
      items.addAll(additions);
      final limitReached = page.hasMore && page.nextOffset > 1000000;
      state = BrowseState(items: List.unmodifiable(items), total: page.total,
        nextOffset: page.nextOffset, hasMore: page.hasMore && !limitReached,
        limitReached: limitReached);
    } catch (error) {
      if (_disposed || ticket != _request) return;
      state = BrowseState(items: before.items, total: before.total,
        nextOffset: before.nextOffset, hasMore: before.hasMore,
        failure: AppFailure.from(error), limitReached: before.limitReached,
        appendFailure: !reset);
    }
  }
}
