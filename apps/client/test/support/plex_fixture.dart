import 'dart:convert';
import 'dart:io';

/// Strict local Plex HTTP fixture. Unknown/Emby routes fail rather than hiding a
/// provider routing error. No real server, token or user media is contacted.
class PlexFixture {
  late HttpServer server;
  String token = 'plex-test-token';
  String machineIdentifier = 'plex-machine';
  String accountId = '100';
  String accountName = 'Plex test account';
  int accountStatus = 200;
  String? accountBody;
  int sectionsStatus = 200;
  bool _closing = false;
  final requests =
      <({String method, Uri uri, Map<String, String> headers, String body})>[];
  final catalog = <String, List<String>>{
    '1': [plexMovie()],
    '2': [plexSeries(), plexEpisode('202', 1), plexEpisode('203', 2)],
  };
  final details = <String, String>{};
  Future<void> Function(HttpRequest)? override,
      detailHandler,
      accountHandler,
      itemsHandler,
      artworkHandler,
      streamHandler,
      playbackHandler;
  String get serverUri => 'http://127.0.0.1:${server.port}/plex';
  String get address => serverUri;
  Uri get accountEndpoint => Uri.parse('$serverUri/account');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await _respond(request);
      } catch (_) {
        if (!_closing) {
          try {
            request.response.statusCode = 500;
            await request.response.close();
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _respond(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    requests.add((
      method: request.method,
      uri: request.uri,
      headers: headers,
      body: body,
    ));
    if (override != null) return override!(request);
    final path = request.uri.path;
    final authenticated =
        request.headers.value('X-Plex-Token') == token ||
        request.uri.queryParameters['X-Plex-Token'] == token;
    final invalid =
        !path.startsWith('/plex/') ||
        request.method != 'GET' ||
        request.headers.value('X-Emby-Authorization') != null ||
        request.headers.value('Authorization') != null ||
        request.uri.queryParameters.keys.any(
          (key) => {'api_key', 'apikey'}.contains(key.toLowerCase()),
        );
    if (invalid) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType(
      'application',
      'xml',
      charset: 'utf-8',
    );
    if (path == '/plex/identity') {
      request.response.write(
        '<MediaContainer machineIdentifier="$machineIdentifier" friendlyName="Plex fixture"/>',
      );
    } else if (!authenticated) {
      request.response.statusCode = 401;
    } else if (path == '/plex/account') {
      if (accountHandler != null) return accountHandler!(request);
      request.response.statusCode = accountStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        accountBody ?? jsonEncode({'id': accountId, 'username': accountName}),
      );
    } else if (path == '/plex/library/sections') {
      request.response.statusCode = sectionsStatus;
      request.response.write(
        '<MediaContainer size="3"><Directory key="1" title="Plex 电影" type="movie"/><Directory key="2" title="Plex 电视剧" type="show"/><Directory key="3" title="照片" type="photo"/></MediaContainer>',
      );
    } else if (RegExp(r'^/plex/library/sections/\d+/all$').hasMatch(path) ||
        path.endsWith('/allLeaves')) {
      if (itemsHandler != null) return itemsHandler!(request);
      var values = path.endsWith('/allLeaves')
          ? catalog.values
                .expand((v) => v)
                .where(
                  (v) => v.contains(
                    'grandparentRatingKey="${request.uri.pathSegments[3]}"',
                  ),
                )
                .toList()
          : List<String>.from(catalog[request.uri.pathSegments[3]] ?? []);
      final type = request.uri.queryParameters['type'];
      final kind = {
        '1': 'movie',
        '2': 'show',
        '4': 'episode',
        '10': 'track',
      }[type];
      if (kind != null) {
        values = values.where((v) => v.contains('type="$kind"')).toList();
      }
      final actor = request.uri.queryParameters['actor'];
      if (actor != null) {
        values = values
            .where(
              (v) => v.contains('id="$actor"') || v.contains('tag="$actor"'),
            )
            .toList();
      }
      final start =
          int.tryParse(request.headers.value('X-Plex-Container-Start') ?? '') ??
          0;
      final size =
          int.tryParse(request.headers.value('X-Plex-Container-Size') ?? '') ??
          300;
      request.response.write(
        container(
          values.skip(start).take(size).join(),
          total: values.length,
          offset: start,
        ),
      );
    } else if (RegExp(r'^/plex/library/metadata/\d+$').hasMatch(path)) {
      if (detailHandler != null) return detailHandler!(request);
      final id = request.uri.pathSegments.last;
      final item =
          details[id] ??
          catalog.values
              .expand((v) => v)
              .where((v) => v.contains('ratingKey="$id"'))
              .firstOrNull;
      if (item == null) {
        request.response.statusCode = 404;
      } else {
        request.response.write(container(item, total: 1));
      }
    } else if (path.endsWith('/children')) {
      request.response.write(container('', total: 0));
    } else if (path.contains('/thumb/') || path.contains('/art/')) {
      if (artworkHandler != null) return artworkHandler!(request);
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAarVyFEAAAAASUVORK5CYII=',
        ),
      );
    } else if (path.startsWith('/plex/library/streams/')) {
      request.response.headers.contentType = ContentType(
        'text',
        'plain',
        charset: 'utf-8',
      );
      request.response.write('1\n00:00:01,000 --> 00:00:03,000\nPlex 中文字幕\n');
    } else if (path.startsWith('/plex/library/parts/')) {
      if (streamHandler != null) return streamHandler!(request);
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.add(List.filled(1024, 7));
    } else if (path.startsWith('/plex/:/')) {
      if (playbackHandler != null) return playbackHandler!(request);
      request.response.statusCode = 204;
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  static String container(
    String content, {
    required int total,
    int offset = 0,
  }) =>
      '<MediaContainer totalSize="$total" offset="$offset">$content</MediaContainer>';
  Future<void> close() async {
    _closing = true;
    await server.close(force: true);
  }
}

String plexMovie({
  String id = '101',
  String title = 'Plex 测试电影',
  String? partKey,
}) =>
    '''
<Video ratingKey="$id" title="$title" type="movie" year="2026" duration="24000" viewOffset="6000" audienceRating="8.5" summary="Plex 测试简介" thumb="/library/metadata/$id/thumb/1" art="/library/metadata/$id/art/1" originallyAvailableAt="2026-01-01">
  <Guid id="tmdb://123"/><Guid id="imdb://tt1234567"/><Genre tag="剧情"/>
  <Role id="501" tag="Plex 演员" role="主角" thumb="/library/metadata/501/thumb/1"/>
  <Media id="1001" container="avi" videoCodec="rawvideo" audioCodec="pcm_s16le" width="1920" height="1080" bitrate="18000">
    <Part id="9001" key="${partKey ?? '/library/parts/9001/1700000000/file.avi'}" container="avi" size="1024">
      <Stream id="1" streamType="1" codec="rawvideo" width="1920" height="1080"/>
      <Stream id="2" streamType="2" codec="pcm_s16le" languageCode="eng"/>
      <Stream id="31" streamType="3" codec="srt" languageCode="zho" displayTitle="Plex 中文字幕" key="/library/streams/31"/>
    </Part>
  </Media>
</Video>''';

String plexSeries() =>
    '<Directory ratingKey="201" title="Plex 测试剧集" type="show" year="2026" summary="Plex series" thumb="/library/metadata/201/thumb/1"><Role id="501" tag="Plex 演员"/></Directory>';
String plexEpisode(String id, int episode) =>
    '''
<Video ratingKey="$id" title="Plex 第$episode集" type="episode" grandparentRatingKey="201" grandparentTitle="Plex 测试剧集" parentIndex="1" index="$episode" duration="24000" viewOffset="4000">
<Media container="avi"><Part id="9$id" key="/library/parts/9$id/1700000000/file.avi" container="avi" size="1024"/></Media></Video>''';
