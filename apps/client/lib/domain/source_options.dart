/// Source policy defaults from MediaLibCore/Models/MediaSource.swift.
/// Persistence does not imply that each consuming service has been migrated.
enum RemoteTraceSyncMode {
  bidirectional,
  importOnly,
  disabled;

  static RemoteTraceSyncMode fromStorage(Object? value) =>
      values.where((mode) => mode.name == value).firstOrNull ?? bidirectional;
}

class SourceOptions {
  SourceOptions({
    this.autoScan = true,
    this.readNFO = true,
    this.preferLocalArtwork = true,
    this.networkScrapingEnabled = true,
    this.screenshotFallbackEnabled = true,
    this.includeInMetadataFetch = true,
    this.preferMetadataWriteToSource = false,
    this.includeInHealthCheck = true,
    this.remoteTraceSyncMode = RemoteTraceSyncMode.bidirectional,
    List<String> selectedEmbyLibraryIDs = const [],
  }) : selectedEmbyLibraryIDs = List.unmodifiable(
         selectedEmbyLibraryIDs
             .map((id) => id.trim())
             .where((id) => id.isNotEmpty)
             .toSet(),
       );

  const SourceOptions.defaults()
    : autoScan = true,
      readNFO = true,
      preferLocalArtwork = true,
      networkScrapingEnabled = true,
      screenshotFallbackEnabled = true,
      includeInMetadataFetch = true,
      preferMetadataWriteToSource = false,
      includeInHealthCheck = true,
      remoteTraceSyncMode = RemoteTraceSyncMode.bidirectional,
      selectedEmbyLibraryIDs = const [];

  final bool autoScan;
  final bool readNFO;
  final bool preferLocalArtwork;
  final bool networkScrapingEnabled;
  final bool screenshotFallbackEnabled;
  final bool includeInMetadataFetch;
  final bool preferMetadataWriteToSource;
  final bool includeInHealthCheck;
  final RemoteTraceSyncMode remoteTraceSyncMode;
  final List<String> selectedEmbyLibraryIDs;

  factory SourceOptions.fromJson(Map<String, dynamic> json) => SourceOptions(
    autoScan: json['autoScan'] as bool? ?? true,
    readNFO: json['readNFO'] as bool? ?? true,
    preferLocalArtwork: json['preferLocalArtwork'] as bool? ?? true,
    networkScrapingEnabled: json['networkScrapingEnabled'] as bool? ?? true,
    screenshotFallbackEnabled:
        json['screenshotFallbackEnabled'] as bool? ?? true,
    includeInMetadataFetch: json['includeInMetadataFetch'] as bool? ?? true,
    preferMetadataWriteToSource:
        json['preferMetadataWriteToSource'] as bool? ?? false,
    includeInHealthCheck: json['includeInHealthCheck'] as bool? ?? true,
    remoteTraceSyncMode: RemoteTraceSyncMode.fromStorage(
      json['remoteTraceSyncMode'],
    ),
    selectedEmbyLibraryIDs: List<String>.from(
      json['selectedEmbyLibraryIDs'] as List? ?? const [],
    ),
  );

  Map<String, dynamic> toJson() => {
    'autoScan': autoScan,
    'readNFO': readNFO,
    'preferLocalArtwork': preferLocalArtwork,
    'networkScrapingEnabled': networkScrapingEnabled,
    'screenshotFallbackEnabled': screenshotFallbackEnabled,
    'includeInMetadataFetch': includeInMetadataFetch,
    'preferMetadataWriteToSource': preferMetadataWriteToSource,
    'includeInHealthCheck': includeInHealthCheck,
    'remoteTraceSyncMode': remoteTraceSyncMode.name,
    'selectedEmbyLibraryIDs': selectedEmbyLibraryIDs,
  };
}
