import 'dart:async';
import 'dart:typed_data';

import '../../../domain/media_source.dart';
import '../../../player/mpv_video_frame_preview.dart';
import '../../../player/playback_diagnostics.dart';
import '../../metadata/data/tmdb_artwork_store.dart';
import '../../playback/domain/video_frame_preview.dart';
import '../data/source_repository.dart';
import '../data/url_video_repository.dart';

/// Original automatic cover extraction, queued independently of URL saves.
/// The dedicated decoder never opens a player window or alters playback.
class UrlVideoCoverService {
  UrlVideoCoverService({
    required this.sources,
    TmdbArtworkStore? artwork,
    Future<Uint8List?> Function(VideoPreviewResource, VideoPreviewCancellation)?
    generate,
  }) : artwork = artwork ?? TmdbArtworkStore(),
       generate = generate ?? _generate;
  final SourceRepository sources;
  final TmdbArtworkStore artwork;
  final Future<Uint8List?> Function(
    VideoPreviewResource,
    VideoPreviewCancellation,
  )
  generate;
  Future<void> _pending = Future.value();
  bool _closed = false;
  VideoPreviewCancellation? _token;
  static Future<Uint8List?> _generate(
    VideoPreviewResource resource,
    VideoPreviewCancellation token,
  ) async {
    // Same 20% sample as ThumbnailGenerator, with dark-frame fallback samples.
    for (final ratio in [.2, .15, .2, .3]) {
      if (token.isCancelled) return null;
      final bytes = await generateMpvVideoPreview(
        resource,
        Duration.zero,
        token,
        coverRatio: ratio,
      );
      if (bytes != null) return bytes;
    }
    return null;
  }

  void enqueue(List<MediaIdentity> identities) {
    for (final id in identities) {
      _pending = _pending.then((_) => capture(id)).catchError((
        Object _,
        StackTrace stack,
      ) {
        PlaybackDiagnostics().begin().event(
          'url_cover_failed',
          code: 'extraction_failed',
        );
      });
    }
  }

  Future<void> capture(MediaIdentity identity) async {
    if (_closed) return;
    final token = VideoPreviewCancellation();
    _token = token;
    try {
      final repository = UrlVideoRepository(sources);
      final url = await repository.location(identity);
      final before = await sources.media(identity);
      final bytes = await generate(
        VideoPreviewResource(identity: identity, location: url),
        token,
      );
      if (_closed || token.isCancelled || bytes == null) return;
      final reference = await artwork.save(bytes);
      if (_closed || token.isCancelled) return;
      await sources.database.transaction(() async {
        sources.requireMutationAllowed(identity.sourceId);
        final item = await sources.media(identity);
        if (await repository.location(identity) != url ||
            item.posterPath != before.posterPath ||
            _closed) {
          return;
        }
        await sources.database.customStatement(
          'UPDATE media SET poster_path=? WHERE source_id=? AND local_id=?',
          [reference, identity.sourceId, identity.localId],
        );
      });
      if (!_closed) sources.traceChanged(sourceIds: [identity.sourceId]);
    } catch (_) {
      // URLs/queries/passwords and native error text never enter diagnostics.
      if (!_closed) {
        PlaybackDiagnostics().begin().event(
          'url_cover_failed',
          code: 'extraction_failed',
        );
      }
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  Future<void> dispose() async {
    _closed = true;
    _token?.cancel();
    await _pending;
  }
}
