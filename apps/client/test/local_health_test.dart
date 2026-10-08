import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/library_health.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/health/domain/local_health_evaluator.dart';

MediaSource source(
  String id,
  String path, {
  bool health = true,
  SourceMediaType type = SourceMediaType.auto,
}) => MediaSource(
  id: id,
  kind: MediaSourceKind.localFolder,
  name: id,
  location: path,
  mediaType: type,
  options: SourceOptions(includeInHealthCheck: health),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
IndexedMedia item(
  String source,
  String key, {
  String type = 'movie',
  bool series = false,
  String? parent,
  int? year,
  String? overview,
  String? poster,
}) => IndexedMedia(
  identity: (sourceId: source, localId: key),
  title: key,
  type: type,
  isSeries: series,
  parentId: parent,
  year: year,
  overview: overview,
  posterPath: poster,
  bytes: 0,
  modified: DateTime.utc(2026),
);

void main() {
  Future<LibraryHealthSnapshot> evaluate(
    List<MediaSource> sources,
    List<IndexedMedia> items,
    Set<String> present,
  ) =>
      LocalHealthEvaluator(
        paths: p.Context(style: p.Style.posix),
        exists: (path) async => present.contains(path),
      ).evaluate((
        sources: sources,
        items: items,
      ), cancellation: ScanCancellation());

  test('offline missing files are never safe, including after ignoring the offline alert', () async {
    final a = item('a', 'film.mkv'), b = item('b', 'film.mkv');
    final result = await evaluate(
      [source('a', '/a'), source('b', '/b')],
      [a, b],
      {'/a'},
    );
    expect(result.missing, {a.identity, b.identity});
    expect(result.safeMissing, {a.identity});
    expect(result.offline, {'b'});
    final filtered = result.excluding({
      (kind: HealthIssueKind.offlineSource, sourceId: 'b', localId: ''),
    });
    expect(filtered.offline, isEmpty);
    expect(filtered.safeMissing, {a.identity});
    expect(filtered.missingItems.length, 2);
  });
  test(
    'nested excluded paths do not exclude adjacent prefix siblings',
    () async {
      final hidden = item('root', 'A/film.mkv'),
          visible = item('root', 'Anime/film.mkv');
      final result = await evaluate(
        [
          source('root', '/Media'),
          source('excluded', '/Media/A', health: false),
        ],
        [hidden, visible],
        {'/Media'},
      );
      expect(result.missing, {visible.identity});
      expect(result.metadataGaps.keys, [visible.identity]);
      expect(result.offline, isEmpty);
    },
  );
  test('most specific offline source prevents safe classification for a parent index', () async {
    final film = item('root', 'Mount/film.mkv');
    final result = await evaluate(
      [source('root', '/Media'), source('mount', '/Media/Mount')],
      [film],
      {'/Media'},
    );
    expect(result.offline, {'mount'});
    expect(result.missing, {film.identity});
    expect(result.safeMissing, isEmpty);
  });
  test('photo files are checked but albums, music, private and episode metadata are excluded', () async {
    final photo = item('album', 'pic.jpg', type: 'photo');
    final episode = item(
      'video',
      'S01E01.mkv',
      type: 'episode',
      parent: 'series',
    );
    final result = await evaluate(
      [
        source('album', '/photos', type: SourceMediaType.photo),
        source('video', '/video'),
        source('private', '/vault', type: SourceMediaType.privateCollection),
      ],
      [
        photo,
        episode,
        item('private', 'hidden.mkv'),
        item('video', 'song.flac', type: 'music'),
        item('video', 'home.mkv', type: 'homeVideo'),
        item('video', 'series', type: 'tvShow', series: true),
      ],
      {'/photos', '/video', '/vault', '/video/home.mkv'},
    );
    expect(result.missing, {photo.identity, episode.identity});
    expect(result.metadataGaps.keys, [(sourceId: 'video', localId: 'series')]);
  });
  test('core metadata uses stored presence, not artwork reachability or scraping preference', () async {
    final full = item(
      'a',
      'full.mkv',
      year: 2000,
      overview: '简介',
      poster: 'nonexistent.jpg',
    );
    final empty = item('a', 'empty.mkv', overview: ' \n ');
    final result = await evaluate([source('a', '/a')], [full, empty], {'/a'});
    expect(result.metadataGaps, {
      empty.identity: ['封面', '年份', '简介'],
    });
  });
  test('Windows and UNC path boundaries are case insensitive and probes are deduplicated', () async {
    final calls = <String>[];
    final evaluator = LocalHealthEvaluator(
      paths: p.Context(style: p.Style.windows),
      exists: (path) async {
        calls.add(path.toLowerCase());
        return false;
      },
    );
    expect(
      evaluator.inside(r'C:\Media\Anime\film.mkv', r'c:\media\A'),
      isFalse,
    );
    expect(evaluator.inside(r'\\NAS\Share\film.mkv', r'\\nas\share'), isTrue);
    final result = await evaluator.evaluate((
      sources: [source('a', r'C:\Media'), source('b', r'c:\media')],
      items: [item('a', 'Film.mkv'), item('b', 'film.mkv')],
    ), cancellation: ScanCancellation());
    expect(result.missing.length, 2);
    expect(calls, [r'c:\media', r'c:\media\film.mkv']);
  });
  test(
    'cancelled filesystem probe does not proceed or publish a result',
    () async {
      final gate = Completer<bool>(), entered = Completer<void>();
      final cancellation = ScanCancellation();
      var probes = 0;
      final future =
          LocalHealthEvaluator(
            paths: p.Context(style: p.Style.posix),
            exists: (_) {
              probes++;
              entered.complete();
              return gate.future;
            },
          ).evaluate((
            sources: [source('a', '/a')],
            items: [item('a', 'f.mkv')],
          ), cancellation: cancellation);
      final assertion = expectLater(future, throwsA(isA<ScanCancelled>()));
      await entered.future;
      cancellation.cancel();
      gate.complete(true);
      await assertion;
      expect(probes, 1);
    },
  );
}
