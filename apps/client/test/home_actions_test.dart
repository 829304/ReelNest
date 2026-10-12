import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/home/application/home_actions.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/emby_server_fixture.dart';

class _Store implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class _Http extends HttpOverrides {}

void main() {
  for (final mode in [
    RemoteTraceSyncMode.bidirectional,
    RemoteTraceSyncMode.importOnly,
  ]) {
    for (final failed in [false, true]) {
      testWidgets(
        'home clear preserves local state and reports upload failure: ${mode.name}/$failed',
        (tester) async {
          final server = EmbyServerFixture();
          late EmbyClient client;
          late SourceRepository sources;
          late EmbyConnectionRepository connections;
          await tester.runAsync(() async {
            await server.start();
            client = EmbyClient(
              deviceId: 'home-action-fixture',
              http: HttpOverrides.runWithHttpOverrides(
                () => HttpClient(),
                _Http(),
              ),
            );
            sources = SourceRepository(
              database: LibraryDatabase(NativeDatabase.memory()),
              adapters: {},
            );
            final stores = <String, _Store>{};
            connections = EmbyConnectionRepository(
              sources: sources,
              client: Future.value(client),
              stores: (id) => stores.putIfAbsent(id, _Store.new),
            );
          });
          addTearDown(() async {
            connections.dispose();
            client.close();
            await sources.close();
            await server.close();
          });
          // No runtime/position/date: the synced zero clock must not hide the
          // percentage or make clearHistory silently skip this item.
          server.catalog['movies'] = [
            {
              'Id': 'percentage-film',
              'Name': '百分比影片',
              'Type': 'Movie',
              'UserData': {'PlayedPercentage': 40, 'Played': false},
            },
          ];
          server.catalog['shows'] = [];
          late MediaSource source;
          await tester.runAsync(() async {
            source = await connections.connect(
              server.address,
              'tester',
              'fixture password',
            );
            await sources.updateSettings(
              source.id,
              options: SourceOptions(remoteTraceSyncMode: mode),
            );
            await EmbySyncRepository(
              sources: sources,
              connections: connections,
            ).synchronize(source.id);
          });
          final home = HomeRepository(sources);
          final video = (await home.recommendationCandidates(source.id)).single;
          expect(video.entry.progress, .4);
          expect(
            (await EmbyLibraryRepository(sources).snapshot(source.id))
                .entries
                .single
                .progress,
            .4,
          );
          server.userFlagHandler = (request) async {
            request.response.statusCode = failed ? 500 : 204;
            await request.response.close();
          };
          Future<void>? action;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sourceRepositoryProvider.overrideWithValue(sources),
                embyConnectionProvider.overrideWithValue(connections),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () {
                        action = homeVideoAction(context, ref, video, 'clear');
                      },
                      child: const Text('清除记录'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await tester.tap(find.text('清除记录'));
            await action;
          });
          await tester.pumpAndSettle();
          expect(
            (await PlaybackRepository(sources.database)
                    .read(video.item.identity))
                .position,
            Duration.zero,
          );
          expect(
            (await home.recommendationCandidates(source.id))
                .single
                .entry
                .progress,
            0,
          );
          expect(
            (await EmbyLibraryRepository(sources).snapshot(source.id))
                .entries
                .single
                .progress,
            0,
          );
          final expectedFailure =
              mode == RemoteTraceSyncMode.bidirectional && failed;
          expect(
            find.textContaining('本机播放记录已清除'),
            expectedFailure ? findsOneWidget : findsNothing,
          );
          if (expectedFailure) {
            expect(find.textContaining('后续同步可能恢复服务器记录'), findsOneWidget);
          }
          final uploads = server.requests.where(
            (r) => r.uri.path.contains('/PlayedItems/'),
          );
          expect(uploads.isNotEmpty, mode == RemoteTraceSyncMode.bidirectional);
          // A second clear with the stale percentage must not restore the card.
          await tester.runAsync(() async {
            await tester.tap(find.text('清除记录'));
            await action;
          });
          await tester.pump();
          expect(
            (await home.recommendationCandidates(source.id))
                .single
                .entry
                .progress,
            0,
          );
          await tester.pumpWidget(const SizedBox());
        },
        timeout: const Timeout(Duration(minutes: 1)),
      );
    }
  }
}
