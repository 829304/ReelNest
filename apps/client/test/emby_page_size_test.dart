import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/emby_server_fixture.dart';

class _Store implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

Map<String, dynamic> _movie(String id, {int size = 360}) => {
  'Id': id,
  'Name': id,
  'Type': 'Movie',
  'Overview': 'x' * size,
  'MediaSources': [
    {'Id': 'media-$id', 'Container': 'mkv'},
  ],
};

void main() {
  late EmbyServerFixture server;
  late EmbyClient client;
  late EmbySession session;
  setUp(() async {
    server = EmbyServerFixture()..itemPageSize = 300;
    await server.start();
    // Small limits exercise the real transport without allocating huge bodies.
    client = EmbyClient(deviceId: 'pagination-fixture', maxResponseBytes: 1200);
    session = await client.authenticate(server.address, 'tester', 'pw');
  });
  tearDown(() async {
    client.close();
    await server.close();
  });
  List<Map<String, String>> pages() => server.requests
      .where((r) => r.uri.path.endsWith('/Items'))
      .map((r) => r.uri.queryParameters)
      .toList();

  test('oversized page retries same start, retains fields, and learns scoped limit', () async {
    server.catalog['movies'] = [for (var i = 0; i < 8; i++) _movie('$i')];
    final page = await client.itemPage(
      session,
      parentId: 'movies',
      start: 0,
      limit: 8,
    );
    expect(page.items.map((i) => i.id), ['0', '1']);
    expect(page.total, 8);
    expect(pages().map((p) => p['Limit']), ['8', '4', '2']);
    expect(pages().map((p) => p['StartIndex']), everyElement('0'));
    expect(pages().map((p) => p['Fields']).toSet().length, 1);
    expect(pages().last['Fields'], contains('MediaSources'));
    final next = await client.itemPage(
      session,
      parentId: 'movies',
      start: 2,
      limit: 8,
    );
    expect(next.items.map((i) => i.id), ['2', '3']);
    expect(pages().last['Limit'], '2');
    // A small explicit caller limit, another library and foreground queries
    // retain their own page budgets instead of inheriting a global reduction.
    await client.itemPage(session, parentId: 'movies', start: 4, limit: 1);
    expect(pages().last['Limit'], '1');
    server.catalog['shows'] = [];
    await client.itemPage(session, parentId: 'shows', start: 0, limit: 8);
    expect(pages().last['Limit'], '8');
    server.catalog['movies'] = [];
    await client.itemPage(
      session,
      parentId: 'movies',
      start: 0,
      limit: 8,
      videosOnly: true,
    );
    expect(pages().last['Limit'], '8');
  });

  for (final knownLength in [true, false]) {
    test(
      'oversized pages resize with known Content-Length=$knownLength without raising allowance',
      () async {
        server.itemsHandler = (request) async {
          final limit = int.parse(request.uri.queryParameters['Limit']!);
          final bytes = utf8.encode(
            jsonEncode({
              'Items': [for (var i = 0; i < limit; i++) _movie('$i')],
              'TotalRecordCount': 8,
            }),
          );
          if (knownLength) {
            request.response.headers.set(
              HttpHeaders.contentLengthHeader,
              bytes.length,
            );
          }
          request.response.add(bytes);
          await request.response.close();
        };
        final page = await client.itemPage(
          session,
          parentId: 'movies',
          start: 0,
          limit: 8,
        );
        expect(page.items.length, 2);
        expect(client.maxResponseBytes, 1200);
        expect(pages().map((p) => p['Limit']), ['8', '4', '2']);
      },
    );
  }

  test(
    'full synchronization advances by actual count and commits every item',
    () async {
      server.catalog['movies'] = [for (var i = 0; i < 7; i++) _movie('$i')];
      server.catalog['shows'] = [];
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      final store = _Store();
      final connections = EmbyConnectionRepository(
        sources: sources,
        client: Future.value(client),
        stores: (_) => store,
      );
      addTearDown(() async {
        connections.dispose();
        await sources.close();
      });
      final source = await connections.connect(server.address, 'tester', 'pw');
      await connections.selectLibraries(
        source.id,
        all: false,
        selected: ['movies'],
      );
      await EmbySyncRepository(
        sources: sources,
        connections: connections,
      ).synchronize(source.id);
      final items = (await sources.browse(source.id)).items;
      expect(items.map((i) => i.identity.localId).toSet(), {
        for (var i = 0; i < 7; i++) '$i',
      });
      expect((await sources.source(source.id)).lastScan, isNotNull);
      expect(
        pages()
            .where((p) => p['StartIndex'] != '0')
            .map((p) => p['StartIndex']),
        ['2', '4', '6'],
      );
      expect(
        pages().where((p) => p['StartIndex'] != '0').map((p) => p['Limit']),
        everyElement('2'),
      );
    },
  );

  test('server ignoring Limit fails finitely and preserves previous complete index', () async {
    server.catalog['movies'] = [_movie('old', size: 0)];
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    final store = _Store();
    final connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (_) => store,
    );
    addTearDown(() async {
      connections.dispose();
      await sources.close();
    });
    final source = await connections.connect(server.address, 'tester', 'pw');
    await connections.selectLibraries(
      source.id,
      all: false,
      selected: ['movies'],
    );
    final sync = EmbySyncRepository(sources: sources, connections: connections);
    await sync.synchronize(source.id);
    final previous = (await sources.source(source.id)).lastScan;
    server.requests.clear();
    server.itemsHandler = (request) async {
      request.response.write(
        jsonEncode({
          'Items': [_movie('huge', size: 5000)],
          'TotalRecordCount': 1,
        }),
      );
      await request.response.close();
    };
    await expectLater(
      sync.synchronize(source.id),
      throwsA(
        isA<EmbyFailure>()
            .having((e) => e.kind, 'kind', EmbyError.tooLarge)
            .having((e) => e.message, 'message', contains('分页已缩小至 1 条')),
      ),
    );
    expect(pages().map((p) => p['Limit']), [
      '300',
      '150',
      '75',
      '37',
      '18',
      '9',
      '4',
      '2',
      '1',
    ]);
    expect(
      (await sources.browse(source.id)).items.single.identity.localId,
      'old',
    );
    expect((await sources.source(source.id)).lastScan, previous);
  });

  test('network failures never trigger size backoff', () async {
    server.itemsHandler = (request) async {
      request.response.statusCode = 503;
      await request.response.close();
    };
    await expectLater(
      client.itemPage(session, start: 0, limit: 8),
      throwsA(
        isA<EmbyFailure>().having((e) => e.kind, 'kind', EmbyError.response),
      ),
    );
    expect(pages().map((p) => p['Limit']), ['8']);
  });

  test(
    'oversized headers close stalled response before reusing one connection',
    () async {
      client.close();
      client = EmbyClient(
        deviceId: 'pagination-fixture',
        maxResponseBytes: 1200,
        http: HttpClient()..maxConnectionsPerHost = 1,
      );
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      server.itemsHandler = (request) async {
        try {
          if (request.uri.queryParameters['Limit'] == '2') {
            request.response.contentLength = 5000;
            request.response.bufferOutput = false;
            request.response.add([32]);
            await request.response.flush();
            await release.future;
          } else {
            request.response.write(
              jsonEncode({
                'Items': [_movie('ok')],
                'TotalRecordCount': 1,
              }),
            );
          }
          await request.response.close();
        } catch (_) {
          /* Expected canceled oversized response. */
        }
      };
      final page = await client
          .itemPage(session, start: 0, limit: 2)
          .timeout(const Duration(seconds: 2));
      expect(page.items.single.id, 'ok');
      expect(pages().map((p) => p['Limit']), ['2', '1']);
    },
  );

  test('cancellation prevents retries of an oversized response', () async {
    final cancellation = ScanCancellation();
    server.itemsHandler = (request) async {
      cancellation.cancel();
      request.response.add(List.filled(5000, 32));
      await request.response.close();
    };
    await expectLater(
      client.itemPage(session, start: 0, limit: 8, cancellation: cancellation),
      throwsA(isA<ScanCancelled>()),
    );
    expect(pages().length, 1);
  });
}
