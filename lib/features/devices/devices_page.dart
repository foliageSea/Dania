import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/toolbox/device_state.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';
import '../../shared/widgets.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});
  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController();
  final _pairPort = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _pairing = false;
  Object? _error;
  String? _feedback;

  @override
  void dispose() {
    for (final controller in [_host, _port, _pairPort, _code]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _readPort(TextEditingController field) {
    final value = int.tryParse(field.text.trim());
    if (value == null || value < 1 || value > 65535) {
      throw ToolboxException(
        'invalidInput',
        context.tx('端口必须为 1–65535', 'Port must be between 1 and 65535'),
      );
    }
    return value;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(shizukuProvider);
        await ref
            .read(devicesProvider.notifier)
            .refresh()
            .catchError((Object _) {});
      }
    }
  }

  Future<void> _connect(String host, int port) async {
    final id = await ref.read(toolboxProvider).connect(host, port);
    if (!mounted) return;
    ref.read(selectedDeviceProvider.notifier).select(id);
    setState(() => _feedback = context.tx('已连接', 'Connected'));
    try {
      await ref
          .read(endpointsProvider.notifier)
          .save(SavedEndpoint(host, port));
    } catch (error) {
      if (mounted) notifyUser(context, toolError(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(toolboxProvider);
    final status = ref.watch(shizukuProvider);
    final devices = ref.watch(devicesProvider);
    final selected = ref.watch(activeDeviceProvider);
    final endpoints = ref.watch(endpointsProvider).asData?.value ?? [];
    return PageContent(
      children: [
        PageHeading(
          context.tx('设备', 'Devices'),
          action: ToolButton(
            context.tx('刷新', 'Refresh'),
            icon: FLucideIcons.refreshCw,
            onPress: _busy
                ? null
                : () => _run(() async {
                    ref.invalidate(shizukuProvider);
                  }),
          ),
        ),
        if (_error != null) ToolErrorNotice(_error!),
        if (_feedback != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FAlert(title: Text(_feedback!)),
          ),
        AdaptiveGrid(
          minWidth: 360,
          children: [
            Surface(
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  Row(
                    children: [
                      const Icon(FLucideIcons.shieldCheck),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Shizuku',
                          style: context.theme.typography.body.lg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  status.when(
                    data: (value) => Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Text(
                          !value.supported
                              ? context.tx('仅支持 Android', 'Android only')
                              : !value.running
                              ? context.tx('未运行', 'Not running')
                              : !value.granted
                              ? context.tx('等待授权', 'Permission required')
                              : value.uid == 0
                              ? context.tx('已授权 · Root', 'Authorized · Root')
                              : context.tx('已授权 · Shell', 'Authorized · Shell'),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ToolButton(
                              context.tx('打开 Shizuku', 'Open Shizuku'),
                              onPress: _busy || !value.supported
                                  ? null
                                  : () => _run(client.openShizuku),
                            ),
                            if (value.running && !value.granted)
                              ToolButton(
                                context.tx('授权', 'Authorize'),
                                onPress: _busy
                                    ? null
                                    : () => _run(client.authorize),
                              ),
                            if (value.granted)
                              ToolButton(
                                context.tx('连接本机', 'Connect local'),
                                onPress: _busy
                                    ? null
                                    : () => _run(() async {
                                        final id = await client.connectLocal();
                                        if (mounted)
                                          ref
                                              .read(
                                                selectedDeviceProvider.notifier,
                                              )
                                              .select(id);
                                      }),
                              ),
                            ToolButton(
                              context.tx('下载', 'Download'),
                              onPress: () => openDocumentation(
                                context,
                                'https://shizuku.rikka.app/download/',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    error: (error, _) => ToolErrorNotice(error),
                    loading: () => const FCircularProgress(),
                  ),
                ],
              ),
            ),
            Surface(
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  Row(
                    children: [
                      const Icon(FLucideIcons.wifi),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tx('无线 ADB', 'Wireless ADB'),
                          style: context.theme.typography.body.lg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ToolInput(
                    label: context.tx('主机地址', 'Host address'),
                    controller: _host,
                    enabled: !_busy,
                    hint: '192.168.1.100',
                  ),
                  const SizedBox(height: 16),
                  ToolInput(
                    label: context.tx('连接端口', 'Connection port'),
                    controller: _port,
                    numeric: true,
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 16),
                  FSwitch(
                    label: Text(context.tx('使用配对码', 'Use pairing code')),
                    value: _pairing,
                    enabled: !_busy,
                    onChange: (value) => setState(() => _pairing = value),
                  ),
                  if (_pairing) ...[
                    const SizedBox(height: 16),
                    ToolInput(
                      label: context.tx('配对端口', 'Pairing port'),
                      controller: _pairPort,
                      numeric: true,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 16),
                    ToolInput(
                      label: context.tx('六位配对码', 'Six-digit pairing code'),
                      controller: _code,
                      numeric: true,
                      secret: true,
                      enabled: !_busy,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_pairing)
                        ToolButton(
                          context.tx('配对', 'Pair'),
                          onPress: _busy || !client.supported
                              ? null
                              : () => _run(() async {
                                  final code = _code.text.trim();
                                  if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                                    throw ToolboxException(
                                      'invalidInput',
                                      context.tx(
                                        '请输入六位配对码',
                                        'Enter a six-digit pairing code',
                                      ),
                                    );
                                  }
                                  try {
                                    await client.pair(
                                      _host.text.trim(),
                                      _readPort(_pairPort),
                                      code,
                                    );
                                    if (mounted)
                                      setState(
                                        () => _feedback = context.tx(
                                          '配对成功',
                                          'Paired',
                                        ),
                                      );
                                  } finally {
                                    _code.clear();
                                  }
                                }),
                        ),
                      ToolButton(
                        context.tx('连接', 'Connect'),
                        icon: FLucideIcons.plug,
                        onPress: _busy || !client.supported
                            ? null
                            : () => _run(
                                () => _connect(
                                  _host.text.trim(),
                                  _readPort(_port),
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (_busy) ...[const SizedBox(height: 16), const FProgress()],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          context.tx('已连接', 'Connected'),
          style: context.theme.typography.body.lg,
        ),
        const SizedBox(height: 12),
        devices.when(
          data: (items) => items.isEmpty
              ? EmptyNotice(context.tx('没有已连接设备', 'No connected devices'))
              : Column(
                  children: [
                    for (final device in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Surface(
                          padding: 16,
                          child: Column(
                            crossAxisAlignment: .stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    device.local
                                        ? FLucideIcons.smartphone
                                        : FLucideIcons.wifi,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: .start,
                                      children: [
                                        Text(device.name),
                                        Text(
                                          device.address,
                                          style: context
                                              .theme
                                              .typography
                                              .body
                                              .sm
                                              .copyWith(
                                                color: context
                                                    .theme
                                                    .colors
                                                    .mutedForeground,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected?.id == device.id)
                                    FBadge(
                                      child: Text(context.tx('当前', 'Active')),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ToolButton(
                                    context.tx('使用设备', 'Use device'),
                                    onPress: () {
                                      ref
                                          .read(selectedDeviceProvider.notifier)
                                          .select(device.id);
                                      context.go('/tools');
                                    },
                                  ),
                                  if (!device.local)
                                    ToolButton(
                                      context.tx('投屏', 'Mirror'),
                                      icon: FLucideIcons.monitor,
                                      onPress: () =>
                                          context.push('/mirror/${device.id}'),
                                    ),
                                  ToolButton(
                                    context.tx('断开', 'Disconnect'),
                                    onPress: _busy
                                        ? null
                                        : () => _run(
                                            () => client.disconnect(device.id),
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
          error: (error, _) => ToolErrorNotice(error),
          loading: () => const LoadingNotice(),
        ),
        if (endpoints.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(
            context.tx('最近连接', 'Recent connections'),
            style: context.theme.typography.body.lg,
          ),
          const SizedBox(height: 12),
          for (final endpoint in endpoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Surface(
                padding: 16,
                child: ToolControls(
                  breakpoint: 360,
                  content: Text(endpoint.address),
                  actions: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ToolButton(
                        context.tx('连接', 'Connect'),
                        onPress: _busy
                            ? null
                            : () => _run(
                                () => _connect(endpoint.host, endpoint.port),
                              ),
                      ),
                      ToolButton(
                        context.tx('移除', 'Remove'),
                        onPress: _busy
                            ? null
                            : () => _run(
                                () => ref
                                    .read(endpointsProvider.notifier)
                                    .remove(endpoint),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
