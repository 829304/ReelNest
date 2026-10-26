import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/playback_session.dart';
import '../domain/video_keyboard_shortcuts.dart';

/// Window-local shortcut routing. Dialog/recorder routes have their own focus
/// scope and receive input first; editable descendants never drive playback.
class PlayerShortcutRouter extends StatefulWidget {
  const PlayerShortcutRouter({
    required this.session,
    required this.onAction,
    required this.onSeekForwardHold,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final PlaybackSession session;
  final void Function(VideoShortcutAction) onAction;
  final void Function(bool) onSeekForwardHold;
  final bool enabled;
  final Widget child;
  @override
  State<PlayerShortcutRouter> createState() => _PlayerShortcutRouterState();
}

class _PlayerShortcutRouterState extends State<PlayerShortcutRouter>
    with WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'player-keyboard-scope');
  PhysicalKeyboardKey? _heldKey;
  PhysicalKeyboardKey? _forwardDown;
  Object? _engine, _mapping;
  bool _windowActive = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_focusChanged);
    FocusManager.instance.addListener(_primaryFocusChanged);
    widget.session.addListener(_sessionChanged);
    _snapshot();
  }

  void _snapshot() {
    _engine = widget.session.engine;
    _mapping = widget.session.keyboardShortcuts;
  }

  void _sessionChanged() {
    if (_engine != widget.session.engine ||
        _mapping != widget.session.keyboardShortcuts ||
        widget.session.loading) {
      _endHold();
      _snapshot();
    }
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _endHold();
  }

  void _primaryFocusChanged() {
    if (!_focus.hasFocus || _editing) _endHold();
  }

  void _endHold() {
    _forwardDown = null;
    if (_heldKey == null) return;
    _heldKey = null;
    widget.onSeekForwardHold(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _windowActive = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) _endHold();
  }

  @override
  void didUpdateWidget(PlayerShortcutRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      if (_heldKey != null) oldWidget.onSeekForwardHold(false);
      _heldKey = _forwardDown = null;
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
      _snapshot();
    } else if (!widget.enabled) {
      _endHold();
    }
  }

  @override
  void dispose() {
    _endHold();
    widget.session.removeListener(_sessionChanged);
    _focus.removeListener(_focusChanged);
    FocusManager.instance.removeListener(_primaryFocusChanged);
    _focus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _editing {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    var result = false;
    context.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        result = true;
        return false;
      }
      return true;
    });
    return result;
  }

  KeyEventResult _handle(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.physicalKey == _forwardDown || event.physicalKey == _heldKey) {
        _endHold();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!widget.enabled ||
        !_windowActive ||
        event.synthesized ||
        _editing ||
        ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    final chord = VideoKeyChord.fromEvent(event);
    final action = chord == null
        ? null
        : widget.session.keyboardShortcuts.actionFor(chord);
    if (action == null) return KeyEventResult.ignored;
    if (action == VideoShortcutAction.seekForward) {
      if (event is KeyRepeatEvent) {
        if (_forwardDown != event.physicalKey) return KeyEventResult.ignored;
        if (_heldKey == null) {
          _heldKey = event.physicalKey;
          widget.onSeekForwardHold(true);
        }
        return KeyEventResult.handled;
      }
      _forwardDown = event.physicalKey;
    }
    widget.onAction(action);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _handle,
    child: widget.child,
  );
}
