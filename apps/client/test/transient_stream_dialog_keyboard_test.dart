import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/presentation/transient_playback_controls.dart';

Widget _host(Future<void> Function(String value) onOpen) => MaterialApp(
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () => showTransientStreamDialog(context, onOpen: onOpen),
      child: const Text('show'),
    ),
  ),
);

void main() {
  testWidgets('escape cancels an idle stream dialog without opening media', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(_host((_) async => calls++));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byKey(const ValueKey('transient-stream-dialog')), findsNothing);
  });

  testWidgets('enter submits a valid stream URL', (tester) async {
    String? opened;
    await tester.pumpWidget(_host((value) async => opened = value));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transient-stream-input')),
      ' https://example.com/live.m3u8 ',
    );
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(opened, 'https://example.com/live.m3u8');
    expect(find.byKey(const ValueKey('transient-stream-dialog')), findsNothing);
  });
}
