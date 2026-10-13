import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/toolbox/device_state.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';
import '../../shared/widgets.dart';
import '../../shared/responsive_button.dart';
import 'device_info_card.dart';

final deviceInfoProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, id) => ref.watch(toolboxProvider).info(id),
);

class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(activeDeviceProvider);
    return PageContent(
      compact: true,
      children: [
        PageHeading(context.tx('工具', 'Tools'), compact: true),
        const DevicePicker(),
        if (device == null)
          const SelectDeviceNotice()
        else ...[
          const ToolboxGrid(),
          const SizedBox(height: 20),
          PageHeading(
            context.tx('设备信息', 'Device information'),
            compact: true,
            action: ToolButton(
              context.tx('刷新', 'Refresh'),
              icon: FLucideIcons.refreshCw,
              onPress: () => ref.invalidate(deviceInfoProvider(device.id)),
            ),
          ),
          ref
              .watch(deviceInfoProvider(device.id))
              .when(
                data: (value) => DeviceInfoCard(device: device, output: value),
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
      minWidth: 140,
      spacing: 10,
      maxColumns: MediaQuery.sizeOf(context).width < 600 ? 2 : 4,
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
          FButton(
            variant: .outline,
            style: .delta(
              contentStyle: .delta(
                padding: .value(.symmetric(horizontal: 14, vertical: 18)),
              ),
            ),
            mainAxisAlignment: .start,
            builder: responsiveButtonContent,
            prefix: Icon(icon, size: 22),
            onPress: device == null ? null : () => context.push(route),
            child: Text(title),
          ),
      ],
    );
  }
}
