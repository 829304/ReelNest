import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/automatic_scan_interval.dart';
import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_menu_control.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../application/tmdb_batch_providers.dart';
import '../application/tmdb_providers.dart';
import '../domain/tmdb_match_tolerance.dart';

class TmdbSettingsPanel extends ConsumerStatefulWidget {
  const TmdbSettingsPanel({super.key});

  @override
  ConsumerState<TmdbSettingsPanel> createState() => _TmdbSettingsPanelState();
}

class _TmdbSettingsPanelState extends ConsumerState<TmdbSettingsPanel> {
  final _credential = TextEditingController();
  final _language = TextEditingController();
  final _languageFocus = FocusNode();
  bool _showCredential = false;
  bool _savingCredential = false;
  bool _savingLanguage = false;
  bool _savingTolerance = false;
  bool _savingAutomaticInterval = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _credential.dispose();
    _language.dispose();
    _languageFocus.dispose();
    super.dispose();
  }

  Future<void> _saveCredential({required bool clear}) async {
    if (_savingCredential) return;
    final value = clear ? '' : _credential.text.trim();
    if (!clear && value.isEmpty) {
      setState(() {
        _notice = null;
        _error = '请输入新的 API Key 或 Read Access Token。';
      });
      return;
    }
    setState(() {
      _savingCredential = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(tmdbSettingsProvider.notifier).saveCredential(value);
      if (mounted) {
        _credential.clear();
        setState(() => _notice = clear ? 'TMDB 凭据已清除。' : 'TMDB 凭据已安全保存。');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is SourceFailure ? error.message : 'TMDB 凭据保存失败，请重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _savingCredential = false);
    }
  }

  Future<void> _saveLanguage() async {
    if (_savingLanguage) return;
    setState(() {
      _savingLanguage = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(tmdbSettingsProvider.notifier).setLanguage(_language.text);
      if (mounted) {
        final saved = ref.read(tmdbSettingsProvider).requireValue.language;
        _language.value = TextEditingValue(
          text: saved,
          selection: TextSelection.collapsed(offset: saved.length),
        );
        setState(() => _notice = 'TMDB 语言已保存。');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is SourceFailure ? error.message : 'TMDB 语言保存失败，请重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _savingLanguage = false);
    }
  }

  Future<void> _saveTolerance(TmdbMatchTolerance value) async {
    if (_savingTolerance ||
        value == ref.read(tmdbSettingsProvider).value?.matchTolerance) {
      return;
    }
    setState(() {
      _savingTolerance = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(tmdbSettingsProvider.notifier).setMatchTolerance(value);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is SourceFailure ? error.message : '影视匹配宽容度保存失败，请重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _savingTolerance = false);
    }
  }

  Future<void> _saveAutomaticInterval(AutomaticScanInterval value) async {
    if (_savingAutomaticInterval ||
        value == ref.read(tmdbSettingsProvider).value?.automaticMatchInterval) {
      return;
    }
    setState(() {
      _savingAutomaticInterval = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref
          .read(tmdbSettingsProvider.notifier)
          .setAutomaticMatchInterval(value);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is SourceFailure
              ? error.message
              : 'TMDB 自动拉取周期保存失败，请重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _savingAutomaticInterval = false);
    }
  }

  Future<void> _startBatchMatch() async {
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(tmdbBatchProvider.notifier).start();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is SourceFailure
              ? error.message
              : 'TMDB 剧集匹配无法启动，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(tmdbSettingsProvider);
    final batch = ref.watch(tmdbBatchProvider);
    return AppSettingsSection(
      title: '元数据与匹配',
      subtitle: '管理本地电影、电视剧与动漫的 TMDB 信息来源。',
      icon: Icons.auto_awesome_motion_outlined,
      child: settings.when(
        loading: () => const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => AppSettingsNotice(
          message: 'TMDB 设置读取失败，请重试。',
          error: true,
          actionLabel: '重新读取',
          onAction: () => ref.invalidate(tmdbSettingsProvider),
        ),
        data: (value) {
          if (!_languageFocus.hasFocus &&
              !_savingLanguage &&
              _language.text != value.language) {
            _language.value = TextEditingValue(
              text: value.language,
              selection: TextSelection.collapsed(offset: value.language.length),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSettingsSubsectionHeader(
                title: '影片信息',
                icon: Icons.movie_outlined,
              ),
              const SizedBox(height: 10),
              const AppSettingsDescription(
                text: '本地电影信息由 TMDB 提供；填写 API Key 或 Read Access Token 后即可手动搜索并匹配。凭据只保存在安全凭据存储中。',
              ),
              const SizedBox(height: 14),
              AppSettingsRow(
                title: 'TMDB API',
                subtitle: value.hasCredential
                    ? '已配置；输入新凭据可替换现有配置'
                    : '支持 API Key 或 Read Access Token',
                icon: Icons.key_rounded,
                trailing: _CredentialEditor(
                  controller: _credential,
                  configured: value.hasCredential,
                  obscure: !_showCredential,
                  busy: _savingCredential,
                  onToggleVisibility: () =>
                      setState(() => _showCredential = !_showCredential),
                  onSave: () => _saveCredential(clear: false),
                  onClear: value.hasCredential
                      ? () => _saveCredential(clear: true)
                      : null,
                ),
              ),
              const AppSettingsDivider(),
              AppSettingsRow(
                title: 'TMDB 语言',
                subtitle: '例如 zh-CN、en-US 或 ja-JP',
                icon: Icons.language_rounded,
                trailing: _LanguageEditor(
                  controller: _language,
                  focusNode: _languageFocus,
                  busy: _savingLanguage,
                  onSave: _saveLanguage,
                ),
              ),
              const AppSettingsDivider(),
              AppSettingsRow(
                title: '影视匹配宽容度',
                subtitle: _savingTolerance ? '正在保存…' : null,
                icon: Icons.center_focus_strong_rounded,
                trailing: AppMenuControl<TmdbMatchTolerance>(
                  key: const ValueKey('tmdb-match-tolerance'),
                  value: value.matchTolerance,
                  label: value.matchTolerance.displayName,
                  values: TmdbMatchTolerance.values,
                  itemLabel: (tolerance) => tolerance.displayName,
                  enabled: !_savingTolerance,
                  busy: _savingTolerance,
                  tooltip: '影视匹配宽容度',
                  onSelected: _saveTolerance,
                ),
              ),
              const SizedBox(height: 12),
              AppSettingsDescription(
                text:
                    '决定自动匹配需要多大把握：${value.matchTolerance.summary}。'
                    '越宽松越容易自动配上信息，但偶尔可能认错；拿不准就保持默认。',
              ),
              const AppSettingsDivider(),
              AppSettingsRow(
                title: '剧集一键匹配',
                subtitle: '补全尚未匹配的本地电视剧和动漫',
                icon: Icons.auto_fix_high_rounded,
                trailing: batch.running
                    ? OutlinedButton.icon(
                        key: const ValueKey('cancel-tmdb-batch'),
                        onPressed: () =>
                            ref.read(tmdbBatchProvider.notifier).cancel(),
                        icon: const Icon(Icons.stop_circle_outlined, size: 17),
                        label: const Text('取消'),
                      )
                    : FilledButton.icon(
                        key: const ValueKey('start-tmdb-batch'),
                        onPressed: value.hasCredential
                            ? _startBatchMatch
                            : null,
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                        label: const Text('立即匹配'),
                      ),
              ),
              const AppSettingsDivider(),
              AppSettingsRow(
                title: '自动拉取周期',
                subtitle: _savingAutomaticInterval ? '正在保存…' : '独立于媒体库文件自动扫描',
                icon: Icons.update_rounded,
                trailing: AppMenuControl<AutomaticScanInterval>(
                  key: const ValueKey('tmdb-automatic-match-interval'),
                  value: value.automaticMatchInterval,
                  label: value.automaticMatchInterval.displayName,
                  values: AutomaticScanInterval.values,
                  itemLabel: (interval) => interval.displayName,
                  enabled: !_savingAutomaticInterval,
                  busy: _savingAutomaticInterval,
                  tooltip: '自动拉取周期',
                  onSelected: _saveAutomaticInterval,
                ),
              ),
              const SizedBox(height: 12),
              const AppSettingsDescription(
                text: '立即匹配会补全尚未匹配的本地电视剧和动漫；自动拉取只处理之后新增且未匹配的内容，周期与媒体库文件自动扫描独立。置信度偏低的结果会跳过，仍可在「片库健康 → 补充」中手动复核。',
              ),
              if (batch.running ||
                  batch.processed > 0 ||
                  batch.cancelled ||
                  batch.message != null) ...[
                const SizedBox(height: 12),
                _BatchMatchStatus(state: batch),
              ],
              if (_error != null || _notice != null) ...[
                const SizedBox(height: 12),
                AppSettingsNotice(
                  message: _error ?? _notice!,
                  error: _error != null,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BatchMatchStatus extends StatelessWidget {
  const _BatchMatchStatus({required this.state});

  final TmdbBatchState state;

  String get _summary {
    final supplied = state.message?.trim();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    if (state.running) {
      return state.total > 0
          ? '正在匹配 ${state.processed}/${state.total} 部剧集…'
          : '正在准备需要匹配的剧集…';
    }
    if (state.cancelled) {
      return '匹配已取消；已处理 ${state.processed}/${state.total} 部剧集。';
    }
    return '匹配完成：已为 ${state.matched}/${state.total} 部电视剧 / 动漫匹配 TMDB 信息。';
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Semantics(
      key: const ValueKey('tmdb-batch-status'),
      liveRegion: true,
      label: _summary,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: palette.cleanPanelFill.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (state.running)
                  SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.selectedTint,
                    ),
                  )
                else
                  Icon(
                    state.cancelled
                        ? Icons.pause_circle_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 17,
                    color: palette.selectedTint,
                  ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _summary,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            LinearProgressIndicator(
              key: const ValueKey('tmdb-batch-progress'),
              value: state.total > 0 ? state.fraction : null,
              minHeight: 5,
              borderRadius: BorderRadius.circular(99),
              color: palette.selectedTint,
              backgroundColor: palette.border,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 5,
              children: [
                _BatchCount(label: '已处理', value: state.processed),
                _BatchCount(label: '已匹配', value: state.matched),
                _BatchCount(label: '低置信跳过', value: state.lowConfidence),
                if (state.failed > 0)
                  _BatchCount(label: '失败', value: state.failed),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchCount extends StatelessWidget {
  const _BatchCount({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final color = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    ).secondary;
    return Text(
      '$label $value',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
    );
  }
}

class _CredentialEditor extends StatelessWidget {
  const _CredentialEditor({
    required this.controller,
    required this.configured,
    required this.obscure,
    required this.busy,
    required this.onToggleVisibility,
    required this.onSave,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool configured;
  final bool obscure;
  final bool busy;
  final VoidCallback onToggleVisibility;
  final VoidCallback onSave;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 520),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final input = TextField(
          key: const ValueKey('tmdb-credential-input'),
          controller: controller,
          enabled: !busy,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSave(),
          decoration: InputDecoration(
            hintText: configured
                ? '已配置；输入新凭据以替换'
                : 'API Key 或 Read Access Token',
            suffixIcon: IconButton(
              tooltip: obscure ? '显示凭据' : '隐藏凭据',
              onPressed: busy ? null : onToggleVisibility,
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
            ),
          ),
        );
        final actions = Wrap(
          spacing: 7,
          runSpacing: 7,
          alignment: WrapAlignment.end,
          children: [
            if (configured)
              TextButton(
                key: const ValueKey('clear-tmdb-credential'),
                onPressed: busy ? null : onClear,
                child: const Text('清除'),
              ),
            FilledButton(
              key: const ValueKey('save-tmdb-credential'),
              onPressed: busy ? null : onSave,
              child: Text(busy ? '保存中…' : '保存'),
            ),
          ],
        );
        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [input, const SizedBox(height: 8), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: input),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    ),
  );
}

class _LanguageEditor extends StatelessWidget {
  const _LanguageEditor({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('tmdb-language-input'),
              controller: controller,
              focusNode: focusNode,
              enabled: !busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSave(),
              decoration: const InputDecoration(hintText: 'zh-CN'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey('save-tmdb-language'),
            onPressed: busy ? null : onSave,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.border),
            ),
            child: Text(busy ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}
