import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

import '../test/support/video_fixture.dart';

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
  testWidgets('native video window decodes, switches, saves and resumes', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    final current = await WindowController.fromCurrentEngine();
    await current.setWindowMethodHandler((_) async => null);
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
