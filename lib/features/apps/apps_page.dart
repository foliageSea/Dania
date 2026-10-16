import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/toolbox/device_state.dart';
import '../../core/toolbox/file_staging.dart';
import '../../core/toolbox/models.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';
import '../../shared/transfer_progress.dart';
import '../../shared/widgets.dart';

final appsProvider = FutureProvider.autoDispose
    .family<List<InstalledApp>, String>(
      (ref, id) => ref.watch(toolboxProvider).apps(id),
    );

class AppsPage extends ConsumerStatefulWidget {
  const AppsPage({super.key});
  @override
  ConsumerState<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends ConsumerState<AppsPage> {
  String _search = '';
  int _filter = 0;
  bool _busy = false;
  Object? _error;
  String? _operation;
  int _done = 0;
  int? _total;
  late final ToolboxClient _client;
  StreamSubscription<Map<Object?, Object?>>? _events;

  @override
  void initState() {
    super.initState();
    _client = ref.read(toolboxProvider);
    _events = _client.events.listen((event) {
      if (mounted && event['type'] == 'transfer' && event['id'] == _operation) {
        setState(() => _done = (event['done']! as num).toInt());
      }
    }, onError: (Object _) {});
  }

  Future<void> _action(InstalledApp app, String action) async {
    final device = ref.read(activeDeviceProvider);
    if (device == null || _busy) return;
    final title = switch (action) {
      'disable' => context.tx('停用应用', 'Disable application'),
      'uninstall' => context.tx('卸载应用', 'Uninstall application'),
      'stop' => context.tx('强制停止', 'Force stop'),
      'grant' => context.tx('授予权限', 'Grant permission'),
      'revoke' => context.tx('撤销权限', 'Revoke permission'),
      _ => context.tx('启用应用', 'Enable application'),
    };
    String? permission;
    if (action == 'grant' || action == 'revoke') {
      permission = await promptToolInput(
        context,
        context.tx('权限名称', 'Permission name'),
        initial: 'android.permission.',
      );
      if (permission == null || permission.isEmpty || !mounted) return;
    }
    if (action != 'details' && action != 'enable') {
      if (!mounted) return;
      if (!await confirmToolAction(
        context,
        title,
        '${device.name}\n${app.packageName}${permission == null ? '' : '\n$permission'}',
      ))
        return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _client.appAction(
        device.id,
        app.packageName,
        action,
        permission: permission,
      );
      if (mounted) {
        if (action == 'details') {
          setState(() => _busy = false);
          await showToolDetails(context, app.packageName, result);
        } else {
          notifyUser(context, context.tx('操作完成', 'Completed'));
          ref.invalidate(appsProvider(device.id));
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install() async {
    final device = ref.read(activeDeviceProvider);
    if (device == null || _busy) return;
    final selected = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'APK',
          extensions: ['apk'],
          mimeTypes: ['application/vnd.android.package-archive'],
        ),
      ],
    );
    if (selected == null || !mounted) return;
    if (!await confirmToolAction(
      context,
      context.tx('安装 APK', 'Install APK'),
      '${device.name}\n${selected.name}',
    ))
      return;
    if (!mounted) return;
    final id = newOperationId();
    setState(() {
      _busy = true;
      _error = null;
      _operation = id;
      _done = 0;
      _total = null;
    });
    File? staged;
    try {
      staged = await stageSelectedFile(selected);
      if (!mounted) return;
      final length = await staged.length();
      if (mounted) setState(() => _total = length);
      await _client.install(device.id, id, staged.path);
      if (mounted) {
        notifyUser(context, context.tx('安装完成', 'Installed'));
        ref.invalidate(appsProvider(device.id));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (staged != null)
        await staged.delete().catchError((Object _) => staged!);
      if (mounted)
        setState(() {
          _busy = false;
          _operation = null;
        });
    }
  }

  Future<void> _cancel() async {
    if (_operation == null) return;
    try {
      await _client.cancel(_operation!);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    if (_operation != null)
      unawaited(_client.cancel(_operation!).catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(activeDeviceProvider);
    final apps = device == null ? null : ref.watch(appsProvider(device.id));
    return ToolPage(
      title: context.tx('应用管理', 'Applications'),
      children: [
        const DevicePicker(),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ToolButton(
                context.tx('刷新', 'Refresh'),
                icon: FLucideIcons.refreshCw,
                onPress: device == null || _busy
                    ? null
                    : () => ref.invalidate(appsProvider(device.id)),
              ),
              ToolButton(
                context.tx('安装 APK', 'Install APK'),
                icon: FLucideIcons.download,
                onPress: device == null || _busy ? null : _install,
              ),
            ],
          ),
        ),
        if (_error != null) ToolErrorNotice(_error!),
        if (_operation != null)
          TransferProgress(done: _done, total: _total, cancel: _cancel),
        if (_busy && _operation == null) const FProgress(),
        if (device == null)
          const SelectDeviceNotice()
        else ...[
          ToolControls(
            content: FTextField(
              label: Text(context.tx('搜索包名', 'Search package name')),
              control: .managed(
                onChange: (value) => setState(() => _search = value.text),
              ),
            ),
            actions: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, label) in [
                  context.tx('全部', 'All'),
                  context.tx('用户应用', 'User'),
                  context.tx('系统应用', 'System'),
                  context.tx('已停用', 'Disabled'),
                ].indexed)
                  FButton(
                    size: .sm,
                    mainAxisSize: .min,
                    variant: _filter == index ? .primary : .outline,
                    onPress: () => setState(() => _filter = index),
                    child: Text(label),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          apps!.when(
            data: (items) {
              final query = _search.trim().toLowerCase();
              final filtered =
                  items
                      .where(
                        (app) =>
                            app.packageName.toLowerCase().contains(query) &&
                            switch (_filter) {
                              1 => !app.system,
                              2 => app.system,
                              3 => !app.enabled,
                              _ => true,
                            },
                      )
                      .toList()
                    ..sort((a, b) => a.packageName.compareTo(b.packageName));
              return filtered.isEmpty
                  ? EmptyNotice(
                      context.tx('没有匹配应用', 'No matching applications'),
                    )
                  : Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        Text(
                          '${filtered.length} ${context.tx('个应用', 'applications')}',
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          // Keep the outer page scrollable while letting the app list
                          // use a real viewport. ListView.builder then creates only
                          // the cards currently near the viewport.
                          height: (MediaQuery.sizeOf(context).height * .72)
                              .clamp(420.0, 720.0)
                              .toDouble(),
                          child: ListView.builder(
                            itemCount: filtered.length,
                            padding: const EdgeInsets.only(bottom: 8),
                            itemBuilder: (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _AppCard(
                                app: filtered[index],
                                busy: _busy,
                                onAction: _action,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
            },
            error: (error, _) => ToolErrorNotice(
              error,
              retry: () => ref.invalidate(appsProvider(device.id)),
            ),
            loading: () => const LoadingNotice(),
          ),
        ],
      ],
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.busy,
    required this.onAction,
  });
  final InstalledApp app;
  final bool busy;
  final Future<void> Function(InstalledApp app, String action) onAction;

  @override
  Widget build(BuildContext context) => Surface(
    padding: 12,
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(app.packageName, style: context.theme.typography.body.md),
            FBadge(
              variant: .secondary,
              child: Text(
                app.system
                    ? context.tx('系统', 'System')
                    : context.tx('用户', 'User'),
              ),
            ),
            if (!app.enabled)
              FBadge(
                variant: .outline,
                child: Text(context.tx('已停用', 'Disabled')),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            ToolButton(
              context.tx('详情', 'Details'),
              onPress: busy ? null : () => onAction(app, 'details'),
            ),
            FPopoverMenu(
              menuAnchor: .topLeft,
              childAnchor: .bottomLeft,
              menuBuilder: (context, controller, _) => [
                FItemGroup(
                  children: [
                    for (final (label, action) in [
                      (
                        app.enabled
                            ? context.tx('停用', 'Disable')
                            : context.tx('启用', 'Enable'),
                        app.enabled ? 'disable' : 'enable',
                      ),
                      (context.tx('停止', 'Stop'), 'stop'),
                      (context.tx('授予权限', 'Grant'), 'grant'),
                      (context.tx('撤销权限', 'Revoke'), 'revoke'),
                      (context.tx('卸载', 'Uninstall'), 'uninstall'),
                    ])
                      FItem(
                        title: Text(label),
                        variant: action == 'uninstall'
                            ? .destructive
                            : .primary,
                        onPress: busy
                            ? null
                            : () async {
                                await controller.hide();
                                await onAction(app, action);
                              },
                      ),
                  ],
                ),
              ],
              builder: (context, controller, _) => ToolButton(
                context.tx('更多', 'More'),
                icon: FLucideIcons.ellipsis,
                onPress: busy ? null : controller.toggle,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
