import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/reelnest_app.dart';
import 'package:reelnest/app/service_providers.dart';
import 'package:reelnest/shell/desktop_shell.dart';
import 'package:reelnest/shell/mobile_shell.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';

void main() {
  Future<void> start(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          credentialStoreProvider.overrideWithValue(_MemoryCredentialStore()),
          sourcesProvider.overrideWith((ref) async => <MediaSource>[]),
        ],
        child: const ReelNestApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'desktop navigation retains route when resized',
    (tester) async {
      await start(tester, const Size(1280, 800));
      expect(find.byType(DesktopShell), findsOneWidget);
      await tester.tap(find.text('管理媒体源'));
      await tester.pumpAndSettle();
      expect(find.text('媒体源待添加'), findsOneWidget);

      tester.view.physicalSize = const Size(1088, 720);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopShell), findsOneWidget);
      expect(find.byType(MobileShell), findsNothing);
      expect(find.text('媒体源待添加'), findsOneWidget);
      expect(
        tester.widget<DesktopShell>(find.byType(DesktopShell)).selectedIndex,
        1,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'wide mobile template does not select desktop navigation by width',
    (tester) async {
      await start(tester, const Size(1280, 800));
      expect(find.byType(MobileShell), findsOneWidget);
      expect(find.byType(DesktopShell), findsNothing);
    },
  );

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

// Shell tests should never read credentials from the developer's OS account.
class _MemoryCredentialStore implements CredentialStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}
