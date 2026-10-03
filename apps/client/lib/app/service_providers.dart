import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/mlink/mlink_client.dart';
import '../features/servers/data/server_repository.dart';
import '../platform/secure_credential_store.dart';
import '../storage/credential_store.dart';

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => SecureCredentialStore(),
);

final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  return ServerRepository(
    client: MlinkClient(),
    store: ref.watch(credentialStoreProvider),
    platform: switch (Platform.operatingSystem) {
      'macos' => 'macOS',
      'ios' => 'iOS',
      'android' => 'Android',
      'windows' => 'Windows',
      _ => 'Linux',
    },
  );
});
