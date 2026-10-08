import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/health_providers.dart';

/// SettingsView.advancedSettings: ignored count and restore, no new preference.
class IgnoredHealthSettings extends ConsumerStatefulWidget {
  const IgnoredHealthSettings({super.key});
  @override
  ConsumerState<IgnoredHealthSettings> createState() =>
      _IgnoredHealthSettingsState();
}

class _IgnoredHealthSettingsState extends ConsumerState<IgnoredHealthSettings> {
  bool _busy = false;
  String? _error;
  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(healthRepositoryProvider).restore();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已恢复健康检查。')));
      }
    } catch (_) {
      if (mounted) setState(() => _error = '恢复健康检查失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ignored = ref.watch(ignoredHealthIssuesProvider);
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return AppSheetSection(
      title: '数据、存储与诊断',
      subtitle: '管理备份、存储位置、清理和性能记录。',
      icon: const SourceLineIcon(SourceGlyph.drive, size: 17),
      colors: palette.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SourceLineIcon(SourceGlyph.eyeOff, size: 16),
              const SizedBox(width: 10),
              const Expanded(child: Text('已忽略健康项')),
              Text(
                ignored.when(
                  data: (items) => '${items.length} 项',
                  error: (_, _) => '读取失败',
                  loading: () => '读取中…',
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 122,
                child: SourceSheetButton(
                  label: '恢复显示',
                  prominent: ignored.asData?.value.isNotEmpty == true,
                  onPressed: _busy || ignored.asData?.value.isNotEmpty != true
                      ? null
                      : _restore,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '在仪表盘中点「忽略」的健康检查会永久隐藏；恢复后会重新参与统计和展示。',
            style: TextStyle(fontSize: 11, color: palette.secondary),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
