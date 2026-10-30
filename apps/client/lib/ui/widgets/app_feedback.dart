import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AppFeedbackKind { information, success, warning, error }

void showAppToast(
  BuildContext context,
  String message, {
  AppFeedbackKind kind = AppFeedbackKind.information,
  Duration duration = const Duration(milliseconds: 4200),
}) {
  if (!context.mounted) return;
  final controller = AppFeedbackScope.maybeControllerOf(context);
  if (controller != null && controller.hasHost) {
    controller.show(message, kind: kind, duration: duration);
    return;
  }
  // Isolated widget hosts that do not install the application feedback scope
  // retain a safe fallback. ReelNestApp always installs the floating host.
  final screenWidth = MediaQuery.sizeOf(context).width;
  final toastWidth = screenWidth >= 480 ? 440.0 : screenWidth - 32;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: AppInlineNotice(message: message, kind: kind, floating: true),
        behavior: SnackBarBehavior.floating,
        width: toastWidth,
        elevation: 0,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
      ),
    );
}

@immutable
class AppFloatingNotice {
  const AppFloatingNotice({
    required this.id,
    required this.message,
    required this.kind,
  });

  final int id;
  final String message;
  final AppFeedbackKind kind;
}

class _PendingAppFloatingNotice {
  const _PendingAppFloatingNotice(this.notice, this.duration);

  final AppFloatingNotice notice;
  final Duration duration;
}

/// Original FloatingNoticeStore semantics: one visible notice, FIFO queue,
/// maximum twelve waiting notices, and a minimum visible duration of 1.2s.
class AppFeedbackController extends ChangeNotifier {
  static const _minimumDuration = Duration(milliseconds: 1200);
  final Queue<_PendingAppFloatingNotice> _queue = Queue();
  AppFloatingNotice? _visible;
  Timer? _timer;
  var _nextId = 0;
  var _hostCount = 0;

  AppFloatingNotice? get visible => _visible;
  int get pendingCount => _queue.length;
  bool get hasHost => _hostCount > 0;

  void _attachHost() => _hostCount += 1;

  void _detachHost() {
    assert(_hostCount > 0);
    _hostCount = math.max(0, _hostCount - 1);
    if (_hostCount != 0) return;
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _visible = null;
  }

  void show(
    String message, {
    AppFeedbackKind kind = AppFeedbackKind.information,
    Duration duration = const Duration(milliseconds: 4200),
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final pending = _PendingAppFloatingNotice(
      AppFloatingNotice(id: ++_nextId, message: trimmed, kind: kind),
      duration < _minimumDuration ? _minimumDuration : duration,
    );
    if (_visible == null) {
      _present(pending);
      return;
    }
    _queue.addLast(pending);
    while (_queue.length > 12) {
      _queue.removeFirst();
    }
  }

  void dismiss(int id) {
    if (_visible?.id != id) {
      _queue.removeWhere((pending) => pending.notice.id == id);
      return;
    }
    _timer?.cancel();
    _timer = null;
    _visible = null;
    notifyListeners();
    if (_queue.isNotEmpty) _present(_queue.removeFirst());
  }

  void _present(_PendingAppFloatingNotice pending) {
    _timer?.cancel();
    _visible = pending.notice;
    notifyListeners();
    _timer = Timer(pending.duration, () => dismiss(pending.notice.id));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _queue.clear();
    super.dispose();
  }
}

class AppFeedbackScope extends StatefulWidget {
  const AppFeedbackScope({required this.child, super.key});

  final Widget child;

  static AppFeedbackController? maybeControllerOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AppFeedbackControllerScope>()
          ?.controller;

  static AppFeedbackController controllerOf(BuildContext context) {
    final controller = maybeControllerOf(context);
    assert(
      controller != null,
      'AppFeedbackScope is missing above this context.',
    );
    return controller!;
  }

  @override
  State<AppFeedbackScope> createState() => _AppFeedbackScopeState();
}

class _AppFeedbackScopeState extends State<AppFeedbackScope> {
  late final AppFeedbackController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppFeedbackController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AppFeedbackControllerScope(controller: _controller, child: widget.child);
}

class _AppFeedbackControllerScope extends InheritedWidget {
  const _AppFeedbackControllerScope({
    required this.controller,
    required super.child,
  });

  final AppFeedbackController controller;

  @override
  bool updateShouldNotify(_AppFeedbackControllerScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Place inside the desktop content column so notices align to content rather
/// than spanning the sidebar. The scope itself lives above the Navigator, so
/// dialogs can enqueue feedback after completing.
class AppFloatingNoticeHost extends StatefulWidget {
  const AppFloatingNoticeHost({required this.child, super.key});

  final Widget child;

  @override
  State<AppFloatingNoticeHost> createState() => _AppFloatingNoticeHostState();
}

class _AppFloatingNoticeHostState extends State<AppFloatingNoticeHost> {
  AppFeedbackController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppFeedbackScope.maybeControllerOf(context);
    if (identical(next, _controller)) return;
    _controller?._detachHost();
    _controller = next;
    next?._attachHost();
  }

  @override
  void dispose() {
    _controller?._detachHost();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: 18,
          left: 0,
          right: 0,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _AppFloatingNoticeSwitcher(
              notice: controller.visible,
              onDismiss: controller.dismiss,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppFloatingNoticeSwitcher extends StatelessWidget {
  const _AppFloatingNoticeSwitcher({
    required this.notice,
    required this.onDismiss,
  });

  final AppFloatingNotice? notice;
  final ValueChanged<int> onDismiss;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: notice == null,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: reduceMotion ? 0 : 220),
          reverseDuration: Duration(milliseconds: reduceMotion ? 0 : 160),
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -.28),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  scale: Tween<double>(begin: .96, end: 1).animate(curved),
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              ),
            );
          },
          child: notice == null
              ? const SizedBox.shrink(
                  key: ValueKey('app-floating-notice-empty'),
                )
              : _AppFloatingNoticeCard(
                  key: ValueKey('app-floating-notice-${notice!.id}'),
                  notice: notice!,
                  onDismiss: () => onDismiss(notice!.id),
                ),
        ),
      ),
    );
  }
}

class _AppFloatingNoticeCard extends StatefulWidget {
  const _AppFloatingNoticeCard({
    required this.notice,
    required this.onDismiss,
    super.key,
  });

  final AppFloatingNotice notice;
  final VoidCallback onDismiss;

  @override
  State<_AppFloatingNoticeCard> createState() => _AppFloatingNoticeCardState();
}

class _AppFloatingNoticeCardState extends State<_AppFloatingNoticeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tint = _appFeedbackTint(widget.notice.kind, dark: dark);
    final icon = _appFeedbackIcon(widget.notice.kind);
    final textStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 13,
      height: 1.25,
      fontWeight: FontWeight.w600,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maximumWidth = math.min(
          560.0,
          math.max(180.0, constraints.maxWidth - 40),
        );
        final painter = TextPainter(
          text: TextSpan(text: widget.notice.message, style: textStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout(maxWidth: maximumWidth);
        final width = (painter.width + 98).clamp(146.0, maximumWidth);
        return Semantics(
          liveRegion: true,
          label: widget.notice.message,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedScale(
              scale: _hovered && !reduceMotion ? 1.006 : 1,
              duration: Duration(milliseconds: reduceMotion ? 0 : 140),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                key: const ValueKey('app-floating-notice-card'),
                duration: Duration(milliseconds: reduceMotion ? 0 : 140),
                width: width,
                constraints: BoxConstraints(
                  minHeight: 48,
                  maxWidth: maximumWidth,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF213040) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF334459)
                        : const Color(0xFFE6EAF1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? .20 : .11),
                      blurRadius: _hovered ? 18 : 14,
                      offset: Offset(0, _hovered ? 8 : 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: dark ? .16 : .11),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 15, color: tint),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.notice.message,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Tooltip(
                      message: '关闭',
                      child: IconButton(
                        key: const ValueKey('app-floating-notice-close'),
                        onPressed: widget.onDismiss,
                        icon: const Icon(Icons.close_rounded, size: 14),
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 22,
                          height: 22,
                        ),
                        splashRadius: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Color _appFeedbackTint(AppFeedbackKind kind, {required bool dark}) =>
    switch (kind) {
      AppFeedbackKind.information => Color(dark ? 0xFF87D0F4 : 0xFF2E90FA),
      AppFeedbackKind.success => Color(dark ? 0xFF67E19A : 0xFF1F9D57),
      AppFeedbackKind.warning => Color(dark ? 0xFFFFC66D : 0xFFD98A00),
      AppFeedbackKind.error => Color(dark ? 0xFFFF8E8E : 0xFFD92D20),
    };

IconData _appFeedbackIcon(AppFeedbackKind kind) => switch (kind) {
  AppFeedbackKind.information => Icons.info_outline_rounded,
  AppFeedbackKind.success => Icons.check_circle_outline_rounded,
  AppFeedbackKind.warning => Icons.warning_amber_rounded,
  AppFeedbackKind.error => Icons.error_outline_rounded,
};

class AppInlineNotice extends StatelessWidget {
  const AppInlineNotice({
    required this.message,
    this.kind = AppFeedbackKind.information,
    this.actionLabel,
    this.onAction,
    this.floating = false,
    super.key,
  });

  final String message;
  final AppFeedbackKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = _appFeedbackTint(kind, dark: dark);
    final icon = _appFeedbackIcon(kind);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: dark ? .14 : .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: .24)),
          boxShadow: floating
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? .26 : .10),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: tint),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(width: 10),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
