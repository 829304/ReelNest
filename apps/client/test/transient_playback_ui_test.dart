import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/presentation/transient_playback_controls.dart';
import 'package:reelnest/ui/widgets/source_sheet_button.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('drop target forwards only the first item', (tester) async {
    String? opened;
    Uint8List? forwardedBookmark;
    await tester.pumpWidget(
      _host(
        TransientMediaDropTarget(
          openFile: (path, {securityBookmark}) async {
            opened = path;
            forwardedBookmark = securityBookmark;
          },
          onError: (_) {},
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    var target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragEntered!(
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero),
    );
    await tester.pump();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('transient-drop-overlay')),
          )
          .opacity,
      1,
    );

    target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile(
            r'C:\video\first.mp4',
            extraAppleBookmark: Uint8List.fromList([1, 2, 3]),
          ),
          DropItemFile(r'C:\video\second.mp4'),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, r'C:\video\first.mp4');
    expect(forwardedBookmark, [1, 2, 3]);
  });

  testWidgets('drop target reports a safe launcher failure', (tester) async {
    Object? failure;
    await tester.pumpWidget(
      _host(
        TransientMediaDropTarget(
          openFile: (_, {securityBookmark}) async =>
              throw const SourceFailure('文件不可播放。'),
          onError: (error) => failure = error,
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile(r'C:\video\broken.mp4')],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(failure, isA<SourceFailure>());
    expect((failure! as SourceFailure).message, '文件不可播放。');
  });

  testWidgets('drop overlay only becomes visible while a drag is active', (
    tester,
  ) async {
    Future<void> pump(bool active) => tester.pumpWidget(
      _host(
        TransientPlaybackDropOverlay(
          active: active,
          child: const ColoredBox(
            key: ValueKey('drop-content'),
            color: Colors.black,
          ),
        ),
      ),
    );

    await pump(false);
    expect(find.byKey(const ValueKey('drop-content')), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('transient-drop-overlay')),
          )
          .opacity,
      0,
    );

    await pump(true);
    expect(find.text('松开以播放文件'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('transient-drop-overlay')),
          )
          .opacity,
      1,
    );
  });

  testWidgets('open media menu exposes file and stream actions', (
    tester,
  ) async {
    var fileCalls = 0;
    var streamCalls = 0;
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.topLeft,
          child: TransientPlaybackMenuButton(
            onOpenFile: () => fileCalls++,
            onOpenStream: () => streamCalls++,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-transient-media-menu')));
    await tester.pumpAndSettle();
    expect(find.text('打开文件…'), findsOneWidget);
    expect(find.text('打开网络串流…'), findsOneWidget);

    await tester.tap(find.text('打开文件…'));
    await tester.pumpAndSettle();
    expect(fileCalls, 1);
    expect(streamCalls, 0);
  });

  testWidgets('stream dialog validates protocol and trims the submitted URL', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showTransientStreamDialog(
              context,
              onOpen: (value) async => opened = value,
            ),
            child: const Text('show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    final submit = find.byKey(const ValueKey('transient-stream-submit'));
    expect(tester.widget<SourceSheetButton>(submit).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('transient-stream-input')),
      ' file:///tmp/video.mp4 ',
    );
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();
    expect(opened, isNull);
    expect(find.textContaining('请输入合法的串流地址'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('transient-stream-input')),
      ' https://example.com/video.mp4 ',
    );
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(opened, 'https://example.com/video.mp4');
    expect(find.byKey(const ValueKey('transient-stream-dialog')), findsNothing);
  });

  testWidgets('stream dialog keeps safe launcher failure visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showTransientStreamDialog(
              context,
              onOpen: (_) async => throw const SourceFailure('这个串流暂时无法播放。'),
            ),
            child: const Text('show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transient-stream-input')),
      'rtsp://example.com/live',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transient-stream-submit')));
    await tester.pumpAndSettle();

    expect(find.text('这个串流暂时无法播放。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transient-stream-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('stream dialog prevents duplicate opens while pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showTransientStreamDialog(
              context,
              onOpen: (_) {
                calls++;
                return pending.future;
              },
            ),
            child: const Text('show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transient-stream-input')),
      'srt://example.com/live',
    );
    await tester.pump();
    final submit = find.byKey(const ValueKey('transient-stream-submit'));
    await tester.tap(submit);
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('正在打开…'), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transient-stream-dialog')), findsNothing);
  });
}
