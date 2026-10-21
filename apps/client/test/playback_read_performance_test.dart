import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/video_queue.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/query_counter.dart';

void main() {
  late LibraryDatabase db;
  late SourceRepository sources;
  late PlayerPreferencesRepository preferences;
  late QueryCounter counter;
  setUp(() async {
    counter = QueryCounter();
    db = LibraryDatabase(NativeDatabase.memory().interceptWith(counter));
    sources = SourceRepository(database: db, adapters: {});
    preferences = PlayerPreferencesRepository(db);
    for (final id in ['a', 'b']) {
      await db.customStatement(
        '''INSERT INTO sources
        (id,kind,name,location,location_key,recursive,ignore_hidden,created_at,updated_at)
        VALUES (?, 'localFolder', ?, ?, ?, 1, 1, 0, 0)''',
        [id, id, id, id],
      );
    }
    counter.reads.clear();
  });
  tearDown(() => sources.close());

  Future<void> insert(
    String id, {
    String source = 'a',
    String? parent,
    bool series = false,
    String type = 'episode',
    int? season,
    int? episode,
    String? title,
  }) => db.customStatement(
    '''INSERT INTO media
      (source_id,local_id,title,type,bytes,modified,is_series,identity_kind,parent_id,season_number,episode_number)
      VALUES (?,?,?,?,10,0,?,'fixture',?,?,?)''',
    [source, id, title ?? id, type, series ? 1 : 0, parent, season, episode],
  );

  test('queue candidates match full inventory for cross-source roots, seasons and fallback', () async {
    await insert('show', series: true);
    await insert('ep2', parent: 'show', episode: 2);
    await insert('ep1', parent: 'show', episode: 1);
    await insert('special', parent: 'show', season: 0, episode: 1);
    await insert('next-season', parent: 'show', season: 2, episode: 1);
    await insert('show', source: 'b', series: true);
    await insert('ep1', source: 'b', parent: 'show');
    // Same titles exercise deterministic tie ordering across sources.
    await insert('z-movie', type: 'movie', title: 'Film');
    await insert('a-movie', source: 'b', type: 'movie', title: 'Film');
    await insert('photo', type: 'photo');
    await insert('song', type: 'music');
    await insert('not-series');
    await insert('orphan', parent: 'not-series');
    await db.customStatement(
      "INSERT INTO media_activity VALUES('b','a-movie',999)",
    );
    final all = (await sources.inventory()).items;
    for (final item in all.where((i) => !i.isSeries)) {
      final expected = VideoQueue.forItem(item, all);
      final actual = VideoQueue.forItem(
        item,
        await sources.playbackQueueCandidates(item),
      );
      expect(
        actual.sequence.map((i) => i.identity),
        expected.sequence.map((i) => i.identity),
      );
      expect(
        actual.items.map((i) => i.identity),
        expected.items.map((i) => i.identity),
      );
      for (final direction in [-1, 1]) {
        expect(
          actual.adjacent(item.identity, direction)?.identity,
          expected.adjacent(item.identity, direction)?.identity,
        );
      }
    }
  });

  test('90k unrelated episodes never cross SQLite for an episode or root queue', () async {
    await insert('show', series: true);
    await insert('ep1', parent: 'show', episode: 1);
    await insert('ep2', parent: 'show', episode: 2);
    await insert('other-show', source: 'b', series: true);
    await insert('film', type: 'movie');
    await insert('film', source: 'b', type: 'movie');
    await db.customStatement(
      '''WITH RECURSIVE n(i) AS
      (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i < 90000)
      INSERT INTO media(source_id,local_id,title,type,bytes,modified,is_series,identity_kind,parent_id)
      SELECT 'b','unrelated-'||i,'Episode '||i,'episode',10,0,0,'fixture','other-show' FROM n''',
    );
    await db.customStatement(
      "INSERT INTO remote_media_metadata SELECT source_id,local_id,json_object('externalId',local_id) FROM media",
    );
    final current = await sources.media((sourceId: 'a', localId: 'ep1'));
    final root = await sources.media((sourceId: 'a', localId: 'film'));
    counter.reads.clear();
    final before = Stopwatch()..start();
    final inventory = await sources.inventory();
    before.stop();
    final expected = VideoQueue.forItem(current, inventory.items);
    expect(counter.reads.any((r) => r.rows >= 90000), isTrue);
    counter.reads.clear();
    final after = Stopwatch()..start();
    final candidates = await sources.playbackQueueCandidates(current);
    after.stop();
    expect(candidates.length, 3);
    expect(counter.reads.fold<int>(0, (n, r) => n + r.rows), 3);
    expect(
      VideoQueue.forItem(current, candidates).items.map((i) => i.identity),
      expected.items.map((i) => i.identity),
    );
    counter.reads.clear();
    expect((await sources.playbackQueueCandidates(root)).length, 2);
    expect(counter.reads.fold<int>(0, (n, r) => n + r.rows), 2);
    // Informational only: no timing assertion on shared CI hardware.
    // ignore: avoid_print
    print(
      '90k fixture: inventory=${before.elapsedMilliseconds}ms; episode candidates=${after.elapsedMilliseconds}ms; rows 90006 -> 3',
    );
  });

  IndexedMedia item(String source, String local, {String? parent}) =>
      IndexedMedia(
        identity: (sourceId: source, localId: local),
        title: local,
        type: 'episode',
        bytes: 1,
        modified: DateTime.utc(2026),
        parentId: parent,
      );

  Future<void> readAll(IndexedMedia media) async {
    await preferences.options;
    await preferences.subtitleStyle;
    await preferences.timing;
    await preferences.displaySettings;
    await preferences.renderSettings;
    await preferences.performanceSettings;
    await preferences.sharpenMode;
    await preferences.colorAdjustments;
    await preferences.loopCurrentItem;
    await preferences.markerSkipBehavior;
    await preferences.audio(media);
    await preferences.subtitle(media);
    await preferences.subtitleLanguage;
    await preferences.endAction;
    await preferences.rate(media);
    await preferences.number('videoVolume', 80);
    await preferences.number('videoVolumeBoost', 1);
  }

  test('all playback preferences use one read, and each open sees fresh series/source values', () async {
    final a = item('a', 'ep1', parent: 'show'),
        sibling = item('a', 'ep2', parent: 'show'),
        other = item('b', 'ep1', parent: 'show');
    await preferences.rememberAudio(a, 'en');
    await preferences.rememberSubtitle(
      a,
      PlayerPreferencesRepository.subtitleOff,
    );
    await preferences.rememberRate(a, 1.5);
    await preferences.rememberNumber('videoVolume', 60);
    counter.reads.clear();
    await readAll(a);
    final separateReads = counter.reads.length;
    expect(separateReads, greaterThan(20));
    counter.reads.clear();
    await preferences.readPlaybackSnapshot(sibling, () async {
      await readAll(sibling);
      expect(await preferences.audio(sibling), 'en');
      expect(
        await preferences.subtitle(sibling),
        PlayerPreferencesRepository.subtitleOff,
      );
      expect(await preferences.rate(sibling), 1.5);
    });
    expect(counter.reads.length, 1);
    await preferences.rememberAudio(a, 'ja');
    await preferences.readPlaybackSnapshot(a, () async {
      expect(await preferences.audio(a), 'ja');
    });
    await preferences.readPlaybackSnapshot(other, () async {
      expect(await preferences.audio(other), isNull);
      expect(await preferences.rate(other), isNull);
    });
    // ignore: avoid_print
    print('playback preference SQLite reads: $separateReads -> 1');
  });

  test('snapshot is consistent, expires for async descendants and preserves malformed-value fallbacks', () async {
    final media = item('a', 'film');
    await preferences.rememberNumber('videoVolume', 40);
    for (final key in [
      'videoSubtitleStyle',
      'videoColorAdjustments',
      'videoPerformanceSettings',
      'videoRenderSettings',
    ]) {
      await db.customStatement('INSERT INTO player_preferences VALUES(?,?)', [
        'global.$key',
        '{invalid',
      ]);
    }
    final resume = Completer<void>();
    late Future<double> escaped;
    await preferences.readPlaybackSnapshot(media, () async {
      expect(await preferences.number('videoVolume', 80), 40);
      // Simulate a concurrently saved setting after the snapshot's SELECT.
      await db.customStatement(
        "UPDATE player_preferences SET value='70' WHERE key='global.videoVolume'",
      );
      expect(await preferences.number('videoVolume', 80), 40);
      await readAll(media);
      escaped = () async {
        await resume.future;
        return preferences.number('videoVolume', 80);
      }();
    });
    resume.complete();
    expect(await escaped, 70);
    expect(await preferences.number('videoVolume', 80), 70);
    // Corrupt playbackOptions kept its original fatal read behavior, too.
    await db.customStatement('INSERT INTO player_preferences VALUES(?,?)', [
      'global.playbackOptions',
      jsonEncode([]),
    ]);
    await expectLater(
      preferences.readPlaybackSnapshot(media, () => preferences.options),
      throwsA(anything),
    );
    await preferences.rememberNumber('videoVolume', 90);
    expect(await preferences.number('videoVolume', 80), 90);
  });
}
