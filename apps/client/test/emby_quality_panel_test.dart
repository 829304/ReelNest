import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_quality.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/presentation/player_track_popovers.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _QualitySession extends PlaybackSession {
  _QualitySession(SourceRepository sources)
    : super(
        sources: sources,
        records: PlaybackRepository(sources.database),
        createEngine: FakeVideoEngine.new,
      );
  @override
  List<EmbyVideoQuality> get qualityOptions => const [
    EmbyVideoQuality.source,
    EmbyVideoQuality(
      id: '1080-5800000',
      label: '高清 1080P',
      detail: '1920x1080 · 5.8 Mbps',
      width: 1920,
      height: 1080,
      bitrate: 5800000,
    ),
  ];
  @override
  Future<void> selectQuality(EmbyVideoQuality value) async {
    quality = value;
    notifyListeners();
  }
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'quality popover source dimensions and selection $platform $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(1088, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final sources = SourceRepository(
            database: LibraryDatabase(NativeDatabase.memory()),
            adapters: {},
          );
          final session = _QualitySession(sources);
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(platform: platform, brightness: brightness),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showPlayerPanel(
                        context,
                        anchor: const Rect.fromLTWH(500, 600, 58, 28),
                        panel: PlayerPanel.quality,
                        session: session,
                        palette: PlayerPalette(
                          lightContent: brightness == Brightness.dark,
                        ),
                      ),
                      child: const Text('画质'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('画质'));
            await tester.pumpAndSettle();
            expect(find.text('清晰度'), findsOneWidget);
            expect(find.text('根据片源能力切换播放质量'), findsOneWidget);
            expect(tester.getSize(find.byType(PlayerTrackPopover)).width, 300);
            expect(find.text('1920x1080 · 5.8 Mbps'), findsOneWidget);
            await tester.tap(find.byKey(const ValueKey('1080-5800000')));
            await tester.pumpAndSettle();
            expect(session.quality.id, '1080-5800000');
            expect(find.byType(PlayerTrackPopover), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            session.dispose();
            await tester.runAsync(sources.close);
          }
        },
      );
    }
  }
}
