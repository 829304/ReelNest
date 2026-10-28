import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../../application/async_tasks.dart';
import '../../../domain/media_source.dart';
import '../../../platform/atomic_nfo_publish.dart';
import '../domain/nfo_metadata_update.dart';

class NfoWriteResult {
  const NfoWriteResult({required this.written, this.warning});
  final bool written;
  final String? warning;
}

/// Original VideoMetadataSidecarWriter: bounded XML merge, serialized target
/// ownership and native atomic replacement with recoverable original bytes.
class VideoNfoWriter {
  VideoNfoWriter({this.beforeCommit, this.publish = publishNfo});
  final Future<void> Function()? beforeCommit;
  final Future<bool> Function(String, String, String?) publish;
  static const maximumBytes = 4 * 1024 * 1024;
  static final _queues = <String, SerialTaskQueue>{};
  static final _users = <String, int>{};

  Future<NfoWriteResult> write({
    required String root,
    required String target,
    required String rootTag,
    required String fallbackTitle,
    required NfoMetadataUpdate update,
    required ScanCancellation cancellation,
    required Future<void> Function() validate,
  }) async {
    cancellation.check();
    final key = Platform.isWindows
        ? p.normalize(target).toLowerCase()
        : p.normalize(target);
    final queue = _queues.putIfAbsent(key, SerialTaskQueue.new);
    _users[key] = (_users[key] ?? 0) + 1;
    var started = false;
    final cancelled = Completer<NfoWriteResult>();
    final unlisten = cancellation.listen(() {
      if (!started) cancelled.completeError(const ScanCancelled());
    });
    final work = queue.run(() {
      started = true;
      return _write(
        root,
        target,
        rootTag,
        fallbackTitle,
        update,
        cancellation,
        validate,
      );
    });
    void release() {
      final remaining = _users[key]! - 1;
      if (remaining == 0) {
        _users.remove(key);
        _queues.remove(key);
      } else {
        _users[key] = remaining;
      }
    }

    unawaited(
      work.then<void>(
        (_) => release(),
        onError: (Object _, StackTrace _) => release(),
      ),
    );
    try {
      return await Future.any([work, cancelled.future]);
    } finally {
      unlisten();
    }
  }

  static Future<void> _safeParent(String root, String target) async {
    if (!p.isAbsolute(root) ||
        !p.isAbsolute(target) ||
        !p.isWithin(root, target)) {
      throw const SourceFailure('NFO 路径超出媒体源，已拒绝写入。');
    }
    if (!p.equals(
          await Directory(root).resolveSymbolicLinks(),
          p.normalize(root),
        ) ||
        !p.equals(
          await Directory(p.dirname(target)).resolveSymbolicLinks(),
          p.normalize(p.dirname(target)),
        )) {
      throw const SourceFailure('NFO 父目录身份已改变，已拒绝写入。');
    }
    if (await FileSystemEntity.type(target, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const SourceFailure('NFO 目标是符号链接，已拒绝写入。');
    }
  }

  static Future<Uint8List?> _read(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const SourceFailure('NFO 目标不是普通文件，已保留原文件。');
    }
    final file = File(path);
    if (await file.length() > maximumBytes) {
      throw const SourceFailure('现有 NFO 超出安全合并上限，已保留原文件。');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, maximumBytes + 1)) {
      if (bytes.length + chunk.length > maximumBytes) {
        throw const SourceFailure('现有 NFO 超出安全合并上限，已保留原文件。');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static bool _same(List<int>? a, List<int>? b) => a == null || b == null
      ? a == null && b == null
      : a.length == b.length && sha256.convert(a) == sha256.convert(b);

  Future<NfoWriteResult> _write(
    String root,
    String target,
    String rootTag,
    String fallbackTitle,
    NfoMetadataUpdate update,
    ScanCancellation token,
    Future<void> Function() validate,
  ) async {
    token.check();
    await validate();
    await _safeParent(root, target);
    final original = await _read(target);
    if (original != null && ((await File(target).stat()).mode & 0x92) == 0) {
      return const NfoWriteResult(
        written: false,
        warning: 'NFO 不可写，资料仅保存到 ReelNest 索引。',
      );
    }
    final output = await Isolate.run(
      () => mergeNfo(original, rootTag, fallbackTitle, update),
    );
    token.check();
    final id = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = p.join(
      p.dirname(target),
      '.${p.basename(target)}.reelnest-nfo-$id.tmp',
    );
    final backup = p.join(
      p.dirname(target),
      '.${p.basename(target)}.reelnest-nfo-backup-$id',
    );
    try {
      await File(temporary).create(exclusive: true);
      await File(temporary).writeAsBytes(output, flush: true);
      if (!_same(await _read(temporary), output)) {
        throw const SourceFailure('生成的 NFO 校验失败，已保留原文件。');
      }
      await beforeCommit?.call();
      token.check();
      await validate();
      await _safeParent(root, target);
      if (!_same(await _read(target), original)) {
        throw const SourceFailure('NFO 已被其他程序修改，已保留外部修改。');
      }
      if (await FileSystemEntity.type(backup, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const SourceFailure('NFO 安全副本路径冲突，已保留原文件。');
      }
      try {
        await publish(temporary, target, original == null ? null : backup);
      } catch (_) {
        /* Reconcile actual native filesystem state. */
      }
      await _safeParent(root, target);
      final current = await _read(target);
      if (_same(current, output)) {
        String? warning;
        if (original != null) {
          final saved = await _read(backup);
          if (saved != null && !_same(saved, original)) {
            warning = 'NFO 已写入，但检测到并发变化，安全副本已保留。';
          } else {
            try {
              if (saved != null) await File(backup).delete();
            } catch (_) {
              warning = 'NFO 已更新，但临时安全副本清理失败。';
            }
          }
        }
        return NfoWriteResult(written: true, warning: warning);
      }
      if (original != null && _same(current, original)) {
        await _removeOwned(root, backup, original);
        throw const SourceFailure('NFO 原子替换失败，原文件已保留。');
      }
      if (current == null &&
          original != null &&
          _same(await _read(backup), original)) {
        // Stage a recovery copy; the only backup is never consumed on failure.
        final recovery = '$temporary.recovery';
        try {
          await File(recovery).create(exclusive: true);
          await File(recovery).writeAsBytes(original, flush: true);
          await _safeParent(root, target);
          try {
            await publish(recovery, target, null);
          } catch (_) {}
          if (_same(await _read(target), original)) {
            await _removeOwned(root, backup, original);
            throw const SourceFailure('NFO 原子替换失败，原文件已恢复。');
          }
        } finally {
          await _removeOwned(root, recovery, original);
        }
        throw const SourceFailure('NFO 恢复未完成，安全副本已保留。');
      }
      throw const SourceFailure('NFO 在写入期间发生并发变化，已保留现有文件和安全副本。');
    } finally {
      await _removeOwned(root, temporary, output);
    }
  }

  static Future<void> _removeOwned(
    String root,
    String path,
    List<int> expected,
  ) async {
    try {
      await _safeParent(root, path);
      if (_same(await _read(path), expected)) await File(path).delete();
    } catch (_) {}
  }
}

Uint8List mergeNfo(
  Uint8List? original,
  String rootTag,
  String fallbackTitle,
  NfoMetadataUpdate update,
) {
  XmlDocument parse(List<int> bytes) {
    final text = utf8.decode(bytes);
    final lower = text.toLowerCase();
    if (lower.contains('<!doctype') || lower.contains('<!entity')) {
      throw const SourceFailure('现有 NFO 含不安全声明，已保留原文件。');
    }
    try {
      final doc = XmlDocument.parse(text);
      if (doc.children.whereType<XmlElement>().length != 1 ||
          doc.children.whereType<XmlText>().any(
            (e) => e.value.trim().isNotEmpty,
          ) ||
          doc.rootElement.name.qualified.toLowerCase() != rootTag) {
        throw const FormatException('Invalid NFO root');
      }
      return doc;
    } catch (_) {
      throw const SourceFailure('现有 NFO 无法安全合并，已保留原文件。');
    }
  }

  final doc = original == null
      ? XmlDocument([
          XmlDeclaration([
            XmlAttribute(XmlName.parts('version'), '1.0'),
            XmlAttribute(XmlName.parts('encoding'), 'UTF-8'),
            XmlAttribute(XmlName.parts('standalone'), 'yes'),
          ]),
          XmlElement(XmlName.parts(rootTag)),
        ])
      : parse(original);
  final root = doc.rootElement;
  void set(String name, String? value) {
    if (value == null) return;
    final existing = root.children
        .whereType<XmlElement>()
        .where((e) => e.name.qualified == name)
        .firstOrNull;
    if (existing == null) {
      root.children.add(XmlElement(XmlName.parts(name), [], [XmlText(value)]));
    } else {
      existing.children
        ..clear()
        ..add(XmlText(value));
    }
  }

  set('title', update.title ?? (original == null ? fallbackTitle : null));
  set('originaltitle', update.originalTitle);
  set('year', update.year?.toString());
  set('plot', update.overview);
  set('genre', update.genre);
  final rating = update.rating;
  if (rating != null && rating.isFinite && rating > 0 && rating <= 10) {
    set('rating', rating.toString());
  }
  if (update.externalId != null) {
    final id = root.children
        .whereType<XmlElement>()
        .where(
          (e) =>
              e.name.qualified == 'uniqueid' &&
              e.getAttribute('type')?.toLowerCase() == 'tmdb',
        )
        .firstOrNull;
    if (id == null) {
      root.children.add(
        XmlElement(
          XmlName.parts('uniqueid'),
          [XmlAttribute(XmlName.parts('type'), 'tmdb')],
          [XmlText(update.externalId!)],
        ),
      );
    } else {
      id.children
        ..clear()
        ..add(XmlText(update.externalId!));
    }
  }
  final output = Uint8List.fromList(
    utf8.encode(doc.toXmlString(pretty: true, indent: '  ')),
  );
  if (output.length > VideoNfoWriter.maximumBytes) {
    throw const SourceFailure('生成的 NFO 超出大小上限，已保留原文件。');
  }
  parse(output);
  return output;
}
