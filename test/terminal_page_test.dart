import 'dart:convert';

import 'package:dania/app/theme.dart';
import 'package:dania/core/settings/settings.dart';
import 'package:dania/core/toolbox/device_state.dart';
import 'package:dania/core/toolbox/models.dart';
import 'package:dania/core/toolbox/toolbox_client.dart';
import 'package:dania/features/terminal/terminal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:xterm/xterm.dart';

import 'terminal_session_test.dart' show FakeTerminalClient;

class _PageClient extends FakeTerminalClient {
  @override
  Future<List<Device>> devices() async => const [
    Device(id: 'phone', name: 'Phone', address: 'Shizuku', local: true),
    Device(id: 'other', name: 'Other', address: 'ADB', local: false),
  ];
  @override
  Future<void> openTerminal(
    String device,
    String session,
    int columns,
    int rows,
  ) {
    final result = super.openTerminal(device, session, columns, rows);
    opens.last.$3.complete();
    return result;
  }
}

void main() {
  testWidgets(
    'terminal fits keyboard and rotation; keys target current session',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final client = _PageClient();
      addTearDown(client.controller.close);
      final container = ProviderContainer(
        overrides: [toolboxProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      container.read(selectedDeviceProvider.notifier).select('phone');
      final theme = createAppTheme(
        const AppSettings(),
        brightness: Brightness.dark,
        touch: true,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: FLocalizations.localizationsDelegates,
            home: FTheme(
              data: theme,
              child: const FTooltipGroup(child: TerminalPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      expect(find.byType(TerminalView), findsOneWidget);
      expect(tester.takeException(), isNull);
      final firstId = client.opens.single.$2;
      await tester.ensureVisible(find.text('Ctrl+C'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ctrl+C'));
      await tester.pump();
      expect(utf8.decode(client.writes.last.$2), '\x03');
      expect(client.writes.last.$1, firstId);
      final initialRows = client.sizes.last.$3;
      final initialColumns = client.sizes.last.$2;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(client.sizes.last.$3, lessThan(initialRows));
      tester.view.physicalSize = const Size(844, 390);
      tester.view.viewInsets = const FakeViewPadding(bottom: 150);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final wideColumns = client.sizes.last.$2;
      expect(wideColumns, greaterThan(initialColumns));
      container.read(selectedDeviceProvider.notifier).select('other');
      await tester.pumpAndSettle();
      expect(client.closes, contains(firstId));
      expect(client.opens, hasLength(2));
      expect(find.text('Connected'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(client.closes, contains(client.opens.last.$2));
    },
  );
}
