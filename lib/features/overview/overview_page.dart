import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/toolbox/device_state.dart';
import '../../shared/toolbox_widgets.dart';
import '../../shared/widgets.dart';
import '../tools/tools_page.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final status = ref.watch(shizukuProvider);
    final active = ref.watch(activeDeviceProvider);
    return PageContent(
      children: [
        const PageHeading('Dania'),
        AdaptiveGrid(
          children: [
            Surface(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    context.tx('已连接设备', 'Connected devices'),
                    style: context.theme.typography.body.sm,
                  ),
                  const SizedBox(height: 12),
                  devices.when(
                    data: (items) => Text(
                      '${items.length}',
                      style: context.theme.typography.display.lg,
                    ),
                    error: (error, _) => ToolErrorNotice(error),
                    loading: () => const FCircularProgress(),
                  ),
                  const SizedBox(height: 16),
                  ToolButton(
                    context.tx('管理设备', 'Manage devices'),
                    icon: FLucideIcons.plug,
                    onPress: () => context.go('/devices'),
                  ),
                ],
              ),
            ),
            Surface(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  const Text('Shizuku'),
                  const SizedBox(height: 12),
                  status.when(
                    data: (value) => Text(
                      !value.supported
                          ? context.tx('仅支持 Android', 'Android only')
                          : value.granted
                          ? context.tx('已授权', 'Authorized')
                          : value.running
                          ? context.tx('等待授权', 'Permission required')
                          : context.tx('未运行', 'Not running'),
                      style: context.theme.typography.body.lg,
                    ),
                    error: (error, _) => ToolErrorNotice(error),
                    loading: () => const FCircularProgress(),
                  ),
                  const SizedBox(height: 16),
                  ToolButton(
                    context.tx('授权管理', 'Authorization'),
                    icon: FLucideIcons.shieldCheck,
                    onPress: () => context.go('/devices'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        PageHeading(context.tx('当前设备', 'Active device')),
        const DevicePicker(),
        if (active != null)
          Surface(
            padding: 16,
            child: Row(
              children: [
                Icon(
                  active.local ? FLucideIcons.smartphone : FLucideIcons.wifi,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(active.name),
                      Text(
                        active.address,
                        style: context.theme.typography.body.sm,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        PageHeading(context.tx('常用工具', 'Quick tools')),
        const ToolboxGrid(),
      ],
    );
  }
}
