import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/app/reelnest_app.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/source_scan.dart';
import 'package:reelnest/domain/source_settings_draft.dart';
import 'package:reelnest/features/health/application/health_providers.dart';
import 'package:reelnest/features/health/domain/local_health_evaluator.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/source_settings_sheet.dart';
import 'package:reelnest/sources/source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  Future<SourceRepository> fixture(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1088, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: _Files()},
    );
    addTearDown(repository.close);
    await repository.add(
      kind: MediaSourceKind.localFolder,
      name: '电影目录',
      location: '/online',
    );
    return repository;
  }

  testWidgets(
    'dashboard ignore and settings restore keep native-minimum layout usable',
    (tester) async {
      final repository = await fixture(tester);
      final source = (await repository.sources()).single;
      await repository.scan(source.id);
      var probes = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(repository),
            localHealthEvaluatorProvider.overrideWithValue(
              LocalHealthEvaluator(
                paths: p.Context(style: p.Style.posix),
                exists: (path) async {
                  probes++;
                  return path == '/online';
                },
              ),
            ),
          ],
          child: const ReelNestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
      await tester.pumpAndSettle();
      expect(find.text('挂载源在线监测'), findsOneWidget);
      expect(find.text('缺封面等 3 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final count = probes;
      await tester.tap(find.byTooltip('永久忽略此检查结果，可在设置中恢复').first);
      await tester.pumpAndSettle();
      expect(find.text('影视元数据完整，无需补充。'), findsOneWidget);
      expect(probes, count);
      await tester.tap(find.byKey(const ValueKey('nav-设置')));
      await tester.pumpAndSettle();
      expect(find.text('1 项'), findsOneWidget);
      await tester.tap(find.text('恢复显示'));
      await tester.pumpAndSettle();
      expect(find.text('0 项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-仪表盘')));
      await tester.pumpAndSettle();
      expect(find.text('缺封面等 3 项'), findsOneWidget);
      expect(probes, count);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'source settings draft cancel and save at minimum size: $brightness',
      (tester) async {
        final repository = await fixture(tester);
        final source = (await repository.sources()).single;
        SourceSettingsDraft? draft;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    draft = await showDialog<SourceSettingsDraft>(
                      context: context,
                      builder: (_) => SourceSettingsSheet(source: source),
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
        await tester.tap(find.byKey(const ValueKey('media-type-photo')));
        await tester.pumpAndSettle();
        expect(find.text('参与元数据拉取'), findsNothing);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(draft, isNull);
        expect(
          (await repository.source(source.id)).mediaType,
          SourceMediaType.auto,
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('参与健康检查'));
        await tester.tap(find.widgetWithText(TextButton, '参与健康检查'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存设置'));
        await tester.pumpAndSettle();
        expect(draft!.includeInHealthCheck, isFalse);
        expect(draft!.mediaType, SourceMediaType.auto);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Files implements SourceAdapter {
  @override
  Future<String> validateLocation(String location) async => location;
  @override
  Future<bool> isReachable(String location) async => true;
  @override
  Stream<SourceScanEvent> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    yield const ScanCatalogued(1);
    yield ScanFileProcessed(
      path: 'Film.mkv',
      item: IndexedMedia(
        identity: (sourceId: source.id, localId: 'Film.mkv'),
        title: 'Film',
        type: 'movie',
        bytes: 0,
        modified: DateTime.utc(2026),
      ),
    );
  }
}
