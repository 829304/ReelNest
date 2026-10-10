import 'dart:async';

import '../../../domain/source_scan.dart';
import '../../../sources/emby/emby_library_synchronizer.dart';
import 'emby_connection_repository.dart';
import 'source_repository.dart';
import '../../../api/emby/emby_client.dart';
import 'emby_library_repository.dart';

class EmbySyncRepository {
  const EmbySyncRepository({
    required this.sources,
    required this.connections,
    this.onSynced,
  });
  final Future<void> Function(String)? onSynced;
  final SourceRepository sources;
  final EmbyConnectionRepository connections;
  Future<SourceScanSummary> synchronize(
    String id, {
    void Function(SourceScanProgress)? onProgress,
  }) {
    List<EmbyLibrary>? views;
    return sources
        .syncRemote(
          id,
          (source, cancellation) => EmbyLibrarySynchronizer(
            libraries: (token) async =>
                views = await connections.libraries(id, cancellation: token),
            page: (parent, start, token) => connections.itemPage(
              id,
              parentId: parent,
              start: start,
              cancellation: token,
            ),
          ).fetch(source, cancellation, onProgress: onProgress),
          onProgress: onProgress,
          commitSnapshot: () =>
              EmbyLibraryRepository(sources).replaceViews(id, views!),
        )
        .then((result) {
          if (onSynced != null) {
            unawaited(onSynced!(id).catchError((Object _) {}));
          }
          return result;
        });
  }
}
