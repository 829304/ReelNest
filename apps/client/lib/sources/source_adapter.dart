import '../domain/media_source.dart';
import '../domain/source_scan.dart';

/// Acquisition boundary: adapters never require a global server session.
abstract interface class SourceAdapter {
  Future<bool> isReachable(String location);
  Future<String> validateLocation(String location);
  Stream<SourceScanEvent> scan(
    MediaSource source,
    ScanCancellation cancellation,
  );
}
