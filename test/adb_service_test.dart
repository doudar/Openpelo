import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/adb_service.dart';

void main() {
  test(
    'parses mDNS names containing spaces and ignores device-list headers',
    () {
      expect(parseAdbDeviceEntry('adb-123 (2)._adb-tls-connect._tcp\tdevice'), (
        'adb-123 (2)._adb-tls-connect._tcp',
        'device',
      ));
      expect(parseAdbDeviceEntry('192.168.1.172:5555\tdevice'), (
        '192.168.1.172:5555',
        'device',
      ));
      expect(parseAdbDeviceEntry('usb123\tunauthorized'), (
        'usb123',
        'unauthorized',
      ));
      expect(parseAdbDeviceEntry('List of devices attached'), isNull);
    },
  );
  group('parsePlatformToolsRevision', () {
    test('reads the package revision', () {
      const properties = '''
Pkg.Desc = Android SDK Platform-Tools
Pkg.Revision = 37.0.1
''';

      expect(parsePlatformToolsRevision(properties), '37.0.1');
    });

    test('returns null when the revision is absent', () {
      expect(
        parsePlatformToolsRevision('Pkg.Desc = Android SDK Platform-Tools'),
        isNull,
      );
    });
  });
}
