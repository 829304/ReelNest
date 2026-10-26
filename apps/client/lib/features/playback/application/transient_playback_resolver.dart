import 'package:drift/drift.dart';

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../sources/data/source_repository.dart';

/// A bounded lookup by source-relative identity, never a full library scan.
Future<MediaIdentity?> indexedFileIdentity(
  SourceRepository sources,
  String path,
) async {
  final absolute = p.normalize(p.absolute(path));
  for (final source in await sources.sources(includeCounts: false)) {
    if (!source.kind.isFileSource || !p.isWithin(source.location, absolute)) {
      continue;
    }
    final relative = p.posix.joinAll(
      p.split(p.relative(absolute, from: source.location)),
    );
    final row = await sources.database
        .customSelect(
          "SELECT local_id FROM media WHERE source_id=? AND local_id=? ${Platform.isWindows ? 'COLLATE NOCASE' : ''} AND is_series=0 AND type NOT IN ('music','photo')",
          variables: [Variable(source.id), Variable(relative)],
        )
        .getSingleOrNull();
    if (row != null) {
      return (sourceId: source.id, localId: row.read<String>('local_id'));
    }
  }
  return null;
}
