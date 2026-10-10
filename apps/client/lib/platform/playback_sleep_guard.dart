import 'dart:async';

import 'package:flutter/services.dart';

/// Each Flutter engine aggregates its live decoders. Releasing the old decoder
/// during a switch must not release the new decoder's native power request.
class PlaybackSleepGuard {
  PlaybackSleepGuard(this.onWarning);
  final void Function(String?) onWarning;
  static const _channel = MethodChannel('reelnest/playback_sleep');
  static final _holders = <PlaybackSleepGuard>{};
  static Future<void> _pending = Future.value();
  static bool _active = false;
  bool _enabled = false;
  bool _disposed = false;

  void update(bool playing) {
    if (_disposed || playing == _enabled) return;
    _enabled = playing;
    if (playing) {
      _holders.add(this);
    } else {
      _holders.remove(this);
    }
    _schedule();
  }

  void _schedule() {
    _pending = _pending.then((_) async {
      final desired = _holders.isNotEmpty;
      if (desired == _active) return;
      try {
        await _channel.invokeMethod<void>('setActive', desired);
        _active = desired;
        if (!_disposed) onWarning(null);
      } catch (_) {
        if (!_disposed) onWarning('播放防休眠设置失败，请检查系统电源权限。');
      }
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _holders.remove(this);
    _schedule();
    await _pending;
  }
}
