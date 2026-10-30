import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/ui/widgets/app_confirmation_dialog.dart';
import 'package:reelnest/ui/widgets/app_feedback.dart';

void main() {
  testWidgets('confirmation dialog returns the selected result', (
    tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => const AppConfirmationDialog(
                    title: '移除媒体',
                    subtitle: '仅影响 ReelNest 索引',
                    message: '本地文件不会被删除。',
                    confirmLabel: '确认移除',
                    destructive: true,
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('移除媒体'), findsOneWidget);
    expect(find.text('本地文件不会被删除。'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('app-confirmation-dialog')))
          .width,
      lessThanOrEqualTo(430),
    );
    expect(
      find.byKey(const ValueKey('app-confirmation-cancel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('app-confirmation-confirm')),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('confirmation dialog keeps the safe action focused', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => const AppConfirmationDialog(
                    title: '清理缓存？',
                    message: '播放中的离线副本会保留。',
                    confirmLabel: '清理',
                    destructive: true,
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.byKey(const ValueKey('app-confirmation-dialog')), findsNothing);
  });

  testWidgets('confirmation dialog stays compact in a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(340, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => const AppConfirmationDialog(
                  title: '确认移除多个条目？',
                  subtitle: '仅影响 ReelNest 索引',
                  message: '只会移除内部索引，不会修改媒体文件；离线来源中的条目会继续保留。',
                  confirmLabel: '移除',
                  destructive: true,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(
      find.byKey(const ValueKey('app-confirmation-dialog')),
    );
    expect(dialog.left, greaterThanOrEqualTo(16));
    expect(dialog.right, lessThanOrEqualTo(324));
    expect(dialog.height, lessThanOrEqualTo(268));
    expect(tester.takeException(), isNull);
  });

  testWidgets('app toast uses the shared floating feedback surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showAppToast(context, '设置已保存', kind: AppFeedbackKind.success),
              child: const Text('保存'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('设置已保存'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(AppInlineNotice), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
