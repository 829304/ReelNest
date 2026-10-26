import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../../playback/application/online_subtitle_providers.dart';
import '../../playback/data/online_subtitle_settings_repository.dart';
import '../../playback/domain/online_subtitle.dart' as online;

class OnlineSubtitleSettings extends ConsumerStatefulWidget {
  const OnlineSubtitleSettings({super.key});

  @override
  ConsumerState<OnlineSubtitleSettings> createState() =>
      _OnlineSubtitleSettingsState();
}

class _OnlineSubtitleSettingsState
    extends ConsumerState<OnlineSubtitleSettings> {
  final _languageController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _languageFocus = FocusNode();
  final _apiKeyFocus = FocusNode();

  late final OnlineSubtitleSettingsRepository _repository;

  online.OnlineSubtitleSettings? _saved;
  online.OnlineSubtitleSettings? _saving;
  online.OnlineSubtitleSettings? _queued;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(onlineSubtitleSettingsRepositoryProvider);
    _languageFocus.addListener(_commitLanguageOnBlur);
    _apiKeyFocus.addListener(_commitAPIKeyOnBlur);
    unawaited(_load());
  }

  @override
  void dispose() {
    _persistDraftBeforeDispose();
    _languageFocus.removeListener(_commitLanguageOnBlur);
    _apiKeyFocus.removeListener(_commitAPIKeyOnBlur);
    _languageFocus.dispose();
    _apiKeyFocus.dispose();
    _languageController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _persistDraftBeforeDispose() {
    if (_loading || _saved == null) return;
    final value = _draft;
    if (_saving != null) {
      if (_same(value, _saving)) return;
      unawaited(_saveAfterDispose(value));
      return;
    }
    if (_same(value, _saved)) return;
    unawaited(_saveAfterDispose(value));
  }

  Future<void> _saveAfterDispose(online.OnlineSubtitleSettings value) async {
    try {
      await _repository.save(language: value.language, apiKey: value.apiKey);
    } catch (_) {
      // The settings page no longer has a surface for an error notice. A later
      // visit reloads the last value that the repository committed safely.
    }
  }

  void _commitLanguageOnBlur() {
    if (!_languageFocus.hasFocus) unawaited(_saveDraft());
  }

  void _commitAPIKeyOnBlur() {
    if (!_apiKeyFocus.hasFocus) unawaited(_saveDraft());
  }

  online.OnlineSubtitleSettings get _draft => online.OnlineSubtitleSettings(
    language: _languageController.text.trim().isEmpty
        ? 'zh-CN'
        : _languageController.text.trim(),
    apiKey: _apiKeyController.text.trim(),
  );

  bool _same(
    online.OnlineSubtitleSettings? left,
    online.OnlineSubtitleSettings? right,
  ) => left?.language == right?.language && left?.apiKey == right?.apiKey;

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final value = await _repository.read();
      if (!mounted) return;
      _languageController.text = value.language;
      _apiKeyController.text = value.apiKey;
      setState(() => _saved = value);
    } catch (_) {
      if (mounted) setState(() => _error = '在线字幕设置读取失败，请重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDraft() async {
    if (_loading || _saved == null || !mounted) return;
    final value = _draft;
    if (_saving != null) {
      _queued = _same(value, _saving) ? null : value;
      return;
    }
    if (_same(value, _saved)) return;
    _saving = value;
    setState(() => _error = null);
    try {
      await _repository.save(language: value.language, apiKey: value.apiKey);
      if (mounted) setState(() => _saved = value);
    } catch (_) {
      if (mounted) setState(() => _error = '在线字幕设置保存失败，请重试。');
    } finally {
      _saving = null;
      final queued = _queued;
      _queued = null;
      if (mounted) setState(() {});
      if (queued != null && !_same(queued, _saved)) {
        unawaited(_saveDraft());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final busy = _loading || _saving != null;
    return AppSettingsSection(
      title: '字幕下载',
      subtitle: '设置在线字幕来源与首选语言。',
      icon: Icons.subtitles_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSettingsRow(
            title: '首选语言',
            subtitle: '用于在线字幕搜索，默认为 zh-CN',
            icon: Icons.translate_outlined,
            trailing: SizedBox(
              width: 250,
              child: _field(
                key: const ValueKey('online-subtitle-language'),
                controller: _languageController,
                focusNode: _languageFocus,
                enabled: !_loading,
                hintText: 'zh-CN',
              ),
            ),
          ),
          const AppSettingsDivider(),
          AppSettingsRow(
            title: 'OpenSubtitles API Key',
            subtitle: '可选；留空时仍使用 Podnapisi',
            icon: Icons.key_outlined,
            trailing: SizedBox(
              width: 250,
              child: _field(
                key: const ValueKey('online-subtitle-api-key'),
                controller: _apiKeyController,
                focusNode: _apiKeyFocus,
                enabled: !_loading,
                hintText: '可选',
                obscureText: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const AppSettingsDescription(
            text:
                'Podnapisi 无需密钥；配置 API Key 后会同时搜索 OpenSubtitles。'
                '本地视频的字幕保存到影片目录，远程视频仅在当前播放会话的临时目录中使用。',
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: palette.selectedTint,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _loading ? '读取中…' : '保存中…',
                    style: TextStyle(fontSize: 11.5, color: palette.secondary),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppSettingsNotice(
                key: const ValueKey('online-subtitle-settings-error'),
                message: _error!,
                error: true,
                actionLabel: _saved == null ? '重新读取' : '重试保存',
                onAction: busy
                    ? null
                    : () => unawaited(_saved == null ? _load() : _saveDraft()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool enabled,
    required String hintText,
    bool obscureText = false,
  }) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: palette.border),
    );
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onEditingComplete: () {
        focusNode.unfocus();
        unawaited(_saveDraft());
      },
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        filled: true,
        fillColor: palette.control,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: palette.selectedTint, width: 1.2),
        ),
      ),
    );
  }
}
