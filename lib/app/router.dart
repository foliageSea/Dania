import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/overview/overview_page.dart';
import '../features/devices/devices_page.dart';
import '../features/tools/tools_page.dart';
import '../features/terminal/terminal_page.dart';
import '../features/apps/apps_page.dart';
import '../features/files/files_page.dart';
import '../features/mirror/mirror_page.dart';
import '../features/settings/settings_page.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/overview',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/overview',
                builder: (_, _) => const OverviewPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/devices', builder: (_, _) => const DevicesPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tools',
                builder: (_, _) => const ToolsPage(),
                routes: [
                  GoRoute(
                    path: 'terminal',
                    builder: (_, _) => const TerminalPage(),
                  ),
                  GoRoute(path: 'apps', builder: (_, _) => const AppsPage()),
                  GoRoute(path: 'files', builder: (_, _) => const FilesPage()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/mirror/:id',
        builder: (_, state) =>
            MirrorPage(deviceId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
