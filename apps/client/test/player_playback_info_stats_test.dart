import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/presentation/player_playback_info.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_playback_stats.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

void main() {
  testWidgets('playback info binds, rebinds and disposes its stats sampler', (
    tester,
  ) async {
    final engines = <_StatsFakeVideoEngine>[];
    var nextFps = 24.0;
    Directory? sandbox;
    SourceRepository? sources;
    PlaybackSession? first;
    PlaybackSession? second;
    MediaSource? source;

    _StatsFakeVideoEngine createEngine() {
      final engine = _StatsFakeVideoEngine(
        VideoPlaybackStats(estimatedFps: nextFps),
      );
      nextFps = 60;
      engines.add(engine);
      return engine;
    }

    try {
      await tester.runAsync(() async {
        sandbox = await Directory.systemTemp.createTemp(
          'reelnest-playback-info-stats-',
        );
        final repository = SourceRepository(
          database: LibraryDatabase(NativeDatabase.memory()),
          adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
          identityLookup: (_) async => 'fixture-volume',
        );
        sources = repository;
        final records = PlaybackRepository(repository.database);
        first = PlaybackSession(
          sources: repository,
          records: records,
          createEngine: createEngine,
        );
        second = PlaybackSession(
          sources: repository,
          records: records,
          createEngine: createEngine,
        );
        await File(p.join(sandbox!.path, 'First.mkv')).writeAsString('first');
        await File(p.join(sandbox!.path, 'Second.mkv')).writeAsString('second');
        source = await repository.add(
          kind: MediaSourceKind.localFolder,
          name: 'Test',
          location: sandbox!.path,
          minimumFileSize: 0,
        );
        await repository.scan(source!.id);
        await first!.open((sourceId: source!.id, localId: 'First.mkv'));
      });
      final firstSession = first!;
      final secondSession = second!;

      Widget subject(PlaybackSession session) => MaterialApp(
        home: PlayerPlaybackInfoOverlay(
          session: session,
          palette: const PlayerPalette(lightContent: true),
          onDismiss: () {},
        ),
      );

      await tester.pumpWidget(subject(firstSession));
      await tester.pump();
      expect(engines, hasLength(1));
      expect(engines.first.statsReads, 1);
      expect(find.text('24.00 FPS（估算）'), findsOneWidget);

      await tester.runAsync(
        () => secondSession.open((sourceId: source!.id, localId: 'Second.mkv')),
      );
      await tester.pumpWidget(subject(secondSession));
      await tester.pump();
      expect(engines, hasLength(2));
      expect(engines.last.statsReads, 1);
      expect(find.text('60.00 FPS（估算）'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final readsAfterClose = engines.last.statsReads;
      await tester.pump(const Duration(seconds: 2));
      expect(engines.last.statsReads, readsAfterClose);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        final firstSession = first;
        if (firstSession != null) {
          await firstSession.close(discardProgress: true);
          firstSession.dispose();
        }
        final secondSession = second;
        if (secondSession != null) {
          await secondSession.close(discardProgress: true);
          secondSession.dispose();
        }
        final repository = sources;
        if (repository != null) await repository.close();
        final directory = sandbox;
        if (directory == null) return;
        expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
        expect(
          p.basename(directory.path),
          startsWith('reelnest-playback-info-stats-'),
        );
        await directory.delete(recursive: true);
      });
    }
  });
}

class _StatsFakeVideoEngine extends FakeVideoEngine
    implements VideoStatsEngine {
  _StatsFakeVideoEngine(this.snapshot);

  final VideoPlaybackStats snapshot;
  int statsReads = 0;

  @override
  Future<VideoPlaybackStats> readPlaybackStats() async {
    statsReads++;
    return snapshot;
  }
}
