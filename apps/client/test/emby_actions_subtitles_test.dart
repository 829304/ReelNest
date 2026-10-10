import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_subtitle.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_media_actions.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/emby_server_fixture.dart';
import 'support/fake_video_engine.dart';

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

class _Http extends HttpOverrides {}

void main() {
  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late EmbySyncRepository sync;
  late MediaSource source;
  late PlaybackRepository records;
  final stores = <String, _Store>{};
  MediaIdentity id(String value) => (sourceId: source.id, localId: value);
  Map<String, dynamic> movie(String value) => {
    'Id': value,
    'Name': value,
    'Type': 'Movie',
    'RunTimeTicks': 1000000000,
    'MediaSources': [
      {'Id': 'resource', 'Container': 'mkv'},
    ],
    'UserData': {
      'PlaybackPositionTicks': 300000000,
      'LastPlayedDate': '2026-10-08T12:00:00Z',
      'IsFavorite': false,
    },
  };
  Map<String, dynamic> detail({String? delivery}) => {
    'MediaSources': [
      {
        'Id': 'other',
        'MediaStreams': [
          {'Type': 'Subtitle', 'Index': 9, 'Codec': 'ass'},
        ],
      },
      {
        'Id': 'resource',
        'MediaStreams': [
          {'Type': 'Video', 'Index': 0},
          {
            'Type': 'Subtitle',
            'Index': 3,
            'Codec': 'subrip',
            'Language': 'zho',
            'DisplayTitle': '简体中文',
            'DeliveryUrl': ?delivery,
          },
          {
            'Type': 'Subtitle',
            'Index': 4,
            'Codec': 'webvtt',
            'Language': 'eng',
          },
          {'Type': 'Subtitle', 'Index': 5, 'Codec': 'hdmv_pgs_subtitle'},
        ],
      },
    ],
  };
  List<({String method, Uri uri, String? authorization, String body})>
  flags() => server.requests
      .where(
        (r) =>
            r.uri.path.contains('/FavoriteItems/') ||
            r.uri.path.contains('/PlayedItems/'),
      )
      .toList();
  setUp(() async {
    stores.clear();
    server = EmbyServerFixture();
    await server.start();
    client = EmbyClient(
      deviceId: 'actions-test',
      http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
    );
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (key) => stores.putIfAbsent(key, _Store.new),
    );
    source = await connections.connect(server.address, 'tester', 'fixture');
    server.catalog['movies'] = [movie('film'), movie('second'), movie('third')];
    sync = EmbySyncRepository(sources: sources, connections: connections);
    await sync.synchronize(source.id);
    records = PlaybackRepository(sources.database);
    server.detailHandler = (r) async {
      r.response.write(jsonEncode(detail()));
      await r.response.close();
    };
    server.streamHandler = (r) async {
      r.response.write('1\n00:00:01,000 --> 00:00:02,000\n字幕\n');
      await r.response.close();
    };
  });
  tearDown(() async {
    connections.dispose();
    client.close();
    await sources.close();
    await server.close();
  });

  test(
    'favorite POST and DELETE use user, item and proxy path; SQL persists',
    () async {
      await connections.setFavorite(id('film'), true);
      expect((await sources.media(id('film'))).remote!.favorite, isTrue);
      await connections.setFavorite(id('film'), false);
      expect((await sources.media(id('film'))).remote!.favorite, isFalse);
      expect(flags().map((r) => r.method), ['POST', 'DELETE']);
      expect(
        flags().first.uri.path,
        '/proxy/emby/Users/user-1/FavoriteItems/film',
      );
    },
  );
  test('favorite failure rolls back and emits refreshed state', () async {
    var revisions = 0;
    final subscription = sources.changes.listen((_) => revisions++);
    server.userFlagHandler = (r) async {
      r.response.statusCode = 503;
      await r.response.close();
    };
    await expectLater(
      connections.setFavorite(id('film'), true),
      throwsA(isA<SourceFailure>()),
    );
    expect((await sources.media(id('film'))).remote!.favorite, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(revisions, greaterThanOrEqualTo(2));
    await subscription.cancel();
  });
  test('expired action authenticates once and retries same user', () async {
    server.validToken = 'expired';
    await connections.setFavorite(id('film'), true);
    expect(server.loginCount, 2);
    expect(flags().length, 2);
    expect(flags().last.uri.queryParameters['api_key'], 'token-2');
  });
  for (final mode in [
    RemoteTraceSyncMode.importOnly,
    RemoteTraceSyncMode.disabled,
  ]) {
    test('${mode.name} updates local flags without writing remote', () async {
      await connections.selectLibraries(
        source.id,
        all: true,
        selected: [],
        trace: mode,
      );
      await connections.setFavorite(id('film'), true);
      expect(await connections.markPlayed([id('film')], true), 0);
      expect(flags(), isEmpty);
      expect((await records.read(id('film'))).watched, isTrue);
      await sync.synchronize(source.id);
      expect(
        (await sources.media(id('film'))).remote!.favorite,
        mode == RemoteTraceSyncMode.disabled,
      );
      expect(
        (await records.read(id('film'))).watched,
        mode == RemoteTraceSyncMode.disabled,
      );
    });
  }
  test(
    'mark watched keeps resume/date; unwatched clears both and uses DELETE',
    () async {
      final before = await records.read(id('film'));
      await connections.markPlayed([id('film')], true);
      var after = await records.read(id('film'));
      expect(after.watched, isTrue);
      expect(after.position, before.position);
      expect(after.lastPlayedAt, before.lastPlayedAt);
      await connections.markPlayed([id('film')], false);
      after = await records.read(id('film'));
      expect(after.watched, isFalse);
      expect(after.position, Duration.zero);
      expect(after.lastPlayedAt, isNull);
      expect(flags().map((r) => r.method), ['POST', 'DELETE']);
      expect(flags().last.uri.path, endsWith('/PlayedItems/film'));
    },
  );
  test(
    'batch failure retains all local updates and continues later items',
    () async {
      server.userFlagHandler = (r) async {
        r.response.statusCode = r.uri.path.endsWith('/second') ? 503 : 204;
        await r.response.close();
      };
      final ids = ['film', 'second', 'third'].map(id).toList();
      expect(await connections.markPlayed([...ids, ids.first], true), 1);
      expect(
        (await records.readMany(ids)).values.every((r) => r.watched),
        isTrue,
      );
      expect(flags().length, 3);
      expect(flags().last.uri.path, endsWith('/third'));
    },
  );
  test('batch prevalidates all identities before any local write', () async {
    await expectLater(
      connections.markPlayed([id('film'), id('missing')], true),
      throwsA(isA<SourceFailure>()),
    );
    expect((await records.read(id('film'))).watched, isFalse);
    expect(flags(), isEmpty);
  });
  test('same external ID in another source is isolated', () async {
    final other = await connections.connect(
      server.address,
      'tester',
      'fixture',
    );
    await sync.synchronize(other.id);
    await connections.setFavorite(id('film'), true);
    await connections.markPlayed([id('film')], true);
    final otherId = (sourceId: other.id, localId: 'film');
    expect((await sources.media(otherId)).remote!.favorite, isFalse);
    expect((await records.read(otherId)).watched, isFalse);
  });
  test(
    'subtitle stream matching uses requested media source and text codecs',
    () async {
      final streams = await connections.subtitles(
        await sources.media(id('film')),
      );
      expect(streams.map((s) => s.index), [3, 4]);
      expect(streams.map((s) => s.extension), ['srt', 'vtt']);
      expect(streams.first.displayName, '简体中文');
      expect(EmbySubtitle.parse(detail(), 'film', 'missing').single.index, 9);
    },
  );
  test('fallback subtitle route and auth refresh', () async {
    final item = await sources.media(id('film'));
    final stream = (await connections.subtitles(item)).first;
    server.validToken = 'expired';
    expect(
      utf8.decode(await connections.subtitle(item, stream)),
      contains('字幕'),
    );
    final request = server.requests.last;
    expect(
      request.uri.path,
      '/proxy/emby/Videos/film/resource/Subtitles/3/Stream.srt',
    );
    expect(request.uri.queryParameters['api_key'], 'token-2');
  });
  test(
    'delivery query preserved, old API key replaced, foreign origin refused',
    () async {
      final session = await connections.session(source.id);
      await client.subtitle(
        session,
        const EmbySubtitle(
          itemId: 'film',
          mediaSourceId: 'resource',
          index: 3,
          extension: 'srt',
          deliveryUrl: '/proxy/emby/Videos/film/subtitle.srt?Api_Key=stale&x=1',
        ),
      );
      expect(server.requests.last.uri.queryParameters, {
        'x': '1',
        'api_key': 'token-1',
      });
      final count = server.requests.length;
      expect(
        () => client.subtitle(
          session,
          const EmbySubtitle(
            itemId: 'film',
            mediaSourceId: 'resource',
            index: 3,
            extension: 'srt',
            deliveryUrl: 'http://example.invalid/sub.srt',
          ),
        ),
        throwsA(isA<EmbyFailure>()),
      );
      expect(server.requests.length, count);
    },
  );
  test('oversized chunked subtitle is aborted before full download', () async {
    server.streamHandler = (r) async {
      try {
        for (var n = 0; n < 12; n++) {
          r.response.add(List.filled(1024 * 1024, 65));
          await r.response.flush();
        }
        await r.response.close();
      } on SocketException {
        /* Expected cancellation. */
      } on HttpException {
        /* Expected cancellation. */
      }
    };
    final item = await sources.media(id('film'));
    final stream = (await connections.subtitles(item)).first;
    await expectLater(
      connections.subtitle(item, stream),
      throwsA(
        isA<EmbyFailure>().having((e) => e.kind, 'kind', EmbyError.tooLarge),
      ),
    );
  });
  test('player downloads only chosen subtitle; reuses bytes and removes temp directory', () async {
    final engine = FakeVideoEngine();
    final player = PlaybackSession(
      sources: sources,
      records: records,
      emby: connections,
      createEngine: () => engine,
    );
    try {
      await player.open(id('film'));
      await player.refreshServerSubtitles();
      expect(engine.addedSubtitles, isEmpty);
      await player.selectServerSubtitle('resource:3');
      expect(player.subtitleError, isNull);
      final path = engine.addedSubtitles.single;
      expect(await File(path).readAsString(), contains('字幕'));
      await player.selectServerSubtitle('resource:3');
      expect(
        server.requests.where((r) => r.uri.path.contains('/Subtitles/')).length,
        1,
      );
      await player.close();
      expect(await File(path).parent.exists(), isFalse);
    } finally {
      await player.close(discardProgress: true);
      player.dispose();
    }
  });
  test('subtitle failure does not stop playback and can be retried', () async {
    final engine = FakeVideoEngine();
    final player = PlaybackSession(
      sources: sources,
      records: records,
      emby: connections,
      createEngine: () => engine,
    );
    try {
      await player.open(id('film'));
      await player.refreshServerSubtitles();
      server.streamHandler = (r) async {
        r.response.statusCode = 503;
        await r.response.close();
      };
      await player.selectServerSubtitle('resource:3');
      expect(player.subtitleError, isNotNull);
      expect(player.error, isNull);
      expect(engine.clock.playing, isTrue);
      server.streamHandler = (r) async {
        r.response.write('retry');
        await r.response.close();
      };
      await player.selectServerSubtitle('resource:3');
      expect(player.subtitleError, isNull);
    } finally {
      await player.close(discardProgress: true);
      player.dispose();
    }
  });
  test(
    'closing cancels queued subtitle request; expired task never sends',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      server.artworkHandler = (r) async {
        entered.complete();
        await release.future;
        r.response.add([1]);
        await r.response.close();
      };
      final player = PlaybackSession(
        sources: sources,
        records: records,
        emby: connections,
        createEngine: FakeVideoEngine.new,
      );
      await player.open(id('film'));
      final blocker = connections.artwork(source.id, 'film');
      await entered.future;
      final reading = player.refreshServerSubtitles();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final close = player.close();
      // Subtitle caller must exit before the connection queue's predecessor.
      await reading.timeout(const Duration(milliseconds: 200));
      release.complete();
      await blocker;
      await close;
      expect(
        server.requests.where((r) => r.uri.path.endsWith('/Items/film')),
        isEmpty,
      );
      player.dispose();
    },
  );

  testWidgets(
    'season batch covers every page and leaves other seasons untouched',
    (tester) async {
      await tester.runAsync(() async {
        server.itemPageSize = 300;
        server.catalog['movies'] = [
          {'Id': 'show', 'Name': 'Show', 'Type': 'Series'},
          for (var n = 0; n < 205; n++)
            {
              ...movie('episode-$n'),
              'Type': 'Episode',
              'SeriesId': 'show',
              'SeriesName': 'Show',
              'ParentIndexNumber': 1,
              'IndexNumber': n + 1,
            },
          {
            ...movie('other-season'),
            'Type': 'Episode',
            'SeriesId': 'show',
            'SeriesName': 'Show',
            'ParentIndexNumber': 2,
            'IndexNumber': 1,
          },
        ];
        await connections.selectLibraries(
          source.id,
          all: true,
          selected: [],
          trace: RemoteTraceSyncMode.importOnly,
        );
        await sync.synchronize(source.id);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sources),
            embyConnectionProvider.overrideWithValue(connections),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EmbyBatchWatchedButton(
                series: id('show'),
                oneSeason: true,
                season: 1,
              ),
            ),
          ),
        ),
      );
      for (var n = 0; n < 100; n++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        final button = tester.widget<TextButton>(find.byType(TextButton));
        if (button.onPressed != null) break;
      }
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('标记全已看'));
      for (var n = 0; n < 200 && find.text('标记全未看').evaluate().isEmpty; n++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pump();
      expect(find.text('标记全未看'), findsOneWidget);
      final marked = await records.readMany(
        List.generate(205, (n) => id('episode-$n')),
      );
      expect(marked.values.every((r) => r.watched), isTrue);
      expect((await records.read(id('other-season'))).watched, isFalse);
      expect(flags(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('favorite and watched controls refresh after actions', (
    tester,
  ) async {
    final item = await sources.media(id('film'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          embyConnectionProvider.overrideWithValue(connections),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                EmbyMediaActions(item: item, favoriteOnly: true),
                EmbyMediaActions(item: item),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void> wait(bool Function() condition) async {
      for (var n = 0; n < 200 && !condition(); n++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pump();
      expect(condition(), isTrue);
    }

    await wait(() => find.byTooltip('喜欢').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('喜欢'));
    await wait(() => find.byTooltip('取消喜欢').evaluate().isNotEmpty);
    await tester.tap(find.text('标记为已观看'));
    await wait(() => find.text('清除已观看').evaluate().isNotEmpty);
    await wait(
      () =>
          tester.widget<TextButton>(find.byType(TextButton)).onPressed !=
              null &&
          tester.widget<IconButton>(find.byType(IconButton)).onPressed != null,
    );
    expect((await records.read(id('film'))).watched, isTrue);
    // HttpClient idle connection timers belong to this real HTTP fixture;
    // close it before the widget binding checks for outstanding fake timers.
    client.close();
    await tester.pumpWidget(const SizedBox());
  });
}
