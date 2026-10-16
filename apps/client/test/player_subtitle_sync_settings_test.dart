import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_subtitle_settings.dart';
import 'package:reelnest/features/playback/presentation/player_behavior_settings.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _SettingsSession extends PlaybackSession {
  _SettingsSession(
    SourceRepository sources, {
    required Future<List<String>> Function() fonts,
  }) : super(
         sources: sources,
         records: PlaybackRepository(sources.database),
         createEngine: FakeVideoEngine.new,
         subtitleFonts: fonts,
       );

  Future<void> _styleOperations = Future.value();

  @override
  Future<void> updateSubtitleStyle(
    VideoSubtitleStyle Function(VideoSubtitleStyle current) update,
  ) {
    final operation = _styleOperations.then((_) async {
      await Future<void>.delayed(Duration.zero);
      subtitleStyle = update(subtitleStyle).normalized;
      controlError = null;
      notifyListeners();
    });
    _styleOperations = operation;
    return operation;
  }

  @override
  Future<void> audioDelay(double value) async {
    timing = timing.copyWith(audioDelay: value);
    controlError = null;
    notifyListeners();
  }

  @override
  Future<void> subtitleDelay(double value) async {
    timing = timing.copyWith(subtitleDelay: value);
    controlError = null;
    notifyListeners();
  }

  @override
  Future<void> subtitleScale(double value) async {
    timing = timing.copyWith(subtitleScale: value);
    controlError = null;
    notifyListeners();
  }

  @override
  Future<void> subtitlePosition(double value) async {
    timing = timing.copyWith(subtitlePosition: value);
    controlError = null;
    notifyListeners();
  }
}

Future<void> _showSettings(WidgetTester tester, PlaybackSession session) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPlayerBehaviorSettings(
            context,
            session,
            const PlayerPalette(),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sync and subtitle tabs apply the original controls live', (
    tester,
  ) async {
    var fontLoads = 0;
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    final session = _SettingsSession(
      sources,
      fonts: () async {
        fontLoads++;
        return const ['Arial', 'PingFang SC'];
      },
    );
    session.subtitleStyle = const VideoSubtitleStyle(
      fontName: 'Unavailable Saved Font',
    );
    try {
      await _showSettings(tester, session);
      expect(find.text('播放器更多设置'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-settings-tab-playback')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('player-settings-tab-sync')));
      await tester.pump();
      expect(find.text('音频延迟'), findsOneWidget);
      expect(find.text('字幕延迟'), findsOneWidget);
      expect(find.text('字幕大小'), findsOneWidget);
      expect(find.text('字幕位置'), findsOneWidget);

      await tester.tap(const ValueKey('audio-delay-increase').finder);
      await tester.pump();
      expect(session.timing.audioDelay, .1);
      expect(find.text('+0.1 秒'), findsOneWidget);
      await tester.tap(const ValueKey('subtitle-delay-decrease').finder);
      await tester.tap(const ValueKey('subtitle-scale-decrease').finder);
      await tester.tap(const ValueKey('subtitle-position-decrease').finder);
      await tester.pump();
      expect(session.timing.subtitleDelay, -.1);
      expect(session.timing.subtitleScale, .95);
      expect(session.timing.subtitlePosition, 96);
      await tester.tap(const ValueKey('audio-delay-reset').finder);
      await tester.pump();
      expect(session.timing.audioDelay, 0);

      await tester.tap(
        find.byKey(const ValueKey('player-settings-tab-subtitles')),
      );
      await tester.pumpAndSettle();
      expect(fontLoads, 1);
      expect(find.text('字幕样式'), findsOneWidget);
      expect(find.text('Unavailable Saved Font'), findsOneWidget);
      expect(session.subtitleStyle.fontName, 'Unavailable Saved Font');
      expect(
        find.byKey(const ValueKey('subtitle-color-orange')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('subtitle-bold-toggle')));
      await tester.tap(find.byKey(const ValueKey('subtitle-color-orange')));
      await tester.tap(find.byKey(const ValueKey('subtitle-border-increase')));
      await tester.tap(find.byKey(const ValueKey('subtitle-border-increase')));
      await tester.tap(find.byKey(const ValueKey('subtitle-background-45')));
      await tester.pumpAndSettle();
      expect(session.subtitleStyle.bold, isTrue);
      expect(
        session.subtitleStyle.colorPreset,
        VideoSubtitleColorPreset.orange,
      );
      expect(session.subtitleStyle.borderSize, 4);
      expect(session.subtitleStyle.backgroundOpacity, .45);

      await tester.tap(find.byKey(const ValueKey('subtitle-font-menu')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Arial'));
      await tester.pumpAndSettle();
      expect(session.subtitleStyle.fontName, 'Arial');

      await tester.tap(
        find.byKey(const ValueKey('player-settings-tab-playback')),
      );
      await tester.tap(
        find.byKey(const ValueKey('player-settings-tab-subtitles')),
      );
      await tester.pumpAndSettle();
      expect(fontLoads, 1, reason: '字体 Future 应在弹窗生命周期内复用。');

      await tester.tap(find.byKey(const ValueKey('subtitle-font-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('默认').last);
      await tester.pumpAndSettle();
      expect(session.subtitleStyle.fontName, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await sources.close();
    }
  });

  testWidgets('font enumeration failure is explicit and retryable', (
    tester,
  ) async {
    var fontLoads = 0;
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    final session = _SettingsSession(
      sources,
      fonts: () async {
        fontLoads++;
        if (fontLoads == 1) throw StateError('font service unavailable');
        return const ['Arial'];
      },
    );
    try {
      await _showSettings(tester, session);
      await tester.tap(
        find.byKey(const ValueKey('player-settings-tab-subtitles')),
      );
      await tester.pumpAndSettle();
      expect(find.text('字体列表不可用'), findsOneWidget);
      expect(find.byKey(const ValueKey('subtitle-font-retry')), findsOneWidget);
      expect(find.text('Arial'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('subtitle-font-retry')));
      await tester.pumpAndSettle();
      expect(fontLoads, 2);
      await tester.tap(find.byKey(const ValueKey('subtitle-font-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Arial'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await sources.close();
    }
  });
}

extension on Key {
  Finder get finder => find.byKey(this);
}
