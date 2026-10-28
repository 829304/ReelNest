import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/automatic_scan_interval.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/application/tmdb_batch_providers.dart';
import 'package:reelnest/features/metadata/application/tmdb_video_service.dart';
import 'package:reelnest/features/metadata/application/tmdb_providers.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';
import 'package:reelnest/features/metadata/domain/tmdb_match_tolerance.dart';
import 'package:reelnest/features/metadata/presentation/tmdb_movie_detail_extras.dart';
import 'package:reelnest/features/metadata/presentation/tmdb_movie_search_dialog.dart';
import 'package:reelnest/features/metadata/presentation/tmdb_settings_panel.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/tmdb_fixture.dart';

class _CredentialStore implements CredentialStore {
  String? value = 'fixture-key';
  String language = 'zh-CN';
  TmdbMatchTolerance tolerance = TmdbMatchTolerance.loose;
  AutomaticScanInterval automaticInterval = AutomaticScanInterval.disabled;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<void> write(String next) async => value = next;
}

class _SettingsController extends TmdbSettingsController {
  _SettingsController(this.store);

  final _CredentialStore store;

  TmdbSettings get _value => TmdbSettings(
    language: store.language,
    hasCredential: store.value?.isNotEmpty == true,
    matchTolerance: store.tolerance,
    automaticMatchInterval: store.automaticInterval,
  );

  @override
  Future<TmdbSettings> build() async => _value;

  @override
  Future<void> saveCredential(String value) async {
    final clean = value.trim();
    store.value = clean.isEmpty ? null : clean;
    state = AsyncData(_value);
  }

  @override
  Future<void> setLanguage(String value) async {
    store.language = TmdbSettingsRepository.normalizedLanguage(value);
    state = AsyncData(_value);
  }

  @override
  Future<void> setMatchTolerance(TmdbMatchTolerance value) async {
    store.tolerance = value;
    state = AsyncData(_value);
  }

  @override
  Future<void> setAutomaticMatchInterval(AutomaticScanInterval value) async {
    store.automaticInterval = value;
    state = AsyncData(_value);
  }
}

class _BatchController extends TmdbBatchController {
  bool failStart = false;
  int starts = 0;

  @override
  TmdbBatchState build() => const TmdbBatchState();

  @override
  Future<void> start() async {
    starts++;
    if (failStart) throw const SourceFailure('所有电视剧 / 动漫都已匹配过 TMDB 信息。');
    state = const TmdbBatchState(
      running: true,
      total: 4,
      processed: 1,
      matched: 1,
      message: '正在匹配 1 / 4',
    );
  }

  @override
  void cancel() {
    state = const TmdbBatchState(
      total: 4,
      processed: 1,
      matched: 1,
      cancelled: true,
      message: '匹配已取消。',
    );
  }

  void finish() {
    state = const TmdbBatchState(
      total: 4,
      processed: 4,
      matched: 2,
      lowConfidence: 1,
      failed: 1,
      message: '匹配完成。',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Directory media;
  late Directory library;
  late SourceRepository sources;
  late TmdbSettingsRepository settings;
  late TmdbVideoService service;
  late TmdbFixture fixture;
  late _CredentialStore credentials;
  late _BatchController batch;
  late MediaSource source;
  late MediaIdentity identity;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-tmdb-ui-');
    media = await Directory(p.join(sandbox.path, 'media')).create();
    library = await Directory(p.join(sandbox.path, 'library')).create();
    await File(p.join(media.path, 'Film.2020.mkv')).writeAsString('fixture');
    sources = SourceRepository(
      database: LibraryDatabase(
        NativeDatabase(File(p.join(library.path, 'fixture.sqlite'))),
      ),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Movies',
      location: media.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    identity = (sourceId: source.id, localId: 'Film.2020.mkv');
    credentials = _CredentialStore();
    batch = _BatchController();
    settings = TmdbSettingsRepository(sources.database, store: credentials);
    fixture = await TmdbFixture.start();
    service = TmdbVideoService(
      sources: sources,
      settings: settings,
      client: fixture.client(),
      artwork: TmdbArtworkStore(library: () async => library),
    );
  });

  tearDown(() async {
    await service.dispose();
    await fixture.close();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    await sandbox.delete(recursive: true);
  });

  Widget app(Widget child) => ProviderScope(
    overrides: [
      sourceRepositoryProvider.overrideWithValue(sources),
      tmdbSettingsRepositoryProvider.overrideWithValue(settings),
      tmdbSettingsProvider.overrideWith(() => _SettingsController(credentials)),
      tmdbBatchProvider.overrideWith(() => batch),
      tmdbMovieServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  Widget settingsPanel() =>
      app(const SingleChildScrollView(child: TmdbSettingsPanel()));

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int attempts = 300,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (finder.evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 250));
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    throw TimeoutException('widget did not appear: $finder');
  }

  Future<void> pumpUntilCondition(
    WidgetTester tester,
    bool Function() condition, {
    int attempts = 300,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (condition()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    throw TimeoutException('fixture condition did not complete');
  }

  Future<void> pumpUntilAsyncCondition(
    WidgetTester tester,
    Future<bool> Function() condition, {
    int attempts = 300,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (await tester.runAsync(condition) == true) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    throw TimeoutException('fixture operation did not complete');
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.pumpWidget(
      app(TmdbMovieMatchButton(identity: identity, title: 'Film 2020')),
    );
    await tester.tap(find.byKey(const ValueKey('tmdb-movie-search-entry')));
    await tester.pump();
    await pumpUntil(tester, find.byKey(const ValueKey('tmdb-candidate-1')));
  }

  testWidgets(
    'settings never reveal the saved credential and require explicit clear',
    (tester) async {
      await tester.pumpWidget(settingsPanel());
      await tester.pump();
      await pumpUntil(
        tester,
        find.byKey(const ValueKey('tmdb-credential-input')),
      );

      expect(find.textContaining('已配置'), findsWidgets);
      expect(find.text('fixture-key'), findsNothing);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('tmdb-credential-input')),
      );
      expect(field.obscureText, isTrue);

      await tester.tap(find.byKey(const ValueKey('save-tmdb-credential')));
      await tester.pumpAndSettle();
      expect(find.text('请输入新的 API Key 或 Read Access Token。'), findsOneWidget);
      expect(credentials.value, 'fixture-key');

      await tester.enterText(
        find.byKey(const ValueKey('tmdb-credential-input')),
        'replacement-token',
      );
      await tester.tap(find.byKey(const ValueKey('save-tmdb-credential')));
      await tester.pumpAndSettle();
      expect(credentials.value, 'replacement-token');
      expect(find.text('replacement-token'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('clear-tmdb-credential')));
      await tester.pumpAndSettle();
      expect(credentials.value, isNull);
      expect(find.text('TMDB 凭据已清除。'), findsOneWidget);
    },
  );

  testWidgets('language blank falls back to zh-CN', (tester) async {
    await tester.pumpWidget(settingsPanel());
    await tester.pump();
    await pumpUntil(tester, find.byKey(const ValueKey('tmdb-language-input')));
    await tester.enterText(
      find.byKey(const ValueKey('tmdb-language-input')),
      ' ',
    );
    await tester.tap(find.byKey(const ValueKey('save-tmdb-language')));
    await tester.pumpAndSettle();
    expect(credentials.language, 'zh-CN');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tmdb-language-input')))
          .controller!
          .text,
      'zh-CN',
    );
  });

  testWidgets(
    'settings save match tolerance and explain low-confidence review',
    (tester) async {
      await tester.pumpWidget(settingsPanel());
      await tester.pump();
      await pumpUntil(
        tester,
        find.byKey(const ValueKey('tmdb-match-tolerance')),
      );

      expect(find.text('宽松'), findsOneWidget);
      expect(find.textContaining('置信度偏低的结果会跳过'), findsOneWidget);
      expect(find.text('自动拉取周期'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('tmdb-match-tolerance')),
      );
      await tester.tap(find.byKey(const ValueKey('tmdb-match-tolerance')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('严格').last);
      await tester.pumpAndSettle();

      expect(credentials.tolerance, TmdbMatchTolerance.strict);
      expect(find.text('严格'), findsOneWidget);
      expect(find.textContaining('仅高置信度才自动套用'), findsOneWidget);
    },
  );

  testWidgets(
    'automatic match interval keeps all original choices without credentials',
    (tester) async {
      credentials.value = null;
      await tester.pumpWidget(settingsPanel());
      await tester.pump();
      await pumpUntil(
        tester,
        find.byKey(const ValueKey('tmdb-automatic-match-interval')),
      );

      final start = tester.widget<FilledButton>(
        find.byKey(const ValueKey('start-tmdb-batch')),
      );
      expect(start.onPressed, isNull);
      expect(find.text('关闭'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('tmdb-automatic-match-interval')),
      );
      await tester.tap(
        find.byKey(const ValueKey('tmdb-automatic-match-interval')),
      );
      await tester.pumpAndSettle();
      for (final interval in AutomaticScanInterval.values) {
        expect(find.text(interval.displayName), findsWidgets);
      }
      await tester.tap(find.text('每 6 小时').last);
      await tester.pumpAndSettle();

      expect(credentials.automaticInterval, AutomaticScanInterval.sixHours);
      expect(find.text('每 6 小时'), findsOneWidget);
      expect(find.text('独立于媒体库文件自动扫描'), findsOneWidget);
    },
  );

  testWidgets('batch match exposes progress, result counts and cancellation', (
    tester,
  ) async {
    await tester.pumpWidget(settingsPanel());
    await tester.pump();
    await pumpUntil(tester, find.byKey(const ValueKey('start-tmdb-batch')));

    await tester.ensureVisible(find.byKey(const ValueKey('start-tmdb-batch')));
    await tester.tap(find.byKey(const ValueKey('start-tmdb-batch')));
    await tester.pump();

    expect(batch.starts, 1);
    expect(find.byKey(const ValueKey('cancel-tmdb-batch')), findsOneWidget);
    expect(find.byKey(const ValueKey('tmdb-batch-progress')), findsOneWidget);
    expect(find.text('已处理 1'), findsOneWidget);
    expect(find.text('已匹配 1'), findsOneWidget);

    batch.finish();
    await tester.pump();
    expect(find.text('匹配完成。'), findsOneWidget);
    expect(find.text('低置信跳过 1'), findsOneWidget);
    expect(find.text('失败 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('start-tmdb-batch')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cancel-tmdb-batch')));
    await tester.pump();
    expect(find.text('匹配已取消。'), findsOneWidget);
  });

  testWidgets(
    'batch start failure is shown without inventing confirmation UI',
    (tester) async {
      batch.failStart = true;
      await tester.pumpWidget(settingsPanel());
      await tester.pump();
      await pumpUntil(tester, find.byKey(const ValueKey('start-tmdb-batch')));

      await tester.ensureVisible(
        find.byKey(const ValueKey('start-tmdb-batch')),
      );
      await tester.tap(find.byKey(const ValueKey('start-tmdb-batch')));
      await tester.pump();
      expect(find.text('所有电视剧 / 动漫都已匹配过 TMDB 信息。'), findsOneWidget);
      expect(find.textContaining('候选确认'), findsNothing);
    },
  );

  testWidgets(
    'dialog auto searches title and renders original candidate fields',
    (tester) async {
      await openSearch(tester);
      expect(
        find.byKey(const ValueKey('tmdb-movie-search-dialog')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tmdb-search-input')))
            .controller!
            .text,
        'Film 2020',
      );
      expect(find.byKey(const ValueKey('tmdb-candidate-1')), findsOneWidget);
      expect(find.text('电影 1'), findsOneWidget);
      expect(find.text('2020-03-04'), findsWidgets);
      expect(find.text('Film 1'), findsNothing);
      expect(find.text('TMDB[zh-CN]'), findsWidgets);
      expect(find.text('2020'), findsWidgets);
      expect(find.text('8.2'), findsWidgets);
    },
  );

  testWidgets('closing a pending search cancels it without stale UI updates', (
    tester,
  ) async {
    final started = Completer<void>();
    final release = Completer<void>();
    fixture.intercept = (request) async {
      if (!started.isCompleted) started.complete();
      await release.future;
      await fixture.json(request, {'results': <Object>[]});
    };
    await tester.pumpWidget(
      app(TmdbMovieMatchButton(identity: identity, title: 'Film 2020')),
    );
    await tester.tap(find.byKey(const ValueKey('tmdb-movie-search-entry')));
    await tester.pump();
    await pumpUntilCondition(tester, () => started.isCompleted);
    await tester.tap(find.byKey(const ValueKey('close-tmdb-search')));
    await tester.pump();
    release.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tmdb-movie-search-dialog')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('apply cannot be closed or repeated while the write is pending', (
    tester,
  ) async {
    await openSearch(tester);
    final release = Completer<void>();
    fixture.detailGate = release.future;
    await tester.tap(find.byKey(const ValueKey('apply-tmdb-candidate-1')));
    await tester.pump();
    await pumpUntilCondition(tester, () => fixture.detailStarted.isCompleted);

    expect(find.text('应用中…'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('close-tmdb-search')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.descendant(
              of: find.byKey(const ValueKey('apply-tmdb-candidate-2')),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('tmdb-movie-search-dialog')),
      findsOneWidget,
    );

    release.complete();
    await pumpUntilAsyncCondition(
      tester,
      () async => (await sources.media(identity)).title == '完整电影 1',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tmdb-movie-search-dialog')),
      findsNothing,
    );
    expect(find.text('TMDB 电影资料已应用。'), findsOneWidget);
    expect((await sources.media(identity)).title, '完整电影 1');
  });

  testWidgets('apply failure remains visible and preserves the existing item', (
    tester,
  ) async {
    final before = await tester.runAsync(() => sources.media(identity));
    await openSearch(tester);
    await tester.runAsync(() => settings.saveCredential(''));
    await tester.tap(find.byKey(const ValueKey('apply-tmdb-candidate-1')));
    await tester.pump();
    await pumpUntil(tester, find.textContaining('请先在设置中填写 TMDB'));
    expect(
      find.byKey(const ValueKey('tmdb-movie-search-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('请先在设置中填写 TMDB'), findsOneWidget);
    expect(
      (await tester.runAsync(() => sources.media(identity)))!.title,
      before!.title,
    );
  });

  testWidgets(
    'local movie detail owns the entry and shows saved cast and crew',
    (tester) async {
      await tester.runAsync(() async {
        final selected = (await service.search('Film')).first;
        await service.apply(identity, selected);
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1088, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(app(LocalMediaDetailPage(identity: identity)));
      await tester.pump();
      await pumpUntil(
        tester,
        find.byKey(const ValueKey('tmdb-movie-search-entry')),
      );

      expect(
        find.byKey(const ValueKey('tmdb-movie-search-entry')),
        findsOneWidget,
      );
      expect(find.text('完整电影 1'), findsWidgets);
      expect(find.text('125 分钟'), findsOneWidget);
      expect(find.text('动作'), findsWidgets);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tmdb-movie-detail-extras')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('tmdb-person-3-导演')), findsOneWidget);
      expect(find.text('甲'), findsOneWidget);
      expect(find.text('主角'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toggle-tmdb-details')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('甲'), findsNothing);
      sources.traceChanged(sourceIds: [source.id]);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('tmdb-movie-detail-extras')),
        findsOneWidget,
      );
      expect(find.text('甲'), findsNothing);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('甲'), findsNothing);
    },
  );

  testWidgets('non-movie local detail does not expose TMDB matching', (
    tester,
  ) async {
    await tester.runAsync(
      () => sources.database.customStatement(
        "UPDATE media SET type='episode',season_number=1,episode_number=1 "
        'WHERE source_id=? AND local_id=?',
        [identity.sourceId, identity.localId],
      ),
    );
    await tester.pumpWidget(app(LocalMediaDetailPage(identity: identity)));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tmdb-movie-search-entry')), findsNothing);
  });

  testWidgets('people cards use a quiet fallback when profile loading fails', (
    tester,
  ) async {
    const metadata = TmdbMetadata(
      candidate: TmdbCandidate(id: 7, title: '电影'),
      crew: [
        TmdbPerson(
          id: 1,
          name: '无头像导演',
          role: '导演',
          profileUrl: 'http://127.0.0.1:1/missing.png',
        ),
      ],
      cast: [TmdbPerson(id: 2, name: '无头像演员', role: '主演')],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TmdbMovieDetailExtras(metadata: metadata)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无头像导演'), findsOneWidget);
    expect(find.text('无头像演员'), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('toggle-tmdb-details')));
    await tester.pumpAndSettle();
    expect(find.text('无头像导演'), findsNothing);
  });
}
