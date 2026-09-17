import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/models/app_model.dart';
import 'package:openpelo/models/device_model.dart';
import 'package:openpelo/models/device_resources.dart';
import 'package:openpelo/providers/app_provider.dart';
import 'package:openpelo/services/adb_service.dart';

class PendingResourcesAdb extends AdbService {
  final requests = <(String, Completer<DeviceResources>)>[];
  PendingResourcesAdb() : super(onLog: (_, _) {});

  @override
  Future<DeviceResources> getDeviceResources(String serial) {
    final result = Completer<DeviceResources>();
    requests.add((serial, result));
    return result.future;
  }
}

DeviceModel device(String serial) =>
    DeviceModel(serial: serial, status: 'device', transport: 'usb');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'switch clears readings and ignores the previous device response',
    () async {
      final adb = PendingResourcesAdb();
      final provider = AppProvider(adbService: adb);
      addTearDown(provider.dispose);
      provider.selectDevice(device('first'));
      adb.requests[0].$2.complete(const DeviceResources(ramTotalBytes: 100));
      await Future<void>.delayed(Duration.zero);
      expect(provider.selectedDeviceResources.ramTotalBytes, 100);
      final oldRefresh = provider.refreshDeviceResources(force: true);
      provider.selectDevice(device('second'));
      expect(provider.selectedDeviceResources.ramTotalBytes, isNull);
      adb.requests[2].$2.complete(const DeviceResources(ramTotalBytes: 200));
      await Future<void>.delayed(Duration.zero);
      adb.requests[1].$2.complete(const DeviceResources(ramTotalBytes: 150));
      await oldRefresh;
      expect(provider.selectedDeviceResources.ramTotalBytes, 200);
      expect(provider.isRefreshingDeviceResources, isFalse);
    },
  );

  test(
    'disconnect and disposal invalidate pending resource readings',
    () async {
      final adb = PendingResourcesAdb();
      final provider = AppProvider(adbService: adb);
      provider.selectedDevice = device('first');
      final pending = provider.refreshDeviceResources();
      provider.selectedDevice = null;
      await provider.refreshDeviceResources();
      adb.requests[0].$2.complete(const DeviceResources(ramTotalBytes: 100));
      await pending;
      expect(provider.selectedDeviceResources.ramTotalBytes, isNull);
      expect(provider.isRefreshingDeviceResources, isFalse);
      provider.selectedDevice = device('second');
      final last = provider.refreshDeviceResources();
      provider.dispose();
      adb.requests[1].$2.complete(const DeviceResources(ramTotalBytes: 200));
      await last;
      expect(provider.selectedDeviceResources.ramTotalBytes, isNull);
    },
  );

  test(
    'polling coalesces and throttles while manual refresh preserves apps',
    () async {
      final adb = PendingResourcesAdb();
      final provider = AppProvider(adbService: adb);
      addTearDown(provider.dispose);
      provider.selectedDevice = device('first');
      final app = AppModel(
        name: 'App',
        description: '',
        url: 'https://example.org/a.apk',
      );
      app.isSelected = true;
      provider.availableApps = {'App': app};
      final initial = provider.refreshDeviceResources();
      await provider.refreshDeviceResources(force: true);
      expect(adb.requests, hasLength(1));
      adb.requests[0].$2.complete(
        const DeviceResources(ramAvailableBytes: 100),
      );
      await initial;
      await provider.refreshDeviceResources();
      expect(adb.requests, hasLength(1));
      final manual = provider.refreshDeviceResources(force: true);
      expect(adb.requests, hasLength(2));
      adb.requests[1].$2.complete(
        const DeviceResources(ramAvailableBytes: 200),
      );
      await manual;
      expect(provider.selectedDeviceResources.ramAvailableBytes, 200);
      expect(provider.availableApps['App'], same(app));
      expect(app.isSelected, isTrue);
    },
  );
}
