import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/settings_surfaces.dart';
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
        showAppToast(context, '已恢复健康检查。', kind: AppFeedbackKind.success);
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
    return AppSettingsSection(
      title: '数据、存储与诊断',
      subtitle: '管理备份、存储位置、清理和性能记录。',
      icon: Icons.storage_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSettingsRow(
            title: '已忽略健康项',
            subtitle: '恢复后重新参与健康统计和展示',
            icon: Icons.visibility_off_outlined,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ignored.when(
                    data: (items) => '${items.length} 项',
                    error: (_, _) => '读取失败',
                    loading: () => '读取中…',
                  ),
                ),
                const SizedBox(width: 12),
                SourceSheetButton(
                  label: '恢复显示',
                  prominent: ignored.asData?.value.isNotEmpty == true,
                  onPressed: _busy || ignored.asData?.value.isNotEmpty != true
                      ? null
                      : _restore,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const AppSettingsDescription(
            text: '在仪表盘中点「忽略」的健康检查会永久隐藏；恢复后会重新参与统计和展示。',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppSettingsNotice(message: _error!, error: true),
            ),
        ],
      ),
    );
  }
}
