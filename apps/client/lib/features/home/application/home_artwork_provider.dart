import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../sources/application/emby_providers.dart';
import '../domain/home_artwork_palette.dart';
import '../domain/home_snapshot.dart';

/// Called only for the visible slide. Poster bytes share the existing bounded
/// Emby cache; failures have no effect on the recommendation or its actions.
final homeArtworkPaletteProvider = FutureProvider.autoDispose
    .family<HomeArtworkPalette, HomeVideo>((ref, video) async {
      final item = video.item;
      final relative = item.posterPath;
      if (relative == null || relative.isEmpty) {
        return HomeArtworkPalette.fallback;
      }
      try {
        final source = video.source;
        final bytes = source.kind.isRemoteVideoSource
            ? await ref.watch(
                embyArtworkProvider((
                  sourceId: source.id,
                  itemId: relative,
                  backdrop: false,
                  revision: source.lastScan?.millisecondsSinceEpoch ?? 0,
                )).future,
              )
            : await _localBytes(source, relative);
        if (!ref.mounted || bytes == null) return HomeArtworkPalette.fallback;
        final palette = await ref.read(embyArtworkDecodeProvider).run(() async {
          final codec = await ui.instantiateImageCodec(
            bytes,
            targetWidth: 144,
            targetHeight: 144,
          );
          try {
            final image = (await codec.getNextFrame()).image;
            try {
              final pixels = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              return pixels == null
                  ? HomeArtworkPalette.fallback
                  : HomeArtworkPalette.fromRgba(
                      pixels.buffer.asUint8List(),
                      image.width,
                      image.height,
                    );
            } finally {
              image.dispose();
            }
          } finally {
            codec.dispose();
          }
        });
        if (ref.mounted) {
          final link = ref.keepAlive();
          final expiry = Timer(const Duration(seconds: 30), link.close);
          ref.onDispose(expiry.cancel);
        }
        return palette;
      } catch (_) {
        return HomeArtworkPalette.fallback;
      }
    });

Future<Uint8List?> _localBytes(MediaSource source, String relative) async {
  final file = File(p.joinAll([source.location, ...p.posix.split(relative)]));
  if (await file.length() > 8 * 1024 * 1024) return null;
  return file.readAsBytes();
}
