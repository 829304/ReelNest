import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_frame_preview.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/playback_diagnostics.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _FailureEngine extends FakeVideoEngine implements DiagnosableVideoEngine {
  _FailureEngine({this.issue, this.cleanupFailure = false});
  final PlaybackIssue? issue;
  final bool cleanupFailure;
  @override
  PlaybackTrace? diagnosticTrace;
  @override
  Future<void> open(String path, Duration start) async {
    if (issue != null) throw issue!;
    await super.open(path, start);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    if (cleanupFailure) throw StateError('sensitive cleanup path');
  }
}

void main() {
  late Directory sandbox;
  late SourceRepository sources;
  late PlaybackDiagnostics diagnostics;
  late MediaIdentity video;
  PlaybackSession? session;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-failure-');
    final media = Directory(p.join(sandbox.path, 'media'));
    await media.create();
    await File(p.join(media.path, 'private-film.mkv')).writeAsString('fixture');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture',
    );
    final source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Private',
      location: media.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    video = (sourceId: source.id, localId: 'private-film.mkv');
    diagnostics = PlaybackDiagnostics(
      directory: () async => Directory(p.join(sandbox.path, 'logs')),
      writerId: '111-222',
    );
  });
  tearDown(() async {
    await session?.close(discardProgress: true);
    session?.dispose();
    session = null;
    await diagnostics.close();
    await sources.close();
    await sandbox.delete(recursive: true);
  });

  test(
    'cleanup failure preserves HTTP error, clears loading, and allows retry',
    () async {
      var created = 0;
      final player = session = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        diagnostics: diagnostics,
        createEngine: () => ++created == 1
            ? _FailureEngine(
                issue: const PlaybackIssue('http', status: 503),
                cleanupFailure: true,
              )
            : _FailureEngine(),
      );
      await player.open(video);
      expect(player.loading, isFalse);
      expect(player.error, contains('503'));
      await player.open(video);
      expect(player.error, isNull);
      expect(player.clock.playing, isTrue);
      await diagnostics.flush();
      final text = await File(
        p.join(sandbox.path, 'logs/playback-111-222.jsonl'),
      ).readAsString();
      expect(text, contains('candidate_dispose_failed'));
      expect(text, contains('open_succeeded'));
      expect(text, isNot(contains('private-film')));
      expect(text, isNot(contains('sensitive')));
    },
  );

  test(
    'preview failures are deduplicated and never log private decoder details',
    () async {
      var succeeds = false;
      final player = session = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        diagnostics: diagnostics,
        createEngine: _FailureEngine.new,
        previewGenerator: (_, _, _) async {
          if (succeeds) return Uint8List.fromList([1]);
          throw StateError(
            'https://private.invalid/video?api_key=secret-token',
          );
        },
      );
      await player.open(video);
      for (final seconds in [10, 30]) {
        expect(
          await player.requestPreview(
            time: Duration(seconds: seconds),
            duration: const Duration(seconds: 100),
            coarse: false,
          ),
          isNull,
        );
      }
      succeeds = true;
      for (final seconds in [50, 70]) {
        expect(
          await player.requestPreview(
            time: Duration(seconds: seconds),
            duration: const Duration(seconds: 100),
            coarse: false,
          ),
          isNotNull,
        );
      }
      expect(player.error, isNull);
      expect(player.controlError, isNull);
      await diagnostics.flush();
      final text = await File(
        p.join(sandbox.path, 'logs/playback-111-222.jsonl'),
      ).readAsString();
      expect('preview_unavailable'.allMatches(text).length, 1);
      expect('preview_generated'.allMatches(text).length, 1);
      expect('preview_started'.allMatches(text).length, 4);
      expect('preview_finished'.allMatches(text).length, 4);
      expect(text, contains('preview_exception'));
      for (final secret in [
        'private.invalid',
        'secret-token',
        'private-film',
        sandbox.path,
      ]) {
        expect(text, isNot(contains(secret)));
      }
    },
  );

  test('cancelled preview attempts are observable and diagnostic volume is bounded', () async {
    var calls = 0;
    final player = session = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      diagnostics: diagnostics,
      createEngine: _FailureEngine.new,
      previewGenerator: (_, _, cancellation) async {
        calls++;
        await cancellation.whenCancelled;
        return null;
      },
    );
    await player.open(video);
    for (var i = 0; i < 12; i++) {
      final cancellation = VideoPreviewCancellation();
      final pending = player.requestPreview(
        time: Duration(seconds: i * 20),
        duration: const Duration(seconds: 500),
        coarse: false,
        cancellation: cancellation,
      );
      cancellation.cancel();
      expect(await pending, isNull);
      await Future<void>.delayed(Duration.zero);
    }
    expect(calls, 12);
    await diagnostics.flush();
    final text = await File(p.join(sandbox.path, 'logs/playback-111-222.jsonl'))
        .readAsString();
    expect('preview_started'.allMatches(text).length, 8);
    expect('preview_cancelled'.allMatches(text).length, 8);
    expect(text, isNot(contains('preview_unavailable')));
    expect(player.error, isNull);
  });

  test(
    'surface failure is diagnosed separately and releases committed engine',
    () async {
      final engine = _FailureEngine();
      final player = session = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        diagnostics: diagnostics,
        createEngine: () => engine,
        waitForSurface: () async =>
            throw TimeoutException('private surface detail'),
      );
      await player.open(video);
      expect(player.error, contains('超时'));
      expect(player.loading, isFalse);
      expect(engine.disposals, 1);
      expect(player.engine, isNull);
      await diagnostics.flush();
      final text = await File(
        p.join(sandbox.path, 'logs/playback-111-222.jsonl'),
      ).readAsString();
      expect(text, contains('"stage":"surface"'));
      expect(text, contains('"code":"timeout"'));
      expect(text, isNot(contains('private surface')));
    },
  );
}
