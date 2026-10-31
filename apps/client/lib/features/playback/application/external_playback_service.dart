import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../platform/external_player_gateway.dart';
import '../../../platform/transient_file_access.dart';
import '../../../player/playback_diagnostics.dart';
import '../../sources/data/source_repository.dart';
import '../../sources/data/url_video_repository.dart';
import '../data/external_player_settings_repository.dart';
import '../domain/transient_playback_target.dart';

abstract interface class ExternalPlaybackLauncher {
  Future<void> openLibrary(MediaIdentity identity);
  Future<void> openTransient(TransientPlaybackTarget target);
}

typedef ExternalCacheResource = ({String path, String lease});

/// Owned by the main engine. A launched process may hand playback to another
/// existing instance, so neither a PID nor an IPC acknowledgement proves EOF.
class ExternalPlaybackService implements ExternalPlaybackLauncher {
  ExternalPlaybackService({
    required this.sources,
    required this.settings,
    required this.gateway,
    this.acquireCache,
    this.renewCache,
    this.releaseCache,
    this.remoteResource,
    this.diagnostics,
    this.renewInterval = const Duration(seconds: 30),
    this.launchTimeout = const Duration(seconds: 12),
  });
  final SourceRepository sources;
  final ExternalPlayerSettingsRepository settings;
  final ExternalPlayerGateway gateway;
  final Future<ExternalCacheResource?> Function(MediaIdentity)? acquireCache;
  final Future<void> Function(String)? renewCache, releaseCache;
  final Future<String> Function(IndexedMedia)? remoteResource;
  final PlaybackDiagnostics? diagnostics;
  final Duration renewInterval;
  final Duration launchTimeout;
  final _retained = <String, _ExternalRetention>{};
  Future<void> _pending = Future.value();
  Future<void> _renewing = Future.value();
  Timer? _heartbeat;
  bool _renewPending = false, _closed = false;
  Future<void>? _disposing;
  int get retainedResources => _retained.length;

  Future<void> _run(Future<void> Function() work) {
    final operation = _pending.then((_) async {
      if (_closed) throw const SourceFailure('应用正在关闭，无法启动外部播放器。');
      try {
        await work();
      } on SourceFailure {
        rethrow;
      } catch (_) {
        throw const SourceFailure('外部播放器不可用，请检查应用路径和媒体连接后重试。');
      }
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<void> openLibrary(MediaIdentity identity) => _run(() async {
    final item = await sources.media(identity);
    if (item.isSeries || item.type == 'music' || item.type == 'photo') {
      throw const SourceFailure('请选择一个视频文件。');
    }
    final source = await sources.source(
      identity.sourceId,
      includeCounts: false,
    );
    ExternalCacheResource? cached;
    String location;
    if (source.kind.isFileSource) {
      location = p.normalize(
        p.joinAll([source.location, ...p.posix.split(identity.localId)]),
      );
      if (!p.isWithin(source.location, location) ||
          !await sources.isReachable(source)) {
        throw const SourceFailure('视频文件不存在或 NAS 未连接。');
      }
    } else if (source.kind == MediaSourceKind.url ||
        source.kind.isRemoteVideoSource) {
      try {
        cached = await acquireCache?.call(identity);
      } catch (_) {
        diagnostics?.begin().event(
          'external_cache_fallback',
          code: 'cache_unavailable',
        );
      }
      try {
        location =
            cached?.path ??
            (source.kind == MediaSourceKind.url
                ? await UrlVideoRepository(sources).location(identity)
                : await remoteResource?.call(item)) ??
            (throw const SourceFailure('无法获取服务器视频地址。'));
      } catch (_) {
        if (cached != null) await releaseCache?.call(cached.lease);
        rethrow;
      }
    } else {
      throw const SourceFailure('此媒体源尚不支持外部播放。');
    }
    await _launch(location, cached: cached);
  });

  @override
  Future<void> openTransient(TransientPlaybackTarget target) => _run(() async {
    await _launch(target.location, bookmark: target.securityBookmark);
  });

  Future<void> _launch(
    String location, {
    ExternalCacheResource? cached,
    Uint8List? bookmark,
  }) async {
    final trace = diagnostics?.begin();
    final uri = Uri.tryParse(location);
    final remote =
        uri != null && ['http', 'https'].contains(uri.scheme.toLowerCase());
    TransientFileAccess? mediaAccess, appAccess;
    var retained = false;
    try {
      trace?.event(
        'external_launch_begin',
        remote: remote,
        cached: cached != null,
      );
      if (!remote && !p.isAbsolute(location)) {
        throw const SourceFailure('外部播放器仅支持本地视频和 HTTP/HTTPS 地址。');
      }
      if (remote &&
          (uri.host.isEmpty || location.contains(RegExp(r'[\x00-\x20\x7f]')))) {
        throw const SourceFailure('媒体地址无效。');
      }
      final config = await settings.load();
      if (config.applicationPath != null) {
        appAccess = await TransientFileAccess.acquire(
          config.applicationPath!,
          bookmark: config.applicationBookmark,
        );
        await gateway.validateApplication(config.applicationPath!);
      }
      if (!remote) {
        mediaAccess = await TransientFileAccess.acquire(
          location,
          bookmark: bookmark,
        );
        if (!await File(location).exists()) {
          throw const SourceFailure('视频文件不存在或 NAS 未连接。');
        }
      }
      if (_closed) throw const SourceFailure('应用正在关闭，已取消启动外部播放器。');
      await gateway
          .launch(location, applicationPath: config.applicationPath)
          .timeout(launchTimeout);
      if (!_closed && (cached != null || mediaAccess?.bookmark != null)) {
        if (!_retained.containsKey(location)) {
          _retained[location] = _ExternalRetention(cached?.lease, mediaAccess);
          mediaAccess = null;
          retained = true;
          _startHeartbeat();
        }
      }
      trace?.event(
        'external_launch_succeeded',
        remote: remote,
        cached: cached != null,
      );
    } catch (error, stack) {
      // A timed-out native request may still start the app. Do not release a
      // cache lease based on an acknowledgement deadline or guess playback EOF.
      if (error is TimeoutException &&
          !_closed &&
          (cached != null || mediaAccess?.bookmark != null) &&
          !_retained.containsKey(location)) {
        _retained[location] = _ExternalRetention(cached?.lease, mediaAccess);
        mediaAccess = null;
        retained = true;
        _startHeartbeat();
      }
      trace?.failure('external_launch_failed', error, stack);
      if (error is TimeoutException) {
        throw const SourceFailure('未能确认外部播放器启动，请检查应用是否已打开。');
      }
      rethrow;
    } finally {
      try {
        await appAccess?.release();
      } catch (_) {
        trace?.event('external_scope_release_failed');
      }
      try {
        await mediaAccess?.release();
      } catch (_) {
        trace?.event('external_scope_release_failed');
      }
      if (!retained && cached != null) {
        try {
          await releaseCache?.call(cached.lease);
        } catch (_) {
          trace?.event('external_lease_release_failed');
        }
      }
    }
  }

  void _startHeartbeat() {
    _heartbeat ??= Timer.periodic(renewInterval, (_) {
      if (_closed || _renewPending) return;
      _renewPending = true;
      _renewing = Future<void>(() async {
        for (final value in _retained.values.toList()) {
          if (_closed) break;
          try {
            if (value.lease != null) await renewCache?.call(value.lease!);
          } catch (_) {
            diagnostics?.begin().event(
              'external_lease_renew_failed',
              code: 'cache_unavailable',
            );
          }
        }
      }).whenComplete(() => _renewPending = false);
    });
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    _heartbeat?.cancel();
    await _pending;
    await _renewing;
    for (final value in _retained.values) {
      try {
        if (value.lease != null) await releaseCache?.call(value.lease!);
      } catch (_) {
        /* A failed release expires naturally. */
      }
      try {
        await value.access?.release();
      } catch (_) {
        /* The engine also releases native scopes on exit. */
      }
    }
    _retained.clear();
    await diagnostics?.close();
  }
}

class _ExternalRetention {
  _ExternalRetention(this.lease, this.access);
  final String? lease;
  final TransientFileAccess? access;
}
