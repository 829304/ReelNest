import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/widgets/page_content.dart';
import '../../health/presentation/ignored_health_settings.dart';
import '../application/appearance_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider);
    return PageContent(
      title: '设置',
      subtitle: '让映栖适合你的使用习惯。',
      children: [
        const IgnoredHealthSettings(),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('外观', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final option in const [
                      (mode: ThemeMode.system, label: '跟随系统'),
                      (mode: ThemeMode.light, label: '浅色'),
                      (mode: ThemeMode.dark, label: '深色'),
                    ])
                      ChoiceChip(
                        label: Text(option.label),
                        selected: mode == option.mode,
                        onSelected: (_) => ref
                            .read(appearanceProvider.notifier)
                            .setMode(option.mode),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
