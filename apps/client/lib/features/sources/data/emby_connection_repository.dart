import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../../api/emby/emby_client.dart';
import '../../../api/emby/emby_detail.dart';
import '../../../api/emby/emby_download.dart';
import '../../../api/emby/emby_item.dart';
import '../../../api/emby/emby_playback.dart';
import '../../../api/emby/emby_quality.dart';
import '../../../api/emby/emby_subtitle.dart';
import '../../../application/async_tasks.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_options.dart';
import '../../../storage/credential_store.dart';
import '../../../storage/library_database.dart';
import '../../playback/data/playback_repository.dart';
import '../../playback/domain/playback_record.dart';
import 'emby_library_repository.dart';
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
    this.plexClient,
    this.playbackReportTimeout = const Duration(seconds: 5),
  });
  final SourceRepository sources;
  final Future<EmbyClient> client;
  final Future<EmbyClient>? plexClient;
  Future<EmbyClient> _clientFor(MediaSourceKind kind) =>
      kind == MediaSourceKind.plex
      ? (plexClient ?? Future.error(const SourceFailure('Plex 连接器未初始化。')))
      : client;
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
      final credential = _Credential.decode(raw);
      final source = await sources.source(id, includeCounts: false);
      if (!source.kind.isRemoteVideoSource ||
          source.kind != credential.session.kind) {
        throw const SourceFailure('登录凭据与媒体源类型不一致，请重新认证。');
      }
      return credential;
    } on SourceFailure {
      rethrow;
    } catch (_) {
      throw const SourceFailure('无法读取远程媒体库登录凭据，请重新认证或检查安全存储。');
    }
  }

  Future<void> _save(String id, _Credential value) async {
    try {
      await stores(id).write(value.encode());
    } catch (_) {
      throw const SourceFailure('远程媒体库登录凭据保存失败，请检查系统安全存储。');
    }
  }

  Future<String> _configKey(String id) async =>
      'connector.${(await sources.source(id, includeCounts: false)).kind.name}.$id';
  Future<EmbySession> _configuration(String id) async {
    final row = await sources.database
        .customSelect(
          'SELECT value FROM player_preferences WHERE key = ?',
          variables: [Variable(await _configKey(id))],
        )
        .getSingleOrNull();
    if (row == null) throw const SourceFailure('远程媒体库连接配置缺失，请重新添加媒体源。');
    final data = jsonDecode(row.read<String>('value')) as Map<String, dynamic>;
    return EmbySession(
      server: embyServerUri(data['server'] as String),
      username: data['username'] as String,
      userId: data['userId'] as String,
      token: '',
      serverIdentity: data['serverIdentity'] as String?,
      kind: (await sources.source(id, includeCounts: false)).kind,
    );
  }

  Future<MediaSource> connect(
    String server,
    String username,
    String password, {
    SourceOptions? options,
    MediaSourceKind kind = MediaSourceKind.emby,
  }) => _serial('connect', () async {
    if (!kind.isRemoteVideoSource) throw const SourceFailure('此媒体服务器类型尚未接入。');
    final api = await _clientFor(kind);
    final session = await api.authenticate(
      server,
      username,
      password,
      kind: kind,
    );
    final views = await api.libraries(session);
    _check();
    final id = newEmbyIdentity();
    try {
      await _save(id, _Credential(session, password));
      _check();
      return await sources.database.transaction(() async {
        final source = await sources.add(
          sourceId: id,
          kind: kind,
          name: '${kind.label} 媒体库',
          location: Uri(
            scheme: kind.name,
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
          [await _configKey(id), jsonEncode(config)],
        );
        await EmbyLibraryRepository(sources).replaceViews(source.id, views);
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

  Future<MediaSource> connectPlex(
    String server,
    String token, {
    SourceOptions? options,
  }) =>
      connect(server, '', token, kind: MediaSourceKind.plex, options: options);
  Future<void> reauthenticatePlex(String id, String token) =>
      reauthenticate(id, '', token);

  Future<T> _authenticated<T>(
    String id,
    Future<T> Function(EmbyClient, EmbySession) action, {
    ScanCancellation? cancellation,
  }) async {
    cancellation?.check();
    final credential = await awaitWithCancellation(
      cancellation,
      () => _load(id),
    );
    final api = await awaitWithCancellation(
      cancellation,
      () => _clientFor(credential.session.kind),
    );
    cancellation?.check();
    try {
      final result = await action(api, credential.session);
      _check();
      return result;
    } on EmbyFailure catch (error) {
      if (error.kind != EmbyError.authentication ||
          credential.session.kind == MediaSourceKind.plex) {
        rethrow;
      }
      cancellation?.check();
      final refreshed = await api.authenticate(
        credential.session.server.toString(),
        credential.session.username,
        credential.password,
        kind: credential.session.kind,
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

  /// Foreground browsing must not queue behind a full-library HTTP request.
  /// Only credential refresh is serialized; ordinary reads do not mutate auth.
  Future<T> _foreground<T>(
    String id,
    Future<T> Function(EmbyClient, EmbySession) action, {
    ScanCancellation? cancellation,
  }) async {
    _check();
    cancellation?.check();
    await awaitWithCancellation(cancellation, () => _requireSource(id));
    final credential = await awaitWithCancellation(
      cancellation,
      () => _load(id),
    );
    final api = await awaitWithCancellation(
      cancellation,
      () => _clientFor(credential.session.kind),
    );
    cancellation?.check();
    try {
      final result = await action(api, credential.session);
      cancellation?.check();
      _check();
      await _requireSource(id);
      return result;
    } on EmbyFailure catch (error) {
      if (error.kind != EmbyError.authentication ||
          credential.session.kind == MediaSourceKind.plex) {
        rethrow;
      }
      return awaitWithCancellation(
        cancellation,
        () => _serial(id, () async {
          cancellation?.check();
          await _requireSource(id);
          return _authenticated(id, action, cancellation: cancellation);
        }),
      );
    }
  }

  Future<List<EmbyLibrary>> browseLibraries(
    String id, {
    ScanCancellation? cancellation,
  }) => _foreground(
    id,
    (api, session) => api.libraries(session, cancellation: cancellation),
    cancellation: cancellation,
  );

  Future<EmbyItemPage> browsePage(
    String id, {
    String? parentId,
    String? personKey,
    bool episodesOnly = false,
    required int start,
    int limit = 60,
    ScanCancellation? cancellation,
  }) => _foreground(
    id,
    (api, session) => api.itemPage(
      session,
      parentId: parentId,
      start: start,
      limit: limit,
      videosOnly: true,
      episodesOnly: episodesOnly,
      personKey: personKey,
      cancellation: cancellation,
    ),
    cancellation: cancellation,
  );

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
  }) => _foreground(
    id,
    (api, session) => api.artwork(
      session,
      itemId,
      backdrop: backdrop,
      index: index,
      maxWidth: maxWidth,
      cancellation: cancellation,
    ),
    cancellation: cancellation,
  );
  Future<EmbyDetail> detail(
    IndexedMedia item, {
    ScanCancellation? cancellation,
  }) async {
    cancellation?.check();
    await _requireSource(item.identity.sourceId);
    final remote = item.remote;
    if (remote == null) throw const SourceFailure('此媒体没有远程详情。');
    return _foreground(
      item.identity.sourceId,
      (api, session) => api.detail(
        session,
        remote.externalId,
        mediaSourceId: remote.mediaSourceId,
        cancellation: cancellation,
      ),
      cancellation: cancellation,
    );
  }

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
          if (source.kind != MediaSourceKind.plex &&
              source.options.remoteTraceSyncMode ==
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
    bool played, {
    bool clearHistory = false,
  }) async {
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
      final playback = PlaybackRepository(sources.database);
      if (clearHistory) {
        final records = await playback.readMany(
          ids,
          fallbacks: {
            for (final item in items)
              item.identity: PlaybackRecord(
                identity: item.identity,
                position: Duration(milliseconds: item.remote?.positionMs ?? 0),
                lastPlayedAt: item.remote?.lastPlayedAt,
              ),
          },
        );
        final localTraces =
            (await sources.database
                    .customSelect(
                      'SELECT key FROM player_preferences WHERE key IN (SELECT value FROM json_each(?))',
                      variables: [
                        Variable(
                          jsonEncode(
                            ids.map(PlaybackRepository.localTraceKey).toList(),
                          ),
                        ),
                      ],
                    )
                    .get())
                .map((row) => row.read<String>('key'))
                .toSet();
        items.removeWhere((item) {
          final record = records[item.identity]!;
          return record.position == Duration.zero &&
              record.lastPlayedAt == null &&
              ((item.remote?.playedPercentage ?? 0) <= 0 ||
                  localTraces.contains(
                    PlaybackRepository.localTraceKey(item.identity),
                  ));
        });
        final traced = items.map((i) => i.identity).toSet();
        ids.removeWhere((id) => !traced.contains(id));
        if (ids.isEmpty) return 0;
        await playback.clearHistory(ids);
      } else {
        await playback.markWatched(ids, played);
      }
      sources.traceChanged(sourceIds: [sourceId]);
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
  }) async {
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
    return _foreground(id, (api, session) async {
      return api.preparePlayback(
        session,
        item.remote!,
        cancellation: cancellation,
        audio: item.type == 'music',
        quality: selected,
        start: start,
        playSessionId: playSessionId ?? newEmbyIdentity(),
      );
    }, cancellation: cancellation);
  }

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
        final kind = (await sources.source(
          item.identity.sourceId,
          includeCounts: false,
        )).kind;
        return await (await _clientFor(kind)).download(
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
      if (!source.kind.isRemoteVideoSource ||
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
        throw const EmbyFailure(EmbyError.network, '远程媒体库播放状态同步超时。');
      },
    );
  }

  Future<void> _requireSource(String id) async {
    if (!(await sources.source(
      id,
      includeCounts: false,
    )).kind.isRemoteVideoSource) {
      throw const SourceFailure('该来源不是受支持的媒体服务器。');
    }
  }

  Future<bool> isReachable(MediaSource source) async {
    if (!source.kind.isRemoteVideoSource) return false;
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
        final api = await _clientFor(old.kind);
        final refreshed = await api.authenticate(
          old.server.toString(),
          username,
          password,
          kind: old.kind,
        );
        if (refreshed.kind != old.kind ||
            (old.kind == MediaSourceKind.plex &&
                (old.serverIdentity == null ||
                    refreshed.serverIdentity != old.serverIdentity))) {
          throw const EmbyFailure(
            EmbyError.authentication,
            '服务器身份发生变化，请另行添加媒体源。',
          );
        }
        if (refreshed.userId != old.userId) {
          throw EmbyFailure(
            EmbyError.authentication,
            old.kind == MediaSourceKind.plex
                ? '无法确认新 Token 属于此来源的原账号，请另行添加 Plex 媒体源；原索引和离线缓存不会转交给新凭据。'
                : '请使用此来源原有账号；切换账号请另行添加媒体源。',
          );
        }
        await api.libraries(refreshed);
        _check();
        await _save(id, _Credential(refreshed, password));
      });
  Future<void> remove(String id) => _idle(id, () async {
    await _requireSource(id);
    final configKey = await _configKey(id);
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
          [configKey],
        );
      });
    } catch (_) {
      if (old != null) await stores(id).write(old);
      rethrow;
    }
  });
}
