import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/toolbox/device_state.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';
import '../../shared/widgets.dart';

final commandHistoryProvider = NotifierProvider<CommandHistory, List<String>>(
  CommandHistory.new,
);

class CommandHistory extends Notifier<List<String>> {
  @override
  List<String> build() => [];
  void add(String value) => state = [
    value,
    ...state.where((item) => item != value),
  ].take(30).toList();
}

class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});
  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage> {
  final _command = TextEditingController();
  final _scroll = ScrollController();
  late final ToolboxClient _client;
  StreamSubscription<Map<Object?, Object?>>? _subscription;
  final Map<bool, StreamController<List<int>>> _decoders = {};
  Timer? _refresh;
  String _output = '';
  String? _operation;
  Object? _error;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _client = ref.read(toolboxProvider);
    _subscription = _client.events.listen(
      _onEvent,
      onError: (Object error) {
        if (mounted)
          setState(() {
            _error = error;
            _operation = null;
          });
      },
    );
  }

  void _append(String value) {
    _output += value;
    if (_output.length > 128 * 1024) {
      _output = _output.substring(_output.length - 128 * 1024);
    }
    _refresh ??= Timer(const Duration(milliseconds: 80), () {
      _refresh = null;
      if (!mounted) return;
      setState(() {});
      if (_follow)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients)
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
    });
  }

  void _onEvent(Map<Object?, Object?> event) {
    if (event['type'] != 'command' || event['id'] != _operation) return;
    if (event['text'] case final String value) _append(value);
    if (event['bytes'] case final List<int> bytes) {
      final stderr = event['stderr'] == true;
      final decoder = _decoders.putIfAbsent(stderr, () {
        final controller = StreamController<List<int>>();
        controller.stream
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(_append);
        return controller;
      });
      decoder.add(bytes);
    }
    if (event.containsKey('exitCode') || event.containsKey('error')) {
      unawaited(_finish(event));
    }
  }

  Future<void> _finish(Map<Object?, Object?> event) async {
    final id = _operation;
    final decoders = _decoders.values.toList();
    _decoders.clear();
    for (final decoder in decoders) {
      await decoder.close();
    }
    if (!mounted || id != _operation) return;
    final message = event['cancelled'] == true
        ? context.tx('已取消', 'Cancelled')
        : event['error'] != null
        ? '${event['error']}'
        : '${context.tx('退出码', 'Exit code')}: ${event['exitCode']}';
    _append('\n[$message]\n');
    setState(() => _operation = null);
  }

  Future<void> _run() async {
    final device = ref.read(activeDeviceProvider);
    final command = _command.text.trim();
    if (device == null || command.isEmpty || _operation != null) return;
    final id = newOperationId();
    setState(() {
      _operation = id;
      _error = null;
    });
    _append('\n[${device.name}] \$ $command\n');
    ref.read(commandHistoryProvider.notifier).add(command);
    _command.clear();
    try {
      await _client.command(device.id, id, command);
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error;
          _operation = null;
        });
    }
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
    if (_operation != null)
      unawaited(_client.cancel(_operation!).catchError((Object _) {}));
    _subscription?.cancel();
    for (final controller in _decoders.values) {
      controller.close();
    }
    _refresh?.cancel();
    _scroll.dispose();
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeDeviceProvider);
    final history = ref.watch(commandHistoryProvider);
    return ToolPage(
      title: context.tx('终端', 'Terminal'),
      children: [
        const DevicePicker(),
        if (_error != null) ToolErrorNotice(_error!),
        if (active == null && _operation == null) const SelectDeviceNotice(),
        Surface(
          padding: 12,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * .38).clamp(
                  200.0,
                  420.0,
                ),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (event) {
                    if (event is UserScrollNotification)
                      _follow = event.metrics.extentAfter < 24;
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText(
                      _output.isEmpty ? '\$' : _output,
                      style: context.theme.typography.body.sm.copyWith(
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ToolControls(
                breakpoint: 820,
                content: ToolInput(
                  label: context.tx('命令', 'Command'),
                  controller: _command,
                  enabled: _operation == null,
                  hint: 'getprop ro.product.model',
                  onSubmit: (_) => _run(),
                ),
                actions: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ToolButton(
                      context.tx('执行', 'Run'),
                      icon: FLucideIcons.play,
                      onPress: active == null || _operation != null
                          ? null
                          : _run,
                    ),
                    if (_operation != null)
                      ToolButton(
                        context.tx('停止', 'Stop'),
                        icon: FLucideIcons.square,
                        onPress: _cancel,
                      ),
                    ToolButton(
                      context.tx('复制输出', 'Copy output'),
                      icon: FLucideIcons.copy,
                      onPress: _output.isEmpty
                          ? null
                          : () =>
                                Clipboard.setData(ClipboardData(text: _output)),
                    ),
                    ToolButton(
                      context.tx('清空', 'Clear'),
                      onPress: () => setState(() => _output = ''),
                    ),
                  ],
                ),
              ),
              if (_operation != null) ...[
                const SizedBox(height: 12),
                const FProgress(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final command in [
              'id',
              'getprop',
              'df -h',
              'pm list packages',
              'dumpsys battery',
            ])
              ToolButton(
                command,
                onPress: _operation == null
                    ? () => _command.text = command
                    : null,
              ),
          ],
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            context.tx('本次会话历史', 'Session history'),
            style: context.theme.typography.body.lg,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final command in history)
                ToolButton(
                  command,
                  onPress: _operation == null
                      ? () => _command.text = command
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
