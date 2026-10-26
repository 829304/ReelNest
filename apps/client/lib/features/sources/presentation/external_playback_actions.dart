import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../../playback/application/external_playback_providers.dart';
import '../application/emby_providers.dart';
import '../application/source_providers.dart';
import 'marker_analysis_menu.dart';

Future<MediaIdentity> externalPlaybackIdentity(
  WidgetRef ref,
  IndexedMedia item,
) async {
  if (!item.isSeries) return item.identity;
  if (item.remote != null) await prepareEmbySeries(ref, [item.identity]);
  final sources = ref.read(sourceRepositoryProvider);
  final seasons = await sources.seasons(item.identity);
  if (seasons.isEmpty) throw const SourceFailure('此媒体没有可播放文件。');
  final episodes = await sources.episodes(
    item.identity,
    seasonNumber: seasons.first.number,
    limit: 1,
  );
  if (episodes.items.isEmpty) throw const SourceFailure('此媒体没有可播放文件。');
  return episodes.items.first.identity;
}

Future<void> openLibraryExternally(WidgetRef ref, IndexedMedia item) async {
  final identity = await externalPlaybackIdentity(ref, item);
  await ref.read(externalPlaybackServiceProvider).openLibrary(identity);
}

class ExternalPlaybackButton extends ConsumerStatefulWidget {
  const ExternalPlaybackButton({required this.item, super.key});

  final IndexedMedia item;

  @override
  ConsumerState<ExternalPlaybackButton> createState() =>
      _ExternalPlaybackButtonState();
}

class _ExternalPlaybackButtonState
    extends ConsumerState<ExternalPlaybackButton> {
  bool _busy = false;

  Future<void> _open() async {
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

  @override
  Widget build(BuildContext context) => SourceSheetButton(
    key: const ValueKey('open-library-item-externally'),
    label: _busy ? '正在打开…' : '外部打开',
    icon: const Icon(Icons.open_in_new_rounded, size: 15),
    height: 34,
    horizontalPadding: 13,
    outlined: true,
    onPressed: _busy ? null : _open,
  );
}

/// Local cards previously only exposed marker analysis. Keep that action and
/// add the original explicit external-player command to the same menu.
class LocalVideoContextMenu extends ConsumerStatefulWidget {
  const LocalVideoContextMenu({
    required this.item,
    required this.child,
    super.key,
  });

  final IndexedMedia item;
  final Widget child;

  @override
  ConsumerState<LocalVideoContextMenu> createState() =>
      _LocalVideoContextMenuState();
}

class _LocalVideoContextMenuState extends ConsumerState<LocalVideoContextMenu> {
  final _controller = MenuController();
  bool _busy = false;

  Future<void> _open() async {
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

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _controller,
    menuChildren: [
      MenuItemButton(
        key: const ValueKey('open-local-video-externally'),
        leadingIcon: const Icon(Icons.open_in_new_rounded, size: 16),
        onPressed: _busy ? null : () => unawaited(_open()),
        child: const Text('外部打开'),
      ),
      MarkerAnalysisMenuItem(identity: widget.item.identity),
    ],
    builder: (context, controller, _) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (event) =>
          controller.open(position: event.localPosition),
      child: widget.child,
    ),
  );
}
