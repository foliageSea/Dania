import 'package:dania/app/theme.dart';
import 'package:dania/app/router.dart';
import 'package:dania/core/settings/settings.dart';
import 'package:dania/core/toolbox/device_state.dart';
import 'package:dania/core/toolbox/models.dart';
import 'package:dania/core/toolbox/toolbox_client.dart';
import 'package:dania/features/apps/apps_page.dart';
import 'package:dania/features/files/files_page.dart';
import 'package:dania/features/devices/devices_page.dart';
import 'package:dania/features/mirror/mirror_page.dart';
import 'package:dania/features/terminal/terminal_page.dart';
import 'package:dania/features/tools/tools_page.dart';
import 'package:dania/l10n/generated/app_localizations.dart';
import 'package:dania/shared/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _LayoutClient extends ToolboxClient {
  @override
  Stream<Map<Object?, Object?>> get events => const Stream.empty();

  @override
  Future<ShizukuStatus> status() async => const ShizukuStatus();

  @override
  Future<List<Device>> devices() async => const [
    Device(
      id: 'remote',
      name: 'Pixel 9',
      address: '192.168.100.100:5555',
      local: false,
    ),
  ];

  @override
  Future<String> info(String id) async => '''Pixel 9
Google
16
36
uid=2000(shell)
Physical size: 1080x2424
  level: 75
  scale: 100
  status: 3
  temperature: 315
  voltage: 4250
''';

  @override
  Future<List<InstalledApp>> apps(String id) async => const [
    InstalledApp(
      packageName: 'com.example.a.long.application.package',
      apkPath: '/data/app/base.apk',
      enabled: false,
      system: true,
    ),
  ];

  @override
  Future<List<RemoteFile>> files(String id, String path) async => [
    const RemoteFile(
      name: 'a-long-file-name-with-a-photo.jpg',
      mode: 0x8000,
      size: 123456,
      modified: 0,
    ),
    const RemoteFile(name: 'Documents', mode: 0x4000, size: 0, modified: 0),
    ...List.generate(
      80,
      (index) => RemoteFile(
        name: 'file-${index.toString().padLeft(3, '0')}.txt',
        mode: 0x8000,
        size: 1024,
        modified: 0,
      ),
    ),
  ];
}

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('tool routes open outside main navigation at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          toolboxProvider.overrideWithValue(_LayoutClient()),
          selectedDeviceProvider.overrideWith(_SelectedDevice.new),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      router.go('/tools');
      final theme = createAppTheme(
        const AppSettings(),
        brightness: Brightness.dark,
        touch: width < 600,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              ...AppLocalizations.localizationsDelegates,
              ...FLocalizations.localizationsDelegates,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.only(top: 24, bottom: 24)),
              child: FTheme(
                data: theme,
                child: FTooltipGroup(child: child!),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final navigation = width < 600
          ? find.byType(FBottomNavigationBar)
          : find.byType(FSidebar);
      expect(navigation, findsOneWidget);
      for (final (title, route) in [
        ('Terminal', '/tools/terminal'),
        ('Applications', '/tools/apps'),
        ('Files', '/tools/files'),
      ]) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, route);
        expect(navigation, findsNothing);
        expect(find.byType(FHeaderAction), findsOneWidget);
        expect(
          tester.getRect(find.byType(PageSafeArea)),
          Rect.fromLTWH(0, 0, width, 900),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(FHeaderAction));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/tools');
        expect(navigation, findsOneWidget);
      }
      router.go('/tools/files');
      await tester.pumpAndSettle();
      expect(navigation, findsNothing);
      await tester.tap(find.byType(FHeaderAction));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/tools');
      expect(navigation, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (width, scale, locale) in [
    (320.0, 1.6, const Locale('zh')),
    (390.0, 1.0, const Locale('zh')),
    (1200.0, 1.0, const Locale('en')),
  ]) {
    testWidgets('tool pages fit width $width at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = createAppTheme(
        const AppSettings(),
        brightness: Brightness.dark,
        touch: width < 600,
      );

      for (final page in [
        const ToolsPage(),
        const TerminalPage(),
        const AppsPage(),
        const FilesPage(),
        const DevicesPage(),
        const MirrorPage(deviceId: 'remote'),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              toolboxProvider.overrideWithValue(_LayoutClient()),
              selectedDeviceProvider.overrideWith(_SelectedDevice.new),
              endpointsProvider.overrideWith(_Endpoints.new),
            ],
            child: MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: [
                ...AppLocalizations.localizationsDelegates,
                ...FLocalizations.localizationsDelegates,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: FTheme(
                  data: theme,
                  child: FTooltipGroup(child: child!),
                ),
              ),
              home: page,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.runtimeType} at $width',
        );
        if (page is ToolsPage) {
          final terminal = tester.getRect(
            find.text(locale.languageCode == 'zh' ? '终端' : 'Terminal'),
          );
          final apps = tester.getRect(
            find.text(locale.languageCode == 'zh' ? '应用管理' : 'Applications'),
          );
          expect(terminal.top, apps.top);
          expect(apps.left, greaterThan(terminal.right));
          expect(find.text('75%'), findsOneWidget);
          expect(find.text('31.5 °C'), findsOneWidget);
        }
        if (page is FilesPage) {
          final path = find.byType(FBreadcrumb);
          final pathRect = tester.getRect(path);
          final list = find.byType(ListView);
          final deleteButton = find
              .widgetWithText(
                FButton,
                locale.languageCode == 'zh' ? '删除' : 'Delete',
              )
              .first;
          final card = find
              .ancestor(of: deleteButton, matching: find.byType(Surface))
              .first;
          expect(
            tester.getRect(deleteButton).right,
            closeTo(tester.getRect(card).right - 12, 1),
          );
          final scrollable = find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.text('file-030.txt'),
            300,
            scrollable: scrollable,
          );
          expect(tester.getRect(path), pathRect);
          expect(
            tester.state<ScrollableState>(scrollable).position.pixels,
            greaterThan(0),
          );
          await tester.tap(
            find.widgetWithText(
              FButton,
              locale.languageCode == 'zh' ? '快捷路径' : 'Shortcuts',
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('/data/local/tmp'));
          await tester.pumpAndSettle();
          expect(
            tester
                .state<ScrollableState>(
                  find.descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  ),
                )
                .position
                .pixels,
            0,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });
  }
}

class _SelectedDevice extends SelectedDevice {
  @override
  String? build() => 'remote';
}

class _Endpoints extends EndpointsController {
  @override
  Future<List<SavedEndpoint>> build() async => [
    SavedEndpoint('192.168.100.100', 5555),
  ];
}
