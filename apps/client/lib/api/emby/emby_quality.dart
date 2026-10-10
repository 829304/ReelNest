import 'dart:math' as math;

import '../../domain/media_source.dart';

/// RemoteVideoQualityPlanner: descriptive targets, never authenticated URLs.
class EmbyVideoQuality {
  const EmbyVideoQuality({
    required this.id,
    required this.label,
    required this.detail,
    this.width,
    this.height,
    this.bitrate,
  });
  final String id, label, detail;
  final int? width, height, bitrate;
  bool get original => id == 'original';
  static const source = EmbyVideoQuality(
    id: 'original',
    label: '原画',
    detail: '直连',
  );

  static List<EmbyVideoQuality> options(IndexedMedia item) {
    final remote = item.remote;
    final resolution = RegExp(r'^(\d+)\s*[x×]\s*(\d+)$')
        .firstMatch(remote?.resolution ?? '');
    if (remote == null ||
        item.type == 'music' ||
        resolution == null ||
        remote.mediaSourceId?.isNotEmpty != true) {
      return [];
    }
    final width = int.parse(resolution[1]!), height = int.parse(resolution[2]!);
    final duration = (remote.durationMs ?? 0) / 1000;
    final bitrate = (remote.bitrate ?? 0) > 0
        ? remote.bitrate!
        : duration > 1 && item.bytes > 0
        ? (item.bytes * 8 / duration).round()
        : 0;
    if (width <= 0 || height < 1080 || bitrate < 5800000 * 1.03) return [];
    String mbps(int b) =>
        '${(b / 1000000).toStringAsFixed(b >= 10000000 ? 0 : 1)} Mbps';
    final targets = height >= 2160
        ? [2160, 1440, 1080]
        : height >= 1440
        ? [1440, 1080]
        : [1080];
    final result = <EmbyVideoQuality>[];
    for (final h in targets) {
      final rounded = (h * width / height).round();
      final w = math.max(2, rounded - rounded % 2);
      final floor = 5800000 * math.pow(math.max(w * h / (1920 * 1080), 1), .72);
      final perTitle = bitrate * math.pow(math.min(h / height, 1), 1.35) * .72;
      final b =
          (math.max(floor, math.min(floor * 1.45, perTitle)) / 50000).round() *
          50000;
      if (b >= bitrate * .88) continue;
      result.add(
        EmbyVideoQuality(
          id: '$h-$b',
          label: h >= 2160
              ? '蓝光 4K'
              : h >= 1440
              ? '超清 2K'
              : '高清 1080P',
          detail: '${w}x$h · ${mbps(b)}',
          width: w,
          height: h,
          bitrate: b,
        ),
      );
    }
    return result.isEmpty
        ? []
        : [
            EmbyVideoQuality(
              id: 'original',
              label: '原画',
              detail: '${remote.resolution} · ${mbps(bitrate)} · 直连',
              width: width,
              height: height,
              bitrate: bitrate,
            ),
            ...result,
          ];
  }
}
