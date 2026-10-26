import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/app/window_close_request.dart';
import 'package:reelnest/features/playback/application/playback_providers.dart';
import 'package:reelnest/features/playback/domain/transient_playback_target.dart';
import 'package:reelnest/features/playback/presentation/player_window_app.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

SourceRepository repository(String path) => SourceRepository(
  database: LibraryDatabase(NativeDatabase.createInBackground(File(path))),
  adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
  identityLookup: (_) async => 'fixture',
);

Future<void> startPlayer() async {
  await windowManager.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  final args = jsonDecode(window.arguments) as Map<String, dynamic>;
  runApp(
    ProviderScope(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(
          repository(args['testDatabase'] as String),
        ),
      ],
      child: PlayerWindowApp(window: window, arguments: args),
    ),
  );
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty && arguments.first == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    unawaited(startPlayer());
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'temporary native window plays file and HTTP, keeps old video on failure, and closes without indexing',
    (tester) async {
      await windowManager.ensureInitialized();
      final main = await WindowController.fromCurrentEngine();
      final temporary = await RuntimeStoragePaths.current.temporary();
      await temporary.create(recursive: true);
      final sandbox = await temporary.createTemp('reelnest-transient-native-');
      final dbPath = p.join(sandbox.path, 'library.sqlite');
      final sources = repository(dbPath);
      final video = await createTrackVideoFixture(
        p.join(sandbox.path, 'Film.mkv'),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        try {
          final length = await video.length();
          final match = RegExp(r'^bytes=(\d+)-(\d*)$')
              .firstMatch(request.headers.value('range') ?? '');
          final start = match == null ? 0 : int.parse(match[1]!);
          final end = match == null || match[2]!.isEmpty
              ? length - 1
              : int.parse(match[2]!).clamp(0, length - 1);
          if (start >= length || end < start) {
            request.response.statusCode = 416;
            await request.response.close();
            return;
          }
          request.response.statusCode = match == null ? 200 : 206;
          request.response.headers.set('Accept-Ranges', 'bytes');
          if (match != null) {
            request.response.headers.set(
              'Content-Range',
              'bytes $start-$end/$length',
            );
          }
          request.response.contentLength = end - start + 1;
          await request.response.addStream(video.openRead(start, end + 1));
          await request.response.close();
        } catch (_) {
          try {
            await request.response.close();
          } catch (_) {
            /* Decoder cancelled its request. */
          }
        }
      });
      final notices = <Object?>[];
      await main.setWindowMethodHandler((call) async {
        if (call.method == 'playbackChanged') notices.add(call.arguments);
        return null;
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Temporary playback integration')),
        ),
      );
      WindowController? player;
      Future<Map> ready(WindowController window) async {
        for (var i = 0; i < 150; i++) {
          try {
            final result = await window
                .invokeMethod<Map>('status')
                .timeout(const Duration(seconds: 1));
            if (result?['error'] != null) {
              fail('Native playback reported an error');
            }
            if (result?['loading'] == false &&
                result?['playing'] == true &&
                (result?['positionMs'] as int? ?? 0) > 500) {
              return result!;
            }
          } on WindowChannelException {
            /* Channel not registered yet. */
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        fail('Native transient playback did not become ready');
      }

      try {
        await sources.sources(); // Initialize only the isolated test database.
        final target = TransientPlaybackTarget.file(video.path);
        player = await WindowController.create(
          WindowConfiguration(
            hiddenAtLaunch: true,
            arguments: jsonEncode({
              'type': 'player',
              'sourceId': target.identity.sourceId,
              'localId': target.identity.localId,
              'transient': target.toJson(),
              'testDatabase': dbPath,
              'mainWindowId': main.windowId,
            }),
          ),
        );
        final first = await ready(player);
        expect(first['durationMs'], greaterThan(10000));
        final launcher = DesktopPlaybackLauncher();
        await launcher.openTransient(
          TransientPlaybackTarget.stream(
            'http://127.0.0.1:${server.port}/Film.mkv?token=fixture-secret',
          ),
        );
        expect((await ready(player))['error'], isNull);
        await expectLater(
          launcher.openTransient(
            TransientPlaybackTarget.file(p.join(sandbox.path, 'Missing.mkv')),
          ),
          throwsA(anything),
        );
        expect((await ready(player))['playing'], isTrue);
        expect(
          (await WindowController.getAll()).where(
            (w) => w.arguments.contains('"type":"player"'),
          ),
          hasLength(1),
        );
        final closingPlayer = player;
        expect(
          await requestChildWindowClose(
            request: () => closingPlayer.invokeMethod('close'),
            exists: () async => (await WindowController.getAll()).any(
              (w) => w.windowId == closingPlayer.windowId,
            ),
            budget: const Duration(seconds: 10),
          ),
          isTrue,
        );
        for (
          var i = 0;
          i < 100 &&
              (await WindowController.getAll()).any(
                (w) => w.windowId == player!.windowId,
              );
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(
          (await WindowController.getAll()).any(
            (w) => w.windowId == player!.windowId,
          ),
          isFalse,
        );
        player = null;
        for (final table in [
          'sources',
          'media',
          'playback_states',
          'media_activity',
          'playback_markers',
        ]) {
          expect(
            (await sources.database
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n'),
            0,
            reason: table,
          );
        }
        expect(notices, isEmpty);
        debugPrint(
          'transient native: real file/HTTP, reused window, failed switch rollback, no library/history writes, normal close passed',
        );
      } finally {
        if (player != null) {
          try {
            final remainingPlayer = player;
            await requestChildWindowClose(
              request: () => remainingPlayer.invokeMethod('close'),
              exists: () async => (await WindowController.getAll()).any(
                (w) => w.windowId == remainingPlayer.windowId,
              ),
              budget: const Duration(seconds: 10),
            );
          } catch (_) {}
        }
        await server.close(force: true);
        await tester.pumpWidget(const SizedBox.shrink());
        await sources.close();
        expect(p.isWithin(temporary.path, sandbox.path), isTrue);
        expect(
          p.basename(sandbox.path),
          startsWith('reelnest-transient-native-'),
        );
        await sandbox.delete(recursive: true);
      }
    },
  );
}
