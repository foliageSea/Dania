import '../../shared/responsive_button.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/logging/log_export_service.dart';
import '../../core/logging/runtime_environment_report.dart';
import '../../core/runtime_environment.dart';
import '../../core/settings/settings.dart';
import '../../core/toolbox/toolbox_client.dart';
import '../../shared/toolbox_widgets.dart';
import '../../app/theme.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';
import 'runtime_environment_section.dart';
import 'live_logs_section.dart';

final packageInfoProvider = FutureProvider((ref) => PackageInfo.fromPlatform());

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Object? _error;
  bool _saving = false;
  bool _exportingLogs = false;
  bool _logExportFailed = false;
  LogExportResult? _logExportResult;
  int _settingsTab = 0;
  bool _resettingIdentity = false;

  Future<void> _resetIdentity() async {
    if (!await confirmToolAction(
      context,
      context.tx('重置 ADB 密钥', 'Reset ADB identity'),
      context.tx(
        '断开所有 ADB 连接，并重新配对设备',
        'Disconnect all ADB sessions and pair devices again',
      ),
    ))
      return;
    if (!mounted) return;
    setState(() => _resettingIdentity = true);
    try {
      await ref.read(toolboxProvider).resetIdentity();
      if (mounted) notifyUser(context, context.tx('密钥已重置', 'Identity reset'));
    } catch (error) {
      if (mounted) notifyUser(context, toolError(context, error));
    } finally {
      if (mounted) setState(() => _resettingIdentity = false);
    }
  }

  Future<void> _exportLogs(BuildContext buttonContext) async {
    if (_exportingLogs) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _exportingLogs = true;
      _logExportFailed = false;
      _logExportResult = null;
    });
    try {
      final exporter = ref.read(logExportServiceProvider);
      final report = await RuntimeEnvironmentReport.collect(
        environment: ref.read(runtimeEnvironmentProvider),
        windowSize: MediaQuery.sizeOf(context),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        appLocale: Localizations.localeOf(context).toLanguageTag(),
        packageInfo: () => ref.read(packageInfoProvider.future),
      );
      final result = await exporter.export(
        sharePositionOrigin: origin,
        environmentReport: report,
      );
      if (mounted) setState(() => _logExportResult = result);
    } catch (_) {
      if (mounted) setState(() => _logExportFailed = true);
    } finally {
      if (mounted) setState(() => _exportingLogs = false);
    }
  }

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(settingsProvider.notifier).update(change);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    return PageContent(
      children: [
        PageHeading(l.settings),
        if (_error != null) ...[
          ErrorNotice(_error!),
          const SizedBox(height: 16),
        ],
        FTabs(
          key: const ValueKey('settings-tabs'),
          scrollable: true,
          control: FTabControl.lifted(
            index: _settingsTab,
            onChange: (index) => setState(() => _settingsTab = index),
          ),
          children: [
            FTabEntry(
              label: Text(l.appearance),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.theme),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (i, value) in ThemeMode.values.indexed)
                          FButton(
                            builder: responsiveButtonContent,
                            mainAxisSize: MainAxisSize.min,
                            variant: settings.themeMode == value
                                ? .primary
                                : .outline,
                            selected: settings.themeMode == value,
                            onPress: _saving
                                ? null
                                : () => _update(
                                    (s) => s.copyWith(themeMode: value),
                                  ),
                            child: Text([l.system, l.light, l.dark][i]),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(l.themeColor),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final color in AppThemeColor.values)
                          FButton(
                            key: ValueKey('theme-color-${color.name}'),
                            builder: responsiveButtonContent,
                            mainAxisSize: MainAxisSize.min,
                            variant: settings.themeColor == color
                                ? .primary
                                : .outline,
                            selected: settings.themeColor == color,
                            onPress: _saving
                                ? null
                                : () => _update(
                                    (s) => s.copyWith(themeColor: color),
                                  ),
                            prefix: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color.primary(
                                  context.theme.colors.brightness,
                                ),
                                border: Border.all(
                                  color: settings.themeColor == color
                                      ? context.theme.colors.primaryForeground
                                      : context.theme.colors.border,
                                ),
                              ),
                            ),
                            child: Text(switch (color) {
                              AppThemeColor.neutral => l.colorNeutral,
                              AppThemeColor.blue => l.colorBlue,
                              AppThemeColor.green => l.colorGreen,
                              AppThemeColor.violet => l.colorViolet,
                              AppThemeColor.orange => l.colorOrange,
                              AppThemeColor.rose => l.colorRose,
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(l.radiusScale),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final radius in [0.0, 0.5, 1.0, 1.5, 2.0])
                          FButton(
                            key: ValueKey('radius-scale-$radius'),
                            builder: responsiveButtonContent,
                            mainAxisSize: MainAxisSize.min,
                            variant: settings.radiusScale == radius
                                ? .primary
                                : .outline,
                            selected: settings.radiusScale == radius,
                            onPress: _saving
                                ? null
                                : () => _update(
                                    (s) => s.copyWith(radiusScale: radius),
                                  ),
                            child: Text(
                              '${radius.toStringAsFixed(radius % 1 == 0 ? 0 : 1)}×',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(l.fontSize),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (scale, label) in [
                          (0.8, l.fontSizeSmall),
                          (1.0, l.fontSizeStandard),
                          (1.2, l.fontSizeLarge),
                        ])
                          FButton(
                            key: ValueKey('font-scale-$scale'),
                            builder: responsiveButtonContent,
                            mainAxisSize: MainAxisSize.min,
                            variant: settings.fontScale == scale
                                ? .primary
                                : .outline,
                            selected: settings.fontScale == scale,
                            onPress: _saving
                                ? null
                                : () => _update(
                                    (s) => s.copyWith(fontScale: scale),
                                  ),
                            child: Text(label),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      key: const ValueKey('font-size-preview'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.theme.colors.muted,
                        borderRadius: context.theme.style.borderRadius.md,
                        border: Border.all(color: context.theme.colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l.fontSizePreview} (${(settings.fontScale * 100).round()}%)',
                            style: context.theme.typography.body.sm.copyWith(
                              color: context.theme.colors.mutedForeground,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.sampleText,
                            style: context.theme.typography.body.md,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            FTabEntry(
              label: Text(l.general),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.language),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (value, label) in [
                          ('system', l.system),
                          ('zh', '简体中文'),
                          ('en', 'English'),
                        ])
                          FButton(
                            builder: responsiveButtonContent,
                            mainAxisSize: MainAxisSize.min,
                            variant: settings.language == value
                                ? .primary
                                : .outline,
                            onPress: _saving
                                ? null
                                : () => _update(
                                    (s) => s.copyWith(language: value),
                                  ),
                            child: Text(label),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    FSwitch(
                      label: Text(l.compactSidebar),
                      value: settings.compactSidebar,
                      enabled: !_saving,
                      onChange: (value) =>
                          _update((s) => s.copyWith(compactSidebar: value)),
                    ),
                  ],
                ),
              ),
            ),
            FTabEntry(
              label: Text(context.tx('ADB', 'ADB')),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FButton(
                      variant: .destructive,
                      onPress:
                          _resettingIdentity ||
                              !ref.watch(toolboxProvider).supported
                          ? null
                          : _resetIdentity,
                      child: Text(
                        context.tx('重置 ADB 密钥', 'Reset ADB identity'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            FTabEntry(
              label: Text(l.logs),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(
                      builder: (buttonContext) => FButton(
                        key: const ValueKey('export-logs'),
                        builder: responsiveButtonContent,
                        variant: .outline,
                        prefix: const Icon(FLucideIcons.download),
                        onPress: _exportingLogs
                            ? null
                            : () => _exportLogs(buttonContext),
                        child: Text(
                          _exportingLogs ? l.exportingLogs : l.exportLogs,
                        ),
                      ),
                    ),
                    if (_logExportFailed) ...[
                      const SizedBox(height: 16),
                      FAlert(
                        variant: .destructive,
                        title: Text(l.logExportError),
                      ),
                    ],
                    if (_logExportResult != null &&
                        _logExportResult != LogExportResult.cancelled) ...[
                      const SizedBox(height: 16),
                      Text(switch (_logExportResult!) {
                        LogExportResult.empty => l.noLogsToExport,
                        LogExportResult.saved => l.logsExported,
                        LogExportResult.shared => l.logsShared,
                        LogExportResult.presented => l.logShareOpened,
                        LogExportResult.cancelled => '',
                      }),
                    ],
                    const LiveLogsSection(),
                  ],
                ),
              ),
            ),
            FTabEntry(
              label: Text(l.runtimeEnvironment),
              child: const Surface(child: RuntimeEnvironmentSection()),
            ),
            FTabEntry(
              label: Text(l.about),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ref
                        .watch(packageInfoProvider)
                        .when(
                          data: (info) => Text(
                            '${l.version} ${info.version} (${info.buildNumber})',
                          ),
                          loading: () => Text(l.loading),
                          error: (e, _) => ErrorNotice(
                            e,
                            onRetry: () => ref.invalidate(packageInfoProvider),
                          ),
                        ),
                    const SizedBox(height: 16),
                    for (final (label, url) in [
                      ('Shizuku', 'https://shizuku.rikka.app/'),
                      ('scrcpy', 'https://github.com/Genymobile/scrcpy'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FButton(
                          builder: responsiveButtonContent,
                          mainAxisSize: MainAxisSize.min,
                          variant: .outline,
                          onPress: () => openDocumentation(context, url),
                          suffix: const Icon(FLucideIcons.externalLink),
                          child: Text(label),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
