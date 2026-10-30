import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/ui/theme/app_theme.dart';
import 'package:reelnest/ui/theme/design_tokens.dart';
import 'package:reelnest/ui/theme/source_sheet_palette.dart';
import 'package:reelnest/ui/widgets/app_menu_control.dart';

void main() {
  testWidgets('desktop menu control exposes original geometry and selection', (
    tester,
  ) async {
    var selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(80),
              child: Align(
                alignment: Alignment.topLeft,
                child: AppMenuControl<int>(
                  key: const ValueKey('menu-control'),
                  value: selected,
                  label: '选项 $selected',
                  values: const [1, 2, 3],
                  itemLabel: (value) => '选项 $value',
                  onSelected: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(DesignTokens.fastMotion);

    final control = find.byKey(const ValueKey('menu-control'));
    expect(tester.getSize(control).height, DesignTokens.defaultButtonHeight);
    expect(tester.getSize(control).width, greaterThanOrEqualTo(76));
    final surface = tester.widget<AnimatedContainer>(
      find.descendant(of: control, matching: find.byType(AnimatedContainer)),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(DesignTokens.controlRadius),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await tester.pump();
    await mouse.moveTo(tester.getCenter(control));
    await tester.pump(DesignTokens.fastMotion);
    final hovered = tester.widget<AnimatedContainer>(
      find.descendant(of: control, matching: find.byType(AnimatedContainer)),
    );
    expect(
      (hovered.decoration! as BoxDecoration).color,
      SourceSheetPalette(false).hoverPill,
    );

    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(find.text('选项 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-menu-selected-1')), findsOneWidget);
    await tester.tap(find.text('选项 2'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(
      find.descendant(
        of: find.descendant(
          of: control,
          matching: find.byType(AnimatedContainer),
        ),
        matching: find.text('选项 2'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu control hover and disabled states use semantic colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: AppMenuControl<int>(
            key: ValueKey('menu-control'),
            value: 1,
            label: '读取中',
            values: [1],
            itemLabel: _label,
            onSelected: _ignore,
            busy: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(DesignTokens.fastMotion);
    final control = find.byKey(const ValueKey('menu-control'));
    final context = tester.element(control);
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final surface = tester.widget<AnimatedContainer>(
      find.descendant(of: control, matching: find.byType(AnimatedContainer)),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.color, palette.card);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(control);
    await tester.pump();
    expect(find.byType(PopupMenuItem<int>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

String _label(int value) => '$value';
void _ignore(int value) {}
