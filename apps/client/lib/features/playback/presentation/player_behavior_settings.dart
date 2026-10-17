import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/playback_session.dart';
import 'player_basic_settings.dart';
import 'player_subtitle_sync_settings.dart';
import 'player_video_display_settings.dart';
import 'player_visuals.dart';

enum PlayerAdvancedSettingsTab { playback, sync, video, subtitles }

extension on PlayerAdvancedSettingsTab {
  String get title => switch (this) {
    PlayerAdvancedSettingsTab.playback => '播放',
    PlayerAdvancedSettingsTab.sync => '音画同步',
    PlayerAdvancedSettingsTab.video => '画面',
    PlayerAdvancedSettingsTab.subtitles => '字幕',
  };

  IconData get icon => switch (this) {
    PlayerAdvancedSettingsTab.playback => Icons.play_circle_outline_rounded,
    PlayerAdvancedSettingsTab.sync => Icons.graphic_eq_rounded,
    PlayerAdvancedSettingsTab.video => Icons.aspect_ratio_rounded,
    PlayerAdvancedSettingsTab.subtitles => Icons.closed_caption_outlined,
  };
}

/// PlayerAdvancedSettingsOverlay's frame and currently migrated settings tabs.
Future<void> showPlayerBehaviorSettings(
  BuildContext context,
  PlaybackSession session,
  PlayerPalette palette,
) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '关闭播放器更多设置',
  barrierColor: Colors.black.withValues(alpha: .26),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => Theme(
    data: playerOverlayThemeData(Theme.of(context)),
    child: _PlayerBehaviorSettingsDialog(session: session, palette: palette),
  ),
);

class _PlayerBehaviorSettingsDialog extends StatefulWidget {
  const _PlayerBehaviorSettingsDialog({
    required this.session,
    required this.palette,
  });

  final PlaybackSession session;
  final PlayerPalette palette;

  @override
  State<_PlayerBehaviorSettingsDialog> createState() =>
      _PlayerBehaviorSettingsDialogState();
}

class _PlayerBehaviorSettingsDialogState
    extends State<_PlayerBehaviorSettingsDialog> {
  PlayerAdvancedSettingsTab selected = PlayerAdvancedSettingsTab.playback;
  Future<List<String>>? fontFamilies;

  PlaybackSession get session => widget.session;
  PlayerPalette get palette => widget.palette;

  void select(PlayerAdvancedSettingsTab tab) {
    if (selected == tab) return;
    setState(() {
      selected = tab;
      if (tab == PlayerAdvancedSettingsTab.subtitles) {
        fontFamilies ??= session.subtitleFontFamilies;
      }
    });
  }

  void retryFonts() => setState(() {
    fontFamilies = session.subtitleFontFamilies;
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: PlayerPanelEntrance(
            child: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                width: (screen.width - 92)
                    .clamp(680, 900)
                    .clamp(0, screen.width)
                    .toDouble(),
                height: (screen.height - 92)
                    .clamp(500, 660)
                    .clamp(0, screen.height)
                    .toDouble(),
                child: PlayerPanelSurface(
                  palette: palette,
                  shadowRadius: 22,
                  shadowOffset: const Offset(0, 10),
                  child: Column(
                    children: [
                      _header(context),
                      Divider(height: 1, color: palette.rowStroke),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sidebar(),
                            VerticalDivider(width: 1, color: palette.rowStroke),
                            Expanded(
                              child: SingleChildScrollView(
                                key: ValueKey(
                                  'player-settings-content-${selected.name}',
                                ),
                                padding: const EdgeInsets.all(18),
                                child: switch (selected) {
                                  PlayerAdvancedSettingsTab.playback =>
                                    PlayerBasicSettings(
                                      session: session,
                                      palette: palette,
                                    ),
                                  PlayerAdvancedSettingsTab.sync =>
                                    PlayerSyncSettings(
                                      session: session,
                                      palette: palette,
                                    ),
                                  PlayerAdvancedSettingsTab.video =>
                                    PlayerVideoDisplaySettings(
                                      session: session,
                                      palette: palette,
                                    ),
                                  PlayerAdvancedSettingsTab.subtitles =>
                                    PlayerSubtitleStyleSettings(
                                      session: session,
                                      palette: palette,
                                      fontFamilies: fontFamilies ??=
                                          session.subtitleFontFamilies,
                                      onRetryFonts: retryFonts,
                                    ),
                                },
                              ),
                            ),
                          ],
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
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Row(
      spacing: 12,
      children: [
        PlayerSymbolIcon(PlayerSymbol.settings, color: palette.primary),
        Expanded(
          child: Text(
            '播放器更多设置',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: palette.primary,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          height: 30,
          child: PlayerControlSurface(
            palette: palette,
            enabled: true,
            child: IconButton(
              tooltip: '关闭设置',
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close, size: 13, color: palette.secondary),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _sidebar() => SizedBox(
    width: 150,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        spacing: 7,
        children: [
          for (final tab in PlayerAdvancedSettingsTab.values)
            Semantics(
              button: true,
              selected: selected == tab,
              child: InkWell(
                key: ValueKey('player-settings-tab-${tab.name}'),
                onTap: () => select(tab),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: selected == tab
                        ? palette.selectedFill
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      Icon(
                        tab.icon,
                        size: 14,
                        color: selected == tab
                            ? palette.primary
                            : palette.secondary,
                      ),
                      Text(
                        tab.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected == tab
                              ? palette.primary
                              : palette.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
