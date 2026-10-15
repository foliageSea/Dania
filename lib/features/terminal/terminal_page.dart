import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:xterm/xterm.dart';

import '../../core/toolbox/device_state.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';
import 'terminal_session.dart';

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
  late final TerminalSession _session;
  final _view = GlobalKey<TerminalViewState>();
  final _selection = TerminalController();
  final _focus = FocusNode();
  final _command = TextEditingController();
  String? _selected;
  bool _ctrl = false;
  bool _commands = false;

  @override
  void initState() {
    super.initState();
    _session = TerminalSession(ref.read(toolboxProvider));
    _session.terminal.onOutput = (data) {
      if (_ctrl && data.runes.length == 1) {
        final code = data.codeUnitAt(0);
        if (code >= 64 && code <= 127) data = String.fromCharCode(code & 31);
        setState(() => _ctrl = false);
      }
      _session.send(data);
    };
  }

  void _select(String? device) {
    if (_selected == device) return;
    _selected = device;
    _ctrl = false;
    _selection.clearSelection();
    if (device == null) {
      _session.disconnect();
    } else {
      unawaited(_session.connect(device));
    }
  }

  void _key(TerminalKey key) {
    _session.terminal.keyInput(key, ctrl: _ctrl);
    if (_ctrl) setState(() => _ctrl = false);
  }

  void _insert(String command) {
    _session.terminal.paste(command);
    ref.read(commandHistoryProvider.notifier).add(command);
    _command.clear();
    _focus.requestFocus();
  }

  Future<void> _paste() async {
    final id = _session.sessionId;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (mounted &&
        _session.running &&
        id == _session.sessionId &&
        data?.text != null) {
      _session.terminal.paste(data!.text!);
      _focus.requestFocus();
    }
  }

  String _status(BuildContext context) => switch (_session.phase) {
    TerminalPhase.idle => context.tx(
      '选择设备以连接终端',
      'Select a device to open a terminal',
    ),
    TerminalPhase.starting => context.tx('正在连接…', 'Connecting…'),
    TerminalPhase.running => context.tx('已连接', 'Connected'),
    TerminalPhase.closing => context.tx('正在断开…', 'Disconnecting…'),
    TerminalPhase.failed => context.tx(
      '连接失败，可重新连接',
      'Connection failed. Reconnect to retry.',
    ),
    TerminalPhase.exited =>
      _session.exitCode != null
          ? '${context.tx('退出码', 'Exit code')}: ${_session.exitCode}'
          : context.tx('会话已断开', 'Session disconnected'),
  };

  @override
  void dispose() {
    _session.dispose();
    _selection.dispose();
    _focus.dispose();
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeDeviceProvider);
    ref.listen(activeDeviceProvider, (_, next) => _select(next?.id));
    if (_selected != active?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _select(ref.read(activeDeviceProvider)?.id);
      });
    }
    final history = ref.watch(commandHistoryProvider);
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) => ToolPage(
        title: context.tx('终端', 'Terminal'),
        expandedChild: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TerminalView(
                  _session.terminal,
                  key: _view,
                  controller: _selection,
                  focusNode: _focus,
                  readOnly: !_session.running,
                  keyboardType: TextInputType.text,
                  deleteDetection: true,
                  padding: const EdgeInsets.all(8),
                  textStyle: const TerminalStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 6,
                children: [
                  for (final entry in <(String, TerminalKey)>[
                    ('Esc', TerminalKey.escape),
                    ('Tab', TerminalKey.tab),
                    ('↑', TerminalKey.arrowUp),
                    ('↓', TerminalKey.arrowDown),
                    ('←', TerminalKey.arrowLeft),
                    ('→', TerminalKey.arrowRight),
                  ])
                    ToolButton(
                      entry.$1,
                      onPress: _session.running ? () => _key(entry.$2) : null,
                    ),
                  FButton(
                    size: .sm,
                    variant: _ctrl ? .primary : .outline,
                    onPress: _session.running
                        ? () => setState(() => _ctrl = !_ctrl)
                        : null,
                    child: const Text('Ctrl'),
                  ),
                  ToolButton(
                    'Ctrl+C',
                    onPress: _session.running
                        ? () => _session.send('\x03')
                        : null,
                  ),
                  ToolButton(
                    'Ctrl+D',
                    onPress: _session.running
                        ? () => _session.send('\x04')
                        : null,
                  ),
                  ToolButton(
                    'Enter',
                    onPress: _session.running
                        ? () => _key(TerminalKey.enter)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        children: [
          const DevicePicker(),
          if (_session.error != null) ToolErrorNotice(_session.error!),
          Row(
            children: [
              Expanded(child: Text(_status(context))),
              if (_session.connected)
                ToolButton(
                  context.tx('断开', 'Disconnect'),
                  onPress: _session.disconnect,
                )
              else
                ToolButton(
                  context.tx('重新连接', 'Reconnect'),
                  onPress: active == null
                      ? null
                      : () => _session.connect(active.id),
                ),
            ],
          ),
          if (_session.phase == TerminalPhase.starting) ...[
            const SizedBox(height: 8),
            const FProgress(),
          ],
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                ToolButton(
                  context.tx('键盘', 'Keyboard'),
                  icon: FLucideIcons.keyboard,
                  onPress: _session.running
                      ? () {
                          _focus.requestFocus();
                          _view.currentState?.requestKeyboard();
                        }
                      : null,
                ),
                ToolButton(
                  context.tx('粘贴', 'Paste'),
                  onPress: _session.running ? _paste : null,
                ),
                ToolButton(
                  context.tx('复制选区/输出', 'Copy selection/output'),
                  onPress: () => Clipboard.setData(
                    ClipboardData(
                      text: _session.terminal.buffer.getText(
                        _selection.selection,
                      ),
                    ),
                  ),
                ),
                ToolButton(
                  context.tx('清空显示', 'Clear display'),
                  onPress: _session.clear,
                ),
                ToolButton(
                  context.tx('快捷命令', 'Commands'),
                  onPress: () => setState(() => _commands = !_commands),
                ),
              ],
            ),
          ),
          if (_commands) ...[
            const SizedBox(height: 8),
            ToolControls(
              content: ToolInput(
                label: context.tx(
                  '插入命令（不会自动执行）',
                  'Insert command (does not execute)',
                ),
                controller: _command,
                enabled: _session.running,
                onSubmit: (_) {
                  if (_session.running && _command.text.isNotEmpty) {
                    _insert(_command.text);
                  }
                },
              ),
              actions: ToolButton(
                context.tx('插入', 'Insert'),
                onPress: _session.running
                    ? () {
                        if (_command.text.isNotEmpty) _insert(_command.text);
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final command in {
                  ...[
                    'id',
                    'getprop',
                    'df -h',
                    'pm list packages',
                    'dumpsys battery',
                  ],
                  ...history,
                })
                  ToolButton(
                    command,
                    onPress: _session.running ? () => _insert(command) : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
