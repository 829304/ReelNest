import 'dart:collection';
import 'dart:isolate';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/application/emby_library_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/storage/library_database.dart';

// Runs only when filtering inside the actual worker. Report its exit separately
// so merely discarding the provider's result cannot make this regression pass.
class _BlockingTerms extends ListBase<String?> {
  _BlockingTerms(this.ready, this.exited);
  final SendPort ready, exited;
  @override
  int get length {
    Isolate.current.addOnExitListener(exited);
    ready.send(true);
    while (true) {
      /* Stop only when the worker is killed. */
    }
  }

  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  String? operator [](int index) => 'unused';
  @override
  void operator []=(int index, String? value) =>
      throw UnsupportedError('immutable');
}

void main() {
  test('disposing obsolete Emby search kills active worker; next search still completes', () async {
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    addTearDown(sources.close);
    await sources.add(
      sourceId: 's',
      kind: MediaSourceKind.emby,
      name: 'Source',
      location: 'emby://fixture/s',
    );
    final source = await sources.source('s', includeCounts: false);
    final ready = ReceivePort(), exited = ReceivePort();
    addTearDown(() {
      ready.close();
      exited.close();
    });
    final entries = List.generate(181, (i) {
      final identity = (sourceId: 's', localId: '$i');
      return VideoLibraryEntry(
        item: IndexedMedia(
          identity: identity,
          title: 'Movie $i',
          type: 'movie',
          bytes: 0,
          modified: DateTime.utc(2026),
        ),
        record: PlaybackRecord(identity: identity),
        createdAt: DateTime.utc(2026),
        searchTerms: _BlockingTerms(ready.sendPort, exited.sendPort),
      );
    });
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        embyVideoSnapshotProvider.overrideWith(
          (ref, id) async => EmbyVideoSnapshot(
            source: source,
            libraries: [],
            entries: entries,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    const destination = (
      sourceId: 's',
      section: EmbyVideoSection.videos,
      libraryId: null as String?,
    );
    final first = embyVideoResultsProvider((
      destination: destination,
      settings: const VideoLibrarySettings(search: 'obsolete'),
    ));
    final subscription = container.listen(first, (_, _) {});
    final exit = exited.first.timeout(const Duration(seconds: 5));
    await ready.first.timeout(const Duration(seconds: 5));
    subscription.close();
    await container.pump();
    await exit;
    final next = embyVideoResultsProvider((
      destination: destination,
      settings: const VideoLibrarySettings(),
    ));
    final active = container.listen(next, (_, _) {});
    addTearDown(active.close);
    // Empty query does not enumerate fields; all items remain available.
    expect(await container.read(next.future), hasLength(181));
  });
}
