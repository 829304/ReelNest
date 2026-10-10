import 'dart:async';

import 'package:flutter/material.dart';

import '../application/playback_session.dart';
import '../domain/playback_options.dart';
import '../domain/video_queue.dart';
import 'player_visuals.dart';

/// PlayerView's playback behavior rows. Advanced tabs remain separate work.
class PlayerBasicSettings extends StatelessWidget {
  const PlayerBasicSettings({
    required this.session,
    required this.palette,
    super.key,
  });
  final PlaybackSession session;
  final PlayerPalette palette;

  void change(PlaybackOptions Function(PlaybackOptions) update) =>
      unawaited(session.changeOptions(update));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final value = session.options;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            '播放行为',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: palette.subdued,
            ),
          ),
          row(
            '默认倍速',
            Icons.speed,
            choices<double>(
              [.75, 1, 1.25, 1.5, 2],
              value.defaultRate,
              (v) =>
                  '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}x',
              (v) => change((o) => o.copyWith(defaultRate: v)),
            ),
          ),
          row(
            '快进/快退',
            Icons.fast_forward,
            choices<double>(
              [5, 10, 15, 30],
              value.skipSeconds,
              (v) => '${v.toInt()}秒',
              (v) => change((o) => o.copyWith(skipSeconds: v)),
            ),
          ),
          row(
            '恢复回退',
            Icons.replay,
            choices<double>(
              [0, 5, 10, 15, 30],
              value.rewindSeconds,
              (v) => v == 0 ? '关闭' : '${v.toInt()}秒',
              (v) => change((o) => o.copyWith(rewindSeconds: v)),
            ),
          ),
          row(
            '记忆进度',
            Icons.history,
            toggle(
              value.rememberPosition,
              (v) => change((o) => o.copyWith(rememberPosition: v)),
            ),
          ),
          row(
            '记忆本片倍速',
            Icons.speed,
            toggle(
              value.rememberRate,
              (v) => change((o) => o.copyWith(rememberRate: v)),
            ),
          ),
          row(
            '启动音量',
            Icons.volume_up,
            toggle(
              value.useLaunchVolume,
              (v) => change((o) => o.copyWith(useLaunchVolume: v)),
            ),
          ),
          if (value.useLaunchVolume)
            row(
              '音量设定',
              Icons.volume_up,
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: value.launchVolume,
                      min: 0,
                      max: 100,
                      label: '${value.launchVolume.round()}%',
                      onChanged: (v) =>
                          change((o) => o.copyWith(launchVolume: v)),
                    ),
                  ),
                  Text(
                    '${value.launchVolume.round()}%',
                    style: TextStyle(fontSize: 11, color: palette.secondary),
                  ),
                ],
              ),
            ),
          row(
            '播放结束',
            Icons.skip_next,
            choices<VideoEndAction>(
              VideoEndAction.values,
              session.endAction,
              (a) => a.label,
              (a) => unawaited(session.setEndAction(a)),
              keyFor: (a) => ValueKey('end-action-${a.name}'),
            ),
          ),
          row(
            '自动标记已看',
            Icons.check_circle_outline,
            toggle(
              value.autoMarkWatched,
              (v) => change((o) => o.copyWith(autoMarkWatched: v)),
            ),
          ),
          row(
            '变调保护',
            Icons.music_note,
            toggle(
              value.pitchCorrection,
              (v) => change((o) => o.copyWith(pitchCorrection: v)),
            ),
          ),
          if (session.controlError != null)
            Text(
              session.controlError!,
              style: TextStyle(fontSize: 11, color: palette.secondary),
            ),
        ],
      );
    },
  );

  Widget row(String title, IconData icon, Widget control) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 28),
    child: Row(
      spacing: 10,
      children: [
        SizedBox(
          width: 104,
          child: Row(
            spacing: 7,
            children: [
              SizedBox(
                width: 20,
                child: Icon(icon, size: 12, color: palette.secondary),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.secondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: control),
      ],
    ),
  );

  Widget choices<T>(
    List<T> items,
    T selected,
    String Function(T) label,
    ValueChanged<T> onSelect, {
    Key Function(T)? keyFor,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    spacing: 5,
    children: [
      for (final item in items)
        Flexible(
          child: Semantics(
            selected: selected == item,
            button: true,
            child: InkWell(
              key: keyFor?.call(item),
              onTap: () => onSelect(item),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 24,
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected == item
                      ? palette.selectedFill
                      : palette.choiceFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    width: .8,
                    color: selected == item
                        ? palette.selectedStroke
                        : palette.rowStroke,
                  ),
                ),
                child: Text(
                  label(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget toggle(bool value, ValueChanged<bool> onChanged) => Align(
    alignment: Alignment.centerRight,
    child: Semantics(
      toggled: value,
      label: value ? '开启' : '关闭',
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: 40,
          height: 22,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? palette.selectedFill : palette.choiceFill,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: palette.rowStroke, width: .8),
          ),
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// PlayerInlineSpeedControl: live .5–3x adjustment, remember only on release.
class PlayerSpeedControl extends StatefulWidget {
  const PlayerSpeedControl({
    required this.session,
    required this.palette,
    super.key,
  });
  final PlaybackSession session;
  final PlayerPalette palette;
  @override
  State<PlayerSpeedControl> createState() => _PlayerSpeedControlState();
}

class _PlayerSpeedControlState extends State<PlayerSpeedControl> {
  double? _drag;
  static const stops = [.5, .75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
  double snap(double value) {
    final nearest = stops.reduce(
      (a, b) => (a - value).abs() < (b - value).abs() ? a : b,
    );
    return (nearest - value).abs() < .045 ? nearest : value;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: widget.session.playbackRate,
    builder: (context, rate, _) {
      final value = (_drag ?? rate).clamp(.5, 3.0);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              spacing: 9,
              children: [
                Expanded(
                  child: Slider(
                    value: value,
                    min: .5,
                    max: 3,
                    onChangeStart: (v) => setState(() => _drag = v),
                    onChanged: (v) {
                      final speed = snap(v);
                      setState(() => _drag = speed);
                      unawaited(widget.session.rate(speed, remember: false));
                    },
                    onChangeEnd: (v) async {
                      await widget.session.rate(snap(v));
                      if (mounted) setState(() => _drag = null);
                    },
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${value.toStringAsFixed(2)}x',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.palette.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 51),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final tick in const [.5, 1.0, 1.5, 2.0, 2.5, 3.0])
                  Text(
                    '${tick}x',
                    style: TextStyle(
                      fontSize: 9,
                      color: widget.palette.subdued,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
