import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show SelectableText;

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
      padding: const EdgeInsets.only(bottom: 12),
      child: devices.when(
        data: (items) => items.isEmpty
            ? FButton(
                size: .sm,
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
                      size: .sm,
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
                    size: .sm,
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

class ToolPage extends StatelessWidget {
  const ToolPage({
    required this.title,
    required this.children,
    this.actions,
    this.expandedChild,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final Widget? actions;
  final Widget? expandedChild;

  @override
  Widget build(BuildContext context) => PageSafeArea(
    child: FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(title),
        prefixes: [
          FHeaderAction.back(
            onPress: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/tools');
              }
            },
          ),
        ],
      ),
      child: PageContent(
        compact: true,
        expandedChild: expandedChild,
        children: [
          if (actions != null)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: actions),
          ...children,
        ],
      ),
    ),
  );
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
    size: .sm,
    mainAxisSize: .min,
    builder: responsiveButtonContent,
    variant: destructive ? .destructive : .outline,
    onPress: onPress,
    prefix: icon == null ? null : Icon(icon, size: 16),
    child: Text(label),
  );
}

class ToolControls extends StatelessWidget {
  const ToolControls({
    required this.content,
    required this.actions,
    this.breakpoint = 760,
    super.key,
  });

  final Widget content;
  final Widget actions;
  final double breakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= breakpoint
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: content),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .55,
                ),
                child: actions,
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [content, const SizedBox(height: 10), actions],
          ),
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

Future<void> showToolDetails(
  BuildContext context,
  String title,
  String content,
) => showFDialog<void>(
  context: context,
  useSafeArea: true,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (_, _) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text(title, style: context.theme.typography.body.lg),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: context.theme.typography.body.sm.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FButton(
            variant: .outline,
            onPress: () => Navigator.pop(context),
            child: Text(context.tx('关闭', 'Close')),
          ),
        ],
      ),
    ),
  ),
);

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
