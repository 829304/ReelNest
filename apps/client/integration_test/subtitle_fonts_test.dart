import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelnest/platform/subtitle_font_catalog.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _child() async {
  await windowManager.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  await window.setWindowMethodHandler((call) async {
    if (call.method == 'families') return SubtitleFontCatalog().families();
    if (call.method == 'close') {
      // Reply before destroying this child engine; never quit the whole runner.
      Timer(
        const Duration(milliseconds: 100),
        () => unawaited(windowManager.close()),
      );
      return true;
    }
    return null;
  });
  runApp(const SizedBox.shrink());
}

// flutter drive is required: flutter test's listener also starts in child
// engines and would prevent them from booting this isolated test entry point.
void main(List<String> arguments) {
  if (arguments.isNotEmpty && arguments.first == 'multi_window') {
    WidgetsFlutterBinding.ensureInitialized();
    unawaited(_child());
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('installed subtitle fonts enumerate in main and child engines', (
    tester,
  ) async {
    final mainFonts = await SubtitleFontCatalog().families();
    expect(
      mainFonts,
      isNotEmpty,
      reason: 'This desktop test host must have at least one installed preferred family',
    );
    final child = await WindowController.create(
      const WindowConfiguration(arguments: 'subtitle-font-test'),
    );
    try {
      List<dynamic>? childFonts;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (childFonts == null && DateTime.now().isBefore(deadline)) {
        try {
          childFonts = await child
              .invokeMethod<List<dynamic>>('families')
              .timeout(const Duration(seconds: 1));
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      expect(childFonts, mainFonts);
    } finally {
      await child.invokeMethod<bool>('close');
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while ((await WindowController.getAll()).any(
            (w) => w.windowId == child.windowId,
          ) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        (await WindowController.getAll()).any(
          (w) => w.windowId == child.windowId,
        ),
        isFalse,
      );
    }
    expect(await SubtitleFontCatalog().families(), mainFonts);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
