import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/toolbox/device_state.dart';
import '../../core/toolbox/file_staging.dart';
import '../../core/toolbox/models.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';
import '../../shared/transfer_progress.dart';
import '../../shared/widgets.dart';

final filesProvider = FutureProvider.autoDispose
    .family<List<RemoteFile>, (String, String)>(
      (ref, target) => ref.watch(toolboxProvider).files(target.$1, target.$2),
    );

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});
  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  String _directory = '/sdcard';
  bool _busy = false;
  Object? _error;
  String? _operation;
  int _done = 0;
  int? _total;
  String? _downloadPath;
  String? _downloadName;
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

  void _navigate(String path) {
    if (_busy) return;
    setState(() {
      _directory = path;
      _error = null;
    });
  }

  Widget _breadcrumb() {
    final parts = _directory
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    String pathAt(int count) => '/${parts.take(count).join('/')}';
    VoidCallback? press(int count) =>
        _busy || count == parts.length ? null : () => _navigate(pathAt(count));
    final collapsedCount = parts.length > 3 ? parts.length - 2 : 0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: FBreadcrumb(
        children: [
          FBreadcrumbItem(
            current: parts.isEmpty,
            onPress: press(0),
            child: const Text('/'),
          ),
          if (collapsedCount > 0)
            FBreadcrumbItem.collapsed(
              key: ValueKey(_directory),
              menu: [
                FItemGroup(
                  children: [
                    for (var i = 0; i < collapsedCount; i++)
                      FItem(
                        title: Text(parts[i]),
                        onPress: _busy ? null : () => _navigate(pathAt(i + 1)),
                      ),
                  ],
                ),
              ],
            ),
          for (var i = collapsedCount; i < parts.length; i++)
            FBreadcrumbItem(
              current: i == parts.length - 1,
              onPress: press(i + 1),
              child: Text(parts[i]),
            ),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _operation = null;
        });
    }
  }

  Future<void> _newDirectory() async {
    final device = ref.read(activeDeviceProvider);
    if (device == null) return;
    final directory = _directory;
    final name = await promptToolInput(
      context,
      context.tx('目录名称', 'Directory name'),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _run(() async {
      await _client.fileAction(
        device.id,
        joinRemotePath(directory, name),
        'mkdir',
      );
      if (mounted) ref.invalidate(filesProvider((device.id, directory)));
    });
  }

  Future<void> _fileAction(RemoteFile file, String action) async {
    final device = ref.read(activeDeviceProvider);
    if (device == null || _busy) return;
    final directory = _directory;
    final path = joinRemotePath(directory, file.name);
    String? destination;
    if (action == 'rename') {
      final name = await promptToolInput(
        context,
        context.tx('新名称', 'New name'),
        initial: file.name,
      );
      if (name == null || name.isEmpty || name == file.name || !mounted) return;
      try {
        destination = joinRemotePath(directory, name);
      } catch (error) {
        setState(() => _error = error);
        return;
      }
    }
    if (action == 'delete') {
      if (!await confirmToolAction(
        context,
        context.tx('删除文件', 'Delete file'),
        '${device.name}\n$path',
      ))
        return;
    }
    if (!mounted) return;
    await _run(() async {
      await _client.fileAction(
        device.id,
        path,
        action,
        destination: destination,
      );
      if (mounted) ref.invalidate(filesProvider((device.id, directory)));
    });
  }

  Future<void> _upload() async {
    final device = ref.read(activeDeviceProvider);
    if (device == null || _busy) return;
    final directory = _directory;
    final selected = await openFile();
    if (selected == null || !mounted) return;
    String path;
    try {
      path = joinRemotePath(directory, selected.name);
    } catch (error) {
      setState(() => _error = error);
      return;
    }
    final entries = ref
        .read(filesProvider((device.id, directory)))
        .asData
        ?.value;
    if (entries == null) {
      setState(
        () => _error = ToolboxException(
          'unavailable',
          context.tx('请先刷新目录', 'Refresh the directory first'),
        ),
      );
      return;
    }
    if (entries.any((file) => file.name == selected.name)) {
      if (!await confirmToolAction(
        context,
        context.tx('覆盖文件', 'Overwrite file'),
        '${device.name}\n$path',
      ))
        return;
    }
    if (!mounted) return;
    await _run(() async {
      final id = newOperationId();
      setState(() {
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
        await _client.upload(device.id, id, staged.path, path);
        if (mounted) {
          notifyUser(context, context.tx('上传完成', 'Uploaded'));
          ref.invalidate(filesProvider((device.id, directory)));
        }
      } finally {
        if (staged != null)
          await staged.delete().catchError((Object _) => staged!);
      }
    });
  }

  Future<void> _download(RemoteFile file) async {
    final device = ref.read(activeDeviceProvider);
    if (device == null || _busy) return;
    final path = joinRemotePath(_directory, file.name);
    await _run(() async {
      final id = newOperationId();
      setState(() {
        _operation = id;
        _done = 0;
        _total = file.size;
      });
      final downloaded = await _client.download(device.id, id, path);
      if (!mounted) return;
      setState(() {
        _operation = null;
        _downloadPath = downloaded;
        _downloadName = file.name;
      });
      final saved = await _client.exportFile(downloaded, file.name);
      if (mounted && saved) {
        setState(() {
          _downloadPath = null;
          _downloadName = null;
        });
        notifyUser(context, context.tx('已保存', 'Saved'));
      }
    });
  }

  Future<void> _cancel() async {
    final id = _operation;
    if (id == null) return;
    try {
      await _client.cancel(id);
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
    final entries = device == null
        ? null
        : ref.watch(filesProvider((device.id, _directory)));
    return ToolPage(
      title: context.tx('文件管理', 'Files'),
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
                    : () => ref.invalidate(
                        filesProvider((device.id, _directory)),
                      ),
              ),
              ToolButton(
                context.tx('新建目录', 'New directory'),
                icon: FLucideIcons.folderPlus,
                onPress: device == null || _busy ? null : _newDirectory,
              ),
              ToolButton(
                context.tx('上传', 'Upload'),
                icon: FLucideIcons.upload,
                onPress: device == null || _busy ? null : _upload,
              ),
            ],
          ),
        ),
        if (_error != null) ToolErrorNotice(_error!),
        if (_operation != null)
          TransferProgress(done: _done, total: _total, cancel: _cancel),
        if (_downloadPath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Surface(
              padding: 16,
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(_downloadName!),
                  const SizedBox(height: 8),
                  ToolButton(
                    context.tx('另存为', 'Save as'),
                    onPress: _busy
                        ? null
                        : () => _run(() async {
                            if (await _client.exportFile(
                                  _downloadPath!,
                                  _downloadName!,
                                ) &&
                                mounted) {
                              setState(() {
                                _downloadPath = null;
                                _downloadName = null;
                              });
                              notifyUser(context, context.tx('已保存', 'Saved'));
                            }
                          }),
                  ),
                ],
              ),
            ),
          ),
        if (device == null)
          const SelectDeviceNotice()
        else ...[
          Row(
            children: [
              Expanded(child: _breadcrumb()),
              const SizedBox(width: 8),
              FPopoverMenu(
                menuAnchor: .topRight,
                childAnchor: .bottomRight,
                menuBuilder: (context, controller, _) => [
                  FItemGroup(
                    children: [
                      for (final path in const ['/sdcard', '/data/local/tmp'])
                        FItem(
                          title: Text(path),
                          onPress: () async {
                            await controller.hide();
                            _navigate(path);
                          },
                        ),
                    ],
                  ),
                ],
                builder: (context, controller, _) => ToolButton(
                  context.tx('快捷路径', 'Shortcuts'),
                  icon: FLucideIcons.bookmark,
                  onPress: _busy ? null : controller.toggle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
      expandedChild: device == null
          ? null
          : entries!.when(
              data: (items) {
                final sorted = [...items]
                  ..sort(
                    (a, b) => a.directory != b.directory
                        ? (a.directory ? -1 : 1)
                        : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
                return sorted.isEmpty
                    ? SingleChildScrollView(
                        child: EmptyNotice(
                          context.tx('空目录', 'Empty directory'),
                        ),
                      )
                    : ListView.builder(
                        key: ValueKey((device.id, _directory)),
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          final file = sorted[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Surface(
                              padding: 12,
                              child: ToolControls(
                                content: Row(
                                  children: [
                                    Icon(
                                      file.directory
                                          ? FLucideIcons.folder
                                          : file.symbolicLink
                                          ? FLucideIcons.link
                                          : FLucideIcons.file,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: .start,
                                        children: [
                                          Text(file.name),
                                          if (!file.directory)
                                            Text(
                                              formatBytes(file.size),
                                              style: context
                                                  .theme
                                                  .typography
                                                  .body
                                                  .sm,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                actions: Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (file.directory)
                                      ToolButton(
                                        context.tx('打开', 'Open'),
                                        onPress: _busy
                                            ? null
                                            : () => _navigate(
                                                joinRemotePath(
                                                  _directory,
                                                  file.name,
                                                ),
                                              ),
                                      ),
                                    if (!file.directory && !file.symbolicLink)
                                      ToolButton(
                                        context.tx('下载', 'Download'),
                                        onPress: _busy
                                            ? null
                                            : () => _download(file),
                                      ),
                                    ToolButton(
                                      context.tx('重命名', 'Rename'),
                                      onPress: _busy
                                          ? null
                                          : () => _fileAction(file, 'rename'),
                                    ),
                                    ToolButton(
                                      context.tx('删除', 'Delete'),
                                      destructive: true,
                                      onPress: _busy
                                          ? null
                                          : () => _fileAction(file, 'delete'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
              },
              error: (error, _) => SingleChildScrollView(
                child: ToolErrorNotice(
                  error,
                  retry: () =>
                      ref.invalidate(filesProvider((device.id, _directory))),
                ),
              ),
              loading: () =>
                  const SingleChildScrollView(child: LoadingNotice()),
            ),
    );
  }
}
