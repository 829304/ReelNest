import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/reelnest_app.dart';
import 'package:reelnest/app/service_providers.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_scan.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/platform/directory_access.dart';
import 'package:reelnest/sources/source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';

void main() {
  testWidgets(
    'add multiple folders, classify, scan in selection order and browse without Mlink',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final files = _Files();
      final repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: files},
      );
      addTearDown(repository.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(repository),
            directoryAccessProvider.overrideWithValue(_Picker()),
            serverRepositoryProvider.overrideWith(
              (ref) => throw StateError(
                'Local UI must not construct a server repository',
              ),
            ),
            credentialStoreProvider.overrideWith(
              (ref) =>
                  throw StateError('Local UI must not require credentials'),
            ),
          ],
          child: const ReelNestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理媒体源'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-source')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '选择文件夹'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('media-type-music')),
      );
      await tester.tap(find.byKey(const ValueKey('media-type-music')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加并扫描'));
      await tester.pumpAndSettle();
      expect(find.text('local'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      expect(files.scanned, ['/synthetic/local', '/synthetic/second']);
      expect(
        (await repository.sources()).every(
          (s) =>
              s.mediaType == SourceMediaType.music &&
              s.minimumFileSize == 512 * 1024,
        ),
        isTrue,
      );
      expect(find.text('扫描完成：1 个媒体文件'), findsNWidgets(2));
      await tester.tap(find.text('浏览媒体').first);
      await tester.pumpAndSettle();
      expect(find.byType(LocalMediaCard), findsOneWidget);
      await tester.tap(find.byType(LocalMediaCard));
      // Route/data frames create the native File.exists future. Allow real I/O
      // between frames rather than spinning only Flutter's fake test clock.
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        if (find.byType(LocalMediaDetailPage).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            find.text('文件').evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(find.byType(LocalMediaDetailPage), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data!.replaceAll('\\', '/').endsWith('/movies/local.mp4'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('返回'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

class _Picker implements DirectoryAccess {
  @override
  bool get supported => true;
  @override
  String get unavailableReason => '';
  @override
  Future<String?> choose() async => '/synthetic/local';
  @override
  Future<List<String>> chooseMany() async => [
    '/synthetic/local',
    '/synthetic/second',
  ];
}

class _Files implements SourceAdapter {
  final scanned = <String>[];
  @override
  Future<bool> isReachable(String location) async => true;
  @override
  Future<String> validateLocation(String location) async => location;
  @override
  Stream<SourceScanEvent> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    cancellation.check();
    scanned.add(source.location);
    yield const ScanCatalogued(1);
    yield ScanFileProcessed(
      path: 'film.mp4',
      item: IndexedMedia(
        identity: (sourceId: source.id, localId: 'movies/local.mp4'),
        title: '本地影片',
        type: 'homeVideo',
        bytes: 1024,
        modified: DateTime.utc(2026),
      ),
    );
  }
}
