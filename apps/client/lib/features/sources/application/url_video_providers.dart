import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../data/url_video_repository.dart';
import '../domain/url_video.dart';
import 'source_providers.dart';
import 'url_video_health_monitor.dart';
import 'url_video_cover_service.dart';

export '../domain/url_video.dart';

final urlVideoRepositoryProvider = Provider<UrlVideoRepository>(
  (ref) => UrlVideoRepository(
    ref.watch(sourceRepositoryProvider),
    onAdded: (ids) => ref.read(urlVideoCoverServiceProvider).enqueue(ids),
  ),
);
final urlVideosProvider = FutureProvider<List<UrlVideo>>((ref) {
  ref.watch(sourceChangesProvider);
  return ref.watch(urlVideoRepositoryProvider).list();
});
final urlVideoHealthProvider =
    NotifierProvider<
      UrlVideoHealthController,
      Map<MediaIdentity, UrlVideoHealth>
    >(UrlVideoHealthController.new);

class UrlVideoHealthController
    extends Notifier<Map<MediaIdentity, UrlVideoHealth>> {
  late UrlVideoHealthMonitor _monitor;
  String? _fingerprint;
  bool _closed = false;
  Future<void> _pending = Future.value();
  @override
  Map<MediaIdentity, UrlVideoHealth> build() {
    _monitor = UrlVideoHealthMonitor(
      onState: (value) {
        if (ref.mounted) state = value;
      },
    );
    final subscription = ref
        .read(sourceRepositoryProvider)
        .changes
        .listen((_) => _automaticRefresh());
    ref.onDispose(() {
      _closed = true;
      unawaited(subscription.cancel());
      unawaited(_monitor.dispose());
    });
    scheduleMicrotask(_automaticRefresh);
    return const {};
  }

  Future<void> refresh() => _refresh(true);
  void _automaticRefresh() =>
      unawaited(_refresh(false).catchError((Object _) {}));
  Future<void> _refresh(bool force) {
    Future<void> health = Future.value();
    final work = _pending.then((_) async {
      if (_closed || !ref.mounted) return;
      final repo = ref.read(urlVideoRepositoryProvider);
      final items = await repo.list();
      final sources = await ref
          .read(sourceRepositoryProvider)
          .sources(includeCounts: false);
      if (_closed || !ref.mounted) return;
      final enabled =
          sources
              .where((s) => s.kind == MediaSourceKind.url)
              .firstOrNull
              ?.options
              .includeInHealthCheck ??
          false;
      // Poster/favorite/position updates do not re-probe every saved address.
      final fingerprint =
          '$enabled:${items.map((e) => e.identity.localId).join(',')}';
      if (!force && fingerprint == _fingerprint) return;
      _fingerprint = fingerprint;
      health = _monitor.refresh(items, enabled: enabled);
    });
    _pending = work.catchError((Object _) {});
    return work.then((_) => health);
  }

  Future<void> dispose() async {
    _closed = true;
    await _monitor.dispose();
    await _pending;
  }
}

final urlVideoCoverServiceProvider = Provider<UrlVideoCoverService>((ref) {
  final service = UrlVideoCoverService(
    sources: ref.watch(sourceRepositoryProvider),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
