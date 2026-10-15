import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dania/core/toolbox/toolbox_client.dart';
import 'package:dania/features/terminal/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTerminalClient extends ToolboxClient {
  final controller = StreamController<Map<Object?, Object?>>.broadcast(
    sync: true,
  );
  final opens = <(String, String, Completer<void>)>[];
  final writes = <(String, List<int>)>[];
  final sizes = <(String, int, int)>[];
  final closes = <String>[];
  final acknowledgements = <(String, int)>[];
  Completer<void>? blockWrite;
  Object? writeError;
  @override
  Stream<Map<Object?, Object?>> get events => controller.stream;
  @override
  Future<void> openTerminal(
    String device,
    String session,
    int columns,
    int rows,
  ) {
    final pending = Completer<void>();
    opens.add((device, session, pending));
    return pending.future;
  }

  @override
  Future<void> writeTerminal(String session, Uint8List bytes) async {
    writes.add((session, bytes.toList()));
    if (writeError != null) throw writeError!;
    await blockWrite?.future;
  }

  @override
  Future<void> resizeTerminal(String session, int columns, int rows) async =>
      sizes.add((session, columns, rows));
  @override
  Future<void> closeTerminal(String session) async => closes.add(session);
  @override
  Future<void> acknowledgeTerminal(String session, int sequence) async =>
      acknowledgements.add((session, sequence));
  void event(
    String session,
    Map<String, Object?> fields, {
    String device = 'phone',
  }) => controller.add({
    'type': 'terminal',
    'deviceId': device,
    'sessionId': session,
    ...fields,
  });
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeTerminalClient client;
  late TerminalSession session;
  setUp(() {
    client = FakeTerminalClient();
    session = TerminalSession(client);
  });
  tearDown(() async {
    session.dispose();
    await client.controller.close();
  });

  Future<String> open() async {
    final opening = session.connect('phone');
    client.opens.last.$3.complete();
    await opening;
    return session.sessionId!;
  }

  test(
    'decodes split UTF-8 before acknowledging and preserves ANSI output',
    () async {
      final id = await open();
      final bytes = utf8.encode('中文');
      client.event(id, {'bytes': bytes.sublist(0, 2), 'sequence': 1});
      expect(session.terminal.buffer.getText(), isNot(contains('�')));
      client.event(id, {'bytes': bytes.sublist(2), 'sequence': 2});
      client.event(id, {'bytes': utf8.encode('\x1b[31m red\x1b[0m')});
      expect(session.terminal.buffer.getText(), contains('中文 red'));
      expect(client.acknowledgements, [(id, 1), (id, 2)]);
    },
  );

  test(
    'serializes raw input including whitespace and control characters',
    () async {
      final id = await open();
      final blocked = Completer<void>();
      client.blockWrite = blocked;
      session.send('  中文\r');
      session.send('\x03');
      await flush();
      expect(client.writes.length, 1);
      blocked.complete();
      await flush();
      expect(client.writes.map((entry) => entry.$1), everyElement(id));
      expect(client.writes.map((entry) => utf8.decode(entry.$2)), [
        '  中文\r',
        '\x03',
      ]);
    },
  );

  test('chunks large UTF-8 input without altering bytes', () async {
    await open();
    final text = List.filled(10000, '中').join();
    session.send(text);
    await flush();
    expect(client.writes.length, 2);
    expect(client.writes.every((entry) => entry.$2.length <= 16384), isTrue);
    expect(
      utf8.decode(client.writes.expand((entry) => entry.$2).toList()),
      text,
    );
  });

  test(
    'switch during startup closes old session and rejects late output',
    () async {
      final firstOpen = session.connect('old');
      final oldId = session.sessionId!;
      final secondOpen = session.connect('phone');
      final newId = session.sessionId!;
      client.opens.last.$3.complete();
      await secondOpen;
      client.event(oldId, {
        'bytes': utf8.encode('OLD'),
        'ended': true,
      }, device: 'old');
      client.opens.first.$3.complete();
      await firstOpen;
      expect(session.running, isTrue);
      expect(session.sessionId, newId);
      expect(session.terminal.buffer.getText(), isNot(contains('OLD')));
      expect(client.closes, contains(oldId));
    },
  );

  test('queued input never migrates to reconnected session', () async {
    final oldId = await open();
    final blocked = Completer<void>();
    client.blockWrite = blocked;
    session.send('first');
    session.send('stale');
    await flush();
    session.disconnect();
    await open();
    blocked.complete();
    await flush();
    expect(client.writes, hasLength(1));
    expect(client.writes.single.$1, oldId);
    expect(client.writes.single.$2, utf8.encode('first'));
  });

  test('resize changes are coalesced and delivered after startup', () async {
    final pending = session.connect('phone');
    session.resize(100, 30);
    session.resize(120, 40);
    client.opens.last.$3.complete();
    await pending;
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(client.sizes, [(session.sessionId!, 120, 40)]);
  });

  test('natural exit flushes malformed tail and disables input', () async {
    final id = await open();
    client.event(id, {
      'bytes': [0xe4],
    });
    client.event(id, {'ended': true, 'exitCode': 7, 'reason': 'exited'});
    session.send('ignored');
    await flush();
    expect(session.phase, TerminalPhase.exited);
    expect(session.exitCode, 7);
    expect(session.terminal.buffer.getText(), contains('�'));
    expect(client.writes, isEmpty);
  });

  test('stream error and write failure close the active PTY', () async {
    final first = await open();
    client.controller.addError(StateError('disconnected'));
    expect(session.phase, TerminalPhase.failed);
    expect(client.closes, contains(first));
    final second = await open();
    client.writeError = StateError('write failed');
    session.send('input');
    await flush();
    expect(session.phase, TerminalPhase.failed);
    expect(client.closes, contains(second));
  });

  testWidgets(
    'startup timeout can reconnect without accepting a late completion',
    (tester) async {
      final firstOpen = session.connect('phone');
      final oldId = session.sessionId!;
      await tester.pump(const Duration(seconds: 31));
      await firstOpen;
      expect(session.phase, TerminalPhase.failed);
      expect(client.closes, contains(oldId));
      final newOpen = session.connect('phone');
      client.opens.last.$3.complete();
      await newOpen;
      client.opens.first.$3.complete();
      await tester.pump();
      expect(session.running, isTrue);
      expect(session.sessionId, isNot(oldId));
      session.disconnect();
    },
  );

  test('clear only changes display and leaves connection open', () async {
    final id = await open();
    client.event(id, {'bytes': utf8.encode('hello')});
    session.clear();
    expect(session.terminal.buffer.getText(), isNot(contains('hello')));
    expect(session.running, isTrue);
    expect(client.writes, isEmpty);
  });
}
