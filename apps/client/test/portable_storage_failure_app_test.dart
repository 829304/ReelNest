import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/portable_storage_failure_app.dart';

void main() {
  testWidgets('portable storage failure stays concise and path-free', (
    tester,
  ) async {
    await tester.pumpWidget(const PortableStorageFailureApp());

    expect(find.text('程序目录不可写'), findsOneWidget);
    expect(find.text(PortableStorageFailureApp.defaultMessage), findsOneWidget);
    expect(find.byIcon(Icons.folder_off_rounded), findsOneWidget);
    expect(find.textContaining('AppData'), findsNothing);
    expect(find.textContaining(r'C:\'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('portable storage failure accepts a sanitized startup message', (
    tester,
  ) async {
    const message = '便携数据初始化失败，请重新打开 ReelNest。';
    await tester.pumpWidget(const PortableStorageFailureApp(message: message));

    expect(find.text(message), findsOneWidget);
    expect(find.text(PortableStorageFailureApp.defaultMessage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
