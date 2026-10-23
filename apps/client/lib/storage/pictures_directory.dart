import 'dart:io';

import 'package:path/path.dart' as p;

/// Read user-dirs as data, never source it through a shell. Unknown expansions
/// and relative paths fall back to Pictures rather than depending on cwd.
String linuxPicturesPath(String home, String? userDirs) {
  final fallback = p.posix.join(home, 'Pictures');
  if (userDirs == null) return fallback;
  final match = RegExp(
    r'^\s*XDG_PICTURES_DIR="((?:\\.|[^"\\])*)"\s*(?:#.*)?$',
    multiLine: true,
  ).firstMatch(userDirs);
  if (match == null) return fallback;
  var value = match[1]!;
  if (value == r'$HOME' || value == r'${HOME}') return home;
  if (value.startsWith(r'$HOME/')) value = home + value.substring(5);
  if (value.startsWith(r'${HOME}/')) value = home + value.substring(7);
  value = value.replaceAllMapped(RegExp(r'\\([\\"$`])'), (m) => m[1]!);
  return p.posix.isAbsolute(value) ? p.posix.normalize(value) : fallback;
}

Future<Directory> desktopPicturesDirectory(String home) async {
  if (!Platform.isLinux) return Directory(p.join(home, 'Pictures'));
  final configured = Platform.environment['XDG_CONFIG_HOME'];
  final config = configured != null && p.isAbsolute(configured)
      ? configured
      : p.join(home, '.config');
  final file = File(p.join(config, 'user-dirs.dirs'));
  String? text;
  try {
    // This tiny local config should never require an unbounded read.
    if (await file.length() <= 64 * 1024) text = await file.readAsString();
  } on FileSystemException {
    // The XDG default applies when the optional config is absent/unreadable.
  } on FormatException {
    // Corrupt optional config is not a reason to reject a valid Pictures path.
  }
  return Directory(linuxPicturesPath(home, text));
}
