import 'dart:async';

import 'package:flutter/material.dart';

import '../application/playback_session.dart';
import '../domain/video_subtitle_settings.dart';
import 'player_visuals.dart';

const _keepSubtitleFont = Object();

class PlayerSyncSettings extends StatelessWidget {
  const PlayerSyncSettings({
    required this.session,
    required this.palette,
    this.showControlError = true,
    super.key,
  });

  final PlaybackSession session;
  final PlayerPalette palette;
  final bool showControlError;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final timing = session.timing;
      return _SettingsSection(
        title: '音画同步',
        palette: palette,
        children: [
          _SettingsRow(
            title: '音频延迟',
            icon: Icons.volume_up_outlined,
            palette: palette,
            control: _AdjustmentControls(
              value: _delayText(timing.audioDelay),
              valueKey: const ValueKey('audio-delay-value'),
              palette: palette,
              onDecrease: () => unawaited(
                session.audioDelay(
                  (timing.audioDelay - .1).clamp(-3, 3).toDouble(),
                ),
              ),
              onReset: () => unawaited(session.audioDelay(0)),
              onIncrease: () => unawaited(
                session.audioDelay(
                  (timing.audioDelay + .1).clamp(-3, 3).toDouble(),
                ),
              ),
              keyPrefix: 'audio-delay',
            ),
          ),
          _SettingsRow(
            title: '字幕延迟',
            icon: Icons.closed_caption_outlined,
            palette: palette,
            control: _AdjustmentControls(
              value: _delayText(timing.subtitleDelay),
              valueKey: const ValueKey('subtitle-delay-value'),
              palette: palette,
              onDecrease: () => unawaited(
                session.subtitleDelay(
                  (timing.subtitleDelay - .1).clamp(-3, 3).toDouble(),
                ),
              ),
              onReset: () => unawaited(session.subtitleDelay(0)),
              onIncrease: () => unawaited(
                session.subtitleDelay(
                  (timing.subtitleDelay + .1).clamp(-3, 3).toDouble(),
                ),
              ),
              keyPrefix: 'subtitle-delay',
            ),
          ),
          _SettingsRow(
            title: '字幕大小',
            icon: Icons.format_size_rounded,
            palette: palette,
            control: _AdjustmentControls(
              value: '${(timing.subtitleScale * 100).round()}%',
              valueKey: const ValueKey('subtitle-scale-value'),
              palette: palette,
              onDecrease: () => unawaited(
                session.subtitleScale(
                  (timing.subtitleScale - .05).clamp(.75, 1.5).toDouble(),
                ),
              ),
              onReset: () => unawaited(session.subtitleScale(1)),
              onIncrease: () => unawaited(
                session.subtitleScale(
                  (timing.subtitleScale + .05).clamp(.75, 1.5).toDouble(),
                ),
              ),
              keyPrefix: 'subtitle-scale',
            ),
          ),
          _SettingsRow(
            title: '字幕位置',
            icon: Icons.format_line_spacing_rounded,
            palette: palette,
            control: _AdjustmentControls(
              value: '${timing.subtitlePosition.round()}%',
              valueKey: const ValueKey('subtitle-position-value'),
              palette: palette,
              onDecrease: () => unawaited(
                session.subtitlePosition(
                  (timing.subtitlePosition - 4).clamp(70, 100).toDouble(),
                ),
              ),
              onReset: () => unawaited(session.subtitlePosition(100)),
              onIncrease: () => unawaited(
                session.subtitlePosition(
                  (timing.subtitlePosition + 4).clamp(70, 100).toDouble(),
                ),
              ),
              keyPrefix: 'subtitle-position',
            ),
          ),
          if (showControlError && session.controlError != null)
            PlayerInlineNotice(
              message: session.controlError!,
              palette: palette,
            ),
        ],
      );
    },
  );
}

class PlayerSubtitleStyleSettings extends StatelessWidget {
  const PlayerSubtitleStyleSettings({
    required this.session,
    required this.palette,
    required this.fontFamilies,
    required this.onRetryFonts,
    this.showControlError = true,
    super.key,
  });

  final PlaybackSession session;
  final PlayerPalette palette;
  final Future<List<String>> fontFamilies;
  final VoidCallback onRetryFonts;
  final bool showControlError;

  void update({
    Object? fontName = _keepSubtitleFont,
    bool? bold,
    VideoSubtitleColorPreset? colorPreset,
    double? borderSize,
    double? backgroundOpacity,
  }) {
    unawaited(
      session.updateSubtitleStyle(
        (current) => current.copyWith(
          fontName: identical(fontName, _keepSubtitleFont)
              ? current.fontName
              : fontName as String?,
          bold: bold,
          colorPreset: colorPreset,
          borderSize: borderSize,
          backgroundOpacity: backgroundOpacity,
        ),
      ),
    );
  }

  void adjustBorder(double delta) {
    unawaited(
      session.updateSubtitleStyle(
        (current) => current.copyWith(
          borderSize: (current.borderSize + delta).clamp(0, 6).toDouble(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) {
      final style = session.subtitleStyle;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 15,
        children: [
          _SettingsSection(
            title: '字幕样式',
            palette: palette,
            children: [
              _SettingsRow(
                title: '字体',
                icon: Icons.text_format_rounded,
                palette: palette,
                control: FutureBuilder<List<String>>(
                  future: fontFamilies,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    if (snapshot.hasError) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: [
                          Text(
                            '字体列表不可用',
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.secondary,
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey('subtitle-font-retry'),
                            onPressed: onRetryFonts,
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: const Text('重试'),
                          ),
                        ],
                      );
                    }
                    return _FontMenu(
                      value: style.fontName,
                      families: snapshot.data ?? const [],
                      palette: palette,
                      onSelected: (font) => update(fontName: font),
                    );
                  },
                ),
              ),
              _SettingsRow(
                title: '粗体',
                icon: Icons.format_bold_rounded,
                palette: palette,
                control: _SettingToggle(
                  key: const ValueKey('subtitle-bold-toggle'),
                  value: style.bold,
                  palette: palette,
                  onChanged: (value) => update(bold: value),
                ),
              ),
              _SettingsRow(
                title: '颜色',
                icon: Icons.palette_outlined,
                palette: palette,
                control: _ChoiceGroup<VideoSubtitleColorPreset>(
                  values: VideoSubtitleColorPreset.values,
                  selected: style.colorPreset,
                  label: (value) => value.displayName,
                  keyFor: (value) => ValueKey('subtitle-color-${value.name}'),
                  palette: palette,
                  onSelected: (value) => update(colorPreset: value),
                ),
              ),
              _SettingsRow(
                title: '描边',
                icon: Icons.border_color_outlined,
                palette: palette,
                control: _AdjustmentControls(
                  value: style.borderSize.toStringAsFixed(1),
                  valueKey: const ValueKey('subtitle-border-value'),
                  palette: palette,
                  onDecrease: () => adjustBorder(-.5),
                  onReset: () => update(borderSize: 3),
                  onIncrease: () => adjustBorder(.5),
                  keyPrefix: 'subtitle-border',
                ),
              ),
              _SettingsRow(
                title: '背景底',
                icon: Icons.branding_watermark_outlined,
                palette: palette,
                control: _ChoiceGroup<double>(
                  values: const [0, .25, .45, .7],
                  selected: style.backgroundOpacity,
                  label: (value) => switch (value) {
                    0 => '关闭',
                    .25 => '淡',
                    .45 => '中',
                    _ => '深',
                  },
                  keyFor: (value) =>
                      ValueKey('subtitle-background-${(value * 100).round()}'),
                  palette: palette,
                  onSelected: (value) => update(backgroundOpacity: value),
                ),
              ),
              if (showControlError && session.controlError != null)
                PlayerInlineNotice(
                  message: session.controlError!,
                  palette: palette,
                ),
            ],
          ),
          Text(
            '改动立刻能在画面上看到，并作为以后视频的默认字幕样式。字幕大小与位置在「音画同步」标签页调整。',
            style: TextStyle(fontSize: 11, color: palette.subdued),
          ),
        ],
      );
    },
  );
}

String _delayText(double value) => value.abs() < .001
    ? '0.0 秒'
    : '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)} 秒';

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.palette,
    required this.children,
  });

  final String title;
  final PlayerPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: palette.subdued,
        ),
      ),
      ...children,
    ],
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.icon,
    required this.palette,
    required this.control,
  });

  final String title;
  final IconData icon;
  final PlayerPalette palette;
  final Widget control;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 32),
    child: Row(
      spacing: 10,
      children: [
        SizedBox(
          width: 112,
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
          child: Align(alignment: Alignment.centerRight, child: control),
        ),
      ],
    ),
  );
}

class _AdjustmentControls extends StatelessWidget {
  const _AdjustmentControls({
    required this.value,
    required this.valueKey,
    required this.palette,
    required this.onDecrease,
    required this.onReset,
    required this.onIncrease,
    required this.keyPrefix,
  });

  final String value;
  final Key valueKey;
  final PlayerPalette palette;
  final VoidCallback onDecrease;
  final VoidCallback onReset;
  final VoidCallback onIncrease;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      _SmallButton(
        key: ValueKey('$keyPrefix-decrease'),
        tooltip: '减少',
        icon: Icons.remove_rounded,
        palette: palette,
        onPressed: onDecrease,
      ),
      Container(
        key: valueKey,
        width: 72,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.choiceFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.rowStroke, width: .8),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: palette.primary,
          ),
        ),
      ),
      _SmallButton(
        key: ValueKey('$keyPrefix-reset'),
        tooltip: '恢复默认',
        icon: Icons.refresh_rounded,
        palette: palette,
        onPressed: onReset,
      ),
      _SmallButton(
        key: ValueKey('$keyPrefix-increase'),
        tooltip: '增加',
        icon: Icons.add_rounded,
        palette: palette,
        onPressed: onIncrease,
      ),
    ],
  );
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
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
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 26,
    child: PlayerControlSurface(
      palette: palette,
      enabled: true,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 14, color: palette.primary),
      ),
    ),
  );
}

class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.values,
    required this.selected,
    required this.label,
    required this.keyFor,
    required this.palette,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final Key Function(T) keyFor;
  final PlayerPalette palette;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 5,
    children: [
      for (final value in values)
        Semantics(
          selected: selected == value,
          button: true,
          child: InkWell(
            key: keyFor(value),
            onTap: () => onSelected(value),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 24,
              constraints: const BoxConstraints(minWidth: 42),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected == value
                    ? palette.selectedFill
                    : palette.choiceFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected == value
                      ? palette.selectedStroke
                      : palette.rowStroke,
                  width: .8,
                ),
              ),
              child: Text(
                label(value),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.value,
    required this.palette,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final PlayerPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    button: true,
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
  );
}

class _FontMenu extends StatelessWidget {
  const _FontMenu({
    required this.value,
    required this.families,
    required this.palette,
    required this.onSelected,
  });

  final String? value;
  final List<String> families;
  final PlayerPalette palette;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: const ValueKey('subtitle-font-menu'),
    tooltip: '选择字幕字体',
    onSelected: (selected) =>
        onSelected(selected == '__default_subtitle_font__' ? null : selected),
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: '__default_subtitle_font__',
        child: Text('默认'),
      ),
      if (families.isNotEmpty) const PopupMenuDivider(),
      for (final family in families)
        PopupMenuItem(value: family, child: Text(family)),
    ],
    child: Container(
      height: 24,
      constraints: const BoxConstraints(minWidth: 72, maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.choiceFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.rowStroke, width: .8),
      ),
      child: Text(
        value ?? '默认',
        key: const ValueKey('subtitle-font-value'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: palette.primary,
        ),
      ),
    ),
  );
}
