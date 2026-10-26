import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/playback_session.dart';
import '../domain/video_keyboard_shortcuts.dart';
import 'player_visuals.dart';

/// Original PlayerAdvancedSettingsOverlay shortcut editor.
///
/// The list stays lazy because the approved surface contains 59 independently
/// configurable actions. Only one row may own keyboard recording at a time.
class PlayerShortcutSettings extends StatefulWidget {
  const PlayerShortcutSettings({
    required this.session,
    required this.palette,
    super.key,
  });

  final PlaybackSession session;
  final PlayerPalette palette;

  @override
  State<PlayerShortcutSettings> createState() => _PlayerShortcutSettingsState();
}

class _PlayerShortcutSettingsState extends State<PlayerShortcutSettings>
    with WidgetsBindingObserver {
  VideoShortcutAction? _recording;

  PlaybackSession get session => widget.session;
  PlayerPalette get palette => widget.palette;

  List<Object> get _entries => [
    for (final group in VideoShortcutAction.groups) ...[
      group,
      ...VideoShortcutAction.values.where(
        (action) => action.groupTitle == group,
      ),
    ],
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopRecording();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _record(VideoShortcutAction action) => setState(() {
    _recording = action;
  });

  void _stopRecording() {
    if (mounted && _recording != null) setState(() => _recording = null);
  }

  void _set(VideoShortcutAction action, List<VideoKeyChord> shortcuts) {
    _stopRecording();
    unawaited(session.setKeyboardShortcuts(action, shortcuts));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  '这些快捷键在视频播放窗口内有效。把一个按键设给新动作时，会自动从原来的动作上移除。',
                  maxLines: 2,
                  style: TextStyle(
                    height: 1.35,
                    fontSize: 11,
                    color: palette.secondary,
                  ),
                ),
              ),
              _ResetAllButton(
                palette: palette,
                onPressed: () {
                  _stopRecording();
                  unawaited(session.resetAllKeyboardShortcuts());
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: ListView.builder(
              key: const ValueKey('player-shortcut-list'),
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                if (entry is String) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 5),
                    child: Text(
                      entry,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: palette.subdued,
                      ),
                    ),
                  );
                }
                final action = entry as VideoShortcutAction;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ShortcutSettingRow(
                    key: ValueKey('player-shortcut-row-${action.name}'),
                    action: action,
                    shortcuts: session.keyboardShortcuts.resolved(action),
                    isRecording: _recording == action,
                    palette: palette,
                    conflictLookup: (shortcut) => session.keyboardShortcuts
                        .conflict(shortcut, excluding: action),
                    onRecord: () => _record(action),
                    onClear: () => _set(action, const []),
                    onReset: () {
                      _stopRecording();
                      unawaited(session.resetKeyboardShortcut(action));
                    },
                    onCancel: _stopRecording,
                    onCapture: (shortcut) => _set(action, [shortcut]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class _ResetAllButton extends StatelessWidget {
  const _ResetAllButton({required this.palette, required this.onPressed});

  final PlayerPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '恢复全部默认快捷键',
    child: InkWell(
      key: const ValueKey('player-shortcut-reset-all'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: palette.choiceFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.rowStroke, width: .8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(Icons.refresh_rounded, size: 12, color: palette.secondary),
            Text(
              '恢复全部默认',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: palette.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ShortcutSettingRow extends StatefulWidget {
  const _ShortcutSettingRow({
    required this.action,
    required this.shortcuts,
    required this.isRecording,
    required this.palette,
    required this.conflictLookup,
    required this.onRecord,
    required this.onClear,
    required this.onReset,
    required this.onCancel,
    required this.onCapture,
    super.key,
  });

  final VideoShortcutAction action;
  final List<VideoKeyChord> shortcuts;
  final bool isRecording;
  final PlayerPalette palette;
  final VideoShortcutAction? Function(VideoKeyChord) conflictLookup;
  final VoidCallback onRecord;
  final VoidCallback onClear;
  final VoidCallback onReset;
  final VoidCallback onCancel;
  final ValueChanged<VideoKeyChord> onCapture;

  @override
  State<_ShortcutSettingRow> createState() => _ShortcutSettingRowState();
}

class _ShortcutSettingRowState extends State<_ShortcutSettingRow> {
  final _recorderFocus = FocusNode(debugLabel: 'shortcut-recorder');
  VideoKeyChord? _pendingShortcut;
  VideoShortcutAction? _conflictAction;

  PlayerPalette get palette => widget.palette;

  @override
  void didUpdateWidget(_ShortcutSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isRecording) {
      _pendingShortcut = null;
      _conflictAction = null;
    } else if (!oldWidget.isRecording) {
      _requestRecorderFocus();
    }
  }

  @override
  void dispose() {
    _recorderFocus.dispose();
    super.dispose();
  }

  void _requestRecorderFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isRecording) _recorderFocus.requestFocus();
    });
  }

  void _beginRecording() {
    setState(() {
      _pendingShortcut = null;
      _conflictAction = null;
    });
    widget.onRecord();
    _requestRecorderFocus();
  }

  void _cancel() {
    setState(() {
      _pendingShortcut = null;
      _conflictAction = null;
    });
    widget.onCancel();
  }

  void _capture(VideoKeyChord shortcut) {
    final conflict = widget.conflictLookup(shortcut);
    if (conflict != null) {
      setState(() {
        _pendingShortcut = shortcut;
        _conflictAction = conflict;
      });
      _requestRecorderFocus();
      return;
    }
    widget.onCapture(shortcut);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.isRecording) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      final shortcut = VideoKeyChord.fromEvent(event);
      if (shortcut != null) _capture(shortcut);
    }
    // Recording owns both down/up/repeat so playback never sees the same key.
    return KeyEventResult.handled;
  }

  void _handleFocusChange(bool focused) {
    if (focused || !widget.isRecording) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isRecording && !_recorderFocus.hasFocus) {
        widget.onCancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shortcutText = widget.shortcuts
        .map((shortcut) => shortcut.displayName())
        .join(' / ');
    return Focus(
      focusNode: _recorderFocus,
      canRequestFocus: widget.isRecording,
      onFocusChange: _handleFocusChange,
      onKeyEvent: _handleKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            spacing: 10,
            children: [
              SizedBox(
                width: 142,
                child: Text(
                  widget.action.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.secondary,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 26),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: palette.choiceFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.rowStroke, width: .8),
                  ),
                  child: Text(
                    shortcutText.isEmpty ? '未设置' : shortcutText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: shortcutText.isEmpty
                          ? palette.subdued
                          : palette.primary,
                    ),
                  ),
                ),
              ),
              Row(
                spacing: 5,
                children: [
                  _ShortcutButton(
                    key: ValueKey(
                      'player-shortcut-record-${widget.action.name}',
                    ),
                    tooltip: widget.isRecording ? '等待按键' : '记录快捷键',
                    icon: Icons.keyboard_rounded,
                    palette: palette,
                    selected: widget.isRecording,
                    onPressed: _beginRecording,
                  ),
                  _ShortcutButton(
                    key: ValueKey(
                      'player-shortcut-clear-${widget.action.name}',
                    ),
                    tooltip: '清除快捷键',
                    icon: Icons.close_rounded,
                    palette: palette,
                    onPressed: widget.onClear,
                  ),
                  _ShortcutButton(
                    key: ValueKey(
                      'player-shortcut-reset-${widget.action.name}',
                    ),
                    tooltip: '恢复默认',
                    icon: Icons.refresh_rounded,
                    palette: palette,
                    onPressed: widget.onReset,
                  ),
                ],
              ),
            ],
          ),
          if (_pendingShortcut != null && _conflictAction != null)
            _conflictBanner(_pendingShortcut!, _conflictAction!)
          else if (widget.isRecording)
            Container(
              key: ValueKey('player-shortcut-recording-${widget.action.name}'),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: palette.selectedFill.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                spacing: 8,
                children: [
                  Icon(
                    Icons.keyboard_rounded,
                    size: 12,
                    color: palette.primary,
                  ),
                  Text(
                    '按下新的组合键',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: ValueKey(
                      'player-shortcut-record-cancel-${widget.action.name}',
                    ),
                    onPressed: _cancel,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.secondary,
                      textStyle: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      minimumSize: const Size(0, 24),
                    ),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _conflictBanner(
    VideoKeyChord shortcut,
    VideoShortcutAction conflict,
  ) => Container(
    key: ValueKey('player-shortcut-conflict-${widget.action.name}'),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: palette.selectedFill.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: palette.selectedStroke, width: .8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Row(
          spacing: 6,
          children: [
            Icon(Icons.warning_amber_rounded, size: 12, color: palette.primary),
            Expanded(
              child: Text(
                '“${shortcut.displayName()}” 已用于「${conflict.displayName}」',
                maxLines: 2,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                ),
              ),
            ),
          ],
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                '替换后将从「${conflict.displayName}」移除该键',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: palette.subdued),
              ),
            ),
            TextButton(
              key: ValueKey(
                'player-shortcut-conflict-replace-${widget.action.name}',
              ),
              onPressed: () => widget.onCapture(shortcut),
              style: _bannerButtonStyle(palette.primary),
              child: const Text('替换'),
            ),
            TextButton(
              key: ValueKey(
                'player-shortcut-conflict-cancel-${widget.action.name}',
              ),
              onPressed: _cancel,
              style: _bannerButtonStyle(palette.secondary),
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    ),
  );

  ButtonStyle _bannerButtonStyle(Color color) => TextButton.styleFrom(
    foregroundColor: color,
    textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    minimumSize: const Size(0, 24),
  );
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.tooltip,
    required this.icon,
    required this.palette,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final PlayerPalette palette;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 26,
      height: 24,
      child: PlayerControlSurface(
        palette: palette,
        enabled: true,
        selected: selected,
        capsule: true,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          splashRadius: 13,
          onPressed: onPressed,
          icon: Icon(icon, size: 11, color: palette.secondary),
        ),
      ),
    ),
  );
}
