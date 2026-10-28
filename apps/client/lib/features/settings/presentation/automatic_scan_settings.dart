import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/automatic_scan_interval.dart';
import '../../../ui/theme/source_sheet_palette.dart';
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
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
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
            trailing: PopupMenuButton<AutomaticScanInterval>(
              key: const ValueKey('automatic-scan-interval'),
              enabled: !_busy,
              initialValue: interval,
              tooltip: '自动扫描',
              onSelected: _change,
              itemBuilder: (_) => [
                for (final value in AutomaticScanInterval.values)
                  PopupMenuItem(value: value, child: Text(value.displayName)),
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
                    if (_busy) ...[
                      SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: palette.selectedTint,
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      interval.displayName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.expand_more, size: 15, color: palette.secondary),
                  ],
                ),
              ),
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
