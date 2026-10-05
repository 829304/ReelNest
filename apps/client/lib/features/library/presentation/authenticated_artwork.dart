import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/library_providers.dart';

class AuthenticatedArtwork extends ConsumerStatefulWidget {
  const AuthenticatedArtwork({
    required this.scope,
    required this.id,
    required this.available,
    super.key,
  });
  final int scope;
  final String id;
  final bool available;

  @override
  ConsumerState<AuthenticatedArtwork> createState() =>
      _AuthenticatedArtworkState();
}

class _AuthenticatedArtworkState extends ConsumerState<AuthenticatedArtwork> {
  Uint8List? _bytes;
  ImageProvider? _image;

  void _evictDecoded() {
    if (_image case final image?) unawaited(image.evict());
    _image = null;
    _bytes = null;
  }

  @override
  void didUpdateWidget(AuthenticatedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope ||
        oldWidget.id != widget.id ||
        oldWidget.available != widget.available) {
      _evictDecoded();
    }
  }

  @override
  void dispose() {
    _evictDecoded();
    super.dispose();
  }

  void _retry() {
    final key = (scope: widget.scope, id: widget.id);
    _evictDecoded();
    ref.read(artworkRepositoryProvider(widget.scope)).evict(widget.id);
    ref.invalidate(artworkProvider(key));
  }

  Widget _placeholder({bool loading = false, bool failed = false}) =>
      ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: loading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : failed
              ? IconButton(
                  onPressed: _retry,
                  tooltip: '重新加载海报',
                  icon: const Icon(Icons.broken_image_outlined),
                )
              : const Icon(Icons.image_outlined, size: 36),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.available) return _placeholder();
    final result = ref.watch(
      artworkProvider((scope: widget.scope, id: widget.id)),
    );
    return result.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      loading: () => _placeholder(loading: true),
      error: (_, _) => _placeholder(failed: true),
      data: (bytes) {
        if (!identical(_bytes, bytes)) {
          _evictDecoded();
          _bytes = bytes;
          _image = ResizeImage(MemoryImage(bytes), width: 320);
        }
        return Image(
          image: _image!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => _placeholder(failed: true),
        );
      },
    );
  }
}
