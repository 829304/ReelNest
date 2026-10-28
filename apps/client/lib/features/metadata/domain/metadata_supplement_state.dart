class MetadataSupplementState {
  const MetadataSupplementState({
    this.running = false,
    this.total = 0,
    this.processed = 0,
    this.updated = 0,
    this.skipped = 0,
    this.failed = 0,
    this.warningCount = 0,
    this.message,
  });
  final bool running;
  final int total, processed, updated, skipped, failed, warningCount;
  final String? message;
  double get fraction => total == 0 ? 0 : (processed / total).clamp(0, 1);
}
