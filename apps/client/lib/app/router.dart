import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/library/presentation/browse_page.dart';
import '../features/library/presentation/media_detail_page.dart';
import '../features/servers/presentation/servers_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../shell/app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
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
                path: '/servers',
                builder: (context, state) => const ServersPage(),
                routes: [
                  GoRoute(
                    path: 'library',
                    builder: (context, state) => const LibraryPage(),
                    routes: [
                      GoRoute(
                        name: 'media-browse', path: 'category/:type',
                        builder: (context, state) => BrowsePage(
                          key: state.pageKey, type: state.pathParameters['type']!),
                        routes: [
                          GoRoute(name: 'media-detail', path: 'item/:id',
                            builder: (context, state) => MediaDetailPage(
                              key: state.pageKey,
                              type: state.pathParameters['type']!,
                              id: state.pathParameters['id']!,
                              isSeries: state.uri.queryParameters['series'] == '1',
                            )),
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
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
