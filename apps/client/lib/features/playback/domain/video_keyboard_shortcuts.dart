import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Original VideoPlayerShortcutAction order also determines first-match wins
/// when restoring one action brings back a key used by another custom action.
enum VideoShortcutAction {
  playPause('播放 / 暂停', '播放'),
  exitFullscreenOrClose('退出全屏 / 关闭', '播放'),
  closeWindow('关闭播放器', '播放'),
  previousEpisode('上一集', '播放'),
  nextEpisode('下一集', '播放'),
  restart('从头播放', '播放'),
  captureFrame('保存当前画面', '播放'),
  openExternal('用系统播放器打开', '播放'),
  cycleABLoopPoint('设置 A-B 循环点', '播放'),
  clearABLoop('清除 A-B 循环', '播放'),
  toggleCurrentLoop('单片循环开关', '播放'),
  showPlaybackInfo('打开播放信息', '播放'),
  seekBackward('后退默认间隔', '跳转'),
  seekForward('前进默认间隔', '跳转'),
  seekBackwardSmall('后退 5 秒', '跳转'),
  seekForwardSmall('前进 5 秒', '跳转'),
  seekBackwardLarge('后退 60 秒', '跳转'),
  seekForwardLarge('前进 60 秒', '跳转'),
  seekBackwardTen('后退 10 秒', '跳转'),
  seekForwardTen('前进 10 秒', '跳转'),
  volumeUp('调高音量', '窗口与控制'),
  volumeDown('调低音量', '窗口与控制'),
  mute('静音', '窗口与控制'),
  toggleFullscreen('切换全屏', '窗口与控制'),
  goToBeginning('跳到开头', '跳转'),
  goToEnd('跳到结尾', '跳转'),
  speedDown('降低倍速', '画面'),
  speedUp('提高倍速', '画面'),
  resetSpeed('恢复 1x 倍速', '画面'),
  frameBackward('上一帧', '画面'),
  frameForward('下一帧', '画面'),
  audioDelayDown('音频提前 0.1 秒', '音画同步'),
  audioDelayUp('音频延后 0.1 秒', '音画同步'),
  subtitleDelayDown('字幕提前 0.1 秒', '音画同步'),
  subtitleDelayUp('字幕延后 0.1 秒', '音画同步'),
  subtitleSizeDown('缩小字幕', '音画同步'),
  subtitleSizeUp('放大字幕', '音画同步'),
  subtitleMoveUp('字幕上移', '音画同步'),
  subtitleMoveDown('字幕下移', '音画同步'),
  cycleAspectRatio('切换画面比例', '画面'),
  cycleCropMode('切换黑边裁切', '画面'),
  cycleDeinterlaceMode('切换去隔行', '画面'),
  rotateVideoLeft('画面向左旋转', '画面'),
  rotateVideoRight('画面向右旋转', '画面'),
  subtitleCycle('切换字幕轨道', '轨道'),
  subtitleToggle('显示 / 隐藏字幕', '轨道'),
  audioCycle('切换音轨', '轨道'),
  seekTo0Percent('跳到 0%', '跳转'),
  seekTo10Percent('跳到 10%', '跳转'),
  seekTo20Percent('跳到 20%', '跳转'),
  seekTo30Percent('跳到 30%', '跳转'),
  seekTo40Percent('跳到 40%', '跳转'),
  seekTo50Percent('跳到 50%', '跳转'),
  seekTo60Percent('跳到 60%', '跳转'),
  seekTo70Percent('跳到 70%', '跳转'),
  seekTo80Percent('跳到 80%', '跳转'),
  seekTo90Percent('跳到 90%', '跳转'),
  toggleControlsLock('锁定 / 显示控制栏', '窗口与控制'),
  showAdvancedSettings('打开更多设置', '窗口与控制'),
  toggleMiniMode('迷你悬浮窗', '窗口与控制');

  const VideoShortcutAction(this.displayName, this.groupTitle);
  final String displayName, groupTitle;
  static const groups = ['播放', '跳转', '窗口与控制', '画面', '音画同步', '轨道'];
  double? get seekPercent =>
      index >= seekTo0Percent.index && index <= seekTo90Percent.index
      ? (index - seekTo0Percent.index) / 10
      : null;

  List<VideoKeyChord> defaults(TargetPlatform platform) {
    final mac = platform == TargetPlatform.macOS;
    VideoKeyChord key(
      LogicalKeyboardKey value, {
      bool primary = false,
      bool control = false,
      bool alt = false,
      bool shift = false,
    }) => VideoKeyChord(
      value.keyId,
      control: control || (primary && !mac),
      meta: primary && mac,
      alt: alt,
      shift: shift,
    );
    return switch (this) {
      playPause => [
        key(LogicalKeyboardKey.space),
        key(LogicalKeyboardKey.keyK),
      ],
      exitFullscreenOrClose => [key(LogicalKeyboardKey.escape)],
      closeWindow => [
        key(LogicalKeyboardKey.keyW, primary: true),
        key(LogicalKeyboardKey.keyQ),
      ],
      captureFrame => [key(LogicalKeyboardKey.keyS)],
      cycleABLoopPoint => [key(LogicalKeyboardKey.keyB)],
      clearABLoop => [key(LogicalKeyboardKey.keyB, shift: true)],
      showPlaybackInfo => [key(LogicalKeyboardKey.keyI)],
      seekBackward => [key(LogicalKeyboardKey.arrowLeft)],
      seekForward => [key(LogicalKeyboardKey.arrowRight)],
      seekBackwardSmall => [key(LogicalKeyboardKey.arrowLeft, shift: true)],
      seekForwardSmall => [key(LogicalKeyboardKey.arrowRight, shift: true)],
      seekBackwardLarge => [
        key(LogicalKeyboardKey.arrowLeft, alt: true),
        key(LogicalKeyboardKey.pageDown),
      ],
      seekForwardLarge => [
        key(LogicalKeyboardKey.arrowRight, alt: true),
        key(LogicalKeyboardKey.pageUp),
      ],
      seekBackwardTen => [key(LogicalKeyboardKey.keyJ)],
      seekForwardTen => [key(LogicalKeyboardKey.keyL)],
      volumeUp => [key(LogicalKeyboardKey.arrowUp)],
      volumeDown => [key(LogicalKeyboardKey.arrowDown)],
      mute => [key(LogicalKeyboardKey.keyM)],
      toggleFullscreen => [
        key(LogicalKeyboardKey.enter),
        key(LogicalKeyboardKey.keyF),
        key(LogicalKeyboardKey.keyF, primary: true),
      ],
      goToBeginning => [
        key(LogicalKeyboardKey.home),
        key(LogicalKeyboardKey.arrowLeft, primary: true),
      ],
      goToEnd => [
        key(LogicalKeyboardKey.end),
        key(LogicalKeyboardKey.arrowRight, primary: true),
      ],
      speedDown => [key(LogicalKeyboardKey.bracketLeft)],
      speedUp => [key(LogicalKeyboardKey.bracketRight)],
      resetSpeed => [key(LogicalKeyboardKey.backslash)],
      frameBackward => [key(LogicalKeyboardKey.comma)],
      frameForward => [key(LogicalKeyboardKey.period)],
      audioDelayDown => [key(LogicalKeyboardKey.minus, control: true)],
      audioDelayUp => [key(LogicalKeyboardKey.equal, control: true)],
      subtitleDelayDown => [key(LogicalKeyboardKey.keyZ)],
      subtitleDelayUp => [key(LogicalKeyboardKey.keyZ, shift: true)],
      subtitleSizeDown => [key(LogicalKeyboardKey.keyG)],
      subtitleSizeUp => [key(LogicalKeyboardKey.keyG, shift: true)],
      subtitleMoveUp => [key(LogicalKeyboardKey.keyR)],
      subtitleMoveDown => [key(LogicalKeyboardKey.keyR, shift: true)],
      cycleDeinterlaceMode => [key(LogicalKeyboardKey.keyD)],
      subtitleCycle => [key(LogicalKeyboardKey.keyC)],
      subtitleToggle => [key(LogicalKeyboardKey.keyV)],
      audioCycle => [key(LogicalKeyboardKey.keyA)],
      showAdvancedSettings => [key(LogicalKeyboardKey.comma, primary: true)],
      toggleMiniMode => [key(LogicalKeyboardKey.keyP)],
      _ when seekPercent != null => [
        VideoKeyChord(
          LogicalKeyboardKey.digit0.keyId + (seekPercent! * 10).round(),
        ),
      ],
      _ => const [],
    };
  }
}

/// Stable Flutter logical IDs, never macOS/Windows native scan codes. Modifiers
/// are explicit in saved user bindings; only factory defaults map Command to Ctrl.
class VideoKeyChord {
  const VideoKeyChord(
    this.keyId, {
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });
  final int keyId;
  final bool control, alt, shift, meta;
  static final _modifiers = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.scrollLock,
    LogicalKeyboardKey.fn,
  };
  bool get valid =>
      keyId > 0 &&
      keyId <= 0x1fffffffff &&
      !_modifiers.contains(LogicalKeyboardKey(keyId));
  static VideoKeyChord? fromEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    const shifted = r'!@#$%^&*()_+{}|:"<>?~';
    const plain =
        r'1234567890-=[]\;'
        "',./`";
    final label = event.logicalKey.keyLabel;
    final shiftedIndex = keyboard.isShiftPressed && label.length == 1
        ? shifted.indexOf(label)
        : -1;
    final result = VideoKeyChord(
      shiftedIndex >= 0
          ? plain.codeUnitAt(shiftedIndex)
          : event.logicalKey.keyId,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
    );
    return result.valid ? result : null;
  }

  String displayName([TargetPlatform? platform]) {
    final mac = (platform ?? defaultTargetPlatform) == TargetPlatform.macOS;
    final key = LogicalKeyboardKey(keyId);
    final title =
        {
          LogicalKeyboardKey.space: 'Space',
          LogicalKeyboardKey.escape: 'Esc',
          LogicalKeyboardKey.enter: 'Return',
          LogicalKeyboardKey.numpadEnter: 'Return (Num)',
          LogicalKeyboardKey.arrowLeft: 'Left',
          LogicalKeyboardKey.arrowRight: 'Right',
          LogicalKeyboardKey.arrowUp: 'Up',
          LogicalKeyboardKey.arrowDown: 'Down',
          LogicalKeyboardKey.pageUp: 'Page Up',
          LogicalKeyboardKey.pageDown: 'Page Down',
          LogicalKeyboardKey.backspace: 'Delete',
        }[key] ??
        (key.keyLabel.isEmpty ? 'Key $keyId' : key.keyLabel.toUpperCase());
    return [
      if (meta) mac ? 'Command' : 'Meta',
      if (alt) mac ? 'Option' : 'Alt',
      if (control) mac ? 'Control' : 'Ctrl',
      if (shift) 'Shift',
      title,
    ].join('+');
  }

  Map<String, Object> toJson() => {
    'key': keyId,
    'control': control,
    'alt': alt,
    'shift': shift,
    'meta': meta,
  };
  static VideoKeyChord? fromJson(Object? raw) {
    if (raw is! Map || raw['key'] is! int) return null;
    for (final name in ['control', 'alt', 'shift', 'meta']) {
      if (raw[name] != null && raw[name] is! bool) return null;
    }
    final value = VideoKeyChord(
      raw['key'] as int,
      control: raw['control'] == true,
      alt: raw['alt'] == true,
      shift: raw['shift'] == true,
      meta: raw['meta'] == true,
    );
    return value.valid ? value : null;
  }

  @override
  bool operator ==(Object other) =>
      other is VideoKeyChord &&
      keyId == other.keyId &&
      control == other.control &&
      alt == other.alt &&
      shift == other.shift &&
      meta == other.meta;
  @override
  int get hashCode => Object.hash(keyId, control, alt, shift, meta);
}

class VideoKeyboardShortcuts {
  VideoKeyboardShortcuts({
    TargetPlatform? platform,
    Map<VideoShortcutAction, List<VideoKeyChord>> overrides = const {},
  }) : platform = platform ?? defaultTargetPlatform,
       overrides = Map.unmodifiable({
         for (final entry in overrides.entries)
           entry.key: List<VideoKeyChord>.unmodifiable(
             entry.value.where((key) => key.valid).toSet(),
           ),
       });
  final TargetPlatform platform;
  final Map<VideoShortcutAction, List<VideoKeyChord>> overrides;
  List<VideoKeyChord> resolved(VideoShortcutAction action) =>
      overrides[action] ?? action.defaults(platform);
  VideoShortcutAction? actionFor(VideoKeyChord chord) => chord.valid
      ? VideoShortcutAction.values
            .where((action) => resolved(action).contains(chord))
            .firstOrNull
      : null;
  VideoShortcutAction? conflict(
    VideoKeyChord chord, {
    required VideoShortcutAction excluding,
  }) => VideoShortcutAction.values
      .where(
        (action) => action != excluding && resolved(action).contains(chord),
      )
      .firstOrNull;
  VideoKeyboardShortcuts set(
    VideoShortcutAction action,
    List<VideoKeyChord> keys,
  ) {
    final clean = keys.where((key) => key.valid).toSet().toList();
    final next = {...overrides};
    for (final other in VideoShortcutAction.values.where((a) => a != action)) {
      final existing = resolved(other);
      final kept = existing.where((key) => !clean.contains(key)).toList();
      if (existing.length != kept.length) next[other] = kept;
    }
    next[action] = clean;
    return VideoKeyboardShortcuts(platform: platform, overrides: next);
  }

  VideoKeyboardShortcuts reset(VideoShortcutAction action) =>
      VideoKeyboardShortcuts(
        platform: platform,
        overrides: {...overrides}..remove(action),
      );
  VideoKeyboardShortcuts resetAll() =>
      VideoKeyboardShortcuts(platform: platform);
  Map<String, Object> toJson() => {
    for (final entry in overrides.entries)
      entry.key.name: entry.value.map((key) => key.toJson()).toList(),
  };
  static VideoKeyboardShortcuts fromJson(
    Object? raw, {
    TargetPlatform? platform,
  }) {
    final custom = <VideoShortcutAction, List<VideoKeyChord>>{};
    if (raw is Map) {
      for (final action in VideoShortcutAction.values) {
        final list = raw[action.name];
        // A malformed override must not disable the original default binding.
        if (list is! List || list.length > 16) continue;
        final parsed = list.map(VideoKeyChord.fromJson).toList();
        if (parsed.any((key) => key == null)) continue;
        custom[action] = parsed.cast<VideoKeyChord>();
      }
    }
    return VideoKeyboardShortcuts(platform: platform, overrides: custom);
  }
}
