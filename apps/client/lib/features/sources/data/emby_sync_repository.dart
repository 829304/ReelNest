import '../../../domain/source_scan.dart';
import '../../../sources/emby/emby_library_synchronizer.dart';
import 'emby_connection_repository.dart';
import 'source_repository.dart';

class EmbySyncRepository {
  const EmbySyncRepository({required this.sources, required this.connections});
  final SourceRepository sources;
  final EmbyConnectionRepository connections;
  Future<SourceScanSummary> synchronize(
    String id, {
    void Function(SourceScanProgress)? onProgress,
  }) => sources.syncRemote(
    id,
    (source, cancellation) => EmbyLibrarySynchronizer(
      libraries: (token) => connections.libraries(id, cancellation: token),
      page: (parent, start, token) => connections.itemPage(
        id,
        parentId: parent,
        start: start,
        cancellation: token,
      ),
    ).fetch(source, cancellation, onProgress: onProgress),
    onProgress: onProgress,
  );
}
