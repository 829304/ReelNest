import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../../domain/runtime_status.dart';
import '../data/marker_analysis_repository.dart';
import '../domain/marker_analysis_task.dart';

class _AnalysisRequest {
  _AnalysisRequest(this.id, this.plan);
  final String id;
  final MarkerAnalysisPlan plan;
  final cancellation = ScanCancellation();
  final done = Completer<void>();
  bool cancelled = false;
}

/// One serialized writer for markerAnalysis jobs. Per-video commits survive a
/// later failure/cancellation, while an interrupted individual commit rolls back.
class PlaybackMarkerAnalysisController {
  PlaybackMarkerAnalysisController(
    this.repository, {
    this.onTasks,
    this.onMarkersChanged,
  }) {
    ready = _restore();
    _sourceChanges = repository.sources.changes.listen((_) {
      _privacyWork = _privacyWork.then((_) => _refreshPrivacy());
    });
  }
  final MarkerAnalysisRepository repository;
  final void Function(List<MarkerAnalysisTask>)? onTasks;
  final Future<void> Function(Set<String>)? onMarkersChanged;
  final tasks = ValueNotifier<List<MarkerAnalysisTask>>(const []);
  late final Future<void> ready;
  late final StreamSubscription<void> _sourceChanges;
  String? historyError;
  static const historyKey = 'global.markerAnalysisTasks';
  final _queue = <_AnalysisRequest>[];
  final _requests = <MediaIdentity, _AnalysisRequest>{};
  final _starting = <MediaIdentity, Future<String>>{};
  final _privacySourceKeys = <String, String>{};
  Future<void>? _draining, _closing;
  Future<void> _writes = Future.value(), _privacyWork = Future.value();
  bool _closed = false;

  void _checkOpen() {
    if (_closing != null || _closed) throw const SourceFailure('片头片尾检测正在关闭。');
  }

  bool canRetry(MarkerAnalysisTask task) =>
      _closing == null &&
      !_closed &&
      task.state == MarkerAnalysisState.failed &&
      !_requests.containsKey(task.root) &&
      !_starting.containsKey(task.root);

  Future<String> enqueue(MediaIdentity root) {
    try {
      _checkOpen();
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    return _starting.putIfAbsent(root, () {
      final work = _enqueue(root);
      unawaited(
        work.then<void>(
          (_) => _starting.remove(root),
          onError: (Object _, StackTrace _) {
            _starting.remove(root);
          },
        ),
      );
      return work;
    });
  }

  Future<String> _enqueue(MediaIdentity root) async {
    await ready;
    _checkOpen();
    final existing = _requests[root];
    if (existing != null) {
      if (!existing.cancelled) return existing.id;
      await existing.done.future;
      _checkOpen();
    }
    final plan = await repository.plan(root);
    _checkOpen();
    if (plan.targets.isEmpty) throw const SourceFailure('这个条目没有可分析的视频。');
    final random = Random.secure();
    final id =
        'marker-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final request = _AnalysisRequest(id, plan);
    _requests[root] = request;
    _queue.add(request);
    final snapshots = [
      MarkerAnalysisTask(
        id: id,
        root: root,
        title: plan.title,
        startedAt: DateTime.now().toUtc(),
        total: plan.targets.length,
        hidesDetail: plan.hidesDetail,
      ),
      ...tasks.value,
    ];
    // Original insertion limit is 40; never evict a still-running request.
    var historySlots = max(0, 40 - snapshots.where((t) => t.active).length);
    _publish(snapshots.where((t) => t.active || historySlots-- > 0).toList());
    await _persist();
    // Shutdown may have begun while writing the queued snapshot.
    if (_closing != null) cancel(id);
    _startDrain();
    return id;
  }

  void _publish(List<MarkerAnalysisTask> values) {
    if (_closed) return;
    tasks.value = List.unmodifiable(values);
    onTasks?.call(tasks.value);
  }

  MarkerAnalysisTask? _task(String id) =>
      tasks.value.where((t) => t.id == id).firstOrNull;
  void _update(MarkerAnalysisTask task) =>
      _publish([for (final old in tasks.value) old.id == task.id ? task : old]);

  void _startDrain() {
    if (_draining != null) return;
    final work = _drain();
    _draining = work;
    unawaited(
      work.whenComplete(() {
        _draining = null;
        if (_queue.isNotEmpty) _startDrain();
      }),
    );
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final request = _queue.removeAt(0);
      final changedSources = <String>{};
      try {
        request.cancellation.check();
        _update(
          _task(request.id)!.copyWith(state: MarkerAnalysisState.running),
        );
        for (final target in request.plan.targets) {
          request.cancellation.check();
          final count = await repository.analyze(
            request.plan,
            target,
            request.cancellation,
          );
          if (count > 0) changedSources.add(target.identity.sourceId);
          final task = _task(request.id)!;
          _update(
            task.copyWith(
              processed: task.processed + 1,
              createdCandidates: task.createdCandidates + count,
              skipped: task.skipped + (count == 0 ? 1 : 0),
            ),
          );
        }
        request.cancellation.check();
        _update(
          _task(request.id)!.copyWith(
            state: MarkerAnalysisState.completed,
            finishedAt: DateTime.now().toUtc(),
          ),
        );
      } on ScanCancelled {
        final task = _task(request.id);
        if (task != null) {
          _update(
            task.copyWith(
              state: MarkerAnalysisState.cancelled,
              finishedAt: DateTime.now().toUtc(),
            ),
          );
        }
      } catch (error) {
        final task = _task(request.id);
        if (task != null) {
          _update(
            task.copyWith(
              state: request.cancelled
                  ? MarkerAnalysisState.cancelled
                  : MarkerAnalysisState.failed,
              error: error is SourceFailure ? error.message : '片头片尾检测失败，请重试。',
              finishedAt: DateTime.now().toUtc(),
            ),
          );
        }
      } finally {
        _requests.remove(request.plan.root);
        if (!request.done.isCompleted) request.done.complete();
        await _persist();
        if (changedSources.isNotEmpty) {
          try {
            await onMarkersChanged
                ?.call(changedSources)
                .timeout(const Duration(seconds: 3));
          } catch (_) {
            // A closed player does not invalidate already committed candidates.
          }
        }
      }
    }
  }

  void cancel(String id) {
    if (_closed) return;
    final request = _requests.values.where((r) => r.id == id).firstOrNull;
    if (request == null) return;
    request.cancelled = true;
    request.cancellation.cancel();
    if (_queue.remove(request)) {
      final task = _task(id)!;
      _update(
        task.copyWith(
          state: MarkerAnalysisState.cancelled,
          finishedAt: DateTime.now().toUtc(),
        ),
      );
      _requests.remove(request.plan.root);
      if (!request.done.isCompleted) request.done.complete();
      unawaited(_persist());
    }
  }

  Future<String?> retry(String id) async {
    await ready;
    _checkOpen();
    final task = _task(id);
    if (task == null || !canRetry(task)) return null;
    // Re-resolve current children/durations/scope, never replay stale targets.
    return enqueue(task.root);
  }

  Future<void> clearFinished() async {
    await ready;
    _checkOpen();
    _publish(tasks.value.where((t) => t.active).toList());
    await _persist();
  }

  Future<bool> _isPrivate(MediaIdentity root) async {
    try {
      final source = await repository.sources.source(
        root.sourceId,
        includeCounts: false,
      );
      if (source.mediaType == SourceMediaType.privateCollection) return true;
      final row = await repository.sources.database
          .customSelect(
            '''
        WITH RECURSIVE ancestors(local_id,parent_id,type) AS (
          SELECT local_id,parent_id,type FROM media WHERE source_id=? AND local_id=?
          UNION SELECT m.local_id,m.parent_id,m.type FROM media m
            JOIN ancestors a ON m.local_id=a.parent_id WHERE m.source_id=?
        ) SELECT 1 FROM ancestors WHERE type IN ('private','privateCollection') LIMIT 1
      ''',
            variables: [
              Variable(root.sourceId),
              Variable(root.localId),
              Variable(root.sourceId),
            ],
          )
          .getSingleOrNull();
      return row != null;
    } catch (_) {
      return true; // Deleted/unavailable sources cannot expose old task titles.
    }
  }

  Future<void> _refreshPrivacy() async {
    await ready;
    if (_closed) return;
    // Browsing pages and watch-state writes also emit source changes. A single
    // configuration read avoids walking every historical root on each page.
    final versions = <String, String>{};
    try {
      for (final source in await repository.sources.sources(
        includeCounts: false,
      )) {
        versions[source.id] = runtimeSourceKey(source);
      }
    } catch (_) {
      // Missing versions take the conservative per-root redaction path below.
    }
    var changed = false;
    final snapshots = tasks.value.toList();
    for (final task in snapshots) {
      final version = versions[task.root.sourceId];
      if (version != null &&
          _privacySourceKeys[task.root.sourceId] == version) {
        continue;
      }
      if (task.hidesDetail || !await _isPrivate(task.root)) continue;
      if (_closed) return;
      final latest = _task(task.id);
      if (latest != null) {
        _update(latest.copyWith(hidesDetail: true));
        changed = true;
      }
    }
    _privacySourceKeys
      ..clear()
      ..addAll(versions);
    if (changed) await _persist();
  }

  Future<void> _restore() async {
    try {
      final row = await repository.sources.database
          .customSelect(
            'SELECT value FROM player_preferences WHERE key=?',
            variables: [const Variable(historyKey)],
          )
          .getSingleOrNull();
      if (row == null) return;
      final text = row.read<String>('value');
      if (text.length > 1024 * 1024) {
        throw const FormatException('Marker history too large');
      }
      final json = jsonDecode(text) as List;
      final loaded = <MarkerAnalysisTask>[];
      for (final data in json.take(60)) {
        var task = MarkerAnalysisTask.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        final private = task.hidesDetail || await _isPrivate(task.root);
        task = task.copyWith(hidesDetail: private);
        if (task.active) {
          task = task.copyWith(
            state: MarkerAnalysisState.failed,
            error: '上次退出时任务尚未完成。',
            finishedAt: DateTime.now().toUtc(),
          );
        }
        loaded.add(task);
      }
      _publish(loaded);
    } catch (_) {
      historyError = '片头片尾检测任务记录读取失败，请重试。';
      _publish(tasks.value);
    }
  }

  Future<void> _persist() {
    final data = jsonEncode(
      tasks.value.take(60).map((t) => t.toJson()).toList(),
    );
    final work = _writes.then((_) async {
      try {
        await repository.sources.database.customStatement(
          'INSERT INTO player_preferences(key,value) VALUES(?,?) '
          'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          [historyKey, data],
        );
        if (historyError != null) {
          historyError = null;
          _publish(tasks.value);
        }
      } catch (_) {
        historyError = '片头片尾检测任务记录保存失败，当前候选仍保留。';
        _publish(tasks.value);
      }
    });
    _writes = work;
    return work;
  }

  Future<void> dispose() => _closing ??= _dispose();
  Future<void> _dispose() async {
    await ready;
    await _sourceChanges.cancel();
    for (final request in _requests.values.toList()) {
      cancel(request.id);
    }
    await Future.wait(
      _starting.values.map((f) async {
        try {
          await f;
        } catch (_) {}
      }),
    );
    await _draining;
    await _privacyWork;
    await _writes;
    _closed = true;
    tasks.dispose();
  }
}
