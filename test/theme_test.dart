import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dania/app/theme.dart';
import 'package:dania/core/settings/settings.dart';

void main() {
  test('MiSans preserves theme tokens and Android system bar styles', () {
    for (final brightness in Brightness.values) {
      for (final touch in [true, false]) {
        for (final color in AppThemeColor.values) {
          for (final scale in [0.0, 1.0, 2.0]) {
            final theme = createAppTheme(
              AppSettings(themeColor: color, radiusScale: scale),
              brightness: brightness,
              touch: touch,
            );
            expect(theme.typography.body.md.fontFamily, appFontFamily);
            expect(theme.typography.display.lg.fontFamily, appFontFamily);
            expect(theme.colors.primary, color.primary(brightness));
            expect(
              theme.style.focusedOutlineStyle.borderRadius,
              BorderRadius.circular(10 * scale),
            );
            final overlay = theme.colors.systemOverlayStyle;
            expect(overlay.statusBarColor, const Color(0x00000000));
            expect(overlay.systemNavigationBarColor, const Color(0x00000000));
            expect(overlay.systemStatusBarContrastEnforced, isFalse);
            expect(overlay.systemNavigationBarContrastEnforced, isFalse);
          }
        }
      }
    }
  });
}
