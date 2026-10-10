import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/playback_session.dart';
import 'player_basic_settings.dart';
import 'player_visuals.dart';

/// PlayerAdvancedSettingsOverlay's frame and basic playback settings.
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
  pageBuilder: (context, _, _) {
    final screen = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: (screen.width - 92)
                  .clamp(680, 900)
                  .clamp(0, screen.width)
                  .toDouble(),
              height: (screen.height - 92)
                  .clamp(500, 660)
                  .clamp(0, screen.height)
                  .toDouble(),
              decoration: BoxDecoration(
                color: palette.opaqueBase,
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: palette.popoverFill,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border.all(color: palette.border.first, width: .9),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      spacing: 12,
                      children: [
                        PlayerSymbolIcon(
                          PlayerSymbol.settings,
                          color: palette.primary,
                        ),
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
                          child: IconButton(
                            tooltip: '关闭设置',
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close,
                              size: 12,
                              color: palette.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: palette.rowStroke),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Container(
                              height: 32,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                              ),
                              decoration: BoxDecoration(
                                color: palette.selectedFill,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '播放',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: palette.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        VerticalDivider(width: 1, color: palette.rowStroke),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(18),
                            child: PlayerBasicSettings(
                              session: session,
                              palette: palette,
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
    );
  },
);
