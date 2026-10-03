import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/reelnest_app.dart';
import 'package:reelnest/shell/desktop_shell.dart';
import 'package:reelnest/shell/mobile_shell.dart';

void main() {
  Future<void> start(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: ReelNestApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop navigation retains route when resized', (tester) async {
    await start(tester, const Size(1280, 800));
    expect(find.byType(DesktopShell), findsOneWidget);
    await tester.tap(find.text('管理服务器'));
    await tester.pumpAndSettle();
    expect(find.text('还没有服务器'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.text('还没有服务器'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile appearance changes survive navigation', (tester) async {
    await start(tester, const Size(390, 844));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '深色')).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen supports enlarged text without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester, const Size(320, 640));
    expect(find.text('你的媒体，从这里开始'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('跟随系统'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
