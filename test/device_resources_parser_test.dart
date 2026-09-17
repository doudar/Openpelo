import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/adb_service.dart';
import 'package:openpelo/services/device_resources_parser.dart';

void main() {
  test('reads Linux memory, highest hardware clock, and /data 1K blocks', () {
    const output = '''
__OPENPELO_MEMINFO__
MemTotal:        4096000 kB
MemFree:          100000 kB
MemAvailable:    1024000 kB
__OPENPELO_CPU_MAX_KHZ__
1800000
2200000
1800000
__OPENPELO_DF_K_DATA__
Filesystem     1K-blocks   Used Available Use% Mounted on
/dev/block/dm-3   1000000 400000    600000  40% /data
__OPENPELO_DF_DATA__
Filesystem     1K-blocks   Used Available Use% Mounted on
/dev/block/dm-3   1000000 400000    600000  40% /data
''';
    final resources = parseDeviceResources(output);
    expect(resources.ramTotalBytes, 4096000 * 1024);
    expect(resources.ramAvailableBytes, 1024000 * 1024);
    expect(resources.cpuMaxKhz, 2200000);
    expect(resources.storageTotalBytes, 1000000 * 1024);
    expect(resources.storageUsedBytes, 400000 * 1024);
    expect(resources.storageAvailableBytes, 600000 * 1024);
    expect(deviceResourcesProbeCommand, contains('cpuinfo_max_freq'));
    expect(deviceResourcesProbeCommand, isNot(contains('scaling_cur_freq')));
  });

  test('uses old toolbox df human units when df -k is unsupported', () {
    const output = '''
__OPENPELO_MEMINFO__
MemTotal: 2097152 kB
MemFree: 999999 kB
__OPENPELO_CPU_MAX_KHZ__
garbage
__OPENPELO_DF_K_DATA__
df: invalid option -- k
__OPENPELO_DF_DATA__
Filesystem               Size     Used     Free   Blksize
/dev/block/mmcblk0p25    5.0G     1.2G     3.8G   4096
''';
    final resources = parseDeviceResources(output);
    expect(resources.ramTotalBytes, 2097152 * 1024);
    expect(resources.ramAvailableBytes, isNull);
    expect(resources.cpuMaxKhz, isNull);
    expect(resources.storageTotalBytes, 5 * 1024 * 1024 * 1024);
    expect(resources.storageUsedBytes, 1.2 * 1024 * 1024 * 1024 ~/ 1);
    expect(resources.storageAvailableBytes, 3.8 * 1024 * 1024 * 1024 ~/ 1);
  });

  test('accepts a wrapped filesystem name and chooses the /data row', () {
    const output = '''
__OPENPELO_DF_K_DATA__
Filesystem               1K-blocks Used Available Use% Mounted on
/dev/block/long-name
                             10000 2500      7500  25% /data
other                       20000 1000     19000   5% /elsewhere
''';
    final resources = parseDeviceResources(output);
    expect(resources.storageTotalBytes, 10000 * 1024);
    expect(resources.storageUsedBytes, 2500 * 1024);
    expect(resources.storageAvailableBytes, 7500 * 1024);
  });

  test('rejects impossible values while keeping other valid readings', () {
    const output = '''
__OPENPELO_MEMINFO__
MemTotal: 1000000 kB
MemAvailable: 2000000 kB
__OPENPELO_CPU_MAX_KHZ__
0
999999999999
1700000
__OPENPELO_DF_K_DATA__
Filesystem 1K-blocks Used Available Use% Mounted on
/dev/block/dm-1 1000 900 900 90% /data
''';
    final resources = parseDeviceResources(output);
    expect(resources.ramTotalBytes, 1000000 * 1024);
    expect(resources.ramAvailableBytes, isNull);
    expect(resources.cpuMaxKhz, 1700000);
    expect(resources.storageTotalBytes, isNull);
    expect(resources.storageUsedBytes, isNull);
    expect(resources.storageAvailableBytes, isNull);
  });

  test(
    'uses a bounded, quiet desktop shell probe and tolerates failure',
    () async {
      final adb = ResourceAdb('''
__OPENPELO_MEMINFO__
MemTotal: 1024000 kB
''');
      final resources = await adb.getDeviceResources('usb123');
      expect(resources.ramTotalBytes, 1024000 * 1024);
      expect(adb.args, ['-s', 'usb123', 'shell', deviceResourcesProbeCommand]);
      expect(adb.timeout, const Duration(seconds: 8));
      expect(adb.logOutput, isFalse);
      expect(adb.allowFailure, isTrue);

      adb.fail = true;
      final unavailable = await adb.getDeviceResources('usb123');
      expect(unavailable.ramTotalBytes, isNull);
      expect(unavailable.storageTotalBytes, isNull);
    },
  );
}

class ResourceAdb extends AdbService {
  final String output;
  List<String>? args;
  Duration? timeout;
  bool? logOutput;
  bool? allowFailure;
  bool fail = false;

  ResourceAdb(this.output) : super(onLog: (_, _) {});

  @override
  bool get isMobile => false;

  @override
  Future<ProcessResult> runAdbCommand(
    List<String> args, {
    bool allowFailure = false,
    Duration? timeout,
    bool logOutput = true,
  }) async {
    this.args = args;
    this.timeout = timeout;
    this.logOutput = logOutput;
    this.allowFailure = allowFailure;
    if (fail) throw const ProcessException('adb', []);
    return ProcessResult(1, 0, output, '');
  }
}
