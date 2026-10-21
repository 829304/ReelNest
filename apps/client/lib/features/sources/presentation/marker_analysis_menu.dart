import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../playback/application/marker_analysis_providers.dart';

/// The original VideoCacheMenuItems entry for a movie, series or episode.
/// Eligibility and series expansion stay in the background-task controller.
class MarkerAnalysisMenuItem extends ConsumerWidget {
  const MarkerAnalysisMenuItem({
    required this.identity,
    this.assumeEligible = false,
    super.key,
  });

  final MediaIdentity identity;
  final bool assumeEligible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!assumeEligible) {
      final eligible = ref.watch(markerAnalysisEligibilityProvider(identity));
      if (eligible.asData?.value != true) return const SizedBox.shrink();
    }
    final controller = ref.read(markerAnalysisProvider);
    return MenuItemButton(
      key: ValueKey(
        'analyze-intro-outro-${identity.sourceId}-${identity.localId}',
      ),
      leadingIcon: const Icon(Icons.auto_awesome_outlined, size: 16),
      onPressed: () => unawaited(_enqueue(context, controller)),
      child: const Text('检测片头片尾'),
    );
  }

  Future<void> _enqueue(
    BuildContext context,
    PlaybackMarkerAnalysisController controller,
  ) async {
    try {
      await controller.enqueue(identity);
    } catch (error) {
      if (!context.mounted) return;
      final message = error is SourceFailure ? error.message : '片头片尾检测失败，请重试。';
      showAppToast(context, message, kind: AppFeedbackKind.error);
    }
  }
}

/// Local media cards and episode rows do not otherwise need a full Emby menu.
/// Wrap them only when the stored item is eligible for marker analysis.
class MarkerAnalysisContextMenu extends ConsumerStatefulWidget {
  const MarkerAnalysisContextMenu({
    required this.identity,
    required this.child,
    super.key,
  });

  final MediaIdentity identity;
  final Widget child;

  @override
  ConsumerState<MarkerAnalysisContextMenu> createState() =>
      _MarkerAnalysisContextMenuState();
}

class _MarkerAnalysisContextMenuState
    extends ConsumerState<MarkerAnalysisContextMenu> {
  final _controller = MenuController();
  var _request = 0;

  @override
  void didUpdateWidget(covariant MarkerAnalysisContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity == widget.identity) return;
    _request++;
    if (_controller.isOpen) _controller.close();
  }

  @override
  void dispose() {
    _request++;
    if (_controller.isOpen) _controller.close();
    super.dispose();
  }

  Future<void> _open(Offset position) async {
    final request = ++_request;
    final identity = widget.identity;
    final eligibility = markerAnalysisEligibilityProvider(identity);
    final hold = ref.listenManual(eligibility, (_, _) {});
    try {
      final eligible = await ref.read(eligibility.future);
      if (!mounted ||
          request != _request ||
          identity != widget.identity ||
          !eligible) {
        return;
      }
      _controller.open(position: position);
    } catch (error) {
      if (!mounted || request != _request || identity != widget.identity) {
        return;
      }
      final message = error is SourceFailure ? error.message : '无法检查当前条目，请重试。';
      showAppToast(context, message, kind: AppFeedbackKind.error);
    } finally {
      hold.close();
    }
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _controller,
    menuChildren: [
      MarkerAnalysisMenuItem(identity: widget.identity, assumeEligible: true),
    ],
    builder: (context, controller, _) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (event) => unawaited(_open(event.localPosition)),
      child: widget.child,
    ),
  );
}
