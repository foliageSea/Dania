import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/toolbox/device_state.dart';
import '../core/toolbox/toolbox_client.dart';
import 'responsive_button.dart';
import 'widgets.dart';

extension ToolboxTranslation on BuildContext {
  String tx(String zh, String en) =>
      Localizations.localeOf(this).languageCode == 'zh' ? zh : en;
}

String toolError(BuildContext context, Object error) {
  if (error is ToolboxException && error.code == 'unsupported')
    return context.tx('此功能仅支持 Android', 'Android is required');
  return error.toString();
}

class ToolErrorNotice extends StatelessWidget {
  const ToolErrorNotice(this.error, {this.retry, super.key});
  final Object error;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FAlert(
          variant: .destructive,
          title: Text(context.tx('操作失败', 'Operation failed')),
          subtitle: Text(toolError(context, error)),
        ),
        if (retry != null) ...[
          const SizedBox(height: 8),
          FButton(
            variant: .outline,
            onPress: retry,
            child: Text(context.tx('重试', 'Retry')),
          ),
        ],
      ],
    ),
  );
}

class DevicePicker extends ConsumerWidget {
  const DevicePicker({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final selected = ref.watch(activeDeviceProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: devices.when(
        data: (items) => items.isEmpty
            ? FButton(
                variant: .outline,
                onPress: () => context.go('/devices'),
                prefix: const Icon(FLucideIcons.plug),
                child: Text(context.tx('连接设备', 'Connect device')),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final device in items)
                    FButton(
                      mainAxisSize: .min,
                      builder: responsiveButtonContent,
                      variant: selected?.id == device.id ? .primary : .outline,
                      prefix: Icon(
                        device.local
                            ? FLucideIcons.smartphone
                            : FLucideIcons.wifi,
                      ),
                      onPress: () => ref
                          .read(selectedDeviceProvider.notifier)
                          .select(device.id),
                      child: Text(device.name),
                    ),
                  FButton.icon(
                    variant: .ghost,
                    semanticsLabel: context.tx('设备', 'Devices'),
                    onPress: () => context.go('/devices'),
                    child: const Icon(FLucideIcons.plus),
                  ),
                ],
              ),
        error: (error, _) => ToolErrorNotice(
          error,
          retry: () => ref.invalidate(devicesProvider),
        ),
        loading: () => const FCircularProgress(),
      ),
    );
  }
}

class SelectDeviceNotice extends StatelessWidget {
  const SelectDeviceNotice({super.key});
  @override
  Widget build(BuildContext context) =>
      EmptyNotice(context.tx('选择设备', 'Select a device'));
}

class ToolButton extends StatelessWidget {
  const ToolButton(
    this.label, {
    required this.onPress,
    this.icon,
    this.destructive = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPress;
  final IconData? icon;
  final bool destructive;
  @override
  Widget build(BuildContext context) => FButton(
    mainAxisSize: .min,
    builder: responsiveButtonContent,
    variant: destructive ? .destructive : .outline,
    onPress: onPress,
    prefix: icon == null ? null : Icon(icon, size: 16),
    child: Text(label),
  );
}

class ToolInput extends StatelessWidget {
  const ToolInput({
    required this.label,
    required this.controller,
    this.hint,
    this.enabled = true,
    this.numeric = false,
    this.secret = false,
    this.onSubmit,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool enabled;
  final bool numeric;
  final bool secret;
  final ValueChanged<String>? onSubmit;
  @override
  Widget build(BuildContext context) => FTextField(
    label: Text(label),
    hint: hint,
    control: .managed(controller: controller),
    enabled: enabled,
    obscureText: secret,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    onSubmit: onSubmit,
  );
}

Future<bool> confirmToolAction(
  BuildContext context,
  String title,
  String target,
) async =>
    await showFDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (_, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              Text(title, style: context.theme.typography.body.lg),
              const SizedBox(height: 12),
              Text(target),
              const SizedBox(height: 24),
              FButton(
                variant: .destructive,
                onPress: () => Navigator.pop(context, true),
                child: Text(context.tx('确认', 'Confirm')),
              ),
              const SizedBox(height: 8),
              FButton(
                variant: .outline,
                onPress: () => Navigator.pop(context, false),
                child: Text(context.tx('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;

Future<String?> promptToolInput(
  BuildContext context,
  String label, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showFDialog<String>(
      context: context,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (_, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              ToolInput(label: label, controller: controller),
              const SizedBox(height: 24),
              FButton(
                onPress: () => Navigator.pop(context, controller.text.trim()),
                child: Text(context.tx('确认', 'Confirm')),
              ),
              const SizedBox(height: 8),
              FButton(
                variant: .outline,
                onPress: () => Navigator.pop(context),
                child: Text(context.tx('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    // Dialog reverse animation may retain the field until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}
