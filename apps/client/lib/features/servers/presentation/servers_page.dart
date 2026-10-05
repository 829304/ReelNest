import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/server_address.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/status_notice.dart';
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
      subtitle: '管理你的媒体来源。',
      children: [
        if (state.busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(state.activity ?? '正在连接…')),
          const SizedBox(height: 16),
        ],
        if (state.failure case final failure?) ...[
          StatusNotice(
            message: state.pendingClear
                ? '本机凭据尚未清除，请重试。清除完成前无法添加新的连接。'
                : failure.message,
            onRetry:
                state.busy ||
                    state.requiresLogin ||
                    (connection == null &&
                        !state.needsRestore &&
                        !state.pendingClear)
                ? null
                : controller.retry,
            actionLabel: state.pendingClear ? '重新清除' : '重试',
          ),
          const SizedBox(height: 16),
        ],
        if (connection != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    connection.server.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(connection.address.toString()),
                  const SizedBox(height: 8),
                  Text('账号：${connection.username}'),
                  const SizedBox(height: 8),
                  Text(
                    state.requiresLogin
                        ? '需要重新登录'
                        : state.pendingSave
                        ? '凭据尚未保存，重试后才能读取媒体库'
                        : state.catalog == null
                        ? '已保存连接，尚未读取媒体库'
                        : state.failure != null
                        ? '更新失败，保留上次读取结果'
                        : '已读取 ${state.catalog!.categories.length} 个媒体分类',
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: state.requiresLogin || state.pendingSave
                            ? null
                            : () => context.go('/servers/library'),
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('查看媒体库'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.busy || state.requiresLogin
                            ? null
                            : controller.retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新'),
                      ),
                      TextButton(
                        onPressed: state.busy ? null : controller.signOut,
                        child: const Text('退出此设备'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('退出会清除本机连接和令牌。服务端会话需在服务端管理。'),
                ],
              ),
            ),
          ),
        if (state.needsRestore && !state.pendingClear && !state.busy)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controller.signOut,
              child: const Text('清除无法读取的本机连接'),
            ),
          ),
        if (canEnterCredentials) ...[
          if (connection == null) ...[
            Text('还没有服务器', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 16),
          _ConnectionForm(
            key: ValueKey('${connection?.address}:${connection?.username}'),
            initialAddress: connection?.address.toString() ?? '',
            initialUsername: connection?.username ?? '',
            busy: state.busy,
          ),
        ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('服务器连接', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('连接 ReelNest Server，填写服务器地址和登录凭据。'),
              const SizedBox(height: 20),
              TextFormField(
                controller: _address,
                enabled: !widget.busy,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://media.example.com',
                  border: OutlineInputBorder(),
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
                controller: _username,
                enabled: !widget.busy,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                  errorMaxLines: 3,
                ),
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
                controller: _password,
                enabled: !widget.busy,
                obscureText: _obscurePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.go,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
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
              const SizedBox(height: 16),
              const Text(
                '密码仅用于本次登录；会话令牌保存到系统安全存储。'
                '局域网地址也需要 HTTPS，只有回环地址允许 HTTP。',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: widget.busy ? null : _submit,
                icon: const Icon(Icons.login),
                label: Text(widget.busy ? '连接中…' : '登录并同步'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
