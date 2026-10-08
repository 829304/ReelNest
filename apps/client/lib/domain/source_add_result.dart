import 'media_source.dart';

typedef FolderAddFailure = ({String location, Exception error});

/// Each folder is independent: a failed folder must not lose successful ones.
class FolderAddResult {
  FolderAddResult({
    required Iterable<MediaSource> added,
    required Iterable<String> skippedLocations,
    required Iterable<FolderAddFailure> failures,
  }) : added = List.unmodifiable(added),
       skippedLocations = List.unmodifiable(skippedLocations),
       failures = List.unmodifiable(failures);

  final List<MediaSource> added;
  final List<String> skippedLocations;
  final List<FolderAddFailure> failures;
}
