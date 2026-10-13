import 'package:dania/core/toolbox/device_information.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'formats Android information with battery scale and display override',
    () {
      final info = DeviceInformation.parse('''Pixel 9
Google
16
36
uid=2000(shell) gid=2000(shell) groups=2000(shell)
Physical size: 1080x2424
Override size: 900x2020
Current Battery Service state:
  AC powered: false
  USB powered: true
  Wireless powered: false
  status: 2
  level: 150
  scale: 200
  voltage: 4250
  temperature: 315
  technology: Li-ion
''');
      expect(info.model, 'Pixel 9');
      expect(info.manufacturer, 'Google');
      expect(info.androidVersion, '16');
      expect(info.sdkVersion, '36');
      expect(info.uid, '2000');
      expect(info.user, 'shell');
      expect(info.physicalSize, '1080x2424');
      expect(info.overrideSize, '900x2020');
      expect(info.batteryPercent, 75);
      expect(info.batteryStatus, 2);
      expect(info.batteryTemperature, 31.5);
      expect(info.batteryVoltage, 4.25);
      expect(info.powerSources, ['USB']);
    },
  );

  test('preserves missing properties and tolerates unavailable commands', () {
    final info = DeviceInformation.parse(
      'Phone\r\n\r\n16\r\n36\r\nuid=0(root)\r\n'
      'wm: permission denied\r\n  level: 80\r\n  scale: 0\r\n',
    );
    expect(info.manufacturer, isNull);
    expect(info.androidVersion, '16');
    expect(info.uid, '0');
    expect(info.physicalSize, isNull);
    expect(info.batteryPercent, isNull);
    expect(info.batteryTemperature, isNull);
    expect(info.powerSources, isEmpty);
    expect(DeviceInformation.parse('').model, isNull);
  });
}
