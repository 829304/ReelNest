import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../application/url_video_providers.dart';
import 'emby_cache_actions.dart';

/// URL counterpart of the original `VideoCacheMenuItems`.
///
/// The indexed identity deliberately does not expose the stored address, so
/// cache eligibility is resolved from [urlVideosProvider]. Existing cache and
/// task rendering stays in [EmbyCacheActions] and therefore shares the same
/// progress, pause, cancel, retry, maintenance, and playback paths.
class UrlVideoCacheActions extends ConsumerWidget {
  const UrlVideoCacheActions({
    required this.item,
    this.compact = false,
    this.menuOnly = false,
    super.key,
  });

  final IndexedMedia item;
  final bool compact;
  final bool menuOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videos = ref.watch(urlVideosProvider);
    return videos.when(
      data: (values) {
        final location = values
            .where((value) => value.identity == item.identity)
            .firstOrNull
            ?.url;
        final cacheable =
            location != null && UrlVideoPolicy.isCacheable(location);
        return EmbyCacheActions(
          item: item,
          compact: compact,
          menuOnly: menuOnly,
          downloadEnabled: cacheable,
          savingLabel: '正在保存缓存…',
          disabledReason: location == null
              ? '视频地址暂不可用，无法缓存'
              : '仅 HTTP/HTTPS 直链可离线缓存',
        );
      },
      loading: () => EmbyCacheActions(
        item: item,
        compact: compact,
        menuOnly: menuOnly,
        downloadEnabled: false,
        savingLabel: '正在保存缓存…',
        disabledReason: '正在读取缓存能力…',
      ),
      error: (_, _) => EmbyCacheActions(
        item: item,
        compact: compact,
        menuOnly: menuOnly,
        downloadEnabled: false,
        savingLabel: '正在保存缓存…',
        disabledReason: '视频地址读取失败，无法缓存',
      ),
    );
  }
}
