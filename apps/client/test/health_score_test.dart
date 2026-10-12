import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/app/runtime_observations.dart';
import 'package:reelnest/domain/library_health.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/health/application/health_providers.dart';
import 'package:reelnest/features/health/domain/health_score.dart';
import 'package:reelnest/features/health/domain/local_health_evaluator.dart';
import 'package:reelnest/features/health/domain/video_health_evaluator.dart';
import 'package:reelnest/features/home/application/home_runtime_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';

final date = DateTime.utc(2026, 10, 12);
MediaSource source(
  String id, {
  MediaSourceKind kind = MediaSourceKind.localFolder,
  SourceMediaType type = SourceMediaType.auto,
  bool health = true,
  List<String> selected = const [],
  bool scanned = true,
  String? location,
}) => MediaSource(
  id: id,
  name: id,
  kind: kind,
  location: location ?? '/$id',
  mediaType: type,
  createdAt: date,
  updatedAt: date,
  lastScan: scanned ? date : null,
  options: SourceOptions(
    includeInHealthCheck: health,
    selectedEmbyLibraryIDs: selected,
  ),
);
IndexedMedia item(
  String id, {
  String owner = 'a',
  String title = 'Movie',
  int? year = 2026,
  String type = 'movie',
  bool series = false,
  String? parent,
  bool complete = true,
  RemoteMediaMetadata? remote,
}) => IndexedMedia(
  identity: (sourceId: owner, localId: id),
  title: title,
  type: type,
  bytes: 1,
  modified: date,
  year: year,
  isSeries: series,
  parentId: parent,
  posterPath: complete ? 'poster.jpg' : null,
  overview: complete ? 'Overview' : null,
  remote: remote,
);
Future<LibraryHealthSnapshot> evaluate(
  List<MediaSource> sources,
  List<IndexedMedia> items, {
  Set<String> absent = const {},
  ScanCancellation? cancellation,
}) =>
    VideoHealthEvaluator(
      LocalHealthEvaluator(
        paths: p.Context(style: p.Style.posix),
        exists: (path) async => !absent.contains(path),
      ),
    ).evaluate((
      sources: sources,
      items: items,
    ), cancellation: cancellation ?? ScanCancellation());
LibraryHealthSnapshot snapshot({
  List<MediaSource>? sources,
  List<IndexedMedia>? items,
  Set<MediaIdentity> missing = const {},
  Set<String> offline = const {},
  Map<MediaIdentity, List<String>> core = const {},
  Map<MediaIdentity, List<String>> detail = const {},
  List<List<IndexedMedia>> duplicates = const [],
}) => LibraryHealthSnapshot(
  inventory: (
    sources: sources ?? [source('a')],
    items: items ?? [item('a.mkv')],
  ),
  missing: missing,
  safeMissing: missing,
  offline: offline,
  metadataGaps: core,
  detailGaps: detail,
  duplicates: duplicates,
  evaluationComplete: true,
);

void main() {
  test('duplicate display rows freeze their group membership', () {
    final members = [item('a'), item('b')];
    final value = snapshot(duplicates: [members]);
    final key = duplicateIssueKey(value.duplicateRows.first.group);
    members.clear();
    expect(value.duplicates.single, hasLength(2));
    expect(value.duplicateRows, hasLength(3));
    expect(duplicateIssueKey(value.duplicateRows.first.group), key);
    expect(
      () => value.duplicateRows.first.group.clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'deferred and private roots protect overlaps without filesystem probes',
    () async {
      final probed = <String>[];
      final sources = [
        source('a'),
        source('music', type: SourceMediaType.music),
        source('photo', type: SourceMediaType.photo),
        source('private', type: SourceMediaType.privateCollection),
      ];
      final value =
          await VideoHealthEvaluator(
            LocalHealthEvaluator(
              paths: p.Context(style: p.Style.posix),
              exists: (path) async {
                probed.add(path);
                return true;
              },
            ),
          ).evaluate((
            sources: sources,
            items: [item('film.mkv')],
          ), cancellation: ScanCancellation());
      expect(probed, ['/a', '/a/film.mkv']);
      expect(value.configurationSources, hasLength(4));
      expect(value.inventory.sources.map((s) => s.id), ['a']);
    },
  );
  test(
    'original source and metadata penalties retain clamps and count floors',
    () {
      expect(HealthScore.sourcePercent(4, 1, 2), 70);
      expect(HealthScore.sourcePercent(1, 50, 50), 35);
      expect(HealthScore.metadataPercent(1000, 1), 97);
      expect(HealthScore.metadataPercent(1, 1), 45);
      expect(HealthScore.metadataPercent(0, 0), 100);
    },
  );
  test('home blend and dashboard scores remain distinct original formulas', () {
    final a = item('a.mkv'), b = item('b.mkv');
    final value = snapshot(
      sources: [source('a'), source('b')],
      items: [a, b],
      missing: {a.identity, b.identity},
      offline: {'a'},
      core: {
        a.identity: ['封面'],
      },
      detail: {
        a.identity: ['人物'],
      },
      duplicates: [
        [a, b],
      ],
    );
    final score = HealthScore.fromSnapshot(value);
    expect(score.source, 78);
    expect(score.metadata, 45);
    expect(score.overall, 57);
    expect(HealthScore.dashboardHealth(value), 58);
    expect(HealthScore.dashboardMetadata(value), 88);
    expect(HealthScore.fromSnapshot(snapshot()).overall, 100);
  });
  test('home penalty is capped at eight issues and floor is 42', () {
    final values = List.generate(20, (i) => item('$i'));
    final value = snapshot(
      items: values,
      missing: values.map((i) => i.identity).toSet(),
      offline: {'a'},
      core: {
        for (final v in values) v.identity: ['封面'],
      },
    );
    expect(HealthScore.fromSnapshot(value).overall, 47);
    expect(
      HealthScore.fromSnapshot(
        snapshot(
          sources: [source('a', health: false)],
          items: values,
          missing: values.map((i) => i.identity).toSet(),
          offline: {'a'},
          core: {
            for (final v in values) v.identity: ['封面'],
          },
        ),
      ).overall,
      45,
    );
  });
  test('duplicate normalization preserves type/year/non-Latin boundaries', () {
    expect(
      VideoHealthEvaluator.duplicateKey(item('a', title: 'Movie: Title!')),
      VideoHealthEvaluator.duplicateKey(item('b', title: 'movie title')),
    );
    expect(
      VideoHealthEvaluator.duplicateKey(
        item('a', title: '电影：标题 01', year: null),
      ),
      'movie-电影标题01-unknown',
    );
    expect(
      VideoHealthEvaluator.duplicateKey(item('a', type: 'tvShow')),
      isNot(VideoHealthEvaluator.duplicateKey(item('a'))),
    );
    expect(
      VideoHealthEvaluator.duplicateKey(item('a', year: 2025)),
      isNot(VideoHealthEvaluator.duplicateKey(item('a'))),
    );
  });
  test('duplicates are local top-level only; scoped IDs prevent cross-source aliasing', () async {
    final a = item('film.mkv'), b = item('film.mkv', owner: 'b');
    final value = await evaluate(
      [source('a'), source('b'), source('remote', kind: MediaSourceKind.emby)],
      [
        a,
        b,
        item('episode', parent: 'series'),
        item(
          'remote',
          owner: 'remote',
          remote: const RemoteMediaMetadata(externalId: 'remote'),
        ),
      ],
    );
    expect(value.duplicates.single.map((v) => v.identity), [
      a.identity,
      b.identity,
    ]);
    expect(duplicateIssueKey([a, b]), duplicateIssueKey([b, a]));
    expect(
      duplicateIssueKey([a, b]),
      isNot(duplicateIssueKey([a, item('film.mkv', owner: 'other')])),
    );
  });
  test('remote core checks use stored data without probing a filesystem or requiring MediaSources', () async {
    var probes = 0;
    final evaluator = VideoHealthEvaluator(
      LocalHealthEvaluator(
        paths: p.Context(style: p.Style.posix),
        exists: (_) async {
          probes++;
          return false;
        },
      ),
    );
    final film = item(
      'film',
      owner: 'remote',
      complete: false,
      year: null,
      remote: const RemoteMediaMetadata(externalId: 'film'),
    );
    final series = item(
      'series',
      owner: 'remote',
      series: true,
      remote: const RemoteMediaMetadata(externalId: 'series'),
    );
    final value = await evaluator.evaluate((
      sources: [source('remote', kind: MediaSourceKind.emby)],
      items: [film, series],
    ), cancellation: ScanCancellation());
    expect(probes, 0);
    expect(value.metadataGaps[film.identity], ['封面', '年份', '简介']);
    expect(value.missing, isEmpty);
    expect(
      value.detailGaps,
      isEmpty,
      reason: 'original detail completeness is for local top-level films',
    );
    expect(value.evaluationComplete, true);
  });
  test('local detail presence detects four missing record categories even with a core poster', () async {
    final film = item('film.mkv');
    final value = await evaluate([source('a')], [film]);
    expect(value.metadataGaps, isEmpty);
    expect(value.detailGaps[film.identity], ['外部 ID', '人物', '艺术照', '推荐']);
    expect(HealthScore.fromSnapshot(value).overall, 75);
  });
  test('bad remote identity is a missing playback path, never a safe local cleanup', () async {
    final value = await evaluate(
      [source('remote', kind: MediaSourceKind.emby)],
      [
        item('bad', owner: 'remote'),
        item('series', owner: 'remote', series: true),
      ],
    );
    expect(value.missing, {(sourceId: 'remote', localId: 'bad')});
    expect(value.safeMissing, isEmpty);
  });
  test('selected libraries/private descendants/photo libraries are filtered before scoring', () async {
    final remote = source(
      'remote',
      kind: MediaSourceKind.emby,
      selected: ['films'],
    );
    RemoteMediaMetadata metadata(
      String id, {
      String library = 'films',
      String? collection,
    }) => RemoteMediaMetadata(
      externalId: id,
      libraryId: library,
      collectionType: collection,
    );
    final value = await evaluate(
      [remote],
      [
        item('keep', owner: 'remote', remote: metadata('keep')),
        item(
          'other',
          owner: 'remote',
          remote: metadata('other', library: 'other'),
        ),
        item(
          'private',
          owner: 'remote',
          type: 'private',
          remote: metadata('private'),
        ),
        item(
          'hidden',
          owner: 'remote',
          parent: 'private',
          remote: metadata('hidden'),
        ),
        item(
          'photo',
          owner: 'remote',
          remote: metadata('photo', collection: 'photos'),
        ),
      ],
    );
    expect(value.inventory.items.map((i) => i.identity.localId), ['keep']);
    expect(HealthScore.fromSnapshot(value).overall, 100);
  });
  test('nested private/excluded roots do not leak metadata or duplicate candidates', () async {
    final value = await evaluate(
      [
        source('a', location: '/Media'),
        source(
          'private',
          type: SourceMediaType.privateCollection,
          location: '/Media/A',
        ),
        source('disabled', health: false, location: '/Media/Excluded'),
      ],
      [
        item('A/private.mkv'),
        item('Anime/public.mkv'),
        item('Excluded/off.mkv'),
      ],
    );
    expect(value.inventory.items.map((i) => i.identity.localId), [
      'Anime/public.mkv',
      'Excluded/off.mkv',
    ]);
    expect(value.detailGaps.keys, {
      (sourceId: 'a', localId: 'Anime/public.mkv'),
    });
    expect(value.duplicates, isEmpty);
    expect(value.configurationSources, hasLength(3));
  });
  test('ignoring detail or duplicate groups adjusts scores, preserves raw cleanup evidence', () async {
    final a = item('a.mkv'), b = item('b.mkv');
    final raw = await evaluate([source('a')], [a, b], absent: {'/a/a.mkv'});
    final ignored = raw.excluding({
      duplicateIssueKey(raw.duplicates.single),
      (kind: HealthIssueKind.detailMetadata, sourceId: 'a', localId: 'a.mkv'),
    });
    expect(ignored.duplicates, isEmpty);
    expect(ignored.detailGaps.keys, [b.identity]);
    expect(ignored.safeMissing, raw.safeMissing);
    expect(
      HealthScore.fromSnapshot(ignored).overall,
      greaterThan(HealthScore.fromSnapshot(raw).overall),
    );
  });
  test('partial Emby indexes are explicitly marked and no module data means no probes', () async {
    final value = await evaluate([
      source('remote', kind: MediaSourceKind.emby, scanned: false),
    ], []);
    expect(value.partialIndex, true);
    var probes = 0;
    final empty =
        await VideoHealthEvaluator(
          LocalHealthEvaluator(
            paths: p.Context(style: p.Style.posix),
            exists: (_) async {
              probes++;
              return true;
            },
          ),
        ).evaluate((
          sources: <MediaSource>[],
          items: <IndexedMedia>[],
        ), cancellation: ScanCancellation());
    expect(empty.inventory.sources, isEmpty);
    expect(probes, 0);
  });
  test(
    'cancelled delayed file result never publishes an advanced result',
    () async {
      final gate = Completer<bool>(),
          entered = Completer<void>(),
          cancellation = ScanCancellation();
      final pending =
          VideoHealthEvaluator(
            LocalHealthEvaluator(
              paths: p.Context(style: p.Style.posix),
              exists: (_) {
                if (!entered.isCompleted) entered.complete();
                return gate.future;
              },
            ),
          ).evaluate((
            sources: [source('a')],
            items: [item('a.mkv')],
          ), cancellation: cancellation);
      final assertion = expectLater(pending, throwsA(isA<ScanCancelled>()));
      await entered.future;
      cancellation.cancel();
      gate.complete(true);
      await assertion;
    },
  );
  test(
    'home consumes completed passive score and invalidates after index events',
    () async {
      final a = source('a'), value = snapshot(sources: [a]);
      final events = StreamController<int>();
      final container = ProviderContainer(
        overrides: [
          sidebarSourcesProvider.overrideWith((_) async => [a]),
          sourceChangesProvider.overrideWith((_) => events.stream),
          rawLibraryHealthProvider.overrideWith(
            (_) => throw StateError('home must not start evaluation'),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await events.close();
      });
      await container.read(sidebarSourcesProvider.future);
      final subscription = container.listen(
        homeRuntimeHealthProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      container.read(observedHealthProvider.notifier).record(value, 0);
      expect(container.read(homeRuntimeHealthProvider).totalScore, 100);
      events.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(homeRuntimeHealthProvider).totalScore, isNull);
    },
  );
  test('ninety-thousand remote rows do not trigger per-item I/O and cancellation yields', () async {
    final cancellation = ScanCancellation();
    var probes = 0;
    final values = List.generate(
      90000,
      (i) => item(
        '$i',
        owner: 'remote',
        remote: RemoteMediaMetadata(externalId: '$i'),
      ),
    );
    final pending =
        VideoHealthEvaluator(
          LocalHealthEvaluator(
            paths: p.Context(style: p.Style.posix),
            exists: (_) async {
              probes++;
              return true;
            },
          ),
        ).evaluate((
          sources: [source('remote', kind: MediaSourceKind.emby)],
          items: values,
        ), cancellation: cancellation);
    final assertion = expectLater(pending, throwsA(isA<ScanCancelled>()));
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    await assertion;
    expect(probes, 0);
  });
}
