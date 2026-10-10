import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/sidecar_subtitle.dart';
import 'package:reelnest/features/playback/domain/track_language_matcher.dart';
import 'package:reelnest/features/playback/presentation/player_track_popovers.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:flutter/services.dart';
import 'package:reelnest/player/video_tracks.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

VideoTrack track(
  int id, {
  String type = 'sub',
  String? language,
  String? title,
  String? filename,
  bool selected = false,
}) => VideoTrack(
  id: id,
  type: type,
  language: language,
  title: title,
  externalFilename: filename,
  external: filename != null,
  selected: selected,
);
void main() {
  group('original language policy', () {
    test('mpv Windows long-path and UNC sidecars match filesystem paths', () {
      final t = VideoTrack.fromMpv({
        'id': 3,
        'type': 'sub',
        'external': true,
        'external-filename': r'\\?\C:\media\Film.en.srt',
      });
      expect(t.externalFilename, r'C:\media\Film.en.srt');
      expect(
        normalizedSubtitlePath(r'\\?\UNC\nas\media\Film.srt'),
        r'\\nas\media\Film.srt',
      );
      expect(
        normalizedSubtitlePath('/mnt/media/Film.srt'),
        '/mnt/media/Film.srt',
      );
    });
    test('Chinese script and exact language outrank generic metadata', () {
      expect(
        TrackLanguageMatcher.best([
          track(1, language: 'zh'),
          track(2, language: 'zh-Hant'),
          track(3, language: 'zh-CN'),
        ], 'zh-CN')?.id,
        3,
      );
      expect(
        TrackLanguageMatcher.best([
          track(1, language: 'zh'),
          track(2, title: '繁體中文字幕'),
        ], 'zh-Hant')?.id,
        2,
      );
    });
    test('title and filename fallbacks do not outrank language', () {
      final tracks = [
        track(1, title: 'English commentary'),
        track(2, filename: '/subs/Film.zh-Hans.srt'),
        track(3, language: 'en'),
      ];
      expect(TrackLanguageMatcher.best(tracks, 'english')?.id, 3);
      expect(TrackLanguageMatcher.best(tracks, 'zh-Hans')?.id, 2);
    });
    test('selected track then lower ID break equal scores', () {
      expect(
        TrackLanguageMatcher.best([
          track(4, language: 'en'),
          track(5, language: 'en', selected: true),
        ], 'en')?.id,
        5,
      );
      expect(
        TrackLanguageMatcher.best([
          track(8, language: 'jpn'),
          track(6, language: 'ja'),
        ], 'japanese')?.id,
        6,
      );
    });
    test('Asian, ISO3 and language-name aliases match', () {
      for (final pair in [
        ('jpn', '日本語'),
        ('kor', 'korean'),
        ('fra', 'french'),
        ('deu', 'german'),
        ('spa', 'spanish'),
        ('vie', 'vi'),
      ]) {
        expect(
          TrackLanguageMatcher.best([track(1, language: pair.$1)], pair.$2)?.id,
          1,
        );
      }
      expect(
        TrackLanguageMatcher.best([track(1, title: '国语')], 'mandarin')?.id,
        1,
      );
    });
    test('unknown and empty language do not force a selection', () {
      expect(
        TrackLanguageMatcher.best([track(1, language: 'und')], 'klingon'),
        isNull,
      );
      expect(
        TrackLanguageMatcher.best([track(1, language: 'eng')], ' '),
        isNull,
      );
    });
    test(
      'display names retain original language, title, codec and external flag',
      () {
        expect(
          const VideoTrack(
            id: 3,
            type: 'sub',
            language: 'zh',
            title: '简体',
            codec: 'ass',
            external: true,
          ).displayName,
          'ZH · 简体 · ASS · 外挂',
        );
        expect(track(7, type: 'audio').displayName, '音轨 7');
      },
    );
  });

  late Directory sandbox;
  late SourceRepository sources;
  late PlaybackSession session;
  late PlayerPreferencesRepository preferences;
  late MediaIdentity film;
  late MediaSource source;
  var resourcesClosed = false;
  final engines = <FakeVideoEngine>[];
  var seed = const VideoTrackState();
  setUp(() async {
    resourcesClosed = false;
    seed = VideoTrackState(
      audio: [
        track(1, type: 'audio', language: 'eng'),
        track(2, type: 'audio', language: 'jpn'),
      ],
      subtitles: [
        track(1, language: 'eng'),
        track(2, language: 'zh-CN'),
      ],
      audioId: 1,
      subtitleId: 1,
    );
    engines.clear();
    sandbox = await Directory.systemTemp.createTemp('reelnest-tracks-test-');
    await File(p.join(sandbox.path, 'Film.mkv')).writeAsString('fake decoder');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Test',
      location: sandbox.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    film = (sourceId: source.id, localId: 'Film.mkv');
    preferences = PlayerPreferencesRepository(sources.database);
    session = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      preferences: preferences,
      createEngine: () {
        final engine = FakeVideoEngine()..trackState = seed;
        engines.add(engine);
        return engine;
      },
    );
  });
  tearDown(() async {
    if (!resourcesClosed) {
      await session.close();
      session.dispose();
      await sources.close();
    }
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-tracks-test-'));
    await sandbox.delete(recursive: true);
  });
  test(
    'sidecars match base, separator suffix or generic subtitle names only',
    () async {
      for (final name in [
        'Film.srt',
        'Film.zh-Hans.ass',
        'Film-2.ssa',
        'Film-10.ssa',
        'subtitles.en.vtt',
        'Other.srt',
        'Film2.srt',
        '.Film.srt',
        'Film.sub',
      ]) {
        await File(p.join(sandbox.path, name)).writeAsString('subtitle');
      }
      final found = await SidecarSubtitle.find(
        p.join(sandbox.path, 'Film.mkv'),
      );
      expect(found.map((s) => s.displayName), [
        'Film.srt',
        'Film-2.ssa',
        'Film-10.ssa',
        'Film.zh-Hans.ass',
        'subtitles.en.vtt',
      ]);
      expect(found.last.languageHint, '英文');
      expect(found[3].languageHint, '中文');
      expect(
        await SidecarSubtitle.find(p.join(sandbox.path, 'absent', 'Film.mkv')),
        isEmpty,
      );
    },
  );
  test(
    'default Chinese preference and explicit selection persist across reopen',
    () async {
      await session.open(film);
      expect(session.tracks.value.subtitleId, 2);
      await session.selectAudio(2);
      await session.selectSubtitle(null);
      expect(await preferences.audio(session.item!), 'jpn');
      expect(
        await preferences.subtitle(session.item!),
        PlayerPreferencesRepository.subtitleOff,
      );
      await session.open(film);
      expect(session.tracks.value.audioId, 2);
      expect(session.tracks.value.subtitleId, isNull);
    },
  );
  test(
    'preferences share parent but remain isolated by source and movie',
    () async {
      final movie = await sources.media(film);
      IndexedMedia withIdentity(
        String sourceId,
        String localId,
        String? parent,
      ) => IndexedMedia(
        identity: (sourceId: sourceId, localId: localId),
        title: 'Test',
        type: 'episode',
        bytes: 0,
        modified: movie.modified,
        parentId: parent,
      );
      final one = withIdentity(source.id, 'one', 'series');
      final two = withIdentity(source.id, 'two', 'series');
      await preferences.rememberAudio(one, '  ja-JP  ');
      await preferences.rememberSubtitle(
        one,
        PlayerPreferencesRepository.subtitleOff,
      );
      expect(await preferences.audio(two), 'ja-JP');
      expect(
        await preferences.subtitle(two),
        PlayerPreferencesRepository.subtitleOff,
      );
      expect(
        await preferences.audio(withIdentity('other-source', 'two', 'series')),
        isNull,
      );
      expect(
        await preferences.audio(withIdentity(source.id, 'two', 'other-series')),
        isNull,
      );
      await preferences.rememberAudio(two, ' ');
      expect(await preferences.audio(one), isNull);
      await preferences.rememberSubtitle(movie, 'en');
      expect(
        await preferences.subtitle(withIdentity(source.id, 'Other.mkv', null)),
        isNull,
      );
    },
  );
  test(
    'manual selection is not overwritten by a later metadata refresh',
    () async {
      await session.open(film);
      await session.selectSubtitle(1);
      await session.refreshTracks();
      expect(session.tracks.value.subtitleId, 1);
      expect(await preferences.subtitle(session.item!), 'eng');
    },
  );
  test(
    'second subtitle excludes primary and is cleared on promotion',
    () async {
      await session.open(film);
      await session.selectSecondarySubtitle(1);
      expect(session.tracks.value.secondarySubtitleId, 1);
      await session.selectSecondarySubtitle(2);
      expect(session.controlError, isNotNull);
      expect(session.tracks.value.secondarySubtitleId, 1);
      await session.selectSubtitle(1);
      expect(session.tracks.value.subtitleId, 1);
      expect(session.tracks.value.secondarySubtitleId, isNull);
    },
  );
  test(
    'existing external subtitles are selected without duplicate loads',
    () async {
      final file = p.join(sandbox.path, 'Film.en.srt');
      await File(file).writeAsString('subtitle');
      seed = VideoTrackState(
        subtitles: [track(1, filename: file, language: 'en')],
      );
      await session.open(film);
      await session.addSubtitle(file);
      expect(engines.single.addedSubtitles, isEmpty);
      expect(session.tracks.value.subtitleId, 1);
    },
  );
  test(
    'failed track selection preserves preferences, decoder and progress',
    () async {
      await session.open(film);
      engines.single.failControl = true;
      await session.selectAudio(2);
      expect(session.controlError, isNotNull);
      expect(session.error, isNull);
      expect(await preferences.audio(session.item!), isNull);
      expect(engines.single.disposals, 0);
      await session.seek(const Duration(seconds: 40));
      await session.save();
      expect((await session.records.read(film)).position.inSeconds, 40);
      engines.single.failControl = false;
      await session.selectAudio(2);
      expect(session.controlError, isNull);
      expect(session.tracks.value.audioId, 2);
    },
  );
  test(
    'subtitle delay and volume enhancement clamp, persist and reload',
    () async {
      await session.open(film);
      await session.subtitleDelay(8);
      expect(session.tracks.value.subtitleDelay, 3);
      await session.subtitleDelay(-.16);
      expect(session.tracks.value.subtitleDelay, -.2);
      await session.volumeBoost(8);
      expect(session.tracks.value.volumeBoost, 2);
      await session.volume(35);
      await session.mute();
      expect(session.clock.volume, 0);
      await session.mute();
      expect(session.clock.volume, 40); // Original unmute lower bound.
      await session.open(film);
      expect(session.clock.volume, 40);
      expect(session.tracks.value.subtitleDelay, -.2);
      expect(session.tracks.value.volumeBoost, 2);
    },
  );
  test('missing audio and subtitle tracks are valid playback', () async {
    seed = const VideoTrackState();
    await session.open(film);
    expect(session.error, isNull);
    expect(session.clock.playing, isTrue);
    await session.selectAudio(99);
    expect(session.controlError, isNotNull);
    expect(session.error, isNull);
  });
  testWidgets(
    'subtitle panel selects internal tracks, delay and bilingual rows',
    (tester) async {
      Future<void> finish(Future<void> future) async {
        var done = false;
        Object? failure;
        future.then(
          (_) => done = true,
          onError: (Object e) {
            failure = e;
            done = true;
          },
        );
        for (var i = 0; i < 200 && !done; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done, isTrue);
        if (failure != null) throw failure!;
      }

      try {
        await finish(session.open(film));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: PlayerTrackPopover(
                    panel: PlayerPanel.subtitles,
                    session: session,
                    palette: const PlayerPalette(),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('内嵌字幕'), findsOneWidget);
        expect(find.text('第二字幕（双语对照）'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('subtitle-1')));
        await finish(session.refreshTracks());
        expect(session.tracks.value.subtitleId, 1);
        await tester.tap(find.byTooltip('增加'));
        await finish(session.refreshTracks());
        expect(session.tracks.value.subtitleDelay, .1);
        await tester.tap(find.byKey(const ValueKey('subtitle-off')));
        await finish(session.refreshTracks());
        expect(session.tracks.value.subtitleId, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await finish(session.close());
        await tester.pumpWidget(const SizedBox());
        session.dispose();
        await finish(sources.close());
        resourcesClosed = true;
      }
    },
  );
  testWidgets('audio empty state and volume output controls fit their widths', (
    tester,
  ) async {
    Future<void> finish(Future<void> future) async {
      var done = false;
      future.then((_) => done = true);
      for (var i = 0; i < 200 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done, isTrue);
    }

    try {
      seed = const VideoTrackState();
      await finish(session.open(film));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: PlayerTrackPopover(
                  panel: PlayerPanel.audio,
                  session: session,
                  palette: const PlayerPalette(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('播放器暂未回传音轨列表。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 338,
                child: PlayerTrackPopover(
                  panel: PlayerPanel.volume,
                  session: session,
                  palette: const PlayerPalette(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('video-volume')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('boost-1.5')));
      await finish(session.refreshTracks());
      expect(session.tracks.value.volumeBoost, 1.5);
      await tester.tap(find.byTooltip('输出设备'));
      await tester.pumpAndSettle();
      expect(find.text('系统默认'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await finish(session.close());
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await finish(sources.close());
      resourcesClosed = true;
    }
  });
  testWidgets('toolbar popover stays open and Escape only dismisses panel', (
    tester,
  ) async {
    Future<void> finish(Future<void> future) async {
      var done = false;
      future.then((_) => done = true);
      for (var i = 0; i < 200 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done, isTrue);
    }

    var closed = false;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            identity: film,
            session: session,
            closeWindow: () async {
              closed = true;
            },
            setFullscreen: (_) async {},
          ),
        ),
      );
      for (
        var i = 0;
        i < 200 && (session.loading || session.clock.duration == Duration.zero);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(session.error, isNull);
      expect(session.clock.duration, isNot(Duration.zero));
      await tester.pump(); // Render controls after the paused surface commit.
      await tester.tap(find.byTooltip('音轨'));
      await tester.pump();
      await finish(session.refreshTracks());
      expect(find.byKey(const ValueKey('audio-2')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('audio-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audio-2')));
      await finish(session.refreshTracks());
      expect(session.tracks.value.audioId, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('audio-2')), findsNothing);
      expect(closed, isFalse);
      await tester.tap(find.byTooltip('音量'));
      await tester.pump();
      expect(find.byKey(const ValueKey('video-volume')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    } finally {
      await finish(session.close());
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await finish(sources.close());
      resourcesClosed = true;
    }
  });
}
