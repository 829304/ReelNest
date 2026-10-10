import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/media_source.dart';
import 'emby_item.dart';
import 'emby_playback.dart';
import 'emby_subtitle.dart';
import 'emby_detail.dart';
import '../../domain/remote_media_metadata.dart';

enum EmbyError {
  address,
  authentication,
  restricted,
  network,
  response,
  tooLarge,
}

class EmbyFailure extends SourceFailure {
  const EmbyFailure(this.kind, String message, {this.status}) : super(message);
  final EmbyError kind;
  final int? status;
}

Uri embyServerUri(String value) {
  final text = value.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
  if (text.isEmpty ||
      uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      RegExp(r'\s').hasMatch(text)) {
    throw const EmbyFailure(
      EmbyError.address,
      '请输入有效的服务器地址，例如 http://192.168.1.20:8096。',
    );
  }
  return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
}

class EmbySession {
  const EmbySession({
    required this.server,
    required this.username,
    required this.userId,
    required this.token,
  });
  final Uri server;
  final String username, userId, token;
  Map<String, dynamic> toJson() => {
    'server': server.toString(),
    'username': username,
    'userId': userId,
    'token': token,
  };
  factory EmbySession.fromJson(Map<String, dynamic> data) => EmbySession(
    server: embyServerUri(data['server'] as String),
    username: data['username'] as String,
    userId: _required(data['userId']),
    token: _required(data['token']),
  );
}

String _required(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const EmbyFailure(EmbyError.response, '服务器没有返回有效的 Emby 数据。');
  }
  return value;
}

class EmbyLibrary {
  const EmbyLibrary({
    required this.id,
    required this.name,
    this.collectionType,
  });
  final String id, name;
  final String? collectionType;
  String get typeLabel => switch (collectionType?.toLowerCase()) {
    'movies' => '电影',
    'tvshows' => '电视剧',
    'music' => '音乐',
    'photos' => '照片',
    'homevideos' => '其他视频',
    'boxsets' => '合集',
    'playlists' => '播放列表',
    'livetv' => '直播电视',
    _ => '媒体库',
  };
}

/// EmbyService's protocol only. Credentials/SQL/widgets belong to callers.
class EmbyClient {
  EmbyClient({
    required this.deviceId,
    HttpClient? http,
    this.timeout = const Duration(seconds: 15),
    this.maxResponseBytes = 4 * 1024 * 1024,
    this.maxArtworkBytes = 16 * 1024 * 1024,
  }) : _http = http ?? HttpClient() {
    _http.connectionTimeout = timeout;
  }
  final String deviceId;
  final HttpClient _http;
  final Duration timeout;
  final int maxResponseBytes;
  final int maxArtworkBytes;
  String get userAgent => 'ReelNest/0.1.0 (${Platform.operatingSystem})';
  String _quote(String text) => text.replaceAll(RegExp(r'["\\\r\n]'), '_');
  String authorization([String? token]) =>
      'MediaBrowser Client="ReelNest", '
      'Device="${_quote(Platform.localHostname)}", DeviceId="${_quote(deviceId)}", '
      'Version="0.1.0"${token == null ? '' : ', Token="${_quote(token)}"'}';

  Future<EmbySession> authenticate(
    String server,
    String username,
    String password, {
    ScanCancellation? cancellation,
  }) async {
    final base = embyServerUri(server);
    if (username.trim().isEmpty) throw const SourceFailure('请输入用户名。');
    final value = await _request(
      base,
      ['Users', 'AuthenticateByName'],
      method: 'POST',
      body: {'Username': username.trim(), 'Pw': password},
      cancellation: cancellation,
    );
    final user = value['User'];
    if (user is! Map) {
      throw const EmbyFailure(EmbyError.response, '服务器没有返回有效的用户信息。');
    }
    return EmbySession(
      server: base,
      username: user['Name'] is String
          ? user['Name'] as String
          : username.trim(),
      userId: _required(user['Id']),
      token: _required(value['AccessToken']),
    );
  }

  Future<List<EmbyLibrary>> libraries(
    EmbySession session, {
    ScanCancellation? cancellation,
  }) async {
    final value = await _request(
      session.server,
      ['Users', session.userId, 'Views'],
      token: session.token,
      cancellation: cancellation,
    );
    final items = value['Items'];
    if (items is! List) {
      throw const EmbyFailure(EmbyError.response, '媒体库列表响应无效。');
    }
    final result = <EmbyLibrary>[];
    final seen = <String>{};
    for (final raw in items) {
      if (raw is! Map) {
        throw const EmbyFailure(EmbyError.response, '媒体库列表响应无效。');
      }
      final id = _required(raw['Id']);
      final collection = raw['CollectionType'] as String?;
      if ((collection == null || collection.isEmpty) &&
          (raw['Type'] as String?)?.toLowerCase() != 'collectionfolder') {
        continue;
      }
      if (seen.add(id)) {
        result.add(
          EmbyLibrary(
            id: id,
            name: raw['Name'] is String ? raw['Name'] as String : '媒体库',
            collectionType: raw['CollectionType'] as String?,
          ),
        );
      }
    }
    return List.unmodifiable(result);
  }

  Future<void> validate(EmbySession session) async {
    await _request(session.server, [
      'Users',
      session.userId,
    ], token: session.token);
  }

  EmbyPlaybackResource playbackResource(
    EmbySession session,
    RemoteMediaMetadata item, {
    bool audio = false,
  }) {
    final container = item.container?.trim().toLowerCase();
    // A container is an extension, never an arbitrary server path.
    final extension =
        container != null && RegExp(r'^[a-z0-9]+$').hasMatch(container)
        ? '.$container'
        : '';
    return EmbyPlaybackResource(
      session.server.replace(
        pathSegments: [
          ...session.server.pathSegments.where((s) => s.isNotEmpty),
          audio ? 'Audio' : 'Videos',
          item.externalId,
          'stream$extension',
        ],
        queryParameters: {
          'Static': 'true',
          'DeviceId': deviceId,
          'api_key': session.token,
          if (item.mediaSourceId?.isNotEmpty == true)
            'MediaSourceId': item.mediaSourceId!,
        },
      ),
      item.mediaSourceId,
    );
  }

  Future<void> reportPlayback(
    EmbySession session, {
    required String itemId,
    required String playSessionId,
    required EmbyPlaybackPhase phase,
    required Duration position,
    required Duration duration,
    required bool paused,
    String? mediaSourceId,
    ScanCancellation? cancellation,
  }) async {
    await _requestBytes(
      session.server,
      [
        'Sessions',
        'Playing',
        if (phase == EmbyPlaybackPhase.progress) 'Progress',
        if (phase == EmbyPlaybackPhase.stopped) 'Stopped',
      ],
      method: 'POST',
      token: session.token,
      requestTimeout: const Duration(seconds: 5),
      cancellation: cancellation,
      body: {
        'ItemId': itemId,
        'MediaSourceId': ?mediaSourceId,
        'PlaySessionId': playSessionId,
        'PositionTicks': position.inMicroseconds.clamp(0, 1 << 53) * 10,
        if (duration > Duration.zero)
          'RunTimeTicks': duration.inMicroseconds * 10,
        'IsPaused': paused,
        'PlayMethod': 'DirectStream',
      },
    );
    // Emby normally responds with 204; do not attempt JSON decoding here.
  }

  Future<void> setUserFlag(
    EmbySession session,
    String itemId, {
    required bool favorite,
    required bool value,
  }) async {
    await _requestBytes(
      session.server,
      [
        'Users',
        session.userId,
        favorite ? 'FavoriteItems' : 'PlayedItems',
        itemId,
      ],
      method: value ? 'POST' : 'DELETE',
      token: session.token,
    );
  }

  Future<EmbyDetail> detail(
    EmbySession session,
    String itemId, {
    String? mediaSourceId,
    ScanCancellation? cancellation,
  }) async => EmbyDetail.fromServer(
    await _request(
      session.server,
      ['Users', session.userId, 'Items', itemId],
      token: session.token,
      query: {
        'Fields': 'People,ProviderIds,Overview,Genres,BackdropImageTags,Studios,ProductionLocations,OfficialRating,Status,MediaSources,MediaStreams',
      },
      cancellation: cancellation,
    ),
    itemId,
    mediaSourceId: mediaSourceId,
  );

  Future<List<EmbySubtitle>> subtitles(
    EmbySession session,
    String itemId,
    String? mediaSourceId, {
    ScanCancellation? cancellation,
  }) async => EmbySubtitle.parse(
    await _request(
      session.server,
      ['Users', session.userId, 'Items', itemId],
      token: session.token,
      cancellation: cancellation,
    ),
    itemId,
    mediaSourceId,
  );

  Future<Uint8List> subtitle(
    EmbySession session,
    EmbySubtitle stream, {
    ScanCancellation? cancellation,
  }) {
    Uri? resource;
    if (stream.deliveryUrl?.trim().isNotEmpty == true) {
      resource = session.server.resolve(stream.deliveryUrl!);
      if (resource.origin != session.server.origin ||
          resource.userInfo.isNotEmpty) {
        throw const EmbyFailure(EmbyError.address, '字幕地址不属于当前服务器。');
      }
      resource = resource.replace(
        queryParameters: {
          for (final entry in resource.queryParameters.entries)
            if (entry.key.toLowerCase() != 'api_key') entry.key: entry.value,
        },
      );
    } else if (stream.mediaSourceId == null) {
      throw const EmbyFailure(EmbyError.response, '服务器没有返回有效的字幕地址。');
    }
    return _requestBytes(
      session.server,
      [
        'Videos',
        stream.itemId,
        stream.mediaSourceId ?? '',
        'Subtitles',
        '${stream.index}',
        'Stream.${stream.extension}',
      ],
      resource: resource,
      token: session.token,
      cancellation: cancellation,
      maxBytes: 8 * 1024 * 1024,
    );
  }

  Future<EmbyItemPage> itemPage(
    EmbySession session, {
    String? parentId,
    required int start,
    int limit = 300,
    ScanCancellation? cancellation,
  }) async => EmbyItemPage.fromJson(
    await _request(
      session.server,
      ['Users', session.userId, 'Items'],
      token: session.token,
      cancellation: cancellation,
      query: {
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Series,Episode,Audio',
        'Fields': 'OriginalTitle,Overview,ProductionYear,RunTimeTicks,ParentId,SeriesId,SeriesName,IndexNumber,ParentIndexNumber,CommunityRating,UserData,ImageTags,BackdropImageTags,MediaSources,ProviderIds,Genres',
        'StartIndex': '$start',
        'Limit': '$limit',
        'ParentId': ?parentId,
      },
    ),
  );

  Future<Uint8List> artwork(
    EmbySession session,
    String itemId, {
    bool backdrop = false,
    int index = 0,
    int? maxWidth,
    ScanCancellation? cancellation,
  }) => _requestBytes(
    session.server,
    [
      'Items',
      itemId,
      'Images',
      backdrop ? 'Backdrop' : 'Primary',
      if (backdrop) '$index',
    ],
    token: session.token,
    cancellation: cancellation,
    maxBytes: maxArtworkBytes,
    query: {
      'maxWidth': '${(maxWidth ?? (backdrop ? 1280 : 700)).clamp(1, 2048)}',
      'quality': '90',
    },
  );

  Future<Map<String, dynamic>> _request(
    Uri base,
    List<String> path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
    Map<String, String> query = const {},
    ScanCancellation? cancellation,
  }) async {
    final bytes = await _requestBytes(
      base,
      path,
      method: method,
      body: body,
      token: token,
      query: query,
      cancellation: cancellation,
    );
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const EmbyFailure(EmbyError.response, '服务器没有返回有效的 Emby 数据。');
    } on TypeError {
      throw const EmbyFailure(EmbyError.response, '服务器没有返回有效的 Emby 数据。');
    }
  }

  Future<Uint8List> _requestBytes(
    Uri base,
    List<String> path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? token,
    Map<String, String> query = const {},
    ScanCancellation? cancellation,
    int? maxBytes,
    Duration? requestTimeout,
    Uri? resource,
  }) async {
    cancellation?.check();
    HttpClientRequest? active;
    final unlisten = cancellation?.listen(() => active?.abort());
    var expired = false;
    Future<Uint8List> send() async {
      var uri =
          resource?.replace(
            queryParameters: {...resource.queryParameters, 'api_key': ?token},
          ) ??
          base.replace(
            pathSegments: [
              ...base.pathSegments.where((s) => s.isNotEmpty),
              ...path,
            ],
            queryParameters: {...query, 'api_key': ?token},
          );
      for (var attempt = 0; attempt < 6; attempt++) {
        final request = active = await _http.openUrl(method, uri);
        cancellation?.check();
        if (expired) {
          request.abort();
          throw const EmbyFailure(EmbyError.network, '连接已超时。');
        }
        request.followRedirects = false;
        request.headers.set('X-Emby-Authorization', authorization(token));
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        request.headers.contentType = ContentType.json;
        if (body != null) request.add(utf8.encode(jsonEncode(body)));
        final response = await request.close();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            throw const EmbyFailure(EmbyError.response, '服务器重定向无效。');
          }
          final next = uri.resolve(location);
          // Never forward a password/token to another origin or downgrade TLS.
          if (next.origin != uri.origin || next.userInfo.isNotEmpty) {
            throw const EmbyFailure(
              EmbyError.address,
              '服务器地址发生跨站跳转，请填写最终服务器地址后重试。',
            );
          }
          await response.take(0).drain<void>();
          uri = next;
          if (response.statusCode == 303 ||
              ([301, 302].contains(response.statusCode) && method == 'POST')) {
            method = 'GET';
            body = null;
          }
          continue;
        }
        final bytes = BytesBuilder(copy: false);
        final limit = response.statusCode >= 200 && response.statusCode < 300
            ? maxBytes ?? maxResponseBytes
            : 8192;
        await for (final chunk in response) {
          cancellation?.check();
          if (bytes.length + chunk.length > limit) {
            request.abort();
            if (response.statusCode >= 200 && response.statusCode < 300) {
              throw const EmbyFailure(EmbyError.tooLarge, '服务器响应过大，请检查服务器。');
            }
            bytes.add(
              chunk.take((limit - bytes.length).clamp(0, limit)).toList(),
            );
            break;
          }
          bytes.add(chunk);
        }
        cancellation?.check();
        final collected = bytes.takeBytes();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return collected;
        }
        final text = utf8.decode(
          collected,
          allowMalformed:
              response.statusCode < 200 || response.statusCode >= 300,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final lower = text.toLowerCase();
          final restricted =
              response.statusCode == 403 ||
              response.statusCode == 451 ||
              (response.headers.contentType?.mimeType == 'text/html') ||
              lower.contains('<html') ||
              [
                'whitelist',
                'not whitelisted',
                'unsupported client',
                'unsupported device',
                'forbidden',
                'access denied',
                'not allowed',
                'client blocked',
                'blocked client',
              ].any(lower.contains);
          if (restricted) {
            throw EmbyFailure(
              EmbyError.restricted,
              '该服务器可能限制第三方客户端接入。请联系管理员将 ReelNest 加入白名单。',
              status: response.statusCode,
            );
          }
          if (response.statusCode == 401) {
            throw const EmbyFailure(
              EmbyError.authentication,
              '远程媒体库登录已失效或用户名、密码不正确，需要重新认证。',
              status: 401,
            );
          }
          throw EmbyFailure(
            EmbyError.response,
            '远程媒体库请求失败（HTTP ${response.statusCode}）。',
            status: response.statusCode,
          );
        }
      }
      throw const EmbyFailure(EmbyError.response, '服务器重定向次数过多。');
    }

    try {
      return await send().timeout(
        requestTimeout ?? timeout,
        onTimeout: () {
          expired = true;
          active?.abort();
          throw const EmbyFailure(EmbyError.network, '连接超时，请检查服务器地址和网络后重试。');
        },
      );
    } on ScanCancelled {
      active?.abort();
      rethrow;
    } on SourceFailure {
      rethrow;
    } on FormatException {
      throw const EmbyFailure(EmbyError.response, '服务器没有返回有效的 Emby 数据。');
    } on TypeError {
      throw const EmbyFailure(EmbyError.response, '服务器没有返回有效的 Emby 数据。');
    } catch (_) {
      active?.abort();
      cancellation?.check();
      throw const EmbyFailure(EmbyError.network, '无法连接服务器，请检查地址和网络后重试。');
    } finally {
      unlisten?.call();
    }
  }

  void close() => _http.close(force: true);
}
