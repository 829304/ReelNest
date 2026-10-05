import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/sources/filesystem/media_file_policy.dart';

void main() {
  MediaSource source(SourceMediaType type, {int size = 50 * 1024 * 1024}) =>
      MediaSource(
        id: 'fixture',
        kind: MediaSourceKind.localFolder,
        name: 'Fixture',
        location: '/fixture',
        mediaType: type,
        minimumFileSize: size,
      );

  test('original source categories distinguish album assets from sidecars', () {
    for (final type in SourceMediaType.values) {
      expect(
        MediaFilePolicy.accepts('movie.M2TS', type),
        type != SourceMediaType.music,
      );
      expect(
        MediaFilePolicy.accepts('song.CAF', type),
        type == SourceMediaType.music || type == SourceMediaType.auto,
      );
      expect(
        MediaFilePolicy.accepts('cover.HEIC', type),
        type == SourceMediaType.photo,
      );
      for (final sidecar in [
        'movie.nfo',
        'subtitle.ass',
        'song.lrc',
        'disc.cue',
        'readme.txt',
      ]) {
        expect(MediaFilePolicy.accepts(sidecar, type), isFalse);
      }
    }
    expect(MediaFilePolicy.accepts('photo.CR2', SourceMediaType.photo), isTrue);
    expect(
      MediaFilePolicy.accepts('no-extension', SourceMediaType.auto),
      isFalse,
    );
  });

  test('50 MiB video, 512 KiB audio cap, and unrestricted album sizes', () {
    final automatic = source(SourceMediaType.auto);
    expect(MediaFilePolicy.minimumBytes('movie.mkv', automatic), 52428800);
    expect(MediaFilePolicy.minimumBytes('song.mka', automatic), 524288);
    final lowerLimit = source(SourceMediaType.auto, size: 128);
    expect(MediaFilePolicy.minimumBytes('song.mp3', lowerLimit), 128);
    expect(MediaFilePolicy.minimumBytes('movie.mp4', lowerLimit), 128);
    final album = source(SourceMediaType.photo);
    expect(MediaFilePolicy.minimumBytes('photo.dng', album), 0);
    expect(MediaFilePolicy.minimumBytes('clip.mov', album), 0);
  });
}
