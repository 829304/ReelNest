import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/domain/tmdb_match_scorer.dart';
import 'package:reelnest/features/metadata/domain/tmdb_match_tolerance.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';

IndexedMedia item(String title, {String? original, int? year}) => IndexedMedia(
  identity: (sourceId: 'source', localId: 'show'),
  title: title,
  originalTitle: original,
  year: year,
  type: 'tvShow',
  isSeries: true,
  bytes: 0,
  modified: DateTime.utc(2026),
);
TmdbCandidate candidate(int id, String title, {int? year}) =>
    TmdbCandidate(id: id, title: title, year: year, kind: TmdbMediaKind.tv);
void main() {
  test(
    'noise, bracket groups and CJK season suffixes produce original queries',
    () {
      expect(
        TmdbMatchScorer.normalized('[Group] Dark.S01E02.1080p.WEB-DL.mkv'),
        'dark',
      );
      expect(TmdbMatchScorer.queries(item('三体 第2季 全12集 1080p')).first, '三体');
      expect(
        TmdbMatchScorer.queries(
          item('Show S02E03 2021'),
          folders: ['Folder.CollectionName', 'Season 2'],
        ),
        contains('folder collectionname'),
      );
      expect(
        TmdbMatchScorer.queries(item('Café'), folders: ['CAFE']),
        contains('café'),
      );
    },
  );
  test('specific query rule rejects generic words and numeric releases', () {
    for (final query in ['Season', 'TV', '2024', '完结', '第2季']) {
      expect(TmdbMatchScorer.specific(query), isFalse, reason: query);
    }
    expect(TmdbMatchScorer.specific('Sousou no Frieren'), isTrue);
  });
  test('equal scores preserve server relevance order', () {
    final results = [candidate(2, 'Dark'), candidate(1, 'Dark')];
    expect(
      TmdbMatchScorer.best(
        item('Dark'),
        results,
        {},
        {},
        TmdbMatchTolerance.loose,
      )!.candidate.id,
      2,
    );
  });
  test('year agreement wins against a different adaptation', () {
    final results = [
      candidate(1, 'Three Body', year: 2010),
      candidate(2, 'Three Body', year: 2023),
    ];
    expect(
      TmdbMatchScorer.best(
        item('Three Body', year: 2023),
        results,
        {},
        {},
        TmdbMatchTolerance.strict,
      )!.candidate.id,
      2,
    );
  });
  test(
    'a unique cross-language result clears loose but not standard or strict',
    () {
      final result = candidate(1, '葬送的芙莉莲');
      final match = TmdbMatchScorer.best(
        item('Sousou no Frieren'),
        [result],
        {
          1: ['Sousou no Frieren'],
        },
        {1},
        TmdbMatchTolerance.loose,
      )!;
      expect(match.confidence, .52);
      expect(
        match.confidence,
        greaterThanOrEqualTo(TmdbMatchTolerance.loose.videoThreshold),
      );
      expect(
        match.confidence,
        lessThan(TmdbMatchTolerance.standard.videoThreshold),
      );
    },
  );
  test('strong distinct result beats weak singleton evidence', () {
    final best = TmdbMatchScorer.best(
      item('Dark'),
      [candidate(1, 'Unrelated'), candidate(2, 'Dark')],
      {
        1: ['Another title'],
        2: ['Dark'],
      },
      {1},
      TmdbMatchTolerance.loose,
    )!;
    expect(best.candidate.id, 2);
  });
  test('conflicting unrelated singleton results do not bypass confidence', () {
    final best = TmdbMatchScorer.best(
      item('三体'),
      [candidate(1, 'abcdef'), candidate(2, 'ghijkl')],
      {
        1: ['三体'],
        2: ['三体'],
      },
      {1, 2},
      TmdbMatchTolerance.loose,
    )!;
    expect(best.confidence, lessThan(.42));
  });
  test('grapheme Levenshtein handles CJK, empty and emoji safely', () {
    expect(TmdbMatchScorer.similarity('三体', '三体'), 1);
    expect(TmdbMatchScorer.similarity('三体', '三国'), .5);
    expect(TmdbMatchScorer.similarity('', ''), 1);
    expect(TmdbMatchScorer.similarity('a', ''), 0);
    expect(TmdbMatchScorer.similarity('👩‍👩‍👧a', '👩‍👩‍👧b'), .5);
  });
  test(
    'oversized metadata titles fail without starting edit-distance work',
    () {
      expect(
        () => TmdbMatchScorer.normalized('a' * 1025),
        throwsA(isA<SourceFailure>()),
      );
    },
  );

  test('tolerance thresholds and query budgets match original defaults', () {
    expect(TmdbMatchTolerance.parse(null), TmdbMatchTolerance.loose);
    expect(TmdbMatchTolerance.parse('invalid'), TmdbMatchTolerance.loose);
    expect(TmdbMatchTolerance.values.map((e) => e.videoThreshold), [
      .42,
      .58,
      .74,
    ]);
    expect(TmdbMatchTolerance.values.map((e) => e.searchLimit), [16, 10, 6]);
  });
}
