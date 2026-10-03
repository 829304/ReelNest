import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

class PageContent extends StatelessWidget {
  const PageContent({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: constraints.maxWidth < 500
                ? 20
                : DesignTokens.pageHorizontal,
            vertical: DesignTokens.pageVertical,
          ),
          children: [
            Text(title, style: theme.textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        );
      },
    );
  }
}
