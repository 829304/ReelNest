class TmdbBatchState {
  const TmdbBatchState({
    this.running = false,
    this.total = 0,
    this.processed = 0,
    this.matched = 0,
    this.lowConfidence = 0,
    this.failed = 0,
    this.cancelled = false,
    this.message,
  });
  final bool running, cancelled;
  final int total, processed, matched, lowConfidence, failed;
  final String? message;
  double get fraction => total == 0 ? 0 : (processed / total).clamp(0, 1);
}
