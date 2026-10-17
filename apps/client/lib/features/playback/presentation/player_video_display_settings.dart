import 'dart:async';

import 'package:flutter/material.dart';

import '../application/playback_session.dart';
import '../domain/video_display_settings.dart';
import 'player_visuals.dart';

/// PlayerView.swift's "画面显示" settings group.
///
/// These controls only expose the original aspect, crop, deinterlace,
/// rotation and mirror options. Picture adjustment and performance settings
/// are intentionally outside the current migration scope.
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
}
