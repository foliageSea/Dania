import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/toolbox/device_state.dart';
import '../../core/toolbox/models.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';

class MirrorPage extends ConsumerStatefulWidget {
  const MirrorPage({required this.deviceId, super.key});
  final String deviceId;
  @override
  ConsumerState<MirrorPage> createState() => _MirrorPageState();
}

class _MirrorPageState extends ConsumerState<MirrorPage>
    with WidgetsBindingObserver {
  late final ToolboxClient _client;
  StreamSubscription<Map<Object?, Object?>>? _events;
  Timer? _startupTimer;
  MirrorInfo? _info;
  String? _mirrorId;
  bool _starting = false;
  bool _playing = false;
  Object? _error;
  int _quality = 1;

  @override
  void initState() {
    super.initState();
    _client = ref.read(toolboxProvider);
    WidgetsBinding.instance.addObserver(this);
    _events = _client.events.listen(
      (event) {
        if (!mounted ||
            event['type'] != 'mirror' ||
            event['deviceId'] != widget.deviceId ||
            event['mirrorId'] != _mirrorId)
          return;
        setState(() {
          switch (event['state']) {
            case 'size':
              if (_info != null)
                _info = _info!.resize(
                  (event['width']! as num).toInt(),
                  (event['height']! as num).toInt(),
                );
            case 'playing':
              _playing = true;
            case 'error':
              _startupTimer?.cancel();
              _error = event['error'] ?? 'Screen control failed';
              _info = null;
              _starting = false;
              _playing = false;
            case 'stopped':
              _startupTimer?.cancel();
              _info = null;
              _starting = false;
              _playing = false;
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        unawaited(_stop());
        setState(() => _error = error);
      },
    );
  }

  Future<void> _start() async {
    if (_starting || _info != null) return;
    final id = newOperationId();
    setState(() {
      _starting = true;
      _error = null;
      _playing = false;
      _mirrorId = id;
    });
    _startupTimer = Timer(const Duration(seconds: 35), () {
      if (!mounted || _mirrorId != id || !_starting) return;
      unawaited(_stop());
      setState(() {
        _error = ToolboxException(
          'mirrorTimeout',
          context.tx(
            '投屏启动超时，请重试',
            'Screen control startup timed out. Try again.',
          ),
        );
      });
    });
    try {
      final settings = [
        (720, 2000000),
        (1280, 4000000),
        (1920, 8000000),
      ][_quality];
      final info = await _client.startMirror(
        widget.deviceId,
        mirrorId: id,
        maxSize: settings.$1,
        bitRate: settings.$2,
      );
      if (mounted && _mirrorId == id && _starting) {
        _startupTimer?.cancel();
        setState(() {
          _info = info;
          _starting = false;
        });
      } else {
        await _client.stopMirror(widget.deviceId, mirrorId: id);
      }
    } catch (error) {
      if (mounted && _mirrorId == id) {
        _startupTimer?.cancel();
        setState(() {
          _error = error;
          _starting = false;
        });
      }
    }
  }

  Future<void> _stop() async {
    _startupTimer?.cancel();
    final id = _mirrorId;
    _mirrorId = null;
    if (mounted)
      setState(() {
        _info = null;
        _starting = false;
        _playing = false;
      });
    try {
      if (id != null) await _client.stopMirror(widget.deviceId, mirrorId: id);
    } catch (error) {
      if (mounted && _mirrorId == null) setState(() => _error = error);
    }
  }

  void _touch(PointerEvent event, int action, Size size) {
    final info = _info;
    if (info == null || !_playing || size.width == 0 || size.height == 0)
      return;
    unawaited(
      _client
          .mirrorTouch(
            widget.deviceId,
            action: action,
            pointer: event.pointer,
            x: (event.localPosition.dx / size.width * info.width).floor(),
            y: (event.localPosition.dy / size.height * info.height).floor(),
            width: info.width,
            height: info.height,
          )
          .catchError((Object error) {
            if (mounted) setState(() => _error = error);
          }),
    );
  }

  Future<void> _key(int key) async {
    try {
      await _client.mirrorKey(widget.deviceId, key);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached)
      unawaited(_stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startupTimer?.cancel();
    _events?.cancel();
    final id = _mirrorId;
    if (id != null)
      unawaited(
        _client
            .stopMirror(widget.deviceId, mirrorId: id)
            .catchError((Object _) {}),
      );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = ref
        .watch(devicesProvider)
        .asData
        ?.value
        .where((item) => item.id == widget.deviceId)
        .firstOrNull;
    final info = _info;
    return SafeArea(
      child: FScaffold(
        childPad: false,
        header: FHeader.nested(
          title: Text(device?.name ?? context.tx('投屏控制', 'Screen control')),
          prefixes: [
            FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  if (_error != null) ToolErrorNotice(_error!),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (index, label) in [
                        '720p',
                        '1280p',
                        '1920p',
                      ].indexed)
                        FButton(
                          mainAxisSize: .min,
                          size: .sm,
                          variant: _quality == index ? .primary : .outline,
                          onPress: _starting || info != null
                              ? null
                              : () => setState(() => _quality = index),
                          child: Text(label),
                        ),
                      ToolButton(
                        context.tx('开始', 'Start'),
                        icon: FLucideIcons.play,
                        onPress:
                            device == null ||
                                device.local ||
                                _starting ||
                                info != null
                            ? null
                            : _start,
                      ),
                      ToolButton(
                        context.tx('停止', 'Stop'),
                        icon: FLucideIcons.square,
                        onPress: !_starting && info == null ? null : _stop,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: const Color(0xff09090b),
                child: Center(
                  child: info == null
                      ? _starting
                            ? const FCircularProgress()
                            : Icon(
                                FLucideIcons.monitor,
                                size: 48,
                                color: context.theme.colors.mutedForeground,
                              )
                      : Padding(
                          padding: const EdgeInsets.all(8),
                          child: AspectRatio(
                            aspectRatio: info.width / info.height,
                            child: LayoutBuilder(
                              builder: (context, constraints) => Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (event) =>
                                    _touch(event, 0, constraints.biggest),
                                onPointerUp: (event) =>
                                    _touch(event, 1, constraints.biggest),
                                onPointerMove: (event) =>
                                    _touch(event, 2, constraints.biggest),
                                onPointerCancel: (event) =>
                                    _touch(event, 3, constraints.biggest),
                                child: Texture(textureId: info.textureId),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, key) in [
                    (context.tx('返回', 'Back'), 4),
                    (context.tx('主页', 'Home'), 3),
                    (context.tx('最近任务', 'Recents'), 187),
                    (context.tx('音量 −', 'Volume −'), 25),
                    (context.tx('音量 +', 'Volume +'), 24),
                  ])
                    ToolButton(
                      label,
                      onPress: info == null || !_playing
                          ? null
                          : () => _key(key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
