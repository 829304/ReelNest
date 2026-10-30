import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/automatic_scan_interval.dart';
import '../../../ui/widgets/app_menu_control.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../../sources/application/automatic_scan_providers.dart';

/// SettingsView.scanSettings, scoped to the automatic scan preference.
class AutomaticScanSettingsPanel extends ConsumerStatefulWidget {
  const AutomaticScanSettingsPanel({super.key});

  @override
  ConsumerState<AutomaticScanSettingsPanel> createState() =>
      _AutomaticScanSettingsPanelState();
}

class _AutomaticScanSettingsPanelState
    extends ConsumerState<AutomaticScanSettingsPanel> {
  bool _busy = false;
  String? _error;

  Future<void> _change(AutomaticScanInterval value) async {
    if (_busy || value == ref.read(automaticScanIntervalProvider)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(automaticScanIntervalProvider.notifier).setInterval(value);
    } catch (_) {
      if (mounted) setState(() => _error = '自动扫描设置保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final interval = ref.watch(automaticScanIntervalProvider);
    return AppSettingsSection(
      title: '媒体库更新',
      subtitle: '设置扫描频率、后台进度和完成提醒。',
      icon: Icons.sync_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSettingsRow(
            title: '自动扫描',
            icon: Icons.update_rounded,
            trailing: AppMenuControl<AutomaticScanInterval>(
              key: const ValueKey('automatic-scan-interval'),
              value: interval,
              label: interval.displayName,
              values: AutomaticScanInterval.values,
              itemLabel: (value) => value.displayName,
              enabled: !_busy,
              busy: _busy,
              tooltip: '自动扫描',
              onSelected: _change,
            ),
          ),
          const SizedBox(height: 12),
          const AppSettingsDescription(
            text: '本机文件夹有变动会很快更新；移动硬盘和网络位置按固定间隔检查。暂时连不上的来源会先跳过，之后自动再试。',
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            AppSettingsNotice(message: _error!, error: true),
          ],
        ],
      ),
    );
  }
}
