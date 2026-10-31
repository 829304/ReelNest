import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/sources/presentation/emby_sheets.dart';
import 'package:reelnest/ui/widgets/app_menu_control.dart';

void main() {
  testWidgets('remote trace menu preserves the selected policy semantics', (
    tester,
  ) async {
    var selected = RemoteTraceSyncMode.bidirectional;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 520,
              child: RemotePolicyPanel(
                metadata: true,
                health: true,
                trace: selected,
                onMetadata: (_) {},
                onHealth: (_) {},
                onTrace: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AppMenuControl<RemoteTraceSyncMode>), findsOneWidget);
    expect(find.text('数据双向同步'), findsOneWidget);
    expect(find.textContaining('与远程服务器互相更新'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remote-trace-sync-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅从服务器同步').last);
    await tester.pumpAndSettle();

    expect(selected, RemoteTraceSyncMode.importOnly);
    expect(find.textContaining('不把本机痕迹写回服务器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
