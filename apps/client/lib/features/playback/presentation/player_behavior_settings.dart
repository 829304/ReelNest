import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/playback_session.dart';
import 'player_basic_settings.dart';
import 'player_shortcut_settings.dart';
import 'player_subtitle_sync_settings.dart';
import 'player_video_display_settings.dart';
import 'player_visuals.dart';

enum PlayerAdvancedSettingsTab { playback, sync, video, subtitles, shortcuts }

extension on PlayerAdvancedSettingsTab {
  String get title => switch (this) {
    PlayerAdvancedSettingsTab.playback => '播放',
    PlayerAdvancedSettingsTab.sync => '音画同步',
    PlayerAdvancedSettingsTab.video => '画面',
    PlayerAdvancedSettingsTab.subtitles => '字幕',
    PlayerAdvancedSettingsTab.shortcuts => '快捷键',
  };

  IconData get icon => switch (this) {
    PlayerAdvancedSettingsTab.playback => Icons.play_circle_outline_rounded,
    PlayerAdvancedSettingsTab.sync => Icons.graphic_eq_rounded,
    PlayerAdvancedSettingsTab.video => Icons.aspect_ratio_rounded,
    PlayerAdvancedSettingsTab.subtitles => Icons.closed_caption_outlined,
    PlayerAdvancedSettingsTab.shortcuts => Icons.keyboard_rounded,
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
  int shortcutEditorEpoch = 0;

  PlaybackSession get session => widget.session;
  PlayerPalette get palette => widget.palette;

  void select(PlayerAdvancedSettingsTab tab) {
    if (selected == tab) return;
    setState(() {
      if (selected == PlayerAdvancedSettingsTab.shortcuts) {
        // A later same-frame selection must still create a fresh recorder.
        // Otherwise a recorded key could survive a rapid/programmatic tab
        // round-trip even though the editor was left in between.
        shortcutEditorEpoch++;
      }
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
    final horizontalInset = screen.width < 760 ? 12.0 : 46.0;
    final verticalInset = screen.height < 560 ? 12.0 : 46.0;
    final dialogWidth = (screen.width - horizontalInset * 2)
        .clamp(0, 900)
        .toDouble();
    final dialogHeight = (screen.height - verticalInset * 2)
        .clamp(0, 660)
        .toDouble();
    final compact = dialogWidth < 720;
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
                key: const ValueKey('player-settings-dialog'),
                width: dialogWidth,
                height: dialogHeight,
                child: PlayerPanelSurface(
                  palette: palette,
                  shadowRadius: 22,
                  shadowOffset: const Offset(0, 10),
                  child: Column(
                    children: [
                      _header(context),
                      _controlNotice(),
                      Divider(height: 1, color: palette.rowStroke),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sidebar(compact ? 132 : 150),
                            VerticalDivider(width: 1, color: palette.rowStroke),
                            Expanded(
                              child:
                                  selected ==
                                      PlayerAdvancedSettingsTab.shortcuts
                                  ? PlayerShortcutSettings(
                                      key: ValueKey(
                                        'player-shortcut-settings-$shortcutEditorEpoch',
                                      ),
                                      session: session,
                                      palette: palette,
                                    )
                                  : Scrollbar(
                                      child: SingleChildScrollView(
                                        key: ValueKey(
                                          'player-settings-content-${selected.name}',
                                        ),
                                        padding: EdgeInsets.fromLTRB(
                                          compact ? 14 : 18,
                                          16,
                                          compact ? 14 : 18,
                                          18,
                                        ),
                                        child: switch (selected) {
                                          PlayerAdvancedSettingsTab.playback =>
                                            PlayerBasicSettings(
                                              session: session,
                                              palette: palette,
                                              showControlError: false,
                                            ),
                                          PlayerAdvancedSettingsTab.sync =>
                                            PlayerSyncSettings(
                                              session: session,
                                              palette: palette,
                                              showControlError: false,
                                            ),
                                          PlayerAdvancedSettingsTab.video =>
                                            PlayerVideoDisplaySettings(
                                              session: session,
                                              palette: palette,
                                              showControlError: false,
                                            ),
                                          PlayerAdvancedSettingsTab.subtitles =>
                                            PlayerSubtitleStyleSettings(
                                              session: session,
                                              palette: palette,
                                              fontFamilies: fontFamilies ??=
                                                  session.subtitleFontFamilies,
                                              onRetryFonts: retryFonts,
                                              showControlError: false,
                                            ),
                                          PlayerAdvancedSettingsTab.shortcuts =>
                                            const SizedBox.shrink(),
                                        },
                                      ),
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

  Widget _controlNotice() => AnimatedBuilder(
    animation: session,
    builder: (context, _) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 100),
      child: session.controlError == null
          ? const SizedBox.shrink(
              key: ValueKey('player-settings-control-error-empty'),
            )
          : Padding(
              key: const ValueKey('player-settings-control-error'),
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: PlayerInlineNotice(
                message: session.controlError!,
                palette: palette,
              ),
            ),
    ),
  );

  Widget _sidebar(double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        spacing: 7,
        children: [
          for (final tab in PlayerAdvancedSettingsTab.values)
            Semantics(
              button: true,
              selected: selected == tab,
              child: PlayerMenuRowSurface(
                key: ValueKey('player-settings-tab-${tab.name}'),
                palette: palette,
                onTap: () => select(tab),
                selected: selected == tab,
                fill: Colors.transparent,
                minHeight: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
        ],
      ),
    ),
  );
}
