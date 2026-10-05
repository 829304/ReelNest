import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/sources_page.dart';
import 'package:reelnest/sources/source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/ui/theme/app_theme.dart';

void main() {
  testWidgets(
    'connected/offline groups, scan-all and focus refresh use actual reachability',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(
        836,
        720,
      ); // 1088 minus desktop sidebar.
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = _Files();
      final repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: files},
      );
      addTearDown(repository.close);
      for (final name in ['Online', 'Offline']) {
        await repository.add(
          kind: MediaSourceKind.localFolder,
          name: name,
          location: '/$name',
        );
      }
      final container = ProviderContainer(
        overrides: [sourceRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: SourcesPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已连接媒体源'), findsOneWidget);
      expect(find.text('已断开媒体源'), findsOneWidget);
      expect(find.text('1个'), findsNWidgets(2));
      expect(find.text('可访问'), findsOneWidget);
      expect(find.text('不可访问'), findsOneWidget);
      final rowScans = tester
          .widgetList<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '重新扫描'),
          )
          .toList();
      expect(
        rowScans.where((button) => button.onPressed != null),
        hasLength(1),
      );
      await tester.tap(find.byKey(const ValueKey('scan-all')));
      await tester.pumpAndSettle();
      expect(files.scanned, ['/Online']);
      expect(
        container.read(sourceScansProvider).values.every((scan) => !scan.busy),
        isTrue,
      );

      files.connected.add('/Offline');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('已断开媒体源'), findsNothing);
      expect(find.text('2个'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Files implements SourceAdapter {
  final connected = {'/Online'};
  final scanned = <String>[];
  @override
  Future<bool> isReachable(String location) async =>
      connected.contains(location);
  @override
  Future<String> validateLocation(String location) async => location;
  @override
  Stream<IndexedMedia> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    scanned.add(source.location);
    yield IndexedMedia(
      identity: (sourceId: source.id, localId: 'film.mp4'),
      title: 'Film',
      type: 'homeVideo',
      bytes: 52428800,
      modified: DateTime.utc(2026),
    );
  }
}
