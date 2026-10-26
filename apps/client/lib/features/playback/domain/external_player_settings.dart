import 'dart:convert';
import 'dart:typed_data';

enum ExternalPlayerMode { builtIn, external }

class ExternalPlayerSettings {
  const ExternalPlayerSettings({
    this.mode = ExternalPlayerMode.builtIn,
    this.applicationPath,
    this.applicationBookmark,
  });
  final ExternalPlayerMode mode;
  final String? applicationPath;
  final Uint8List? applicationBookmark;
  ExternalPlayerSettings copyWith({ExternalPlayerMode? mode}) =>
      ExternalPlayerSettings(
        mode: mode ?? this.mode,
        applicationPath: applicationPath,
        applicationBookmark: applicationBookmark,
      );
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'applicationPath': applicationPath,
    if (applicationBookmark != null)
      'applicationBookmark': base64Encode(applicationBookmark!),
  };
  factory ExternalPlayerSettings.fromJson(Map<String, dynamic> json) {
    final mode = ExternalPlayerMode.values.byName(json['mode'] as String);
    final path = json['applicationPath'] as String?;
    final bookmark = json['applicationBookmark'] as String?;
    if (path?.contains('\u0000') == true ||
        (bookmark?.length ?? 0) > 128 * 1024) {
      throw const FormatException('Invalid player settings');
    }
    return ExternalPlayerSettings(
      mode: mode,
      applicationPath: path?.trim().isEmpty == true ? null : path,
      applicationBookmark: bookmark == null ? null : base64Decode(bookmark),
    );
  }
}

class ExternalPlayerApplication {
  const ExternalPlayerApplication({required this.name, required this.path});
  final String name, path;
}
