import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/external_playback_providers.dart';
import 'package:reelnest/features/playback/application/external_playback_service.dart';
import 'package:reelnest/features/playback/data/external_player_settings_repository.dart';
import 'package:reelnest/features/playback/domain/external_player_settings.dart';
import 'package:reelnest/features/playback/domain/transient_playback_target.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/platform/external_player_gateway.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';
import 'package:window_manager/window_manager.dart';

Future<void> child() async {
  await windowManager.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  final args = jsonDecode(window.arguments) as Map;
  final launcher = ExternalWindowPlaybackLauncher(
    args['mainWindowId'] as String,
  );
  await window.setWindowMethodHandler((call) async {
    if (call.method == 'ready') return true;
    if (call.method == 'launch') {
      try {
        await launcher.openTransient(
          TransientPlaybackTarget.fromJson(
            Map<String, dynamic>.from(call.arguments as Map),
          ),
        );
        return true;
      } on SourceFailure catch (error) {
        return error.message;
      }
    }
    if (call.method == 'close') {
      await windowManager.close();
      return null;
    }
    throw MissingPluginException();
  });
  runApp(const MaterialApp(home: Scaffold(body: Text('External IPC fixture'))));
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty && arguments.first == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    unawaited(child());
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'child IPC delegates external startup to the main service without indexing',
    (tester) async {
      const probe = String.fromEnvironment('EXTERNAL_PLAYER_PROBE_PATH');
      expect(probe, isNotEmpty);
      await windowManager.ensureInitialized();
      final main = await WindowController.fromCurrentEngine();
      final temporary = await RuntimeStoragePaths.current.temporary();
      await temporary.create(recursive: true);
      final sandbox = await temporary.createTemp('reelnest-external-ipc-');
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      final settings = ExternalPlayerSettingsRepository(sources.database);
      final service = ExternalPlaybackService(
        sources: sources,
        settings: settings,
        gateway: DesktopExternalPlayerGateway(),
      );
      WindowController? secondary;
      try {
        await settings.save(
          const ExternalPlayerSettings(applicationPath: probe),
        );
        await main.setWindowMethodHandler((call) async {
          if (call.method != 'openExternal') throw MissingPluginException();
          try {
            final payload = Map<String, dynamic>.from(call.arguments as Map);
            await service.openTransient(
              TransientPlaybackTarget.fromJson(
                Map<String, dynamic>.from(payload['transient'] as Map),
              ),
            );
            return null;
          } catch (error) {
            throw PlatformException(
              code: 'external_failed',
              message: error is SourceFailure ? error.message : '外部播放器不可用。',
            );
          }
        });
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Main IPC fixture'))),
        );
        secondary = await WindowController.create(
          WindowConfiguration(
            hiddenAtLaunch: true,
            arguments: jsonEncode({'mainWindowId': main.windowId}),
          ),
        );
        var ready = false;
        for (var i = 0; i < 100 && !ready; i++) {
          try {
            ready =
                await secondary
                    .invokeMethod<bool>('ready')
                    .timeout(const Duration(seconds: 1)) ??
                false;
          } on WindowChannelException {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        expect(ready, isTrue);
        final video = await File(p.join(sandbox.path, '电影 & file.mkv'))
            .writeAsString('fixture');
        expect(
          await secondary.invokeMethod<Object?>(
            'launch',
            TransientPlaybackTarget.file(video.path).toJson(),
          ),
          true,
        );
        expect(
          await secondary.invokeMethod<Object?>(
            'launch',
            TransientPlaybackTarget.stream(
              'https://example.invalid/film.mp4?token=fixture&x=1',
            ).toJson(),
          ),
          true,
        );
        final failed = await File(p.join(sandbox.path, 'fail.mp4'))
            .writeAsString('fixture');
        final error = await secondary.invokeMethod<Object?>(
          'launch',
          TransientPlaybackTarget.file(failed.path).toJson(),
        );
        expect(error, isA<String>());
        expect(error, isNot(contains(sandbox.path)));
        for (final table in [
          'sources',
          'media',
          'playback_states',
          'media_activity',
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
        debugPrint(
          'external native IPC: main-owned local/HTTP launch and safe failure; no library/progress writes passed',
        );
      } finally {
        if (secondary != null) {
          try {
            await secondary
                .invokeMethod<void>('close')
                .timeout(const Duration(seconds: 3));
          } catch (_) {}
        }
        await service.dispose();
        await sources.close();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(p.isWithin(temporary.path, sandbox.path), isTrue);
        expect(p.basename(sandbox.path), startsWith('reelnest-external-ipc-'));
        await sandbox.delete(recursive: true);
        final capture = File(p.join(p.dirname(probe), 'capture.bin'));
        if (await capture.exists()) await capture.delete();
      }
    },
  );
}
