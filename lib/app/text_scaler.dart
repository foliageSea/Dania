import 'package:flutter/widgets.dart';

/// Applies the app preference without replacing the system's scaling curve.
final class AppTextScaler extends TextScaler {
  const AppTextScaler(this.systemScaler, this.fontScale)
    : assert(fontScale > 0 && fontScale < double.infinity);

  final TextScaler systemScaler;
  final double fontScale;

  @override
  double scale(double fontSize) => systemScaler.scale(fontSize) * fontScale;

  // Required by TextScaler for compatibility with legacy consumers.
  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.systemScaler == systemScaler &&
      other.fontScale == fontScale;

  @override
  int get hashCode => Object.hash(systemScaler, fontScale);
}
