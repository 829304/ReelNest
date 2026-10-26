import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../../playback/data/player_preferences_repository.dart';
import '../../sources/application/source_providers.dart';
import 'external_player_settings_panel.dart';
import 'video_cache_settings.dart';

/// SettingsView.videoSettings: watched threshold remains in general settings.
class WatchedSettings extends ConsumerStatefulWidget {
  const WatchedSettings({super.key});
  @override
  ConsumerState<WatchedSettings> createState() => _WatchedSettingsState();
}

class _WatchedSettingsState extends ConsumerState<WatchedSettings> {
  double? _threshold;
  bool _busy = false;
  String? _error;
  PlayerPreferencesRepository get _preferences =>
      PlayerPreferencesRepository(ref.read(sourceRepositoryProvider).database);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _preferences.watchedThreshold;
      if (mounted) setState(() => _threshold = value);
    } catch (_) {
      if (mounted) setState(() => _error = '播放设置读取失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(double value) async {
    if (_busy) return;
    final sources = ref.read(sourceRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _preferences.rememberWatchedThreshold(value);
      sources.traceChanged();
      if (mounted) setState(() => _threshold = value);
    } catch (_) {
      if (mounted) setState(() => _error = '已看判定保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return AppSettingsSection(
      title: '视频播放与缓存',
      subtitle: '设置视频启动方式、观看规则和离线缓存。',
      icon: Icons.ondemand_video_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ExternalPlayerSettingsPanel(),
          const AppSettingsDivider(),
          const AppSettingsSubsectionHeader(
            title: '观看规则',
            icon: Icons.tune_rounded,
          ),
          const SizedBox(height: 12),
          AppSettingsRow(
            title: '已看判定',
            subtitle: '播放达到设定比例后标记为已看',
            icon: Icons.verified_outlined,
            trailing: _threshold == null
                ? Text(
                    _busy ? '读取中…' : '--',
                    style: TextStyle(color: palette.secondary),
                  )
                : PopupMenuButton<double>(
                    enabled: !_busy,
                    initialValue: _threshold,
                    tooltip: '已看判定',
                    onSelected: _save,
                    itemBuilder: (_) => [
                      for (final value in const [.7, .8, .9, .95])
                        PopupMenuItem(
                          value: value,
                          child: Text('播放 ${(value * 100).round()}%'),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: palette.control,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(_threshold! * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.expand_more,
                            size: 15,
                            color: palette.secondary,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppSettingsNotice(
                message: _error!,
                error: true,
                actionLabel: '重新读取',
                onAction: _busy ? null : _load,
              ),
            ),
          const AppSettingsDivider(),
          const VideoCacheSettings(),
        ],
      ),
    );
  }
}
