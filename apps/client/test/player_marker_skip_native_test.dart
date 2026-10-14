import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/playback_marker.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';
import 'support/track_video_fixture.dart';

/// Real decoder clock/seek with stubbed track controls and no Flutter surface.
/// This checks the session's skip dispatch; it is not a native window UI test.
class _NativeSkipEngine extends FakeVideoEngine {
  _NativeSkipEngine(this.player) {
    for (final stream in <Stream<dynamic>>[
      player.stream.position,
      player.stream.duration,
      player.stream.playing,
      player.stream.completed,
    ]) {
      subscriptions.add(stream.listen((_) => events.add(clock)));
    }
  }
  final Player player;
  final subscriptions = <StreamSubscription<dynamic>>[];
  @override
  VideoClock get clock => VideoClock(
    position: player.state.position,
    duration: player.state.duration,
    playing: player.state.playing,
    completed: player.state.completed,
  );
  @override
  Future<void> open(String path, Duration start) async {
    await (player.platform as NativePlayer).setProperty('vid', 'auto');
    await player.open(Media(path, start: start), play: false);
    await _waitFor(() => player.state.duration > Duration.zero);
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> dispose() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
    await super.dispose();
  }
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Native marker skip timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test(
    'session prompt and automatic marker skip seek the real mpv decoder',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final directory = await Directory.systemTemp.createTemp(
        'reelnest-native-marker-',
      );
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'native-fixture-volume',
      );
      final native = Player(
        configuration: const PlayerConfiguration(muted: true),
      );
      _NativeSkipEngine? engine;
      final session = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        checkpointInterval: const Duration(hours: 1),
        createEngine: () => engine = _NativeSkipEngine(native),
      );
      try {
        await createTrackVideoFixture(p.join(directory.path, 'Film.mkv'));
        final source = await sources.add(
          kind: MediaSourceKind.localFolder,
          name: 'native fixture',
          location: directory.path,
          minimumFileSize: 0,
        );
        await sources.scan(source.id);
        await session.open((sourceId: source.id, localId: 'Film.mkv'));
        expect(session.error, isNull);
        await session.toggle();
        await _waitFor(() => !native.state.playing);
        await session.setMarkerBoundary(
          PlaybackMarkerKind.intro,
          isStart: true,
          at: const Duration(seconds: 1),
        );
        await session.setMarkerBoundary(
          PlaybackMarkerKind.intro,
          isStart: false,
          at: const Duration(seconds: 3),
        );
        await session.seek(const Duration(seconds: 2));
        await _waitFor(() => session.precision.value.activeSkipMarker != null);
        await session.skipPlaybackMarker(
          session.precision.value.activeSkipMarker!.id,
        );
        await _waitFor(
          () => native.state.position >= const Duration(milliseconds: 2900),
        );
        expect(native.state.playing, isFalse);
        await session.seek(Duration.zero);
        await _waitFor(() => session.precision.value.activeSkipMarker == null);
        await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
        await session.seek(const Duration(seconds: 2));
        await _waitFor(
          () => native.state.position >= const Duration(milliseconds: 2900),
        );
        expect(session.error, isNull);
        expect(session.controlError, isNull);
        expect(native.state.playing, isFalse);
      } finally {
        await session.close(discardProgress: true);
        session.dispose();
        // Creation/scanning can fail before the session owns the decoder.
        if (engine == null) {
          await native.dispose();
        } else if (engine!.disposals == 0) {
          await engine!.dispose();
        }
        await sources.close();
        expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
        expect(
          p.basename(directory.path),
          startsWith('reelnest-native-marker-'),
        );
        await directory.delete(recursive: true);
      }
    },
    skip: library.isEmpty ? 'Set REELNEST_MPV_PATH for native checks' : false,
  );
}
