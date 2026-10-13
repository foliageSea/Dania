import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/toolbox/device_information.dart';
import '../../core/toolbox/models.dart';
import '../../shared/toolbox_widgets.dart';
import '../../shared/widgets.dart';

class DeviceInfoCard extends StatefulWidget {
  const DeviceInfoCard({required this.device, required this.output, super.key});

  final Device device;
  final String output;

  @override
  State<DeviceInfoCard> createState() => _DeviceInfoCardState();
}

class _DeviceInfoCardState extends State<DeviceInfoCard> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final info = DeviceInformation.parse(widget.output);
    final status = switch (info.batteryStatus) {
      2 => context.tx('充电中', 'Charging'),
      3 => context.tx('放电中', 'Discharging'),
      4 => context.tx('未充电', 'Not charging'),
      5 => context.tx('已充满', 'Full'),
      _ => '—',
    };
    final identity = info.uid == null
        ? null
        : '${info.user ?? (info.uid == '0' ? 'root' : 'UID')} (${info.uid})';
    return Surface(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdaptiveGrid(
            minWidth: 260,
            spacing: 20,
            children: [
              _InfoGroup(
                title: context.tx('设备与系统', 'Device & system'),
                icon: FLucideIcons.smartphone,
                fields: [
                  (context.tx('型号', 'Model'), info.model ?? widget.device.name),
                  (context.tx('厂商', 'Manufacturer'), info.manufacturer),
                  (
                    context.tx('系统版本', 'System'),
                    info.androidVersion == null
                        ? null
                        : 'Android ${info.androidVersion}',
                  ),
                  ('API', info.sdkVersion),
                  (
                    context.tx('连接方式', 'Connection'),
                    widget.device.local
                        ? 'Shizuku'
                        : context.tx('无线 ADB', 'Wireless ADB'),
                  ),
                  (context.tx('地址', 'Address'), widget.device.address),
                  (context.tx('执行身份', 'Identity'), identity),
                ],
              ),
              _InfoGroup(
                title: context.tx('屏幕与电池', 'Display & battery'),
                icon: FLucideIcons.battery,
                fields: [
                  (
                    context.tx('分辨率', 'Resolution'),
                    _resolution(info.physicalSize),
                  ),
                  if (info.overrideSize != null)
                    (
                      context.tx('覆盖分辨率', 'Override size'),
                      _resolution(info.overrideSize),
                    ),
                  (
                    context.tx('电量', 'Battery'),
                    info.batteryPercent == null
                        ? null
                        : '${info.batteryPercent}%',
                  ),
                  (context.tx('状态', 'Status'), status),
                  (
                    context.tx('供电', 'Power source'),
                    info.powerSources.isEmpty
                        ? null
                        : info.powerSources
                              .map(
                                (source) => switch (source) {
                                  'AC' => context.tx('交流电', 'AC'),
                                  'Wireless' => context.tx('无线充电', 'Wireless'),
                                  'Dock' => context.tx('底座', 'Dock'),
                                  _ => source,
                                },
                              )
                              .join(' · '),
                  ),
                  (
                    context.tx('温度', 'Temperature'),
                    info.batteryTemperature == null
                        ? null
                        : '${info.batteryTemperature!.toStringAsFixed(1)} °C',
                  ),
                  (
                    context.tx('电压', 'Voltage'),
                    info.batteryVoltage == null
                        ? null
                        : '${info.batteryVoltage!.toStringAsFixed(2)} V',
                  ),
                  (context.tx('电池类型', 'Technology'), info.batteryTechnology),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ToolButton(
                context.tx('复制原始信息', 'Copy raw information'),
                icon: FLucideIcons.copy,
                onPress: () => copySource(context, widget.output),
              ),
              ToolButton(
                _showRaw
                    ? context.tx('收起原始信息', 'Hide raw information')
                    : context.tx('原始信息', 'Raw information'),
                onPress: () => setState(() => _showRaw = !_showRaw),
              ),
            ],
          ),
          if (_showRaw) ...[
            const SizedBox(height: 12),
            SelectableText(
              widget.output,
              style: context.theme.typography.body.sm.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _resolution(String? value) => value?.replaceAll('x', ' × ');
}

class _InfoGroup extends StatelessWidget {
  const _InfoGroup({
    required this.title,
    required this.icon,
    required this.fields,
  });

  final String title;
  final IconData icon;
  final List<(String, String?)> fields;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: context.theme.typography.body.md.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final (label, value) in fields)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: Text(
                  label,
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  value ?? '—',
                  style: context.theme.typography.body.sm,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
