import 'dart:async';

import 'package:dania/core/toolbox/toolbox_client.dart';
import 'package:dania/features/terminal/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm/xterm.dart';

Future<void> until(bool Function() predicate, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out: $description');
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<void> exercise(ToolboxClient client, String device) async {
  final session = TerminalSession(client);
  try {
    await session.connect(device);
    expect(session.running, isTrue, reason: session.error?.toString());
    String screen() => session.terminal.buffer.getText();
    Future<void> command(String value, String output) async {
      session.clear();
      session.send('$value\r');
      await until(() => screen().contains(output), 'shell response $output');
    }

    await command('id', 'uid=');
    expect(screen().contains('uid=2000') || screen().contains('uid=0'), isTrue);
    await command(
      'cd /data/local/tmp; printf "\\n__DIR:%s\\n" "\$PWD"',
      '__DIR:/data/local/tmp',
    );
    session.clear();
    session.send('read -r value; printf "\\n__READ:%s\\n" "\$value"\r');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    session.send('你好终端\r');
    await until(
      () => screen().contains('__READ:你好终端'),
      'interactive Unicode input',
    );
    await command(
      'printf "\\n__ANSI:%s\\n" "\$(printf "\\033[31mRED\\033[0m")"',
      '__ANSI:RED',
    );
    session.clear();
    session.send('getpr\t');
    await until(() => screen().contains('getprop'), 'Tab completion');
    session.send(
      '\x15',
    ); // Ctrl+U clears the completed command without executing it.
    await command('printf "\\n__HISTORY\\n"', '\n__HISTORY\n');
    session.clear();
    session.terminal.keyInput(TerminalKey.arrowUp);
    session.send('\r');
    await until(
      () => screen().contains('\n__HISTORY\n'),
      'Shell history with Up',
    );
    session.send('sleep 60\r');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    session.send('\x03');
    await command('printf "\\n__INTERRUPTED\\n"', '\n__INTERRUPTED\n');
    session.resize(100, 32, force: true);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await command('printf "\\n__SIZE:%s\\n" "\$(stty size)"', '__SIZE:32 100');
    session.clear();
    session.send('top -d 1\r');
    await until(
      () => screen().contains('PID') && screen().contains('CPU'),
      'top full screen output',
    );
    session.resize(90, 28);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    session.send('q');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await command(
      'printf "\\n__AFTER_TOP:%s\\n" "\$(stty size)"',
      '__AFTER_TOP:28 90',
    );
    session.send('exit 7\r');
    await until(
      () =>
          session.phase == TerminalPhase.exited ||
          session.phase == TerminalPhase.failed,
      'exit event',
    );
    expect(
      session.phase,
      TerminalPhase.exited,
      reason: session.error?.toString(),
    );
    expect(session.exitCode, 7);
    await session.connect(device);
    expect(session.running, isTrue, reason: session.error?.toString());
    await command('printf "\\n__RECONNECTED\\n"', '\n__RECONNECTED\n');
    session.disconnect();
    expect(session.connected, isFalse);
  } finally {
    session.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final client = ToolboxClient();
  testWidgets(
    'Shizuku PTY supports interactive shell, signals, resize and reconnect',
    (tester) async {
      await tester.runAsync(() async {
        await until(() => client.supported, 'Android platform');
        var status = await client.status();
        for (var attempt = 0; !status.running && attempt < 30; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          status = await client.status();
        }
        expect(
          status.running,
          isTrue,
          reason: 'Start Shizuku before running this test',
        );
        expect(
          status.granted,
          isTrue,
          reason: 'Authorize Dania in Shizuku before running this test',
        );
        await client.connectLocal();
        await exercise(client, 'local');
      });
    },
  );

  const host = String.fromEnvironment('TERMINAL_ADB_HOST');
  const port = int.fromEnvironment('TERMINAL_ADB_PORT');
  testWidgets(
    'ADB PTY supports interactive shell, signals, resize and reconnect',
    (tester) async {
      await tester.runAsync(() async {
        final device = await client.connect(host, port);
        try {
          await exercise(client, device);
        } finally {
          await client.disconnect(device);
        }
      });
    },
    skip: host.isEmpty || port == 0,
  );
}
