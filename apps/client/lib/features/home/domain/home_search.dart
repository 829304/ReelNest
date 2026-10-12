import 'dart:convert';

import '../../../domain/media_source.dart';
import '../../sources/domain/emby_library.dart';
import 'home_snapshot.dart';

/// Configuration is part of the provider key: retained AsyncLoading data from
/// another account, location or library selection must never enter this search.
String homeSearchScope(MediaSource source) => jsonEncode([
  source.id,
  source.kind.name,
  source.location,
  source.mediaType.name,
  source.updatedAt.millisecondsSinceEpoch,
  source.lastScan?.millisecondsSinceEpoch,
  source.options.toJson(),
]);

enum HomeSearchGroup {
  movie('电影'),
  tvShow('电视剧'),
  anime('动漫'),
  documentary('纪录片'),
  variety('综艺'),
  other('其他');

  const HomeSearchGroup(this.title);
  final String title;
  static HomeSearchGroup of(HomeVideo video) =>
      values.where((g) => g.name == video.item.displayType).firstOrNull ??
      other;
}

class HomeSearchState {
  const HomeSearchState({
    this.groups = const {},
    this.loading = false,
    this.partial = false,
    this.errors = const {},
  });
  final Map<HomeSearchGroup, List<HomeVideo>> groups;
  final bool loading, partial;
  final Map<String, String> errors;
  int get count =>
      groups.values.fold(0, (count, items) => count + items.length);

  static HomeSearchState merge(
    List<HomeVideo> items, {
    required bool loading,
    required bool partial,
    required Map<String, String> errors,
  }) {
    final groups = <HomeSearchGroup, List<HomeVideo>>{};
    for (final item in {for (final v in items) v.item.identity: v}.values) {
      (groups[HomeSearchGroup.of(item)] ??= []).add(item);
    }
    for (final group in groups.values) {
      group.sort((a, b) {
        final title = libraryTitleCompare(a.item.title, b.item.title);
        if (title != 0) return title;
        final source = a.source.id.compareTo(b.source.id);
        return source != 0
            ? source
            : a.item.identity.localId.compareTo(b.item.identity.localId);
      });
    }
    return HomeSearchState(
      groups: Map<HomeSearchGroup, List<HomeVideo>>.unmodifiable({
        for (final type in HomeSearchGroup.values)
          if (groups.containsKey(type))
            type: List<HomeVideo>.unmodifiable(groups[type]!),
      }),
      loading: loading,
      partial: partial,
      errors: Map.unmodifiable(errors),
    );
  }
}
