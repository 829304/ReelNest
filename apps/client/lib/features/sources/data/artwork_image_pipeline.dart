import 'dart:async';
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'artwork_decode_queue.dart';

typedef ArtworkImageKey = ({
  String sourceId,
  String itemId,
  bool backdrop,
  int index,
  int width,
  int height,
  int revision,
});

typedef _ArtworkIdentity = ({
  String sourceId,
  String itemId,
  bool backdrop,
  int index,
  int revision,
});
_ArtworkIdentity _identity(ArtworkImageKey key) => (
  sourceId: key.sourceId,
  itemId: key.itemId,
  backdrop: key.backdrop,
  index: key.index,
  revision: key.revision,
);

/// Physical pixels, bucketed to reuse nearby window sizes without undersampling
/// high-DPI displays. Visible posters and their warmup must use the same key.
({int width, int height}) posterDecodeSize(
  double logicalWidth,
  double pixelRatio,
) {
  final pixels = logicalWidth.isFinite && logicalWidth > 0
      ? logicalWidth * pixelRatio
      : 512.0;
  final width = ((pixels / 64).ceil() * 64).clamp(64, 2048);
  return (width: width, height: width * 3 ~/ 2);
}

/// ArtworkImageCache's decoded LRU, independent of Flutter's unrelated images.
/// Stable identities reuse pixels even when a byte-provider has auto-disposed.
class ArtworkImagePipeline with WidgetsBindingObserver {
  ArtworkImagePipeline({
    required this.decodes,
    int maximumBytes = 512 * 1024 * 1024,
    int maximumImages = 1800,
  }) {
    cache.maximumSizeBytes = maximumBytes;
    cache.maximumSize = maximumImages;
    WidgetsBinding.instance.addObserver(this);
  }
  final ArtworkDecodeQueue decodes;
  final cache = ImageCache();
  final _variants = <_ArtworkIdentity, Set<ArtworkImageKey>>{};
  final _knownKeys = <ArtworkImageKey>{};
  bool _disposed = false;
  int _warmGeneration = 0;
  ImageProvider<ArtworkImageKey> image(
    ArtworkImageKey key,
    Future<Uint8List> Function() bytes,
  ) => _ArtworkImage(this, key, bytes);

  /// A route may need a different decode size for the same poster. Display
  /// existing pixels while decoding that size, without retaining extra images
  /// outside the bounded ImageCache or mixing accounts/image generations.
  ImageProvider<ArtworkImageKey>? preview(ArtworkImageKey key) {
    final candidates = _variants[_identity(key)];
    if (candidates == null) return null;
    ArtworkImageKey? best;
    for (final candidate in candidates.toList()) {
      final status = cache.statusForKey(candidate);
      if (!status.keepAlive && !status.live) {
        _forget(candidate);
      } else if (best == null || candidate.width > best.width) {
        best = candidate;
      }
    }
    return best == null
        ? null
        : _ArtworkImage(
            this,
            best,
            () => Future.error(StateError('Artwork preview was evicted')),
          );
  }

  void _forget(ArtworkImageKey key) {
    _knownKeys.remove(key);
    final identity = _identity(key);
    final variants = _variants[identity];
    variants?.remove(key);
    if (variants?.isEmpty == true) _variants.remove(identity);
  }

  void _remember(ArtworkImageKey key) {
    _knownKeys.remove(key);
    _knownKeys.add(key);
    (_variants[_identity(key)] ??= {}).add(key);
    while (_knownKeys.length > cache.maximumSize) {
      _forget(_knownKeys.first);
    }
  }

  Future<ImageInfo> _decode(
    ArtworkImageKey key,
    Future<Uint8List> Function() bytes,
  ) async {
    if (_disposed) throw StateError('Artwork cache closed');
    final data = await bytes();
    return decodes.run(() async {
      if (_disposed) throw StateError('Artwork cache closed');
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final ratio = math.min(
            1.0,
            math.min(key.width / width, key.height / height),
          );
          return ui.TargetImageSize(
            width: math.max(1, (width * ratio).round()),
            height: math.max(1, (height * ratio).round()),
          );
        },
      );
      try {
        final frame = await codec.getNextFrame();
        if (_disposed) {
          frame.image.dispose();
          throw StateError('Artwork cache closed');
        }
        _remember(key);
        return ImageInfo(image: frame.image);
      } finally {
        codec.dispose();
      }
    });
  }

  /// Only the upcoming poster window is decoded; no listener outlives warmup.
  Future<void> prewarm(
    List<({ArtworkImageKey key, Future<Uint8List> Function() bytes})> requests,
  ) async {
    final generation = ++_warmGeneration;
    var cursor = 0;
    Future<void> worker() async {
      while (!_disposed &&
          generation == _warmGeneration &&
          cursor < requests.length) {
        final request = requests[cursor++];
        final stream = image(
          request.key,
          request.bytes,
        ).resolve(ImageConfiguration.empty);
        final done = Completer<void>();
        final listener = ImageStreamListener(
          (info, _) {
            info.dispose();
            if (!done.isCompleted) done.complete();
          },
          onError: (Object error, StackTrace? stack) {
            if (!done.isCompleted) done.complete();
          },
        );
        stream.addListener(listener);
        try {
          await done.future;
        } finally {
          stream.removeListener(listener);
        }
      }
    }

    await Future.wait(
      List.generate(requests.length.clamp(0, 4), (_) => worker()),
    );
  }

  @override
  void didHaveMemoryPressure() {
    cache.clear();
    _variants.clear();
    _knownKeys.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    cache.clear();
    cache.clearLiveImages();
    _variants.clear();
    _knownKeys.clear();
  }
}

class _ArtworkImage extends ImageProvider<ArtworkImageKey> {
  const _ArtworkImage(this.owner, this.key, this.bytes);
  final ArtworkImagePipeline owner;
  final ArtworkImageKey key;
  final Future<Uint8List> Function() bytes;
  @override
  Future<ArtworkImageKey> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(key);
  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    ArtworkImageKey key,
    ImageErrorListener handleError,
  ) {
    final completer = owner.cache.putIfAbsent(
      key,
      () =>
          stream.completer ??
          loadImage(
            key,
            PaintingBinding.instance.instantiateImageCodecWithSize,
          ),
      onError: handleError,
    );
    if (completer != null && stream.completer == null) {
      stream.setCompleter(completer);
    }
  }

  @override
  ImageStreamCompleter loadImage(
    ArtworkImageKey key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(owner._decode(key, bytes));
  @override
  Future<ImageCacheStatus?> obtainCacheStatus({
    required ImageConfiguration configuration,
    ImageErrorListener? handleError,
  }) async => owner.cache.statusForKey(key);
  @override
  Future<bool> evict({
    ImageCache? cache,
    ImageConfiguration configuration = ImageConfiguration.empty,
  }) async => (cache ?? owner.cache).evict(key);
  @override
  bool operator ==(Object other) =>
      other is _ArtworkImage &&
      identical(other.owner, owner) &&
      other.key == key;
  @override
  int get hashCode => Object.hash(owner, key);
}
