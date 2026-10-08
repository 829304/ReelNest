import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/sources/filesystem/filename_parser.dart';

// Ported from FilenameParserTests, FilenameParserMultiLanguageTests and
// MediaScannerBoundaryAuditTests, plus desktop paths and source boundaries.
void main() {
  final parser = FilenameParser(paths: p.Context(style: p.Style.posix));

  test('original movie release cleanup and unknown year', () {
    final movie = parser.parse(
      '/Movies/Inception.2010.1080p.BluRay.x265.mkv',
      preferredType: SourceMediaType.movie,
    );
    expect(movie.kind, ParsedMediaKind.movie);
    expect(movie.title, 'Inception');
    expect(movie.year, 2010);
    expect(movie.seasonNumber, isNull);
    expect(movie.episodeNumber, isNull);
    expect(movie.seriesDirectoryPath, isNull);
    final unknown = parser.parse('/Movies/SomeIndependentFilm.mkv');
    expect(unknown.title, 'SomeIndependentFilm');
    expect(unknown.year, isNull);
  });

  test('original English and Chinese season and episode patterns', () {
    for (final sample in [
      ('/TV/Breaking Bad/Breaking Bad.S02E07.mkv', 'Breaking Bad', 2, 7),
      ('/TV/The Wire/The Wire.S03E11.mkv', 'The Wire', 3, 11),
      ('/剧集/某剧/某剧 第2季第05集.mkv', '某剧', 2, 5),
      ('/剧集/某剧/第3部第06話.mkv', '某剧', 3, 6),
      ('/Anime/ShowName/ShowName.EP12.mkv', 'ShowName', 1, 12),
      ('/Anime/ShowName/Season 04/e013.mkv', 'ShowName', 4, 13),
    ]) {
      final result = parser.parse(sample.$1);
      expect(result.kind, ParsedMediaKind.episode, reason: sample.$1);
      expect(result.title, sample.$2);
      expect(result.seasonNumber, sample.$3);
      expect(result.episodeNumber, sample.$4);
      expect(result.year, isNull);
    }
  });

  test('show directory overrides release title and strips its year suffix', () {
    final result = parser.parse(
      '/TV/正确剧名 (2020)/Season 2/Wrong.S02E03.mkv',
      sourcePath: '/TV',
    );
    expect(result.title, '正确剧名');
    expect(result.seriesDirectoryPath, '/TV/正确剧名 (2020)');
    expect(result.seasonNumber, 2);
    expect(result.episodeNumber, 3);
    expect(result.year, isNull);
    final root = parser.parse('/TV/Show.S01E02.mkv', sourcePath: '/TV/./');
    expect(root.title, 'Show');
    expect(root.seriesDirectoryPath, isNull);
  });

  test('number-only episodes require an original season-folder pattern', () {
    for (final sample in [('Season 02', 2), ('第3季', 3), ('Specials', 1)]) {
      final result = parser.parse('/TV/Show/${sample.$1}/07 - Title.mkv');
      expect(result.kind, ParsedMediaKind.episode);
      expect(result.title, 'Show');
      expect(result.seasonNumber, sample.$2);
      expect(result.episodeNumber, 7);
      expect(result.seriesDirectoryPath, '/TV/Show');
    }
    // The original does not treat S02 folders or loose numbers as episodes.
    expect(parser.parse('/TV/Show/S02/07.mkv').kind, ParsedMediaKind.movie);
    expect(parser.parse('/TV/Show/07.mkv').kind, ParsedMediaKind.movie);
  });

  test(
    'forced movie suppresses episode parsing; TV preference does not invent it',
    () {
      final movie = parser.parse(
        '/TV/Show/Show.S02E03.mkv',
        preferredType: SourceMediaType.movie,
      );
      expect(movie.kind, ParsedMediaKind.movie);
      expect(movie.title, 'Show S02E03');
      expect(movie.episodeNumber, isNull);
      final unnumbered = parser.parse(
        '/TV/Show/Some Film.mkv',
        preferredType: SourceMediaType.tvShow,
      );
      expect(unnumbered.kind, ParsedMediaKind.movie);
      expect(unnumbered.title, 'Some Film');
    },
  );

  test('original numeric titles and final release-year rule', () {
    final numeric = parser.parse(
      '/Movies/[BD-Remux] 1984 (1984) [1080p_FLAC].mkv',
    );
    expect(numeric.title, '1984');
    expect(numeric.year, 1984);
    final space = parser.parse(
      '/Movies/2001太空漫游.2001.A.Space.Odyssey.1968.UHD.BluRay.2160p.TrueHD.7.1.x265.mkv',
    );
    expect(space.title, contains('2001太空漫游'));
    expect(space.year, 1968);
    expect(parser.parse('/Movies/Blade Runner 2049 (2017).mkv').year, 2017);
    expect(parser.parse('/Movies/Some Film (2021)/Some Film.mkv').year, 2021);
    // Preserve the original short-title fallback rather than changing it.
    expect(parser.parse('/Movies/Up.2009.mkv').title, 'Up 2009');
    expect(parser.parse('/Movies/éa.2009.mkv').title, 'éa 2009');
  });

  test('original multilingual and complex release-tag examples', () {
    final anime = parser.parse(
      '/Anime/[Ohys-Raws] 进击的巨人 / 進撃の巨人 / Attack on Titan - 01 (BS11 1280x720 x264 AAC).mp4',
    );
    expect(anime.title, contains('Attack on Titan'));
    expect(anime.year, isNull);
    final korean = parser.parse(
      '/Movies/기생충.Parasite.2019.1080p.FHDRip.H264.AAC.mp4',
    );
    expect(korean.title, contains('기생충'));
    expect(korean.year, 2019);
    final russian = parser.parse(
      '/Movies/Солярис.Solaris.1972.BD.Remux.1080p.mkv',
    );
    expect(russian.title, contains('Солярис'));
    expect(russian.year, 1972);
    final complex = parser.parse(
      '/Anime/[BD-1080p] [动漫屋·独家压制] 🔥进击的巨人 Final Season Part 3 [2023] [HEVC_FLAC_2.0][中日双语内嵌] [修正版].mkv',
    );
    expect(complex.title, '进击的巨人 Final Season Part 3');
    expect(complex.year, 2023);
  });

  test(
    'emoji presentation is stripped without stripping numbers or punctuation',
    () {
      final result = parser.parse(
        '/Movies/🚀🔥✨ [2025新春特别篇] 快乐生活与编程！(2025) #4K UHD.mp4',
      );
      expect(result.title, '快乐生活与编程！ #4K UHD');
      expect(result.year, 2025);
      expect(parser.parse('/Movies/Title #1 *2 ©.mp4').title, 'Title #1 *2 ©');
      final tags = List.filled(80, '[Tag]').join();
      expect(
        parser.parse('/Movies/$tags My Movie Title (2024).mp4').title,
        'My Movie Title',
      );
    },
  );

  for (final style in [p.Style.windows, p.Style.posix]) {
    test('$style paths preserve show folders and exclude the source root', () {
      final paths = p.Context(style: style);
      final parser = FilenameParser(paths: paths);
      final root = style == p.Style.windows ? r'C:\Media' : '/Media';
      final result = parser.parse(
        paths.join(root, 'Show (2024)', 'Season 2', 'S02E007.mkv'),
        sourcePath: root,
      );
      expect(result.title, 'Show');
      expect(result.seriesDirectoryPath, paths.join(root, 'Show (2024)'));
      expect(result.episodeNumber, 7);
      final loose = parser.parse(
        paths.join(root, 'Show.S02E007.mkv'),
        sourcePath: root,
      );
      expect(loose.title, 'Show');
      expect(loose.seriesDirectoryPath, isNull);
    });
  }

  test('Windows UNC paths and case-insensitive root comparison', () {
    final parser = FilenameParser(paths: p.Context(style: p.Style.windows));
    final result = parser.parse(
      r'\\nas\share\Show\Season 3\EP12.mkv',
      sourcePath: r'\\nas\share',
    );
    expect(result.title, 'Show');
    expect(result.seasonNumber, 3);
    expect(result.seriesDirectoryPath, r'\\nas\share\Show');
    final loose = parser.parse(
      r'C:\Media\Show.S01E01.mkv',
      sourcePath: r'c:\media',
    );
    expect(loose.title, 'Show');
    expect(loose.seriesDirectoryPath, isNull);
  });
}
