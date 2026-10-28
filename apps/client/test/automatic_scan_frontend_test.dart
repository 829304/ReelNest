import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/automatic_scan_interval.dart';
import 'package:reelnest/features/settings/presentation/automatic_scan_settings.dart';
import 'package:reelnest/features/sources/application/automatic_scan_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/preference_store.dart';
import 'package:reelnest/ui/theme/app_theme.dart';

void main() {
  testWidgets('automatic scan menu loads and saves every original interval', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 520);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: const {},
    );
    addTearDown(repository.close);
    await repository.database.writePreference(
      AutomaticScanSettings.preferenceKey,
      AutomaticScanInterval.sixHours.name,
    );
    final container = ProviderContainer(
      overrides: [sourceRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: AutomaticScanSettingsPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('媒体库更新'), findsOneWidget);
    expect(find.text('每 6 小时'), findsOneWidget);
    expect(find.textContaining('本机文件夹有变动会很快更新'), findsOneWidget);

    for (final interval in AutomaticScanInterval.values) {
      await tester.tap(find.byKey(const ValueKey('automatic-scan-interval')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(interval.displayName).last);
      await tester.pumpAndSettle();
      expect(container.read(automaticScanIntervalProvider), interval);
      expect(
        await repository.database.preferenceValue(
          AutomaticScanSettings.preferenceKey,
        ),
        interval.name,
      );
      expect(tester.takeException(), isNull);
    }
    // UncontrolledProviderScope does not own its external container. Stop its
    // periodic timer before the widget binding checks for leaked timers.
    await tester.runAsync(
      () => container.read(automaticSourceScannerProvider).dispose(),
    );
  });

  testWidgets('automatic scan menu remains usable at compact desktop width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 520);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: const {},
    );
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sourceRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SingleChildScrollView(child: AutomaticScanSettingsPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('自动扫描'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('automatic-scan-interval')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
