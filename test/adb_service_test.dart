import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/adb_service.dart';

void main() {
  test(
    'abilist overrides stale legacy ABI properties and USB metadata is cached',
    () async {
      final adb = CapabilityAdb('''
[ro.build.version.sdk]: [24]
[ro.build.version.release]: [7.0]
[ro.product.cpu.abilist]: [arm64-v8a]
[ro.product.cpu.abi]: [arm64-v8a]
[ro.product.cpu.abi2]: [armeabi-v7a]
''');
      final device = (await adb.getConnectedDevices()).single;
      expect(device.supportedAbis, ['arm64-v8a']);
      expect(device.apiLevel, 24);
      expect(device.androidVersion, '7.0');
      await adb.getConnectedDevices();
      expect(adb.propertyReads, 1);
      adb.connected = false;
      await adb.getConnectedDevices();
      adb.connected = true;
      await adb.getConnectedDevices();
      expect(adb.propertyReads, 2);
    },
  );
  test(
    'legacy ABI fallback works and failed property read retains device',
    () async {
      final adb = CapabilityAdb('''
[ro.product.cpu.abi]: [armeabi-v7a]
[ro.product.cpu.abi2]: [armeabi]
''');
      expect((await adb.getConnectedDevices()).single.supportedAbis, [
        'armeabi-v7a',
        'armeabi',
      ]);
      final failed = CapabilityAdb('');
      final device = (await failed.getConnectedDevices()).single;
      expect(device.apiLevel, isNull);
      expect(device.supportedAbis, isEmpty);
    },
  );
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

  group('parseDeviceProperties', () {
    test('parses capabilities from one getprop response', () {
      const output = '''
[ro.build.version.sdk]: [24]
[ro.build.version.release]: [7.0]
[ro.product.cpu.abi]: [arm64-v8a]
[ro.product.cpu.abi2]: [armeabi-v7a]
[ro.product.cpu.abilist]: [arm64-v8a,armeabi-v7a,armeabi]
[ro.product.model]: [Ruby]
''';

      final properties = parseDeviceProperties(output);
      expect(properties['ro.build.version.sdk'], '24');
      expect(
        properties['ro.product.cpu.abilist'],
        'arm64-v8a,armeabi-v7a,armeabi',
      );
      expect(properties['ro.product.model'], 'Ruby');
    });

    test('ignores malformed and unrelated lines', () {
      final properties = parseDeviceProperties(
        '[ro.product.model]: [Ruby]\nnot a property\n',
      );
      expect(properties, {'ro.product.model': 'Ruby'});
    });
  });
}

class CapabilityAdb extends AdbService {
  final String properties;
  int propertyReads = 0;
  bool connected = true;
  CapabilityAdb(this.properties) : super(onLog: (_, _) {});
  @override
  bool get isMobile => false;
  @override
  Future<ProcessResult> runAdbCommand(
    List<String> args, {
    bool allowFailure = false,
    Duration? timeout,
    bool logOutput = true,
  }) async {
    if (args.first == 'devices') {
      return ProcessResult(
        1,
        0,
        'List of devices attached\n${connected ? 'usb123\tdevice\n' : ''}',
        '',
      );
    }
    propertyReads++;
    return ProcessResult(1, 0, properties, '');
  }
}
