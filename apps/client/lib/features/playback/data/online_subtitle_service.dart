import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unicode;
import 'package:xml/xml.dart';

import '../../../domain/media_source.dart';
import '../domain/online_subtitle.dart';
import 'online_subtitle_payload.dart';

class OnlineSubtitleService {
  OnlineSubtitleService({
    Uri? openSubtitlesBase,
    Uri? podnapisiBase,
    this.allowInsecureForTesting = false,
    this.timeout = const Duration(seconds: 15),
  }) : openSubtitlesBase =
           openSubtitlesBase ??
           Uri.parse('https://api.opensubtitles.com/api/v1/'),
       podnapisiBase = podnapisiBase ?? Uri.parse('https://www.podnapisi.net/');
  final Uri openSubtitlesBase, podnapisiBase;
  final bool allowInsecureForTesting;
  final Duration timeout;
  static const _agent = 'ReelNest v0.1.0';

  Future<OnlineSubtitleSearch> search(
    OnlineSubtitleQuery query,
    OnlineSubtitleSettings settings,
    ScanCancellation cancellation,
  ) async {
    if (query.title.trim().isEmpty) {
      throw const OnlineSubtitleFailure('缺少影片名称，无法搜索字幕。');
    }
    Future<OnlineSubtitleSearch> attempt(
      OnlineSubtitleProvider provider,
    ) async {
      try {
        return OnlineSubtitleSearch(
          await _searchProvider(provider, query, settings, cancellation),
          const [],
        );
      } on ScanCancelled {
        rethrow;
      } catch (error) {
        final source = provider == OnlineSubtitleProvider.podnapisi
            ? 'Podnapisi'
            : 'OpenSubtitles';
        final message = error is OnlineSubtitleFailure
            ? error.message
            : '字幕服务暂不可用，请重试。';
        return OnlineSubtitleSearch(const [], ['$source：$message']);
      }
    }

    final sources = await Future.wait([
      attempt(OnlineSubtitleProvider.podnapisi),
      if (settings.apiKey.isNotEmpty)
        attempt(OnlineSubtitleProvider.openSubtitles),
    ]);
    cancellation.check();
    final seen = <String>{};
    final results = <OnlineSubtitleResult>[];
    for (final source in sources) {
      for (final result in source.results) {
        final name = unicode
            .nfkd(result.displayName.trim())
            .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
            .toLowerCase();
        if (seen.add(name)) results.add(result);
      }
    }
    return OnlineSubtitleSearch(
      List.unmodifiable(results),
      List.unmodifiable(sources.expand((s) => s.warnings)),
    );
  }

  Future<List<OnlineSubtitleResult>> _searchProvider(
    OnlineSubtitleProvider provider,
    OnlineSubtitleQuery query,
    OnlineSubtitleSettings settings,
    ScanCancellation token,
  ) async {
    if (provider == OnlineSubtitleProvider.podnapisi) {
      final uri = podnapisiBase
          .resolve('api/search/1')
          .replace(
            queryParameters: {
              'keywords': query.title,
              'language': podnapisiLanguage(settings.language),
            },
          );
      final bytes = await _request(uri, token, maxBytes: 2 * 1024 * 1024);
      token.check();
      return parsePodnapisi(bytes, settings.language);
    }
    final parameters = SplayTreeMap<String, String>.from({
      'query': query.title,
      'languages': openSubtitlesLanguage(settings.language),
      'order_by': 'download_count',
      'order_direction': 'desc',
      if (query.year != null) 'year': '${query.year}',
      if (RegExp(r'^tt\d+$').hasMatch(query.imdbID ?? ''))
        'imdb_id': query.imdbID!.substring(2),
      if (query.season != null) 'season_number': '${query.season}',
      if (query.episode != null) 'episode_number': '${query.episode}',
    });
    final bytes = await _request(
      openSubtitlesBase
          .resolve('subtitles')
          .replace(queryParameters: parameters),
      token,
      apiKey: settings.apiKey,
      maxBytes: 2 * 1024 * 1024,
    );
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map || root['data'] is! List) {
      throw const FormatException('Invalid subtitles');
    }
    final result = <OnlineSubtitleResult>[];
    for (final item in (root['data'] as List).take(1000)) {
      if (item is! Map || item['attributes'] is! Map) continue;
      final attrs = item['attributes'] as Map;
      final files = attrs['files'];
      if (files is! List || files.isEmpty || files.first is! Map) continue;
      final file = files.first as Map, id = file['file_id'];
      if (id is! int || id <= 0) continue;
      result.add(
        OnlineSubtitleResult(
          id: 'os-${item['id'] ?? id}',
          provider: provider,
          fileId: id,
          displayName:
              _text(file['file_name']) ?? _text(attrs['release']) ?? '字幕 #$id',
          language: _text(attrs['language']) ?? settings.language,
          downloads: attrs['download_count'] is int
              ? (attrs['download_count'] as int).clamp(0, 1 << 31)
              : 0,
        ),
      );
    }
    return result;
  }

  Future<OnlineSubtitlePayload> download(
    OnlineSubtitleResult result,
    OnlineSubtitleSettings settings,
    ScanCancellation token,
  ) async {
    if (result.fileId <= 0) throw const OnlineSubtitleFailure('字幕标识无效，请重新搜索。');
    Uri uri;
    String? name;
    if (result.provider == OnlineSubtitleProvider.podnapisi) {
      uri = podnapisiBase.resolve('subtitles/${result.fileId}/download');
    } else {
      if (settings.apiKey.isEmpty) {
        throw const OnlineSubtitleFailure('请先在设置中填写 OpenSubtitles API Key。');
      }
      final response = await _request(
        openSubtitlesBase.resolve('download'),
        token,
        apiKey: settings.apiKey,
        body: jsonEncode({'file_id': result.fileId}),
        maxBytes: 64 * 1024,
      );
      final data = jsonDecode(utf8.decode(response));
      if (data is! Map || data['link'] is! String) {
        throw const OnlineSubtitleFailure('字幕下载地址无效，请重新搜索。');
      }
      uri = Uri.parse(data['link'] as String);
      name = _text(data['file_name']);
    }
    // Signed file hosts never receive Api-Key or media-server credentials.
    final bytes = await _request(
      uri,
      token,
      maxBytes: OnlineSubtitlePayload.maxArchiveBytes,
    );
    token.check();
    return OnlineSubtitlePayload.decode(
      bytes,
      filename: name,
      cancellation: token,
    );
  }

  void _checkURI(Uri uri) {
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !(uri.scheme == 'https' ||
            (allowInsecureForTesting && uri.scheme == 'http'))) {
      throw const OnlineSubtitleFailure('字幕服务返回了无效的下载地址。');
    }
  }

  Future<Uint8List> _request(
    Uri initial,
    ScanCancellation token, {
    String? apiKey,
    String? body,
    required int maxBytes,
  }) async {
    token.check();
    _checkURI(initial);
    final client = HttpClient()..connectionTimeout = timeout;
    final cancelled = Completer<Uint8List>();
    final unlisten = token.listen(() {
      client.close(force: true);
      if (!cancelled.isCompleted) {
        cancelled.completeError(const ScanCancelled());
      }
    });
    Future<Uint8List> perform() async {
      var uri = initial, payload = body, method = body == null ? 'GET' : 'POST';
      for (var redirect = 0; redirect <= 4; redirect++) {
        token.check();
        _checkURI(uri);
        final request = await client.openUrl(method, uri);
        token.check();
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, _agent);
        final authentication = apiKey;
        if (authentication != null && uri.origin == initial.origin) {
          if (authentication.contains(RegExp(r'[^\x20-\x7e]')) ||
              authentication.length > 1024) {
            throw const OnlineSubtitleFailure('OpenSubtitles API Key 格式不正确。');
          }
          request.headers.set('Api-Key', authentication);
        }
        if (payload != null) {
          request.headers.contentType = ContentType.json;
          request.write(payload);
        }
        final response = await request.close();
        token.check();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirect == 4) {
            throw const OnlineSubtitleFailure('字幕服务重定向失败。');
          }
          final next = uri.resolve(location);
          _checkURI(next);
          // Never forward credentials after leaving the original API origin,
          // including if a later redirect returns to it.
          if (next.origin != uri.origin) apiKey = null;
          uri = next;
          if (response.statusCode == 303 ||
              response.statusCode == 301 ||
              response.statusCode == 302) {
            method = 'GET';
            payload = null;
          }
          // A redirect body is untrusted and can be unbounded; do not drain it.
          await response.listen((_) {}).cancel();
          continue;
        }
        final status = response.statusCode;
        if (status < 200 || status >= 300) {
          if (status == 406 || status == 429) {
            throw const OnlineSubtitleFailure('字幕服务请求或下载额度已受限，请稍后重试。');
          }
          if (status == 401 || status == 403) {
            throw const OnlineSubtitleFailure('字幕服务拒绝访问，请检查 API Key 或稍后重试。');
          }
          throw const OnlineSubtitleFailure('字幕服务请求失败，请稍后重试。');
        }
        if (response.contentLength > maxBytes) {
          throw const OnlineSubtitleFailure('字幕服务响应过大，已停止读取。');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          token.check();
          if (bytes.length + chunk.length > maxBytes) {
            throw const OnlineSubtitleFailure('字幕服务响应过大，已停止读取。');
          }
          bytes.add(chunk);
        }
        token.check();
        return bytes.takeBytes();
      }
      throw const OnlineSubtitleFailure('字幕服务重定向失败。');
    }

    try {
      return await Future.any([perform(), cancelled.future]).timeout(
        timeout,
        onTimeout: () => throw const OnlineSubtitleFailure('字幕服务连接超时，请重试。'),
      );
    } on ScanCancelled {
      rethrow;
    } on OnlineSubtitleFailure {
      rethrow;
    } catch (_) {
      throw const OnlineSubtitleFailure('字幕服务连接或响应异常，请稍后重试。');
    } finally {
      unlisten();
      client.close(force: true);
    }
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty
      ? value.trim().substring(0, value.trim().length.clamp(0, 1024))
      : null;
  static String podnapisiLanguage(String language) {
    final value = language.toLowerCase();
    if (value.startsWith('zh-hant') || value == 'zh-tw' || value == 'zh-hk') {
      return 'zht';
    }
    if (value.startsWith('zh')) return 'zh';
    return value.split('-').first;
  }

  static String openSubtitlesLanguage(String language) {
    final pod = podnapisiLanguage(language);
    return pod == 'zh'
        ? 'zh-cn'
        : pod == 'zht'
        ? 'zh-tw'
        : pod;
  }

  static List<OnlineSubtitleResult> parsePodnapisi(
    Uint8List bytes,
    String language,
  ) {
    final text = utf8.decode(bytes);
    if (text.toUpperCase().contains('<!DOCTYPE') ||
        text.toUpperCase().contains('<!ENTITY')) {
      throw const FormatException('Unexpected XML declarations');
    }
    final document = XmlDocument.parse(text);
    if (document.rootElement.name.local.toLowerCase() == 'html') {
      throw const FormatException('Unexpected HTML response');
    }
    return [
      for (final element in document.findAllElements('subtitle').take(1000))
        if (int.tryParse(element.getElement('id')?.innerText.trim() ?? '')
            case final int id when id > 0)
          OnlineSubtitleResult(
            id: 'pod-$id',
            provider: OnlineSubtitleProvider.podnapisi,
            fileId: id,
            displayName:
                _text(element.getElement('release')?.innerText) ?? '字幕 #$id',
            language:
                _text(element.getElement('language')?.innerText) ?? language,
            downloads:
                (int.tryParse(
                          element.getElement('downloads')?.innerText.trim() ??
                              '',
                        ) ??
                        0)
                    .clamp(0, 1 << 31),
          ),
    ];
  }
}
