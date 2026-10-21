import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/reelnest_app.dart';
import 'package:reelnest/app/service_providers.dart';
import 'package:reelnest/shell/desktop_shell.dart';
import 'package:reelnest/shell/mobile_shell.dart';
import 'package:reelnest/shell/sidebar_components.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/settings/presentation/settings_page.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/ui/theme/design_tokens.dart';

void main() {
  Future<void> start(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(repository),
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
      expect(find.byType(AppSidebarSectionHeader), findsNWidgets(2));
      expect(
        tester.getSize(find.byKey(const ValueKey('desktop-sidebar'))).width,
        DesignTokens.sidebarIdealWidth,
      );
      await tester.drag(
        find.byKey(const ValueKey('desktop-sidebar-resizer')),
        const Offset(100, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('desktop-sidebar'))).width,
        DesignTokens.sidebarMaxWidth,
      );
      await tester.drag(
        find.byKey(const ValueKey('desktop-sidebar-resizer')),
        const Offset(-100, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('desktop-sidebar'))).width,
        DesignTokens.sidebarMinWidth,
      );
      await tester.tap(find.text('前往媒体源添加'));
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

  for (final brightness in Brightness.values) {
    testWidgets(
      'sidebar real mouse hover/click/exit has no stale fills $brightness',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SizedBox(
                width: DesignTokens.sidebarIdealWidth,
                child: AppSidebarHoverRegion(
                  child: Column(
                    children: [
                      for (var index = 0; index < 3; index++)
                        AppSidebarRow(
                          key: ValueKey('row-$index'),
                          label: ['国产剧', '外语电影', '动画电影'][index],
                          leading: const Icon(Icons.video_library_outlined),
                          selected: index == 0,
                          onTap: () => taps++,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        BoxDecoration background(int index) =>
            tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: find.byKey(ValueKey('row-$index')),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(700, 550));
        addTearDown(mouse.removePointer);
        final first = tester.getCenter(find.byKey(const ValueKey('row-1')));
        final second = tester.getCenter(find.byKey(const ValueKey('row-2')));
        await mouse.moveTo(first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final enteringAlpha = background(1).color!.a;
        expect(enteringAlpha, greaterThan(0));
        await tester.pumpAndSettle();
        final settledAlpha = background(1).color!.a;
        expect(enteringAlpha, lessThan(settledAlpha));
        // Selection remains visible while another row is hovered (SwiftUI).
        expect(background(0).gradient, isNotNull);
        expect(background(1).color, isNot(Colors.transparent));
        expect(background(2).color, Colors.transparent);
        await mouse.down(first);
        await tester.pump();
        await mouse.up();
        await tester.pumpAndSettle();
        expect(taps, 1);
        // Click does not manufacture a pointer exit; hover must survive.
        expect(background(1).color, isNot(Colors.transparent));
        await mouse.moveTo(const Offset(700, 550));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final exitingAlpha = background(1).color!.a;
        expect(exitingAlpha, greaterThan(0));
        expect(exitingAlpha, lessThan(settledAlpha));
        await tester.pumpAndSettle();
        expect(background(1).color, Colors.transparent);
        await mouse.moveTo(first);
        await tester.pumpAndSettle();
        for (var n = 0; n < 6; n++) {
          await mouse.moveTo(n.isEven ? second : first);
          await tester.pump(const Duration(milliseconds: 16));
          // Check the painted decoration during rapid movement, not only
          // the final state after every animation has settled.
          expect(background(n.isEven ? 1 : 2).color, Colors.transparent);
          expect(background(0).gradient, isNotNull);
        }
        await mouse.moveTo(second);
        await tester.pumpAndSettle();
        expect(background(1).color, Colors.transparent);
        expect(background(2).color, isNot(Colors.transparent));
        // Drag out while pressed, then release: no pressed/hover trail.
        await mouse.down(second);
        await tester.pump();
        await mouse.moveTo(const Offset(700, 550));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(background(0).gradient, isNotNull);
        expect(background(1).color, Colors.transparent);
        expect(background(2).color, Colors.transparent);
        // Keyboard focus can outline a row, but never fill another gray pill.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(background(1).color, Colors.transparent);
        expect(background(2).color, Colors.transparent);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets('mobile appearance changes survive navigation', (tester) async {
    Future<Finder> revealAppearance() async {
      final scrollable = find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .first;
      final selector = find.byKey(
        const ValueKey('settings-appearance-selector'),
      );
      for (var n = 0; n < 6 && selector.evaluate().isEmpty; n++) {
        await tester.drag(scrollable, const Offset(0, -420));
        await tester.pumpAndSettle();
      }
      expect(selector, findsOneWidget);
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      return selector;
    }

    await start(tester, const Size(390, 844));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    var selector = await revealAppearance();
    await tester.tap(find.descendant(of: selector, matching: find.text('深色')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    selector = await revealAppearance();
    expect(tester.widget<SegmentedButton<ThemeMode>>(selector).selected, {
      ThemeMode.dark,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen supports enlarged text without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester, const Size(320, 640));
    expect(find.text('媒体源待添加'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('跟随系统'), 150);
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
