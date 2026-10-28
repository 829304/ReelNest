import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/data/video_nfo_writer.dart';
import 'package:reelnest/features/metadata/domain/nfo_metadata_update.dart';
import 'package:reelnest/platform/atomic_nfo_publish.dart';

void main() {
  late Directory root;
  late File target;
  const original =
      '<movie custom="keep"><title language="zh">Old</title><studio id="42">Studio</studio><uniqueid type="imdb">tt123</uniqueid><!--keep--><plot><![CDATA[old text]]></plot></movie>';
  setUp(() async {
    root = await Directory.systemTemp.createTemp('reelnest-nfo-writer-');
    target = File(p.join(root.path, 'Feature.nfo'));
  });
  tearDown(() async {
    expect(p.isWithin(Directory.systemTemp.path, root.path), isTrue);
    expect(p.basename(root.path), startsWith('reelnest-nfo-writer-'));
    await root.delete(recursive: true);
  });
  Future<NfoWriteResult> write({
    VideoNfoWriter? writer,
    NfoMetadataUpdate? update,
    ScanCancellation? token,
  }) => (writer ?? VideoNfoWriter()).write(
    root: root.path,
    target: target.path,
    rootTag: 'movie',
    fallbackTitle: 'Fallback',
    update: update ?? const NfoMetadataUpdate(title: 'New title'),
    cancellation: token ?? ScanCancellation(),
    validate: () async {},
  );
  Future<List<FileSystemEntity>> artifacts() async =>
      (await root.list().toList())
          .where((e) => p.basename(e.path).contains('.reelnest-nfo'))
          .toList();

  test('native publication creates UTF8 XML then atomically merges existing unknown content', () async {
    var result = await write(
      update: const NfoMetadataUpdate(
        title: '中文 & <Title>',
        overview: 'A < B & C',
        rating: 9.2,
      ),
    );
    expect(result.written, isTrue);
    expect(
      XmlDocument.parse(await target.readAsString()).rootElement
          .findElements('title')
          .single
          .innerText,
      '中文 & <Title>',
    );
    await target.writeAsString(original);
    result = await write(
      update: const NfoMetadataUpdate(
        rating: 9.25,
        externalId: 'tmdb:movie:42',
      ),
    );
    final doc = XmlDocument.parse(await target.readAsString()),
        xml = await target.readAsString();
    expect(doc.rootElement.getAttribute('custom'), 'keep');
    expect(doc.rootElement.findElements('title').single.innerText, 'Old');
    expect(
      doc.rootElement.findElements('title').single.getAttribute('language'),
      'zh',
    );
    expect(
      doc.rootElement.findElements('studio').single.getAttribute('id'),
      '42',
    );
    expect(doc.rootElement.findElements('uniqueid').first.innerText, 'tt123');
    expect(
      doc.rootElement.findElements('uniqueid').last.innerText,
      'tmdb:movie:42',
    );
    expect(xml, contains('<!--keep-->'));
    expect(xml, contains('<![CDATA[old text]]>'));
    expect(result.warning, isNull);
    expect(await artifacts(), isEmpty);
  });
  test(
    'merging updates only the first direct tag and matching TMDB ID',
    () async {
      await target.writeAsString(
        '<movie><title a="b">first</title><title>second</title><nested><title>keep</title></nested><uniqueid type="TMDB" default="true">old</uniqueid></movie>',
      );
      await write(
        update: const NfoMetadataUpdate(
          title: 'new',
          externalId: 'tmdb:movie:2',
        ),
      );
      final doc = XmlDocument.parse(await target.readAsString());
      expect(doc.rootElement.findElements('title').map((e) => e.innerText), [
        'new',
        'second',
      ]);
      expect(
        doc.rootElement
            .findElements('nested')
            .single
            .findElements('title')
            .single
            .innerText,
        'keep',
      );
      expect(
        doc.rootElement.findElements('uniqueid').single.getAttribute('default'),
        'true',
      );
    },
  );
  test('new documents use fallback titles and omit invalid ratings', () async {
    final xml = utf8.decode(
      mergeNfo(
        null,
        'tvshow',
        'Show & title',
        const NfoMetadataUpdate(rating: double.infinity),
      ),
    );
    final doc = XmlDocument.parse(xml);
    expect(doc.rootElement.name.qualified, 'tvshow');
    expect(
      doc.rootElement.findElements('title').single.innerText,
      'Show & title',
    );
    expect(doc.rootElement.findElements('rating'), isEmpty);
  });
  for (final input in [
    '<movie><title>broken',
    '<tvshow/>',
    '<movie/><movie/>',
    '<!DOCTYPE movie [<!ENTITY xxe SYSTEM "file:///secret">]><movie>&xxe;</movie>',
  ]) {
    test('unsafe or incompatible XML is never overwritten: $input', () async {
      await target.writeAsString(input);
      await expectLater(write(), throwsA(isA<SourceFailure>()));
      expect(await target.readAsString(), input);
      expect(await artifacts(), isEmpty);
    });
  }
  test('large existing NFO is rejected before staging replacement', () async {
    final file = await target.open(mode: FileMode.write);
    await file.truncate(VideoNfoWriter.maximumBytes + 1);
    await file.close();
    await expectLater(write(), throwsA(isA<SourceFailure>()));
    expect(await target.length(), VideoNfoWriter.maximumBytes + 1);
    expect(await artifacts(), isEmpty);
  });
  test('external edits before commit win with no orphan artifacts', () async {
    await target.writeAsString(original);
    final writer = VideoNfoWriter(
      beforeCommit: () async {
        await target.writeAsString('<movie><title>External</title></movie>');
      },
    );
    await expectLater(write(writer: writer), throwsA(isA<SourceFailure>()));
    expect(await target.readAsString(), contains('External'));
    expect(await artifacts(), isEmpty);
  });
  test('external removal before commit is not undone', () async {
    await target.writeAsString(original);
    await expectLater(
      write(writer: VideoNfoWriter(beforeCommit: target.delete)),
      throwsA(isA<SourceFailure>()),
    );
    expect(await target.exists(), isFalse);
    expect(await artifacts(), isEmpty);
  });
  test('target symlink cannot overwrite its destination', () async {
    final outside = await File(p.join(root.path, 'Other.nfo'))
        .writeAsString('other');
    final link = Link(target.path);
    await link.create(outside.path);
    try {
      await expectLater(write(), throwsA(isA<SourceFailure>()));
      expect(await outside.readAsString(), 'other');
    } finally {
      await link.delete();
    }
  });
  test(
    'a parent replaced by a directory link cannot redirect writes or cleanup',
    () async {
      final inside = await Directory(p.join(root.path, 'inside')).create();
      final outside = await Directory(p.join(root.path, 'outside')).create();
      target = File(p.join(inside.path, 'Feature.nfo'));
      await target.writeAsString(original);
      final external = File(p.join(outside.path, 'Feature.nfo'));
      await external.writeAsString('external');
      final moved = p.join(root.path, 'moved');
      final link = Link(inside.path);
      final writer = VideoNfoWriter(
        beforeCommit: () async {
          await inside.rename(moved);
          await link.create(outside.path);
        },
      );
      try {
        await expectLater(write(writer: writer), throwsA(isA<SourceFailure>()));
        expect(await external.readAsString(), 'external');
        expect(
          await File(p.join(moved, 'Feature.nfo')).readAsString(),
          original,
        );
      } finally {
        if (await link.exists()) await link.delete();
      }
    },
  );

  test(
    'cancel before commit preserves original and cleans staged bytes',
    () async {
      await target.writeAsString(original);
      final token = ScanCancellation();
      await expectLater(
        write(
          token: token,
          writer: VideoNfoWriter(
            beforeCommit: () async {
              token.cancel();
            },
          ),
        ),
        throwsA(isA<ScanCancelled>()),
      );
      expect(await target.readAsString(), original);
      expect(await artifacts(), isEmpty);
    },
  );
  test('cancelled queued write returns promptly and does not poison target coordination', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    final writer = VideoNfoWriter(
      beforeCommit: () async {
        if (!entered.isCompleted) {
          entered.complete();
          await gate.future;
        }
      },
    );
    final first = write(writer: writer);
    await entered.future;
    final token = ScanCancellation();
    final second = write(writer: writer, token: token);
    token.cancel();
    await expectLater(
      second.timeout(const Duration(seconds: 1)),
      throwsA(isA<ScanCancelled>()),
    );
    gate.complete();
    await first;
    await write(
      writer: writer,
      update: const NfoMetadataUpdate(title: 'Third'),
    );
    expect(await target.readAsString(), contains('Third'));
    expect(await artifacts(), isEmpty);
  });
  test('replacement failure before mutation preserves original', () async {
    await target.writeAsString(original);
    await expectLater(
      write(writer: VideoNfoWriter(publish: (_, _, _) async => false)),
      throwsA(isA<SourceFailure>()),
    );
    expect(await target.readAsString(), original);
    expect(await artifacts(), isEmpty);
  });
  for (final recover in [true, false]) {
    test(
      'partial native failure retains recovery material, recover=$recover',
      () async {
        await target.writeAsString(original);
        final writer = VideoNfoWriter(
          publish: (temporary, path, backup) async {
            if (backup != null) {
              await File(path).rename(backup);
              return false;
            }
            return recover ? publishNfo(temporary, path, null) : false;
          },
        );
        await expectLater(write(writer: writer), throwsA(isA<SourceFailure>()));
        if (recover) {
          expect(await target.readAsString(), original);
          expect(await artifacts(), isEmpty);
        } else {
          expect(await target.exists(), isFalse);
          final backups = await artifacts();
          expect(backups, hasLength(1));
          expect(await File(backups.single.path).readAsString(), original);
        }
      },
    );
  }
  test(
    'external edit after replacement wins and original backup stays available',
    () async {
      await target.writeAsString(original);
      final writer = VideoNfoWriter(
        publish: (temporary, path, backup) async {
          final result = await publishNfo(temporary, path, backup);
          await File(path)
              .writeAsString('<movie><title>External after</title></movie>');
          return result;
        },
      );
      await expectLater(write(writer: writer), throwsA(isA<SourceFailure>()));
      expect(await target.readAsString(), contains('External after'));
      expect(
        await File((await artifacts()).single.path).readAsString(),
        original,
      );
    },
  );
  test('read-only target is retained with a distinct warning', () async {
    await target.writeAsString(original);
    if (Platform.isWindows) {
      await Process.run('attrib', ['+R', target.path]);
    } else {
      await Process.run('chmod', ['444', target.path]);
    }
    try {
      final result = await write();
      expect(result.written, isFalse);
      expect(result.warning, isNotNull);
      expect(await target.readAsString(), original);
    } finally {
      if (Platform.isWindows) {
        await Process.run('attrib', ['-R', target.path]);
      } else {
        await Process.run('chmod', ['644', target.path]);
      }
    }
  });
}
