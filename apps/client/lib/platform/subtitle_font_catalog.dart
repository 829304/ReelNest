import 'dart:io';

import 'package:flutter/services.dart';

/// The original limits its menu to installed preferred families. Desktop names
/// differ, so select installed platform equivalents rather than fake choices.
class SubtitleFontCatalog {
  SubtitleFontCatalog({MethodChannel? channel, String? platform})
    : channel = channel ?? const MethodChannel('reelnest/subtitle_fonts'),
      platform = platform ?? Platform.operatingSystem;
  final MethodChannel channel;
  final String platform;
  Future<List<String>> families() async {
    final installed = await channel.invokeListMethod<String>('families');
    if (installed == null) throw const FormatException('Invalid font catalog');
    final lookup = {
      for (final family in installed) family.toLowerCase(): family,
    };
    final preferred = switch (platform) {
      'macos' => const [
        'PingFang SC',
        'Hiragino Sans GB',
        'Heiti SC',
        'Songti SC',
        'Yuanti SC',
        'LXGW WenKai',
        'Helvetica Neue',
        'Avenir Next',
        'Georgia',
        'Arial',
      ],
      'windows' => const [
        'Microsoft YaHei',
        '微软雅黑',
        'Microsoft YaHei UI',
        '微软雅黑 UI',
        'SimHei',
        '黑体',
        'SimSun',
        '宋体',
        'KaiTi',
        '楷体',
        'LXGW WenKai',
        'Segoe UI',
        'Arial',
        'Georgia',
      ],
      _ => const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Noto Serif CJK SC',
        'WenQuanYi Micro Hei',
        'LXGW WenKai',
        'DejaVu Sans',
        'Liberation Sans',
        'Arial',
        'Georgia',
      ],
    };
    return List<String>.unmodifiable({
      for (final name in preferred)
        if (lookup[name.toLowerCase()] != null) lookup[name.toLowerCase()]!,
    });
  }
}
