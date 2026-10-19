import 'dart:async';

import 'package:flutter/material.dart';

import '../application/playback_session.dart';
import '../domain/video_color_adjustments.dart';
import '../domain/video_display_settings.dart';
import '../domain/video_performance_settings.dart';
import '../domain/video_render_settings.dart';
import '../domain/video_sharpen_mode.dart';
import 'player_visuals.dart';

/// PlayerView.swift's "画面显示" and "画面调整" settings groups.
///
/// These controls expose the original aspect, crop, deinterlace, rotation,
/// mirror, five color adjustments, sharpening, buffering, hardware decode,
/// debanding and HDR tone mapping. Denoising remains outside the current
/// migration scope.
class PlayerVideoDisplaySettings extends StatelessWidget {
  const PlayerVideoDisplaySettings({
    required this.session,
    required this.palette,
    super.key,
  });

  final PlaybackSession session;
  final PlayerPalette palette;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final value = session.displaySettings;
      return Column(
        key: const ValueKey('player-video-display-settings'),
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            '画面显示',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: palette.subdued,
            ),
          ),
          _row(
            '画面比例',
            Icons.aspect_ratio_rounded,
            _choices<VideoAspectOverride>(
              VideoAspectOverride.values,
              value.aspectOverride,
              (item) => item.displayName,
              (item) => unawaited(
                session.updateDisplaySettings(
                  (current) => current.copyWith(aspectOverride: item),
                ),
              ),
              keyFor: (item) => ValueKey('video-aspect-${item.name}'),
            ),
          ),
          _row(
            '黑边裁切',
            Icons.crop_rounded,
            _choices<VideoCropMode>(
              VideoCropMode.values,
              value.cropMode,
              (item) => item.displayName,
              (item) => unawaited(
                session.updateDisplaySettings(
                  (current) => current.copyWith(cropMode: item),
                ),
              ),
              keyFor: (item) => ValueKey('video-crop-${item.name}'),
            ),
          ),
          _row(
            '去隔行',
            Icons.dehaze_rounded,
            _choices<VideoDeinterlaceMode>(
              VideoDeinterlaceMode.values,
              value.deinterlaceMode,
              (item) => item.displayName,
              (item) => unawaited(
                session.updateDisplaySettings(
                  (current) => current.copyWith(deinterlaceMode: item),
                ),
              ),
              keyFor: (item) => ValueKey('video-deinterlace-${item.name}'),
            ),
          ),
          _row(
            '画面旋转',
            Icons.rotate_right_rounded,
            _choices<VideoRotationMode>(
              VideoRotationMode.values,
              value.rotationMode,
              (item) => item.displayName,
              (item) => unawaited(
                session.updateDisplaySettings(
                  (current) => current.copyWith(rotationMode: item),
                ),
              ),
              keyFor: (item) => ValueKey('video-rotation-${item.name}'),
            ),
          ),
          _row(
            '镜像翻转',
            Icons.compare_arrows_rounded,
            _choices<VideoFlipMode>(
              VideoFlipMode.values,
              value.flipMode,
              (item) => item.displayName,
              (item) => unawaited(
                session.updateDisplaySettings(
                  (current) => current.copyWith(flipMode: item),
                ),
              ),
              keyFor: (item) => ValueKey('video-flip-${item.name}'),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '画面调整',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: palette.subdued,
            ),
          ),
          _colorRow(
            '亮度',
            Icons.wb_sunny_outlined,
            'brightness',
            value: session.colorAdjustments.brightness,
            read: (current) => current.brightness,
            update: (current, next) => current.copyWith(brightness: next),
          ),
          _colorRow(
            '对比度',
            Icons.contrast_rounded,
            'contrast',
            value: session.colorAdjustments.contrast,
            read: (current) => current.contrast,
            update: (current, next) => current.copyWith(contrast: next),
          ),
          _colorRow(
            '饱和度',
            Icons.water_drop_outlined,
            'saturation',
            value: session.colorAdjustments.saturation,
            read: (current) => current.saturation,
            update: (current, next) => current.copyWith(saturation: next),
          ),
          _colorRow(
            '伽马',
            Icons.auto_fix_high_rounded,
            'gamma',
            value: session.colorAdjustments.gamma,
            read: (current) => current.gamma,
            update: (current, next) => current.copyWith(gamma: next),
          ),
          _colorRow(
            '色相',
            Icons.palette_outlined,
            'hue',
            value: session.colorAdjustments.hue,
            read: (current) => current.hue,
            update: (current, next) => current.copyWith(hue: next),
          ),
          _row(
            '锐化',
            Icons.change_history_rounded,
            _choices<VideoSharpenMode>(
              VideoSharpenMode.values,
              session.sharpenMode,
              (item) => item.displayName,
              (item) => unawaited(session.setSharpenMode(item)),
              keyFor: (item) => ValueKey('video-sharpen-${item.name}'),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '播放性能',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: palette.subdued,
            ),
          ),
          _row(
            '弱网内存缓冲',
            Icons.memory_rounded,
            _SettingsToggle(
              toggleKey: const ValueKey('video-memory-buffering-toggle'),
              value: session.performanceSettings.memoryBufferingEnabled,
              palette: palette,
              onChanged: (enabled) => unawaited(
                session.updatePerformanceSettings(
                  memoryBufferingEnabled: enabled,
                ),
              ),
            ),
          ),
          _row(
            '硬件解码',
            Icons.developer_board_rounded,
            _choices<VideoHardwareDecodingMode>(
              VideoHardwareDecodingMode.values,
              session.performanceSettings.hardwareDecodingMode,
              (item) => item.displayName,
              (item) => unawaited(
                session.updatePerformanceSettings(hardwareDecodingMode: item),
              ),
              keyFor: (item) =>
                  ValueKey('video-hardware-decoding-${item.name}'),
            ),
          ),
          _row(
            '去色带',
            Icons.auto_awesome_rounded,
            _choices<VideoDebandMode>(
              VideoDebandMode.values,
              session.renderSettings.debandMode,
              (item) => item.displayName,
              (item) =>
                  unawaited(session.updateRenderSettings(debandMode: item)),
              keyFor: (item) => ValueKey('video-deband-${item.name}'),
            ),
          ),
          _row(
            'HDR 映射',
            Icons.hdr_on_rounded,
            _choices<VideoToneMappingMode>(
              VideoToneMappingMode.values,
              session.renderSettings.toneMappingMode,
              (item) => item.displayName,
              (item) => unawaited(
                session.updateRenderSettings(toneMappingMode: item),
              ),
              keyFor: (item) => ValueKey('video-tone-mapping-${item.name}'),
            ),
          ),
          if (session.controlError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                session.controlError!,
                style: TextStyle(fontSize: 11, color: palette.secondary),
              ),
            ),
        ],
      );
    },
  );

  Widget _row(String title, IconData icon, Widget control) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 32),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        SizedBox(
          width: 112,
          height: 32,
          child: Row(
            spacing: 7,
            children: [
              SizedBox(
                width: 20,
                child: Icon(icon, size: 13, color: palette.secondary),
              ),
              Expanded(
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
            ],
          ),
        ),
        Expanded(
          child: Align(alignment: Alignment.topRight, child: control),
        ),
      ],
    ),
  );

  Widget _choices<T>(
    List<T> items,
    T selected,
    String Function(T) label,
    ValueChanged<T> onSelect, {
    required Key Function(T) keyFor,
  }) => Wrap(
    alignment: WrapAlignment.end,
    spacing: 5,
    runSpacing: 5,
    children: [
      for (final item in items)
        Semantics(
          selected: selected == item,
          button: true,
          child: InkWell(
            key: keyFor(item),
            onTap: () => onSelect(item),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 24,
              constraints: const BoxConstraints(minWidth: 42),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected == item
                    ? palette.choiceSelectedFill
                    : palette.choiceFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected == item
                      ? palette.selectedStroke
                      : palette.rowStroke,
                  width: .8,
                ),
              ),
              child: Text(
                label(item),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected == item
                      ? palette.choiceSelectedForeground
                      : palette.primary,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _colorRow(
    String title,
    IconData icon,
    String keyPrefix, {
    required double value,
    required double Function(VideoColorAdjustments current) read,
    required VideoColorAdjustments Function(
      VideoColorAdjustments current,
      double next,
    )
    update,
  }) => _row(
    title,
    icon,
    _ColorAdjustmentControls(
      value: _colorValueText(value),
      keyPrefix: 'video-color-$keyPrefix',
      palette: palette,
      onDecrease: () => unawaited(
        session.updateColorAdjustments(
          (current) => update(current, read(current) - 5),
        ),
      ),
      onReset: () => unawaited(
        session.updateColorAdjustments((current) => update(current, 0)),
      ),
      onIncrease: () => unawaited(
        session.updateColorAdjustments(
          (current) => update(current, read(current) + 5),
        ),
      ),
    ),
  );

  String _colorValueText(double value) {
    final rounded = value.round();
    return rounded == 0 ? '0' : '${rounded > 0 ? '+' : ''}$rounded';
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.toggleKey,
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final Key toggleKey;
  final bool value;
  final PlayerPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Semantics(
      toggled: value,
      label: value ? '开启' : '关闭',
      child: InkWell(
        key: toggleKey,
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 40,
          height: 22,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? palette.selectedFill : palette.choiceFill,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: palette.rowStroke, width: .8),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 140),
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

class _ColorAdjustmentControls extends StatelessWidget {
  const _ColorAdjustmentControls({
    required this.value,
    required this.keyPrefix,
    required this.palette,
    required this.onDecrease,
    required this.onReset,
    required this.onIncrease,
  });

  final String value;
  final String keyPrefix;
  final PlayerPalette palette;
  final VoidCallback onDecrease;
  final VoidCallback onReset;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      _ColorAdjustmentButton(
        key: ValueKey('$keyPrefix-decrease'),
        tooltip: '减少',
        icon: Icons.remove_rounded,
        palette: palette,
        onPressed: onDecrease,
      ),
      Container(
        key: ValueKey('$keyPrefix-value'),
        width: 76,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.choiceFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.rowStroke, width: .8),
        ),
        child: Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: palette.primary,
          ),
        ),
      ),
      _ColorAdjustmentButton(
        key: ValueKey('$keyPrefix-reset'),
        tooltip: '恢复默认',
        icon: Icons.refresh_rounded,
        palette: palette,
        onPressed: onReset,
      ),
      _ColorAdjustmentButton(
        key: ValueKey('$keyPrefix-increase'),
        tooltip: '增加',
        icon: Icons.add_rounded,
        palette: palette,
        onPressed: onIncrease,
      ),
    ],
  );
}

class _ColorAdjustmentButton extends StatelessWidget {
  const _ColorAdjustmentButton({
    required this.tooltip,
    required this.icon,
    required this.palette,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final PlayerPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 28,
      height: 26,
      child: PlayerMenuRowSurface(
        palette: palette,
        radius: 8,
        minHeight: 26,
        padding: EdgeInsets.zero,
        fill: palette.choiceFill,
        stroke: palette.rowStroke,
        onTap: onPressed,
        child: Center(child: Icon(icon, size: 13, color: palette.secondary)),
      ),
    ),
  );
}
