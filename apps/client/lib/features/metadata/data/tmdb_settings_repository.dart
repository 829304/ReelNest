import 'dart:async';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../platform/secure_credential_store.dart';
import '../../../storage/credential_store.dart';
import '../../../storage/library_database.dart';
import '../domain/tmdb_models.dart';

class TmdbSettingsRepository {
  TmdbSettingsRepository(this.database, {CredentialStore? store})
    : store =
          store ??
          SecureCredentialStore(
            key: 'io.github.user829304.reelnest.tmdb.api-key',
          );
  final LibraryDatabase database;
  final CredentialStore store;
  static const languageKey = 'global.tmdbLanguage';
  Future<void> _pending = Future.value();
  Future<String> credential() async {
    try {
      return (await store.read() ?? '').trim();
    } catch (_) {
      throw const SourceFailure('无法读取 TMDB 凭据，请重新填写。');
    }
  }

  Future<TmdbSettings> read() async {
    final row = await database
        .customSelect(
          'SELECT value FROM player_preferences WHERE key=?',
          variables: [Variable(languageKey)],
        )
        .getSingleOrNull();
    return TmdbSettings(
      language: normalizedLanguage(row?.read<String>('value') ?? ''),
      hasCredential: (await credential()).isNotEmpty,
    );
  }

  static String normalizedLanguage(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'zh-CN';
    if (!RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(clean) ||
        clean.length > 32) {
      throw const SourceFailure('TMDB 语言格式不正确，例如 zh-CN 或 en-US。');
    }
    return clean;
  }

  Future<void> _write(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> saveCredential(String raw) => _write(() async {
    final value = raw.trim();
    if (value.length > 4096 || value.contains(RegExp(r'[^\x21-\x7e]'))) {
      throw const SourceFailure('TMDB API Key 或 Token 格式不正确。');
    }
    try {
      if (value.isEmpty) {
        await store.clear();
      } else {
        await store.write(value);
      }
    } catch (_) {
      throw const SourceFailure('TMDB 凭据保存失败，原配置未更改，请重试。');
    }
  });
  Future<void> setLanguage(String raw) => _write(() async {
    final value = normalizedLanguage(raw);
    try {
      await database.customStatement(
        'INSERT INTO player_preferences(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [languageKey, value],
      );
    } catch (_) {
      throw const SourceFailure('TMDB 语言设置保存失败，请重试。');
    }
  });
}
