import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../application/source_providers.dart';
import '../application/url_video_providers.dart';
import 'external_playback_actions.dart';
import 'marker_analysis_menu.dart';
import 'url_video_cache_actions.dart';

/// VideoItemContextMenuItems URL branch: normal video actions plus the stored
/// address command. The URL stays repository-owned and is never reconstructed
/// from the opaque media identity.
class UrlVideoContextMenu extends ConsumerStatefulWidget {
  const UrlVideoContextMenu({
    required this.item,
    required this.child,
    super.key,
  });

  final IndexedMedia item;
  final Widget child;

  @override
  ConsumerState<UrlVideoContextMenu> createState() =>
      _UrlVideoContextMenuState();
}

class _UrlVideoContextMenuState extends ConsumerState<UrlVideoContextMenu> {
  final _controller = MenuController();
  bool _busy = false;

  Future<void> _external() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await openLibraryExternally(ref, widget.item);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          sourceErrorMessage(error),
          kind: AppFeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    try {
      final url = await ref
          .read(urlVideoRepositoryProvider)
          .location(widget.item.identity);
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        showAppToast(context, '已复制链接', kind: AppFeedbackKind.success);
      }
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          sourceErrorMessage(error),
          kind: AppFeedbackKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _controller,
    menuChildren: [
      MenuItemButton(
        key: const ValueKey('open-url-video-externally'),
        leadingIcon: const Icon(Icons.open_in_new_rounded, size: 16),
        onPressed: _busy ? null : () => unawaited(_external()),
        child: const Text('外部打开'),
      ),
      UrlVideoCacheActions(item: widget.item, menuOnly: true),
      MarkerAnalysisMenuItem(identity: widget.item.identity),
      MenuItemButton(
        key: const ValueKey('copy-url-video-link'),
        leadingIcon: const Icon(Icons.link_rounded, size: 16),
        onPressed: _busy ? null : () => unawaited(_copy()),
        child: const Text('复制链接'),
      ),
    ],
    builder: (context, controller, _) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (event) =>
          controller.open(position: event.localPosition),
      child: widget.child,
    ),
  );
}
