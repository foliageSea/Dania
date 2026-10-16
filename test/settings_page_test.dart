import 'dart:async';

import 'package:dania/app/app.dart';
import 'package:dania/app/router.dart';
import 'package:dania/core/app_exception.dart';
import 'package:dania/core/logging/live_log_store.dart';
import 'package:dania/core/logging/log_export_service.dart';
import 'package:dania/core/logging/runtime_environment_report.dart';
import 'package:dania/core/settings/settings.dart';
import 'package:dania/core/toolbox/toolbox_client.dart';
import 'package:dania/features/settings/live_logs_section.dart';
import 'package:dania/features/settings/settings_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MemorySettings implements SettingsRepository {
  AppSettings value = const AppSettings(language: 'en');
  bool fail = false;

  @override
  Future<AppSettings> load() async => value;

  @override
  Future<void> save(AppSettings settings) async {
    if (fail) throw const AppException(FailureKind.storage);
    value = settings;
  }
}

class FakeToolbox extends ToolboxClient {
  FakeToolbox({this.supported = true});

  @override
  final bool supported;

  @override
  Stream<Map<Object?, Object?>> get events => const Stream.empty();

  int resets = 0;
  Completer<void>? pendingReset;

  @override
  Future<void> resetIdentity() async {
    resets++;
    await pendingReset?.future;
  }
}

class FakeLogExporter implements LogExportService {
  LogExportResult result = LogExportResult.empty;
  bool fail = false;
  RuntimeEnvironmentReport? report;

  @override
  Future<LogExportResult> export({
    Rect? sharePositionOrigin,
    RuntimeEnvironmentReport? environmentReport,
  }) async {
    report = environmentReport;
    if (fail) throw StateError('export failed');
    return result;
  }
}

ProviderContainer appContainer({
  AppSettings settings = const AppSettings(language: 'en'),
  MemorySettings? repository,
  FakeToolbox? toolbox,
  FakeLogExporter? exporter,
}) {
  final logs = LiveLogStore();
  final container = ProviderContainer(
    overrides: [
      initialSettingsProvider.overrideWithValue(settings),
      settingsRepositoryProvider.overrideWithValue(
        repository ?? MemorySettings(),
      ),
      toolboxProvider.overrideWithValue(toolbox ?? FakeToolbox()),
      liveLogStoreProvider.overrideWithValue(logs),
      logExportServiceProvider.overrideWithValue(exporter ?? FakeLogExporter()),
      packageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'Dania',
          packageName: 'dania',
          version: '0.1.0',
          buildNumber: '1',
        ),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    logs.dispose();
  });
  container.read(routerProvider).go('/settings');
  return container;
}

Future<void> showApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const DaniaApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void setView(WidgetTester tester, double width, {double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  for (final width in [390.0, 1200.0]) {
    for (final language in ['en', 'zh']) {
      testWidgets('general keeps language preference at $width in $language', (
        tester,
      ) async {
        setView(tester, width);
        final repository = MemorySettings();
        final container = appContainer(
          repository: repository,
          settings: AppSettings(language: language),
        );
        await showApp(tester, container);
        final general = find.text(language == 'en' ? 'General' : '常规');
        final appearance = find.text(language == 'en' ? 'Appearance' : '外观');
        expect(
          tester.getTopLeft(general).dx,
          lessThan(tester.getTopLeft(appearance).dx),
        );
        expect(find.byKey(const ValueKey('language-select')), findsOneWidget);
        expect(find.byType(FSwitch), findsNothing);
        await tester.tap(find.byKey(const ValueKey('language-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(language == 'en' ? '简体中文' : 'English').last);
        await tester.pumpAndSettle();
        final next = language == 'en' ? 'zh' : 'en';
        expect(container.read(settingsProvider).language, next);
        expect((await repository.load()).language, next);
        await choose(tester, find.text(next == 'en' ? 'Appearance' : '外观'));
        expect(find.byKey(const ValueKey('theme-color-blue')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'font tiers update, persist and retain state on save failure at $width',
      (tester) async {
        setView(tester, width, scale: 1.25);
        final repository = MemorySettings();
        final container = appContainer(repository: repository);
        await showApp(tester, container);
        await choose(tester, find.text('Appearance'));
        for (final (tier, percent) in [(0.8, 65), (1.0, 80), (1.2, 100)]) {
          await choose(tester, find.byKey(ValueKey('font-scale-$tier')));
          expect(container.read(settingsProvider).fontScale, tier);
          expect((await repository.load()).fontScale, tier);
          expect(find.text('Preview ($percent%)'), findsOneWidget);
          expect(
            MediaQuery.textScalerOf(tester.element(find.byType(SettingsPage)))
                .scale(16),
            closeTo(16 * 1.25 * percent / 100, 1e-9),
          );
        }
        repository.fail = true;
        await choose(tester, find.byKey(const ValueKey('font-scale-0.8')));
        expect(container.read(settingsProvider).fontScale, 1.2);
        expect(find.textContaining('Could not save'), findsOneWidget);
        repository.fail = false;
        await choose(tester, find.byKey(const ValueKey('font-scale-0.8')));
        expect(container.read(settingsProvider).fontScale, 0.8);
        final restored = AppSettings.fromJson(
          (await repository.load()).toJson(),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final restarted = appContainer(settings: restored);
        await showApp(tester, restarted);
        expect(restarted.read(settingsProvider).fontScale, 0.8);
        expect(
          MediaQuery.textScalerOf(tester.element(find.byType(SettingsPage)))
              .scale(16),
          closeTo(16 * 1.25 * 0.65, 1e-9),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('font percentage reacts to device pixel ratio changes', (
    tester,
  ) async {
    setView(tester, 390);
    final container = appContainer();
    await showApp(tester, container);
    await choose(tester, find.text('Appearance'));
    for (final (ratio, percent) in [(1.0, 80), (2.0, 100), (3.0, 72)]) {
      tester.view.physicalSize = Size(390 * ratio, 1000 * ratio);
      tester.view.devicePixelRatio = ratio;
      await tester.pumpAndSettle();
      expect(find.text('Preview ($percent%)'), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(SettingsPage)))
            .scale(16),
        closeTo(16 * percent / 100, 1e-9),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final language in ['en', 'zh']) {
      testWidgets(
        'settings tabs fit $width in $language with large text and keyboard',
        (tester) async {
          setView(tester, width, scale: 2);
          final exporter = FakeLogExporter();
          final container = appContainer(
            exporter: exporter,
            settings: AppSettings(language: language),
          );
          await showApp(tester, container);
          for (final title
              in language == 'en'
                  ? [
                      'Appearance',
                      'ADB',
                      'Runtime environment',
                      'About this template',
                      'Logs',
                    ]
                  : ['外观', 'ADB', '运行环境', '关于模板', '日志']) {
            await choose(tester, find.text(title));
            expect(tester.takeException(), isNull, reason: title);
          }
          expect(find.byType(LiveLogsSection), findsOneWidget);
          final tabs = tester.widget<FTabs>(
            find.byKey(const ValueKey('settings-tabs')),
          );
          expect(tabs.expands, isTrue);
          expect(tabs.contentPhysics, isA<NeverScrollableScrollPhysics>());
          tester.view.viewInsets = const FakeViewPadding(bottom: 600);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          await choose(tester, find.byKey(const ValueKey('export-logs')));
          expect(exporter.report!.appLocale, language);
          expect(exporter.report!.appVersion, '0.1.0');
          exporter.fail = true;
          await choose(tester, find.byKey(const ValueKey('export-logs')));
          expect(tester.takeException(), isNull);
          exporter.fail = false;
          exporter.result = LogExportResult.cancelled;
          await choose(tester, find.byKey(const ValueKey('export-logs')));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  for (final language in ['en', 'zh']) {
    testWidgets('about keeps business links and opens notices in $language', (
      tester,
    ) async {
      setView(tester, 390, scale: 2);
      final container = appContainer(settings: AppSettings(language: language));
      await showApp(tester, container);
      await choose(
        tester,
        find.text(language == 'en' ? 'About this template' : '关于模板'),
      );
      expect(find.text('Shizuku'), findsOneWidget);
      expect(find.text('scrcpy'), findsOneWidget);
      await choose(tester, find.byKey(const ValueKey('font-notice')));
      expect(find.textContaining('MiSans'), findsWidgets);
      expect(find.byKey(const ValueKey('font-license-link')), findsOneWidget);
      await choose(tester, find.text(language == 'en' ? 'Close' : '关闭'));
      expect(find.byKey(const ValueKey('font-license-link')), findsNothing);
      await choose(tester, find.byKey(const ValueKey('open-source-licenses')));
      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text('Dania'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'ADB identity reset still confirms and disables duplicate requests',
    (tester) async {
      setView(tester, 390);
      final toolbox = FakeToolbox()..pendingReset = Completer<void>();
      final container = appContainer(toolbox: toolbox);
      await showApp(tester, container);
      await choose(tester, find.text('ADB'));
      await choose(tester, find.text('Reset ADB identity'));
      await choose(tester, find.text('Cancel'));
      expect(toolbox.resets, 0);
      await choose(tester, find.text('Reset ADB identity'));
      await choose(tester, find.text('Confirm'));
      expect(toolbox.resets, 1);
      final button = find.ancestor(
        of: find.text('Reset ADB identity'),
        matching: find.byType(FButton),
      );
      expect(tester.widget<FButton>(button).onPress, isNull);
      toolbox.pendingReset!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<FButton>(button).onPress, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('ADB identity reset stays disabled on unsupported platforms', (
    tester,
  ) async {
    setView(tester, 390);
    final container = appContainer(toolbox: FakeToolbox(supported: false));
    await showApp(tester, container);
    await choose(tester, find.text('ADB'));
    final button = find.ancestor(
      of: find.text('Reset ADB identity'),
      matching: find.byType(FButton),
    );
    expect(tester.widget<FButton>(button).onPress, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
