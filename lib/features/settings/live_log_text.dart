import 'package:forui/forui.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/logging/live_log_store.dart';

class LiveLogText extends StatelessWidget {
  const LiveLogText({required this.entry, super.key});

  final LiveLogEntry entry;

  static final _header = RegExp(
    r'^([A-Z]+)(?=[:\s]|$)'
    r'((?:: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?:)?'
    r'(?: \[[^\]\r\n]*\]){0,2} ?)',
  );

  Color _levelColor(FColors colors) {
    final dark = colors.brightness == Brightness.dark;
    if (entry.level >= Level.SHOUT) {
      return dark ? const Color(0xffd8b4fe) : const Color(0xff7e22ce);
    }
    if (entry.level >= Level.SEVERE) {
      return dark ? const Color(0xfffca5a5) : const Color(0xffb91c1c);
    }
    if (entry.level >= Level.WARNING) {
      return dark ? const Color(0xfffcd34d) : const Color(0xff92400e);
    }
    if (entry.level >= Level.INFO) {
      return dark ? const Color(0xff93c5fd) : const Color(0xff1d4ed8);
    }
    if (entry.level >= Level.CONFIG) {
      return dark ? const Color(0xff5eead4) : const Color(0xff0f766e);
    }
    return colors.mutedForeground;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final header = _header.firstMatch(entry.text);
    final hasHeader = header != null && header.group(1) == entry.level.name;
    return SelectableText.rich(
      TextSpan(
        children: hasHeader
            ? [
                TextSpan(
                  text: header.group(1),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: header.group(2),
                  style: TextStyle(color: theme.colors.mutedForeground),
                ),
                TextSpan(text: entry.text.substring(header.end)),
              ]
            : [TextSpan(text: entry.text)],
      ),
      style: theme.typography.body.sm.copyWith(
        fontFamily: 'monospace',
        color: _levelColor(theme.colors),
      ),
    );
  }
}
