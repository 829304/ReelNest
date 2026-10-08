import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media.dart';
import '../../../domain/media_source.dart';

/// Local paths never pass through the legacy server artwork/auth providers.
class LocalMediaArtwork extends StatelessWidget {
  const LocalMediaArtwork({
    required this.source,
    required this.item,
    this.fit = BoxFit.cover,
    super.key,
  });
  final MediaSource source;
  final IndexedMedia item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final relative = item.posterPath;
    final placeholder = LocalPosterPlaceholder(
      title: item.cardTitle,
      type: item.type,
    );
    if (relative == null) return placeholder;
    final path = p.joinAll([source.location, ...p.posix.split(relative)]);
    return LayoutBuilder(
      builder: (context, size) {
        final width = (size.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(1, 2048);
        return Image(
          image: ResizeImage(
            _ScannedFileImage(
              File(path),
              source.lastScan?.millisecondsSinceEpoch ?? 0,
            ),
            width: width,
          ),
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          excludeFromSemantics: true,
          errorBuilder: (_, error, stack) => placeholder,
          frameBuilder: (context, child, frame, synchronous) =>
              frame == null ? placeholder : child,
        );
      },
    );
  }
}

/// Same file name may contain a new poster after a rescan.
class _ScannedFileImage extends FileImage {
  const _ScannedFileImage(super.file, this.revision);
  final int revision;
  @override
  bool operator ==(Object other) =>
      other is _ScannedFileImage &&
      other.file.path == file.path &&
      other.scale == scale &&
      other.revision == revision;
  @override
  int get hashCode => Object.hash(file.path, scale, revision);
}

/// GeneratedPlaceholderPalette.swift, balanced poster palette and FNV-1a key.
class LocalPosterPlaceholder extends StatelessWidget {
  const LocalPosterPlaceholder({
    required this.title,
    required this.type,
    super.key,
  });
  final String title;
  final String type;
  static const _swatches = [
    [0x0D5B46, 0x061C18, 0x22D3A8],
    [0x173B63, 0x0A1628, 0x38BDF8],
    [0x143F66, 0x091624, 0x2E90FA],
    [0x5C3A08, 0x1F1304, 0xF7C948],
    [0x6A1019, 0x260609, 0xFF6B7A],
    [0x3D155F, 0x160721, 0xD946EF],
    [0x7A4220, 0x2A1408, 0xFF9F45],
    [0x223A5F, 0x0D1729, 0x8DB7FF],
    [0x5A2440, 0x1E0A15, 0xF9A8D4],
  ];
  static final _glyph = RegExp(r'[^\p{P}\p{S}\s]', unicode: true);

  @override
  Widget build(BuildContext context) {
    var hash = BigInt.parse('14695981039346656037');
    final mask = (BigInt.one << 64) - BigInt.one;
    final prime = BigInt.from(1099511628211);
    for (final byte in utf8.encode('$type|$title')) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    final swatch = _swatches[(hash % BigInt.from(_swatches.length)).toInt()];
    final colors = swatch.map((rgb) => Color(0xff000000 | rgb)).toList();
    final fallback = switch (type) {
      'movie' => '影',
      'tvShow' || 'episode' => '剧',
      'anime' => '番',
      'documentary' => '纪',
      'variety' => '综',
      'homeVideo' => '录',
      'private' => '藏',
      _ => '片',
    };
    final glyph =
        _glyph.firstMatch(title.trim())?.group(0)?.toUpperCase() ?? fallback;
    return LayoutBuilder(
      builder: (context, size) {
        final side = math.max(size.maxWidth, size.maxHeight);
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors.take(2).toList(),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.84,
                    colors: [
                      colors[2].withValues(alpha: .34),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(.44, -.68),
                    radius: 1.28,
                    colors: [
                      Colors.white.withValues(alpha: .10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Positioned(
                left: size.maxWidth * .24,
                bottom: -size.maxHeight * .13,
                child: Transform.rotate(
                  angle: -8 * math.pi / 180,
                  child: Text(
                    glyph,
                    style: TextStyle(
                      fontSize: side * .72,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withValues(alpha: .13),
                    ),
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x42000000),
                      Color(0xAD000000),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: math.max(12, size.maxWidth * .075),
                right: 12,
                bottom: math.max(12, size.maxHeight * .070),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? mediaTypes[type] ?? '未命名媒体' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: (size.maxWidth * .082).clamp(12, 17),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: math.max(3, size.maxHeight * .018)),
                    Text(
                      mediaTypes[type] ?? '媒体',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: (size.maxWidth * .058).clamp(10, 13),
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: .76),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// PosterCardView's 2:3 crop, 18px corners, title inset and bottom gradient.
class LocalMediaCard extends StatefulWidget {
  const LocalMediaCard({
    required this.source,
    required this.item,
    required this.onOpen,
    super.key,
  });
  final MediaSource source;
  final IndexedMedia item;
  final VoidCallback onOpen;
  @override
  State<LocalMediaCard> createState() => _LocalMediaCardState();
}

class _LocalMediaCardState extends State<LocalMediaCard> {
  bool _active = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.item.cardTitle,
    child: Tooltip(
      message: widget.item.cardTitle,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LocalMediaArtwork(source: widget.source, item: widget.item),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x1F000000),
                    Color(0xC7000000),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                widget.item.cardTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: _active ? .38 : .18),
                  width: _active ? 1.1 : .7,
                ),
              ),
            ),
            TextButton(
              onPressed: widget.onOpen,
              onHover: (v) => setState(() => _active = v),
              onFocusChange: (v) => setState(() => _active = v),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ],
        ),
      ),
    ),
  );
}
