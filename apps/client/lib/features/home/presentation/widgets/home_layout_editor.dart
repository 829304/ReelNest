import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../ui/theme/source_sheet_palette.dart';
import '../../application/home_layout_provider.dart';
import '../../domain/home_layout.dart';

IconData homeModuleIcon(HomeModule module) => switch (module) {
  HomeModule.hero => Icons.auto_awesome_outlined,
  HomeModule.stats => Icons.bar_chart,
  HomeModule.dashboard => Icons.speed,
  HomeModule.seriesRecommendations => Icons.live_tv_outlined,
  HomeModule.continueWatching => Icons.play_circle_outline,
  HomeModule.recentlyPlayed => Icons.history,
  HomeModule.watchlist => Icons.bookmark_border,
  HomeModule.favorites => Icons.favorite_border,
  HomeModule.musicRecommendations => Icons.music_note_outlined,
  HomeModule.continueListening => Icons.headphones_outlined,
  HomeModule.recentSeries => Icons.update,
  HomeModule.highRated => Icons.star_border,
};

/// The wrapper hierarchy is identical in and out of editing: changing modes or
/// moving the keyed outer sliver must not dispose the actual module content.
class HomeEditableModule extends StatefulWidget {
  const HomeEditableModule({
    required this.module,
    required this.editing,
    required this.enabled,
    required this.canHide,
    required this.dragged,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onUpdate,
    required this.onHide,
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });
  final HomeModule module;
  final bool editing, enabled, canHide;
  final HomeModule? dragged;
  final VoidCallback onStart, onEnd, onHide;
  final void Function(HomeModule, HomeModule) onMove;
  final void Function(DragUpdateDetails) onUpdate;
  final Widget child;
  final EdgeInsets padding;
  @override
  State<HomeEditableModule> createState() => _HomeEditableModuleState();
}

class _HomeEditableModuleState extends State<HomeEditableModule> {
  Future<void> _menu(TapDownDetails details) async {
    if (!widget.editing || !widget.enabled) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(details.globalPosition);
    final selected = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: true,
          enabled: widget.canHide,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.remove_circle_outline,
                size: 16,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Text('移除${widget.module.title}'),
            ],
          ),
        ),
      ],
    );
    if (mounted && selected == true && widget.editing && widget.enabled) {
      widget.onHide();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dragged = widget.dragged == widget.module;
      final reduce = MediaQuery.disableAnimationsOf(context);
      return DragTarget<HomeModule>(
        onWillAcceptWithDetails: (details) {
          final accept =
              widget.editing &&
              widget.enabled &&
              widget.dragged != null &&
              details.data != widget.module;
          if (accept) widget.onMove(details.data, widget.module);
          return accept;
        },
        onAcceptWithDetails: (_) => widget.onEnd(),
        builder: (_, _, _) => Draggable<HomeModule>(
          data: widget.module,
          maxSimultaneousDrags: widget.editing && widget.enabled ? 1 : 0,
          allowedButtonsFilter: (buttons) => buttons == kPrimaryMouseButton,
          onDragStarted: widget.onStart,
          onDragUpdate: widget.onUpdate,
          onDragEnd: (_) => widget.onEnd(),
          onDraggableCanceled: (_, _) => widget.onEnd(),
          feedback: _DragPreview(
            module: widget.module,
            width: constraints.maxWidth - widget.padding.horizontal,
            child: widget.child,
          ),
          child: Semantics(
            label: widget.editing ? '拖动${widget.module.title}以调整顺序' : null,
            child: GestureDetector(
              onSecondaryTapDown: widget.editing ? _menu : null,
              behavior: HitTestBehavior.opaque,
              child: AnimatedScale(
                scale: dragged && !reduce ? .985 : 1,
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
                child: AnimatedOpacity(
                  opacity: dragged ? .42 : 1,
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  child: IgnorePointer(
                    ignoring: widget.editing,
                    child: TickerMode(
                      enabled: !widget.editing,
                      child: Padding(
                        padding: widget.padding,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DragPreview extends StatelessWidget {
  const _DragPreview({
    required this.module,
    required this.width,
    required this.child,
  });
  final HomeModule module;
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: IgnorePointer(
      child: Container(
        width: 280,
        height: 176,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .2),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: width,
                    maxWidth: width,
                    maxHeight: double.infinity,
                    child: PageStorage(
                      bucket: PageStorageBucket(),
                      child: TickerMode(enabled: false, child: child),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .46),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        homeModuleIcon(module),
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        module.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class HomeLayoutFooter extends StatelessWidget {
  const HomeLayoutFooter({
    required this.state,
    required this.onEdit,
    required this.onRetry,
    super.key,
  });
  final HomeLayoutState state;
  final VoidCallback onEdit, onRetry;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('home-edit'),
    onPressed: state.ready
        ? onEdit
        : state.error != null
        ? onRetry
        : null,
    style: TextButton.styleFrom(
      foregroundColor: SourceSheetPalette(
        Theme.of(context).brightness == Brightness.dark,
      ).secondary,
      minimumSize: const Size(double.infinity, 46),
    ),
    icon: Icon(state.ready ? Icons.edit_outlined : Icons.refresh, size: 14),
    label: Text(
      state.error != null && !state.ready ? '首页布局读取失败，重试' : '编辑首页',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}

class HomeLayoutEditorDock extends StatelessWidget {
  const HomeLayoutEditorDock({
    required this.state,
    required this.controller,
    super.key,
  });
  final HomeLayoutState state;
  final HomeLayoutController controller;

  Future<void> _add(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final anchor =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final menuHeight = state.layout.addable.isEmpty
        ? 70.0
        : state.layout.addable.length * 42.0 + 20;
    final module = await showMenu<HomeModule>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          anchor.center.dx - 140,
          anchor.top - 8 - menuHeight,
          280,
          menuHeight,
        ),
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 280),
      color: p.card,
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: state.layout.addable.isEmpty
          ? [
              const PopupMenuItem(
                enabled: false,
                height: 50,
                padding: EdgeInsets.zero,
                child: Text('所有组件均已添加', style: TextStyle(fontSize: 13)),
              ),
            ]
          : [
              for (final module in state.layout.addable)
                PopupMenuItem(
                  value: module,
                  height: 42,
                  padding: EdgeInsets.zero,
                  key: ValueKey('home-add-${module.name}'),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF5FF),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          homeModuleIcon(module),
                          size: 14,
                          color: const Color(0xFF2E90FA),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          module.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Text(
                        '添加',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2E90FA),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
    );
    if (context.mounted && module != null) controller.restore(module);
  }

  @override
  Widget build(BuildContext context) {
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final enabled = !state.finishing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    state.error!,
                    style: TextStyle(fontSize: 12, color: p.secondary),
                  ),
                ),
                TextButton(
                  onPressed: enabled ? controller.retrySave : null,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: p.card.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: p.border.withValues(alpha: .9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .12),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (context) => SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      key: const ValueKey('home-layout-add'),
                      onPressed: enabled ? () => _add(context) : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.text,
                        backgroundColor: p.card,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        side: BorderSide(color: p.border),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text(
                        '添加',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (state.layout.canReset) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      key: const ValueKey('home-layout-reset'),
                      tooltip: '恢复默认布局',
                      onPressed: enabled ? controller.reset : null,
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2E90FA), Color(0xFF36BFFA)],
                    ),
                  ),
                  child: SizedBox(
                    height: 36,
                    child: TextButton.icon(
                      key: const ValueKey('home-layout-done'),
                      onPressed: enabled ? controller.finish : null,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      icon: state.finishing
                          ? const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 14),
                      label: const Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
