import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/features/sources/presentation/add_source_dialog.dart';
import 'package:reelnest/platform/directory_access.dart';
import 'package:reelnest/ui/theme/app_theme.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'multi-directory selection, cancel and picker error retain draft (dark=$dark)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1088, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final picker = _Picker();
        SourceDraft? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<SourceDraft>(
                      context: context,
                      builder: (_) => AddSourceDialog(access: picker),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('media-type-private')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '添加并扫描'))
              .onPressed,
          isNull,
        );
        await tester.tap(find.widgetWithText(TextButton, '选择文件夹'));
        await tester.pumpAndSettle();
        picker.pending.complete(List.generate(6, (i) => '/folder$i'));
        await tester.pumpAndSettle();
        expect(find.text('已选择 6 个文件夹'), findsOneWidget);
        expect(find.text('另有 2 个文件夹'), findsOneWidget);
        expect(find.text('folder3'), findsOneWidget);
        expect(find.text('folder4'), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('media-type-music')),
        );
        await tester.tap(find.byKey(const ValueKey('media-type-music')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('重新选择文件夹'));
        picker.pending = Completer<List<String>>();
        await tester.tap(find.text('重新选择文件夹'));
        await tester.pumpAndSettle();
        picker.pending.complete([]);
        await tester.pumpAndSettle();
        expect(find.text('已选择 6 个文件夹'), findsOneWidget);
        picker.pending = Completer<List<String>>();
        await tester.tap(find.text('重新选择文件夹'));
        await tester.pumpAndSettle();
        picker.pending.completeError(const SourceFailure('选择器读取失败'));
        await tester.pumpAndSettle();
        expect(find.text('选择器读取失败'), findsOneWidget);
        await tester.tap(find.text('添加并扫描'));
        await tester.pumpAndSettle();
        expect(result!.locations, List.generate(6, (i) => '/folder$i'));
        expect(result!.mediaType, SourceMediaType.music);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Picker implements DirectoryAccess {
  var pending = Completer<List<String>>();
  @override
  bool get supported => true;
  @override
  String get unavailableReason => '';
  @override
  Future<String?> choose() =>
      throw StateError('Must use multi-directory picker');
  @override
  Future<List<String>> chooseMany() => pending.future;
}
