import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/playback/application/playback_marker_analysis_controller.dart';
import 'package:reelnest/features/playback/data/marker_analysis_repository.dart';
import 'package:reelnest/features/playback/data/playback_marker_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/marker_analysis_task.dart';
import 'package:reelnest/features/playback/domain/playback_marker.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/data/remote_index_writer.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

class _ControlledAnalysis extends MarkerAnalysisRepository {
  _ControlledAnalysis(super.sources);
  Future<void> Function(MarkerAnalysisTarget, ScanCancellation)? before;
  @override
  Future<int> analyze(
    MarkerAnalysisPlan plan,
    MarkerAnalysisTarget target,
    ScanCancellation cancellation,
  ) async {
    await before?.call(target, cancellation);
    return super.analyze(plan, target, cancellation);
  }
}

class _CancelAfterGeneration extends PlaybackMarkerRepository {
  _CancelAfterGeneration(super.database);
  @override
  Future<int> generateIntroOutroCandidates(
    MediaIdentity identity, {
    required Duration duration,
    ScanCancellation? cancellation,
  }) async {
    final count = await super.generateIntroOutroCandidates(
      identity,
      duration: duration,
      cancellation: cancellation,
    );
    cancellation!.cancel();
    return count;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SourceRepository sources;
  late MediaSource source;
  late IndexedMedia series;
  late IndexedMedia film;
  late List<IndexedMedia> episodes;
  late PlaybackMarkerRepository markers;
  late _ControlledAnalysis repository;
  PlaybackMarkerAnalysisController? controller;

  Future<void> saveDuration(MediaIdentity id, int seconds) =>
      PlaybackRepository(sources.database).save(
        id,
        position: Duration.zero,
        duration: Duration(seconds: seconds),
      );
  Future<void> chapters(MediaIdentity id) => markers.replaceEmbedded(id, [
    PlaybackMarker(
      id: 'intro',
      identity: id,
      kind: PlaybackMarkerKind.chapter,
      title: 'Opening',
      start: Duration.zero,
      end: const Duration(seconds: 20),
      origin: PlaybackMarkerOrigin.embedded,
    ),
    PlaybackMarker(
      id: 'end',
      identity: id,
      kind: PlaybackMarkerKind.chapter,
      title: 'Credits',
      start: const Duration(seconds: 80),
      end: const Duration(seconds: 100),
      origin: PlaybackMarkerOrigin.embedded,
    ),
  ]);
  Future<MarkerAnalysisTask> finished(String id) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(end)) {
      final task = controller!.tasks.value.where((t) => t.id == id).firstOrNull;
      if (task != null && !task.active) return task;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Marker analysis did not settle');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reelnest-marker-batch-');
    for (final name in [
      'Film.mkv',
      'Show.S01E01.mkv',
      'Show.S01E02.mkv',
      'Show.S01E03.mkv',
    ]) {
      await File(p.join(directory.path, name)).writeAsString('fixture');
    }
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'batch-fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Test',
      location: directory.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    final items = (await sources.inventory()).items;
    series = items.singleWhere((m) => m.isSeries);
    episodes =
        items.where((m) => m.parentId == series.identity.localId).toList()
          ..sort((a, b) => a.episodeNumber!.compareTo(b.episodeNumber!));
    film = items.singleWhere((m) => m.identity.localId == 'Film.mkv');
    markers = PlaybackMarkerRepository(sources.database);
    for (final item in [film, ...episodes]) {
      await saveDuration(item.identity, 100);
      await chapters(item.identity);
    }
    repository = _ControlledAnalysis(sources);
    controller = null;
  });
  tearDown(() async {
    await controller?.dispose();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
    expect(p.basename(directory.path), startsWith('reelnest-marker-batch-'));
    await directory.delete(recursive: true);
  });

  test(
    'eligibility uses direct children, known duration over 60s and video types',
    () async {
      expect(await repository.canAnalyze(series.identity), isTrue);
      expect(
        (await repository.plan(series.identity)).targets.map((t) => t.identity),
        episodes.map((m) => m.identity),
      );
      expect(
        (await repository.plan(episodes.first.identity))
            .targets
            .single
            .identity,
        episodes.first.identity,
      );
      await saveDuration(episodes.first.identity, 60);
      expect((await repository.plan(series.identity)).targets, hasLength(2));
      await sources.database.customStatement(
        "UPDATE media SET type='music' WHERE source_id=? AND local_id=?",
        [source.id, episodes[1].identity.localId],
      );
      await sources.database.customStatement(
        'DELETE FROM playback_states WHERE source_id=? AND local_id=?',
        [source.id, episodes[2].identity.localId],
      );
      expect(await repository.canAnalyze(series.identity), isFalse);
      expect(
        await repository.canAnalyze((sourceId: source.id, localId: 'removed')),
        isFalse,
      );
      // Unknown clocks do not become eligible merely because cached chapters exist.
      expect(await markers.read(episodes.last.identity), hasLength(2));
    },
  );

  test('series jobs create pending candidates with progress and no duplicate on repeat', () async {
    final changed = <Set<String>>[];
    controller = PlaybackMarkerAnalysisController(
      repository,
      onMarkersChanged: (ids) async => changed.add(ids),
    );
    final id = await controller!.enqueue(series.identity);
    final result = await finished(id);
    expect(result.state, MarkerAnalysisState.completed);
    expect(result.total, 3);
    expect(result.processed, 3);
    expect(result.createdCandidates, 6);
    expect(result.progress, 1);
    for (final episode in episodes) {
      final rows = await markers.read(episode.identity);
      expect(rows.where((m) => m.isPendingReview), hasLength(2));
    }
    await controller!
        .dispose(); // Also awaits completion notifications/history.
    expect(changed.single, {source.id});
    controller = PlaybackMarkerAnalysisController(repository);
    final again = await finished(await controller!.enqueue(series.identity));
    expect(again.createdCandidates, 0);
    expect(again.skipped, 3);
    expect(again.detail, '没有发现可审核候选');
  });

  test(
    'concurrent enqueue coalesces one root and queued cancel never analyzes it',
    () async {
      final entered = Completer<void>(), gate = Completer<void>();
      repository.before = (target, cancellation) async {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
        cancellation.check();
      };
      controller = PlaybackMarkerAnalysisController(repository);
      try {
        final ids = await Future.wait([
          controller!.enqueue(series.identity),
          controller!.enqueue(series.identity),
        ]);
        expect(ids[0], ids[1]);
        await entered.future;
        expect(await controller!.enqueue(series.identity), ids[0]);
        final queued = await controller!.enqueue(film.identity);
        expect(controller!.tasks.value.first.state, MarkerAnalysisState.queued);
        controller!.cancel(queued);
        expect((await finished(queued)).state, MarkerAnalysisState.cancelled);
        await controller!.clearFinished();
        expect(controller!.tasks.value.single.id, ids[0]);
        expect(
          (await markers.read(film.identity)).where((m) => m.isPendingReview),
          isEmpty,
        );
      } finally {
        gate.complete();
      }
    },
  );

  test('cancel during a later video preserves earlier commits and skips following videos', () async {
    final second = Completer<void>(), gate = Completer<void>();
    repository.before = (target, token) async {
      if (target.identity == episodes[1].identity) {
        second.complete();
        await gate.future;
        token.check();
      }
    };
    controller = PlaybackMarkerAnalysisController(repository);
    final id = await controller!.enqueue(series.identity);
    try {
      await second.future;
      controller!.cancel(id);
    } finally {
      gate.complete();
    }
    final result = await finished(id);
    expect(result.state, MarkerAnalysisState.cancelled);
    expect(result.processed, 1);
    expect(result.createdCandidates, 2);
    expect(
      (await markers.read(episodes.first.identity))
          .where((m) => m.isPendingReview),
      hasLength(2),
    );
    expect(
      (await markers.read(episodes[1].identity))
          .where((m) => m.isPendingReview),
      isEmpty,
    );
    expect(
      (await markers.read(episodes.last.identity))
          .where((m) => m.isPendingReview),
      isEmpty,
    );
    expect(await controller!.retry(id), isNull);
  });

  test('failure keeps earlier candidates and retry resolves fresh targets without duplication', () async {
    repository.before = (target, _) async {
      if (target.identity == episodes[1].identity) {
        throw StateError('do not expose fixture secret');
      }
    };
    controller = PlaybackMarkerAnalysisController(repository);
    final id = await controller!.enqueue(series.identity);
    final failed = await finished(id);
    expect(failed.state, MarkerAnalysisState.failed);
    expect(failed.processed, 1);
    expect(failed.createdCandidates, 2);
    expect(failed.error, '片头片尾检测失败，请重试。');
    expect(controller!.canRetry(failed), isTrue);
    repository.before = null;
    final retried = (await controller!.retry(id))!;
    final result = await finished(retried);
    expect(result.createdCandidates, 4);
    expect(result.skipped, 1);
    expect(controller!.tasks.value, hasLength(2));
    for (final item in episodes) {
      expect(
        (await markers.read(item.identity)).where((m) => m.isPendingReview),
        hasLength(2),
      );
    }
  });

  test(
    'scope changes and replaced content reject a stale plan before writing',
    () async {
      final plan = await repository.plan(film.identity);
      await sources.database.customStatement(
        'UPDATE media SET bytes=bytes+1 WHERE source_id=? AND local_id=?',
        [source.id, film.identity.localId],
      );
      await expectLater(
        repository.analyze(plan, plan.targets.single, ScanCancellation()),
        throwsA(isA<SourceFailure>()),
      );
      expect(
        (await markers.read(film.identity)).where((m) => m.isPendingReview),
        isEmpty,
      );
      final refreshed = await repository.plan(film.identity);
      await sources.database.customStatement(
        "UPDATE sources SET access_identity='replaced-volume' WHERE id=?",
        [source.id],
      );
      await expectLater(
        repository.analyze(
          refreshed,
          refreshed.targets.single,
          ScanCancellation(),
        ),
        throwsA(isA<SourceFailure>()),
      );
      expect(
        (await markers.read(film.identity)).where((m) => m.isPendingReview),
        isEmpty,
      );
    },
  );

  test(
    'unavailable roots fail before creating a job or clearing existing markers',
    () async {
      controller = PlaybackMarkerAnalysisController(repository);
      await sources.removeIndexedItems({film.identity});
      await expectLater(
        controller!.enqueue(film.identity),
        throwsA(isA<SourceFailure>()),
      );
      expect(controller!.tasks.value, isEmpty);
      expect(await repository.canAnalyze(film.identity), isFalse);
    },
  );

  test(
    'history restores interrupted work as failed and clears only records',
    () async {
      final now = DateTime.now().toUtc();
      final interrupted = MarkerAnalysisTask(
        id: 'interrupted',
        root: series.identity,
        title: '片头片尾检测 · Show',
        startedAt: now,
        state: MarkerAnalysisState.running,
        total: 3,
        processed: 1,
        createdCandidates: 2,
      );
      await sources.database.customStatement(
        'INSERT INTO player_preferences(key,value) VALUES(?,?)',
        [
          PlaybackMarkerAnalysisController.historyKey,
          jsonEncode([interrupted.toJson()]),
        ],
      );
      controller = PlaybackMarkerAnalysisController(repository);
      await controller!.ready;
      final restored = controller!.tasks.value.single;
      expect(restored.state, MarkerAnalysisState.failed);
      expect(restored.detail, '上次退出时任务尚未完成。');
      expect(controller!.canRetry(restored), isTrue);
      final done = await finished((await controller!.retry(restored.id))!);
      expect(done.createdCandidates, 6);
      await controller!.clearFinished();
      expect(controller!.tasks.value, isEmpty);
      expect(
        (await markers.read(episodes.first.identity))
            .where((m) => m.isPendingReview),
        hasLength(2),
      );
      await controller!.dispose();
      controller = PlaybackMarkerAnalysisController(repository);
      await controller!.ready;
      expect(controller!.tasks.value, isEmpty);
    },
  );

  test('private task snapshots hide names and a later privacy change redacts history', () async {
    controller = PlaybackMarkerAnalysisController(repository);
    await finished(await controller!.enqueue(film.identity));
    await sources.updateSettings(
      source.id,
      mediaType: SourceMediaType.privateCollection,
      options: source.options,
    );
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (!controller!.tasks.value.single.hidesDetail &&
        DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller!.tasks.value.single.title, '片头片尾检测');
    expect(controller!.tasks.value.single.detail, '条目、路径和文件名已隐藏');
    await controller!.dispose();
    controller = PlaybackMarkerAnalysisController(repository);
    await controller!.ready;
    expect(controller!.tasks.value.single.title, '片头片尾检测');
  });

  test(
    'shutdown cancels queued/running work and waits before the database closes',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      repository.before = (_, token) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        token.check();
      };
      controller = PlaybackMarkerAnalysisController(repository);
      await controller!.enqueue(series.identity);
      await entered.future;
      await controller!.enqueue(film.identity);
      var closed = false;
      final closing = controller!.dispose().then((_) => closed = true);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(closed, isFalse);
        await expectLater(
          controller!.enqueue(film.identity),
          throwsA(isA<SourceFailure>()),
        );
      } finally {
        release.complete();
      }
      await closing;
      controller = null;
      final rows = await sources.database
          .customSelect(
            'SELECT value FROM player_preferences WHERE key=?',
            variables: [
              const Variable(PlaybackMarkerAnalysisController.historyKey),
            ],
          )
          .getSingle();
      final json = jsonDecode(rows.read<String>('value')) as List;
      expect(json.every((row) => row['state'] == 'cancelled'), isTrue);
      expect(await markers.read(film.identity), hasLength(2));
    },
  );

  test('remote runtime works without a playback clock and identical IDs stay source scoped', () async {
    final remote = await sources.add(
      kind: MediaSourceKind.emby,
      name: 'Remote',
      location: 'emby://fixture/server',
    );
    final remoteId = (sourceId: remote.id, localId: film.identity.localId);
    await sources.database.transaction(
      () => RemoteIndexWriter(sources.database).write(
        remote.id,
        [
          IndexedMedia(
            identity: remoteId,
            title: 'Remote Film',
            type: 'movie',
            bytes: 10,
            modified: DateTime.utc(2026),
            remote: const RemoteMediaMetadata(
              externalId: 'remote-movie',
              durationMs: 100000,
            ),
          ),
        ],
        traceMode: RemoteTraceSyncMode.disabled,
        cancellation: ScanCancellation(),
      ),
    );
    await chapters(remoteId);
    // The sync writer seeds a zero-position clock; remove that fixture row to
    // prove eligibility also works from server runtime alone.
    await sources.database.customStatement(
      'DELETE FROM playback_states WHERE source_id=? AND local_id=?',
      [remote.id, remoteId.localId],
    );
    expect(
      (await PlaybackRepository(sources.database).read(remoteId)).duration,
      Duration.zero,
    );
    expect(await repository.canAnalyze(remoteId), isTrue);
    controller = PlaybackMarkerAnalysisController(repository);
    expect(
      (await finished(await controller!.enqueue(remoteId))).createdCandidates,
      2,
    );
    expect(
      (await markers.read(film.identity)).where((m) => m.isPendingReview),
      isEmpty,
    );
    expect(
      (await markers.read(remoteId)).where((m) => m.isPendingReview),
      hasLength(2),
    );
    await sources.database.customStatement(
      "UPDATE remote_media_metadata SET value=json_set(value,'\$.libraryId','A') WHERE source_id=? AND local_id=?",
      [remote.id, remoteId.localId],
    );
    await sources.updateSettings(
      remote.id,
      options: SourceOptions(selectedEmbyLibraryIDs: ['A']),
    );
    expect(await repository.canAnalyze(remoteId), isTrue);
    // A deselected library may remain cached. A new job/retry cannot analyze it.
    await sources.updateSettings(
      remote.id,
      options: SourceOptions(selectedEmbyLibraryIDs: ['B']),
    );
    expect(await repository.canAnalyze(remoteId), isFalse);
    await expectLater(
      controller!.enqueue(remoteId),
      throwsA(isA<SourceFailure>()),
    );
  });

  test('restore keeps 60 records and enqueue applies the original 40-record insertion limit', () async {
    final records = List.generate(
      75,
      (i) => MarkerAnalysisTask(
        id: 'history-$i',
        root: film.identity,
        title: 'Task',
        startedAt: DateTime.utc(2026),
        state: MarkerAnalysisState.completed,
      ),
    );
    await sources.database.customStatement(
      'INSERT INTO player_preferences(key,value) VALUES(?,?)',
      [
        PlaybackMarkerAnalysisController.historyKey,
        jsonEncode(records.map((t) => t.toJson()).toList()),
      ],
    );
    controller = PlaybackMarkerAnalysisController(repository);
    await controller!.ready;
    expect(controller!.tasks.value, hasLength(60));
    final result = await finished(await controller!.enqueue(film.identity));
    expect(result.state, MarkerAnalysisState.completed);
    expect(controller!.tasks.value, hasLength(40));
    expect(controller!.tasks.value.first.id, result.id);
  });

  test(
    'cancellation after inner generation rolls back the outer per-video commit',
    () async {
      final guarded = MarkerAnalysisRepository(
        sources,
        markers: _CancelAfterGeneration(sources.database),
      );
      final plan = await guarded.plan(film.identity);
      await expectLater(
        guarded.analyze(plan, plan.targets.single, ScanCancellation()),
        throwsA(isA<ScanCancelled>()),
      );
      expect(
        (await markers.read(film.identity)).where((m) => m.isPendingReview),
        isEmpty,
      );
      expect(
        await repository.analyze(
          await repository.plan(film.identity),
          plan.targets.single,
          ScanCancellation(),
        ),
        2,
      );
    },
  );

  test('history read/write errors remain visible without exposing database failures', () async {
    await sources.database.customStatement(
      'INSERT INTO player_preferences(key,value) VALUES(?,?)',
      [PlaybackMarkerAnalysisController.historyKey, 'not json'],
    );
    controller = PlaybackMarkerAnalysisController(repository);
    await controller!.ready;
    expect(controller!.historyError, contains('读取失败'));
    await sources.database.customStatement('''
      CREATE TRIGGER block_task_write BEFORE UPDATE ON player_preferences
      WHEN NEW.key='global.markerAnalysisTasks' BEGIN SELECT RAISE(ABORT,'fixture secret'); END
    ''');
    await finished(await controller!.enqueue(film.identity));
    await controller!.dispose();
    expect(controller!.historyError, contains('保存失败'));
    controller = null;
    expect(
      (await markers.read(film.identity)).where((m) => m.isPendingReview),
      hasLength(2),
    );
  });
}
