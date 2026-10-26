import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/presentation/transient_playback_controls.dart';

void main() {
  Future<void> pressOpenShortcut(
    WidgetTester tester, {
    required bool macOS,
  }) async {
    final modifier = macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets('${platform.name} opens stream with the original shortcut', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: TransientPlaybackShortcuts(
              onOpenStream: () => calls++,
              child: const Focus(autofocus: true, child: SizedBox.expand()),
            ),
          ),
        );
        await tester.pump();

        await pressOpenShortcut(
          tester,
          macOS: platform == TargetPlatform.macOS,
        );
        expect(calls, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
