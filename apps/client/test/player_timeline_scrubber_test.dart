import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/domain/video_frame_preview.dart';
import 'package:reelnest/features/playback/domain/video_scrubber_preview_mode.dart';
import 'package:reelnest/features/playback/presentation/player_timeline_scrubber.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';

void main() {
  Widget subject({
    required VideoScrubberPreviewMode mode,
    ScrubberPreviewLoader? loader,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: SliderTheme(
            data: const SliderThemeData(trackHeight: 6),
            child: PlayerTimelineScrubber(
              duration: const Duration(minutes: 2),
              position: 30000,
              enabled: true,
              mode: mode,
              palette: const PlayerPalette(),
              previewLoader: loader,
              onChangeStart: (_) {},
              onChanged: (_) {},
              onChangeEnd: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  Future<TestGesture> hover(WidgetTester tester, Offset position) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: position);
    await tester.pump();
    await gesture.moveTo(position);
    await tester.pump();
    return gesture;
  }

  testWidgets('off mode keeps the original time-only hover preview', (
    tester,
  ) async {
    await tester.pumpWidget(subject(mode: VideoScrubberPreviewMode.off));
    final slider = find.byKey(const ValueKey('video-timeline'));
    final gesture = await hover(tester, tester.getCenter(slider));
    await tester.pump(const Duration(milliseconds: 120));

    final preview = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('player-timeline-preview')),
    );
    expect(preview.opacity, 1);
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('暂无预览'), findsNothing);

    await gesture.moveTo(const Offset(2, 2));
    await tester.pump();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('player-timeline-preview')),
          )
          .opacity,
      0,
    );
    await gesture.removePointer();
  });

  testWidgets('performance mode debounces and requests a coarse frame', (
    tester,
  ) async {
    final calls = <({Duration time, bool coarse})>[];
    await tester.pumpWidget(
      subject(
        mode: VideoScrubberPreviewMode.performance,
        loader:
            (
              time, {
              required coarse,
              required prefetch,
              required cancellation,
            }) async {
              calls.add((time: time, coarse: coarse));
              return Uint8List(0);
            },
      ),
    );
    final gesture = await hover(
      tester,
      tester.getCenter(find.byKey(const ValueKey('video-timeline'))),
    );

    await tester.pump(const Duration(milliseconds: 119));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(calls, hasLength(1));
    expect(calls.single.coarse, isTrue);
    expect(calls.single.time.inSeconds, inInclusiveRange(58, 62));
    expect(find.text('暂无预览'), findsOneWidget);
    await gesture.removePointer();
  });

  testWidgets(
    'same in-flight bucket survives hover jitter and changed bucket replaces it',
    (tester) async {
      final requests = <VideoPreviewCancellation>[];
      final results = <Completer<Uint8List?>>[];
      await tester.pumpWidget(
        subject(
          mode: VideoScrubberPreviewMode.performance,
          loader:
              (
                time, {
                required coarse,
                required prefetch,
                required cancellation,
              }) {
                requests.add(cancellation);
                final result = Completer<Uint8List?>();
                results.add(result);
                return result.future;
              },
        ),
      );
      final slider = find.byKey(const ValueKey('video-timeline'));
      final center = tester.getCenter(slider);
      final gesture = await hover(tester, center);
      await tester.pump(const Duration(milliseconds: 120));
      expect(requests, hasLength(1));

      // The coarse 120-second fixture has buckets much wider than one pixel.
      // Waiting past the old throttle before a tiny move used to cancel and
      // restart this still-running request forever.
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.moveTo(center + const Offset(1, 0));
      await tester.pump(const Duration(milliseconds: 150));
      expect(requests, hasLength(1));
      expect(requests.single.isCancelled, isFalse);

      await gesture.moveTo(center + const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 120));
      expect(requests, hasLength(2));
      expect(requests.first.isCancelled, isTrue);

      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      results.first.complete(null);
      results.last.complete(png);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('player-timeline-preview-image')),
        findsOneWidget,
      );
      await gesture.removePointer();
    },
  );

  testWidgets('dragging out clears the pending bucket so re-entry retries', (
    tester,
  ) async {
    final requests = <VideoPreviewCancellation>[];
    await tester.pumpWidget(
      subject(
        mode: VideoScrubberPreviewMode.performance,
        loader:
            (
              time, {
              required coarse,
              required prefetch,
              required cancellation,
            }) {
              requests.add(cancellation);
              return cancellation.whenCancelled.then<Uint8List?>((_) => null);
            },
      ),
    );
    final region = find.byKey(const ValueKey('player-timeline-hover-region'));
    final rect = tester.getRect(region);
    final center = rect.center;
    final gesture = await hover(tester, center);
    await tester.pump(const Duration(milliseconds: 120));
    expect(requests, hasLength(1));

    await gesture.down(center);
    await gesture.moveTo(Offset(center.dx, rect.bottom + 60));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(requests.single.isCancelled, isTrue);

    await gesture.moveTo(center);
    await tester.pump(const Duration(milliseconds: 120));
    expect(requests, hasLength(2));
    await gesture.removePointer();
  });

  testWidgets('preview bubble remains clamped at both timeline edges', (
    tester,
  ) async {
    await tester.pumpWidget(subject(mode: VideoScrubberPreviewMode.balanced));
    final region = find.byKey(const ValueKey('player-timeline-hover-region'));
    final box = tester.getRect(region);
    final gesture = await hover(tester, Offset(box.left + 1, box.center.dy));
    var preview = tester.getRect(
      find.byKey(const ValueKey('player-timeline-preview-position')),
    );
    expect(preview.left, closeTo(box.left, .01));

    await gesture.moveTo(Offset(box.right - 1, box.center.dy));
    await tester.pump();
    preview = tester.getRect(
      find.byKey(const ValueKey('player-timeline-preview-position')),
    );
    expect(preview.right, closeTo(box.right, .01));
    await gesture.removePointer();
  });
}
