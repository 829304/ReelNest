import '../../api/emby/emby_client.dart';
import '../../api/emby/emby_item.dart';
import '../../domain/media_source.dart';
import '../../domain/source_scan.dart';
import 'emby_item_mapper.dart';

typedef EmbyPageLoader = Future<EmbyItemPage> Function(
  String? parentId,
  int start,
  ScanCancellation cancellation,
);

/// Fetch a complete snapshot before touching persistent media, like importEmbyItems.
class EmbyLibrarySynchronizer {
  const EmbyLibrarySynchronizer({
    required this.libraries,
    required this.page,
    this.maxPages = 10000,
  });
  final Future<List<EmbyLibrary>> Function(ScanCancellation cancellation)
  libraries;
  final EmbyPageLoader page;
  final int maxPages;

  Future<List<IndexedMedia>> fetch(
    MediaSource source,
    ScanCancellation cancellation, {
    void Function(SourceScanProgress)? onProgress,
  }) async {
    cancellation.check();
    final available = await libraries(cancellation);
    cancellation.check();
    final selected = source.options.selectedEmbyLibraryIDs.toSet();
    final scope = available
        .where((l) => selected.isEmpty || selected.contains(l.id))
        .toList();
    // The original queries the root if Views is genuinely empty in all-libraries mode.
    final parents = <EmbyLibrary?>[
      ...scope,
      if (available.isEmpty && selected.isEmpty) null,
    ];
    final mapper = EmbyItemMapper(source.id, DateTime.now().toUtc());
    final items = <String, IndexedMedia>{};
    final candidates = <String, ({EmbyItem episode, EmbyLibrary? library})>{};
    for (final library in parents) {
      var start = 0, index = 0;
      int? declaredTotal;
      final seen = <String>{};
      while (true) {
        cancellation.check();
        final result = await page(library?.id, start, cancellation);
        cancellation.check();
        index++;
        if (declaredTotal != null &&
            result.total != null &&
            declaredTotal != result.total) {
          throw const SourceFailure('Emby 库在分页期间发生变化，已保留原索引，请重新同步。');
        }
        declaredTotal ??= result.total;
        var added = 0;
        for (final dto in result.items) {
          if (seen.add(dto.id)) added++;
          final mapped = mapper.map(dto, library);
          if (mapped != null) items.putIfAbsent(dto.id, () => mapped);
          if (dto.type == 'episode') {
            final id = dto.text('SeriesId'), name = dto.text('SeriesName');
            if (id != null &&
                id.isNotEmpty &&
                name != null &&
                name.isNotEmpty) {
              candidates[id] = (episode: dto, library: library);
            }
          }
        }
        onProgress?.call(
          SourceScanProgress(
            processedFiles: items.length,
            importedItems: items.length,
          ),
        );
        final next = start + result.items.length;
        if (result.items.isEmpty) {
          if (declaredTotal != null && seen.length < declaredTotal) {
            throw const SourceFailure('Emby 分页提前结束，已保留原索引，请重试同步。');
          }
          break;
        }
        // A repeated/truncated result is never treated as a complete snapshot.
        if (added == 0) {
          throw const SourceFailure('Emby 分页没有继续返回新条目，已保留原索引。');
        }
        if (declaredTotal != null && next >= declaredTotal) {
          if (seen.length < declaredTotal) {
            throw const SourceFailure('Emby 分页条目重复或缺失，已保留原索引。');
          }
          break;
        }
        if (index >= maxPages) {
          throw const SourceFailure('Emby 分页次数超出上限，已保留原索引。');
        }
        start = next;
      }
    }
    for (final entry in candidates.entries) {
      items.putIfAbsent(
        entry.key,
        () => mapper.syntheticSeries(entry.value.episode, entry.value.library),
      );
    }
    // A dangling season/series relation is incomplete data, not a new standalone
    // movie. Never replace a complete old library with broken associations.
    for (final item in items.values) {
      if (item.parentId != null &&
          (!items.containsKey(item.parentId) ||
              !items[item.parentId]!.isSeries)) {
        throw const SourceFailure('Emby 剧集缺少可用的系列信息，已保留原索引。');
      }
    }
    cancellation.check();
    return items.values.toList()..sort(
      (a, b) => a.isSeries == b.isSeries
          ? a.title.compareTo(b.title)
          : a.isSeries
          ? -1
          : 1,
    );
  }
}
