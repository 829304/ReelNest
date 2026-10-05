import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/mlink/mlink_client.dart';
import 'package:reelnest/domain/app_failure.dart';
import 'package:reelnest/domain/media.dart';
import 'package:reelnest/domain/server_address.dart';

import 'support/smoke_fixtures.dart';

void main() {
  test('loopback HTTP discovery, token login, browse, series, episodes and artwork', () async {
    final requests =
        <
          ({
            String method,
            Uri uri,
            String? auth,
            String? native,
            String? cookie,
            Object? body,
          })
        >[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        uri: request.uri,
        auth: request.headers.value(HttpHeaders.authorizationHeader),
        native: request.headers.value('X-MediaLIB-Client'),
        cookie: request.headers.value(HttpHeaders.cookieHeader),
        body: body.isEmpty ? null : jsonDecode(body),
      ));
      final segments = request.uri.pathSegments;
      Object payload;
      if (segments.first == '.well-known') {
        payload = smokeDescriptor();
      } else if (segments.contains('auth')) {
        payload = smokeTokens();
      } else if (segments.contains('browse')) {
        payload = {
          'offset': 0,
          'limit': 48,
          'hasMore': false,
          'totalItemCount': 1,
          'items': [smokeItem(smokeSeriesId, '测试系列', series: true)],
        };
      } else if (segments.contains('episodes')) {
        payload = {
          'offset': 0,
          'limit': 48,
          'hasMore': false,
          'totalItemCount': 0,
          'items': [],
        };
      } else if (segments.contains('images')) {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        );
        await request.response.close();
        return;
      } else {
        payload = smokeSeries();
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
      await request.response.close();
    });
    final address = ServerAddress.parse('http://127.0.0.1:${server.port}');
    final client = MlinkClient();
    expect((await client.discover(address)).id, 'smoke-server');
    final tokens = await client.login(
      address: address,
      username: 'smoke-user',
      password: 'synthetic-password',
      deviceName: 'smoke-device',
      platform: 'test',
    );
    expect(
      (await client.browse(
        address,
        tokens.accessToken,
        type: 'tvShow',
        offset: 0,
        sort: MediaSort.title,
      )).items.single.id,
      smokeSeriesId,
    );
    expect(
      (await client.seriesDetail(
        address,
        tokens.accessToken,
        smokeSeriesId,
      )).seriesSummary!.seasons.length,
      3,
    );
    expect(
      (await client.episodes(
        address,
        tokens.accessToken,
        seriesId: smokeSeriesId,
        season: 'unspecified',
        offset: 0,
      )).items,
      isEmpty,
    );
    expect(
      await client.artwork(address, tokens.accessToken, smokeSeriesId),
      isNotEmpty,
    );

    expect(requests, hasLength(6));
    expect(requests[0].auth, isNull);
    expect(requests[1].method, 'POST');
    expect(requests[1].native, 'mlink-native/1');
    expect((requests[1].body! as Map)['delivery'], 'token');
    for (final request in requests.skip(2)) {
      expect(request.auth, 'Bearer $smokeToken');
      expect(request.uri.toString(), isNot(contains(smokeToken)));
      expect(request.cookie, isNull);
    }
    expect(requests[2].uri.queryParameters['sort'], 'title');
    expect(requests[3].uri.pathSegments.last, smokeSeriesId);
    expect(requests[4].uri.pathSegments[3], smokeSeriesId);
    expect(requests[4].uri.queryParameters['season'], 'unspecified');
    expect(requests[5].uri.queryParameters['size'], '320');
  });

  test(
    'HTTP redirects are not followed and missing series stays notFound',
    () async {
      var redirectedRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/redirected') {
          redirectedRequests++;
          request.response.statusCode = HttpStatus.ok;
        } else if (request.uri.path.contains('/series/')) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/redirected',
          );
        }
        await request.response.close();
      });
      final address = ServerAddress.parse('http://127.0.0.1:${server.port}');
      final client = MlinkClient();
      await expectLater(
        client.artwork(address, smokeToken, 'image'),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.invalidInput,
          ),
        ),
      );
      expect(redirectedRequests, 0);
      await expectLater(
        client.seriesDetail(address, smokeToken, 'missing'),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.notFound),
        ),
      );
    },
  );
}
