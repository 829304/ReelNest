import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../api/emby/emby_quality.dart';
import '../../../domain/media_source.dart';
import 'emby_connection_repository.dart';
import 'source_repository.dart';
import '../../playback/data/player_preferences_repository.dart';

enum VideoCacheTaskState {
  queued,
  downloading,
  paused,
  saving,
  complete,
  failed,
  cancelled,
}

class VideoCacheTask {
  VideoCacheTask(this.item, this.quality);
  final IndexedMedia item;
  final EmbyVideoQuality quality;
  final token = newEmbyIdentity();
  VideoCacheTaskState state = VideoCacheTaskState.queued;
  ScanCancellation cancellation = ScanCancellation();
  int received = 0;
  int? expected;
  String? etag, error;
  bool pauseRequested = false;
  bool cancellationCancelled = false;
  Future<void>? work;
  Timer? heartbeat;
  String? rootPath;
}

class CachedVideo {
  const CachedVideo(
    this.identity,
    this.bundle,
    this.filename,
    this.bytes,
    this.qualityLabel,
  );
  final MediaIdentity identity;
  final String bundle, filename, qualityLabel;
  final int bytes;
}

/// One current manifest shared by all desktop windows. SQL write locks cover
/// publishing and cleaning; uncommitted downloads live in a separate namespace.
class EmbyCacheRepository {
  EmbyCacheRepository({
    required this.sources,
    required this.connections,
    Future<Directory> Function()? cacheDirectory,
    this.maxImageBytes = 512 * 1024 * 1024,
    this.maxImageFiles = 6000,
    this.beforePublish,
  }) : cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;
  final SourceRepository sources;
  final EmbyConnectionRepository connections;
  final Future<Directory> Function() cacheDirectory;
  final int maxImageBytes, maxImageFiles;
  final Future<void> Function()? beforePublish;
  final tasks = ValueNotifier<Map<MediaIdentity, VideoCacheTask>>({});
  final _images = <String, Future<Uint8List>>{};
  final _queue = <VideoCacheTask>[];
  bool _draining = false, _disposed = false;
  final _imageWaiters = <Completer<void>>[];
  int _imageActive = 0;
  final _imageCancellations = <ScanCancellation>{};
  final _imageFailures = <String, ({int until, int attempts})>{};
  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;
  Future<Directory> imageRoot() => _root('ArtworkCache');
  Future<Directory> videoRoot() async {
    final row = await sources.database
        .customSelect(
          "SELECT value FROM player_preferences WHERE key = 'global.videoCacheDirectoryPath'",
        )
        .getSingleOrNull();
    return _root('VideoCache', custom: row?.read<String>('value'));
  }

  Future<Directory> _root(String name, {String? custom}) async {
    final base = custom == null ? await cacheDirectory() : Directory(custom);
    await base.create(recursive: true);
    final canonical = await base.resolveSymbolicLinks();
    final directory = Directory(p.join(canonical, name));
    await directory.create(recursive: true);
    if (!p.isWithin(canonical, await directory.resolveSymbolicLinks())) {
      throw const SourceFailure('缓存目录包含无效的链接。');
    }
    return directory;
  }

  bool _token(String value) => RegExp(r'^[a-f0-9-]{36}$').hasMatch(value);
  Future<void> _writeLock() => sources.database.customStatement(
    "UPDATE video_cache_leases SET expires_at = expires_at WHERE owner = ''",
  );
  Future<void> _removeBundle(
    Directory root,
    String token, {
    bool staging = false,
  }) async {
    if (!_token(token)) throw const SourceFailure('缓存清单路径无效。');
    final parent = Directory(
      p.join(root.path, staging ? '.staging' : 'objects'),
    );
    final target = Directory(p.join(parent.path, token));
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !p.isWithin(root.path, await target.resolveSymbolicLinks())) {
      throw const SourceFailure('缓存路径包含无效的链接。');
    }
    await target.delete(recursive: true);
  }

  Future<Uint8List> artwork(
    String sourceId,
    String itemId, {
    bool backdrop = false,
    int index = 0,
    int? width,
    int revision = 0,
  }) {
    // Successful source sync/detail refresh supplies a persisted timestamp.
    // Separate generations also prevent a late old request replacing new art;
    // old generations remain subject to the same global LRU budget.
    final key = jsonEncode([
      sourceId,
      itemId,
      backdrop,
      index,
      width ?? (backdrop ? 1280 : 700),
      revision,
    ]);
    return _images.putIfAbsent(
      key,
      () => _artwork(key, sourceId, itemId, backdrop, index, width)
          .whenComplete(() {
            _images.remove(key);
          }),
    );
  }

  Future<Uint8List> _artwork(
    String key,
    String sourceId,
    String itemId,
    bool backdrop,
    int index,
    int? width,
  ) async {
    Directory? root;
    try {
      root = await imageRoot();
      final row = await sources.database
          .customSelect(
            'SELECT * FROM artwork_disk_cache WHERE cache_key = ?',
            variables: [Variable(key)],
          )
          .getSingleOrNull();
      if (row != null && _token(row.read<String>('filename'))) {
        final file = File(p.join(root.path, row.read<String>('filename')));
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
                FileSystemEntityType.file &&
            await file.length() <= 24 * 1024 * 1024) {
          final bytes = await file.readAsBytes();
          await _validateImage(bytes);
          await sources.database.customStatement(
            'UPDATE artwork_disk_cache SET accessed_at = ? WHERE cache_key = ?',
            [_now(), key],
          );
          return bytes;
        }
      }
    } catch (_) {
      /* A corrupt/missing disk copy can be fetched again. */
    }
    if ((_imageFailures[key]?.until ?? 0) > _now()) {
      throw const SourceFailure('封面暂不可用，请稍后重试。');
    }
    if (_imageActive >= 4) {
      final waiter = Completer<void>();
      _imageWaiters.add(waiter);
      await waiter.future;
    } else {
      _imageActive++;
    }
    final cancellation = ScanCancellation();
    _imageCancellations.add(cancellation);
    try {
      if (_disposed) throw const ScanCancelled();
      final bytes = await connections
          .artwork(
            sourceId,
            itemId,
            backdrop: backdrop,
            index: index,
            maxWidth: width,
            cancellation: cancellation,
          )
          .timeout(
            const Duration(seconds: 14),
            onTimeout: () {
              cancellation.cancel();
              throw const SourceFailure('封面读取超时。');
            },
          );
      await _validateImage(bytes);
      _imageFailures.remove(key);
      if (root != null) {
        // UUID paths and a manifest replace avoid authenticated URLs on disk.
        final filename = newEmbyIdentity();
        final file = File(p.join(root.path, filename));
        final temporary = File('${file.path}.part');
        try {
          await temporary.writeAsBytes(bytes, flush: true);
          await sources.database.transaction(() async {
            await _writeLock();
            await temporary.rename(file.path);
            await sources.database.customStatement(
              '''
              INSERT INTO artwork_disk_cache(cache_key,source_id,filename,bytes,accessed_at)
              VALUES(?,?,?,?,?) ON CONFLICT(cache_key) DO UPDATE SET
                filename=excluded.filename,bytes=excluded.bytes,accessed_at=excluded.accessed_at
            ''',
              [key, sourceId, filename, bytes.length, _now()],
            );
            await _pruneImages(root!);
          });
        } catch (_) {
          if (await temporary.exists()) await temporary.delete();
          if (await file.exists()) await file.delete();
        }
      }
      return bytes;
    } catch (_) {
      if (!_disposed) {
        final attempts = ((_imageFailures[key]?.attempts ?? 0) + 1).clamp(1, 6);
        if (_imageFailures.length >= 6000) _imageFailures.clear();
        _imageFailures[key] = (
          until: _now() + (30000 * (1 << (attempts - 1))).clamp(30000, 600000),
          attempts: attempts,
        );
      }
      rethrow;
    } finally {
      _imageCancellations.remove(cancellation);
      if (_imageWaiters.isNotEmpty) {
        _imageWaiters.removeAt(0).complete();
      } else {
        _imageActive--;
      }
    }
  }

  Future<void> _validateImage(Uint8List bytes) async {
    if (bytes.length > 24 * 1024 * 1024) throw const SourceFailure('封面过大。');
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 700,
      targetHeight: 1050,
    );
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }

  Future<void> _pruneImages(Directory root) async {
    final rows = await sources.database
        .customSelect(
          'SELECT * FROM artwork_disk_cache ORDER BY accessed_at DESC',
        )
        .get();
    var bytes = 0, count = 0;
    for (final row in rows) {
      bytes += row.read<int>('bytes');
      count++;
      if (bytes <= maxImageBytes && count <= maxImageFiles) continue;
      await sources.database.customStatement(
        'DELETE FROM artwork_disk_cache WHERE cache_key = ?',
        [row.read<String>('cache_key')],
      );
    }
    final kept =
        (await sources.database
                .customSelect('SELECT filename FROM artwork_disk_cache')
                .get())
            .map((r) => r.read<String>('filename'))
            .toSet();
    await for (final file in root.list(followLinks: false)) {
      if (file is File &&
          _token(p.basename(file.path)) &&
          !kept.contains(p.basename(file.path))) {
        try {
          await file.delete();
        } on FileSystemException {
          /* Retry later. */
        }
      }
    }
  }

  Future<void> prewarm(Iterable<IndexedMedia> items, {int revision = 0}) async {
    // Same key/size as visible posters; four workers rather than an unbounded
    // Future list for thousands of entries. Playback never waits for warming.
    final iterator = items.where((i) => i.posterPath != null).iterator;
    await Future.wait(
      List.generate(4, (_) async {
        while (!_disposed && iterator.moveNext()) {
          final item = iterator.current;
          try {
            await artwork(
              item.identity.sourceId,
              item.posterPath!,
              revision: revision,
            );
          } catch (_) {}
        }
      }),
    );
  }

  Future<List<CachedVideo>> entries() async {
    final rows = await sources.database
        .customSelect('SELECT * FROM video_disk_cache')
        .get();
    if (rows.isEmpty) return [];
    final root = await videoRoot();
    final result = <CachedVideo>[];
    for (final r in rows) {
      if (!p.equals(root.path, r.read<String>('root'))) continue;
      final entry = CachedVideo(
        (
          sourceId: r.read<String>('source_id'),
          localId: r.read<String>('local_id'),
        ),
        r.read<String>('bundle'),
        r.read<String>('filename'),
        r.read<int>('bytes'),
        r.read<String>('quality_label'),
      );
      if (await _videoFile(root, entry) != null) result.add(entry);
    }
    return result;
  }

  Future<File?> _videoFile(Directory root, CachedVideo entry) async {
    if (!_token(entry.bundle) ||
        !RegExp(r'^video\.[a-z0-9]{1,10}$').hasMatch(entry.filename)) {
      throw const SourceFailure('缓存清单路径无效。');
    }
    final file = File(
      p.join(root.path, 'objects', entry.bundle, entry.filename),
    );
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !p.isWithin(root.path, await file.resolveSymbolicLinks()) ||
        await file.length() != entry.bytes) {
      return null;
    }
    return file;
  }

  Future<({String path, String? custom, double limit, int bytes, int count})>
  summary() async {
    final row = await sources.database
        .customSelect(
          "SELECT value FROM player_preferences WHERE key='global.videoCacheDirectoryPath'",
        )
        .getSingleOrNull();
    final root = await videoRoot();
    final list = await entries();
    var bytes = 0;
    for (final entry in list) {
      bytes += await _bundleBytes(root, entry.bundle);
    }
    return (
      path: root.path,
      custom: row?.read<String>('value'),
      limit: await PlayerPreferencesRepository(sources.database)
          .number('videoCacheSizeLimitGB', 0),
      bytes: bytes,
      count: list.length,
    );
  }

  Future<void> setDirectory(String? path) async {
    await _root('VideoCache', custom: path);
    await sources.database.customStatement(
      path == null
          ? "DELETE FROM player_preferences WHERE key='global.videoCacheDirectoryPath'"
          : "INSERT INTO player_preferences VALUES('global.videoCacheDirectoryPath',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
      path == null ? [] : [path],
    );
    sources.traceChanged();
  }

  Future<void> setLimit(double gb) async {
    await PlayerPreferencesRepository(sources.database)
        .rememberNumber('videoCacheSizeLimitGB', gb.clamp(0, 4096));
    await maintenance();
  }

  Future<int> _bundleBytes(Directory root, String bundle) async {
    if (!_token(bundle)) throw const SourceFailure('缓存清单路径无效。');
    final directory = Directory(p.join(root.path, 'objects', bundle));
    if (!await directory.exists()) return 0;
    if (!p.isWithin(root.path, await directory.resolveSymbolicLinks())) {
      throw const SourceFailure('缓存路径无效。');
    }
    var bytes = 0;
    await for (final file in directory.list(followLinks: false)) {
      if (file is File) bytes += await file.length();
    }
    return bytes;
  }

  Future<({String path, String lease})?> acquire(MediaIdentity id) async {
    final cached = (await entries()).where((e) => e.identity == id).firstOrNull;
    if (cached == null) return null;
    final root = await videoRoot();
    return sources.database.transaction(() async {
      await _writeLock();
      if (!(await entries()).any(
        (e) => e.identity == id && e.bundle == cached.bundle,
      )) {
        return null;
      }
      if (!_token(cached.bundle) ||
          !RegExp(r'^video\.[a-z0-9]{1,10}$').hasMatch(cached.filename)) {
        throw const SourceFailure('缓存清单路径无效。');
      }
      final file = await _videoFile(root, cached);
      if (file == null) return null;
      final lease = newEmbyIdentity();
      await sources.database.customStatement(
        'INSERT INTO video_cache_leases(owner,bundle,expires_at) VALUES(?,?,?)',
        [lease, cached.bundle, _now() + 120000],
      );
      await sources.database.customStatement(
        'UPDATE video_disk_cache SET accessed_at=? WHERE source_id=? AND local_id=?',
        [_now(), id.sourceId, id.localId],
      );
      return (path: file.path, lease: lease);
    });
  }

  Future<void> renew(String owner) => sources.database.customStatement(
    'UPDATE video_cache_leases SET expires_at=? WHERE owner=?',
    [_now() + 120000, owner],
  );
  Future<void> release(String owner) => sources.database.customStatement(
    'DELETE FROM video_cache_leases WHERE owner=?',
    [owner],
  );
  void _notify() {
    if (!_disposed) tasks.value = {...tasks.value};
  }

  Future<void> enqueue(IndexedMedia item, EmbyVideoQuality quality) async {
    final items = item.isSeries
        ? (await sources.indexedSource(item.identity.sourceId))
              .where((i) => i.parentId == item.identity.localId)
              .toList()
        : [item];
    for (final candidate in items) {
      if (candidate.remote == null ||
          candidate.isSeries ||
          candidate.type == 'music') {
        continue;
      }
      final current = tasks.value[candidate.identity];
      if (current != null &&
          [
            VideoCacheTaskState.queued,
            VideoCacheTaskState.downloading,
            VideoCacheTaskState.saving,
            VideoCacheTaskState.paused,
          ].contains(current.state)) {
        continue;
      }
      final selected =
          EmbyVideoQuality.options(candidate)
              .where((q) => q.id == quality.id)
              .firstOrNull ??
          EmbyVideoQuality.source;
      final task = VideoCacheTask(candidate, selected);
      tasks.value = {...tasks.value, candidate.identity: task};
      _queue.add(task);
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final task = _queue.removeAt(0);
        if (task.state != VideoCacheTaskState.queued) continue;
        task.work = _download(task);
        await task.work;
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _download(VideoCacheTask task) async {
    Directory? root, staging;
    bool published = false;
    try {
      root = await videoRoot();
      task.rootPath = root.path;
      task.heartbeat?.cancel();
      staging = Directory(p.join(root.path, '.staging', task.token));
      await staging.create(recursive: true);
      if (!p.isWithin(root.path, await staging.resolveSymbolicLinks())) {
        throw const SourceFailure('暂存路径无效。');
      }
      await sources.database.customStatement(
        'INSERT OR REPLACE INTO video_cache_staging VALUES(?,?,?)',
        [task.token, root.path, _now()],
      );
      task.heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(
          sources.database
              .customStatement(
                'UPDATE video_cache_staging SET touched_at=? WHERE token=?',
                [_now(), task.token],
              )
              .catchError((Object _) {}),
        );
      });
      final extension = task.quality.original
          ? task.item.remote?.container?.trim().toLowerCase()
          : 'mp4';
      final filename =
          'video.${extension != null && RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension) ? extension : 'bin'}';
      final file = File(p.join(staging.path, filename));
      task.state = VideoCacheTaskState.downloading;
      _notify();
      var lastProgress = 0;
      final result = await connections.downloadVideo(
        task.item,
        file,
        task.cancellation,
        quality: task.quality,
        etag: task.etag,
        onProgress: (progress) {
          task.received = progress.received;
          task.expected = progress.expected;
          task.etag = progress.etag;
          if (_now() - lastProgress > 150) {
            lastProgress = _now();
            _notify();
          }
        },
      );
      task.cancellation.check();
      task.state = VideoCacheTaskState.saving;
      _notify();
      // Subtitle failure does not discard a successful video, matching original.
      try {
        final streams = await _subtitleWork(
          task,
          (token) => connections.subtitles(task.item, cancellation: token),
        );
        for (final stream in streams) {
          task.cancellation.check();
          try {
            final bytes = await _subtitleWork(
              task,
              (token) =>
                  connections.subtitle(task.item, stream, cancellation: token),
            );
            final language = (stream.language ?? 'und').replaceAll(
              RegExp(r'[^a-zA-Z0-9-]'),
              '-',
            );
            await File(
              p.join(
                staging.path,
                'video.$language.${stream.index}.${stream.extension}',
              ),
            ).writeAsBytes(bytes, flush: true);
          } on ScanCancelled {
            rethrow;
          } catch (_) {
            task.error = '视频已缓存，部分字幕未能保存。';
          }
        }
      } on ScanCancelled {
        rethrow;
      } catch (_) {
        task.error = '视频已缓存，字幕未能保存。';
      }
      task.cancellation.check();
      await beforePublish?.call();
      await sources.database.transaction(() async {
        await _writeLock();
        task.cancellation.check();
        await sources.media(
          task.item.identity,
        ); // Removed source/item cannot be resurrected.
        final objects = Directory(p.join(root!.path, 'objects'));
        await objects.create(recursive: true);
        if (!p.isWithin(root!.path, await objects.resolveSymbolicLinks())) {
          throw const SourceFailure('缓存目标路径无效。');
        }
        await staging!.rename(p.join(objects.path, task.token));
        await sources.database.customStatement(
          '''
          INSERT INTO video_disk_cache(source_id,local_id,bundle,root,filename,bytes,quality_id,quality_label,created_at,accessed_at)
          VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(source_id,local_id) DO UPDATE SET
            bundle=excluded.bundle,root=excluded.root,filename=excluded.filename,bytes=excluded.bytes,
            quality_id=excluded.quality_id,quality_label=excluded.quality_label,
            created_at=excluded.created_at,accessed_at=excluded.accessed_at
        ''',
          [
            task.item.identity.sourceId,
            task.item.identity.localId,
            task.token,
            root!.path,
            filename,
            result.received,
            task.quality.id,
            task.quality.label,
            _now(),
            _now(),
          ],
        );
        task.cancellation.check();
      });
      published = true;
      task.state = VideoCacheTaskState.complete;
      sources.traceChanged();
      try {
        await maintenance();
      } catch (_) {
        task.error ??= '视频已缓存，容量清理未能完成。';
      }
    } catch (error) {
      if (task.pauseRequested && !published) {
        task.state = VideoCacheTaskState.paused;
      } else if (task.cancellationCancelled) {
        task.state = VideoCacheTaskState.cancelled;
      } else {
        task.state = VideoCacheTaskState.failed;
        task.error = error is SourceFailure
            ? error.message
            : '缓存保存失败，请检查目录权限和磁盘空间。';
      }
    } finally {
      if (task.state != VideoCacheTaskState.paused) {
        task.heartbeat?.cancel();
        task.heartbeat = null;
      }
      if (root != null && task.state != VideoCacheTaskState.paused) {
        try {
          if (!published) await _removeBundle(root, task.token);
          await _removeBundle(root, task.token, staging: true);
          await sources.database.customStatement(
            'DELETE FROM video_cache_staging WHERE token=?',
            [task.token],
          );
        } catch (_) {
          /* Recognizable staging/orphans can be maintained later. */
        }
      }
      _notify();
    }
  }

  Future<T> _subtitleWork<T>(
    VideoCacheTask task,
    Future<T> Function(ScanCancellation) work,
  ) async {
    final token = ScanCancellation();
    final cancelled = Completer<T>();
    final unlisten = task.cancellation.listen(() {
      token.cancel();
      if (!cancelled.isCompleted) {
        cancelled.completeError(const ScanCancelled());
      }
    });
    try {
      return await Future.any([work(token), cancelled.future]).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          token.cancel();
          throw const SourceFailure('字幕下载超时。');
        },
      );
    } finally {
      unlisten();
    }
  }

  void pause(VideoCacheTask task) {
    if (![
      VideoCacheTaskState.queued,
      VideoCacheTaskState.downloading,
    ].contains(task.state)) {
      return;
    }
    task.pauseRequested = true;
    task.cancellation.cancel();
    if (task.state == VideoCacheTaskState.queued) {
      task.state = VideoCacheTaskState.paused;
    }
    _notify();
  }

  Future<void> resume(VideoCacheTask task) async {
    await task.work;
    if (task.state != VideoCacheTaskState.paused || _disposed) return;
    task.pauseRequested = false;
    task.cancellationCancelled = false;
    task.cancellation = ScanCancellation();
    task.state = VideoCacheTaskState.queued;
    _queue.add(task);
    _notify();
    unawaited(_drain());
  }

  Future<void> cancel(VideoCacheTask task) async {
    task.pauseRequested = false;
    task.cancellationCancelled = true;
    task.cancellation.cancel();
    await task.work;
    task.state = VideoCacheTaskState.cancelled;
    task.heartbeat?.cancel();
    task.heartbeat = null;
    try {
      await _removeBundle(
        task.rootPath == null ? await videoRoot() : Directory(task.rootPath!),
        task.token,
        staging: true,
      );
      await sources.database.customStatement(
        'DELETE FROM video_cache_staging WHERE token=?',
        [task.token],
      );
    } catch (_) {}
    _notify();
  }

  Future<void> maintenance({
    bool clear = false,
    MediaIdentity? remove,
    String? protectedBundle,
  }) async {
    final root = await videoRoot();
    await sources.database.transaction(() async {
      await _writeLock();
      await sources.database.customStatement(
        'DELETE FROM video_cache_leases WHERE expires_at < ?',
        [_now()],
      );
      final leased =
          (await sources.database
                  .customSelect('SELECT bundle FROM video_cache_leases')
                  .get())
              .map((r) => r.read<String>('bundle'))
              .toSet();
      if (remove != null &&
          (await entries()).any(
            (e) => e.identity == remove && leased.contains(e.bundle),
          )) {
        throw const SourceFailure('此缓存正在播放，请关闭播放器后重试。');
      }
      final preferences = PlayerPreferencesRepository(sources.database);
      final limit =
          ((await preferences.number('videoCacheSizeLimitGB', 0)) *
                  1024 *
                  1024 *
                  1024)
              .round();
      final threshold = await preferences.watchedThreshold;
      final list = await entries();
      final validBundles = list.map((e) => e.bundle).toSet();
      final tracked = await sources.database
          .customSelect(
            'SELECT bundle FROM video_disk_cache WHERE root=?',
            variables: [Variable(root.path)],
          )
          .get();
      for (final row in tracked) {
        final bundle = row.read<String>('bundle');
        if (!validBundles.contains(bundle) && !leased.contains(bundle)) {
          await sources.database.customStatement(
            'DELETE FROM video_disk_cache WHERE root=? AND bundle=?',
            [root.path, bundle],
          );
        }
      }
      final hints = await sources.database.customSelect('''
        SELECT c.bundle, c.accessed_at, s.watched, s.position_ms, s.duration_ms, s.last_played_at
        FROM video_disk_cache c LEFT JOIN playback_states s USING(source_id,local_id)
      ''').get();
      int score(String bundle) {
        final r = hints.where((r) => r.read<String>('bundle') == bundle).first;
        final recent =
            (r.readNullable<int>('last_played_at') ?? 0) >
            _now() - 30 * 86400000;
        final duration = r.readNullable<int>('duration_ms') ?? 0;
        final watched =
            r.readNullable<int>('watched') == 1 ||
            (duration > 0 &&
                (r.readNullable<int>('position_ms') ?? 0) / duration >=
                    threshold);
        return watched && !recent
            ? 3
            : !recent
            ? 2
            : watched
            ? 1
            : 0;
      }

      list.sort((a, b) {
        final result = score(b.bundle).compareTo(score(a.bundle));
        if (result != 0) return result;
        int accessed(String bundle) => hints
            .firstWhere((r) => r.read<String>('bundle') == bundle)
            .read<int>('accessed_at');
        return accessed(a.bundle).compareTo(accessed(b.bundle));
      });
      final sizes = <String, int>{};
      for (final entry in list) {
        sizes[entry.bundle] = await _bundleBytes(root, entry.bundle);
      }
      var total = sizes.values.fold<int>(0, (a, b) => a + b);
      final redownloading = tasks.value.values
          .where(
            (t) => [
              VideoCacheTaskState.queued,
              VideoCacheTaskState.downloading,
              VideoCacheTaskState.saving,
              VideoCacheTaskState.paused,
            ].contains(t.state),
          )
          .map((t) => t.item.identity)
          .toSet();
      for (final entry in list) {
        if (leased.contains(entry.bundle) ||
            entry.bundle == protectedBundle ||
            (!clear &&
                remove == null &&
                redownloading.contains(entry.identity))) {
          continue;
        }
        if (clear || entry.identity == remove || (limit > 0 && total > limit)) {
          await sources.database.customStatement(
            'DELETE FROM video_disk_cache WHERE source_id=? AND local_id=?',
            [entry.identity.sourceId, entry.identity.localId],
          );
          total -= sizes[entry.bundle] ?? 0;
        }
      }
      final stagingRows = await sources.database
          .customSelect(
            'SELECT * FROM video_cache_staging WHERE root=?',
            variables: [Variable(root.path)],
          )
          .get();
      for (final row in stagingRows) {
        if (row.read<int>('touched_at') >= _now() - 86400000) continue;
        await _removeBundle(root, row.read<String>('token'), staging: true);
        await sources.database.customStatement(
          'DELETE FROM video_cache_staging WHERE token=?',
          [row.read<String>('token')],
        );
      }
      final registered = stagingRows
          .map((r) => r.read<String>('token'))
          .toSet();
      final stagingRoot = Directory(p.join(root.path, '.staging'));
      if (await stagingRoot.exists()) {
        await for (final entity in stagingRoot.list(followLinks: false)) {
          final token = p.basename(entity.path);
          if (!_token(token) || registered.contains(token)) continue;
          final stat = await entity.stat();
          if (stat.modified.millisecondsSinceEpoch < _now() - 86400000) {
            await _removeBundle(root, token, staging: true);
          }
        }
      }
      final keep = {
        ...leased,
        for (final e in await entries()) e.bundle,
        ?protectedBundle,
        for (final r
            in await sources.database
                .customSelect('SELECT token FROM video_cache_staging')
                .get())
          r.read<String>('token'),
      };
      final objects = Directory(p.join(root.path, 'objects'));
      if (await objects.exists()) {
        await for (final entity in objects.list(followLinks: false)) {
          final token = p.basename(entity.path);
          if (_token(token) && !keep.contains(token)) {
            await _removeBundle(root, token);
          }
        }
      }
    });
    sources.traceChanged();
  }

  /// Clear task records only; managed files and active work are unchanged.
  void clearFinished() {
    if (_disposed) return;
    tasks.value = Map.fromEntries(
      tasks.value.entries.where(
        (e) => [
          VideoCacheTaskState.queued,
          VideoCacheTaskState.downloading,
          VideoCacheTaskState.saving,
          VideoCacheTaskState.paused,
        ].contains(e.value.state),
      ),
    );
  }

  Future<({int count, int bytes, double limit})> storageSummary() async {
    final list = await entries();
    var bytes = 0;
    if (list.isNotEmpty) {
      final root = await videoRoot();
      for (final entry in list) {
        bytes += await _bundleBytes(root, entry.bundle);
      }
    }
    final limit = await PlayerPreferencesRepository(sources.database)
        .number('videoCacheSizeLimitGB', 0);
    return (count: list.length, bytes: bytes, limit: limit);
  }

  Future<void>? _disposing;
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    for (final token in _imageCancellations) {
      token.cancel();
    }
    for (final task in tasks.value.values) {
      task.heartbeat?.cancel();
      task.cancellationCancelled = true;
      task.cancellation.cancel();
    }
    for (final waiter in _imageWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _imageWaiters.clear();
    await Future.wait(
      tasks.value.values.map((t) async {
        await t.work;
      }),
    );
    await Future.wait(
      _images.values.map((f) async {
        try {
          await f;
        } catch (_) {}
      }),
    );
    tasks.dispose();
  }
}
