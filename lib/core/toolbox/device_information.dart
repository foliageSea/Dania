class DeviceInformation {
  DeviceInformation.parse(String output) {
    final lines = output.replaceAll('\r\n', '\n').split('\n');
    String? header(int index) {
      if (index >= lines.length) return null;
      final value = lines[index].trim();
      return value.isEmpty ? null : value;
    }

    model = header(0);
    manufacturer = header(1);
    androidVersion = header(2);
    sdkVersion = header(3);
    identity = RegExp(
      r'^uid=(\d+)(?:\(([^)]+)\))?',
      multiLine: true,
    ).firstMatch(output);
    physicalSize = _value(output, 'Physical size');
    overrideSize = _value(output, 'Override size');
    final level = int.tryParse(_value(output, 'level') ?? '');
    final scale = int.tryParse(_value(output, 'scale') ?? '');
    batteryPercent = level != null && level >= 0 && scale != null && scale > 0
        ? (level / scale * 100).round().clamp(0, 100)
        : null;
    batteryStatus = int.tryParse(_value(output, 'status') ?? '');
    final temperature = int.tryParse(_value(output, 'temperature') ?? '');
    batteryTemperature = temperature == null ? null : temperature / 10;
    final voltage = int.tryParse(_value(output, 'voltage') ?? '');
    batteryVoltage = voltage == null || voltage <= 0 ? null : voltage / 1000;
    batteryTechnology = _value(output, 'technology');
    powerSources = [
      for (final source in ['AC', 'USB', 'Wireless', 'Dock'])
        if (_value(output, '$source powered') == 'true') source,
    ];
  }

  late final String? model;
  late final String? manufacturer;
  late final String? androidVersion;
  late final String? sdkVersion;
  late final RegExpMatch? identity;
  late final String? physicalSize;
  late final String? overrideSize;
  late final int? batteryPercent;
  late final int? batteryStatus;
  late final double? batteryTemperature;
  late final double? batteryVoltage;
  late final String? batteryTechnology;
  late final List<String> powerSources;

  String? get uid => identity?.group(1);
  String? get user => identity?.group(2);

  static String? _value(String output, String key) {
    final value = RegExp(
      '^\\s*${RegExp.escape(key)}:[ \\t]*([^\\r\\n]*)',
      multiLine: true,
    ).firstMatch(output)?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
