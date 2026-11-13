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

  group('package names reach the device shell quoted', () {
    test('launch, force stop and clear data quote the package name', () async {
      final adb = CapturingAdb();

      await adb.launchPackage('usb1', 'com.example.app');
      await adb.forceStopPackage('usb1', 'com.example.app');
      await adb.clearPackageData('usb1', 'com.example.app');

      expect(adb.commands, [
        [
          '-s',
          'usb1',
          'shell',
          "monkey -p 'com.example.app' -c android.intent.category.LAUNCHER 1",
        ],
        ['-s', 'usb1', 'shell', "am force-stop 'com.example.app'"],
        ['-s', 'usb1', 'shell', "pm clear 'com.example.app'"],
      ]);
    });

    test(
      'uninstall for user 0 and app settings quote the package name',
      () async {
        final adb = CapturingAdb();

        await adb.uninstallPackageUser0('usb1', 'com.example.app');
        await adb.openAppSettings('usb1', 'com.example.app');

        expect(adb.commands[0].last, "'com.example.app'");
        expect(adb.commands[1].last, "'package:com.example.app'");
      },
    );

    test('launcher components and quick settings tiles are quoted', () async {
      final adb = CapturingAdb();

      await adb.setDefaultLauncher('usb1', r'com.example.launcher/.Main$Home');
      expect(adb.commands.single.last, r"'com.example.launcher/.Main$Home'");

      adb.commands.clear();
      adb.stdout = 'wifi,bt';
      await adb.enableWirelessDebugging('usb1');
      expect(adb.commands[1].last, "'wifi,bt,wireless_debugging'");
    });

    test(
      'invalid package names are rejected before any command runs',
      () async {
        final adb = CapturingAdb();
        const hostile = 'com.example.app; rm -rf /sdcard';

        expect(await adb.launchPackage('usb1', hostile), isFalse);
        expect(await adb.forceStopPackage('usb1', hostile), isFalse);
        expect(await adb.clearPackageData('usb1', hostile), isFalse);
        expect(await adb.openAppSettings('usb1', hostile), isFalse);
        expect(
          await adb.uninstallPackage('usb1', hostile),
          startsWith('Error'),
        );
        expect(
          await adb.uninstallPackageUser0('usb1', hostile),
          startsWith('Error'),
        );

        expect(adb.commands, isEmpty);
        expect(adb.errors, hasLength(6));
        expect(adb.errors.first, contains('invalid package name'));
      },
    );
  });
}

class CapturingAdb extends AdbService {
  final List<List<String>> commands = [];
  final List<String> errors = [];
  String stdout = '';

  CapturingAdb() : super(onLog: (_, _) {}) {
    onLog = (message, type) {
      if (type == 'error') errors.add(message);
    };
  }

  @override
  bool get isMobile => false;

  @override
  Future<ProcessResult> runAdbCommand(
    List<String> args, {
    bool allowFailure = false,
    Duration? timeout,
    bool logOutput = true,
  }) async {
    commands.add(args);
    return ProcessResult(1, 0, stdout, '');
  }
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
