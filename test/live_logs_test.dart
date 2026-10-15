import 'package:dania/core/logging/live_log_store.dart';
import 'package:dania/features/settings/live_log_controller.dart';
import 'package:dania/features/settings/live_log_text.dart';
import 'package:dania/features/settings/live_logs_section.dart';
import 'package:dania/l10n/generated/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

void append(LiveLogStore store, String text, [Level level = Level.INFO]) =>
    store.add(level: level, time: DateTime(2026, 10, 13, 12), text: text);

Widget viewer(LiveLogStore store, {String language = 'en', double scale = 1}) {
  final theme = FTheme.neutral.light.touch;
  return ProviderScope(
    overrides: [liveLogStoreProvider.overrideWithValue(store)],
    child: MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...FLocalizations.localizationsDelegates,
      ],
      theme: theme.toApproximateMaterialTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: FTheme(
          data: theme,
          child: FToaster(child: child!),
        ),
      ),
      home: FScaffold(
        child: const SingleChildScrollView(child: LiveLogsSection()),
      ),
    ),
  );
}

void main() {
  testWidgets('pause, search, level filtering and clearing remain view-local', (
    tester,
  ) async {
    final store = LiveLogStore(maxEntries: 3);
    final first = LiveLogController(store);
    final second = LiveLogController(store);
    addTearDown(() {
      first.dispose();
      second.dispose();
      store.dispose();
    });
    append(store, 'INFO [Worker] started');
    append(store, 'SEVERE [Worker] failed\n#0 stack.dart:42', Level.SEVERE);
    await tester.pump(const Duration(milliseconds: 150));
    first.setQuery(' STACK.dart:42 ');
    first.setMinimumLevel(Level.WARNING);
    expect(first.entries.length, 1);
    expect(first.copyText, contains('#0 stack.dart:42'));
    first.togglePaused();
    append(store, 'SEVERE stack.dart:42 again', Level.SEVERE);
    await tester.pump(const Duration(milliseconds: 150));
    expect(first.entries.length, 1);
    expect(second.entries.length, 3);
    first.togglePaused();
    expect(first.entries.length, 2);
    first.clearView();
    expect(first.entries, isEmpty);
    expect(second.entries.length, 3);
    append(store, 'SEVERE stack.dart:42 after clear', Level.SEVERE);
    await tester.pump(const Duration(milliseconds: 150));
    expect(first.entries.length, 1);
    expect(store.snapshot.length, 3);
  });

  for (final width in [390.0, 900.0]) {
    testWidgets('viewer filters, pauses and copies full logs at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1100);
      addTearDown(tester.view.reset);
      final store = LiveLogStore();
      addTearDown(store.dispose);
      append(store, 'INFO [Worker] started');
      const failure = 'SEVERE [Worker] failed\nError\n#0 stack.dart:42';
      append(store, failure, Level.SEVERE);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(viewer(store));
      await tester.pumpAndSettle();
      expect(find.text('2 entries'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('log-level')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WARNING+').last);
      await tester.pumpAndSettle();
      expect(find.text('1 entry'), findsOneWidget);
      final row = find.byKey(const ValueKey('live-log-2'));
      final text = find.descendant(of: row, matching: find.byType(LiveLogText));
      expect(tester.widget<LiveLogText>(text).compact, width < 480);
      expect(
        find.textContaining('#0 stack.dart:42', findRichText: true),
        findsNothing,
      );
      if (width < 480) {
        expect(find.byKey(const ValueKey('copy-log-2')), findsNothing);
        await tester.longPress(row);
      } else {
        await tester.tap(find.byKey(const ValueKey('copy-log-2')));
      }
      await tester.pumpAndSettle();
      expect(clipboard, failure);
      await tester.tap(find.byKey(const ValueKey('copy-logs')));
      await tester.pumpAndSettle();
      expect(clipboard, failure);
      await tester.enterText(find.byKey(const ValueKey('log-search')), 'STACK');
      await tester.pumpAndSettle();
      expect(find.text('1 entry'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pause-logs')));
      append(store, 'SEVERE stack new record', Level.SEVERE);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('1 entry'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pause-logs')));
      await tester.pumpAndSettle();
      expect(find.text('2 entries'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clear-logs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('empty-logs-icon')), findsOneWidget);
      expect(store.snapshot.length, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('manual scroll stops following until follow is enabled again', (
    tester,
  ) async {
    final store = LiveLogStore();
    addTearDown(store.dispose);
    for (var i = 0; i < 100; i++) {
      append(store, 'log $i${'\nmessage detail' * (i % 7)}');
    }
    await tester.pumpWidget(viewer(store));
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('live-log-list'));
    final scroll = tester.widget<ListView>(list).controller!;
    expect(scroll.position.extentAfter, closeTo(0, 0.5));
    expect(find.byKey(const ValueKey('live-log-100')), findsOneWidget);
    await tester.drag(list, const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, greaterThan(0));
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('follow-logs')))
          .selected,
      isFalse,
    );
    final readingOffset = scroll.offset;
    append(store, 'latest');
    await tester.pump(const Duration(milliseconds: 150));
    expect(scroll.offset, readingOffset);
    await tester.tap(find.byKey(const ValueKey('follow-logs')));
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, closeTo(0, 0.5));
    expect(find.text('latest', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final language in ['en', 'zh']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('compact logs fit $language at text scale $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 1000);
        addTearDown(tester.view.reset);
        final store = LiveLogStore();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          viewer(store, language: language, scale: scale),
        );
        await tester.pumpAndSettle();
        final empty = find.byKey(const ValueKey('empty-logs-icon'));
        expect(
          tester.widget<Icon>(empty).semanticLabel,
          language == 'en' ? 'No logs to display' : '暂无可显示的日志',
        );
        append(
          store,
          'WARNING [Worker] ${'Long message ' * 30}',
          Level.WARNING,
        );
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
        expect(empty, findsNothing);
        final count = find.byKey(const ValueKey('log-entry-count'));
        expect(
          tester.widget<Text>(count).data,
          language == 'en' ? '1 entry' : '1 条',
        );
        expect(tester.widget<Text>(count).textAlign, TextAlign.right);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
