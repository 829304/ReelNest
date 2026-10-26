import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/data/online_subtitle_payload.dart';
import 'package:reelnest/features/playback/data/online_subtitle_service.dart';
import 'package:reelnest/features/playback/data/online_subtitle_settings_repository.dart';
import 'package:reelnest/features/playback/data/online_subtitle_store.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/online_subtitle.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

const _srt = '1\n00:00:01,000 --> 00:00:03,000\n字幕\n';
Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));
const _settings = OnlineSubtitleSettings(apiKey: 'fixture-secret');
const _query = OnlineSubtitleQuery(
  title: 'Film & Show',
  year: 2026,
  imdbID: 'tt123',
  season: 2,
  episode: 3,
);
const _result = OnlineSubtitleResult(
  id: 'os-one',
  provider: OnlineSubtitleProvider.openSubtitles,
  fileId: 42,
  displayName: 'Film',
  language: 'zh-CN',
);
const _pod =
    '<results><subtitle><id>7</id><release>Ｆílm.srt</release><language>zh</language><downloads>20</downloads></subtitle></results>';
String _jsonResults([String name = 'film.srt']) => jsonEncode({
  'data': [
    {
      'id': 'one',
      'attributes': {
        'files': [
          {'file_id': 42, 'file_name': name},
        ],
        'language': 'zh-CN',
        'download_count': 4,
      },
    },
  ],
});

class _Store implements CredentialStore {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('private path / secret');
    this.value = value;
  }

  @override
  Future<void> clear() async => value = null;
}

// Minimal single-member ZIP fixture; all metadata is independently mutable to
// exercise the archive boundary checks rather than using the production parser.
Uint8List _zip(
  String name,
  Uint8List contents, {
  bool deflate = false,
  int flags = 0,
  int? declaredSize,
  int? crcOverride,
}) {
  final filename = utf8.encode(name);
  final packed = deflate ? ZLibEncoder(raw: true).convert(contents) : contents;
  var crc = 0xffffffff;
  for (final byte in contents) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320;
    }
  }
  crc = crcOverride ?? (crc ^ 0xffffffff);
  final local = ByteData(30), central = ByteData(46), end = ByteData(22);
  void u16(ByteData data, int at, int value) =>
      data.setUint16(at, value, Endian.little);
  void u32(ByteData data, int at, int value) =>
      data.setUint32(at, value, Endian.little);
  u32(local, 0, 0x04034b50);
  u16(local, 4, 20);
  u16(local, 6, flags);
  u16(local, 8, deflate ? 8 : 0);
  u32(local, 14, crc);
  u32(local, 18, packed.length);
  u32(local, 22, declaredSize ?? contents.length);
  u16(local, 26, filename.length);
  u32(central, 0, 0x02014b50);
  u16(central, 4, 20);
  u16(central, 6, 20);
  u16(central, 8, flags);
  u16(central, 10, deflate ? 8 : 0);
  u32(central, 16, crc);
  u32(central, 20, packed.length);
  u32(central, 24, declaredSize ?? contents.length);
  u16(central, 28, filename.length);
  u32(end, 0, 0x06054b50);
  u16(end, 8, 1);
  u16(end, 10, 1);
  u32(end, 12, 46 + filename.length);
  u32(end, 16, 30 + filename.length + packed.length);
  return (BytesBuilder()
        ..add(local.buffer.asUint8List())
        ..add(filename)
        ..add(packed)
        ..add(central.buffer.asUint8List())
        ..add(filename)
        ..add(end.buffer.asUint8List()))
      .takeBytes();
}

void main() {
  group('settings and atomic sidecars', () {
    late LibraryDatabase database;
    late _Store store;
    late OnlineSubtitleSettingsRepository settings;
    setUp(() {
      database = LibraryDatabase(NativeDatabase.memory());
      store = _Store();
      settings = OnlineSubtitleSettingsRepository(
        PlayerPreferencesRepository(database),
        store: store,
      );
    });
    tearDown(() => database.close());
    test(
      'key remains outside SQLite and writes preserve the last completed draft',
      () async {
        expect((await settings.read()).language, 'zh-CN');
        await Future.wait([
          settings.save(language: 'en', apiKey: 'first-secret'),
          settings.save(language: ' zh-TW ', apiKey: ' last-secret '),
        ]);
        expect((await settings.read()).language, 'zh-TW');
        expect(store.value, 'last-secret');
        expect(
          (await settings.read()).toString(),
          isNot(contains('last-secret')),
        );
        final rows = await database
            .customSelect('SELECT value FROM player_preferences')
            .get();
        expect(
          rows.map((row) => row.data.toString()).join(),
          isNot(contains('secret')),
        );
        await settings.save(language: '', apiKey: '');
        expect(store.value, isNull);
        expect((await settings.read()).language, 'zh-CN');
      },
    );
    test(
      'database failure restores the previous key and queue remains reusable',
      () async {
        await settings.save(language: 'en', apiKey: 'original');
        await database.customStatement(
          "CREATE TRIGGER reject_language BEFORE UPDATE ON player_preferences BEGIN SELECT RAISE(ABORT, 'fixture'); END",
        );
        await database.customStatement(
          "CREATE TRIGGER reject_insert BEFORE INSERT ON player_preferences BEGIN SELECT RAISE(ABORT, 'fixture'); END",
        );
        await expectLater(
          settings.save(language: 'ja', apiKey: 'new'),
          throwsA(isA<OnlineSubtitleFailure>()),
        );
        expect(store.value, 'original');
        expect((await settings.read()).language, 'en');
        await database.customStatement('DROP TRIGGER reject_language');
        await database.customStatement('DROP TRIGGER reject_insert');
        await settings.save(language: 'ja', apiKey: 'new');
        expect(store.value, 'new');
      },
    );
    test(
      'invalid header and credential write failure do not change language',
      () async {
        await expectLater(
          settings.save(language: 'en', apiKey: 'key\r\ninjected'),
          throwsA(isA<OnlineSubtitleFailure>()),
        );
        store.failWrite = true;
        await expectLater(
          settings.save(language: 'en', apiKey: 'secret'),
          throwsA(isA<OnlineSubtitleFailure>()),
        );
        expect((await settings.read()).language, 'zh-CN');
      },
    );
    test(
      'validated replacement is atomic, cancellation/failure preserve original',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'reelnest-subtitle-store-test-',
        );
        try {
          final target = File(p.join(root.path, 'Film.srt'));
          await target.writeAsString('original');
          final storage = OnlineSubtitleStore();
          final payload = OnlineSubtitlePayload(_bytes(_srt), 'srt');
          final cancelled = ScanCancellation()..cancel();
          await expectLater(
            storage.save(payload, target.path, cancelled),
            throwsA(isA<ScanCancelled>()),
          );
          expect(await target.readAsString(), 'original');
          await expectLater(
            storage.save(
              OnlineSubtitlePayload(_bytes('<html>error</html>'), 'srt'),
              target.path,
              ScanCancellation(),
            ),
            throwsA(isA<OnlineSubtitleFailure>()),
          );
          expect(await target.readAsString(), 'original');
          await storage.save(payload, target.path, ScanCancellation());
          expect(await target.readAsString(), _srt);
          expect(await root.list().length, 1);
          await expectLater(
            storage.save(
              payload,
              p.join(root.path, 'missing', 'Film.srt'),
              ScanCancellation(),
            ),
            throwsA(isA<OnlineSubtitleFailure>()),
          );
          expect(await root.list().length, 1);
        } finally {
          expect(
            p.basename(root.path),
            startsWith('reelnest-subtitle-store-test-'),
          );
          await root.delete(recursive: true);
        }
      },
    );
  });

  group('bounded subtitle decoding', () {
    Future<OnlineSubtitlePayload> decode(Uint8List bytes, {String? filename}) =>
        OnlineSubtitlePayload.decode(
          bytes,
          filename: filename,
          cancellation: ScanCancellation(),
        );
    for (final deflate in [false, true]) {
      test(
        'ZIP selects a text member without extracting provider paths ($deflate)',
        () async {
          final payload = await decode(
            _zip(
              'nested/Film.ass',
              _bytes('[Script Info]\n[Events]\n'),
              deflate: deflate,
            ),
          );
          expect(payload.extension, 'ass');
          expect(utf8.decode(payload.bytes), '[Script Info]\n[Events]\n');
        },
      );
    }
    test('gzip retains inner extension and bytes', () async {
      final payload = await decode(
        Uint8List.fromList(gzip.encode(_bytes(_srt))),
        filename: 'Film.vtt.gz',
      );
      expect(payload.extension, 'vtt');
      expect(payload.bytes, _bytes(_srt));
    });
    for (final name in [
      '../Film.srt',
      '/Film.srt',
      r'C:\Film.srt',
      r'..\Film.srt',
      'Film.exe',
    ]) {
      test('rejects unsafe or non-subtitle archive member $name', () async {
        await expectLater(
          decode(_zip(name, _bytes(_srt))),
          throwsA(isA<OnlineSubtitleFailure>()),
        );
      });
    }
    test(
      'rejects encryption, corruption, mismatched size and truncated ZIP',
      () async {
        for (final zip in [
          _zip('Film.srt', _bytes(_srt), flags: 1),
          _zip('Film.srt', _bytes(_srt), crcOverride: 0),
          _zip('Film.srt', _bytes(_srt), declaredSize: 3),
          Uint8List.fromList([80, 75, 3, 4]),
        ]) {
          await expectLater(decode(zip), throwsA(isA<OnlineSubtitleFailure>()));
        }
      },
    );
    test(
      'rejects oversized output even when compressed metadata lies',
      () async {
        final large = Uint8List(OnlineSubtitlePayload.maxTextBytes + 1)
          ..fillRange(0, OnlineSubtitlePayload.maxTextBytes + 1, 65);
        await expectLater(
          decode(_zip('Film.srt', large, deflate: true, declaredSize: 10)),
          throwsA(isA<OnlineSubtitleFailure>()),
        );
        await expectLater(
          decode(Uint8List.fromList(gzip.encode(large))),
          throwsA(isA<OnlineSubtitleFailure>()),
        );
      },
    );
    test(
      'accepts legacy and UTF16 text, refuses HTML/binary/empty/nested ZIP',
      () async {
        final utf16 = ByteData(2 + _srt.length * 2)
          ..setUint16(0, 0xfeff, Endian.little);
        for (var n = 0; n < _srt.length; n++) {
          utf16.setUint16(2 + n * 2, _srt.codeUnitAt(n), Endian.little);
        }
        expect(
          (await decode(utf16.buffer.asUint8List())).bytes,
          utf16.buffer.asUint8List(),
        );
        final legacy = Uint8List.fromList([
          ...ascii.encode('1\n00:00:01,000 --> 00:00:03,000\n'),
          0xff,
        ]);
        expect((await decode(legacy)).bytes, legacy);
        for (final invalid in [
          Uint8List(0),
          _bytes('<html><!-- --> --></html>'),
          Uint8List.fromList([0, 1, 2]),
          _zip('Film.srt', _zip('nested.srt', _bytes(_srt))),
        ]) {
          await expectLater(
            decode(invalid),
            throwsA(isA<OnlineSubtitleFailure>()),
          );
        }
      },
    );
    test(
      'all original extensions are preserved; unknown extension uses SRT',
      () {
        for (final ext in OnlineSubtitlePayload.extensions) {
          expect(
            OnlineSubtitlePayload.extensionFor(
              'untrusted/path/FILM.${ext.toUpperCase()}',
            ),
            ext,
          );
        }
        expect(OnlineSubtitlePayload.extensionFor('secret.exe'), 'srt');
      },
    );
  });

  test('TTML namespace/line breaks and textual SUB variants are accepted', () async {
    for (final item in [
      ('<tt\n xmlns="http://www.w3.org/ns/ttml"><body/></tt>', 'ttml'),
      (
        '<tt:tt xmlns:tt="http://www.w3.org/ns/ttml"><tt:body/></tt:tt>',
        'dfxp',
      ),
      (
        '[INFORMATION]\n[TITLE]Film\n[SUBTITLE]\n00:00:01.00,00:00:03.00\nText',
        'sub',
      ),
      ('[10][30]Text', 'sub'),
    ]) {
      final payload = await OnlineSubtitlePayload.decode(
        _bytes(item.$1),
        filename: 'Film.${item.$2}',
        cancellation: ScanCancellation(),
      );
      expect(payload.extension, item.$2);
    }
  });

  group('HTTP provider contracts', () {
    late HttpServer api, files;
    late Uri base, fileBase;
    late Future<void> Function(HttpRequest) handler;
    late Future<void> Function(HttpRequest) fileHandler;
    late OnlineSubtitleService service;
    setUp(() async {
      api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      files = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri.parse('http://127.0.0.1:${api.port}/');
      fileBase = Uri.parse('http://127.0.0.1:${files.port}/');
      service = OnlineSubtitleService(
        openSubtitlesBase: base.resolve('api/v1/'),
        podnapisiBase: base,
        allowInsecureForTesting: true,
        timeout: const Duration(milliseconds: 500),
      );
      handler = (r) async {
        r.response.write(r.uri.path == '/api/search/1' ? _pod : _jsonResults());
        await r.response.close();
      };
      fileHandler = (r) async {
        r.response.write(_srt);
        await r.response.close();
      };
      api.listen((r) async {
        try {
          await handler(r);
        } catch (_) {
          await r.response.close();
        }
      });
      files.listen((r) async {
        try {
          await fileHandler(r);
        } catch (_) {
          await r.response.close();
        }
      });
    });
    tearDown(() async {
      await api.close(force: true);
      await files.close(force: true);
    });
    test('searches in parallel with original query, language and Unicode dedup order', () async {
      final requests = <HttpRequest>[];
      final bothStarted = Completer<void>();
      handler = (r) async {
        requests.add(r);
        if (requests.length == 2) bothStarted.complete();
        await bothStarted.future;
        if (r.uri.path == '/api/v1/subtitles') {
          expect(r.headers.value('Api-Key'), 'fixture-secret');
          expect(r.uri.queryParameters, containsPair('languages', 'zh-cn'));
          expect(r.uri.queryParameters, containsPair('imdb_id', '123'));
          expect(r.uri.queryParameters, containsPair('season_number', '2'));
          expect(r.uri.queryParameters, containsPair('episode_number', '3'));
          expect(r.uri.queryParameters, containsPair('year', '2026'));
          r.response.write(_jsonResults());
        } else {
          expect(r.headers.value('Api-Key'), isNull);
          expect(r.uri.queryParameters, {
            'keywords': 'Film & Show',
            'language': 'zh',
          });
          r.response.write(_pod);
        }
        expect(
          r.headers.value(HttpHeaders.userAgentHeader),
          startsWith('ReelNest'),
        );
        await r.response.close();
      };
      final found = await service.search(_query, _settings, ScanCancellation());
      expect(found.results.single.provider, OnlineSubtitleProvider.podnapisi);
      expect(found.warnings, isEmpty);
    });
    test('no key skips OpenSubtitles; one provider failure preserves successful results', () async {
      var calls = 0;
      handler = (r) async {
        calls++;
        expect(r.uri.path, '/api/search/1');
        r.response.write(_pod);
        await r.response.close();
      };
      expect(
        (await service.search(
          _query,
          const OnlineSubtitleSettings(),
          ScanCancellation(),
        )).results.length,
        1,
      );
      expect(calls, 1);
      handler = (r) async {
        if (r.uri.path == '/api/search/1') {
          r.response.statusCode = 503;
        } else {
          r.response.write(_jsonResults('different.srt'));
        }
        await r.response.close();
      };
      final found = await service.search(_query, _settings, ScanCancellation());
      expect(
        found.results.single.provider,
        OnlineSubtitleProvider.openSubtitles,
      );
      expect(found.warnings.single, contains('Podnapisi'));
    });
    test(
      'OS metadata POST uses key; signed file redirect never receives key',
      () async {
        var downloaded = 0;
        handler = (r) async {
          expect(r.uri.path, '/api/v1/download');
          expect(r.method, 'POST');
          expect(r.headers.value('Api-Key'), 'fixture-secret');
          expect(jsonDecode(await utf8.decoder.bind(r).join()), {
            'file_id': 42,
          });
          r.response.write(
            jsonEncode({
              'link': fileBase.resolve('signed?token=private').toString(),
              'file_name': '../../Film.ass',
            }),
          );
          await r.response.close();
        };
        fileHandler = (r) async {
          expect(r.headers.value('Api-Key'), isNull);
          downloaded++;
          if (r.uri.path == '/signed') {
            r.response.statusCode = 302;
            r.response.headers.set('location', '/actual');
          } else {
            r.response.write('[Script Info]\n[Events]\n');
          }
          await r.response.close();
        };
        final payload = await service.download(
          _result,
          _settings,
          ScanCancellation(),
        );
        expect(payload.extension, 'ass');
        expect(downloaded, 2);
      },
    );
    test(
      'cross origin API redirect strips key even after redirecting back',
      () async {
        handler = (r) async {
          if (r.uri.path == '/api/v1/download') {
            expect(r.headers.value('Api-Key'), 'fixture-secret');
            r.response.statusCode = 307;
            r.response.headers.set('location', fileBase.resolve('bounce'));
          } else {
            expect(r.headers.value('Api-Key'), isNull);
            r.response.write(
              jsonEncode({
                'link': fileBase.resolve('file').toString(),
                'file_name': 'Film.srt',
              }),
            );
          }
          await r.response.close();
        };
        fileHandler = (r) async {
          expect(r.headers.value('Api-Key'), isNull);
          if (r.uri.path == '/bounce') {
            r.response.statusCode = 307;
            r.response.headers.set('location', base.resolve('returned'));
          } else {
            r.response.write(_srt);
          }
          await r.response.close();
        };
        expect(
          (await service.download(
            _result,
            _settings,
            ScanCancellation(),
          )).bytes,
          _bytes(_srt),
        );
      },
    );
    test('quota and malformed downloads expose only safe errors', () async {
      for (final status in [406, 429, 401, 500]) {
        handler = (r) async {
          r.response.statusCode = status;
          r.response.write('fixture-secret token private path');
          await r.response.close();
        };
        await expectLater(
          service.download(_result, _settings, ScanCancellation()),
          throwsA(
            isA<OnlineSubtitleFailure>().having(
              (e) => e.message,
              'safe',
              isNot(contains('fixture-secret')),
            ),
          ),
        );
      }
      handler = (r) async {
        r.response.write(jsonEncode({'link': 'file:///private/subtitle.srt'}));
        await r.response.close();
      };
      await expectLater(
        service.download(_result, _settings, ScanCancellation()),
        throwsA(isA<OnlineSubtitleFailure>()),
      );
    });
    test(
      'search rejects HTML/XML entities and malformed JSON with useful warning',
      () async {
        handler = (r) async {
          r.response.write(
            r.uri.path == '/api/search/1'
                ? '<html><body>error</body></html>'
                : 'not json',
          );
          await r.response.close();
        };
        final result = await service.search(
          _query,
          _settings,
          ScanCancellation(),
        );
        expect(result.results, isEmpty);
        expect(result.warnings.length, 2);
        expect(
          () => OnlineSubtitleService.parsePodnapisi(
            _bytes('<!DOCTYPE results [<!ENTITY x "x">]><results/>'),
            'en',
          ),
          throwsFormatException,
        );
      },
    );
    test('streamed oversized response stops at limit instead of reading whole body', () async {
      handler = (r) async {
        r.response.contentLength = 3 * 1024 * 1024;
        r.response.add([65]);
        await r.response.flush();
        await Future<void>.delayed(const Duration(seconds: 1));
      };
      final stopwatch = Stopwatch()..start();
      final found = await service.search(
        _query,
        const OnlineSubtitleSettings(),
        ScanCancellation(),
      );
      expect(found.warnings.single, contains('响应过大'));
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      handler = (r) async {
        r.response.add(List.filled(2 * 1024 * 1024 + 1, 65));
        await r.response.close();
      };
      expect(
        (await service.search(
          _query,
          const OnlineSubtitleSettings(),
          ScanCancellation(),
        )).warnings.single,
        contains('响应过大'),
      );
    });
    test(
      'timeout and explicit cancellation cover waiting for response headers',
      () async {
        final arrived = Completer<void>();
        handler = (r) async {
          if (!arrived.isCompleted) arrived.complete();
          await Future<void>.delayed(const Duration(seconds: 1));
        };
        final token = ScanCancellation();
        final pending = service.search(_query, _settings, token);
        final expected = expectLater(pending, throwsA(isA<ScanCancelled>()));
        await arrived.future;
        token.cancel();
        await expected;
        final found = await service.search(
          _query,
          const OnlineSubtitleSettings(),
          ScanCancellation(),
        );
        expect(found.warnings.single, contains('超时'));
      },
    );
    test('redirect loop is bounded', () async {
      var requests = 0;
      handler = (r) async {
        requests++;
        r.response.statusCode = 302;
        r.response.headers.set('location', r.uri.toString());
        await r.response.close();
      };
      final found = await service.search(
        _query,
        const OnlineSubtitleSettings(),
        ScanCancellation(),
      );
      expect(requests, 5);
      expect(found.warnings.single, contains('重定向失败'));
    });
  });
}
