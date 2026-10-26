import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../application/tmdb_providers.dart';

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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(tmdbSettingsProvider);
    return AppSettingsSection(
      title: '元数据与匹配',
      subtitle: '管理本地电影的 TMDB 信息来源。',
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
