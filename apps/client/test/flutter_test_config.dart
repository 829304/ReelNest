import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:reelnest/storage/runtime_storage_paths.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = await Directory.systemTemp.createTemp(
    'reelnest-test-storage-',
  );
  await runZoned(
    () async {
      tearDownAll(() async {
        if (await sandbox.exists()) await sandbox.delete(recursive: true);
      });
      await testMain();
    },
    zoneValues: {
      RuntimeStoragePaths.zoneKey: RuntimeStoragePaths(
        root: sandbox,
        portable: true,
      ),
    },
  );
}
