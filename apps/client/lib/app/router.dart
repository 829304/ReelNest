import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_page.dart';
import '../features/health/presentation/library_health_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/library/presentation/browse_page.dart';
import '../features/library/presentation/media_detail_page.dart';
import '../features/servers/presentation/servers_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/sources/presentation/sources_page.dart';
import '../features/sources/presentation/source_library_page.dart';
import '../features/sources/presentation/local_media_detail_page.dart';
import '../shell/app_shell.dart';
import '../features/sources/presentation/emby_task_center.dart';
import '../features/sources/domain/emby_library.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(router.dispose);
  return router;
});

// Legacy routes exist only for regression tests of the isolated Mlink prototype.
GoRouter createRouter({
  bool enableLegacyMlink = false,
  String initialLocation = '/',
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomePage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/sources',
              builder: (context, state) => const SourcesPage(),
              routes: [
                GoRoute(
                  path: ':sourceId',
                  builder: (context, state) => SourceLibraryPage(
                    key: state.pageKey,
                    sourceId: state.pathParameters['sourceId']!,
                    libraryId: state.uri.queryParameters['library'],
                    section:
                        EmbyVideoSection.values
                            .where(
                              (s) =>
                                  s.name ==
                                  state.uri.queryParameters['section'],
                            )
                            .firstOrNull ??
                        EmbyVideoSection.videos,
                  ),
                  routes: [
                    GoRoute(
                      name: 'local-media-detail',
                      path: 'media/:mediaKey',
                      builder: (context, state) {
                        try {
                          final localId = utf8.decode(
                            base64Url.decode(
                              base64Url.normalize(
                                state.pathParameters['mediaKey']!,
                              ),
                            ),
                          );
                          return LocalMediaDetailPage(
                            key: state.pageKey,
                            identity: (
                              sourceId: state.pathParameters['sourceId']!,
                              localId: localId,
                            ),
                          );
                        } on FormatException {
                          return const Center(child: Text('媒体地址无效。'));
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            if (enableLegacyMlink)
              GoRoute(
                path: '/servers',
                builder: (context, state) => const ServersPage(),
                routes: [
                  GoRoute(
                    path: 'library',
                    builder: (context, state) => const LibraryPage(),
                    routes: [
                      GoRoute(
                        name: 'media-browse',
                        path: 'category/:type',
                        builder: (context, state) => BrowsePage(
                          key: state.pageKey,
                          type: state.pathParameters['type']!,
                        ),
                        routes: [
                          GoRoute(
                            name: 'media-detail',
                            path: 'item/:id',
                            builder: (context, state) => MediaDetailPage(
                              key: state.pageKey,
                              type: state.pathParameters['type']!,
                              id: state.pathParameters['id']!,
                              isSeries:
                                  state.uri.queryParameters['series'] == '1',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/health',
              builder: (context, state) => const LibraryHealthPage(),
              routes: [
                GoRoute(
                  path: 'tasks',
                  builder: (context, state) => const EmbyTaskCenterPage(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
