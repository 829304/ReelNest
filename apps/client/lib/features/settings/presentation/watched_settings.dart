import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../playback/data/player_preferences_repository.dart';
import '../../sources/application/source_providers.dart';

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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _preferences.rememberWatchedThreshold(value);
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
    return AppSheetSection(
      title: '视频播放与缓存',
      subtitle: '设置视频启动方式、观看规则和离线缓存。',
      icon: const Icon(Icons.ondemand_video, size: 17),
      colors: palette.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 16),
              const SizedBox(width: 10),
              const Expanded(child: Text('已看判定')),
              if (_threshold == null && _busy) const Text('读取中…'),
              if (_threshold != null)
                PopupMenuButton<double>(
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text('${(_threshold! * 100).round()}% ▾'),
                  ),
                ),
            ],
          ),
          if (_error != null)
            Row(
              children: [
                Expanded(child: Text(_error!)),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('重新读取'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
