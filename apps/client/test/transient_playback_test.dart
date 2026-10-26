import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/application/transient_playback_providers.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/transient_playback_target.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

void main() {
  late Directory sandbox;
  late SourceRepository sources;
  late PlaybackRepository records;
  late PlaybackSession session;
  final engines = <FakeVideoEngine>[];
  var failNext = false;
  setUp(() async {
    engines.clear();
    failNext = false;
    sandbox = await Directory.systemTemp.createTemp('reelnest-transient-');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture',
    );
    records = PlaybackRepository(sources.database);
    session = PlaybackSession(
      sources: sources,
      records: records,
      createEngine: () {
        final engine = FakeVideoEngine()..failOpen = failNext;
        engines.add(engine);
        failNext = false;
        return engine;
      },
    );
  });
  tearDown(() async {
    await session.close(discardProgress: true);
    session.dispose();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-transient-'));
    await sandbox.delete(recursive: true);
  });
  Future<File> file(String name) =>
      File(p.join(sandbox.path, name)).writeAsString('decoder fixture');
  Future<int> count(String table) async =>
      (await sources.database
              .customSelect('SELECT COUNT(*) AS n FROM $table')
              .getSingle())
          .read<int>('n');

  test('stream whitelist, safe opaque identity, and memory-only transport', () {
    for (final scheme in TransientPlaybackTarget.streamSchemes) {
      final target = TransientPlaybackTarget.stream(
        '  $scheme://user:password@example.test/Film.mp4?token=private  ',
      );
      expect(target.item.title, 'Film.mp4');
      expect(
        jsonEncode(target.identity.toString()),
        isNot(contains('password')),
      );
      expect(target.toString(), 'TransientPlaybackTarget');
      final restored = TransientPlaybackTarget.fromJson(target.toJson());
      expect(restored.identity, target.identity);
      expect(restored.location, target.location);
    }
    for (final value in [
      '',
      'file:///secret.mp4',
      'javascript:alert(1)',
      'https://',
      'https://host/a\nsecret',
      'https://host:bad/a',
    ]) {
      expect(
        () => TransientPlaybackTarget.stream(value),
        throwsA(isA<SourceFailure>()),
      );
    }
    final bookmark = Uint8List.fromList([1, 2, 3]);
    final target = TransientPlaybackTarget.file(
      p.join(sandbox.path, 'Film.mkv'),
    ).withBookmark(bookmark);
    expect(
      TransientPlaybackTarget.fromJson(target.toJson()).securityBookmark,
      bookmark,
    );
    expect(
      () => TransientPlaybackTarget.fromJson({
        'kind': 'stream',
        'id': 'https://secret',
        'location': 'https://host/a',
      }),
      throwsA(isA<SourceFailure>()),
    );
  });

  test(
    'unknown local video and markers remain entirely outside the library',
    () async {
      final video = await file('Film.mkv');
      await file('Film.zh.srt');
      final target = TransientPlaybackTarget.file(video.path);
      await session.openTransient(target);
      expect(session.lastOpenSucceeded, isTrue);
      expect(session.transient, isTrue);
      expect(session.filePath, video.path);
      expect(session.sidecarSubtitles.single.displayName, 'Film.zh.srt');
      expect(session.queue.items.single.identity, target.identity);
      expect(session.queue.sequence.length, 1);
      expect(session.qualityOptions, isEmpty);
      engines.single.emit(position: const Duration(seconds: 35));
      await session.save();
      await session.rate(1.5);
      await session.addBookmark();
      expect(session.precision.value.bookmarks, hasLength(1));
      await session.refreshQueue();
      await session.adjacent(1);
      expect(session.engine, same(engines.single));
      for (final table in [
        'sources',
        'media',
        'playback_states',
        'media_activity',
        'playback_markers',
      ]) {
        expect(await count(table), 0, reason: table);
      }
      final preferences = await sources.database
          .customSelect('SELECT key,value FROM player_preferences')
          .get();
      expect(
        preferences.map((r) => r.read<String>('key')).join(),
        isNot(contains(video.path)),
      );
      expect(
        await PlayerPreferencesRepository(sources.database)
            .rate(TransientPlaybackTarget.file(video.path).item),
        1.5,
      );
      await session.close();
      expect(session.precision.value.markers, isEmpty);
    },
  );

  test(
    'indexed external file reuses identity, resume and episode queue',
    () async {
      final series = Directory(p.join(sandbox.path, 'Series'));
      await series.create();
      await File(p.join(series.path, 'Series S01E01.mkv'))
          .writeAsString('fixture');
      await File(p.join(series.path, 'Series S01E02.mkv'))
          .writeAsString('fixture');
      final source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Library',
        location: sandbox.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      final library = await sources.database
          .customSelect(
            "SELECT local_id FROM media WHERE is_series=0 ORDER BY local_id",
          )
          .get();
      final identity = (
        sourceId: source.id,
        localId: library.first.read<String>('local_id'),
      );
      await records.save(
        identity,
        position: const Duration(seconds: 40),
        duration: const Duration(seconds: 100),
      );
      await session.openTransient(
        TransientPlaybackTarget.file(
          p.joinAll([sandbox.path, ...p.posix.split(identity.localId)]),
        ),
      );
      expect(session.transient, isFalse);
      expect(session.item!.identity, identity);
      expect(engines.single.openedAt, greaterThan(Duration.zero));
      expect(session.queue.sequence, hasLength(2));
    },
  );

  test(
    'stream playback does not persist URL or acquire Emby features',
    () async {
      final target = TransientPlaybackTarget.stream(
        'https://user:password@example.test/Film.mp4?api_key=secret',
      );
      await session.openTransient(target);
      expect(session.error, isNull);
      expect(engines.single.openedPath, target.location);
      expect(session.filePath, isNull);
      expect(session.qualityOptions, isEmpty);
      engines.single.emit(position: const Duration(seconds: 25));
      await session.save();
      await session.close();
      expect(await count('media'), 0);
      expect(await count('playback_states'), 0);
      final rows = await sources.database
          .customSelect('SELECT key,value FROM player_preferences')
          .get();
      expect(rows.map((r) => '${r.data}').join(), isNot(contains('secret')));
    },
  );

  test(
    'failed replacement preserves playing decoder and temporary marker state',
    () async {
      final first = TransientPlaybackTarget.file(
        (await file('First.mkv')).path,
      );
      await session.openTransient(first);
      await session.addBookmark();
      failNext = true;
      await session.openTransient(
        TransientPlaybackTarget.file((await file('Second.mkv')).path),
      );
      expect(session.lastOpenSucceeded, isFalse);
      expect(session.item!.identity, first.identity);
      expect(session.engine, same(engines.first));
      expect(engines.first.disposals, 0);
      expect(engines.last.disposals, 1);
      expect(session.clock.playing, isTrue);
      expect(session.precision.value.bookmarks, hasLength(1));
      expect(session.error, isNull);
    },
  );

  test(
    'initial failed temporary request can retry with its original resource',
    () async {
      final target = TransientPlaybackTarget.file(
        (await file('Retry.mkv')).path,
      );
      failNext = true;
      await session.openTransient(target);
      expect(session.error, isNotNull);
      await session.open(target.identity);
      expect(session.lastOpenSucceeded, isTrue);
      expect(engines.last.openedPath, target.location);
      expect(session.error, isNull);
    },
  );

  test(
    'remote decoder errors never expose temporary stream credentials',
    () async {
      await session.openTransient(
        TransientPlaybackTarget.stream(
          'https://user:password@example.test/Film.mp4?token=private',
        ),
      );
      engines.single.emit(
        error: 'Cannot read https://user:password@example.test/Film.mp4?token=private',
      );
      expect(session.error, isNotNull);
      expect(session.error, isNot(contains('password')));
      expect(session.error, isNot(contains('private')));
      expect(await count('playback_states'), 0);
    },
  );

  test('only HTTP temporary streams expose network rate capability', () async {
    for (final scheme in ['https', 'rtsp', 'ftp']) {
      await session.openTransient(
        TransientPlaybackTarget.stream('$scheme://host/Film.mp4'),
      );
      expect(session.lastOpenSucceeded, isTrue);
      expect(session.httpStream, scheme == 'https');
    }
    await session.openTransient(
      TransientPlaybackTarget.file((await file('Local.mkv')).path),
    );
    expect(session.httpStream, isFalse);
  });

  test('temporary track and rate preferences survive a fresh repository without storing URLs', () async {
    const url =
        'https://user:private-password@example.test/Film.mp4?token=private-token';
    final target = TransientPlaybackTarget.stream(url);
    final first = PlayerPreferencesRepository(sources.database);
    await first.rememberAudio(target.item, 'en');
    await first.rememberSubtitle(
      target.item,
      PlayerPreferencesRepository.subtitleOff,
    );
    await first.rememberRate(target.item, 1.5);
    final reopened = PlayerPreferencesRepository(sources.database);
    final same = TransientPlaybackTarget.stream('  $url  ');
    expect(same.identity, target.identity);
    expect(await reopened.audio(same.item), 'en');
    expect(
      await reopened.subtitle(same.item),
      PlayerPreferencesRepository.subtitleOff,
    );
    expect(await reopened.rate(same.item), 1.5);
    final rows = await sources.database
        .customSelect('SELECT key,value FROM player_preferences')
        .get();
    final text = rows.map((r) => r.data.toString()).join();
    expect(text, isNot(contains('private-password')));
    expect(text, isNot(contains('private-token')));
    expect(text, isNot(contains('example.test')));
    expect(await count('media'), 0);
    expect(await count('playback_states'), 0);
  });

  test(
    'launcher reuses indexed identity and serializes temporary requests',
    () async {
      final video = await file('Indexed.mp4');
      final source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Library',
        location: sandbox.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      final calls = <String>[];
      final launcher = TransientPlaybackService(
        sources: sources,
        openLibrary: (id) async {
          calls.add(id.sourceId);
        },
        openTransient: (target) async {
          await Future<void>.delayed(Duration.zero);
          calls.add(target.item.title);
        },
      );
      await launcher.openFile(video.path);
      expect(calls, [source.id]);
      final first = launcher.openStream('https://host/First.mp4');
      final second = launcher.openStream('https://host/Second.mp4');
      await Future.wait([first, second]);
      expect(calls.skip(1), ['First.mp4', 'Second.mp4']);
      await expectLater(
        launcher.openFile(sandbox.path),
        throwsA(isA<SourceFailure>()),
      );
      await launcher.openStream('https://host/Third.mp4');
      expect(calls.last, 'Third.mp4');
    },
  );
}
