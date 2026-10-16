import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../storage/runtime_storage_paths.dart';

/// Structured diagnostics only: callers must never pass media, URLs or messages.
class PlaybackDiagnostics {
  PlaybackDiagnostics({
    Future<Directory> Function()? directory,
    this.maxBytes = 512 * 1024,
    this.maxFiles = 20,
    String? writerId,
  }) : _directory = directory ?? _defaultDirectory,
       _writerId = writerId ?? '$pid-${DateTime.now().microsecondsSinceEpoch}';

  static Future<Directory> _defaultDirectory() async =>
      RuntimeStoragePaths.current.logs();

  final Future<Directory> Function() _directory;
  final String _writerId;
  final int maxBytes;
  final int maxFiles;
  Future<void> _pending = Future.value();
  File? _file;
  int _queued = 0;
  int _sequence = 0;
  bool _closed = false;
  bool get available => _file != null;

  PlaybackTrace begin() => PlaybackTrace._(this, '$_writerId-${++_sequence}');

  void _write(Map<String, Object?> entry) {
    if (_closed || _queued >= 256) return;
    _queued++;
    _pending = _pending
        .then((_) async {
          final directory = await _directory();
          await directory.create(recursive: true);
          final file = _file ??= File(
            p.join(directory.path, 'playback-$_writerId.jsonl'),
          );
          if (await file.exists() && await file.length() >= maxBytes) {
            final previous = File('${file.path}.previous');
            if (await previous.exists()) await previous.delete();
            await file.rename(previous.path);
          }
          if (!await file.exists()) await _prune(directory);
          await file.writeAsString(
            '${jsonEncode({'time': DateTime.now().toUtc().toIso8601String(), ...entry})}\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object _) {
          // Diagnostics must never block or replace the original playback result.
        })
        .whenComplete(() => _queued--);
  }

  Future<void> _prune(Directory directory) async {
    final files = <(File, DateTime)>[];
    final pattern = RegExp(r'^playback-[0-9]+-[0-9]+\.jsonl(?:\.previous)?$');
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !pattern.hasMatch(p.basename(entry.path))) continue;
      if (entry.path == _file?.path) continue;
      files.add((entry, (await entry.stat()).modified));
    }
    files.sort((a, b) => b.$2.compareTo(a.$2));
    final oldest = DateTime.now().subtract(const Duration(days: 7));
    for (var i = 0; i < files.length; i++) {
      if (i >= maxFiles - 1 || files[i].$2.isBefore(oldest)) {
        try {
          await files[i].$1.delete();
        } on FileSystemException {
          // Other windows may be rotating a file at the same time.
        }
      }
    }
  }

  Future<void> flush() => _pending;
  Future<void> close() async {
    _closed = true;
    await flush();
  }
}

class PlaybackTrace {
  PlaybackTrace._(this._sink, this.id);
  final PlaybackDiagnostics _sink;
  final String id;
  final Stopwatch _watch = Stopwatch()..start();
  String _stage = 'begin';
  int _stageStart = 0;

  void stage(String value) {
    event(
      'stage_end',
      stage: _stage,
      durationMs: _watch.elapsedMilliseconds - _stageStart,
    );
    _stage = value;
    _stageStart = _watch.elapsedMilliseconds;
    event('stage_begin');
  }

  void event(
    String event, {
    String? stage,
    String? code,
    int? status,
    int? durationMs,
    bool? remote,
    bool? cached,
  }) => _sink._write({
    'attempt': id,
    'event': event,
    'stage': stage ?? _stage,
    'elapsedMs': _watch.elapsedMilliseconds,
    'platform': Platform.operatingSystem,
    'version': '0.1.0',
    'code': ?code,
    'status': ?status,
    'durationMs': ?durationMs,
    'remote': ?remote,
    'cached': ?cached,
  });

  void failure(
    String event,
    Object error,
    StackTrace stack, {
    PlaybackIssue? issue,
  }) {
    issue ??= PlaybackIssue.from(error);
    _sink._write({
      'attempt': id,
      'event': event,
      'stage': _stage,
      'elapsedMs': _watch.elapsedMilliseconds,
      'code': issue.code,
      if (issue.status != null) 'status': issue.status,
      // No exception.toString(): it can contain authenticated URLs and paths.
      'exception': error.runtimeType.toString(),
      'stack': safePlaybackStack(stack),
    });
  }
}

List<String> safePlaybackStack(StackTrace stack) => RegExp(
  r'(?:package:(?:reelnest|media_kit|media_kit_video)/|dart:)[A-Za-z0-9_./:-]+',
).allMatches(stack.toString()).take(12).map((m) => m.group(0)!).toList();

/// Classification consumes raw backend messages in memory, never persists them.
class PlaybackIssue implements Exception {
  const PlaybackIssue(this.code, {this.status});
  final String code;
  final int? status;

  static PlaybackIssue prefer(PlaybackIssue? previous, PlaybackIssue next) {
    // mpv often follows a precise HTTP failure with "failed to open". Keep
    // the actionable status instead of letting the generic final line hide it.
    if (previous != null &&
        ((previous.status != null && next.status == null) ||
            next.code == 'backend')) {
      return previous;
    }
    return next;
  }

  factory PlaybackIssue.from(Object error) {
    if (error is PlaybackIssue) return error;
    if (error is TimeoutException) return const PlaybackIssue('timeout');
    if (error is SocketException) return const PlaybackIssue('network');
    if (error is HandshakeException) return const PlaybackIssue('tls');
    if (error is FileSystemException) return const PlaybackIssue('filesystem');
    return const PlaybackIssue('unexpected');
  }

  factory PlaybackIssue.backend(String text) {
    final value = text.toLowerCase();
    final status = RegExp(
      r'(?:http(?: error)?(?: status)?|server returned)\s*[:=]?\s*([45][0-9]{2})\b',
    ).firstMatch(value);
    if (status != null) {
      return PlaybackIssue('http', status: int.parse(status.group(1)!));
    }
    if (value.contains('timed out') || value.contains('timeout')) {
      return const PlaybackIssue('timeout');
    }
    if (value.contains('tls') ||
        value.contains('certificate') ||
        value.contains('ssl')) {
      return const PlaybackIssue('tls');
    }
    if (value.contains('resolve') || value.contains('name or service')) {
      return const PlaybackIssue('dns');
    }
    if (value.contains('connection') ||
        value.contains('tcp:') ||
        value.contains('network')) {
      return const PlaybackIssue('network');
    }
    if (value.contains('decoder') ||
        value.contains('codec') ||
        value.contains('decod')) {
      return const PlaybackIssue('decoder');
    }
    if (value.contains('no such file') || value.contains('permission denied')) {
      return const PlaybackIssue('filesystem');
    }
    return const PlaybackIssue('backend');
  }

  String get message => switch (code) {
    'timeout' => '视频加载超时，请检查连接后重试。',
    'http' => '视频请求失败（HTTP $status），请检查服务器或重新认证后重试。',
    'network' || 'dns' => '视频连接失败或中断，请检查网络后重试。',
    'tls' => '视频安全连接失败，请检查服务器证书和系统时间。',
    'decoder' => '视频解码失败，请尝试其他画质或片源。',
    'filesystem' => '媒体文件无法读取，请检查文件、磁盘连接和权限。',
    'cancelled' => '视频加载已取消。',
    _ => '视频载入失败，请重试或检查播放诊断日志。',
  };

  @override
  String toString() =>
      'PlaybackIssue($code${status == null ? '' : ', $status'})';
}

abstract interface class DiagnosableVideoEngine {
  set diagnosticTrace(PlaybackTrace? trace);
}
