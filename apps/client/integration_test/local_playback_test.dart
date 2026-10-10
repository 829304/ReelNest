import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/presentation/player_window_app.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/domain/video_queue.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_cache_repository.dart';
import 'package:reelnest/api/emby/emby_quality.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/emby_detail_repository.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/platform/secure_credential_store.dart';

import '../test/support/video_fixture.dart';
import '../test/support/track_video_fixture.dart';
import '../test/support/emby_server_fixture.dart';

SourceRepository repository(String path) => SourceRepository(
  database: LibraryDatabase(NativeDatabase.createInBackground(File(path))),
  adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
);

Future<void> startPlayer() async {
  await windowManager.ensureInitialized();
  final current = await WindowController.fromCurrentEngine();
  final args = jsonDecode(current.arguments) as Map<String, dynamic>;
  runApp(
    ProviderScope(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(
          repository(args['testDatabase'] as String),
        ),
      ],
      child: PlayerWindowApp(window: current, arguments: args),
    ),
  );
}

// Run with flutter drive: flutter test's generated listener waits for a suite
// command in every engine, so it cannot boot a separate application window.
void main(List<String> entryArguments) {
  if (entryArguments.isNotEmpty && entryArguments.first == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    startPlayer();
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Emby connection persists isolated credentials and restores a session',
    (tester) async {
      final fixture = EmbyServerFixture();
      await fixture.start();
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-native-emby-',
      );
      final sources = repository(p.join(sandbox.path, 'library.sqlite'));
      final client = EmbyClient(
        deviceId: await embyDeviceIdentity(sources.database),
      );
      final prefix =
          'io.github.user829304.reelnest.test.emby.${newEmbyIdentity()}';
      final keys = <String>{};
      SecureCredentialStore store(String id) {
        keys.add(id);
        return SecureCredentialStore(key: '$prefix.$id');
      }

      final connections = EmbyConnectionRepository(
        sources: sources,
        client: Future.value(client),
        stores: store,
      );
      try {
        final source = await connections.connect(
          fixture.address,
          'tester',
          'test password',
        );
        expect((await store(source.id).read()), contains('token-1'));
        final restored = EmbyConnectionRepository(
          sources: sources,
          client: Future.value(client),
          stores: store,
        );
        try {
          expect((await restored.session(source.id)).userId, 'user-1');
          fixture.validToken = 'expired';
          expect(await restored.libraries(source.id), hasLength(2));
          expect(fixture.loginCount, 2);
          await restored.selectLibraries(
            source.id,
            all: false,
            selected: ['movies'],
          );
          expect(
            (await sources.source(source.id)).options.selectedEmbyLibraryIDs,
            ['movies'],
          );
          fixture.catalog['movies'] = [
            {
              'Id': 'native-movie',
              'Name': 'Native movie',
              'Type': 'Movie',
              'Overview': 'Local HTTP fixture',
              'ProductionYear': 2024,
              'ImageTags': {'Primary': 'fixture'},
              'RunTimeTicks': 240000000,
              'MediaSources': [
                {'Id': 'native-resource', 'Container': 'avi'},
              ],
              'UserData': {'PlaybackPositionTicks': 120000000},
            },
          ];
          final synchronizer = EmbySyncRepository(
            sources: sources,
            connections: restored,
          );
          expect((await synchronizer.synchronize(source.id)).importedItems, 1);
          final imported = (await sources.browse(source.id)).items.single;
          expect(imported.remote!.externalId, 'native-movie');
          expect(imported.overview, 'Local HTTP fixture');
          expect(
            (await restored.artwork(source.id, imported.posterPath!)).take(4),
            [137, 80, 78, 71],
          );
          final video = await createVideoFixture(
            p.join(sandbox.path, 'remote.avi'),
          );
          final ranges = <String>[];
          fixture.detailHandler = (request) async {
            request.response.write(
              jsonEncode({
                'Id': imported.remote!.externalId,
                'People': [
                  {'Id': 'native-actor', 'Name': '测试演员', 'Type': 'Actor'},
                ],
                'BackdropImageTags': ['native-backdrop'],
                'OfficialRating': 'PG-13',
                'MediaSources': [
                  {
                    'Id': 'native-resource',
                    'MediaStreams': [
                      {
                        'Type': 'Video',
                        'Codec': 'mpeg4',
                        'Width': 64,
                        'Height': 64,
                      },
                      {
                        'Type': 'Subtitle',
                        'Index': 2,
                        'Codec': 'srt',
                        'Language': 'zho',
                        'DisplayTitle': '服务器中文字幕',
                      },
                    ],
                  },
                ],
              }),
            );
            await request.response.close();
          };
          final details = EmbyDetailRepository(
            sources: sources,
            connections: restored,
          );
          final snapshot = await details.load(imported.identity);
          expect(snapshot.detail.cast.single.name, '测试演员');
          final browser = EmbyLibraryRepository(sources);
          final requestsBeforeBrowsing = fixture.requests.length;
          await browser.setWatchlist(imported.identity, true);
          final cachedBrowser = await browser.snapshot(source.id);
          expect(cachedBrowser.libraries.map((v) => v.id), contains('movies'));
          final listed = cachedBrowser.scope((
            sourceId: source.id,
            section: EmbyVideoSection.watchlist,
            libraryId: null,
          ));
          expect(
            filterVideoLibrary(
              listed,
              const VideoLibrarySettings(search: 'csyy'),
              .9,
            ).single.item.identity,
            imported.identity,
          );
          expect(fixture.requests.length, requestsBeforeBrowsing);
          expect(snapshot.detail.technical.resolution, '64x64');
          expect(
            (await details.read(imported.identity))!.detail.contentRating,
            'PG-13',
          );
          fixture.streamHandler = (request) async {
            final response = request.response;
            if (request.uri.path.contains('/Subtitles/')) {
              response.headers.contentType = ContentType(
                'text',
                'plain',
                charset: 'utf-8',
              );
              response.write(
                '1\n00:00:01,000 --> 00:00:23,000\nEmby subtitle fixture\n',
              );
              await response.close();
              return;
            }
            final length = await video.length();
            response.headers.contentType = ContentType('video', 'x-msvideo');
            response.headers.set('Accept-Ranges', 'bytes');
            var start = 0, end = length - 1;
            final range = request.headers.value(HttpHeaders.rangeHeader);
            if (range != null) {
              ranges.add(range);
              final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
              if (match != null) {
                start = int.parse(match[1]!);
                if (match[2]!.isNotEmpty) {
                  end = int.parse(match[2]!).clamp(start, length - 1);
                }
                if (start >= length) {
                  response.statusCode = 416;
                  await response.close();
                  return;
                }
                response.statusCode = 206;
                response.headers.set(
                  'Content-Range',
                  'bytes $start-$end/$length',
                );
              }
            }
            response.contentLength = end - start + 1;
            try {
              if (request.method != 'HEAD') {
                await response.addStream(video.openRead(start, end + 1));
              }
              await response.close();
            } on SocketException {
              // mpv cancels an in-flight Range request when seeking/closing.
            } on HttpException {
              // The decoder may have enough bytes before the request completes.
            }
          };
          MediaKit.ensureInitialized();
          final session = PlaybackSession(
            sources: sources,
            records: PlaybackRepository(sources.database),
            emby: restored,
            createEngine: MediaKitVideoEngine.new,
          );
          try {
            await tester.pumpWidget(
              MaterialApp(
                home: VideoPlayerPage(
                  identity: imported.identity,
                  session: session,
                  closeWindow: () async {},
                  setFullscreen: (_) async {},
                ),
              ),
            );
            for (
              var n = 0;
              n < 300 && (session.loading || session.engine == null);
              n++
            ) {
              await tester.pump();
              await Future<void>.delayed(const Duration(milliseconds: 100));
              if (session.error != null) break;
            }
            expect(session.loading, isFalse);
            expect(session.error, isNull);
            expect(session.clock.duration.inSeconds, 24);
            expect(session.clock.position.inSeconds, greaterThanOrEqualTo(6));
            await session.seek(const Duration(seconds: 14));
            final deadline = DateTime.now().add(const Duration(seconds: 5));
            while (session.clock.position.inSeconds < 13 &&
                DateTime.now().isBefore(deadline)) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(session.clock.position.inSeconds, greaterThanOrEqualTo(13));
            await session.toggle();
            await session.refreshServerSubtitles();
            expect(session.serverSubtitles.single.displayName, '服务器中文字幕');
            await session.selectServerSubtitle('native-resource:2');
            expect(session.subtitleError, isNull);
            final subtitlePath = session.serverSubtitlePaths.values.single;
            final subtitleTrack = session.engine!.tracks.subtitles.singleWhere(
              (track) =>
                  track.externalFilename != null &&
                  p.equals(track.externalFilename!, subtitlePath),
            );
            expect(session.engine!.tracks.subtitleId, subtitleTrack.id);
            await session.selectSubtitle(null);
            expect(session.engine!.tracks.subtitleId, isNull);
            await session.selectServerSubtitle('native-resource:2');
            expect(session.engine!.tracks.subtitleId, subtitleTrack.id);
            await session.close();
            expect(await File(subtitlePath).parent.exists(), isFalse);
            await restored.setFavorite(imported.identity, true);
            expect(
              (await sources.media(imported.identity)).remote!.favorite,
              isTrue,
            );
            await restored.setFavorite(imported.identity, false);
            expect(
              (await sources.media(imported.identity)).remote!.favorite,
              isFalse,
            );
            expect(await restored.markPlayed([imported.identity], true), 0);
            expect(
              (await PlaybackRepository(sources.database)
                      .read(imported.identity))
                  .watched,
              isTrue,
            );
            final events = fixture.requests
                .where((r) => r.uri.path.contains('/Sessions/Playing'))
                .toList();
            expect(events.first.uri.path, endsWith('/Sessions/Playing'));
            expect(events.last.uri.path, endsWith('/Sessions/Playing/Stopped'));
            expect(
              jsonDecode(events.last.body)['PositionTicks'],
              greaterThanOrEqualTo(130000000),
            );
            expect(
              events.map((r) => jsonDecode(r.body)['PlaySessionId']).toSet(),
              hasLength(1),
            );
            expect(ranges, isNotEmpty);
            expect(session.syncError, isNull);
            expect(
              (await PlaybackRepository(sources.database)
                      .read(imported.identity))
                  .position
                  .inSeconds,
              greaterThanOrEqualTo(13),
            );
          } finally {
            await session.close(discardProgress: true);
            await tester.pumpWidget(const SizedBox());
            session.dispose();
          }
          final cache = EmbyCacheRepository(
            sources: sources,
            connections: restored,
            cacheDirectory: () async =>
                Directory(p.join(sandbox.path, 'cache')),
          );
          final offline = PlaybackSession(
            sources: sources,
            records: PlaybackRepository(sources.database),
            emby: restored,
            cache: cache,
            createEngine: MediaKitVideoEngine.new,
          );
          try {
            await cache.artwork(source.id, imported.posterPath!);
            await cache.enqueue(imported, EmbyVideoQuality.source);
            final task = cache.tasks.value[imported.identity]!;
            final deadline = DateTime.now().add(const Duration(seconds: 20));
            while (![
                  VideoCacheTaskState.complete,
                  VideoCacheTaskState.failed,
                ].contains(task.state) &&
                DateTime.now().isBefore(deadline)) {
              await tester.pump();
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
            await task.work;
            expect(
              task.state,
              VideoCacheTaskState.complete,
              reason: task.error,
            );
            expect(await cache.entries(), hasLength(1));
            final requestsBeforeOffline = fixture.requests.length;
            await cache.artwork(source.id, imported.posterPath!);
            await tester.pumpWidget(
              MaterialApp(
                home: VideoPlayerPage(
                  identity: imported.identity,
                  session: offline,
                  closeWindow: () async {},
                  setFullscreen: (_) async {},
                ),
              ),
            );
            for (
              var n = 0;
              n < 200 && (offline.loading || offline.engine == null);
              n++
            ) {
              await tester.pump();
              await Future<void>.delayed(const Duration(milliseconds: 50));
              if (offline.error != null) break;
            }
            expect(offline.error, isNull);
            expect(offline.loading, isFalse);
            expect(offline.filePath, isNotNull);
            expect(offline.sidecarSubtitles, hasLength(1));
            expect(offline.clock.duration.inSeconds, 24);
            await offline.refreshTracks();
            expect(fixture.requests.length, requestsBeforeOffline);
            await cache.maintenance(clear: true);
            expect(await cache.entries(), hasLength(1));
            await offline.close();
            await cache.maintenance(clear: true);
            expect(await cache.entries(), isEmpty);
          } finally {
            await offline.close(discardProgress: true);
            await tester.pumpWidget(const SizedBox());
            offline.dispose();
            await cache.dispose();
          }
          await restored.remove(source.id);
          expect(await store(source.id).read(), isNull);
          expect(await sources.sources(), isEmpty);
        } finally {
          restored.dispose();
        }
      } finally {
        connections.dispose();
        client.close();
        for (final id in keys.toList()) {
          await store(id).clear();
        }
        await sources.close();
        await fixture.close();
        expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
        expect(p.basename(sandbox.path), startsWith('reelnest-native-emby-'));
        await sandbox.delete(recursive: true);
      }
    },
  );
  testWidgets('native mpv tracks switch, render with libass and load sidecars', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    const powerChannel = MethodChannel('reelnest/playback_sleep');
    await powerChannel.invokeMethod<void>('setActive', true);
    await powerChannel.invokeMethod<void>('setActive', false);
    await expectLater(
      powerChannel.invokeMethod<void>('setActive', 'invalid'),
      throwsA(isA<PlatformException>()),
    );
    final sandbox = await Directory.systemTemp.createTemp(
      'reelnest-native-tracks-',
    );
    MediaKit.ensureInitialized();
    final player = Player(
      configuration: const PlayerConfiguration(
        title: 'Track smoke',
        libass: true,
      ),
    );
    final engine = MediaKitVideoEngine(player: player);
    try {
      final file = await createTrackVideoFixture(
        p.join(sandbox.path, 'Track.Sample.mkv'),
      );
      final sidecar = File(p.join(sandbox.path, 'Track.Sample.ja.srt'));
      await sidecar.writeAsString(
        '1\n00:00:00,000 --> 00:00:24,000\nSidecar subtitle\n',
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: engine.surface())),
      );
      await engine.open(file.path, const Duration(seconds: 2));
      expect(engine.clock.playing, isFalse);
      for (
        var n = 0;
        n < 20 && engine.clock.position.inMilliseconds < 1900;
        n++
      ) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        engine.clock.position.inMilliseconds,
        inInclusiveRange(1900, 2100),
      );
      final preparedPosition = engine.clock.position;
      await tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.clock.playing, isFalse);
      expect(
        (engine.clock.position - preparedPosition).inMilliseconds.abs(),
        lessThan(150),
      );
      await engine.play();
      await engine.pause();
      await engine.refreshTracks();
      expect(
        engine.clock.duration.inMilliseconds,
        inInclusiveRange(23000, 25000),
      );
      expect(engine.tracks.audio, hasLength(2));
      expect(engine.tracks.subtitles.where((t) => !t.external), hasLength(2));
      expect(
        engine.tracks.subtitles.any(
          (t) =>
              t.external &&
              t.externalFilename != null &&
              p.equals(t.externalFilename!, sidecar.path),
        ),
        isTrue,
        reason:
            'Expected ${sidecar.path}; mpv tracks=${await (player.platform as NativePlayer).getProperty('track-list')}; sub-auto=${await (player.platform as NativePlayer).getProperty('sub-auto')}',
      );
      final native = player.platform as NativePlayer;
      await engine.setPitchCorrection(false);
      await engine.setRate(1.5);
      expect(double.parse(await native.getProperty('speed')), 1.5);
      expect(await native.getProperty('audio-pitch-correction'), 'no');
      await engine.setPitchCorrection(true);
      expect(await native.getProperty('audio-pitch-correction'), 'yes');
      await engine.setRate(1);
      final audio = engine.tracks.audio.firstWhere((t) => t.language == 'jpn');
      await engine.selectAudio(audio.id);
      expect(engine.tracks.audioId, audio.id);
      final english = engine.tracks.subtitles.firstWhere(
        (t) => !t.external && t.language == 'eng',
      );
      final chinese = engine.tracks.subtitles.firstWhere(
        (t) => !t.external && t.language == 'chi',
      );
      await engine.selectSubtitle(english.id);
      await engine.selectSecondarySubtitle(chinese.id);
      expect(engine.tracks.subtitleId, english.id);
      expect(engine.tracks.secondarySubtitleId, chinese.id);
      await engine.seek(const Duration(milliseconds: 2100));
      await engine.play();
      for (var i = 0; i < 20; i++) {
        if ((await native.getProperty('sub-text')).isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await engine.pause();
      expect(
        await native.getProperty('sub-text'),
        contains('English internal subtitle'),
        reason:
            'position=${await native.getProperty('time-pos')}; subtitle events=${await native.getProperty('sub-start')}/${await native.getProperty('sub-end')}',
      );
      final withoutSubtitles = await player.screenshot(format: null);
      final withSubtitles = await player.screenshot(
        format: null,
        includeLibassSubtitles: true,
      );
      expect(withSubtitles, isNotNull);
      expect(withoutSubtitles?.length, withSubtitles?.length);
      expect(
        listEquals(withoutSubtitles, withSubtitles),
        isFalse,
        reason: 'libass must draw subtitles into the decoded frame',
      );
      await engine.selectSubtitle(chinese.id);
      expect(engine.tracks.secondarySubtitleId, isNull);
      await engine.setSubtitleDelay(.2);
      expect(engine.tracks.subtitleDelay, closeTo(.2, .001));
      await engine.selectSubtitle(null);
      expect(engine.tracks.subtitleId, isNull);
      expect(await native.getProperty('sub-visibility'), 'no');
      final manual = File(p.join(sandbox.path, 'manual.srt'));
      await manual.writeAsString(
        '1\n00:00:00,000 --> 00:00:24,000\nManual subtitle\n',
      );
      await engine.addSubtitle(manual.path);
      expect(
        engine.tracks.subtitles.any(
          (t) =>
              t.id == engine.tracks.subtitleId &&
              t.externalFilename != null &&
              p.equals(t.externalFilename!, manual.path),
        ),
        isTrue,
      );
      await engine.enableAutoSubtitles();
      expect(engine.tracks.autoSubtitles, isTrue);
      await engine.setVolume(40);
      await engine.setVolumeBoost(1.5);
      expect(engine.clock.volume, closeTo(40, .1));
      expect(double.parse(await native.getProperty('volume')), closeTo(60, .1));
      await engine.setAudioDevice('auto');
      expect(engine.tracks.audioDevice, 'auto');
      await expectLater(
        engine.addSubtitle(p.join(sandbox.path, 'missing.srt')),
        throwsStateError,
      );
      expect(engine.clock.error, isNull);
      final invalid = File(p.join(sandbox.path, 'invalid.srt'));
      await invalid.writeAsString('this is not a subtitle file');
      await expectLater(engine.addSubtitle(invalid.path), throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        engine.clock.error,
        isNull,
        reason: 'An invalid external subtitle must not poison video playback',
      );
      await engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(engine.clock.playing, isTrue);
      expect(engine.clock.warning, isNull);
      await engine.pause();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.clock.warning, isNull);
    } finally {
      await engine.dispose();
      await tester.pumpWidget(const SizedBox());
      expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
      expect(p.basename(sandbox.path), startsWith('reelnest-native-tracks-'));
      await sandbox.delete(recursive: true);
    }
  });
  testWidgets('native EOF holds, advances, rejects corrupt next and closes', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    final sandbox = await Directory.systemTemp.createTemp(
      'reelnest-native-queue-',
    );
    final root = Directory(p.join(sandbox.path, 'media'));
    final first = await createVideoFixture(
      p.join(root.path, 'Show.S01E01.avi'),
    );
    await first.copy(p.join(root.path, 'Show.S01E02.avi'));
    await File(p.join(root.path, 'Show.S01E03.avi'))
        .writeAsString('not a video');
    final sources = repository(p.join(sandbox.path, 'library.sqlite'));
    final records = PlaybackRepository(sources.database);
    final session = PlaybackSession(
      sources: sources,
      records: records,
      createEngine: MediaKitVideoEngine.new,
    );
    var closed = false;
    try {
      final source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Queue smoke',
        location: root.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      MediaIdentity id(int n) =>
          (sourceId: source.id, localId: 'Show.S01E0$n.avi');
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            identity: id(1),
            session: session,
            closeWindow: () async {
              closed = true;
            },
            setFullscreen: (_) async {},
          ),
        ),
      );
      Future<void> waitFor(bool Function() predicate) async {
        for (var n = 0; n < 300 && !predicate(); n++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          predicate(),
          isTrue,
          reason:
              'identity=${session.item?.identity} loading=${session.loading} '
              'error=${session.error} transition=${session.transitionMessage} '
              'position=${session.clock.position} completed=${session.clock.completed}',
        );
      }

      await waitFor(
        () => !session.loading && session.clock.duration > Duration.zero,
      );
      expect(session.queue.items.length, 3);
      await session.setEndAction(VideoEndAction.holdLastFrame);
      await session.seek(const Duration(seconds: 22));
      await waitFor(() => session.clock.completed);
      await session.refreshQueue();
      expect(session.item!.identity, id(1));
      expect(session.engine, isNotNull);
      expect(session.error, isNull);
      expect((await records.read(id(1))).watched, isTrue);
      await session.setEndAction(VideoEndAction.nextEpisode);
      await session.seek(const Duration(seconds: 22));
      if (!session.clock.playing) await session.toggle();
      await waitFor(() => !session.loading && session.item?.identity == id(2));
      expect(
        (await records.read(id(1))).position.inSeconds,
        inInclusiveRange(23, 25),
      );
      expect(session.queue.items.length, 2);
      final secondEngine = session.engine;
      await session.seek(const Duration(seconds: 22));
      await waitFor(
        () => !session.loading && session.transitionMessage != null,
      );
      expect(session.item!.identity, id(2));
      expect(session.engine, same(secondEngine));
      expect(session.error, isNull);
      await session.setEndAction(VideoEndAction.closeWindow);
      await session.seek(const Duration(seconds: 22));
      if (!session.clock.playing) await session.toggle();
      await waitFor(() => closed);
      expect(session.engine, isNull);
      expect((await records.read(id(2))).watched, isTrue);
    } finally {
      await session.close(discardProgress: true);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await sources.close();
      expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
      expect(p.basename(sandbox.path), startsWith('reelnest-native-queue-'));
      await sandbox.delete(recursive: true);
    }
  });
  testWidgets('native video window decodes, switches, saves and resumes', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    final current = await WindowController.fromCurrentEngine();
    final playbackNotices = <List<String>>[];
    await current.setWindowMethodHandler((call) async {
      if (call.method == 'playbackChanged') {
        playbackNotices.add(
          List<String>.from((call.arguments as Map)['sourceIds'] as List),
        );
      }
      return null;
    });
    final sandbox = await Directory.systemTemp.createTemp(
      'reelnest-native-playback-',
    );
    final sourceRoot = Directory(p.join(sandbox.path, 'media'));
    final file = await createVideoFixture(
      p.join(sourceRoot.path, 'ReelNest.Sample.avi'),
    );
    await file.copy(p.join(sourceRoot.path, 'Show.S01E01.avi'));
    final database = p.join(sandbox.path, 'library.sqlite');
    final sources = repository(database);
    WindowController? player;
    try {
      final source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Smoke',
        location: sourceRoot.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      final record = PlaybackRepository(sources.database);
      final film = (sourceId: source.id, localId: 'ReelNest.Sample.avi');
      await record.save(
        film,
        position: const Duration(seconds: 15),
        duration: const Duration(seconds: 24),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Native playback smoke'))),
      );
      final payload = {
        'type': 'player',
        'sourceId': source.id,
        'localId': film.localId,
        'mainWindowId': current.windowId,
        'testDatabase': database,
      };
      player = await WindowController.create(
        WindowConfiguration(arguments: jsonEncode(payload)),
      );
      Future<Map<dynamic, dynamic>> ready(
        WindowController window, {
        int minimumPosition = 0,
      }) async {
        Object? lastStatus;
        Object? lastError;
        for (var i = 0; i < 180; i++) {
          try {
            final status = await window
                .invokeMethod<Map>('status')
                .timeout(const Duration(seconds: 2));
            lastStatus = status;
            if (status?['error'] != null) {
              fail('Native player error: ${status!['error']}');
            }
            if (status?['loading'] == false &&
                (status?['durationMs'] as int? ?? 0) > 0 &&
                (status?['positionMs'] as int? ?? 0) >= minimumPosition) {
              return status!;
            }
          } catch (e) {
            if (e is TestFailure) rethrow;
            lastError = e;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        fail(
          'Native playback did not become ready: status=$lastStatus, error=$lastError',
        );
      }

      var status = await ready(player, minimumPosition: 10000);
      expect(status['durationMs'], inInclusiveRange(23000, 25000));
      expect(status['playing'], isTrue);
      final episode = (sourceId: source.id, localId: 'Show.S01E01.avi');
      await player
          .hide(); // Reuse must show the window before awaiting a frame.
      await player.invokeMethod('play', {
        ...payload,
        'localId': episode.localId,
      });
      status = await ready(player, minimumPosition: 1000);
      expect(status['error'], isNull);
      expect(
        (await record.read(film)).position.inMilliseconds,
        greaterThanOrEqualTo(10000),
      );
      try {
        await player.invokeMethod('close').timeout(const Duration(seconds: 10));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        (await record.read(episode)).position.inMilliseconds,
        greaterThanOrEqualTo(1000),
      );
      expect(playbackNotices, isNotEmpty);
      expect(playbackNotices.every((ids) => ids.contains(source.id)), isTrue);
      expect(
        (await WindowController.getAll()).any(
          (w) => w.windowId == player!.windowId,
        ),
        isFalse,
      );
      player = null;
    } finally {
      if (player != null) {
        try {
          await player.invokeMethod('close');
        } catch (_) {}
      }
      await sources.close();
      expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
      expect(p.basename(sandbox.path), startsWith('reelnest-native-playback-'));
      await sandbox.delete(recursive: true);
    }
  });
}
