import 'media_source.dart';
import 'source_media_type.dart';
import 'source_options.dart';

/// Only fields exposed by SourcesView.SourceSettingsSheet for local sources.
/// Other source settings are preserved from the latest repository snapshot.
class SourceSettingsDraft {
  const SourceSettingsDraft({
    required this.mediaType,
    required this.includeInMetadataFetch,
    required this.includeInHealthCheck,
    required this.preferMetadataWriteToSource,
  });

  factory SourceSettingsDraft.fromSource(MediaSource source) =>
      SourceSettingsDraft(
        mediaType: source.mediaType,
        includeInMetadataFetch: source.options.includeInMetadataFetch,
        includeInHealthCheck: source.options.includeInHealthCheck,
        preferMetadataWriteToSource: source.options.preferMetadataWriteToSource,
      );

  final SourceMediaType mediaType;
  final bool includeInMetadataFetch;
  final bool includeInHealthCheck;
  final bool preferMetadataWriteToSource;

  SourceOptions applyTo(SourceOptions current) {
    final metadata =
        mediaType != SourceMediaType.photo &&
        mediaType != SourceMediaType.homeVideo &&
        includeInMetadataFetch;
    return SourceOptions.fromJson({
      ...current.toJson(),
      'includeInMetadataFetch': metadata,
      'includeInHealthCheck': includeInHealthCheck,
      'preferMetadataWriteToSource': metadata && preferMetadataWriteToSource,
    });
  }
}
