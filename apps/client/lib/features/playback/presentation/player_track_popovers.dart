import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';

import '../application/playback_session.dart';
import 'player_behavior_settings.dart';
import 'player_basic_settings.dart';
import 'player_visuals.dart';

enum PlayerPanel { subtitles, audio, volume, episodes, settings }

Future<void> showPlayerPanel(
  BuildContext context, {
  required Rect anchor,
  required PlayerPanel panel,
  required PlaybackSession session,
  required PlayerPalette palette,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '关闭播放器面板',
  barrierColor: Colors.transparent,
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) {
    final screen = MediaQuery.sizeOf(context);
    final width = (switch (panel) {
      PlayerPanel.subtitles => 360.0,
      PlayerPanel.audio => 300.0,
      PlayerPanel.volume => 338.0,
      PlayerPanel.episodes => 320.0,
      PlayerPanel.settings => 420.0,
    }).clamp(0, screen.width - 16).toDouble();
    final bottom = (screen.height - anchor.top + 6)
        .clamp(8, screen.height - 80)
        .toDouble();
    final maxHeight = (screen.height - bottom - 8)
        .clamp(
          72,
          panel == PlayerPanel.subtitles
              ? 540
              : panel == PlayerPanel.settings
              ? 520
              : 420,
        )
        .toDouble();
    return Stack(
      children: [
        Positioned(
          left: (anchor.center.dx - width / 2)
              .clamp(8, screen.width - width - 8)
              .toDouble(),
          bottom: bottom,
          width: width,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.pop(context),
            },
            child: Focus(
              autofocus: true,
              child: PlayerTrackPopover(
                panel: panel,
                session: session,
                palette: palette,
                maxHeight: maxHeight,
              ),
            ),
          ),
        ),
      ],
    );
  },
);

/// Dimensions, spacing, headings and rows translated from the three original
/// PlayerView popovers. Online subtitle search has its own later service port.
class PlayerTrackPopover extends StatefulWidget {
  const PlayerTrackPopover({
    required this.panel,
    required this.session,
    required this.palette,
    this.maxHeight = 540,
    super.key,
  });
  final PlayerPanel panel;
  final PlaybackSession session;
  final PlayerPalette palette;
  final double maxHeight;
  @override
  State<PlayerTrackPopover> createState() => _PlayerTrackPopoverState();
}

class _PlayerTrackPopoverState extends State<PlayerTrackPopover> {
  double? _draftVolume;
  PlaybackSession get session => widget.session;
  PlayerPalette get palette => widget.palette;
  @override
  void initState() {
    super.initState();
    _refreshServerSubtitles();
  }

  @override
  void didUpdateWidget(PlayerTrackPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel != widget.panel ||
        oldWidget.session != widget.session) {
      _refreshServerSubtitles();
    }
  }

  void _refreshServerSubtitles() {
    if (widget.panel == PlayerPanel.subtitles && session.item?.remote != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) session.refreshServerSubtitles();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([session, session.tracks, session.volumeLevel]),
    builder: (context, _) => Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        decoration: BoxDecoration(
          color: palette.opaqueBase,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: palette.lightContent ? .08 : .10,
              ),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: palette.popoverFill,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border.all(color: palette.border.first, width: .9),
          ),
          child: SingleChildScrollView(
            padding: widget.panel == PlayerPanel.volume
                ? const EdgeInsets.symmetric(horizontal: 13, vertical: 11)
                : const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: widget.panel == PlayerPanel.volume ? 9 : 10,
              children: [
                ...switch (widget.panel) {
                  PlayerPanel.audio => _audio(),
                  PlayerPanel.subtitles => _subtitles(),
                  PlayerPanel.volume => _volume(),
                  PlayerPanel.episodes => _episodes(),
                  PlayerPanel.settings => _settings(),
                },
                if (session.controlError != null)
                  Text(
                    session.controlError!,
                    style: TextStyle(fontSize: 11, color: palette.secondary),
                  ),
                if (session.transitionMessage != null ||
                    session.saveError != null)
                  Text(
                    session.saveError ?? session.transitionMessage!,
                    style: TextStyle(fontSize: 11, color: palette.secondary),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  List<Widget> _episodes() => [
    _header(
      '剧集列表',
      '选择同系列中的其他剧集',
      PlayerSymbol.episodes,
      '${session.queue.items.length} 集',
    ),
    SizedBox(
      height: (session.queue.items.length * 52.0).clamp(
        0,
        (widget.maxHeight - 96).clamp(0, 380),
      ),
      child: ListView.separated(
        key: ValueKey(session.item?.identity),
        itemCount: session.queue.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (_, index) {
          final episode = session.queue.items[index];
          return _row(
            'episode-${episode.identity.sourceId}-${episode.identity.localId}',
            episode.title,
            _episodeSubtitle(episode),
            episode.identity == session.item?.identity,
            () => session.open(episode.identity),
          );
        },
      ),
    ),
  ];

  String? _episodeSubtitle(IndexedMedia episode) {
    final parts = <String>[];
    if (episode.episodeNumber != null) {
      parts.add(
        episode.seasonNumber != null
            ? episode.episodeLabel
            : '第 ${episode.episodeNumber} 集',
      );
    }
    final record = session.queueRecords[episode.identity];
    if (record != null && record.duration > Duration.zero) {
      parts.add('${(record.duration.inSeconds / 60).round()} 分钟');
    }
    if (episode.identity == session.item?.identity) {
      parts.add('正在播放');
    } else if (record?.watched == true) {
      parts.add('已看');
    } else if (record != null && record.progress > .02) {
      parts.add('看到 ${(record.progress * 100).round()}%');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  List<Widget> _settings() => [
    _header('播放器设置', '常用播放与时间轴选项', PlayerSymbol.settings, ''),
    Text(
      '播放',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: palette.subdued,
      ),
    ),
    Row(
      spacing: 10,
      children: [
        Text('倍速', style: TextStyle(fontSize: 12, color: palette.secondary)),
        Expanded(
          child: PlayerSpeedControl(session: session, palette: palette),
        ),
      ],
    ),
    Text(
      '完整设置',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: palette.subdued,
      ),
    ),
    InkWell(
      onTap: () {
        final navigatorContext = Navigator.of(context).context;
        Navigator.pop(context);
        unawaited(
          showPlayerBehaviorSettings(navigatorContext, session, palette),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.choiceFill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '打开内置播放器设置',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: palette.primary,
          ),
        ),
      ),
    ),
  ];
  Widget _header(
    String title,
    String subtitle,
    PlayerSymbol symbol,
    String value,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      spacing: 10,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.selectedFill,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: palette.selectedStroke, width: .8),
          ),
          child: PlayerSymbolIcon(symbol, size: 13, color: palette.primary),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.primary,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: palette.subdued),
              ),
            ],
          ),
        ),
        if (value.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Container(
              height: 24,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: palette.choiceFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.rowStroke, width: .7),
              ),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: palette.secondary,
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Widget _row(
    String key,
    String title,
    String? subtitle,
    bool selected,
    Future<void> Function() action,
  ) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      key: ValueKey(key),
      borderRadius: BorderRadius.circular(9),
      onTap: () => unawaited(action()),
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? palette.selectedFill : palette.rowFill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? palette.selectedStroke : palette.rowStroke,
            width: .7,
          ),
        ),
        child: Row(
          spacing: 9,
          children: [
            SizedBox(
              width: 18,
              child: PlayerSymbolIcon(
                selected ? PlayerSymbol.check : PlayerSymbol.circle,
                size: 14,
                color: selected ? palette.primary : palette.subdued,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                    ),
                  ),
                  if (subtitle?.isNotEmpty == true)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: palette.secondary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _divider() => Container(height: .7, color: palette.divider);
  Widget _section(String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 10,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _divider(),
      ),
      Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: palette.secondary,
        ),
      ),
    ],
  );
  List<Widget> _audio() {
    final state = session.tracks.value;
    final selected = state.audio
        .where((t) => t.id == state.audioId)
        .firstOrNull;
    return [
      _header(
        '音轨',
        '选择声音轨道与语言',
        PlayerSymbol.audio,
        selected?.displayName ?? '自动',
      ),
      _row(
        'audio-auto',
        '自动选择',
        '由播放器选择默认音轨',
        selected == null,
        () => session.selectAudio(null),
      ),
      if (state.audio.isEmpty)
        Text(
          '播放器暂未回传音轨列表。',
          style: TextStyle(fontSize: 12, color: palette.secondary),
        ),
      for (final track in state.audio)
        _row(
          'audio-${track.id}',
          track.displayName,
          'ID ${track.id}',
          track.id == state.audioId,
          () => session.selectAudio(track.id),
        ),
    ];
  }

  List<Widget> _subtitles() {
    final state = session.tracks.value;
    final selected = state.subtitles
        .where((t) => t.id == state.subtitleId)
        .firstOrNull;
    final embedded = state.subtitles.where((t) => !t.external).toList();
    final external = state.subtitles.where((t) => t.external).toList();
    final delay = state.subtitleDelay;
    return [
      _header(
        '字幕',
        '内嵌、同目录与在线字幕',
        PlayerSymbol.subtitle,
        selected?.displayName ?? '关闭',
      ),
      _row(
        'subtitle-off',
        '关闭字幕',
        null,
        selected == null,
        () => session.selectSubtitle(null),
      ),
      _row(
        'subtitle-auto',
        '自动加载目录字幕',
        '扫描同目录字幕文件',
        state.autoSubtitles,
        session.enableAutoSubtitles,
      ),
      _row(
        'subtitle-file',
        '从文件加载…',
        '选择任意位置的字幕文件（srt / ass / vtt 等）',
        false,
        _openSubtitle,
      ),
      _divider(),
      Row(
        children: [
          PlayerSymbolIcon(
            PlayerSymbol.timer,
            size: 12,
            color: palette.secondary,
          ),
          const SizedBox(width: 6),
          Text(
            '字幕快慢',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.secondary,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 186,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 6,
              children: [
                _adjust(
                  '减少',
                  PlayerSymbol.minus,
                  () => session.subtitleDelay(delay - .1),
                ),
                Container(
                  width: 76,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.choiceFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${delay.abs() < .001 ? '0.0' : '${delay > 0 ? '+' : ''}${delay.toStringAsFixed(1)}'} 秒',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.primary,
                    ),
                  ),
                ),
                _adjust(
                  '恢复默认',
                  PlayerSymbol.reset,
                  () => session.subtitleDelay(0),
                ),
                _adjust(
                  '增加',
                  PlayerSymbol.plus,
                  () => session.subtitleDelay(delay + .1),
                ),
              ],
            ),
          ),
        ],
      ),
      if (embedded.isNotEmpty) _section('内嵌字幕'),
      for (final track in embedded)
        _row(
          'subtitle-${track.id}',
          track.displayName,
          'ID ${track.id}',
          track.id == state.subtitleId,
          () => session.selectSubtitle(track.id),
        ),
      if (session.item?.remote != null) ...[
        _section('服务器字幕'),
        if (session.subtitleError != null) Text(session.subtitleError!),
        for (final stream in session.serverSubtitles)
          _row(
            'server-subtitle-${stream.key}',
            stream.displayName,
            stream.language,
            external.any(
              (t) =>
                  t.externalFilename != null &&
                  session.serverSubtitlePaths[stream.key] != null &&
                  p.equals(
                    t.externalFilename!,
                    session.serverSubtitlePaths[stream.key]!,
                  ) &&
                  t.id == state.subtitleId,
            ),
            () => session.selectServerSubtitle(stream.key),
          ),
        _row(
          'server-subtitle-refresh',
          '刷新服务器字幕',
          null,
          false,
          session.refreshServerSubtitles,
        ),
      ],
      if (session.sidecarSubtitles.isNotEmpty ||
          external.any(
            (t) => !session.serverSubtitlePaths.values.any(
              (path) =>
                  t.externalFilename != null &&
                  p.equals(path, t.externalFilename!),
            ),
          ))
        _section('同目录字幕'),
      for (final file in session.sidecarSubtitles)
        _row(
          'sidecar-${file.path}',
          file.displayName,
          file.languageHint,
          external.any(
            (t) =>
                t.externalFilename != null &&
                p.equals(t.externalFilename!, file.path) &&
                t.id == state.subtitleId,
          ),
          () => session.addSubtitle(file.path),
        ),
      for (final track in external.where(
        (t) =>
            !session.serverSubtitlePaths.values.any(
              (path) =>
                  t.externalFilename != null &&
                  p.equals(path, t.externalFilename!),
            ) &&
            !session.sidecarSubtitles.any(
              (s) =>
                  t.externalFilename != null &&
                  p.equals(s.path, t.externalFilename!),
            ),
      ))
        _row(
          'subtitle-${track.id}',
          track.displayName,
          '外挂字幕',
          track.id == state.subtitleId,
          () => session.selectSubtitle(track.id),
        ),
      if (state.subtitles.length > 1) ...[
        _section('第二字幕（双语对照）'),
        _row(
          'secondary-off',
          '关闭第二字幕',
          null,
          state.secondarySubtitleId == null,
          () => session.selectSecondarySubtitle(null),
        ),
        for (final track in state.subtitles.where(
          (t) => t.id != state.subtitleId,
        ))
          _row(
            'secondary-${track.id}',
            track.displayName,
            '显示在画面顶部',
            track.id == state.secondarySubtitleId,
            () => session.selectSecondarySubtitle(track.id),
          ),
      ],
    ];
  }

  Widget _adjust(
    String label,
    PlayerSymbol symbol,
    Future<void> Function() action,
  ) => Tooltip(
    message: label,
    child: InkWell(
      onTap: () => unawaited(action()),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.choiceFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: PlayerSymbolIcon(symbol, size: 10.5, color: palette.secondary),
      ),
    ),
  );
  Future<void> _openSubtitle() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '字幕文件',
            extensions: [
              'srt',
              'ass',
              'ssa',
              'sub',
              'vtt',
              'sup',
              'idx',
              'smi',
            ],
          ),
        ],
      );
      if (file != null && mounted) await session.addSubtitle(file.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法选择字幕文件，请重试。')));
      }
    }
  }

  List<Widget> _volume() {
    final state = session.tracks.value;
    final volume = session.volumeLevel.value;
    return [
      _header('音量与输出', '调整响度与播放设备', PlayerSymbol.speaker, '${volume.round()}%'),
      Row(
        spacing: 10,
        children: [
          SizedBox(
            width: 22,
            height: 24,
            child: PlayerSymbolIcon(
              volume == 0 ? PlayerSymbol.muted : PlayerSymbol.speaker,
              size: 15,
              color: palette.secondary,
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 26,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: palette.trackProgress,
                  inactiveTrackColor: palette.trackBase,
                  thumbColor: palette.primary,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  key: const ValueKey('video-volume'),
                  value: (_draftVolume ?? volume).clamp(0, 100),
                  min: 0,
                  max: 100,
                  onChangeStart: (v) => setState(() => _draftVolume = v),
                  onChanged: (v) {
                    setState(() => _draftVolume = v);
                    unawaited(session.volume(v, remember: false));
                  },
                  onChangeEnd: (v) {
                    setState(() => _draftVolume = null);
                    unawaited(session.volume(v));
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            width: 26,
            height: 26,
            child: PopupMenuButton<String>(
              tooltip: '输出设备',
              padding: EdgeInsets.zero,
              icon: PlayerSymbolIcon(
                PlayerSymbol.device,
                size: 13,
                color: palette.secondary,
              ),
              initialValue: state.audioDevice,
              onSelected: (name) => unawaited(session.audioDevice(name)),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'auto',
                  checked: state.audioDevice == 'auto',
                  child: const Text('系统默认'),
                ),
                for (final device in state.devices.where(
                  (d) => d.name != 'auto',
                ))
                  CheckedPopupMenuItem(
                    value: device.name,
                    checked: state.audioDevice == device.name,
                    child: Text(device.displayName),
                  ),
              ],
            ),
          ),
        ],
      ),
      Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '增强',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: palette.secondary,
              ),
            ),
          ),
          for (final boost in [1.0, 1.25, 1.5, 2.0])
            Expanded(
              child: InkWell(
                key: ValueKey('boost-$boost'),
                onTap: () => unawaited(session.volumeBoost(boost)),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (state.volumeBoost - boost).abs() < .01
                        ? palette.selectedFill
                        : palette.choiceFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    boost == 1 ? '关闭' : '${(boost * 100).round()}%',
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
      ),
    ];
  }
}
