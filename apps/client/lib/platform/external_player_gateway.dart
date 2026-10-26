import 'dart:ffi';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../domain/media_source.dart';
import '../features/playback/domain/external_player_settings.dart';

abstract interface class ExternalPlayerGateway {
  Future<void> validateApplication(String path);
  Future<List<ExternalPlayerApplication>> availablePlayers({
    String? customPath,
  });
  Future<void> launch(String location, {String? applicationPath});
}

class DesktopExternalPlayerGateway implements ExternalPlayerGateway {
  static const _channel = MethodChannel('reelnest/external_player');
  @override
  Future<void> validateApplication(String path) async {
    if (!p.isAbsolute(path) || path.contains('\u0000')) {
      throw const SourceFailure('请选择播放器应用的完整路径。');
    }
    if (p.equals(p.normalize(path), p.normalize(Platform.resolvedExecutable))) {
      throw const SourceFailure('请选择其他播放器，不能将 ReelNest 作为外部播放器。');
    }
    final type = await FileSystemEntity.type(path);
    if (Platform.isMacOS) {
      if (type != FileSystemEntityType.directory ||
          p.extension(path).toLowerCase() != '.app') {
        throw const SourceFailure('请选择有效的播放器应用（.app）。');
      }
    } else {
      if (type != FileSystemEntityType.file ||
          (Platform.isWindows && p.extension(path).toLowerCase() != '.exe')) {
        throw const SourceFailure('播放器程序不存在，请重新选择。');
      }
      if (p.equals(
        await File(path).resolveSymbolicLinks(),
        await File(Platform.resolvedExecutable).resolveSymbolicLinks(),
      )) {
        throw const SourceFailure('请选择其他播放器，不能将 ReelNest 作为外部播放器。');
      }
      if (Platform.isLinux && ((await File(path).stat()).mode & 0x49) == 0) {
        throw const SourceFailure('所选播放器程序没有执行权限。');
      }
    }
  }

  @override
  Future<List<ExternalPlayerApplication>> availablePlayers({
    String? customPath,
  }) async {
    final found = <ExternalPlayerApplication>[];
    if (Platform.isMacOS) {
      final values = await _channel.invokeListMethod<dynamic>(
        'availablePlayers',
      );
      for (final value in values ?? const []) {
        final entry = value as Map;
        found.add(
          ExternalPlayerApplication(
            name: entry['name'] as String,
            path: entry['path'] as String,
          ),
        );
      }
    } else {
      final paths = Platform.isWindows
          ? [
              for (final root in [
                Platform.environment['ProgramFiles'],
                Platform.environment['ProgramFiles(x86)'],
              ])
                if (root != null) p.join(root, 'VideoLAN', 'VLC', 'vlc.exe'),
            ]
          : [
              for (final root
                  in (Platform.environment['PATH'] ?? '/usr/bin:/bin').split(
                    ':',
                  ))
                for (final name in ['vlc', 'mpv']) p.join(root, name),
            ];
      for (final path in paths.toSet()) {
        try {
          await validateApplication(path);
          found.add(
            ExternalPlayerApplication(
              name: p.basenameWithoutExtension(path),
              path: path,
            ),
          );
        } catch (_) {
          /* Not installed. */
        }
      }
    }
    if (customPath != null && !found.any((a) => p.equals(a.path, customPath))) {
      try {
        await validateApplication(customPath);
        found.add(
          ExternalPlayerApplication(
            name: p.basenameWithoutExtension(customPath),
            path: customPath,
          ),
        );
      } catch (_) {
        /* The settings row retains a missing selected path. */
      }
    }
    return found;
  }

  @override
  Future<void> launch(String location, {String? applicationPath}) async {
    if (applicationPath != null) await validateApplication(applicationPath);
    final remote = [
      'http',
      'https',
    ].contains(Uri.tryParse(location)?.scheme.toLowerCase());
    if (!remote && !await File(location).exists()) {
      throw const SourceFailure('视频文件不存在或 NAS 未连接。');
    }
    if (Platform.isMacOS) {
      await _channel
          .invokeMethod<void>('open', {
            'location': location,
            'applicationPath': applicationPath,
          })
          .timeout(const Duration(seconds: 10));
      return;
    }
    var application = applicationPath;
    if (application == null && remote) {
      application = (await availablePlayers()).firstOrNull?.path;
    }
    if (application != null) {
      await _startExternal(application, [location]);
    } else if (Platform.isWindows) {
      final result = await Isolate.run(() => _openWindows(location));
      if (!result) {
        throw const SourceFailure('系统默认播放器不可用，或默认应用是 ReelNest。请在设置中选择外部播放器。');
      }
    } else if (Platform.isLinux) {
      await _startExternal('xdg-open', [
        remote ? location : p.toUri(location).toString(),
      ]);
    } else {
      throw const SourceFailure('当前平台尚不支持外部播放。');
    }
  }
}

Future<void> _startExternal(String executable, List<String> arguments) async {
  final process = await Process.start(executable, arguments, runInShell: false);
  // Drain concurrently without retaining output; players may print signed URLs.
  unawaited(process.stdout.drain<void>().catchError((Object _) {}));
  unawaited(process.stderr.drain<void>().catchError((Object _) {}));
  final result = await process.exitCode.timeout(
    const Duration(milliseconds: 800),
    onTimeout: () => -999999,
  );
  if (result != 0 && result != -999999) {
    throw const SourceFailure('外部播放器启动失败，请检查应用是否可正常运行。');
  }
}

bool _openWindows(String location) => using((arena) {
  // Read the association only; never register an application or change it.
  if (!['http', 'https'].contains(Uri.tryParse(location)?.scheme)) {
    final query = DynamicLibrary.open('shlwapi.dll')
        .lookupFunction<
          Int32 Function(
            Uint32,
            Int32,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Uint32>,
          ),
          int Function(
            int,
            int,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Uint32>,
          )
        >('AssocQueryStringW');
    final length = arena<Uint32>()..value = 32768;
    final executable = arena<Uint16>(32768).cast<Utf16>();
    if (query(
              0,
              2,
              p.extension(location).toNativeUtf16(allocator: arena),
              nullptr,
              executable,
              length,
            ) >=
            0 &&
        p.equals(
          p.normalize(executable.toDartString()),
          p.normalize(Platform.resolvedExecutable),
        )) {
      return false;
    }
  }
  return ShellExecute(
        null,
        'open'.toPcwstr(allocator: arena),
        location.toPcwstr(allocator: arena),
        null,
        null,
        SW_SHOWNORMAL,
      ).address >
      32;
});
