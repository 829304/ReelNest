import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/online_subtitle_providers.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/online_subtitle_payload.dart';
import 'package:reelnest/features/playback/data/online_subtitle_service.dart';
import 'package:reelnest/features/playback/data/online_subtitle_settings_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/online_subtitle.dart'
    as online;
import 'package:reelnest/features/playback/presentation/player_track_popovers.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/settings/presentation/online_subtitle_settings.dart'
    as settings_ui;
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _MemoryCredentialStore implements CredentialStore {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class _FakeSettingsRepository extends OnlineSubtitleSettingsRepository {
  _FakeSettingsRepository(super.preferences)
    : super(store: _MemoryCredentialStore());

  online.OnlineSubtitleSettings value = const online.OnlineSubtitleSettings(
    language: 'zh-CN',
    apiKey: 'initial-key',
  );
  int saves = 0;
  bool failRead = false;
  bool failSave = false;
  bool holdSave = false;
  final requests = <online.OnlineSubtitleSettings>[];
  final pendingSaves = <Completer<void>>[];
  Future<void> _writes = Future.value();

  @override
  Future<online.OnlineSubtitleSettings> read() => failRead
      ? Future.error(StateError('secret raw settings read failure'))
      : Future.value(value);

  @override
  Future<void> save({required String language, required String apiKey}) {
    saves++;
    final next = online.OnlineSubtitleSettings(
      language: language,
      apiKey: apiKey,
    );
    requests.add(next);
    if (failSave) {
      return Future.error(StateError('secret raw settings failure'));
    }
    final gate = holdSave ? Completer<void>() : null;
    if (gate != null) pendingSaves.add(gate);
    final result = _writes.then((_) async {
      if (gate != null) await gate.future;
      value = next;
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

class _FakeOnlineSubtitleService extends OnlineSubtitleService {
  List<online.OnlineSubtitleResult> results = [
    for (var index = 0; index < 24; index++)
      online.OnlineSubtitleResult(
        id: 'r$index',
        provider: index.isEven
            ? online.OnlineSubtitleProvider.podnapisi
            : online.OnlineSubtitleProvider.openSubtitles,
        fileId: index + 1,
        displayName: 'Film.zh.$index.srt',
        language: index.isEven ? 'zh-CN' : 'zh-TW',
        downloads: index * 10,
      ),
  ];
  List<String> warnings = const [];
  int searches = 0;
  int downloads = 0;
  bool holdSearch = false;
  bool cancelled = false;

  @override
  Future<online.OnlineSubtitleSearch> search(
    online.OnlineSubtitleQuery query,
    online.OnlineSubtitleSettings settings,
    ScanCancellation cancellation,
  ) {
    searches++;
    if (!holdSearch) {
      return Future.value(online.OnlineSubtitleSearch(results, warnings));
    }
    final pending = Completer<online.OnlineSubtitleSearch>();
    final unlisten = cancellation.listen(() {
      cancelled = true;
      if (!pending.isCompleted) pending.completeError(const ScanCancelled());
    });
    return pending.future.whenComplete(unlisten);
  }

  @override
  Future<OnlineSubtitlePayload> download(
    online.OnlineSubtitleResult result,
    online.OnlineSubtitleSettings settings,
    ScanCancellation token,
  ) async {
    downloads++;
    token.check();
    return OnlineSubtitlePayload(
      Uint8List.fromList(utf8.encode('1\n00:00:01,000 --> 00:00:03,000\n字幕\n')),
      'srt',
    );
  }
}

void main() {
  testWidgets(
    'settings save only on focus completion and expose safe failures',
    (tester) async {
      final database = LibraryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = _FakeSettingsRepository(
        PlayerPreferencesRepository(database),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
              repository,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 760,
                  child: settings_ui.OnlineSubtitleSettings(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final language = find.byKey(const ValueKey('online-subtitle-language'));
      final apiKey = find.byKey(const ValueKey('online-subtitle-api-key'));
      expect(tester.widget<TextField>(language).controller?.text, 'zh-CN');
      expect(tester.widget<TextField>(apiKey).obscureText, isTrue);

      await tester.enterText(language, 'en');
      await tester.pump();
      expect(repository.saves, 0);
      await tester.tap(apiKey);
      await tester.pumpAndSettle();
      expect(repository.saves, 1);
      expect(repository.value.language, 'en');

      await tester.enterText(apiKey, 'new-key');
      expect(repository.saves, 1);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repository.saves, 2);
      expect(repository.value.apiKey, 'new-key');

      repository.failSave = true;
      await tester.enterText(language, 'ja');
      await tester.tap(apiKey);
      await tester.pumpAndSettle();
      expect(repository.saves, 3);
      expect(
        find.byKey(const ValueKey('online-subtitle-settings-error')),
        findsOneWidget,
      );
      expect(find.textContaining('secret raw'), findsNothing);
      expect(find.text('在线字幕设置保存失败，请重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings persist the latest focused draft when leaving', (
    tester,
  ) async {
    final database = LibraryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _FakeSettingsRepository(
      PlayerPreferencesRepository(database),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: settings_ui.OnlineSubtitleSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final language = find.byKey(const ValueKey('online-subtitle-language'));
    final apiKey = find.byKey(const ValueKey('online-subtitle-api-key'));
    await tester.enterText(language, ' fr ');
    tester.widget<TextField>(apiKey).controller!.text = ' depart-key ';
    await tester.pump();
    expect(repository.saves, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repository.saves, 1);
    expect(repository.value.language, 'fr');
    expect(repository.value.apiKey, 'depart-key');
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving does not duplicate the same in-flight draft', (
    tester,
  ) async {
    final database = LibraryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _FakeSettingsRepository(
      PlayerPreferencesRepository(database),
    )..holdSave = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: settings_ui.OnlineSubtitleSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final language = find.byKey(const ValueKey('online-subtitle-language'));
    await tester.enterText(language, 'ko');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(repository.saves, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repository.saves, 1);
    repository.pendingSaves.single.complete();
    await tester.pump();
    expect(repository.value.language, 'ko');
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving queues a return to the saved value after a newer save', (
    tester,
  ) async {
    final database = LibraryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _FakeSettingsRepository(
      PlayerPreferencesRepository(database),
    )..holdSave = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: settings_ui.OnlineSubtitleSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final language = find.byKey(const ValueKey('online-subtitle-language'));
    await tester.enterText(language, 'en');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(repository.saves, 1);

    await tester.enterText(language, 'zh-CN');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repository.saves, 2);
    expect(repository.requests.map((value) => value.language), ['en', 'zh-CN']);

    repository.pendingSaves[0].complete();
    await tester.pump();
    expect(repository.value.language, 'en');
    repository.pendingSaves[1].complete();
    await tester.pump();
    expect(repository.value.language, 'zh-CN');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed initial read does not persist an untouched default', (
    tester,
  ) async {
    final database = LibraryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _FakeSettingsRepository(
      PlayerPreferencesRepository(database),
    )..failRead = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineSubtitleSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: settings_ui.OnlineSubtitleSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('online-subtitle-settings-error')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repository.saves, 0);
    expect(repository.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  group('player online subtitle popover', () {
    late Directory sandbox;
    late SourceRepository sources;
    late PlayerPreferencesRepository preferences;
    late PlaybackSession session;
    late _FakeOnlineSubtitleService service;
    late MediaIdentity film;
    late MediaIdentity secondFilm;
    var closed = false;

    setUp(() async {
      closed = false;
      sandbox = await Directory.systemTemp.createTemp(
        'reelnest-online-subtitle-ui-',
      );
      await File(p.join(sandbox.path, 'Film.mkv')).writeAsString('video');
      await File(p.join(sandbox.path, 'Second.mkv')).writeAsString('video');
      sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture-volume',
      );
      final source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Test',
        location: sandbox.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      film = (sourceId: source.id, localId: 'Film.mkv');
      secondFilm = (sourceId: source.id, localId: 'Second.mkv');
      preferences = PlayerPreferencesRepository(sources.database);
      final credentials = _MemoryCredentialStore()..value = 'configured-key';
      service = _FakeOnlineSubtitleService();
      session = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        preferences: preferences,
        onlineSubtitleService: service,
        onlineSubtitleSettings: OnlineSubtitleSettingsRepository(
          preferences,
          store: credentials,
        ),
        createEngine: FakeVideoEngine.new,
      );
    });

    tearDown(() async {
      if (!closed) {
        await session.close();
        session.dispose();
        await sources.close();
      }
      expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
      expect(
        p.basename(sandbox.path),
        startsWith('reelnest-online-subtitle-ui-'),
      );
      await sandbox.delete(recursive: true);
    });

    testWidgets(
      'auto searches, caps results, downloads, reloads and cancels on close',
      (tester) async {
        Future<void> finish(Future<void> future) async {
          var done = false;
          Object? failure;
          future.then(
            (_) => done = true,
            onError: (Object error) {
              failure = error;
              done = true;
            },
          );
          for (var n = 0; n < 200 && !done; n++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump();
          }
          expect(done, isTrue);
          if (failure != null) throw failure!;
        }

        await finish(session.open(film));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  child: PlayerTrackPopover(
                    panel: PlayerPanel.subtitles,
                    session: session,
                    palette: const PlayerPalette(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        for (var n = 0; n < 30 && session.searchingOnlineSubtitles; n++) {
          await tester.pump(const Duration(milliseconds: 5));
        }
        expect(service.searches, 1);
        expect(find.text('· Podnapisi · OpenSubtitles'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('online-subtitle-r19')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('online-subtitle-r20')), findsNothing);

        final first = find.byKey(const ValueKey('online-subtitle-r0'));
        await tester.ensureVisible(first);
        await tester.tap(first);
        for (
          var n = 0;
          n < 100 && session.downloadingOnlineSubtitleID != null;
          n++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(service.downloads, 1);
        expect(session.downloadedOnlineSubtitlePaths['r0'], isNotNull);
        expect(
          await tester.runAsync(
            () => File(session.downloadedOnlineSubtitlePaths['r0']!).exists(),
          ),
          isTrue,
        );

        await tester.ensureVisible(first);
        await tester.tap(first);
        await tester.pump();
        for (
          var n = 0;
          n < 100 && session.downloadingOnlineSubtitleID != null;
          n++
        ) {
          await tester.pump(const Duration(milliseconds: 5));
        }
        expect(service.downloads, 1);

        service.results = const [
          online.OnlineSubtitleResult(
            id: 'second-film',
            provider: online.OnlineSubtitleProvider.podnapisi,
            fileId: 100,
            displayName: 'Second.zh.srt',
            language: 'zh-CN',
          ),
        ];
        await finish(session.open(secondFilm));
        await tester.pump();
        for (var n = 0; n < 30 && session.searchingOnlineSubtitles; n++) {
          await tester.pump(const Duration(milliseconds: 5));
        }
        expect(service.searches, 2);
        expect(
          find.byKey(const ValueKey('online-subtitle-second-film')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('online-subtitle-r0')), findsNothing);

        service.results = const [];
        final refresh = find.byKey(const ValueKey('online-subtitle-refresh'));
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('online-subtitle-empty')),
          findsOneWidget,
        );

        service.holdSearch = true;
        await tester.tap(refresh);
        await tester.pump();
        expect(session.searchingOnlineSubtitles, isTrue);
        expect(
          find.byKey(const ValueKey('online-subtitle-searching')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(service.cancelled, isTrue);

        await finish(session.close());
        session.dispose();
        await finish(sources.close());
        closed = true;
        expect(tester.takeException(), isNull);
      },
    );
  });
}
