import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/logging/live_log_store.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import 'live_log_controller.dart';
import 'live_log_text.dart';

class LiveLogsSection extends ConsumerStatefulWidget {
  const LiveLogsSection({super.key});

  @override
  ConsumerState<LiveLogsSection> createState() => _LiveLogsSectionState();
}

class _LiveLogsSectionState extends ConsumerState<LiveLogsSection> {
  late final LiveLogController _logs;
  final _scroll = ScrollController();
  bool _following = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _logs = LiveLogController(ref.read(liveLogStoreProvider));
    _logs.addListener(_scheduleFollow);
    _scheduleFollow();
  }

  void _scheduleFollow() {
    if (!_following || _logs.paused || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_following || _logs.paused || !_scroll.hasClients) {
        return;
      }
      final position = _scroll.position;
      if ((position.maxScrollExtent - position.pixels).abs() > 0.5) {
        _scroll.jumpTo(position.maxScrollExtent);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) notifyUser(context, context.l10n.copied);
    } catch (_) {
      if (mounted) notifyUser(context, context.l10n.logCopyError);
    }
  }

  @override
  void dispose() {
    _logs.removeListener(_scheduleFollow);
    _logs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _logs,
    builder: (context, _) {
      final l = context.l10n;
      final entries = _logs.entries;
      final indices = {
        for (var i = 0; i < entries.length; i++) 'live-log-${entries[i].id}': i,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = FTextField(
                key: const ValueKey('log-search'),
                hint: l.searchLogs,
                control: .managed(
                  onChange: (value) => _logs.setQuery(value.text),
                ),
              );
              final level = FSelect<Level>.rich(
                key: const ValueKey('log-level'),
                control: .lifted(
                  value: _logs.minimumLevel,
                  onChange: (value) =>
                      _logs.setMinimumLevel(value ?? Level.ALL),
                ),
                format: (value) =>
                    value == Level.ALL ? l.all : '${value.name}+',
                children: [
                  FSelectItem(title: Text(l.all), value: Level.ALL),
                  for (final value in [
                    Level.FINE,
                    Level.INFO,
                    Level.WARNING,
                    Level.SEVERE,
                    Level.SHOUT,
                  ])
                    FSelectItem(title: Text('${value.name}+'), value: value),
                ],
              );
              if (constraints.maxWidth < 480) {
                return Column(
                  children: [search, const SizedBox(height: 8), level],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  SizedBox(width: 160, child: level),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FButton(
                key: const ValueKey('pause-logs'),
                builder: responsiveButtonContent,
                mainAxisSize: MainAxisSize.min,
                variant: .outline,
                onPress: _logs.togglePaused,
                prefix: Icon(
                  _logs.paused ? FLucideIcons.play : FLucideIcons.pause,
                ),
                child: Text(_logs.paused ? l.resumeLogs : l.pauseLogs),
              ),
              FButton(
                key: const ValueKey('follow-logs'),
                builder: responsiveButtonContent,
                mainAxisSize: MainAxisSize.min,
                variant: _following ? .primary : .outline,
                selected: _following,
                onPress: () {
                  setState(() => _following = !_following);
                  _scheduleFollow();
                },
                child: Text(l.autoScrollLogs),
              ),
              FButton(
                key: const ValueKey('copy-logs'),
                builder: responsiveButtonContent,
                mainAxisSize: MainAxisSize.min,
                variant: .outline,
                onPress: entries.isEmpty ? null : () => _copy(_logs.copyText),
                child: Text(l.copyVisibleLogs),
              ),
              FButton(
                key: const ValueKey('clear-logs'),
                builder: responsiveButtonContent,
                mainAxisSize: MainAxisSize.min,
                variant: .outline,
                onPress: _logs.clearView,
                child: Text(l.clearLogView),
              ),
              Text(l.logEntryCount(entries.length)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: (MediaQuery.sizeOf(context).height * 0.45).clamp(240, 600),
            decoration: BoxDecoration(
              border: Border.all(color: context.theme.colors.border),
              borderRadius: context.theme.style.borderRadius.md,
            ),
            clipBehavior: Clip.antiAlias,
            child: entries.isEmpty
                ? Center(child: Text(l.noLiveLogs))
                : NotificationListener<ScrollMetricsNotification>(
                    onNotification: (notification) {
                      // Lazy variable-height rows refine their extent as they
                      // are laid out; resizing can change it as well.
                      if (notification.depth == 0) _scheduleFollow();
                      return false;
                    },
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null &&
                            _following) {
                          setState(() => _following = false);
                        } else if (notification is UserScrollNotification &&
                            notification.direction != ScrollDirection.idle &&
                            _following) {
                          setState(() => _following = false);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        key: const ValueKey('live-log-list'),
                        controller: _scroll,
                        padding: EdgeInsets.zero,
                        itemCount: entries.length,
                        findChildIndexCallback: (key) =>
                            key is ValueKey<String> ? indices[key.value] : null,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return Container(
                            key: ValueKey('live-log-${entry.id}'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: context.theme.colors.border,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: LiveLogText(entry: entry)),
                                FButton.icon(
                                  key: ValueKey('copy-log-${entry.id}'),
                                  variant: .ghost,
                                  size: .xs,
                                  semanticsLabel: l.copyLogEntry,
                                  onPress: () => _copy(entry.text),
                                  child: const Icon(
                                    FLucideIcons.copy,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
