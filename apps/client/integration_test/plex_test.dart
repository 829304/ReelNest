import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/plex/plex_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/features/sources/presentation/source_library_page.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/plex_fixture.dart';
import '../test/support/video_fixture.dart';

class _Store implements CredentialStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native Plex browse, detail and real mpv playback keep Plex identity',
    (tester) async {
      // IntegrationTest disables mock text input by default. Register it for
      // WidgetTester.enterText; this is synthetic UI input, not an OS IME test.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1150, 800));
      final temporary = await RuntimeStoragePaths.current.temporary();
      await temporary.create(recursive: true);
      final sandbox = await temporary.createTemp('reelnest-plex-native-');
      final database = File(p.join(sandbox.path, 'library.sqlite'));
      final video = await createVideoFixture(
        p.join(sandbox.path, 'remote.avi'),
      );
      final fixture = PlexFixture();
      fixture.catalog['1'] = [plexMovie(title: 'Plex 原生影片')];
      await fixture.start();
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.createInBackground(database)),
        adapters: {},
      );
      final embyClient = EmbyClient(
        deviceId: await embyDeviceIdentity(sources.database),
      );
      final plexClient = PlexClient(
        accountEndpoint: fixture.accountEndpoint,
        deviceId: await embyDeviceIdentity(sources.database),
      );
      final stores = <String, _Store>{};
      final connections = EmbyConnectionRepository(
        sources: sources,
        client: Future.value(embyClient),
        plexClient: Future.value(plexClient),
        stores: (id) => stores.putIfAbsent(id, _Store.new),
      );
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          embyConnectionProvider.overrideWithValue(connections),
          embyCachedVideosProvider.overrideWith((_) async => []),
        ],
      );
      PlaybackSession? session;

      Future<void> waitFor(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native Plex UI did not reach expected state');
          }
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      Future<void> mount(Widget child) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      );

      try {
        final source = await connections.connectPlex(
          fixture.address,
          fixture.token,
        );
        await connections.selectLibraries(
          source.id,
          all: false,
          selected: ['section:1'],
        );
        final result = await EmbySyncRepository(
          sources: sources,
          connections: connections,
        ).synchronize(source.id);
        expect(result.importedItems, 1);
        final item = (await sources.browse(source.id)).items.single;
        expect(item.title, 'Plex 原生影片');
        expect((await sources.source(source.id)).kind, MediaSourceKind.plex);

        final ranges = <String>[];
        fixture.streamHandler = (request) async {
          final response = request.response;
          final length = await video.length();
          response.headers.contentType = ContentType('video', 'x-msvideo');
          response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
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
              response.statusCode = HttpStatus.partialContent;
              response.headers.set(
                HttpHeaders.contentRangeHeader,
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
            // mpv may cancel an in-flight Range request while seeking/closing.
          } on HttpException {
            // The decoder can finish after it has received enough bytes.
          }
        };

        await mount(
          SourceLibraryPage(sourceId: source.id, libraryId: 'section:1'),
        );
        await waitFor(() => find.text('浏览与管理 Plex 视频内容').evaluate().isNotEmpty);
        await waitFor(() => find.text('Plex 原生影片').evaluate().isNotEmpty);
        expect(find.text('Plex 原生影片'), findsWidgets);
        final search = find.byType(TextField).first;
        await waitFor(() => tester.widget<TextField>(search).enabled == true);
        expect(tester.widget<TextField>(search).enabled, isTrue);
        await tester.enterText(search, 'definitely-no-match-2026');
        expect(
          tester.widget<TextField>(search).controller!.text,
          'definitely-no-match-2026',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await waitFor(() => find.text('没有匹配的内容').evaluate().isNotEmpty);
        await tester.enterText(search, '原生影片');
        expect(tester.widget<TextField>(search).controller!.text, '原生影片');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await waitFor(() => find.text('Plex 原生影片').evaluate().isNotEmpty);
        expect(find.text('Plex 原生影片'), findsWidgets);

        await mount(LocalMediaDetailPage(identity: item.identity));
        await waitFor(
          () => find.textContaining('Plex 流媒体').evaluate().isNotEmpty,
        );
        await waitFor(() => find.text('Plex 演员').evaluate().isNotEmpty);
        expect(find.text('Plex 演员'), findsOneWidget);
        expect(find.textContaining('Emby'), findsNothing);

        MediaKit.ensureInitialized();
        session = PlaybackSession(
          sources: sources,
          records: PlaybackRepository(sources.database),
          emby: connections,
          createEngine: MediaKitVideoEngine.new,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: VideoPlayerPage(
              identity: item.identity,
              session: session,
              closeWindow: () async {},
              setFullscreen: (_) async {},
            ),
          ),
        );
        final playbackDeadline = DateTime.now().add(
          const Duration(seconds: 15),
        );
        while ((session.loading || session.engine == null) &&
            DateTime.now().isBefore(playbackDeadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (session.error != null) break;
        }
        expect(session.loading, isFalse);
        expect(session.error, isNull);
        expect(session.qualityOptions, isEmpty);
        expect(find.byTooltip('画质'), findsNothing);
        expect(session.clock.duration.inSeconds, 24);
        expect(session.clock.position.inSeconds, greaterThanOrEqualTo(3));
        await session.seek(const Duration(seconds: 14));
        final seekDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (session.clock.position.inSeconds < 13 &&
            DateTime.now().isBefore(seekDeadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(session.clock.position.inSeconds, greaterThanOrEqualTo(13));
        await session.refreshServerSubtitles();
        expect(session.serverSubtitles.single.displayName, 'Plex 中文字幕');
        await session.selectServerSubtitle('9001:31');
        expect(session.subtitleError, isNull);
        await session.close();

        final reports = fixture.requests
            .where((entry) => entry.uri.path == '/plex/:/progress')
            .toList();
        expect(reports, isNotEmpty);
        expect(reports.last.uri.queryParameters['state'], 'stopped');
        expect(ranges, isNotEmpty);
        expect(
          fixture.requests
              .where(
                (entry) => !entry.uri.path.startsWith('/plex/library/parts/'),
              )
              .every(
                (entry) =>
                    entry.headers['x-plex-client-identifier']?.isNotEmpty ==
                    true,
              ),
          isTrue,
        );
        expect(
          fixture.requests.any(
            (entry) =>
                entry.uri.queryParameters.containsKey('api_key') ||
                entry.headers.containsKey('x-emby-authorization') ||
                entry.headers.containsKey('authorization'),
          ),
          isFalse,
        );
        debugPrint(
          'Plex native: production library UI -> search -> detail UI -> real mpv Range playback -> subtitle -> progress report passed',
        );
      } finally {
        await session?.close(discardProgress: true);
        session?.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        connections.dispose();
        embyClient.close();
        plexClient.close();
        await sources.close();
        await fixture.close();
        expect(p.isWithin(temporary.path, sandbox.path), isTrue);
        expect(p.basename(sandbox.path), startsWith('reelnest-plex-native-'));
        await sandbox.delete(recursive: true);
      }
    },
  );
}
