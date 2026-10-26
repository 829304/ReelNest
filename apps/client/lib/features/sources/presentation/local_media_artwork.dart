import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/emby_providers.dart';
import '../data/artwork_image_pipeline.dart';
import '../../metadata/application/tmdb_providers.dart';
import '../../metadata/data/tmdb_artwork_store.dart';

import 'package:path/path.dart' as p;

import '../../../domain/media.dart';
import '../../../domain/media_source.dart';

/// Shared poster rendering. File and Emby-compatible data never use legacy
/// Mlink artwork/auth.
class LocalMediaArtwork extends ConsumerWidget {
  const LocalMediaArtwork({
    required this.source,
    required this.item,
    this.fit = BoxFit.cover,
    this.revision,
    this.backdrop = false,
    this.placeholder,
    super.key,
  });
  final MediaSource source;
  final IndexedMedia item;
  final BoxFit fit;
  final int? revision;
  final bool backdrop;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useBackdrop = backdrop && item.backdropPath != null;
    final relative = useBackdrop ? item.backdropPath : item.posterPath;
    final placeholder =
        this.placeholder ??
        LocalPosterPlaceholder(title: item.cardTitle, type: item.displayType);
    if (relative == null) return placeholder;
    if (source.kind.isEmbyCompatible) {
      final pipeline = ref.watch(embyImagePipelineProvider);
      final key = (
        sourceId: source.id,
        itemId: relative,
        backdrop: useBackdrop,
        revision: math.max(
          revision ?? 0,
          source.lastScan?.millisecondsSinceEpoch ?? 0,
        ),
      );
      return LayoutBuilder(
        builder: (context, size) {
          final target = posterDecodeSize(
            size.maxWidth,
            MediaQuery.devicePixelRatioOf(context),
          );
          final imageKey = (
            sourceId: key.sourceId,
            itemId: key.itemId,
            backdrop: key.backdrop,
            index: 0,
            width: target.width,
            height: target.height,
            revision: key.revision,
          );
          final cached = pipeline.preview(imageKey);
          final preview = cached == null
              ? placeholder
              : Image(
                  image: cached,
                  fit: fit,
                  width: double.infinity,
                  height: double.infinity,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => placeholder,
                );
          return Image(
            image: pipeline.image(
              imageKey,
              () => ref.read(embyArtworkProvider(key).future),
            ),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => placeholder,
            frameBuilder: (_, child, frame, synchronous) =>
                frame == null ? preview : child,
          );
        },
      );
    }
    if (TmdbArtworkStore.isReference(relative)) {
      return ref
          .watch(tmdbArtworkFileProvider(relative))
          .when(
            loading: () => placeholder,
            error: (_, _) => placeholder,
            data: (file) =>
                _fileImage(context, file, placeholder, revision ?? 0),
          );
    }
    final path = p.joinAll([source.location, ...p.posix.split(relative)]);
    return _fileImage(
      context,
      File(path),
      placeholder,
      source.lastScan?.millisecondsSinceEpoch ?? 0,
    );
  }

  Widget _fileImage(
    BuildContext context,
    File file,
    Widget placeholder,
    int imageRevision,
  ) {
    return LayoutBuilder(
      builder: (context, size) {
        final width = (size.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(1, 2048);
        return Image(
          image: ResizeImage(
            _ScannedFileImage(file, imageRevision),
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
    this.selectionMode = false,
    this.selected = false,
    this.suppressHover = false,
    this.progress = 0,
    this.rating,
    this.badges = const [],
    super.key,
  });
  final MediaSource source;
  final IndexedMedia item;
  final VoidCallback onOpen;
  final bool selectionMode, selected, suppressHover;
  final double progress;
  final double? rating;
  final List<String> badges;
  @override
  State<LocalMediaCard> createState() => _LocalMediaCardState();
}

class _LocalMediaCardState extends State<LocalMediaCard> {
  bool _hovering = false;
  bool _focused = false;
  late Widget _artwork;

  @override
  void initState() {
    super.initState();
    _updateArtwork();
  }

  @override
  void didUpdateWidget(LocalMediaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source) ||
        !identical(oldWidget.item, widget.item)) {
      _updateArtwork();
    }
    if (!oldWidget.suppressHover && widget.suppressHover) {
      _hovering = false;
    }
  }

  void _updateArtwork() {
    _artwork = LocalMediaArtwork(source: widget.source, item: widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final progress = widget.progress.clamp(0.0, 1.0);
    final selected = widget.selected && widget.selectionMode;
    final active =
        !widget.selectionMode &&
        (_focused || (_hovering && !widget.suppressHover));
    return Semantics(
      button: true,
      label: widget.item.cardTitle,
      selected: widget.selectionMode ? widget.selected : null,
      child: Tooltip(
        message: widget.item.cardTitle,
        child: AnimatedScale(
          scale: active && !reduceMotion ? 1.018 : 1,
          alignment: Alignment.bottomCenter,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .24),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _artwork,
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x26000000),
                          Color(0xD1000000),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.item.cardTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            height: 1.15,
                            shadows: [
                              Shadow(color: Color(0x99000000), blurRadius: 6),
                            ],
                          ),
                        ),
                        if (progress > 0 && progress < .98) ...[
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox(
                              height: 4,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: Colors.white.withValues(alpha: .30),
                                  ),
                                  FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress,
                                    child: const ColoredBox(
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        AnimatedSize(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          alignment: Alignment.topLeft,
                          child: active && widget.badges.isNotEmpty
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Wrap(
                                    spacing: 5,
                                    runSpacing: 5,
                                    children: widget.badges
                                        .take(3)
                                        .map(_badge)
                                        .toList(),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white.withValues(
                                alpha: active ? .38 : .18,
                              ),
                        width: selected
                            ? 2.5
                            : active
                            ? 1.1
                            : .7,
                      ),
                    ),
                  ),
                  if (widget.selectionMode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0x57000000),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 22,
                            color: widget.selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white,
                          ),
                        ),
                      ),
                    )
                  else if (widget.rating case final rating? when rating > 0)
                    Positioned(
                      top: 9,
                      right: 9,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .46),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .12),
                              width: .7,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              '★ ${rating.toStringAsFixed(1)}',
                              style: const TextStyle(
                                color: Color(0xFFFFCE4A),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: widget.onOpen,
                    onHover: (value) {
                      if (widget.suppressHover) {
                        if (_hovering) setState(() => _hovering = false);
                        return;
                      }
                      if (_hovering != value) {
                        setState(() => _hovering = value);
                      }
                    },
                    onFocusChange: (value) {
                      if (_focused != value) {
                        setState(() => _focused = value);
                      }
                    },
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
        ),
      ),
    );
  }

  Widget _badge(String text) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .44),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: .16), width: .7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        text,
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
