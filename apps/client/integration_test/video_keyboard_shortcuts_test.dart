import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_keyboard_shortcuts.dart';
import 'package:reelnest/features/playback/presentation/player_shortcut_router.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final gpu in [true, false]) {
    testWidgets('configured keyboard shortcuts drive native mpv GPU=$gpu', (
      tester,
    ) async {
      MediaKit.ensureInitialized();
      final temporary = await RuntimeStoragePaths.current.temporary();
      await temporary.create(recursive: true);
      final root = await temporary.createTemp('reelnest-keyboard-native-');
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture-volume',
      );
      NativePlayer? native;
      MediaKitVideoEngine? engine;
      final session = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        createEngine: () {
          final player = Player(
            configuration: const PlayerConfiguration(muted: true, libass: true),
          );
          native = player.platform as NativePlayer;
          return engine = MediaKitVideoEngine(
            player: player,
            videoConfiguration: VideoControllerConfiguration(
              enableHardwareAcceleration: gpu,
            ),
          );
        },
      );
      final focus = FocusNode();
      Future<void> finish(Future<void> future) async {
        var done = false;
        Object? failure;
        future.then(
          (_) => done = true,
          onError: (Object error) {
            failure = error;
            done = true;
          },
        );
        for (var n = 0; n < 500 && !done; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done, isTrue);
        if (failure != null) throw failure!;
      }

      Future<void> waitProperty(
        String name,
        bool Function(String) matches,
      ) async {
        for (var n = 0; n < 100; n++) {
          if (matches(await native!.getProperty(name))) return;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        fail('Native property $name did not match');
      }

      try {
        await createTrackVideoFixture(p.join(root.path, 'Film.mkv'));
        final source = await sources.add(
          kind: MediaSourceKind.localFolder,
          name: 'Fixture',
          location: root.path,
          minimumFileSize: 0,
        );
        await sources.scan(source.id);
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerShortcutRouter(
              session: session,
              onAction: (action) =>
                  unawaited(session.performKeyboardAction(action)),
              onSeekForwardHold: (holding) =>
                  unawaited(session.setKeyboardSeekForwardHold(holding)),
              child: Focus(
                focusNode: focus,
                autofocus: true,
                child: AnimatedBuilder(
                  animation: session,
                  builder: (_, _) => Center(
                    child: SizedBox(
                      width: 320,
                      height: 180,
                      child: engine?.surface() ?? const SizedBox(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await finish(session.open((sourceId: source.id, localId: 'Film.mkv')));
        expect(session.error, isNull);
        await finish(engine!.pause());
        await finish(session.seek(const Duration(seconds: 1)));
        await waitProperty('pause', (value) => value == 'yes');
        await finish(
          session.setKeyboardShortcuts(VideoShortcutAction.seekForward, [
            VideoKeyChord(LogicalKeyboardKey.keyN.keyId),
          ]),
        );
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(
          LogicalKeyboardKey.keyN,
          physicalKey: PhysicalKeyboardKey.keyN,
        );
        await waitProperty(
          'time-pos',
          (value) => ((double.tryParse(value) ?? -1) - 6).abs() < .1,
        );
        final before = await native!.getProperty('time-pos');
        await tester.sendKeyEvent(
          LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.arrowRight,
        );
        await tester.pump();
        expect(await native!.getProperty('time-pos'), before);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.bracketRight,
          physicalKey: PhysicalKeyboardKey.bracketRight,
        );
        await waitProperty('speed', (value) => double.tryParse(value) == 1.25);
        await finish(engine!.refreshTracks());
        expect(engine!.tracks.audio.length, greaterThanOrEqualTo(2));
        expect(engine!.tracks.subtitles.length, greaterThanOrEqualTo(2));
        await finish(engine!.selectSubtitle(engine!.tracks.subtitles.first.id));
        final subtitle = await native!.getProperty('sid');
        await tester.sendKeyEvent(
          LogicalKeyboardKey.keyV,
          physicalKey: PhysicalKeyboardKey.keyV,
        );
        await waitProperty('sub-visibility', (value) => value == 'no');
        expect(await native!.getProperty('sid'), subtitle);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.keyC,
          physicalKey: PhysicalKeyboardKey.keyC,
        );
        await waitProperty('sub-visibility', (value) => value == 'yes');
        await waitProperty('sid', (value) => value != subtitle);
        final audio = await native!.getProperty('aid');
        await tester.sendKeyEvent(
          LogicalKeyboardKey.keyA,
          physicalKey: PhysicalKeyboardKey.keyA,
        );
        await waitProperty('aid', (value) => value != audio);
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyN,
          physicalKey: PhysicalKeyboardKey.keyN,
        );
        await tester.sendKeyRepeatEvent(
          LogicalKeyboardKey.keyN,
          physicalKey: PhysicalKeyboardKey.keyN,
        );
        await waitProperty('speed', (value) => double.tryParse(value) == 3);
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.keyN,
          physicalKey: PhysicalKeyboardKey.keyN,
        );
        await waitProperty('speed', (value) => double.tryParse(value) == 1.25);
        expect(await session.preferences.rate(session.item!), 1.25);
        expect(session.controlError, isNull);
        debugPrint(
          'keyboard shortcuts GPU=$gpu: remap/old-key removal, seek/rate, subtitle visibility/cycle, audio cycle and temporary 3x passed',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await finish(session.close(discardProgress: true));
        session.dispose();
        focus.dispose();
        await sources.close();
        expect(p.isWithin(temporary.path, root.path), isTrue);
        expect(p.basename(root.path), startsWith('reelnest-keyboard-native-'));
        await root.delete(recursive: true);
      }
    });
  }
}
