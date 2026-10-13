import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/toolbox/device_state.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';
import '../../shared/widgets.dart';

final deviceInfoProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, id) => ref.watch(toolboxProvider).info(id),
);

class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(activeDeviceProvider);
    return PageContent(
      children: [
        PageHeading(context.tx('工具', 'Tools')),
        const DevicePicker(),
        if (device == null)
          const SelectDeviceNotice()
        else ...[
          const ToolboxGrid(),
          const SizedBox(height: 28),
          PageHeading(
            context.tx('设备信息', 'Device information'),
            action: ToolButton(
              context.tx('刷新', 'Refresh'),
              icon: FLucideIcons.refreshCw,
              onPress: () => ref.invalidate(deviceInfoProvider(device.id)),
            ),
          ),
          ref
              .watch(deviceInfoProvider(device.id))
              .when(
                data: (value) => Surface(
                  child: SelectableText(
                    value,
                    style: context.theme.typography.body.sm.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                error: (error, _) => ToolErrorNotice(
                  error,
                  retry: () => ref.invalidate(deviceInfoProvider(device.id)),
                ),
                loading: () => const LoadingNotice(),
              ),
        ],
      ],
    );
  }
}

class ToolboxGrid extends ConsumerWidget {
  const ToolboxGrid({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(activeDeviceProvider);
    return AdaptiveGrid(
      minWidth: 200,
      children: [
        for (final (title, icon, route) in [
          (
            context.tx('终端', 'Terminal'),
            FLucideIcons.terminal,
            '/tools/terminal',
          ),
          (
            context.tx('应用管理', 'Applications'),
            FLucideIcons.package,
            '/tools/apps',
          ),
          (context.tx('文件管理', 'Files'), FLucideIcons.folder, '/tools/files'),
          if (device != null && !device.local)
            (
              context.tx('投屏控制', 'Screen control'),
              FLucideIcons.monitor,
              '/mirror/${device.id}',
            ),
        ])
          Surface(
            padding: 20,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Align(alignment: .centerLeft, child: Icon(icon, size: 28)),
                const SizedBox(height: 16),
                FButton(
                  variant: .outline,
                  onPress: device == null
                      ? null
                      : () {
                          if (route.startsWith('/mirror')) {
                            context.push(route);
                          } else {
                            context.go(route);
                          }
                        },
                  child: Text(title),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
