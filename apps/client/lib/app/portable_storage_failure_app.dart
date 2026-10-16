import 'package:flutter/material.dart';

import '../ui/theme/app_palette.dart';
import '../ui/theme/app_theme.dart';
import '../ui/theme/design_tokens.dart';

/// Standalone fallback shown when ReelNest cannot initialize portable storage.
///
/// Keep [message] user-facing and sanitized. System exceptions, credentials,
/// and filesystem paths must remain in diagnostics rather than this screen.
class PortableStorageFailureApp extends StatelessWidget {
  const PortableStorageFailureApp({this.message = defaultMessage, super.key});

  static const defaultMessage = '请将 ReelNest 完整文件夹移动到可写目录后重新打开。';

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ReelNest 无法启动',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: _PortableStorageFailureView(message: message),
  );
}

class _PortableStorageFailureView extends StatelessWidget {
  const _PortableStorageFailureView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignTokens.pageHorizontal),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(DesignTokens.cardRadius),
                  border: Border.all(color: palette.border),
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadow.withValues(alpha: .10),
                      blurRadius: 28,
                      spreadRadius: -10,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 30,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.iconChip,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(
                          dimension: 52,
                          child: Icon(
                            Icons.folder_off_rounded,
                            color: palette.iconGlyph,
                            size: 25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '程序目录不可写',
                        key: const ValueKey('portable-storage-failure-title'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        message,
                        key: const ValueKey('portable-storage-failure-message'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: palette.secondary, height: 1.55),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
