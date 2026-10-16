import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/player/playback_diagnostics.dart';
import 'package:reelnest/player/video_load_monitor.dart';

void main() {
  test('generic final error cannot mask an earlier HTTP status', () {
    final issue = PlaybackIssue.prefer(
      const PlaybackIssue('http', status: 403),
      const PlaybackIssue('backend'),
    );
    expect(issue.status, 403);
    expect(issue.code, 'http');
  });
  test(
    'native probe accepts video parameters and handles unavailable audio',
    () async {
      final snapshot = await readVideoLoadSnapshot(
        property: (key) async => switch (key) {
          'idle-active' => 'no',
          'video-params' => '{"w":1920,"h":1080}',
          _ => '',
        },
        duration: () => Duration.zero,
        checkAlive: () {},
      );
      expect(snapshot.ready, isTrue);
    },
  );

  test(
    'cancel during native query prevents subsequent property commands',
    () async {
      final probe = Completer<String>();
      var cancelled = false;
      final reads = <String>[];
      final result = readVideoLoadSnapshot(
        property: (key) {
          reads.add(key);
          return probe.future;
        },
        duration: () => Duration.zero,
        checkAlive: () {
          if (cancelled) throw const PlaybackIssue('cancelled');
        },
      );
      cancelled = true;
      final check = expectLater(result, throwsA(isA<PlaybackIssue>()));
      probe.complete('no');
      await check;
      expect(reads, ['idle-active']);
    },
  );

  test(
    'valid audio/video streams need not advertise a total duration',
    () async {
      for (final video in [true, false]) {
        final monitor = VideoLoadMonitor(
          timeout: const Duration(milliseconds: 50),
        );
        await monitor.wait(
          read: () async =>
              VideoLoadSnapshot(idle: false, hasVideo: video, hasAudio: !video),
          backendIssue: () => null,
        );
      }
    },
  );

  test(
    'decoder fallback error does not reject an active valid stream',
    () async {
      final monitor = VideoLoadMonitor();
      await monitor.wait(
        read: () async => const VideoLoadSnapshot(idle: false, hasVideo: true),
        backendIssue: () => const PlaybackIssue('decoder'),
      );
    },
  );

  test(
    'metadata duration alone cannot make an idle failed player ready',
    () async {
      final monitor = VideoLoadMonitor();
      await expectLater(
        monitor.wait(
          read: () async => const VideoLoadSnapshot(
            idle: true,
            duration: Duration(minutes: 90),
          ),
          backendIssue: () => const PlaybackIssue('http', status: 403),
        ),
        throwsA(isA<PlaybackIssue>().having((e) => e.status, 'status', 403)),
      );
    },
  );

  test(
    'unready stream times out even when a property read never returns',
    () async {
      final monitor = VideoLoadMonitor(
        timeout: const Duration(milliseconds: 25),
      );
      await expectLater(
        monitor.wait(
          read: () => Completer<VideoLoadSnapshot>().future,
          backendIssue: () => null,
        ),
        throwsA(isA<PlaybackIssue>().having((e) => e.code, 'code', 'timeout')),
      );
    },
  );

  test(
    'cancel interrupts a pending probe and ignores its later result',
    () async {
      final monitor = VideoLoadMonitor();
      final probe = Completer<VideoLoadSnapshot>();
      final waiting = monitor.wait(
        read: () => probe.future,
        backendIssue: () => null,
      );
      final check = expectLater(
        waiting,
        throwsA(
          isA<PlaybackIssue>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      monitor.cancel();
      await check;
      probe.complete(const VideoLoadSnapshot(idle: false, hasVideo: true));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('an initially unready stream can become ready without a second duration event', () async {
    final monitor = VideoLoadMonitor();
    var reads = 0;
    await monitor.wait(
      read: () async => VideoLoadSnapshot(idle: false, hasVideo: ++reads == 2),
      backendIssue: () => null,
      interval: const Duration(milliseconds: 1),
    );
    expect(reads, 2);
  });

  test(
    'HTTP/network/decoder classifications never retain the backend message',
    () {
      const sensitive = ' https://private.example/movie.mkv?api_key=secret';
      for (final (text, expected) in [
        ('HTTP error 401$sensitive', 'http'),
        ('Server returned 503$sensitive', 'http'),
        ('Connection timed out$sensitive', 'timeout'),
        ('TCP: Connection refused$sensitive', 'network'),
        ('certificate validation failed$sensitive', 'tls'),
        ('Cannot resolve hostname$sensitive', 'dns'),
        ('Failed to initialize decoder$sensitive', 'decoder'),
      ]) {
        final issue = PlaybackIssue.backend(text);
        expect(issue.code, expected);
        expect(issue.toString(), isNot(contains('secret')));
        expect(issue.message, isNot(contains('private.example')));
      }
    },
  );

  group('disk diagnostics', () {
    late Directory sandbox;
    late PlaybackDiagnostics diagnostics;
    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('reelnest-diagnostics-');
      diagnostics = PlaybackDiagnostics(
        directory: () async => sandbox,
        writerId: '123-456',
      );
    });
    tearDown(() async {
      await diagnostics.close();
      await sandbox.delete(recursive: true);
    });

    test('success and failure share an attempt and preserve safe source locations only', () async {
      final trace = diagnostics.begin();
      trace.stage('decoder_load');
      trace.event('backend_error', code: 'http', status: 403);
      trace.failure(
        'open_failed',
        StateError('https://server/movie?api_key=secret'),
        StackTrace.fromString(
          '#0 open (package:reelnest/player/media_kit_video_engine.dart:310:8)\n'
          '#1 native (file:///C:/Users/private/movie.mkv:12:3)\n'
          '#2 read (dart:async/future.dart:77:2)',
        ),
      );
      final another = diagnostics.begin();
      another.event('open_succeeded');
      await diagnostics.flush();
      final text = await File(p.join(sandbox.path, 'playback-123-456.jsonl'))
          .readAsString();
      for (final secret in [
        'secret',
        'server',
        'private',
        'movie.mkv',
        'file:///',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      final rows = const LineSplitter()
          .convert(text)
          .map((line) => jsonDecode(line) as Map)
          .toList();
      final failure = rows.singleWhere((row) => row['event'] == 'open_failed');
      expect(failure['attempt'], trace.id);
      expect(failure['stage'], 'decoder_load');
      expect(failure['exception'], 'StateError');
      expect(failure['stack'], [
        'package:reelnest/player/media_kit_video_engine.dart:310:8',
        'dart:async/future.dart:77:2',
      ]);
      expect(another.id, isNot(trace.id));
    });

    test(
      'rolling logs have a bounded previous file and clear old sessions only',
      () async {
        await diagnostics.close();
        diagnostics = PlaybackDiagnostics(
          directory: () async => sandbox,
          maxBytes: 200,
          maxFiles: 3,
          writerId: '123-456',
        );
        final old = File(p.join(sandbox.path, 'playback-99-100.jsonl'));
        await old.writeAsString('old');
        await old.setLastModified(
          DateTime.now().subtract(const Duration(days: 8)),
        );
        final unrelated = File(p.join(sandbox.path, 'keep.txt'));
        await unrelated.writeAsString('unrelated');
        final trace = diagnostics.begin();
        for (var i = 0; i < 10; i++) {
          trace.event('backend_warning', code: 'network');
        }
        await diagnostics.flush();
        final current = File(p.join(sandbox.path, 'playback-123-456.jsonl'));
        final previous = File('${current.path}.previous');
        expect(await current.exists(), isTrue);
        expect(await previous.exists(), isTrue);
        expect(await current.length(), lessThan(600));
        expect(await previous.length(), lessThan(600));
        expect(await old.exists(), isFalse);
        expect(await unrelated.readAsString(), 'unrelated');
      },
    );

    test('an unavailable log directory cannot throw into playback', () async {
      await diagnostics.close();
      final blocked = File(p.join(sandbox.path, 'blocked'));
      await blocked.writeAsString('file');
      diagnostics = PlaybackDiagnostics(
        directory: () async => Directory(blocked.path),
      );
      diagnostics.begin().failure(
        'open_failed',
        TimeoutException('secret'),
        StackTrace.current,
      );
      await diagnostics.flush();
    });

    test('close flushes queued events and rejects subsequent writes', () async {
      final trace = diagnostics.begin();
      trace.event('open_succeeded');
      await diagnostics.close();
      trace.event('ignored_after_close');
      await diagnostics.flush();
      final text = await File(p.join(sandbox.path, 'playback-123-456.jsonl'))
          .readAsString();
      expect(text, contains('open_succeeded'));
      expect(text, isNot(contains('ignored_after_close')));
    });
  });
}
