import '../../../domain/media_source.dart';

enum VideoEndAction {
  nextEpisode('自动下一集'),
  holdLastFrame('停在结尾'),
  closeWindow('关闭窗口');

  const VideoEndAction(this.label);
  final String label;
}

/// AppState.videoQueueItems and MediaHierarchyPolicy. The visible queue is a
/// suffix, whereas manual adjacency uses all siblings and never wraps.
class VideoQueue {
  const VideoQueue({this.sequence = const [], this.items = const []});
  final List<IndexedMedia> sequence;
  final List<IndexedMedia> items;

  factory VideoQueue.forItem(IndexedMedia current, List<IndexedMedia> library) {
    final parent = current.parentId;
    final hasParent =
        parent != null &&
        library.any(
          (i) =>
              i.identity.sourceId == current.identity.sourceId &&
              i.identity.localId == parent &&
              i.isSeries,
        );
    final sequence = hasParent
        ? (library
              .where(
                (i) =>
                    i.identity.sourceId == current.identity.sourceId &&
                    i.parentId == parent &&
                    i.filePath != null,
              )
              .toList()
            ..sort(_compareEpisodes))
        : (library
              .where(
                (i) =>
                    i.parentId == null &&
                    i.filePath != null &&
                    i.type != 'music' &&
                    i.type != 'photo',
              )
              .toList()
            ..sort(
              (a, b) => (b.updatedAt ?? b.modified).compareTo(
                a.updatedAt ?? a.modified,
              ),
            ));
    final index = sequence.indexWhere((i) => i.identity == current.identity);
    return VideoQueue(
      sequence: List.unmodifiable(sequence),
      items: List.unmodifiable(
        hasParent && index >= 0 ? sequence.sublist(index) : [current],
      ),
    );
  }

  IndexedMedia? adjacent(MediaIdentity current, int direction) {
    final index = sequence.indexWhere((i) => i.identity == current);
    if (index < 0) return null;
    final target = index + (direction < 0 ? -1 : 1);
    return target < 0 || target >= sequence.length ? null : sequence[target];
  }

  static int _compareEpisodes(IndexedMedia a, IndexedMedia b) {
    var result = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
    if (result != 0) return result;
    result = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
    if (result != 0) return result;
    // Natural numeric ordering follows localizedStandardCompare's numeric
    // rule. Locale/width/diacritic collation remains platform acceptance work.
    final parts = RegExp(r'\d+|\D+');
    final left = parts
        .allMatches(a.title.toLowerCase())
        .map((m) => m[0]!)
        .toList();
    final right = parts
        .allMatches(b.title.toLowerCase())
        .map((m) => m[0]!)
        .toList();
    for (var i = 0; i < left.length && i < right.length; i++) {
      final x = BigInt.tryParse(left[i]), y = BigInt.tryParse(right[i]);
      result = x != null && y != null
          ? x.compareTo(y)
          : left[i].compareTo(right[i]);
      if (result != 0) return result;
    }
    return left.length.compareTo(right.length);
  }
}
