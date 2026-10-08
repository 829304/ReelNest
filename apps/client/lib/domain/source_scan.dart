import 'media_source.dart';

sealed class SourceScanEvent {
  const SourceScanEvent();
}

class ScanCatalogued extends SourceScanEvent {
  const ScanCatalogued(this.totalFiles);
  final int totalFiles;
}

/// One supported file: imported, below the size threshold, or failed.
class ScanFileProcessed extends SourceScanEvent {
  const ScanFileProcessed({
    required this.path,
    this.item,
    this.parent,
    this.error,
  });
  final String path;
  final IndexedMedia? item;

  /// The original scanner imports both a show and its episode for one file.
  /// Repository commits this pair atomically and counts it as one file.
  final IndexedMedia? parent;
  final String? error;
}

class SourceScanProgress {
  const SourceScanProgress({
    this.totalFiles = 0,
    this.processedFiles = 0,
    this.importedItems = 0,
    this.skippedFiles = 0,
    this.currentPath,
    this.errors = const [],
  });
  final int totalFiles;
  final int processedFiles;
  final int importedItems;
  final int skippedFiles;
  final String? currentPath;
  final List<String> errors;
  double get fraction =>
      totalFiles == 0 ? 0 : (processedFiles / totalFiles).clamp(0, 1);
}

class SourceScanSummary {
  SourceScanSummary({
    required this.scannedFiles,
    required this.importedItems,
    required this.skippedFiles,
    required List<String> errors,
  }) : errors = List.unmodifiable(errors);
  final int scannedFiles;
  final int importedItems;
  final int skippedFiles;
  final List<String> errors;
}
