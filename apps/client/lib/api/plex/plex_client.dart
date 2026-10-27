import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:crypto/crypto.dart';

import '../../domain/media_source.dart';
import '../../domain/remote_media_metadata.dart';
import '../emby/emby_client.dart';
import '../emby/emby_detail.dart';
import '../emby/emby_item.dart';
import '../emby/emby_playback.dart';
import '../emby/emby_quality.dart';
import '../emby/emby_subtitle.dart';
import 'plex_item.dart';

/// Plex protocol adapter for the shared remote-video data pipeline. No Emby
/// endpoint, authentication scheme or streaming URL is used by this adapter.
class PlexClient extends EmbyClient {
  PlexClient({
    required super.deviceId,
    super.http,
    super.timeout,
    super.maxResponseBytes,
    super.maxArtworkBytes,
    Uri? accountEndpoint,
  }) : _plexHttp = http ?? HttpClient(),
       _accountEndpoint = _accountUrl(accountEndpoint) {
    _plexHttp.connectionTimeout = timeout;
  }
  static Uri _accountUrl(Uri? testEndpoint) {
    if (testEndpoint == null) return Uri.https('plex.tv', '/api/v2/user');
    if (testEndpoint.scheme != 'http' ||
        InternetAddress.tryParse(testEndpoint.host)?.isLoopback != true ||
        testEndpoint.userInfo.isNotEmpty ||
        testEndpoint.hasQuery ||
        testEndpoint.hasFragment) {
      throw ArgumentError(
        'Only loopback account endpoints may be injected for tests',
      );
    }
    return testEndpoint;
  }

  final HttpClient _plexHttp;
  // Fixed official realm in production. Injection is only for loopback tests;
  // never obtain this URL from the configured PMS or its responses.
  final Uri _accountEndpoint;
  final _views = <String, List<EmbyLibrary>>{};
  final _showCounts = <String, int>{};
  final _pageLimits = <String, int>{};
  // A machineIdentifier identifies the server, never its authenticated user.
  // An opaque PMS token has no locally verifiable, stable account ID. Bind
  // the source conservatively to this credential; do not call it an account ID.
  static String credentialIdentity(String token) =>
      'plex-token:${sha256.convert(utf8.encode(token))}';
  String _scope(EmbySession s) =>
      '${s.server}|${s.serverIdentity}|${s.userId}|${credentialIdentity(s.token)}';

  @override
  Future<EmbySession> authenticate(
    String server,
    String username,
    String password, {
    ScanCancellation? cancellation,
    MediaSourceKind kind = MediaSourceKind.plex,
  }) async {
    if (kind != MediaSourceKind.plex) {
      throw const SourceFailure('Plex 连接器不能连接其他服务器类型。');
    }
    final token = password.trim();
    if (token.isEmpty || RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(token)) {
      throw const SourceFailure('请输入有效的 Plex Token。');
    }
    final base = embyServerUri(server);
    final identity = await _xml(
      base,
      '/identity',
      token,
      cancellation: cancellation,
    );
    final machine = plexText(identity, 'machineIdentifier');
    if (machine == null) {
      throw const EmbyFailure(EmbyError.response, 'Plex 服务器身份响应无效。');
    }
    final account = await _accountIdentity(token, cancellation);
    final session = EmbySession(
      server: base,
      username:
          plexText(identity, 'friendlyName') ??
          plexText(identity, 'name') ??
          'Plex',
      userId: account,
      serverIdentity: machine,
      token: token,
      kind: kind,
    );
    // /identity can be public. A protected request is necessary to accept a token.
    await libraries(session, cancellation: cancellation);
    return session;
  }

  Future<String> _accountIdentity(
    String token,
    ScanCancellation? cancellation,
  ) async {
    Uint8List bytes;
    try {
      bytes = await _bytes(
        _accountEndpoint.replace(path: '', query: ''),
        _accountEndpoint.toString(),
        token,
        headers: const {'Accept': 'application/json'},
        maxBytes: 256 * 1024,
        allowRedirects: false,
        cancellation: cancellation,
      );
    } on EmbyFailure catch (error) {
      // PMS-scoped tokens are not necessarily Plex account tokens. Preserve
      // server-only connections, but they cannot prove ownership after rotation.
      if (error.status == 401 || error.status == 403) {
        return credentialIdentity(token);
      }
      throw const EmbyFailure(
        EmbyError.authentication,
        '无法向 Plex 官方确认账号身份，请稍后重试；原凭据不会被修改。',
      );
    }
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) throw const FormatException();
      final raw = data['id'];
      final id = raw is int && raw > 0
          ? '$raw'
          : raw is String
          ? raw.trim()
          : '';
      if (!RegExp(r'^[1-9][0-9]{0,30}$').hasMatch(id)) {
        throw const FormatException();
      }
      // Do not persist profile, email, name, authenticationToken or response DTO.
      return 'plex-account:$id';
    } catch (_) {
      throw const EmbyFailure(
        EmbyError.authentication,
        'Plex 官方没有返回有效的账号标识；原凭据不会被修改。',
      );
    }
  }

  @override
  Future<List<EmbyLibrary>> libraries(
    EmbySession session, {
    ScanCancellation? cancellation,
  }) async {
    final identity = await _xml(
      session.server,
      '/identity',
      session.token,
      cancellation: cancellation,
    );
    if (plexText(identity, 'machineIdentifier') != session.serverIdentity) {
      throw const EmbyFailure(
        EmbyError.authentication,
        'Plex 服务器身份发生变化，请重新添加媒体源。',
      );
    }
    final root = await _xml(
      session.server,
      '/library/sections',
      session.token,
      cancellation: cancellation,
    );
    final result = <EmbyLibrary>[];
    final seen = <String>{};
    for (final node in root.findElements('Directory')) {
      final id = plexText(node, 'key');
      final type = switch (plexText(node, 'type')) {
        'movie' => 'movies',
        'show' => 'tvshows',
        'artist' => 'music',
        _ => null,
      };
      // Photos are outside the explicitly agreed product scope.
      if (type == null) continue;
      if (id == null || !RegExp(r'^\d+$').hasMatch(id) || !seen.add(id)) {
        throw const EmbyFailure(EmbyError.response, 'Plex 媒体库列表响应无效。');
      }
      result.add(
        EmbyLibrary(
          id: 'section:$id',
          name: plexText(node, 'title') ?? '媒体库',
          collectionType: type,
        ),
      );
    }
    if (_views.length > 48) _views.clear();
    return _views[_scope(session)] = List.unmodifiable(result);
  }

  @override
  Future<void> validate(
    EmbySession session, {
    ScanCancellation? cancellation,
  }) async {
    await libraries(session, cancellation: cancellation);
  }

  @override
  Future<EmbyItemPage> itemPage(
    EmbySession session, {
    String? parentId,
    int start = 0,
    int limit = 300,
    bool videosOnly = false,
    bool episodesOnly = false,
    String? personKey,
    ScanCancellation? cancellation,
  }) async {
    if (start < 0 || limit < 1 || limit > 300) {
      throw ArgumentError('Plex page range');
    }
    if (parentId == null) {
      // Browsing/sync normally supplies a section. An empty server has no items.
      final views = await libraries(session, cancellation: cancellation);
      if (views.isEmpty) return const EmbyItemPage([], 0);
      throw const SourceFailure('请先选择 Plex 媒体库。');
    }
    final person = _personQuery(personKey);
    if (!parentId.startsWith('section:')) {
      return _page(
        session,
        '/library/metadata/${_id(parentId)}/allLeaves',
        start,
        limit,
        query: {'type': '4', ...person},
        cancellation: cancellation,
      );
    }
    final section = _id(parentId.substring(8));
    final views =
        _views[_scope(session)] ??
        await libraries(session, cancellation: cancellation);
    final library = views.where((e) => e.id == parentId).firstOrNull;
    if (library == null) throw const SourceFailure('Plex 媒体库已移除或无访问权限。');
    final path = '/library/sections/$section/all';
    final type = library.collectionType == 'tvshows'
        ? '2'
        : library.collectionType == 'music'
        ? '10'
        : '1';
    if (videosOnly || type != '2' || episodesOnly) {
      return _page(
        session,
        path,
        start,
        limit,
        query: {'type': episodesOnly ? '4' : type, ...person},
        cancellation: cancellation,
      );
    }
    // Translate the original show's two passes into one contiguous cursor.
    // Unknown totals stay unknown; a page's `size` is not a library total.
    final scope = '${_scope(session)}|$parentId|$personKey';
    if (start == 0) _showCounts.remove(scope);
    var shows = _showCounts[scope];
    final values = <EmbyItem>[];
    if (shows == null || start < shows) {
      final page = await _page(
        session,
        path,
        start,
        shows == null ? limit : limit.clamp(1, shows - start),
        query: {'type': '2', ...person},
        cancellation: cancellation,
      );
      if (shows != null && page.total != null && shows != page.total) {
        throw const SourceFailure('Plex 媒体库在分页期间发生变化，请重试。');
      }
      shows = page.total ?? (page.items.isEmpty ? start : null);
      if (shows != null) {
        if (_showCounts.length > 128) _showCounts.clear();
        _showCounts[scope] = shows;
      }
      values.addAll(page.items);
    }
    if (shows == null ||
        start + values.length < shows ||
        values.length == limit) {
      return EmbyItemPage(List.unmodifiable(values), null);
    }
    final offset = (start - shows).clamp(0, 1 << 53);
    final page = await _page(
      session,
      path,
      offset,
      limit - values.length,
      query: {'type': '4', ...person},
      cancellation: cancellation,
    );
    values.addAll(page.items);
    final total = page.total != null
        ? shows + page.total!
        : page.items.isEmpty
        ? start + values.length
        : null;
    return EmbyItemPage(List.unmodifiable(values), total);
  }

  Map<String, String> _personQuery(String? key) {
    if (key == null) return const {};
    final colon = key.indexOf(':');
    if (colon < 0) throw const SourceFailure('Plex 人物筛选标识无效。');
    final type = key.substring(0, colon), value = key.substring(colon + 1);
    if (type == 'name') return {'actor': value};
    if (!{'actor', 'director', 'writer', 'producer'}.contains(type)) {
      throw const SourceFailure('Plex 人物类型无效。');
    }
    return {type: _id(value)};
  }

  Future<EmbyItemPage> _page(
    EmbySession session,
    String path,
    int start,
    int limit, {
    Map<String, String> query = const {},
    ScanCancellation? cancellation,
  }) async {
    final scope = '${_scope(session)}|$path|${jsonEncode(query)}';
    final effectiveLimit = limit.clamp(1, _pageLimits[scope] ?? limit);
    XmlElement root;
    try {
      root = await _xml(
        session.server,
        path,
        session.token,
        query: query,
        headers: {
          'X-Plex-Container-Start': '$start',
          'X-Plex-Container-Size': '$effectiveLimit',
        },
        cancellation: cancellation,
      );
    } on EmbyFailure catch (error) {
      if (error.kind != EmbyError.tooLarge || effectiveLimit == 1) rethrow;
      if (_pageLimits.length > 128) _pageLimits.clear();
      _pageLimits[scope] = effectiveLimit ~/ 2;
      return _page(
        session,
        path,
        start,
        limit,
        query: query,
        cancellation: cancellation,
      );
    }
    final nodes = root.childElements
        .where((e) => {'Video', 'Directory', 'Track'}.contains(e.name.local))
        .toList();
    final total = plexInt(root, 'totalSize');
    final offset = plexInt(root, 'offset');
    if ((total != null && total < 0) ||
        (offset != null && offset != start) ||
        nodes.length > effectiveLimit ||
        (total != null && nodes.length > (total - start).clamp(0, total))) {
      throw const EmbyFailure(EmbyError.response, 'Plex 媒体分页响应无效，已保留原索引。');
    }
    return EmbyItemPage(
      List.unmodifiable(nodes.map((node) => plexItem(node, session.server))),
      total,
    );
  }

  Future<XmlElement> _metadata(
    EmbySession session,
    String id,
    ScanCancellation? cancellation,
  ) async {
    final root = await _xml(
      session.server,
      '/library/metadata/${_id(id)}',
      session.token,
      query: const {'includeExtras': '1'},
      cancellation: cancellation,
    );
    final node = root.childElements
        .where((e) => e.getAttribute('ratingKey') == id)
        .firstOrNull;
    if (node == null) {
      throw const EmbyFailure(EmbyError.response, 'Plex 没有返回当前媒体的详情。');
    }
    return node;
  }

  @override
  Future<EmbyDetail> detail(
    EmbySession session,
    String itemId, {
    String? mediaSourceId,
    ScanCancellation? cancellation,
  }) async => EmbyDetail.fromServer(
    plexItem(
      await _metadata(session, itemId, cancellation),
      session.server,
    ).data,
    itemId,
    mediaSourceId: mediaSourceId,
  );

  @override
  Future<List<EmbySubtitle>> subtitles(
    EmbySession session,
    String itemId,
    String? mediaSourceId, {
    ScanCancellation? cancellation,
  }) async {
    final item = plexItem(
      await _metadata(session, itemId, cancellation),
      session.server,
    );
    // Embedded streams are decoded by mpv; fetch only advertised external files.
    return EmbySubtitle.parse(
      item.data,
      itemId,
      mediaSourceId,
    ).where((s) => s.deliveryUrl != null).toList(growable: false);
  }

  @override
  Future<Uint8List> subtitle(
    EmbySession session,
    EmbySubtitle stream, {
    ScanCancellation? cancellation,
  }) {
    if (stream.deliveryUrl == null) {
      throw const SourceFailure('Plex 字幕没有可下载地址。');
    }
    return _bytes(
      session.server,
      stream.deliveryUrl!,
      session.token,
      maxBytes: 8 * 1024 * 1024,
      cancellation: cancellation,
    );
  }

  @override
  Future<Uint8List> artwork(
    EmbySession session,
    String itemId, {
    bool backdrop = false,
    int index = 0,
    int? maxWidth,
    ScanCancellation? cancellation,
  }) async {
    String? reference = itemId;
    if (!reference.startsWith('plex-artwork:')) {
      final node = await _metadata(session, itemId, cancellation);
      reference = plexArtworkReference(
        plexText(node, backdrop ? 'art' : 'thumb') ??
            (!backdrop ? plexText(node, 'grandparentThumb') : null),
        session.server,
      );
    }
    if (reference == null) throw const SourceFailure('Plex 媒体没有此图片。');
    String path;
    try {
      path = utf8.decode(
        base64Url.decode(reference.substring('plex-artwork:'.length)),
      );
    } catch (_) {
      throw const SourceFailure('Plex 图片标识无效。');
    }
    // The reference includes the server's image revision, so changing a poster
    // changes its cache key without persisting a credential.
    final image = Uri.tryParse(path);
    if (image == null ||
        image.hasScheme && !{'http', 'https'}.contains(image.scheme)) {
      throw const SourceFailure('Plex 图片地址无效。');
    }
    final publicImage =
        image.hasScheme && image.origin != session.server.origin;
    return _bytes(
      publicImage ? image.replace(path: '', query: '') : session.server,
      path,
      publicImage ? '' : session.token,
      publicArtwork: publicImage,
      maxBytes: maxArtworkBytes,
      cancellation: cancellation,
    );
  }

  @override
  EmbyPlaybackResource playbackResource(
    EmbySession session,
    RemoteMediaMetadata item, {
    bool audio = false,
    EmbyVideoQuality quality = EmbyVideoQuality.source,
    Duration start = Duration.zero,
    String? playSessionId,
  }) => throw const SourceFailure('Plex 必须先读取媒体文件信息。');

  @override
  Future<EmbyPlaybackResource> preparePlayback(
    EmbySession session,
    RemoteMediaMetadata item, {
    bool audio = false,
    EmbyVideoQuality quality = EmbyVideoQuality.source,
    Duration start = Duration.zero,
    String? playSessionId,
    ScanCancellation? cancellation,
  }) async {
    if (!quality.original) throw const SourceFailure('Plex 高级转码画质尚未迁移。');
    await validate(session, cancellation: cancellation);
    final node = await _metadata(session, item.externalId, cancellation);
    final parts = node
        .findElements('Media')
        .expand((m) => m.findElements('Part'))
        .toList();
    final part =
        parts
            .where((p) => plexText(p, 'id') == item.mediaSourceId)
            .firstOrNull ??
        parts.firstOrNull;
    final key = part == null ? null : plexText(part, 'key');
    if (key == null) throw const SourceFailure('Plex 媒体没有可直连的文件。');
    final uri = _uri(session.server, key, const {});
    cancellation?.check();
    return EmbyPlaybackResource(
      uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'X-Plex-Token': session.token,
        },
      ),
      plexText(part!, 'id'),
    );
  }

  @override
  Future<void> reportPlayback(
    EmbySession session, {
    required String itemId,
    required String playSessionId,
    required EmbyPlaybackPhase phase,
    required Duration position,
    required Duration duration,
    required bool paused,
    bool transcoding = false,
    String? mediaSourceId,
    ScanCancellation? cancellation,
  }) async {
    await _bytes(
      session.server,
      '/:/progress',
      session.token,
      query: {
        'key': _id(itemId),
        'identifier': 'com.plexapp.plugins.library',
        'time': '${position.inMilliseconds.clamp(0, 1 << 53)}',
        'state': phase == EmbyPlaybackPhase.stopped
            ? 'stopped'
            : paused
            ? 'paused'
            : 'playing',
      },
      cancellation: cancellation,
    );
  }

  @override
  Future<void> setUserFlag(
    EmbySession session,
    String itemId, {
    required bool favorite,
    required bool value,
  }) async {
    if (favorite) throw const SourceFailure('Plex 收藏仅保存在本机。');
    await _bytes(
      session.server,
      value ? '/:/scrobble' : '/:/unscrobble',
      session.token,
      query: {'key': _id(itemId), 'identifier': 'com.plexapp.plugins.library'},
    );
  }

  String _id(String value) {
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw const SourceFailure('Plex 媒体标识无效。');
    }
    return value;
  }

  Uri _uri(Uri base, String path, Map<String, String> query) {
    final raw = Uri.tryParse(path);
    if (raw == null ||
        raw.userInfo.isNotEmpty ||
        raw.hasFragment ||
        raw.pathSegments.any((s) => s == '..' || s.contains('\\')) ||
        (raw.hasScheme &&
            (!{'http', 'https'}.contains(raw.scheme) ||
                raw.origin != base.origin)) ||
        raw.hasAuthority && !raw.hasScheme) {
      throw const EmbyFailure(EmbyError.address, 'Plex 资源地址无效或指向其他服务器。');
    }
    final uri = raw.hasScheme
        ? raw
        : base.replace(
            path: base.path.isNotEmpty && raw.path.startsWith('${base.path}/')
                ? raw.path
                : '${base.path}/${raw.path.replaceFirst(RegExp(r'^/+'), '')}',
          );
    return uri.replace(
      queryParameters: {
        for (final entry in raw.queryParameters.entries)
          if (!{
            'x-plex-token',
            'api_key',
            'apikey',
            'token',
          }.contains(entry.key.toLowerCase()))
            entry.key: entry.value,
        ...query,
      },
    );
  }

  Future<XmlElement> _xml(
    Uri base,
    String path,
    String token, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    ScanCancellation? cancellation,
  }) async {
    final bytes = await _bytes(
      base,
      path,
      token,
      query: query,
      headers: headers,
      cancellation: cancellation,
    );
    try {
      final text = utf8.decode(bytes);
      if (RegExp(
        r'<!\s*(DOCTYPE|ENTITY)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        throw const FormatException();
      }
      final root = XmlDocument.parse(text).rootElement;
      if (root.name.local != 'MediaContainer') throw const FormatException();
      return root;
    } catch (_) {
      throw const EmbyFailure(EmbyError.response, 'Plex XML 响应无效。');
    }
  }

  Future<Uint8List> _bytes(
    Uri base,
    String path,
    String token, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    int? maxBytes,
    bool publicArtwork = false,
    bool allowRedirects = true,
    ScanCancellation? cancellation,
  }) async {
    cancellation?.check();
    HttpClientRequest? active;
    StreamIterator<List<int>>? reader;
    var expired = false;
    final stopped = Completer<Uint8List>();
    void stop(Object error) {
      expired = true;
      active?.abort();
      unawaited(reader?.cancel());
      if (!stopped.isCompleted) stopped.completeError(error);
    }

    final unlisten = cancellation?.listen(() => stop(const ScanCancelled()));
    final timer = Timer(
      timeout,
      () => stop(const EmbyFailure(EmbyError.network, 'Plex 请求超时，请重试。')),
    );
    Future<Uint8List> send() async {
      var uri = _uri(base, path, query);
      for (var attempt = 0; attempt < 6; attempt++) {
        active = await _plexHttp.getUrl(uri);
        if (expired) {
          active!.abort();
          throw const EmbyFailure(EmbyError.network, 'Plex 请求已结束。');
        }
        cancellation?.check();
        active!.followRedirects = false;
        for (final entry in {
          'Accept': 'application/xml',
          if (!publicArtwork) 'X-Plex-Product': 'ReelNest',
          if (!publicArtwork) 'X-Plex-Version': '0.1.0',
          if (!publicArtwork) 'X-Plex-Platform': Platform.operatingSystem,
          if (!publicArtwork) 'X-Plex-Device': Platform.operatingSystem,
          if (!publicArtwork) 'X-Plex-Client-Identifier': deviceId,
          if (!publicArtwork) 'X-Plex-Token': token,
          ...headers,
        }.entries) {
          active!.headers.set(entry.key, entry.value);
        }
        final response = await active!.close();
        if (expired) {
          await response.take(0).drain<void>();
          throw const EmbyFailure(EmbyError.network, 'Plex 请求已结束。');
        }
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          if (!allowRedirects) {
            await response.take(0).drain<void>();
            throw const EmbyFailure(
              EmbyError.address,
              'Plex 官方账号接口发生跳转，已停止发送凭据。',
            );
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          final next = location == null ? null : uri.resolve(location);
          await response.take(0).drain<void>();
          if (next == null ||
              next.origin != base.origin ||
              next.userInfo.isNotEmpty ||
              next.hasFragment) {
            throw const EmbyFailure(
              EmbyError.address,
              'Plex 资源发生跨站跳转，已停止发送凭据。',
            );
          }
          uri = next;
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.take(0).drain<void>();
          throw EmbyFailure(
            response.statusCode == 401
                ? EmbyError.authentication
                : response.statusCode == 403
                ? EmbyError.restricted
                : EmbyError.response,
            'Plex 请求失败（HTTP ${response.statusCode}）。',
            status: response.statusCode,
          );
        }
        final limit = maxBytes ?? maxResponseBytes;
        if (response.contentLength > limit) {
          await response.take(0).drain<void>();
          throw const EmbyFailure(EmbyError.tooLarge, 'Plex 响应超过安全读取上限。');
        }
        final bytes = BytesBuilder(copy: false);
        reader = StreamIterator<List<int>>(response);
        while (await reader!.moveNext()) {
          cancellation?.check();
          final chunk = reader!.current;
          if (bytes.length + chunk.length > limit) {
            throw const EmbyFailure(EmbyError.tooLarge, 'Plex 响应超过安全读取上限。');
          }
          bytes.add(chunk);
        }
        cancellation?.check();
        return bytes.takeBytes();
      }
      throw const EmbyFailure(EmbyError.response, 'Plex 重定向次数过多。');
    }

    try {
      return await Future.any([send(), stopped.future]);
    } on ScanCancelled {
      rethrow;
    } on SourceFailure {
      rethrow;
    } catch (_) {
      cancellation?.check();
      throw const EmbyFailure(EmbyError.network, '无法读取 Plex 服务器，请检查网络后重试。');
    } finally {
      expired = true;
      timer.cancel();
      unlisten?.call();
      active?.abort();
      await reader?.cancel();
    }
  }

  @override
  void close() {
    _views.clear();
    _showCounts.clear();
    _pageLimits.clear();
    _plexHttp.close(force: true);
    super.close();
  }
}
