import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/server_address.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/connection_controller.dart';

class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionControllerProvider);
    final controller = ref.read(connectionControllerProvider.notifier);
    final connection = state.connection;
    final canEnterCredentials =
        !state.needsRestore &&
        !state.pendingClear &&
        (connection == null || state.requiresLogin);
    return PageContent(
      title: '服务器',
      subtitle: '连接并管理 ReelNest Server。',
      header: const AppSettingsHeader(
        title: '服务器',
        subtitle: '连接并管理 ReelNest Server。',
        icon: Icons.dns_outlined,
      ),
      children: [
        if (state.busy) ...[
          AppSettingsNotice(message: state.activity ?? '正在连接…'),
          const SizedBox(height: 18),
        ],
        if (state.failure case final failure?) ...[
          AppSettingsNotice(
            message: state.pendingClear
                ? '本机凭据尚未清除，请重试。清除完成前无法添加新的连接。'
                : failure.message,
            error: true,
            onAction:
                state.busy ||
                    state.requiresLogin ||
                    (connection == null &&
                        !state.needsRestore &&
                        !state.pendingClear)
                ? null
                : controller.retry,
            actionLabel: state.pendingClear ? '重新清除' : '重试',
          ),
          const SizedBox(height: 18),
        ],
        if (connection != null)
          AppSettingsSection(
            title: '当前连接',
            subtitle: '查看服务器状态、媒体分类和本机登录信息。',
            icon: Icons.cloud_done_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSettingsRow(
                  title: '服务器',
                  icon: Icons.dns_outlined,
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        connection.server.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        connection.address.toString(),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const AppSettingsDivider(),
                AppSettingsRow(
                  title: '登录账号',
                  icon: Icons.person_outline,
                  trailing: Text(
                    connection.username,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const AppSettingsDivider(),
                AppSettingsRow(
                  title: '连接状态',
                  icon: state.requiresLogin
                      ? Icons.warning_amber_outlined
                      : Icons.check_circle_outline,
                  trailing: Text(
                    state.requiresLogin
                        ? '需要重新登录'
                        : state.pendingSave
                        ? '凭据尚未保存，重试后才能读取媒体库'
                        : state.catalog == null
                        ? '已保存连接，尚未读取媒体库'
                        : state.failure != null
                        ? '更新失败，保留上次读取结果'
                        : '已读取 ${state.catalog!.categories.length} 个媒体分类',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: state.requiresLogin
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    SourceSheetButton(
                      label: '查看媒体库',
                      prominent: true,
                      icon: const Icon(Icons.video_library_outlined, size: 14),
                      onPressed: state.requiresLogin || state.pendingSave
                          ? null
                          : () => context.go('/servers/library'),
                    ),
                    SourceSheetButton(
                      label: '刷新',
                      outlined: true,
                      icon: const Icon(Icons.refresh, size: 14),
                      onPressed: state.busy || state.requiresLogin
                          ? null
                          : controller.retry,
                    ),
                    SourceSheetButton(
                      label: '退出此设备',
                      onPressed: state.busy ? null : controller.signOut,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const AppSettingsDescription(
                  text: '退出会清除本机连接和令牌。服务端会话需在服务端管理。',
                ),
              ],
            ),
          ),
        if (connection != null && canEnterCredentials)
          const SizedBox(height: 28),
        if (state.needsRestore && !state.pendingClear && !state.busy) ...[
          Align(
            alignment: Alignment.centerRight,
            child: SourceSheetButton(
              label: '清除无法读取的本机连接',
              outlined: true,
              onPressed: controller.signOut,
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (canEnterCredentials && connection == null) ...[
          const AppSettingsNotice(message: '还没有服务器'),
          const SizedBox(height: 18),
        ],
        if (canEnterCredentials)
          _ConnectionForm(
            key: ValueKey('${connection?.address}:${connection?.username}'),
            initialAddress: connection?.address.toString() ?? '',
            initialUsername: connection?.username ?? '',
            busy: state.busy,
          ),
      ],
    );
  }
}

class _ConnectionForm extends ConsumerStatefulWidget {
  const _ConnectionForm({
    required this.initialAddress,
    required this.initialUsername,
    required this.busy,
    super.key,
  });

  final String initialAddress;
  final String initialUsername;
  final bool busy;

  @override
  ConsumerState<_ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends ConsumerState<_ConnectionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _address;
  late final TextEditingController _username;
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: widget.initialAddress);
    _username = TextEditingController(text: widget.initialUsername);
  }

  @override
  void dispose() {
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final password = _password.text;
    _password.clear();
    await ref
        .read(connectionControllerProvider.notifier)
        .connect(
          address: _address.text,
          username: _username.text,
          password: password,
        );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    InputDecoration decoration({
      required String label,
      String? hint,
      Widget? suffix,
      int errorMaxLines = 3,
    }) => InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      errorMaxLines: errorMaxLines,
      filled: true,
      fillColor: palette.control.withValues(alpha: .70),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border),
      ),
    );
    return AppSettingsSection(
      title: '服务器连接',
      subtitle: '填写 ReelNest Server 地址和登录凭据。',
      icon: Icons.add_link_outlined,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSettingsSubsectionHeader(
              title: '登录信息',
              icon: Icons.lock_outline,
            ),
            const SizedBox(height: 12),
            AutofillGroup(
              child: Column(
                children: [
                  TextFormField(
                    key: const ValueKey('server-address-field'),
                    controller: _address,
                    enabled: !widget.busy,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.url],
                    decoration: decoration(
                      label: '服务器地址',
                      hint: 'https://media.example.com',
                      errorMaxLines: 4,
                    ),
                    validator: (value) {
                      try {
                        ServerAddress.parse(value ?? '');
                        return null;
                      } on AppFailure catch (error) {
                        return error.message;
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('server-username-field'),
                    controller: _username,
                    enabled: !widget.busy,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.username],
                    decoration: decoration(label: '用户名'),
                    validator: (value) {
                      final username = (value ?? '').trim();
                      if (username.isEmpty) return '请填写用户名';
                      return utf8.encode(username).length > 128
                          ? '用户名不得超过 128 字节'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('server-password-field'),
                    controller: _password,
                    enabled: !widget.busy,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.go,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: decoration(
                      label: '密码',
                      suffix: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: widget.busy
                            ? null
                            : () => setState(() {
                                _obscurePassword = !_obscurePassword;
                              }),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return '请填写密码';
                      return utf8.encode(value).length > 1024
                          ? '密码不得超过 1024 字节'
                          : null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const AppSettingsDescription(
              text: '密码仅用于本次登录；会话令牌保存到本机安全存储。局域网地址也需要 HTTPS，只有回环地址允许 HTTP。',
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: SourceSheetButton(
                label: widget.busy ? '连接中…' : '登录并同步',
                prominent: true,
                icon: const Icon(Icons.login, size: 14),
                onPressed: widget.busy ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
