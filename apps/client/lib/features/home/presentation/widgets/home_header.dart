import 'package:flutter/material.dart';

import '../../../../ui/theme/source_sheet_palette.dart';

/// HomeVividHeader / HomeVividSearchControl: 230x41, radius 13; wrap below
/// the title when the desktop window cannot fit the horizontal arrangement.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.greeting,
    required this.controller,
    required this.onChanged,
    required this.onSubmit,
    super.key,
  });
  final String greeting;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting，欢迎回来',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: p.secondary,
          ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: '今天，'),
              WidgetSpan(
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [
                      Color(0xFF36BFFA),
                      Color(0xFF2E90FA),
                      Color(0xFFFF9F45),
                      Color(0xFFFF5C8A),
                    ],
                  ).createShader(rect),
                  child: const Text(
                    '为你精选',
                    style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const TextSpan(text: '了一份片单'),
            ],
          ),
          style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
        ),
      ],
    );
    final search = Container(
      width: 230,
      height: 41,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: p.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('home-search-field'),
              controller: controller,
              onChanged: onChanged,
              onSubmitted: (_) => onSubmit(),
              style: TextStyle(fontSize: 13, color: p.text),
              decoration: InputDecoration(
                hintText: '搜索全部媒体',
                hintStyle: TextStyle(fontSize: 13, color: p.secondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
    // Measure the actual title, rather than guessing a width for Chinese fonts.
    final painter = TextPainter(
      text: TextSpan(
        text: '今天，为你精选了一份片单',
        style: DefaultTextStyle.of(context).style
            .copyWith(fontSize: 29, fontWeight: FontWeight.w900),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final titleWidth = painter.width;
    painter.dispose();
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= titleWidth + 262
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: 20),
                search,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 14), search],
            ),
    );
  }
}
