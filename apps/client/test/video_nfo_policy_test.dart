import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/metadata/data/video_nfo_policy.dart';

void main() {
  late Directory root;
  MediaSource source({
    bool enabled = true,
    MediaSourceKind kind = MediaSourceKind.localFolder,
  }) => MediaSource(
    id: 'source',
    kind: kind,
    name: 'test',
    location: root.path,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    options: SourceOptions(preferMetadataWriteToSource: enabled),
  );
  IndexedMedia item(String id, {bool series = false, String? parent}) =>
      IndexedMedia(
        identity: (sourceId: 'source', localId: id),
        title: 'Show',
        type: series
            ? 'tvShow'
            : parent == null
            ? 'movie'
            : 'episode',
        parentId: parent,
        isSeries: series,
        bytes: 1,
        modified: DateTime.now(),
      );
  Future<void> file(String id) async {
    final f = File(p.join(root.path, id));
    await f.parent.create(recursive: true);
    await f.writeAsString('fixture');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reelnest-nfo-policy-');
  });
  tearDown(() async {
    expect(p.isWithin(Directory.systemTemp.path, root.path), isTrue);
    await root.delete(recursive: true);
  });
  test(
    'each movie in a shared directory owns only its basename sidecar',
    () async {
      await file('A.mkv');
      await file('B.mp4');
      expect(
        await VideoNfoPolicy.resolve(source(), item('A.mkv'), []),
        p.join(root.path, 'A.nfo'),
      );
      expect(
        await VideoNfoPolicy.resolve(source(), item('B.mp4'), []),
        p.join(root.path, 'B.nfo'),
      );
    },
  );
  test('series seasons must resolve to one shared show directory', () async {
    await file('Show/Season 1/Show.S01E01.mkv');
    await file('Show/Season 2/Show.S02E01.mkv');
    final children = [
      item('Show/Season 1/Show.S01E01.mkv', parent: 'show'),
      item('Show/Season 2/Show.S02E01.mkv', parent: 'show'),
    ];
    expect(
      await VideoNfoPolicy.resolve(
        source(),
        item('show', series: true),
        children,
      ),
      p.join(root.path, 'Show', 'tvshow.nfo'),
    );
  });
  test('ambiguous root ownership and mixed shows never write library-root tvshow.nfo', () async {
    await file('Show.S01E01.mkv');
    await file('A/A.S01E01.mkv');
    await file('B/B.S01E01.mkv');
    expect(
      await VideoNfoPolicy.resolve(source(), item('show', series: true), [
        item('Show.S01E01.mkv', parent: 'show'),
      ]),
      isNull,
    );
    expect(
      await VideoNfoPolicy.resolve(source(), item('show', series: true), [
        item('A/A.S01E01.mkv', parent: 'show'),
        item('B/B.S01E01.mkv', parent: 'show'),
      ]),
      isNull,
    );
  });
  test(
    'disabled and remote sources return before touching source directories',
    () async {
      expect(
        await VideoNfoPolicy.resolve(
          source(enabled: false),
          item('missing.mkv'),
          [],
        ),
        isNull,
      );
      expect(
        await VideoNfoPolicy.resolve(
          source(kind: MediaSourceKind.emby),
          item('missing.mkv'),
          [],
        ),
        isNull,
      );
      await expectLater(
        VideoNfoPolicy.resolve(source(), item('../escape.mkv'), []),
        throwsA(isA<SourceFailure>()),
      );
    },
  );
}
