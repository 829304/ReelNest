import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../domain/media_source.dart';
import 'playback_marker.dart';

/// AppState.automaticIntroOutroCandidates (MediaLib 64f8ee2). Only chapter
/// metadata is inspected; no media probing, network request or decoder is used.
class IntroOutroCandidates {
  static List<PlaybackMarker> generate({
    required MediaIdentity identity,
    required Duration duration,
    required Iterable<PlaybackMarker> existing,
  }) {
    if (duration <= const Duration(seconds: 60)) return [];
    final markers = existing.where((m) => m.identity == identity).toList();
    final ids = markers.map((m) => m.id).toSet();
    final acceptedKinds = markers
        .where((m) => m.isCompleteRange && m.isAcceptedForPlayback)
        .map((m) => m.kind)
        .toSet();
    final chapters =
        markers
            .where(
              (m) =>
                  m.kind == PlaybackMarkerKind.chapter &&
                  m.origin == PlaybackMarkerOrigin.embedded &&
                  m.isCompleteRange,
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final result = <PlaybackMarker>[];
    for (final chapter in chapters) {
      final kind = _kind(chapter.title);
      if (kind == null ||
          acceptedKinds.contains(kind) ||
          !_plausible(kind, chapter.start, chapter.end!, duration)) {
        continue;
      }
      final id = 'automatic-${identity.localId}-${kind.name}-${chapter.id}';
      if (ids.contains(id) || result.any((m) => m.kind == kind)) continue;
      final title = chapter.title.toLowerCase();
      result.add(
        PlaybackMarker(
          id: id,
          identity: identity,
          kind: kind,
          title: kind.title,
          start: chapter.start,
          end: chapter.end,
          origin: PlaybackMarkerOrigin.automatic,
          review: PlaybackMarkerReview.pending,
          detectorIdentifier: 'embedded-chapter-keyword',
          confidence:
              ['opening', 'ending', 'credits', '片头', '片尾'].any(title.contains)
              ? .88
              : .76,
        ),
      );
    }
    return result;
  }

  static PlaybackMarkerKind? _kind(String title) {
    // Width folding must also handle half-width Japanese chapter labels. NFKC
    // is applied only to width-form characters, not unrelated compatibility
    // symbols that Foundation's widthInsensitive would leave unchanged.
    final width = title.replaceAllMapped(
      RegExp(r'[\u3000\uff01-\uffef]+'),
      (match) => unorm.nfkc(match[0]!),
    );
    // NFD + mark removal folds accents while retaining Japanese voicing marks:
    // removing those would turn オープニング into a different keyword.
    final text = unorm
        .nfc(unorm.nfd(width).replaceAll(RegExp(r'[\u0300-\u036f]'), ''))
        .toLowerCase()
        .trim();
    bool matches(String keyword) => keyword.runes.length <= 2
        ? text == keyword ||
              [
                ' $keyword ',
                '[$keyword]',
                '($keyword)',
                '【$keyword】',
              ].any(text.contains)
        : text.contains(keyword);
    if (['片头', 'opening', 'op', 'intro', 'オープニング', '開頭', '开场'].any(matches)) {
      return PlaybackMarkerKind.intro;
    }
    if ([
      '片尾',
      'ending',
      'ed',
      'credits',
      'credit',
      'エンディング',
      'スタッフ',
      'staff roll',
    ].any(matches)) {
      return PlaybackMarkerKind.credits;
    }
    return null;
  }

  static bool _plausible(
    PlaybackMarkerKind kind,
    Duration start,
    Duration end,
    Duration duration,
  ) {
    final length = (end - start).inMicroseconds;
    if (length < const Duration(seconds: 12).inMicroseconds) return false;
    return switch (kind) {
      PlaybackMarkerKind.intro =>
        length <= const Duration(seconds: 180).inMicroseconds &&
            start.inMicroseconds <=
                (duration.inMicroseconds * .35).clamp(
                  const Duration(seconds: 420).inMicroseconds,
                  double.infinity,
                ),
      PlaybackMarkerKind.credits =>
        length <= const Duration(seconds: 720).inMicroseconds &&
            start.inMicroseconds >= duration.inMicroseconds * .45,
      _ => false,
    };
  }
}
