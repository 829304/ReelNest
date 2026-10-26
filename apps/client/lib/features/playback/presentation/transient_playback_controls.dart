import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../domain/transient_playback_target.dart';

typedef OpenTransientStream = Future<void> Function(String value);
typedef OpenTransientFile = Future<void> Function(
  String path, {
  Uint8List? securityBookmark,
});

/// Window-scoped equivalent of the original Cmd+Shift+O Playback menu item.
class TransientPlaybackShortcuts extends StatelessWidget {
  const TransientPlaybackShortcuts({
    required this.onOpenStream,
    required this.child,
    super.key,
  });

  final VoidCallback onOpenStream;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final macOS = defaultTargetPlatform == TargetPlatform.macOS;
    return CallbackShortcuts(
      key: const ValueKey('transient-playback-shortcuts'),
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyO,
          shift: true,
          control: !macOS,
          meta: macOS,
        ): onOpenStream,
      },
      child: child,
    );
  }
}

/// App-wide equivalent of the original macOS Playback menu entries.
///
/// Flutter's desktop shell does not expose that native menu, so the compact
/// button is placed beside the app identity instead of creating a navigation
/// destination for one-shot playback.
class TransientPlaybackMenuButton extends StatefulWidget {
  const TransientPlaybackMenuButton({
    required this.onOpenFile,
    required this.onOpenStream,
    super.key,
  });

  final VoidCallback onOpenFile;
  final VoidCallback onOpenStream;

  @override
  State<TransientPlaybackMenuButton> createState() =>
      _TransientPlaybackMenuButtonState();
}

class _TransientPlaybackMenuButtonState
    extends State<TransientPlaybackMenuButton> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = SourceSheetPalette(dark);
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('open-transient-file'),
          leadingIcon: const Icon(Icons.video_file_outlined, size: 18),
          onPressed: widget.onOpenFile,
          child: const Text('打开文件…'),
        ),
        MenuItemButton(
          key: const ValueKey('open-transient-stream'),
          leadingIcon: const Icon(Icons.language_rounded, size: 18),
          onPressed: widget.onOpenStream,
          child: const Text('打开网络串流…'),
        ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: '打开媒体',
        child: IconButton(
          key: const ValueKey('open-transient-media-menu'),
          tooltip: '',
          onPressed: controller.isOpen ? controller.close : controller.open,
          icon: const Icon(Icons.video_call_outlined, size: 18),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(34),
            maximumSize: const Size.square(34),
            padding: EdgeInsets.zero,
            foregroundColor: palette.secondary,
            backgroundColor: Colors.transparent,
            hoverColor: palette.hoverPill,
            focusColor: palette.hoverPill,
            highlightColor: palette.control,
            side: BorderSide(color: palette.border.withValues(alpha: .72)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual layer for desktop_drop. The package-specific DropTarget remains in
/// the shell so this presentation can be tested without synthesizing native
/// drag events.
class TransientPlaybackDropOverlay extends StatelessWidget {
  const TransientPlaybackDropOverlay({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: reduceMotion ? 0 : 150);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: AnimatedOpacity(
            key: const ValueKey('transient-drop-overlay'),
            opacity: active ? 1 : 0,
            duration: duration,
            child: ColoredBox(
              color: palette.page.withValues(alpha: .78),
              child: Center(
                child: AnimatedScale(
                  scale: active ? 1 : .985,
                  duration: duration,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 360),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: palette.selectedTint.withValues(alpha: .42),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: palette.shadow.withValues(alpha: .12),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.iconChip,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.play_circle_outline_rounded,
                            size: 28,
                            color: palette.selectedTint,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '松开以播放文件',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '仅打开第一个文件，不会加入媒体库。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.secondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Desktop file drop adapter shared by the main shell and player window.
///
/// It intentionally forwards only the first dropped item, matching the
/// original playExternalFiles behavior. The launcher owns validation and must
/// leave any existing playback untouched when opening fails.
class TransientMediaDropTarget extends StatefulWidget {
  const TransientMediaDropTarget({
    required this.openFile,
    required this.onError,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final OpenTransientFile openFile;
  final ValueChanged<Object> onError;
  final Widget child;
  final bool enabled;

  @override
  State<TransientMediaDropTarget> createState() =>
      _TransientMediaDropTargetState();
}

class _TransientMediaDropTargetState extends State<TransientMediaDropTarget> {
  bool _dragging = false;
  bool _opening = false;

  void _setDragging(bool value) {
    if (_dragging == value || !mounted) return;
    setState(() => _dragging = value);
  }

  Future<void> _open(DropDoneDetails details) async {
    _setDragging(false);
    if (_opening || details.files.isEmpty) return;
    setState(() => _opening = true);
    try {
      final file = details.files.first;
      await widget.openFile(
        file.path,
        securityBookmark: file.extraAppleBookmark,
      );
    } catch (error) {
      if (mounted) widget.onError(error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_opening;
    return DropTarget(
      key: const ValueKey('transient-media-drop-target'),
      enable: enabled,
      onDragEntered: (_) {
        if (enabled) _setDragging(true);
      },
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) => unawaited(_open(details)),
      child: TransientPlaybackDropOverlay(
        active: enabled && _dragging,
        child: widget.child,
      ),
    );
  }
}

Future<void> showTransientStreamDialog(
  BuildContext context, {
  required OpenTransientStream onOpen,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => TransientStreamDialog(onOpen: onOpen),
);

/// ContentView.NetworkStreamPromptSheet translated to the shared app sheet
/// surfaces. Validation mirrors AppState.playNetworkStream; the launcher still
/// validates independently before opening the transient player.
class TransientStreamDialog extends StatefulWidget {
  const TransientStreamDialog({required this.onOpen, super.key});

  final OpenTransientStream onOpen;

  @override
  State<TransientStreamDialog> createState() => _TransientStreamDialogState();
}

class _TransientStreamDialogState extends State<TransientStreamDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_inputChanged);
  }

  void _inputChanged() {
    if (!mounted) return;
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_inputChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !TransientPlaybackTarget.streamSchemes.contains(
          uri.scheme.toLowerCase(),
        )) {
      setState(() => _error = '请输入合法的串流地址（http / https / rtsp / rtmp 等）。');
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await widget.onOpen(value);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is SourceFailure ? error.message : '无法打开网络串流，请检查地址后重试。';
      });
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _cancel() {
    if (_opening) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final canOpen = !_opening && _controller.text.trim().isNotEmpty;
    return PopScope(
      canPop: !_opening,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: Dialog(
          key: const ValueKey('transient-stream-dialog'),
          backgroundColor: palette.page,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: palette.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(AppSheetMetrics.horizontalPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSheetHeader(
                    title: '打开网络串流',
                    subtitle: '输入媒体地址，使用内置播放器临时播放。',
                    icon: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.iconChip,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.language_rounded,
                        color: palette.selectedTint,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  TextField(
                    key: const ValueKey('transient-stream-input'),
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    enabled: !_opening,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) {
                      if (canOpen) unawaited(_open());
                    },
                    decoration: InputDecoration(
                      hintText: 'https://example.com/stream.m3u8',
                      prefixIcon: const Icon(Icons.link_rounded, size: 19),
                      errorText: _error,
                      filled: true,
                      fillColor: palette.control,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    '支持 http / https / rtsp / rtmp / rtp / mms / srt / udp / ftp。仅本次播放，不会加入媒体库。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: palette.secondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppSheetActionFooter(
                    panelBorder: palette.panelBorder,
                    solarLightTint: palette.solar,
                    actions: [
                      SourceSheetButton(
                        label: '取消',
                        outlined: true,
                        onPressed: _opening ? null : _cancel,
                      ),
                      SourceSheetButton(
                        key: const ValueKey('transient-stream-submit'),
                        label: _opening ? '正在打开…' : '播放',
                        icon: _opening
                            ? const SizedBox.square(
                                dimension: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        prominent: true,
                        onPressed: canOpen ? () => unawaited(_open()) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
