import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_frame_preview.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

void main() {
  late Directory directory;
  late SourceRepository sources;
  late PlaybackSession session;
  late MediaSource source;
  late VideoPreviewGenerator generate;
  final engines = <FakeVideoEngine>[];
  setUp(() async {
    engines.clear();
    directory = await Directory.systemTemp.createTemp(
      'reelnest-preview-session-',
    );
    for (final name in ['First.mkv', 'Second.mkv']) {
      await File(p.join(directory.path, name)).writeAsString('fake decoder');
    }
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Fixture',
      location: directory.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    generate = (_, _, _) async => Uint8List(1);
    session = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      previewGenerator: (resource, time, cancellation) =>
          generate(resource, time, cancellation),
      createEngine: () {
        final e = FakeVideoEngine();
        engines.add(e);
        return e;
      },
    );
  });
  tearDown(() async {
    await session.close(discardProgress: true);
    session.dispose();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
    expect(p.basename(directory.path), startsWith('reelnest-preview-session-'));
    await directory.delete(recursive: true);
  });
  Future<VideoPreviewFrame?> request() => session.requestPreview(
    time: const Duration(seconds: 20),
    duration: const Duration(seconds: 100),
    coarse: false,
  );
  test(
    'preview reads committed local resource without changing main clock',
    () async {
      VideoPreviewResource? resource;
      generate = (value, _, _) async {
        resource = value;
        return Uint8List(1);
      };
      expect(await request(), isNull);
      await session.open((sourceId: source.id, localId: 'First.mkv'));
      final before = session.clock;
      expect(await request(), isNotNull);
      expect(resource!.location, p.join(directory.path, 'First.mkv'));
      expect(resource!.identity, session.item!.identity);
      expect(resource.toString(), isNot(contains(directory.path)));
      expect(session.clock, same(before));
      expect(session.error, isNull);
    },
  );
  test('switch and close suppress stale frames and cancel producer', () async {
    final result = Completer<Uint8List?>();
    VideoPreviewCancellation? token;
    var calls = 0;
    generate = (_, _, c) {
      token = c;
      return ++calls == 1
          ? result.future
          : Future.value(Uint8List.fromList([2]));
    };
    await session.open((sourceId: source.id, localId: 'First.mkv'));
    final old = request();
    await session.open((sourceId: source.id, localId: 'Second.mkv'));
    expect(await old, isNull);
    expect(token!.isCancelled, isTrue);
    result.complete(Uint8List.fromList([1]));
    expect((await request())!.bytes, [2]);
    await session.close(discardProgress: true);
    expect(session.previewFrames.cachedCount, 0);
    expect(await request(), isNull);
  });
  test('failed switch restores original resource; preview failure remains auxiliary', () async {
    await session.open((sourceId: source.id, localId: 'First.mkv'));
    await File(p.join(directory.path, 'Second.mkv')).delete();
    await session.open((sourceId: source.id, localId: 'Second.mkv'));
    expect(session.item!.identity.localId, 'First.mkv');
    expect(await request(), isNotNull);
    session.previewFrames.attach(
      VideoPreviewResource(
        identity: session.item!.identity,
        location: session.filePath!,
      ),
    );
    generate = (_, _, _) async {
      throw StateError('Preview unavailable');
    };
    expect(await request(), isNull);
    expect(session.error, isNull);
    expect(session.controlError, isNull);
    expect(engines.single.disposals, 0);
  });
}
