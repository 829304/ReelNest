import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/domain/intro_outro_candidates.dart';
import 'package:reelnest/features/playback/domain/playback_marker.dart';

const _id = (sourceId: 'one', localId: 'video');
PlaybackMarker chapter(
  String title, {
  int start = 0,
  int end = 90,
  String id = 'chapter',
  MediaIdentity identity = _id,
}) => PlaybackMarker(
  id: id,
  identity: identity,
  kind: PlaybackMarkerKind.chapter,
  title: title,
  start: Duration(seconds: start),
  end: Duration(seconds: end),
  origin: PlaybackMarkerOrigin.embedded,
);
List<PlaybackMarker> generate(
  List<PlaybackMarker> existing, {
  int duration = 1200,
}) => IntroOutroCandidates.generate(
  identity: _id,
  duration: Duration(seconds: duration),
  existing: existing,
);

void main() {
  test(
    'original chapter labels, width/case/accents and short token boundaries',
    () {
      for (final title in [
        '片头',
        'OPENING theme',
        'Intró',
        '[OP]',
        'A op B',
        '【片头】',
        'ＯＰＥＮＩＮＧ',
        'オープニング',
        'ｵｰﾌﾟﾆﾝｸﾞ',
        '開頭',
        '开场',
      ]) {
        final candidate = generate([chapter(title)]).single;
        expect(candidate.kind, PlaybackMarkerKind.intro, reason: title);
        expect(candidate.isPendingReview, isTrue);
        expect(candidate.isAcceptedForPlayback, isFalse);
        expect(candidate.detectorIdentifier, 'embedded-chapter-keyword');
      }
      for (final title in [
        '片尾',
        'ENDING theme',
        '(ED)',
        'CREDITS',
        'credit roll',
        'スタッフ',
        'エンディング',
        'staff roll',
      ]) {
        expect(
          generate([chapter(title, start: 900, end: 990)]).single.kind,
          PlaybackMarkerKind.credits,
          reason: title,
        );
      }
      // Preserve the original narrow short-keyword matching, including OP at a
      // title edge. Do not infer a token from arbitrary substrings or punctuation.
      for (final title in [
        'Top',
        'edited',
        'op theme',
        'theme ed',
        '片头曲',
        'episode 1',
        'prelude',
        'Chapter 01',
        'OP: start',
      ]) {
        expect(generate([chapter(title)]), isEmpty, reason: title);
      }
      expect(generate([chapter('Opening')]).single.confidence, .88);
      expect(generate([chapter('[OP]')]).single.confidence, .76);
      expect(generate([chapter('Ópening')]).single.confidence, .76);
    },
  );

  test(
    'original duration, range length and placement thresholds stay inclusive',
    () {
      expect(generate([chapter('Opening')], duration: 60), isEmpty);
      expect(
        generate([chapter('Opening', end: 12)], duration: 61),
        hasLength(1),
      );
      expect(generate([chapter('Opening', end: 11)]), isEmpty);
      expect(generate([chapter('Opening', end: 180)]), hasLength(1));
      expect(generate([chapter('Opening', end: 181)]), isEmpty);
      expect(
        generate([chapter('Opening', start: 420, end: 432)]),
        hasLength(1),
      );
      expect(generate([chapter('Opening', start: 421, end: 433)]), isEmpty);
      expect(
        generate([chapter('Opening', start: 700, end: 720)], duration: 2000),
        hasLength(1),
      );
      expect(generate([chapter('Ending', start: 540, end: 552)]), hasLength(1));
      expect(generate([chapter('Ending', start: 539, end: 551)]), isEmpty);
      expect(
        generate([chapter('Ending', start: 540, end: 1260)]),
        hasLength(1),
      );
      expect(generate([chapter('Ending', start: 540, end: 1261)]), isEmpty);
      expect(generate([chapter('Opening', start: 10, end: 10)]), isEmpty);
    },
  );

  test(
    'only embedded complete chapters for this source and item are analyzed',
    () {
      final other = (sourceId: 'other-account', localId: _id.localId);
      expect(generate([chapter('Opening', identity: other)]), isEmpty);
      expect(
        generate([
          PlaybackMarker(
            identity: _id,
            kind: PlaybackMarkerKind.chapter,
            title: 'Opening',
            start: Duration.zero,
            end: const Duration(seconds: 90),
          ),
          PlaybackMarker(
            identity: _id,
            kind: PlaybackMarkerKind.chapter,
            title: 'Opening',
            start: Duration.zero,
            origin: PlaybackMarkerOrigin.embedded,
          ),
        ]),
        isEmpty,
      );
    },
  );

  test(
    'earliest eligible chapter wins; accepted ranges and prior IDs survive',
    () {
      final chapters = [
        chapter('Intro', id: 'later', start: 100, end: 120),
        chapter('Opening'),
        chapter('Credits', id: 'end', start: 1100, end: 1200),
      ];
      final first = generate(chapters);
      expect(first.map((m) => m.start), [
        Duration.zero,
        const Duration(seconds: 1100),
      ]);
      final pending = first.first;
      final rejected = PlaybackMarker(
        id: pending.id,
        identity: _id,
        kind: pending.kind,
        title: pending.title,
        start: pending.start,
        end: pending.end,
        origin: PlaybackMarkerOrigin.automatic,
        review: PlaybackMarkerReview.rejected,
      );
      final next = generate([...chapters, rejected]);
      expect(next.any((m) => m.id == rejected.id), isFalse);
      // The original may try a different chapter of the same kind after a
      // rejection; the rejected chapter itself is never re-created.
      expect(next.first.start, const Duration(seconds: 100));
      final manual = PlaybackMarker(
        identity: _id,
        kind: PlaybackMarkerKind.intro,
        title: 'My intro',
        start: const Duration(seconds: 3),
        end: const Duration(seconds: 30),
      );
      expect(generate([...chapters, manual]).map((m) => m.kind), [
        PlaybackMarkerKind.credits,
      ]);
      final incomplete = PlaybackMarker(
        identity: _id,
        kind: PlaybackMarkerKind.intro,
        title: 'Unfinished',
        start: Duration.zero,
      );
      expect(generate([...chapters, incomplete]), hasLength(2));
      expect(generate([chapter('Opening'), pending]), isEmpty);
    },
  );
}
