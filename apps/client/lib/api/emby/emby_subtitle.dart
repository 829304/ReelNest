/// A server stream descriptor, held only in memory (DeliveryUrl may be signed).
class EmbySubtitle {
  const EmbySubtitle({
    required this.itemId,
    required this.mediaSourceId,
    required this.index,
    required this.extension,
    this.language,
    this.title,
    this.deliveryUrl,
  });
  final String itemId;
  final String? mediaSourceId, language, title, deliveryUrl;
  final int index;
  final String extension;
  String get key => '$mediaSourceId:$index';
  String get displayName => title?.isNotEmpty == true
      ? title!
      : '${language?.toUpperCase() ?? '字幕'} · ${extension.toUpperCase()}';

  static List<EmbySubtitle> parse(
    Map<String, dynamic> item,
    String itemId,
    String? requestedSource,
  ) {
    final sources = (item['MediaSources'] as List? ?? []).whereType<Map>();
    final source =
        sources.where((s) => s['Id'] == requestedSource).firstOrNull ??
        sources.firstOrNull;
    if (source == null) return const [];
    final result = <EmbySubtitle>[];
    final seen = <int>{};
    for (final stream
        in (source['MediaStreams'] as List? ?? []).whereType<Map>()) {
      if (stream['Type']?.toString().toLowerCase() != 'subtitle' ||
          stream['Index'] is! int ||
          (stream['Index'] as int) < 0) {
        continue;
      }
      final delivery = stream['DeliveryUrl'] as String?;
      final path = Uri.tryParse(delivery ?? '')?.path ?? '';
      String? extension;
      for (final value in [
        path.split('.').last.toLowerCase(),
        stream['Codec']?.toString().toLowerCase(),
      ]) {
        extension = switch (value) {
          'srt' || 'subrip' => 'srt',
          'ass' => 'ass',
          'ssa' => 'ssa',
          'vtt' || 'webvtt' => 'vtt',
          _ => null,
        };
        if (extension != null) break;
      }
      extension ??= stream['IsTextSubtitleStream'] == true ? 'srt' : null;
      if (extension == null || !seen.add(stream['Index'] as int)) continue;
      result.add(
        EmbySubtitle(
          itemId: itemId,
          mediaSourceId: source['Id'] as String?,
          index: stream['Index'] as int,
          extension: extension,
          language: stream['Language'] as String?,
          title: stream['DisplayTitle'] as String?,
          deliveryUrl: delivery,
        ),
      );
    }
    return List.unmodifiable(result);
  }
}
