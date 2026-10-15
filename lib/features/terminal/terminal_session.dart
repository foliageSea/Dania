import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../core/toolbox/toolbox_client.dart';

enum TerminalPhase { idle, starting, running, exited, failed, closing }

class _TextSink implements Sink<String> {
  _TextSink(this.output);
  final void Function(String) output;
  @override
  void add(String data) => output(data);
  @override
  void close() {}
}

class _Connection {
  _Connection(this.device, this.id, void Function(String) output)
    : decoder = const Utf8Decoder(allowMalformed: true)
          .startChunkedConversion(StringConversionSink.from(_TextSink(output)));
  final String device;
  final String id;
  final ByteConversionSink decoder;
  final ready = Completer<void>();
  final stopped = Completer<void>();
  Timer? deadline;
  Future<void> queue = Future.value();
  int queuedBytes = 0;
  bool ended = false;
}

/// Owns one PTY connection. Queued work captures its connection, never a later ID.
class TerminalSession extends ChangeNotifier {
  TerminalSession(
    this.client, {
    this.startTimeout = const Duration(seconds: 30),
  }) {
    terminal.onOutput = send;
    terminal.onResize = (columns, rows, _, _) => resize(columns, rows);
    _events = client.events.listen(
      _event,
      onError: (Object error) {
        final connection = _connection;
        if (connection != null) _fail(connection, error);
      },
      onDone: () {
        final connection = _connection;
        if (connection != null && !connection.ended) {
          _fail(connection, StateError('Terminal event connection closed'));
        }
      },
    );
  }

  final ToolboxClient client;
  final Duration startTimeout;
  final terminal = Terminal(
    maxLines: 5000,
    platform: TerminalTargetPlatform.linux,
  );
  late final StreamSubscription<Map<Object?, Object?>> _events;
  _Connection? _connection;
  TerminalPhase phase = TerminalPhase.idle;
  Object? error;
  int? exitCode;
  String? reason;
  int columns = 80;
  int rows = 24;
  Timer? _resizeTimer;
  bool _disposed = false;
  String? get deviceId => _connection?.device;
  String? get sessionId => _connection?.id;
  bool get running => phase == TerminalPhase.running;
  bool get connected => phase == TerminalPhase.starting || running;

  bool _current(_Connection connection) =>
      !_disposed && identical(connection, _connection) && !connection.ended;

  Future<void> connect(String device) async {
    disconnect();
    if (_disposed) return;
    // New sessions start with a clean emulator, preserving size and callbacks.
    terminal.write('\x1bc');
    final connection = _Connection(device, newOperationId(), terminal.write);
    _connection = connection;
    error = null;
    exitCode = null;
    reason = null;
    phase = TerminalPhase.starting;
    notifyListeners();
    connection.deadline = Timer(startTimeout, () {
      if (_current(connection)) {
        _fail(connection, TimeoutException('Terminal startup timed out'));
      }
    });
    try {
      await Future.any([
        client.openTerminal(device, connection.id, columns, rows),
        connection.stopped.future,
      ]);
      connection.deadline?.cancel();
      if (!_current(connection)) {
        _close(connection);
        return;
      }
      phase = TerminalPhase.running;
      connection.ready.complete();
      // The view may have changed size while the backend was opening.
      resize(columns, rows, force: true);
      notifyListeners();
    } catch (error) {
      if (_current(connection)) _fail(connection, error);
      // A late native open must also be closed after a timeout/cancellation.
      _close(connection);
    }
  }

  void _event(Map<Object?, Object?> event) {
    final connection = _connection;
    if (connection == null ||
        !_current(connection) ||
        event['type'] != 'terminal' ||
        event['sessionId'] != connection.id ||
        event['deviceId'] != connection.device) {
      return;
    }
    if (event['bytes'] case final List<int> bytes) {
      connection.decoder.add(bytes);
      if (event['sequence'] case final int sequence) {
        unawaited(
          client.acknowledgeTerminal(connection.id, sequence).catchError((
            Object error,
          ) {
            if (_current(connection)) _fail(connection, error);
          }),
        );
      }
    }
    if (event['ended'] == true) {
      exitCode = event['exitCode'] as int?;
      reason = event['reason'] as String?;
      error = event['error'];
      _end(connection);
      phase = error == null ? TerminalPhase.exited : TerminalPhase.failed;
      notifyListeners();
    }
  }

  void send(String data) {
    final connection = _connection;
    if (connection == null || !_current(connection) || data.isEmpty) return;
    final bytes = utf8.encode(data);
    if (connection.queuedBytes + bytes.length > 256 * 1024) {
      _fail(connection, StateError('Terminal input queue exceeded 256 KiB'));
      return;
    }
    connection.queuedBytes += bytes.length;
    _enqueue(connection, () async {
      try {
        for (
          var offset = 0;
          offset < bytes.length && _current(connection);
          offset += 16384
        ) {
          final end = (offset + 16384).clamp(0, bytes.length);
          await client.writeTerminal(
            connection.id,
            Uint8List.fromList(bytes.sublist(offset, end)),
          );
        }
      } finally {
        connection.queuedBytes -= bytes.length;
      }
    });
  }

  void _enqueue(_Connection connection, Future<void> Function() action) {
    connection.queue = connection.queue
        .then((_) async {
          await connection.ready.future;
          if (_current(connection)) {
            await Future.any([action(), connection.stopped.future])
                .timeout(const Duration(seconds: 15));
          }
        })
        .catchError((Object error) {
          if (_current(connection)) _fail(connection, error);
        });
  }

  void resize(int width, int height, {bool force = false}) {
    final nextColumns = width.clamp(2, 1000);
    final nextRows = height.clamp(1, 1000);
    if (!force && columns == nextColumns && rows == nextRows) return;
    columns = nextColumns;
    rows = nextRows;
    _resizeTimer?.cancel();
    final connection = _connection;
    if (connection == null || !_current(connection)) return;
    _resizeTimer = Timer(const Duration(milliseconds: 50), () {
      _enqueue(
        connection,
        () => client.resizeTerminal(connection.id, columns, rows),
      );
    });
  }

  void _fail(_Connection connection, Object value) {
    if (!_current(connection)) return;
    error = value is TimeoutException
        ? const ToolboxException(
            'terminalTimeout',
            'Terminal connection timed out',
          )
        : value;
    reason = 'failed';
    _end(connection);
    phase = TerminalPhase.failed;
    _close(connection);
    notifyListeners();
  }

  void _end(_Connection connection) {
    connection.ended = true;
    connection.deadline?.cancel();
    if (!connection.stopped.isCompleted) connection.stopped.complete();
    connection.decoder.close();
    if (!connection.ready.isCompleted) connection.ready.complete();
    _resizeTimer?.cancel();
  }

  void _close(_Connection connection) {
    unawaited(client.closeTerminal(connection.id).catchError((Object _) {}));
  }

  void disconnect() {
    final connection = _connection;
    if (connection == null || connection.ended) return;
    phase = TerminalPhase.closing;
    _end(connection);
    _close(connection);
    reason = 'closed';
    phase = TerminalPhase.exited;
    if (!_disposed) notifyListeners();
  }

  void clear() => terminal.write('\x1b[2J\x1b[3J\x1b[H');

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    _resizeTimer?.cancel();
    unawaited(_events.cancel());
    terminal.onOutput = null;
    terminal.onResize = null;
    super.dispose();
  }
}
