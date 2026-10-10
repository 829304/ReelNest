/// Port of MpvTrack; identifiers are mpv IDs, never list offsets.
class VideoTrack {
  const VideoTrack({
    required this.id,
    required this.type,
    this.title,
    this.language,
    this.codec,
    this.selected = false,
    this.external = false,
    this.externalFilename,
  });
  final int id;
  final String type;
  final String? title;
  final String? language;
  final String? codec;
  final bool selected;
  final bool external;
  final String? externalFilename;

  factory VideoTrack.fromMpv(Map<String, dynamic> data) => VideoTrack(
    id: data['id'] as int,
    type: data['type'] as String,
    title: data['title'] as String?,
    language: data['lang'] as String?,
    codec: data['codec'] as String?,
    selected: data['selected'] == true,
    external: data['external'] == true,
    externalFilename: data['external-filename'] == null
        ? null
        : normalizedSubtitlePath(data['external-filename'] as String),
  );

  String get displayName {
    final parts = <String>[
      if (language?.isNotEmpty == true) language!.toUpperCase(),
      if (title?.isNotEmpty == true) title!,
      if (codec?.isNotEmpty == true) codec!.toUpperCase(),
    ];
    if (parts.isEmpty) parts.add('${type == 'audio' ? '音轨' : '字幕'} $id');
    if (external) parts.add('外挂');
    return parts.join(' · ');
  }
}

/// media_kit opens Windows files with extended-length paths. mpv returns this
/// prefix for auto-loaded sidecars; compare those with picker/scanner paths.
String normalizedSubtitlePath(String value) {
  final windows = value.replaceAll('/', '\\');
  if (windows.startsWith(r'\\?\UNC\')) return r'\\' + windows.substring(8);
  if (windows.startsWith(r'\\?\')) return windows.substring(4);
  return value;
}

class VideoAudioDevice {
  const VideoAudioDevice(this.name, this.description);
  final String name;
  final String description;
  String get displayName => description.isEmpty ? name : description;
}

class VideoTrackState {
  const VideoTrackState({
    this.audio = const [],
    this.subtitles = const [],
    this.audioId,
    this.subtitleId,
    this.secondarySubtitleId,
    this.autoSubtitles = false,
    this.subtitleDelay = 0,
    this.volumeBoost = 1,
    this.devices = const [],
    this.audioDevice = 'auto',
  });
  final List<VideoTrack> audio;
  final List<VideoTrack> subtitles;
  final int? audioId;
  final int? subtitleId;
  final int? secondarySubtitleId;
  final bool autoSubtitles;
  final double subtitleDelay;
  final double volumeBoost;
  final List<VideoAudioDevice> devices;
  final String audioDevice;
}
