import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/emby/emby_quality.dart';
import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/emby_providers.dart';
import '../domain/emby_offline_subscription.dart';

class EmbyOfflineMenu extends ConsumerWidget {
  const EmbyOfflineMenu({required this.item, this.compact = false, super.key});
  final IndexedMedia item;
  final bool compact;
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is SourceFailure ? error.message : '自动缓存设置失败，请重试。',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = item.isSeries
        ? item.identity
        : item.parentId == null
        ? null
        : (sourceId: item.identity.sourceId, localId: item.parentId!);
    if (series == null) return const SizedBox.shrink();
    final candidates =
        ref.watch(embyCacheCandidatesProvider(series)).asData?.value ?? [];
    if (candidates.isEmpty) return const SizedBox.shrink();
    final repository = ref.watch(embyOfflineProvider);
    final qualities = EmbyVideoQuality.options(candidates.first);
    return ValueListenableBuilder(
      valueListenable: repository.state,
      builder: (context, state, _) {
        final rule = state.rules.where((r) => r.series == series).firstOrNull;
        Widget action(
          String title,
          Future<void> Function() work, {
          bool selected = false,
        }) => MenuItemButton(
          leadingIcon: selected ? const Icon(Icons.check, size: 16) : null,
          onPressed: () => unawaited(_run(context, work)),
          child: Text(title),
        );
        List<Widget> presets(String? quality) {
          final result = <Widget>[];
          for (final mode in OfflineMode.values) {
            for (final count
                in mode == OfflineMode.nextUnwatched ? [3, 5, 10] : [1]) {
              final title = switch (mode) {
                OfflineMode.nextEpisode => '自动缓存下一集',
                OfflineMode.nextUnwatched => '自动缓存未看 $count 集',
                OfflineMode.season => '自动缓存整季',
                OfflineMode.fullSeries => '自动缓存全系列',
              };
              result.add(
                action(
                  title,
                  () async {
                    await repository.save(
                      item,
                      mode,
                      episodeLimit: count,
                      qualityId: quality,
                    );
                  },
                  selected:
                      rule?.mode == mode &&
                      (mode != OfflineMode.nextUnwatched ||
                          rule?.episodeLimit == count) &&
                      rule?.qualityId ==
                          (quality == 'original' ? null : quality),
                ),
              );
            }
          }
          result.add(const Divider());
          result.add(
            action('自定义未看集数…', () async {
              final title =
                  rule?.title ?? (await repository.sources.media(series)).title;
              if (!context.mounted) return;
              final count = await showDialog<int>(
                context: context,
                builder: (_) => OfflineLimitSheet(
                  title: title,
                  initial: rule?.mode == OfflineMode.nextUnwatched
                      ? rule!.episodeLimit
                      : 3,
                ),
              );
              if (count != null) {
                await repository.save(
                  item,
                  OfflineMode.nextUnwatched,
                  episodeLimit: count,
                  qualityId: quality,
                );
              }
            }),
          );
          return result;
        }

        return MenuAnchor(
          menuChildren: [
            ...presets(null),
            if (qualities.length > 1) ...[
              const Divider(),
              SubmenuButton(
                menuChildren: [
                  for (final q in qualities)
                    SubmenuButton(
                      menuChildren: presets(q.id),
                      child: Text('${q.label} · ${q.detail}'),
                    ),
                ],
                child: const Text('指定缓存清晰度'),
              ),
            ],
            if (rule != null) ...[
              const Divider(),
              action(
                rule.paused(DateTime.now()) ? '继续自动缓存' : '暂停 7 天',
                () => repository.update(
                  series,
                  pause: !rule.paused(DateTime.now()),
                ),
              ),
              SubmenuButton(
                menuChildren: [
                  for (final policy in OfflineNetwork.values)
                    action(
                      policy.label,
                      () => repository.update(series, network: policy),
                      selected: rule.network == policy,
                    ),
                ],
                child: Text('网络策略：${rule.network.label}'),
              ),
              SubmenuButton(
                menuChildren: [
                  action(
                    '不自动到期',
                    () => repository.update(series, clearExpiration: true),
                    selected: rule.expiresAt == null,
                  ),
                  for (final days in [7, 30, 90])
                    action(
                      '$days 天后到期',
                      () => repository.update(series, expirationDays: days),
                    ),
                ],
                child: Text(
                  rule.expiresAt == null
                      ? '到期计划：不自动到期'
                      : '到期计划：${rule.expired(DateTime.now()) ? '已到期' : '${rule.expiresAt!.difference(DateTime.now()).inDays + 1} 天后'}',
                ),
              ),
              const Divider(),
              action('停止自动缓存', () => repository.stop(series)),
            ],
          ],
          builder: (context, controller, _) => TextButton(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.downloading_outlined, size: 16),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    rule == null ? '自动缓存系列' : '自动缓存：${rule.compact}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// VideoOfflineSubscriptionLimitSheet: 500 wide, 18 spacing, 1...99 stepper.
class OfflineLimitSheet extends StatefulWidget {
  const OfflineLimitSheet({required this.title, this.initial = 3, super.key});
  final String title;
  final int initial;
  @override
  State<OfflineLimitSheet> createState() => _OfflineLimitSheetState();
}

class _OfflineLimitSheetState extends State<OfflineLimitSheet> {
  late final TextEditingController _count;
  int? get value => int.tryParse(_count.text);
  bool get valid => value != null && value! >= 1 && value! <= 99;
  @override
  void initState() {
    super.initState();
    _count = TextEditingController(text: '${widget.initial.clamp(1, 99)}');
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  void _step(int by) =>
      setState(() => _count.text = '${((value ?? 3) + by).clamp(1, 99)}');
  void _save() {
    if (valid) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.enter): _save,
      },
      child: Dialog(
        backgroundColor: p.page,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: SizedBox(
          width: 500,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSheetHeader(
                  title: '自定义自动缓存',
                  subtitle: '为${widget.title}设置未看剧集的离线窗口。',
                  icon: Icon(
                    Icons.downloading_outlined,
                    size: 42,
                    color: p.accent,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: Text('保持集数')),
                      SizedBox(
                        width: 168,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '减少集数',
                              onPressed: value == 1 ? null : () => _step(-1),
                              icon: const Icon(Icons.remove, size: 16),
                            ),
                            SizedBox(
                              width: 72,
                              child: TextField(
                                controller: _count,
                                autofocus: true,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _save(),
                                decoration: const InputDecoration(
                                  suffixText: '集',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '增加集数',
                              onPressed: value == 99 ? null : () => _step(1),
                              icon: const Icon(Icons.add, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                AppInfoNote(
                  text:
                      'ReelNest 会把未观看队列前 ${value ?? 3} 集保持为离线缓存；已缓存或正在缓存的剧集不会重复加入任务。',
                  icon: const Icon(Icons.info_outline, size: 16),
                  surface: p.card,
                  border: p.border,
                  iconTint: p.accent,
                  textColor: p.secondary,
                ),
                if (!valid)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('请输入 1–99 集。'),
                  ),
                const SizedBox(height: 18),
                AppSheetActionFooter(
                  panelBorder: p.panelBorder,
                  solarLightTint: p.solar,
                  actions: [
                    SourceSheetButton(
                      label: '取消',
                      outlined: true,
                      onPressed: () => Navigator.pop(context),
                    ),
                    SourceSheetButton(
                      label: '保存',
                      prominent: true,
                      onPressed: valid ? _save : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
