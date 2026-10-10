import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_sheets.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/emby_server_fixture.dart';

class _Store implements CredentialStore {
  String? value;
  bool failWrite = false, failClear = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async {
    value = text; // Also exercise a partially successful secure-store write.
    if (failWrite) throw StateError('fixture');
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('fixture');
    value = null;
  }
}

class _RealHttpOverrides extends HttpOverrides {}

HttpClient _realHttp() => HttpOverrides.runWithHttpOverrides(
  () => HttpClient(),
  _RealHttpOverrides(),
);

void main() {
  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  final stores = <String, _Store>{};
  bool resourcesClosed = false;
  setUp(() async {
    resourcesClosed = false;
    stores.clear();
    server = EmbyServerFixture();
    await server.start();
    client = EmbyClient(deviceId: 'stable-test-device', http: _realHttp());
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores.putIfAbsent(id, _Store.new),
    );
  });
  tearDown(() async {
    if (!resourcesClosed) {
      connections.dispose();
      client.close();
      await sources.close();
      await server.close();
    }
  });
  Future<MediaSource> connect() =>
      connections.connect(server.address, ' tester ', ' p@ss word ');
  Matcher failure(EmbyError kind) =>
      isA<EmbyFailure>().having((e) => e.kind, 'kind', kind);

  test('normalizes optional scheme, IPv6 and proxy paths; rejects credentials and invalid addresses', () {
    expect(
      embyServerUri(' host:8096/proxy/ ').toString(),
      'http://host:8096/proxy',
    );
    expect(embyServerUri('http://[::1]:8096').host, '::1');
    for (final value in [
      '',
      'ftp://host',
      'http://u:p@host',
      'http://host?api_key=secret',
      'http://host/#secret',
      'http://bad host',
    ]) {
      expect(() => embyServerUri(value), throwsA(failure(EmbyError.address)));
    }
  });
  test('real HTTP authenticates with original body and identity, preserving proxy base', () async {
    final session = await client.authenticate(
      server.address,
      ' tester ',
      ' p@ss word ',
    );
    expect(session.userId, 'user-1');
    expect((await client.libraries(session)).map((l) => l.id), [
      'movies',
      'shows',
    ]);
    final request = server.requests.first;
    expect(request.method, 'POST');
    expect(jsonDecode(request.body), {
      'Username': 'tester',
      'Pw': ' p@ss word ',
    });
    expect(request.authorization, contains('Client="ReelNest"'));
    expect(request.authorization, contains('DeviceId="stable-test-device"'));
    expect(request.authorization, isNot(contains('Token=')));
    expect(server.requests.last.authorization, contains('Token="token-1"'));
  });
  test('source and options persist without secrets; restart restores session and device identity', () async {
    final source = await connect();
    expect(source.kind, MediaSourceKind.emby);
    expect(source.options.autoScan, isFalse);
    expect(
      source.options.remoteTraceSyncMode,
      RemoteTraceSyncMode.bidirectional,
    );
    expect(source.options.selectedEmbyLibraryIDs, isEmpty);
    expect(
      await sources.isReachable(source),
      isFalse,
    ); // No filesystem probing.
    final rows = await sources.database
        .customSelect('SELECT * FROM sources')
        .get();
    expect(rows.single.data.toString(), isNot(contains('token-1')));
    expect(rows.single.data.toString(), isNot(contains('p@ss')));
    final configs = await sources.database
        .customSelect('SELECT * FROM player_preferences')
        .get();
    expect(configs.single.data.toString(), isNot(contains('token-1')));
    expect(configs.single.data.toString(), isNot(contains('p@ss')));
    final restored = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores[id]!,
    );
    expect((await restored.session(source.id)).userId, 'user-1');
    expect(server.loginCount, 1);
    expect(
      await embyDeviceIdentity(sources.database),
      await embyDeviceIdentity(sources.database),
    );
    restored.dispose();
  });
  test('same server with separate accounts uses isolated source and secure-store keys', () async {
    final first = await connect();
    server.userId = 'user-2';
    final second = await connections.connect(
      server.address,
      'other',
      'other password',
    );
    expect(first.id, isNot(second.id));
    expect(first.location, isNot(second.location));
    expect(stores, hasLength(2));
    await connections.remove(first.id);
    expect((await sources.sources()).single.id, second.id);
    expect(stores[first.id]!.value, isNull);
    expect(stores[second.id]!.value, isNotNull);
  });
  test('library scope deduplicates, rejects empty custom scope, and supports all libraries', () async {
    final source = await connect();
    final selected = await connections.selectLibraries(
      source.id,
      all: false,
      selected: [' movies ', 'movies', 'shows'],
      metadata: false,
      health: false,
      trace: RemoteTraceSyncMode.importOnly,
    );
    expect(selected.options.selectedEmbyLibraryIDs, ['movies', 'shows']);
    expect(selected.options.includeInMetadataFetch, isFalse);
    expect(
      selected.options.remoteTraceSyncMode,
      RemoteTraceSyncMode.importOnly,
    );
    await expectLater(
      connections.selectLibraries(source.id, all: false, selected: []),
      throwsA(isA<SourceFailure>()),
    );
    expect((await sources.source(source.id)).options.selectedEmbyLibraryIDs, [
      'movies',
      'shows',
    ]);
    final all = await connections.selectLibraries(
      source.id,
      all: true,
      selected: ['movies'],
    );
    expect(all.options.selectedEmbyLibraryIDs, isEmpty);
    expect(all.options.includeInHealthCheck, isFalse);
  });
  test(
    'expired Views token refreshes once and persists the replacement',
    () async {
      final source = await connect();
      server.validToken = 'expired';
      expect(await connections.libraries(source.id), hasLength(2));
      expect(server.loginCount, 2);
      expect(stores[source.id]!.value, contains('token-2'));
      expect(await connections.libraries(source.id), hasLength(2));
      expect(server.loginCount, 2);
    },
  );
  test('repeated authentication failure stops after one refresh and retains source', () async {
    final source = await connect();
    server.validToken = 'expired';
    server.loginStatus = 401;
    await expectLater(
      connections.libraries(source.id),
      throwsA(failure(EmbyError.authentication)),
    );
    expect(server.loginCount, 2);
    expect(await sources.sources(), hasLength(1));
    expect(stores[source.id]!.value, contains('token-1'));
  });
  test(
    '403 restriction does not reauthenticate or delete existing source',
    () async {
      final source = await connect();
      server.viewsStatus = 403;
      await expectLater(
        connections.libraries(source.id),
        throwsA(failure(EmbyError.restricted)),
      );
      expect(server.loginCount, 1);
      expect(await sources.sources(), hasLength(1));
    },
  );
  test('valid empty library list differs from a malformed response', () async {
    final source = await connect();
    server.views = {'Items': []};
    expect(await connections.libraries(source.id), isEmpty);
    server.views = {
      'Items': [
        {'Id': null},
      ],
    };
    await expectLater(
      connections.libraries(source.id),
      throwsA(failure(EmbyError.response)),
    );
  });
  test(
    'bad login or malformed library response leaves no source or credentials',
    () async {
      server.loginStatus = 401;
      await expectLater(connect(), throwsA(failure(EmbyError.authentication)));
      server.loginStatus = 200;
      server.views = {'unexpected': []};
      await expectLater(connect(), throwsA(failure(EmbyError.response)));
      expect(await sources.sources(), isEmpty);
      expect(stores, isEmpty);
    },
  );
  test('secure write and SQL commit failures roll back partial credentials and source', () async {
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores.putIfAbsent(id, () => _Store()..failWrite = true),
    );
    await expectLater(connect(), throwsA(isA<SourceFailure>()));
    expect(await sources.sources(), isEmpty);
    expect(stores.values.every((s) => s.value == null), isTrue);
    stores.clear();
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores.putIfAbsent(id, _Store.new),
    );
    await sources.database.customStatement(
      "CREATE TRIGGER reject_config BEFORE INSERT ON player_preferences BEGIN SELECT RAISE(ABORT, 'fixture'); END",
    );
    await expectLater(connect(), throwsA(anything));
    expect(await sources.sources(), isEmpty);
    expect(stores.values.every((s) => s.value == null), isTrue);
  });
  test('lost credentials can be reauthenticated; another account cannot replace the source', () async {
    final source = await connect();
    await stores[source.id]!.clear();
    await connections.reauthenticate(source.id, 'tester', 'new password');
    expect((await connections.session(source.id)).userId, 'user-1');
    final saved = stores[source.id]!.value;
    server.userId = 'other';
    await expectLater(
      connections.reauthenticate(source.id, 'other', 'password'),
      throwsA(failure(EmbyError.authentication)),
    );
    expect(stores[source.id]!.value, saved);
  });
  test('removal refuses credential deletion failure and rolls back a failed SQL removal', () async {
    final source = await connect();
    stores[source.id]!.failClear = true;
    await expectLater(
      connections.remove(source.id),
      throwsA(isA<SourceFailure>()),
    );
    expect(await sources.sources(), hasLength(1));
    stores[source.id]!.failClear = false;
    await sources.database.customStatement(
      "CREATE TRIGGER reject_delete BEFORE DELETE ON sources BEGIN SELECT RAISE(ABORT, 'fixture'); END",
    );
    await expectLater(connections.remove(source.id), throwsA(anything));
    expect(stores[source.id]!.value, isNotNull);
    await sources.database.customStatement('DROP TRIGGER reject_delete');
    await connections.remove(source.id);
    expect(await sources.sources(), isEmpty);
    expect(
      (await sources.database
          .customSelect('SELECT * FROM player_preferences')
          .get()),
      isEmpty,
    );
  });
  test(
    'oversized responses are stopped while streaming and timeout is bounded',
    () async {
      client.close();
      client = EmbyClient(
        deviceId: 'fixture',
        http: _realHttp(),
        maxResponseBytes: 64,
        timeout: const Duration(milliseconds: 100),
      );
      server.override = (request) async {
        request.response.write('x' * 1000);
        await request.response.close();
      };
      await expectLater(
        client.authenticate(server.address, 'tester', 'pw'),
        throwsA(failure(EmbyError.tooLarge)),
      );
      server.override = (request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          await request.response.close();
        } catch (_) {}
      };
      await expectLater(
        client.authenticate(server.address, 'tester', 'pw'),
        throwsA(failure(EmbyError.network)),
      );
    },
  );
  test('cross-origin redirects cannot forward a login password', () async {
    final other = EmbyServerFixture();
    await other.start();
    try {
      server.override = (request) async {
        request.response.statusCode = 307;
        request.response.headers.set('location', other.address);
        await request.response.close();
      };
      await expectLater(connect(), throwsA(failure(EmbyError.address)));
      expect(other.requests, isEmpty);
      expect(await sources.sources(), isEmpty);
    } finally {
      await other.close();
    }
  });
  test('provider restores remote reachability without a filesystem adapter or provider cycle', () async {
    final source = await connect();
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        embyClientProvider.overrideWith((_) async => client),
        embyCredentialStoresProvider.overrideWithValue((id) => stores[id]!),
      ],
    );
    try {
      expect(
        (await container.read(sourceReachabilityProvider.future))[source.id],
        isTrue,
      );
    } finally {
      container.dispose();
    }
  });
  testWidgets('connection form logs in and closes with a saved source', (
    tester,
  ) async {
    MediaSource? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<MediaSource>(
                context: context,
                builder: (_) => EmbyConnectionSheet(repository: connections),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('emby-server')),
      server.address,
    );
    await tester.enterText(
      find.byKey(const ValueKey('emby-username')),
      'tester',
    );
    await tester.enterText(find.byKey(const ValueKey('emby-password')), ' pw ');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('参与策略'), findsOneWidget);
    await tester.tap(find.text('登录并同步'));
    for (var n = 0; n < 150 && saved == null; n++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(saved, isNotNull);
    await tester.pumpAndSettle();
    expect(find.byType(EmbyConnectionSheet), findsNothing);
    expect(saved!.options.selectedEmbyLibraryIDs, isEmpty);
    expect(saved!.options.autoScan, isFalse);
    expect(jsonDecode(server.requests.first.body)['Pw'], ' pw ');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    connections.dispose();
    client.close();
    await tester.runAsync(sources.close);
    await tester.runAsync(server.close);
    resourcesClosed = true;
  });
  testWidgets(
    'remote settings reads libraries and saves selected scope through the dialog',
    (tester) async {
      late MediaSource source;
      Future<void> finish(Future<void> work) async {
        var done = false;
        work.then((_) => done = true);
        for (var n = 0; n < 150 && !done; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done, isTrue);
      }

      await finish(connect().then((s) => source = s));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) =>
                    EmbyLibrarySheet(source: source, repository: connections),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (var n = 0; n < 150 && find.text('电影').evaluate().isEmpty; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('同步全部媒体库'), findsOneWidget);
      await tester.tap(find.text('电影').first);
      await tester.pump();
      expect(find.text('已选 1 个库'), findsOneWidget);
      await tester.tap(find.text('保存并同步'));
      await tester.pump(const Duration(milliseconds: 20));
      for (
        var n = 0;
        n < 150 && find.byType(EmbyLibrarySheet).evaluate().isNotEmpty;
        n++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byType(EmbyLibrarySheet), findsNothing);
      late MediaSource saved;
      await finish(sources.source(source.id).then((s) => saved = s));
      expect(saved.options.selectedEmbyLibraryIDs, ['movies']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      connections.dispose();
      client.close();
      await finish(sources.close());
      await tester.runAsync(server.close);
      resourcesClosed = true;
    },
  );
}
