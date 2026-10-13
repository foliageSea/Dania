import 'dart:async';

import 'package:dania/app/theme.dart';
import 'package:dania/core/settings/settings.dart';
import 'package:dania/core/toolbox/models.dart';
import 'package:dania/core/toolbox/toolbox_client.dart';
import 'package:dania/features/mirror/mirror_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _MirrorClient extends ToolboxClient {
  final controller = StreamController<Map<Object?, Object?>>.broadcast();
  final starts = <(String, Completer<MirrorInfo>)>[];
  final stops = <String?>[];

  @override
  Stream<Map<Object?, Object?>> get events => controller.stream;

  @override
  Future<List<Device>> devices() async => const [
    Device(id: 'remote', name: 'Phone', address: '192.0.2.1', local: false),
  ];

  @override
  Future<MirrorInfo> startMirror(
    String device, {
    required String mirrorId,
    int maxSize = 1280,
    int bitRate = 4000000,
  }) {
    final pending = Completer<MirrorInfo>();
    starts.add((mirrorId, pending));
    return pending.future;
  }

  @override
  Future<void> stopMirror(String device, {String? mirrorId}) async {
    stops.add(mirrorId);
  }
}

Future<void> _open(WidgetTester tester, _MirrorClient client) async {
  final theme = createAppTheme(
    const AppSettings(),
    brightness: Brightness.light,
    touch: false,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [toolboxProvider.overrideWithValue(client)],
      child: MaterialApp(
        localizationsDelegates: FLocalizations.localizationsDelegates,
        home: FTheme(
          data: theme,
          child: const FTooltipGroup(child: MirrorPage(deviceId: 'remote')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start'));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('startup timeout clears loading and allows retry', (
    tester,
  ) async {
    final client = _MirrorClient();
    addTearDown(client.controller.close);
    await _open(tester, client);
    expect(find.byType(FCircularProgress), findsOneWidget);
    final first = client.starts.single;

    await tester.pump(const Duration(seconds: 36));
    expect(find.byType(FCircularProgress), findsNothing);
    expect(
      find.text('Screen control startup timed out. Try again.'),
      findsOneWidget,
    );
    expect(client.stops, [first.$1]);

    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(client.starts, hasLength(2));
    first.$2.complete(const MirrorInfo(textureId: 1, width: 720, height: 1280));
    await tester.pump();
    expect(find.byType(FCircularProgress), findsOneWidget);
    expect(client.stops, [first.$1, first.$1]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('event stream failure clears loading and stops the session', (
    tester,
  ) async {
    final client = _MirrorClient();
    addTearDown(client.controller.close);
    await _open(tester, client);
    client.controller.addError(StateError('Event connection lost'));
    await tester.pump();
    expect(find.byType(FCircularProgress), findsNothing);
    expect(find.text('Bad state: Event connection lost'), findsOneWidget);
    expect(client.stops, [client.starts.single.$1]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('successful startup cancels the loading deadline', (
    tester,
  ) async {
    final client = _MirrorClient();
    addTearDown(client.controller.close);
    await _open(tester, client);
    client.starts.single.$2.complete(
      const MirrorInfo(textureId: 1, width: 720, height: 1280),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 36));
    expect(find.byType(FCircularProgress), findsNothing);
    expect(find.byType(Texture), findsOneWidget);
    expect(client.stops, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
