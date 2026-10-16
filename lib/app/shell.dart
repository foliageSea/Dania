import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/toolbox/device_state.dart';
import '../shared/toolbox_widgets.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(toolboxEventsProvider);
    final labels = [
      context.tx('概览', 'Overview'),
      context.tx('设备', 'Devices'),
      context.tx('工具', 'Tools'),
      context.tx('设置', 'Settings'),
    ];
    const icons = [
      FLucideIcons.house,
      FLucideIcons.smartphone,
      FLucideIcons.wrench,
      FLucideIcons.settings2,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 600;
        final compact = constraints.maxWidth < 1024;
        return ColoredBox(
          color: context.theme.colors.background,
          child: SafeArea(
            child: Row(
              children: [
                if (!mobile)
                  SizedBox(
                    width: compact ? 76 : 224,
                    child: FSidebar(
                      header: Padding(
                        padding: const EdgeInsets.all(24),
                        child: compact
                            ? const Icon(FLucideIcons.command)
                            : Text(
                                'DANIA',
                                style: context.theme.typography.display.md
                                    .copyWith(letterSpacing: 3),
                              ),
                      ),
                      children: [
                        FSidebarGroup(
                          children: [
                            for (var i = 0; i < labels.length; i++)
                              FSidebarItem(
                                icon: Icon(icons[i]),
                                label: compact ? null : Text(labels[i]),
                                selected: shell.currentIndex == i,
                                onPress: () => shell.goBranch(i),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: FScaffold(
                    childPad: false,
                    header: mobile
                        ? FHeader(
                            title: Text(
                              shell.currentIndex == 0
                                  ? 'Dania'
                                  : labels[shell.currentIndex],
                            ),
                          )
                        : null,
                    footer: mobile
                        ? FBottomNavigationBar(
                            index: shell.currentIndex,
                            onChange: shell.goBranch,
                            children: [
                              for (var i = 0; i < labels.length; i++)
                                FBottomNavigationBarItem(
                                  icon: Icon(icons[i]),
                                  label: Text(labels[i]),
                                ),
                            ],
                          )
                        : null,
                    child: shell,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
