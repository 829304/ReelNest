import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/external_playback_providers.dart';
import 'package:reelnest/features/playback/application/external_playback_service.dart';
import 'package:reelnest/features/playback/application/marker_analysis_providers.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/external_player_settings_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/external_player_settings.dart';
import 'package:reelnest/features/playback/domain/transient_playback_target.dart';
import 'package:reelnest/features/playback/presentation/player_precision_controls.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/settings/presentation/external_player_settings_panel.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/external_playback_actions.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _Launcher implements ExternalPlaybackLauncher {
  MediaIdentity? library;
  TransientPlaybackTarget? transient;

  @override
  Future<void> openLibrary(MediaIdentity identity) async => library = identity;

  @override
  Future<void> openTransient(TransientPlaybackTarget target) async =>
      transient = target;
}

class _FailureSession extends PlaybackSession {
  _FailureSession(SourceRepository sources)
    : super(
        sources: sources,
        records: PlaybackRepository(sources.database),
        createEngine: FakeVideoEngine.new,
      );

  @override
  Future<void> open(MediaIdentity identity) async {
    item = _video(identity.localId);
    loading = false;
    error = '测试播放失败';
    notifyListeners();
  }
}

IndexedMedia _video([String localId = 'Film.mkv']) => IndexedMedia(
  identity: (sourceId: 'local', localId: localId),
  title: 'Film',
  type: 'movie',
  bytes: 1,
  modified: DateTime(2026),
);

void main() {
  late SourceRepository sources;

  setUp(() {
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
  });

  tearDown(() => sources.close());

  Widget settingsHost() => ProviderScope(
    overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ExternalPlayerSettingsPanel()),
      ),
    ),
  );

  testWidgets('settings switches between built-in and system player', (
    tester,
  ) async {
    await tester.pumpWidget(settingsHost());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('external-player-application-row')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('external-player-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('external-player-application-row')),
      findsOneWidget,
    );
    expect(
      (await ExternalPlayerSettingsRepository(sources.database).load()).mode,
      ExternalPlayerMode.external,
    );
  });

  testWidgets('settings can return a chosen application to system default', (
    tester,
  ) async {
    await ExternalPlayerSettingsRepository(sources.database).save(
      const ExternalPlayerSettings(
        mode: ExternalPlayerMode.external,
        applicationPath: r'C:\Players\VLC\vlc.exe',
      ),
    );
    await tester.pumpWidget(settingsHost());
    await tester.pumpAndSettle();
    expect(find.text(r'C:\Players\VLC\vlc.exe'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('use-system-video-player')));
    await tester.pumpAndSettle();

    expect(find.text('系统默认'), findsWidgets);
    expect(
      (await ExternalPlayerSettingsRepository(
        sources.database,
      ).load()).applicationPath,
      isNull,
    );
  });

  testWidgets('damaged settings can be explicitly reset to built-in mode', (
    tester,
  ) async {
    await sources.database.customStatement(
      'INSERT INTO player_preferences(key,value) VALUES(?,?)',
      [ExternalPlayerSettingsRepository.key, '{invalid-json'],
    );
    await tester.pumpWidget(settingsHost());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('重置播放器设置'), findsOneWidget);

    await tester.tap(find.text('重置播放器设置'));
    await tester.pumpAndSettle();

    final restored = await ExternalPlayerSettingsRepository(sources.database)
        .load();
    expect(restored.mode, ExternalPlayerMode.builtIn);
    expect(restored.applicationPath, isNull);
    expect(find.text('内置'), findsOneWidget);
  });

  testWidgets('detail action explicitly opens the selected library item', (
    tester,
  ) async {
    final launcher = _Launcher();
    final item = _video();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          externalPlaybackServiceProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          home: Scaffold(body: ExternalPlaybackButton(item: item)),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('open-library-item-externally')),
    );
    await tester.pumpAndSettle();

    expect(launcher.library, item.identity);
  });

  testWidgets(
    'local context menu keeps external playback as an explicit action',
    (tester) async {
      final launcher = _Launcher();
      final item = _video('Episode.mkv');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            externalPlaybackServiceProvider.overrideWithValue(launcher),
            markerAnalysisEligibilityProvider.overrideWith(
              (ref, id) async => false,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LocalVideoContextMenu(
                item: item,
                child: const SizedBox(
                  key: ValueKey('local-context-target'),
                  width: 180,
                  height: 80,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('local-context-target'))),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('外部打开'));
      await tester.pumpAndSettle();

      expect(launcher.library, item.identity);
    },
  );

  testWidgets('player menu opens externally without changing its session', (
    tester,
  ) async {
    final session = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      createEngine: FakeVideoEngine.new,
    );
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlayerPrecisionMenu(
              context,
              position: const Offset(20, 20),
              session: session,
              palette: const PlayerPalette(lightContent: true),
              onNotice: (_) {},
              onOpenPlaybackInfo: () {},
              onOpenExternal: () async => opens++,
            ),
            child: const Text('menu'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-with-system-player')));
    await tester.pumpAndSettle();

    expect(opens, 1);
    expect(find.byKey(const ValueKey('player-precision-menu')), findsNothing);
    session.dispose();
  });

  testWidgets('built-in playback failure offers the original external action', (
    tester,
  ) async {
    final session = _FailureSession(sources);
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          identity: const (sourceId: 'local', localId: 'Film.mkv'),
          session: session,
          closeWindow: () async {},
          setFullscreen: (_) async {},
          openExternal: () async => opens++,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('内置播放器无法播放'), findsOneWidget);
    expect(find.text('用外部播放器打开'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('open-error-with-system-player')),
    );
    await tester.pump();

    expect(opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
