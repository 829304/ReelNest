import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../../api/emby/emby_client.dart';
import '../../../api/emby/emby_item.dart';
import '../../../api/emby/emby_playback.dart';
import '../../../api/emby/emby_subtitle.dart';
import '../../../api/emby/emby_detail.dart';
import '../../../api/emby/emby_quality.dart';
import '../../../api/emby/emby_download.dart';
import '../../playback/data/playback_repository.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_options.dart';
import '../../../storage/credential_store.dart';
import '../../../storage/library_database.dart';
import 'source_repository.dart';

String newEmbyIdentity() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<String> embyDeviceIdentity(LibraryDatabase database) =>
    database.transaction(() async {
      final row = await database
          .customSelect(
            "SELECT value FROM player_preferences WHERE key = 'emby.deviceId'",
          )
          .getSingleOrNull();
      if (row != null) return row.read<String>('value');
      final value = newEmbyIdentity();
      await database.customStatement(
        "INSERT INTO player_preferences(key, value) VALUES('emby.deviceId', ?)",
        [value],
      );
      return value;
    });

typedef EmbyCredentialStores = CredentialStore Function(String sourceId);

class _Credential {
  const _Credential(this.session, this.password);
  final EmbySession session;
  final String password;
  String encode() =>
      jsonEncode({'session': session.toJson(), 'password': password});
  factory _Credential.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return _Credential(
      EmbySession.fromJson(data['session'] as Map<String, dynamic>),
      data['password'] as String,
    );
  }
}

/// Connection lifecycle only; E2 owns item synchronization, not this service.
class EmbyConnectionRepository {
  EmbyConnectionRepository({
    required this.sources,
    required this.client,
    required this.stores,
    this.playbackReportTimeout = const Duration(seconds: 5),
  });
  final SourceRepository sources;
  final Future<EmbyClient> client;
  final EmbyCredentialStores stores;
  final Duration playbackReportTimeout;
  final _operations = <String, Future<void>>{};
  bool _disposed = false;
  void dispose() {
    _disposed = true;
  }

  void _check() {
    if (_disposed) throw const SourceFailure('媒体库已关闭。');
  }

  Future<T> _serial<T>(String id, Future<T> Function() work) {
    final next = (_operations[id] ?? Future.value()).then((_) {
      _check();
      return work();
    });
    final settled = next.then<void>((_) {}, onError: (Object _) {});
    _operations[id] = settled;
    settled.then((_) {
      if (identical(_operations[id], settled)) _operations.remove(id);
    });
    return next;
  }

  Future<T> _idle<T>(String id, Future<T> Function() work) => Future.sync(() {
    if (sources.isScanning(id)) throw const SourceFailure('请先取消同步并等待结束。');
    return _serial(id, work);
  });

  Future<_Credential> _load(String id) async {
    try {
      final raw = await stores(id).read();
      if (raw == null) {
        throw const EmbyFailure(EmbyError.authentication, '未找到此来源的登录凭据，请重新认证。');
      }
      return _Credential.decode(raw);
    } on SourceFailure {
      rethrow;
    } catch (_) {
      throw const SourceFailure('无法读取 Emby 登录凭据，请重新认证或检查安全存储。');
    }
  }

  Future<void> _save(String id, _Credential value) async {
    try {
      await stores(id).write(value.encode());
    } catch (_) {
      throw const SourceFailure('Emby 登录凭据保存失败，请检查系统安全存储。');
    }
  }

  String _configKey(String id) => 'connector.emby.$id';
  Future<EmbySession> _configuration(String id) async {
    final row = await sources.database
        .customSelect(
          'SELECT value FROM player_preferences WHERE key = ?',
          variables: [Variable(_configKey(id))],
        )
        .getSingleOrNull();
    if (row == null) throw const SourceFailure('Emby 连接配置缺失，请重新添加媒体源。');
    final data = jsonDecode(row.read<String>('value')) as Map<String, dynamic>;
    return EmbySession(
      server: embyServerUri(data['server'] as String),
      username: data['username'] as String,
      userId: data['userId'] as String,
      token: '',
    );
  }

  Future<MediaSource> connect(
    String server,
    String username,
    String password, {
    SourceOptions? options,
  }) => _serial('connect', () async {
    final api = await client;
    final session = await api.authenticate(server, username, password);
    await api.libraries(
      session,
    ); // Validate the library response before saving.
    _check();
    final id = newEmbyIdentity();
    try {
      await _save(id, _Credential(session, password));
      _check();
      return await sources.database.transaction(() async {
        final source = await sources.add(
          sourceId: id,
          kind: MediaSourceKind.emby,
          name: 'Emby 媒体库',
          location: Uri(
            scheme: 'emby',
            host: session.server.host,
            path: '/$id',
          ).toString(),
          minimumFileSize: 0,
          options:
              options ??
              SourceOptions(
                autoScan: false,
                preferLocalArtwork: false,
                networkScrapingEnabled: false,
                screenshotFallbackEnabled: false,
              ),
        );
        final config = Map<String, dynamic>.from(session.toJson())
          ..remove('token');
        await sources.database.customStatement(
          'INSERT INTO player_preferences(key, value) VALUES(?, ?)',
          [_configKey(id), jsonEncode(config)],
        );
        return source;
      });
    } catch (_) {
      try {
        await stores(id).clear();
      } catch (_) {
        throw const SourceFailure('连接未保存，临时登录凭据清理失败，请检查系统安全存储。');
      }
      rethrow;
    }
  });

  Future<T> _authenticated<T>(
    String id,
    Future<T> Function(EmbyClient, EmbySession) action, {
    ScanCancellation? cancellation,
  }) async {
    cancellation?.check();
    final credential = await _load(id);
    final api = await client;
    try {
      final result = await action(api, credential.session);
      _check();
      return result;
    } on EmbyFailure catch (error) {
      if (error.kind != EmbyError.authentication) rethrow;
      cancellation?.check();
      final refreshed = await api.authenticate(
        credential.session.server.toString(),
        credential.session.username,
        credential.password,
        cancellation: cancellation,
      );
      if (refreshed.userId != credential.session.userId) {
        throw const EmbyFailure(
          EmbyError.authentication,
          '服务器用户身份已改变，请重新添加该媒体源。',
        );
      }
      _check();
      cancellation?.check();
      await _save(id, _Credential(refreshed, credential.password));
      // Retry the failed request exactly once, including a Views 401.
      final result = await action(api, refreshed);
      _check();
      return result;
    }
  }

  Future<EmbySession> session(String id) => _serial(id, () async {
    await _requireSource(id);
    return _authenticated(id, (api, value) async {
      await api.validate(value);
      return value;
    });
  });
  Future<List<EmbyLibrary>> libraries(
    String id, {
    ScanCancellation? cancellation,
  }) => _serial(id, () async {
    await _requireSource(id);
    return _authenticated(
      id,
      (api, value) => api.libraries(value, cancellation: cancellation),
    );
  });
  Future<EmbyItemPage> itemPage(
    String id, {
    String? parentId,
    required int start,
    int limit = 300,
    ScanCancellation? cancellation,
  }) => _serial(id, () async {
    cancellation?.check();
    await _requireSource(id);
    return _authenticated(
      id,
      (api, session) => api.itemPage(
        session,
        parentId: parentId,
        start: start,
        limit: limit,
        cancellation: cancellation,
      ),
    );
  });
  Future<Uint8List> artwork(
    String id,
    String itemId, {
    bool backdrop = false,
    int index = 0,
    int? maxWidth,
    ScanCancellation? cancellation,
  }) async {
    final credential = await _serial(id, () async {
      cancellation?.check();
      await _requireSource(id);
      return _load(id);
    });
    final api = await client;
    Future<Uint8List> fetch(EmbyClient api, EmbySession session) => api.artwork(
      session,
      itemId,
      backdrop: backdrop,
      index: index,
      maxWidth: maxWidth,
      cancellation: cancellation,
    );
    try {
      cancellation?.check();
      final result = await fetch(api, credential.session);
      _check();
      return result;
    } on EmbyFailure catch (error) {
      if (error.kind != EmbyError.authentication) rethrow;
      return _serial(id, () async {
        cancellation?.check();
        await _requireSource(id);
        return _authenticated(id, fetch, cancellation: cancellation);
      });
    }
  }

  Future<EmbyDetail> detail(
    IndexedMedia item, {
    ScanCancellation? cancellation,
  }) => _serial(item.identity.sourceId, () async {
    cancellation?.check();
    await _requireSource(item.identity.sourceId);
    final remote = item.remote;
    if (remote == null) throw const SourceFailure('此媒体没有远程详情。');
    return _authenticated(
      item.identity.sourceId,
      (api, session) => api.detail(
        session,
        remote.externalId,
        mediaSourceId: remote.mediaSourceId,
        cancellation: cancellation,
      ),
      cancellation: cancellation,
    );
  });

  Future<List<EmbySubtitle>> subtitles(
    IndexedMedia item, {
    ScanCancellation? cancellation,
  }) => _serial(item.identity.sourceId, () async {
    cancellation?.check();
    await _requireSource(item.identity.sourceId);
    final remote = item.remote;
    if (remote == null) return const <EmbySubtitle>[];
    return _authenticated(
      item.identity.sourceId,
      (api, session) => api.subtitles(
        session,
        remote.externalId,
        remote.mediaSourceId,
        cancellation: cancellation,
      ),
      cancellation: cancellation,
    );
  });

  Future<Uint8List> subtitle(
    IndexedMedia item,
    EmbySubtitle stream, {
    ScanCancellation? cancellation,
  }) => _serial(item.identity.sourceId, () async {
    cancellation?.check();
    await _requireSource(item.identity.sourceId);
    if (item.remote?.externalId != stream.itemId) {
      throw const SourceFailure('字幕不属于当前媒体。');
    }
    return _authenticated(
      item.identity.sourceId,
      (api, session) =>
          api.subtitle(session, stream, cancellation: cancellation),
      cancellation: cancellation,
    );
  });

  Future<void> setFavorite(MediaIdentity identity, bool favorite) =>
      _idle(identity.sourceId, () async {
        await _requireSource(identity.sourceId);
        final source = await sources.source(identity.sourceId);
        final item = await sources.media(identity);
        final remote = item.remote;
        if (remote == null) throw const SourceFailure('此媒体没有远程状态。');
        await sources.setRemoteFavorite(identity, favorite);
        try {
          if (source.options.remoteTraceSyncMode ==
              RemoteTraceSyncMode.bidirectional) {
            await _authenticated(
              source.id,
              (api, session) => api.setUserFlag(
                session,
                remote.externalId,
                favorite: true,
                value: favorite,
              ),
            );
          }
        } catch (_) {
          await sources.setRemoteFavorite(identity, remote.favorite);
          throw const SourceFailure('远程收藏同步失败，状态已回滚，请重试。');
        }
      });

  /// Return failed uploads, retaining every successful local mutation, as in
  /// scheduleEmbyPlayedSync. A later failure must not skip remaining items.
  Future<int> markPlayed(
    Iterable<MediaIdentity> identities,
    bool played,
  ) async {
    final ids = identities.toSet().toList();
    if (ids.isEmpty) return 0;
    final sourceId = ids.first.sourceId;
    if (ids.any((id) => id.sourceId != sourceId)) {
      throw ArgumentError('One source per batch');
    }
    return _idle(sourceId, () async {
      await _requireSource(sourceId);
      final source = await sources.source(sourceId);
      final items = <IndexedMedia>[];
      for (final id in ids) {
        final item = await sources.media(id);
        if (item.remote == null) throw const SourceFailure('此媒体没有远程状态。');
        items.add(item);
      }
      await PlaybackRepository(sources.database).markWatched(ids, played);
      sources.traceChanged();
      var failed = 0;
      if (source.options.remoteTraceSyncMode ==
          RemoteTraceSyncMode.bidirectional) {
        for (final item in items) {
          try {
            await _authenticated(
              sourceId,
              (api, session) => api.setUserFlag(
                session,
                item.remote!.externalId,
                favorite: false,
                value: played,
              ),
            );
          } catch (_) {
            failed++;
          }
        }
      }
      return failed;
    });
  }

  Future<EmbyPlaybackResource> preparePlayback(
    IndexedMedia item, {
    EmbyVideoQuality quality = EmbyVideoQuality.source,
    Duration start = Duration.zero,
    String? playSessionId,
    ScanCancellation? cancellation,
  }) => _serial(item.identity.sourceId, () async {
    final id = item.identity.sourceId;
    cancellation?.check();
    await _requireSource(id);
    if (item.remote == null || item.isSeries) {
      throw const SourceFailure('此媒体没有可播放资源。');
    }
    final selected = quality.original
        ? EmbyVideoQuality.source
        : EmbyVideoQuality.options(item)
              .where((q) => q.id == quality.id)
              .firstOrNull;
    if (selected == null) {
      throw const SourceFailure('此片源不支持所选画质。');
    }
    return _authenticated(id, (api, session) async {
      await api.validate(session, cancellation: cancellation);
      return api.playbackResource(
        session,
        item.remote!,
        audio: item.type == 'music',
        quality: selected,
        start: start,
        playSessionId: playSessionId ?? newEmbyIdentity(),
      );
    }, cancellation: cancellation);
  });

  Future<EmbyDownloadProgress> downloadVideo(
    IndexedMedia item,
    File destination,
    ScanCancellation cancellation, {
    EmbyVideoQuality quality = EmbyVideoQuality.source,
    String? etag,
    void Function(EmbyDownloadProgress)? onProgress,
  }) async {
    for (var attempt = 0; ; attempt++) {
      cancellation.check();
      final resource =
          await preparePlayback(
            item,
            quality: quality,
            cancellation: cancellation,
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              cancellation.cancel();
              throw const SourceFailure('视频缓存准备超时。');
            },
          );
      cancellation.check();
      try {
        return await (await client).download(
          resource,
          destination,
          cancellation,
          etag: etag,
          onProgress: onProgress,
        );
      } on EmbyFailure catch (error) {
        if (error.kind != EmbyError.authentication || attempt > 0) rethrow;
        await session(item.identity.sourceId);
      }
    }
  }

  Future<void> reportPlayback(
    IndexedMedia item, {
    required String playSessionId,
    required EmbyPlaybackPhase phase,
    required Duration position,
    required Duration duration,
    required bool paused,
    bool transcoding = false,
  }) async {
    // Bound the caller's wait as well as the HTTP operation. Cancelling only
    // the token would leave a queued Future waiting on its predecessor.
    final cancellation = ScanCancellation();
    await _serial<void>(item.identity.sourceId, () async {
      cancellation.check(); // An expired queued operation must never run later.
      final source = await sources.source(item.identity.sourceId);
      if (source.kind != MediaSourceKind.emby ||
          source.options.remoteTraceSyncMode !=
              RemoteTraceSyncMode.bidirectional) {
        return;
      }
      final remote = item.remote;
      if (remote == null) return;
      await _authenticated(
        source.id,
        (api, session) => api.reportPlayback(
          session,
          itemId: remote.externalId,
          playSessionId: playSessionId,
          phase: phase,
          position: position,
          duration: duration,
          paused: paused,
          transcoding: transcoding,
          mediaSourceId: remote.mediaSourceId,
          cancellation: cancellation,
        ),
        cancellation: cancellation,
      );
    }).timeout(
      playbackReportTimeout,
      onTimeout: () {
        cancellation.cancel();
        throw const EmbyFailure(EmbyError.network, 'Emby 播放状态同步超时。');
      },
    );
  }

  Future<void> _requireSource(String id) async {
    if ((await sources.source(id)).kind != MediaSourceKind.emby) {
      throw const SourceFailure('该来源不是 Emby。');
    }
  }

  Future<bool> isReachable(MediaSource source) async {
    if (source.kind != MediaSourceKind.emby) return false;
    try {
      await session(source.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<MediaSource> selectLibraries(
    String id, {
    required bool all,
    required Iterable<String> selected,
    bool? metadata,
    bool? health,
    RemoteTraceSyncMode? trace,
  }) => _idle(id, () async {
    final source = await sources.source(id);
    await _requireSource(id);
    final ids = selected
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (!all && ids.isEmpty) {
      throw const SourceFailure('请至少选择一个媒体库，或开启同步全部媒体库。');
    }
    final options = SourceOptions.fromJson({
      ...source.options.toJson(),
      'selectedEmbyLibraryIDs': all ? <String>[] : ids,
      'includeInMetadataFetch':
          metadata ?? source.options.includeInMetadataFetch,
      'includeInHealthCheck': health ?? source.options.includeInHealthCheck,
      'remoteTraceSyncMode': (trace ?? source.options.remoteTraceSyncMode).name,
    });
    return sources.updateSettings(id, options: options);
  });
  Future<void> reauthenticate(String id, String username, String password) =>
      _serial(id, () async {
        await _requireSource(id);
        final old = await _configuration(id);
        final api = await client;
        final refreshed = await api.authenticate(
          old.server.toString(),
          username,
          password,
        );
        if (refreshed.userId != old.userId) {
          throw const EmbyFailure(
            EmbyError.authentication,
            '请使用此来源原有账号；切换账号请另行添加媒体源。',
          );
        }
        await api.libraries(refreshed);
        _check();
        await _save(id, _Credential(refreshed, password));
      });
  Future<void> remove(String id) => _idle(id, () async {
    await _requireSource(id);
    final old = await stores(id).read();
    try {
      await stores(id).clear();
    } catch (_) {
      throw const SourceFailure('登录凭据清理失败，媒体源尚未移除。');
    }
    try {
      await sources.database.transaction(() async {
        await sources.remove(id);
        await sources.database.customStatement(
          'DELETE FROM player_preferences WHERE key = ?',
          [_configKey(id)],
        );
      });
    } catch (_) {
      if (old != null) await stores(id).write(old);
      rethrow;
    }
  });
}
