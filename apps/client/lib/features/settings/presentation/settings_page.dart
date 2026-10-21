import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../../health/presentation/ignored_health_settings.dart';
import '../application/appearance_controller.dart';
import 'watched_settings.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider);
    return PageContent(
      title: '设置',
      subtitle: '调整播放、媒体库、界面与隐私设置。',
      header: const AppSettingsHeader(
        title: '设置',
        subtitle: '调整播放、媒体库、界面与隐私设置。',
        icon: Icons.settings_outlined,
      ),
      children: [
        const WatchedSettings(),
        const SizedBox(height: 28),
        const IgnoredHealthSettings(),
        const SizedBox(height: 28),
        AppSettingsSection(
          title: '外观',
          subtitle: '调整应用的明暗外观。',
          icon: Icons.palette_outlined,
          child: AppSettingsRow(
            title: '界面外观',
            subtitle: '跟随系统或固定使用浅色、深色主题',
            icon: Icons.brightness_6_outlined,
            trailing: _AppearanceSelector(
              value: mode,
              onChanged: (value) =>
                  ref.read(appearanceProvider.notifier).setMode(value),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppearanceSelector extends StatelessWidget {
  const _AppearanceSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: SegmentedButton<ThemeMode>(
        key: const ValueKey('settings-appearance-selector'),
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
          ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
          ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onChanged(selection.single),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          side: const WidgetStatePropertyAll(BorderSide.none),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? palette.activePillText
                : palette.idlePillText,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? palette.activePill
                : Colors.transparent,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
      ),
    );
  }
}
