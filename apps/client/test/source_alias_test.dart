import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/source_alias_dialog.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  Future<MediaSource> addSource(SourceRepository repository) => repository.add(
    kind: MediaSourceKind.emby,
    name: 'Emby 媒体库',
    location: 'emby://fixture/user',
  );

  Future<void> openEditor(
    WidgetTester tester,
    SourceRepository repository,
    MediaSource source,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSourceAliasDialog(
                context,
                source: source,
                repository: repository,
              ),
              child: const Text('设置别名'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('设置别名'));
    await tester.pumpAndSettle();
  }

  testWidgets('blank alias cannot save and cancel preserves the source', (
    tester,
  ) async {
    final repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    addTearDown(repository.close);
    final source = await addSource(repository);
    await openEditor(tester, repository, source);
    await tester.enterText(
      find.byKey(const ValueKey('source-alias-input')),
      '   ',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-alias-dialog')), findsNothing);
    expect((await repository.source(source.id)).name, source.name);
  });

  testWidgets(
    'failed persistence retains input and allows a successful retry',
    (tester) async {
      final database = LibraryDatabase(NativeDatabase.memory());
      final repository = SourceRepository(database: database, adapters: {});
      addTearDown(repository.close);
      final source = await addSource(repository);
      await database.customStatement('''
      CREATE TRIGGER reject_alias BEFORE UPDATE OF name ON sources
      BEGIN SELECT RAISE(ABORT, 'fixture save failure'); END
    ''');
      await openEditor(tester, repository, source);
      final input = find.byKey(const ValueKey('source-alias-input'));
      await tester.enterText(input, '  客厅影音  ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-alias-dialog')), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, '  客厅影音  ');
      expect(tester.widget<TextField>(input).decoration!.errorText, isNotNull);
      expect((await repository.source(source.id)).name, source.name);

      await database.customStatement('DROP TRIGGER reject_alias');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-alias-dialog')), findsNothing);
      final saved = await repository.source(source.id);
      expect(saved.name, '客厅影音');
      expect(saved.location, source.location);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'alias survives database reopening without changing source identity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'reelnest-alias-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/library.sqlite');
      var repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase(file)),
        adapters: {},
      );
      final original = await addSource(repository);
      await repository.updateSettings(original.id, name: '  家庭媒体库  ');
      await repository.close();
      repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase(file)),
        adapters: {},
      );
      addTearDown(repository.close);
      final reopened = await repository.source(original.id);
      expect(reopened.name, '家庭媒体库');
      expect(reopened.id, original.id);
      expect(reopened.kind, original.kind);
      expect(reopened.location, original.location);
      expect(reopened.options.toJson(), original.options.toJson());
    },
  );
}
