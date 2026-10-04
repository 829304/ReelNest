import 'package:flutter/material.dart';

import '../../../domain/media.dart';
import 'authenticated_artwork.dart';

class MediaCard extends StatefulWidget {
  const MediaCard({required this.item, required this.scope,
    required this.onOpen, super.key});
  final MediaItem item;
  final int scope;
  final VoidCallback onOpen;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final active = _hovered || _focused;
    return Tooltip(
      message: item.title,
      child: AnimatedScale(
        scale: active && !reduceMotion ? 1.018 : 1,
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
        alignment: Alignment.bottomCenter,
        child: Material(
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onOpen,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            child: Stack(fit: StackFit.expand, children: [
              AuthenticatedArtwork(scope: widget.scope, id: item.id,
                available: item.artworkAvailable),
              const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x1F000000), Color(0xC7000000)]),
              ))),
              Positioned(left: 12, right: 12, bottom: 12,
                child: IgnorePointer(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white,
                        fontSize: 14, fontWeight: FontWeight.bold)),
                    if (item.progress > 0 && item.progress < 0.98) ...[
                      const SizedBox(height: 5),
                      LinearProgressIndicator(value: item.progress,
                        minHeight: 3, backgroundColor: Colors.white24),
                    ],
                    if (active) ...[
                      const SizedBox(height: 5),
                      Text([mediaTypes[item.type] ?? item.type,
                        if (item.year != null) '${item.year}',
                        if (item.isSeries) '系列',
                      ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ],
                ))),
              if (item.watched)
                const Positioned(top: 9, right: 9,
                  child: Tooltip(message: '已看', child: Icon(Icons.check_circle,
                    color: Colors.lightGreenAccent, size: 22))),
              IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _focused
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: active ? 0.38 : 0.18),
                  width: _focused ? 2.5 : active ? 1.1 : 0.7),
              ))),
            ]),
          ),
        ),
      ),
    );
  }
}
